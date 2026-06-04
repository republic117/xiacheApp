import 'package:flutter/services.dart';

enum SpeechState { idle, listening, error }

class SpeechService {
  static const _channel = MethodChannel('com.example.xiaoche_app_v1/speech');

  SpeechState _state = SpeechState.idle;
  String _lastResult = '';

  SpeechState get state => _state;
  String get lastResult => _lastResult;
  bool get isListening => _state == SpeechState.listening;

  Future<bool> initialize() async {
    try {
      await _channel.invokeMethod('initialize');
      _state = SpeechState.idle;
      return true;
    } catch (e) {
      _state = SpeechState.error;
      return false;
    }
  }

  Future<void> startListening(void Function(String) onResult) async {
    if (_state != SpeechState.idle) return;
    _state = SpeechState.listening;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onSpeechResult') {
          final text = call.arguments['text'] as String?;
          if (text != null) {
            _lastResult = text;
            onResult(text);
          }
        }
      });
      await _channel.invokeMethod('startListening');
    } catch (e) {
      _state = SpeechState.error;
    }
  }

  Future<void> stopListening() async {
    if (_state != SpeechState.listening) return;
    try {
      await _channel.invokeMethod('stopListening');
      _state = SpeechState.idle;
    } catch (e) {
      _state = SpeechState.error;
    }
  }
}
