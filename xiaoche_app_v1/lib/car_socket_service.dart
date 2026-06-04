import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

class CarSocketService {
  WebSocketChannel? _channel;
  StreamSubscription? _sub;

  final StreamController<String> _outputController =
      StreamController<String>.broadcast();
  final StreamController<Object> _errorController =
      StreamController<Object>.broadcast();
  final StreamController<void> _closedController =
      StreamController<void>.broadcast();

  Completer<void>? _connectGate;

  Stream<String> get output => _outputController.stream;
  Stream<Object> get errors => _errorController.stream;
  Stream<void> get closed => _closedController.stream;

  bool get isConnected => _channel != null;
  bool get isConnecting => _connectGate != null && !(_connectGate?.isCompleted ?? true);

  Future<void> connect(String url) async {
    await close();

    final uri = Uri.parse(url);

    // 发起连接：真正的成功/失败要靠 stream 事件判断。
    _channel = WebSocketChannel.connect(uri);

    final channel = _channel!;
    _sub = channel.stream.listen(
      (event) {
        _outputController.add(event?.toString() ?? '');
      },
      onError: (e, _) {
        _errorController.add(e);
      },
      onDone: () {
        _closedController.add(null);
      },
      cancelOnError: false,
    );

    final gate = Completer<void>();
    _connectGate = gate;

    late final StreamSubscription msgSub;
    late final StreamSubscription errSub;
    late final StreamSubscription closeSub;

    void finish([Object? error]) {
      if (gate.isCompleted) return;
      msgSub.cancel();
      errSub.cancel();
      closeSub.cancel();

      if (error != null) {
        gate.completeError(error);
      } else {
        gate.complete();
      }
    }

    msgSub = output.listen((_) => finish());
    errSub = errors.listen((e) => finish(e));
    closeSub = closed.listen((_) => finish(StateError('连接已关闭')));

    try {
      await gate.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw TimeoutException('连接超时'),
      );
    } finally {
      if (identical(_connectGate, gate)) {
        _connectGate = null;
      }
    }
  }

  void send(String cmd) {
    _channel?.sink.add(cmd);
  }

  Future<void> close() async {
    // 如果正在等待 connect() 的 gate，先让它失败返回，避免 UI 一直“连接中”
    final gate = _connectGate;
    if (gate != null && !gate.isCompleted) {
      gate.completeError(StateError('连接已取消'));
    }
    _connectGate = null;

    await _sub?.cancel();
    _sub = null;

    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await close();
    await _outputController.close();
    await _errorController.close();
    await _closedController.close();
  }
}
