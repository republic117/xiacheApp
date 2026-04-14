import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum AtlasCommandConnState {
  connecting,
  connected,
  disconnected,
}

class AtlasDecision {
  const AtlasDecision({
    required this.valid,
    required this.cmd,
    required this.mode,
    required this.durationMs,
    required this.rejectReason,
  });

  final bool valid;
  final String cmd;
  final String mode;
  final int durationMs;
  final String rejectReason;

  factory AtlasDecision.defaults() {
    return const AtlasDecision(
      valid: false,
      cmd: '',
      mode: '',
      durationMs: 0,
      rejectReason: '',
    );
  }

  factory AtlasDecision.fromJsonMap(Map<String, dynamic> map) {
    bool asBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return fallback;
    }

    int asInt(dynamic v, {int fallback = 0}) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    String asString(dynamic v) {
      if (v == null) return '';
      return v.toString().trim();
    }

    return AtlasDecision(
      valid: asBool(map['valid']),
      cmd: asString(map['cmd']),
      mode: asString(map['mode']),
      durationMs: asInt(map['duration_ms']),
      rejectReason: asString(map['reject_reason']),
    );
  }
}

class AtlasCommandResponse {
  const AtlasCommandResponse({
    required this.ok,
    required this.decision,
    this.llmRaw,
    this.raw,
  });

  final bool ok;
  final AtlasDecision decision;
  final String? llmRaw;
  final String? raw;

  bool get accepted => ok && decision.valid;

  factory AtlasCommandResponse.fromRawString(String raw) {
    bool asBool(dynamic v, {bool fallback = false}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'no') return false;
      }
      return fallback;
    }

    String asString(dynamic v) {
      if (v == null) return '';
      return v.toString().trim();
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return AtlasCommandResponse(
          ok: false,
          decision: AtlasDecision.defaults(),
          raw: raw,
        );
      }

      final decisionMap = decoded['decision'];
      final decision = decisionMap is Map<String, dynamic>
          ? AtlasDecision.fromJsonMap(decisionMap)
          : AtlasDecision.defaults();

      final llmRawText = asString(decoded['llm_raw']);

      return AtlasCommandResponse(
        ok: asBool(decoded['ok']),
        decision: decision,
        llmRaw: llmRawText.isEmpty ? null : llmRawText,
        raw: raw,
      );
    } catch (e) {
      debugPrint('[AtlasCmdWs] parse error: $e, raw=$raw');
      return AtlasCommandResponse(
        ok: false,
        decision: AtlasDecision.defaults(),
        raw: raw,
      );
    }
  }
}

class AtlasCommandWsClient {
  final StreamController<AtlasCommandConnState> _stateCtrl =
      StreamController<AtlasCommandConnState>.broadcast();

  WebSocket? _ws;
  StreamSubscription? _wsSub;
  Timer? _reconnectTimer;

  String? _url;
  int _reconnectAttempt = 0;
  bool _manualClosed = false;
  AtlasCommandConnState _connState = AtlasCommandConnState.disconnected;

  final List<Completer<AtlasCommandResponse>> _pending = [];

  Stream<AtlasCommandConnState> get stateStream => _stateCtrl.stream;
  AtlasCommandConnState get connectionState => _connState;

  void start(String url) {
    final needRestart = _url != url;
    _url = url;
    _manualClosed = false;

    if (!needRestart &&
        (_connState == AtlasCommandConnState.connected ||
            _connState == AtlasCommandConnState.connecting)) {
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
    _emitState(AtlasCommandConnState.disconnected);
    _failPending('socket closed');
  }

  Future<void> dispose() async {
    await close();
    await _stateCtrl.close();
  }

  Future<AtlasCommandResponse> sendText(String text) async {
    final payload = text.trim();
    if (payload.isEmpty) {
      return AtlasCommandResponse(
        ok: false,
        decision: AtlasDecision.defaults(),
      );
    }

    if (_ws == null || _connState != AtlasCommandConnState.connected) {
      await _connect();
    }

    final ws = _ws;
    if (ws == null || _connState != AtlasCommandConnState.connected) {
      return AtlasCommandResponse(
        ok: false,
        decision: AtlasDecision.defaults(),
      );
    }

    final completer = Completer<AtlasCommandResponse>();
    _pending.add(completer);

    try {
      ws.add(jsonEncode({'text': payload}));
    } catch (e) {
      _pending.remove(completer);
      return AtlasCommandResponse(
        ok: false,
        decision: AtlasDecision.defaults(),
      );
    }

    try {
      return await completer.future.timeout(const Duration(seconds: 8));
    } catch (_) {
      _pending.remove(completer);
      return AtlasCommandResponse(
        ok: false,
        decision: AtlasDecision.defaults(),
      );
    }
  }

  Future<void> _connect() async {
    final url = _url;
    if (_manualClosed || url == null || url.isEmpty) return;

    if (_connState == AtlasCommandConnState.connecting) return;

    _emitState(AtlasCommandConnState.connecting);

    try {
      final ws = await WebSocket.connect(url);
      if (_manualClosed) {
        await ws.close();
        return;
      }

      _ws = ws;
      _reconnectAttempt = 0;
      _emitState(AtlasCommandConnState.connected);

      _wsSub = ws.listen(
        _onMessage,
        onError: (Object error, StackTrace stack) {
          debugPrint('[AtlasCmdWs] socket error: $error');
          _handleDisconnected();
        },
        onDone: () {
          debugPrint('[AtlasCmdWs] socket closed');
          _handleDisconnected();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[AtlasCmdWs] connect failed: $e');
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    final response = AtlasCommandResponse.fromRawString(raw);

    if (_pending.isNotEmpty) {
      final completer = _pending.removeAt(0);
      if (!completer.isCompleted) {
        completer.complete(response);
      }
    }
  }

  void _handleDisconnected() {
    _ws = null;
    if (_manualClosed) return;
    _scheduleReconnect();
    _failPending('socket disconnected');
  }

  void _scheduleReconnect() {
    _emitState(AtlasCommandConnState.disconnected);
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

  void _emitState(AtlasCommandConnState next) {
    if (_connState == next) return;
    _connState = next;
    _stateCtrl.add(next);
  }

  void _failPending(String reason) {
    while (_pending.isNotEmpty) {
      final c = _pending.removeAt(0);
      if (!c.isCompleted) {
        c.complete(AtlasCommandResponse(
          ok: false,
          decision: AtlasDecision.defaults(),
        ));
      }
    }
    debugPrint('[AtlasCmdWs] fail pending: $reason');
  }
}
