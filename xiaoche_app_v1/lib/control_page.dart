import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'connection_model.dart';
import 'settings_model.dart';

class MotionCmd {
  const MotionCmd({required this.cmd, required this.speed});

  final String cmd;
  final int speed;

  Map<String, dynamic> toJson() => {'cmd': cmd, 'speed': speed};
}

int percentToU16(double percent) {
  final p = percent.clamp(0, 100);
  return (p * 65535 / 100).round();
}

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  static const _throttleMs = 80;

  String _currentCommand = 'stop';
  DateTime? _lastSendAt;
  double? _draftPercent;

  @override
  void dispose() {
    final model = context.read<ConnectionModel>();
    // 仅在「手动模式」退出页面时才补发 stop，避免 AUTO/EMG 模式触发手动接管。
    if (model.connected && model.controlMode == CarControlMode.manual) {
      unawaited(_sendMotionCommand('stop', forceStop: true));
    }
    super.dispose();
  }

  Future<void> _onSpeedChanged(double percent) async {
    setState(() => _draftPercent = percent);
    await context.read<SettingsModel>().setManualSpeedPercent(percent);
  }

  bool _canSendNow() {
    final now = DateTime.now();
    final last = _lastSendAt;
    if (last != null && now.difference(last).inMilliseconds < _throttleMs) {
      return false;
    }
    _lastSendAt = now;
    return true;
  }

  Future<void> _sendMotionCommand(String cmd, {bool forceStop = false}) async {
    final model = context.read<ConnectionModel>();
    final settings = context.read<SettingsModel>();

    if (!model.connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未连接，无法发送控制指令')),
      );
      return;
    }

    final speed = forceStop ? 0 : percentToU16(_draftPercent ?? settings.manualSpeedPercent);
    final payloadCmd = MotionCmd(cmd: cmd, speed: cmd == 'stop' ? 0 : speed);

    final wireText = settings.manualUseTextProtocol
        ? '${payloadCmd.cmd} ${payloadCmd.speed}'
        : jsonEncode(payloadCmd.toJson());

    try {
      await model.send(wireText);
      if (!mounted) return;
      setState(() {
        _currentCommand = payloadCmd.cmd;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败，请检查连接状态')),
      );
    }
  }

  Future<void> _handleCommandTap(String cmd) async {
    if (!_canSendNow()) return;
    if (cmd == 'stop') {
      HapticFeedback.mediumImpact();
      await _sendMotionCommand('stop', forceStop: true);
      return;
    }

    HapticFeedback.lightImpact();
    await _sendMotionCommand(cmd);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final conn = context.watch<ConnectionModel>();
    final settings = context.watch<SettingsModel>();

    final speedPercent = _draftPercent ?? settings.manualSpeedPercent;
    final speedU16 = percentToU16(speedPercent);
    final isConnected = conn.connected;

    return Scaffold(
      appBar: AppBar(
        title: const Text('按钮控制'),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primary.withValues(alpha: 0.1),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _currentCommand.toUpperCase(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        isConnected ? Icons.wifi : Icons.wifi_off,
                        size: 16,
                        color: isConnected ? Colors.green : scheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConnected ? '已连接' : '未连接',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isConnected ? Colors.green : scheme.error,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed_rounded),
                              const SizedBox(width: 8),
                              Text(
                                '速度：${speedPercent.round()}%（$speedU16）',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          Slider(
                            value: speedPercent,
                            min: 0,
                            max: 100,
                            divisions: 100,
                            label: '${speedPercent.round()}%',
                            onChanged: (value) => _onSpeedChanged(value),
                          ),
                          const SizedBox(height: 6),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('文本协议兼容模式'),
                            subtitle: const Text('开启后发送格式：forward 28000'),
                            value: settings.manualUseTextProtocol,
                            onChanged: (value) =>
                                context.read<SettingsModel>().setManualUseTextProtocol(value),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      children: [
                        Align(
                          alignment: Alignment.topCenter,
                          child: _ControlButton(
                            command: 'forward',
                            icon: Icons.keyboard_arrow_up_rounded,
                            enabled: isConnected,
                            onTap: _handleCommandTap,
                          ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _ControlButton(
                            command: 'backward',
                            icon: Icons.keyboard_arrow_down_rounded,
                            enabled: isConnected,
                            onTap: _handleCommandTap,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _ControlButton(
                            command: 'left',
                            icon: Icons.keyboard_arrow_left_rounded,
                            enabled: isConnected,
                            onTap: _handleCommandTap,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _ControlButton(
                            command: 'right',
                            icon: Icons.keyboard_arrow_right_rounded,
                            enabled: isConnected,
                            onTap: _handleCommandTap,
                          ),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: _ControlButton(
                            command: 'stop',
                            icon: Icons.stop_rounded,
                            enabled: isConnected,
                            onTap: _handleCommandTap,
                            isStop: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatefulWidget {
  const _ControlButton({
    required this.command,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.isStop = false,
  });

  final String command;
  final IconData icon;
  final bool enabled;
  final ValueChanged<String> onTap;
  final bool isStop;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final btnColor = widget.isStop ? scheme.error : scheme.primary;

    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) {
              setState(() => _isPressed = true);
            }
          : null,
      onTapCancel: () {
        if (!_isPressed) return;
        setState(() => _isPressed = false);
      },
      onTapUp: widget.enabled
          ? (_) {
              setState(() => _isPressed = false);
              widget.onTap(widget.command);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: _isPressed ? 72 : 64,
        height: _isPressed ? 72 : 64,
        decoration: BoxDecoration(
          color: widget.enabled
              ? (_isPressed ? btnColor : scheme.surfaceVariant)
              : scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.enabled
                  ? btnColor.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: _isPressed ? 12 : 7,
              spreadRadius: _isPressed ? 3 : 1,
            ),
          ],
        ),
        child: Icon(
          widget.icon,
          color: widget.enabled
              ? (_isPressed ? scheme.onPrimary : scheme.onSurfaceVariant)
              : scheme.onSurface.withValues(alpha: 0.4),
          size: 36,
        ),
      ),
    );
  }
}
