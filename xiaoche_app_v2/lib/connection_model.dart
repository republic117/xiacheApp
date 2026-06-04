import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'car_socket_service.dart';
import 'settings_model.dart';

enum LogSource {
  client,
  server,
  system,
}

enum CarControlMode {
  manual,
  auto,
  emg,
  unknown,
}

class LogEntry {
  LogEntry({required this.source, required this.text, DateTime? time})
      : time = time ?? DateTime.now();

  final LogSource source;
  final String text;
  final DateTime time;
}

class ConnectionModel extends ChangeNotifier {
  void applySettings(SettingsModel settings) {
    autoReconnectEnabled = settings.autoReconnectEnabled;
    reconnectMaxAttempts = settings.reconnectAttempts;
    reconnectIntervalSeconds = settings.reconnectInterval;
    notifyListeners();
  }

  static const _prefsKeyLastUrl = 'last_ws_url';

  bool connected = false;
  bool connecting = false;

  String url = '';
  String? lastError;

  final List<String> history = <String>[];
  final List<LogEntry> logs = <LogEntry>[];

  CarControlMode controlMode = CarControlMode.unknown;

  final CarSocketService _service = CarSocketService();

  CarSocketService get service => _service;

  // Auto-reconnect
  bool autoReconnectEnabled = true;
  bool reconnecting = false;
  int reconnectMaxAttempts = 5;
  int reconnectAttemptsLeft = 0;
  int reconnectCountdownSeconds = 0;
  int reconnectIntervalSeconds = 3;

  Timer? _reconnectTimer;

  StreamSubscription? _outputSub;
  StreamSubscription? _errorSub;
  StreamSubscription? _closedSub;

  void _pushLog(LogEntry entry) {
    logs.insert(0, entry);
    const maxItems = 300;
    if (logs.length > maxItems) {
      logs.removeRange(maxItems, logs.length);
    }
  }

  CarControlMode? _parseModeFromMessage(String raw) {
    final msg = raw.trim().toUpperCase();

    final modeReg = RegExp(r'\bMODE\s*[:=]?\s*(MANUAL|AUTO|EMG)\b');
    final modeMatch = modeReg.firstMatch(msg);
    final token = modeMatch?.group(1);

    if (token == null) return null;

    switch (token) {
      case 'MANUAL':
        return CarControlMode.manual;
      case 'AUTO':
        return CarControlMode.auto;
      case 'EMG':
        return CarControlMode.emg;
      default:
        return null;
    }
  }

  void _syncModeFromServerMessage(String raw) {
    final parsed = _parseModeFromMessage(raw);
    if (parsed == null || parsed == controlMode) return;
    controlMode = parsed;
  }

  void setControlMode(CarControlMode mode, {bool notify = true}) {
    if (controlMode == mode) return;
    controlMode = mode;
    if (notify) notifyListeners();
  }

