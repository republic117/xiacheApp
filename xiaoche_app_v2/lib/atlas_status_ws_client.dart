import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum AtlasStatusConnState {
  connecting,
  connected,
  disconnected,
}

class AtlasTelemetry {
  const AtlasTelemetry({
    required this.decisionState,
    required this.obstacleSide,
    required this.confidence,
    required this.fps,
    required this.latencyMs,
    required this.currentCmd,
    required this.cmdSource,
    required this.llmApplied,
    required this.detCount,
    required this.tsMs,
  });

  final String decisionState;
  final String obstacleSide;
  final double confidence;
  final double fps;
  final double latencyMs;
  final String currentCmd;
  final String cmdSource;
  final String llmApplied;
  final int detCount;
  final int tsMs;

  factory AtlasTelemetry.defaults() {
    return const AtlasTelemetry(
      decisionState: 'stop',
      obstacleSide: 'none',
      confidence: 0,
      fps: 0,
      latencyMs: 0,
      currentCmd: 'stop',
      cmdSource: 'watchdog',
      llmApplied: '',
      detCount: 0,
      tsMs: 0,
    );
  }

  factory AtlasTelemetry.fromJsonMap(Map<String, dynamic> map) {
    double asDouble(dynamic v, {double fallback = 0}) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    int asInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    String asString(dynamic v, {required String fallback}) {
      if (v == null) return fallback;
      final s = v.toString().trim();
      return s.isEmpty ? fallback : s;
    }

    return AtlasTelemetry(
      decisionState: asString(map['decision_state'], fallback: 'stop'),
      obstacleSide: asString(map['obstacle_side'], fallback: 'none'),
      confidence: asDouble(map['confidence']),
      fps: asDouble(map['fps']),
      latencyMs: asDouble(map['latency_ms']),
      currentCmd: asString(map['current_cmd'], fallback: 'stop'),
      cmdSource: asString(map['cmd_source'], fallback: 'watchdog'),
      llmApplied: asString(map['llm_applied'], fallback: ''),
      detCount: asInt(map['det_count']),
      tsMs: asInt(map['ts_ms']),
    );
  }
}

class AtlasStatusWsClient {
  final StreamController<AtlasTelemetry> _telemetryCtrl =
      StreamController<AtlasTelemetry>.broadcast();
  final StreamController<AtlasStatusConnState> _stateCtrl =
      StreamController<AtlasStatusConnState>.broadcast();

  WebSocket? _ws;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;

  String? _url;
  int _reconnectAttempt = 0;
  bool _manualClosed = false;
  AtlasStatusConnState _connState = AtlasStatusConnState.disconnected;

  Stream<AtlasTelemetry> get telemetryStream => _telemetryCtrl.stream;
  Stream<AtlasStatusConnState> get stateStream => _stateCtrl.stream;

  AtlasStatusConnState get connectionState => _connState;

  void start(String url) {
    final needRestart = _url != url;
    _url = url;
    _manualClosed = false;

    if (!needRestart &&
        (_connState == AtlasStatusConnState.connected ||
            _connState == AtlasStatusConnState.connecting)) {
      return;
    }

    _reconnectTimer?.cancel();
    unawaited(_connect());
  }

  Future<void> close() async {
    _manualClosed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.close();
    _ws = null;
    _emitState(AtlasStatusConnState.disconnected);
  }

  Future<void> dispose() async {
    await close();
    await _telemetryCtrl.close();
    await _stateCtrl.close();
  }

  Future<void> _connect() async {
    final url = _url;
    if (_manualClosed || url == null || url.isEmpty) return;

    _emitState(AtlasStatusConnState.connecting);

    try {
      final ws = await WebSocket.connect(url);
      if (_manualClosed) {
        await ws.close();
        return;
      }

      _ws = ws;
      _reconnectAttempt = 0;
      _emitState(AtlasStatusConnState.connected);

      _wsSub = ws.listen(
        _onMessage,
        onError: (Object error, StackTrace stack) {
          debugPrint('[AtlasStatusWs] socket error: $error');
          _handleDisconnected();
        },
        onDone: () {
          debugPrint('[AtlasStatusWs] socket closed');
          _handleDisconnected();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[AtlasStatusWs] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) {
      debugPrint('[AtlasStatusWs] ignore non-string message: $raw');
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('[AtlasStatusWs] ignore invalid json map: $raw');
        return;
      }
      final telemetry = AtlasTelemetry.fromJsonMap(decoded);
      _telemetryCtrl.add(telemetry);
    } catch (e) {
      debugPrint('[AtlasStatusWs] ignore invalid json message: $raw, error=$e');
    }
  }

  void _handleDisconnected() {
    if (_manualClosed) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _emitState(AtlasStatusConnState.disconnected);
    _reconnectTimer?.cancel();

    _reconnectAttempt += 1;
    final delaySec = _backoffSec(_reconnectAttempt);
    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (_manualClosed) return;
      unawaited(_connect());
    });
  }

  int _backoffSec(int attempt) {
    return (1 << (attempt - 1)).clamp(1, 5);
  }

  void _emitState(AtlasStatusConnState next) {
    if (_connState == next) return;
    _connState = next;
    _stateCtrl.add(next);
  }
}
