import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsModel extends ChangeNotifier {
  // Keys for SharedPreferences
  static const _keyAutoReconnect = 'settings_auto_reconnect_enabled';
  static const _keyReconnectAttempts = 'settings_reconnect_attempts';
  static const _keyReconnectInterval = 'settings_reconnect_interval';
  static const _keyDefaultPort = 'settings_default_port';
  static const _keyThemeColor = 'settings_theme_color';
  static const _keyAtlasIp = 'settings_atlas_ip';
  static const _keyRtspPort = 'settings_rtsp_port';
  static const _keyStreamPathLive = 'settings_stream_path_live';
  static const _keyStreamPathYolo = 'settings_stream_path_yolo';
  static const _keyRtspUsername = 'settings_rtsp_username';
  static const _keyRtspPassword = 'settings_rtsp_password';
  static const _keyRtspTransport = 'settings_rtsp_transport';

  // Default values
  bool _autoReconnectEnabled = true;
  int _reconnectAttempts = 5;
  int _reconnectInterval = 3;
  int _defaultPort = 8080;
  Color _themeColor = const Color(0xFF2F6BFF);
  String _atlasIp = '192.168.137.2';
  int _rtspPort = 8554;
  String _streamPathLive = 'live';
  String _streamPathYolo = 'yolo';
  String _rtspUsername = '';
  String _rtspPassword = '';
  String _rtspTransport = 'tcp';

  bool _loading = true;

  // Getters
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  int get reconnectAttempts => _reconnectAttempts;
  int get reconnectInterval => _reconnectInterval;
  int get defaultPort => _defaultPort;
  Color get themeColor => _themeColor;
  String get atlasIp => _atlasIp;
  int get rtspPort => _rtspPort;
  String get streamPathLive => _streamPathLive;
  String get streamPathYolo => _streamPathYolo;
  String get rtspUsername => _rtspUsername;
  String get rtspPassword => _rtspPassword;
  String get rtspTransport => _rtspTransport;
  bool get rtspUseTcp => _rtspTransport.toLowerCase() != 'udp';
  bool get loading => _loading;

  SettingsModel() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _loading = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    _autoReconnectEnabled = prefs.getBool(_keyAutoReconnect) ?? true;
    _reconnectAttempts = prefs.getInt(_keyReconnectAttempts) ?? 5;
    _reconnectInterval = prefs.getInt(_keyReconnectInterval) ?? 3;
    _defaultPort = prefs.getInt(_keyDefaultPort) ?? 8080;
    _themeColor = Color(prefs.getInt(_keyThemeColor) ?? 0xFF2F6BFF);
    _atlasIp = prefs.getString(_keyAtlasIp) ?? '192.168.137.2';
    _rtspPort = prefs.getInt(_keyRtspPort) ?? 8554;
    _streamPathLive = prefs.getString(_keyStreamPathLive) ?? 'live';
    _streamPathYolo = prefs.getString(_keyStreamPathYolo) ?? 'yolo';
    _rtspUsername = prefs.getString(_keyRtspUsername) ?? '';
    _rtspPassword = prefs.getString(_keyRtspPassword) ?? '';
    _rtspTransport = prefs.getString(_keyRtspTransport) ?? 'tcp';
    _loading = false;
    notifyListeners();
  }

  // Setters
  Future<void> setAtlasIp(String value) async {
    _atlasIp = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAtlasIp, value);
  }

  Future<void> setRtspPort(int value) async {
    _rtspPort = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRtspPort, value);
  }

  Future<void> setStreamPathLive(String value) async {
    _streamPathLive = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStreamPathLive, value);
  }

  Future<void> setStreamPathYolo(String value) async {
    _streamPathYolo = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyStreamPathYolo, value);
  }

  Future<void> setRtspUsername(String value) async {
    _rtspUsername = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRtspUsername, value);
  }

  Future<void> setRtspPassword(String value) async {
    _rtspPassword = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRtspPassword, value);
  }

  Future<void> setRtspTransport(String value) async {
    final normalized = value.toLowerCase() == 'udp' ? 'udp' : 'tcp';
    _rtspTransport = normalized;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRtspTransport, normalized);
  }

  Future<void> setAutoReconnect(bool value) async {
    _autoReconnectEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoReconnect, value);
  }

  Future<void> setReconnectAttempts(int value) async {
    _reconnectAttempts = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReconnectAttempts, value);
  }

  Future<void> setReconnectInterval(int value) async {
    _reconnectInterval = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyReconnectInterval, value);
  }

  Future<void> setDefaultPort(int value) async {
    _defaultPort = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDefaultPort, value);
  }

  Future<void> setThemeColor(Color color) async {
    _themeColor = color;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeColor, color.value);
  }

  Future<void> clearHistoryAndCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_ws_url');
  }
}