  ConnectionModel() {
    _loadPrefs();

    _outputSub = _service.output.listen((msg) {
      _pushLog(LogEntry(source: LogSource.server, text: msg));
      _syncModeFromServerMessage(msg);
      notifyListeners();
    });

    _errorSub = _service.errors.listen((e) {
      connected = false;
      connecting = false;
      lastError = e.toString();
      _pushLog(LogEntry(source: LogSource.system, text: 'ERROR: ${e.toString()}'));
      _maybeStartAutoReconnect(reason: '发生错误');
      notifyListeners();
    });

    _closedSub = _service.closed.listen((_) {
      connected = false;
      connecting = false;
      _pushLog(LogEntry(source: LogSource.system, text: '连接已关闭'));
      _maybeStartAutoReconnect(reason: '连接断开');
      notifyListeners();
    });
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      url = prefs.getString(_prefsKeyLastUrl) ?? '';
      notifyListeners();
    } catch (e) {
      debugPrint('[ConnectionModel] 加载最近 URL 失败: $e');
    }
  }

  Future<void> _savePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyLastUrl, url);
    } catch (e) {
      debugPrint('[ConnectionModel] 保存最近 URL 失败: $e');
    }
  }

  void _maybeStartAutoReconnect({required String reason}) {
    if (!autoReconnectEnabled) return;
    if (url.trim().isEmpty) return;
    if (connecting) return;
    if (reconnecting) return;

    reconnectAttemptsLeft = reconnectMaxAttempts;
    reconnecting = true;
    _pushLog(LogEntry(source: LogSource.system, text: '$reason，准备自动重连'));
    _scheduleReconnectTick();
  }

  void cancelAutoReconnect() {
    reconnecting = false;
    reconnectAttemptsLeft = 0;
    reconnectCountdownSeconds = 0;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    notifyListeners();
  }

  void _scheduleReconnectTick() {
    _reconnectTimer?.cancel();

    reconnectCountdownSeconds = reconnectIntervalSeconds;
    notifyListeners();

    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!reconnecting) {
        t.cancel();
        return;
      }

      reconnectCountdownSeconds -= 1;
      notifyListeners();

      if (reconnectCountdownSeconds > 0) return;

      t.cancel();
      await _attemptReconnectOnce();
    });
  }

  Future<void> _attemptReconnectOnce() async {
    if (!reconnecting) return;

    if (reconnectAttemptsLeft <= 0) {
      reconnecting = false;
      _pushLog(LogEntry(source: LogSource.system, text: '自动重连已停止：超过最大次数'));
      notifyListeners();
      return;
    }

    reconnectAttemptsLeft -= 1;
    _pushLog(LogEntry(
      source: LogSource.system,
      text: '自动重连中...（剩余 $reconnectAttemptsLeft 次）',
    ));
    notifyListeners();

    final ok = await connect(url);
    if (ok) {
      reconnecting = false;
      reconnectCountdownSeconds = 0;
      _reconnectTimer?.cancel();
      _reconnectTimer = null;
      _pushLog(LogEntry(source: LogSource.system, text: '自动重连成功'));
      notifyListeners();
      return;
    }

    if (reconnectAttemptsLeft <= 0) {
      reconnecting = false;
      _pushLog(LogEntry(source: LogSource.system, text: '自动重连失败：次数用尽'));
      notifyListeners();
      return;
    }

    _scheduleReconnectTick();
  }

  Future<void> send(String cmd) async {
    _service.send(cmd);
    history.insert(0, cmd);
    _pushLog(LogEntry(source: LogSource.client, text: cmd));
    notifyListeners();
  }

  void addSystemLog(String text) {
    _pushLog(LogEntry(source: LogSource.system, text: text));
    notifyListeners();
  }

  Future<bool> connect(String url) async {
    this.url = url;
    lastError = null;
    connecting = true;
    cancelAutoReconnect();
    _pushLog(LogEntry(source: LogSource.system, text: '连接中：$url'));
    notifyListeners();

    try {
      await _service.connect(url);
      connected = true;
      connecting = false;
      _pushLog(LogEntry(source: LogSource.system, text: '连接成功'));
      await _savePrefs();
      notifyListeners();
      return true;
    } catch (e) {
      connected = false;
      connecting = false;
      lastError = e.toString();
      _pushLog(LogEntry(source: LogSource.system, text: '连接失败：${e.toString()}'));
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    cancelAutoReconnect();
    await _service.close();
    connected = false;
    connecting = false;
    _pushLog(LogEntry(source: LogSource.system, text: '已断开'));
    notifyListeners();
  }

  Future<void> cancelConnect() async {
    cancelAutoReconnect();
    await _service.close();
    connected = false;
    connecting = false;
    lastError = '已取消连接';
    _pushLog(LogEntry(source: LogSource.system, text: '已取消连接'));
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    cancelAutoReconnect();
    _outputSub?.cancel();
    _errorSub?.cancel();
    _closedSub?.cancel();
    _service.dispose();
    super.dispose();
  }
}
