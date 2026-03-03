import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'connection_model.dart';

class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  Timer? _sendTimer;
  String _currentCommand = 'stop';

  @override
  void dispose() {
    _sendTimer?.cancel();
    // Ensure we send a 'stop' command when leaving the page
    final model = context.read<ConnectionModel>();
    if (model.connected) {
      model.send('stop');
    }
    super.dispose();
  }

  void _startSending(String command) {
    // If the command is already being sent, do nothing.
    if (_currentCommand == command && _sendTimer != null && _sendTimer!.isActive) return;

    HapticFeedback.lightImpact();
    setState(() {
      _currentCommand = command;
    });

    // Cancel any existing timer and start a new one.
    _sendTimer?.cancel();
    _sendCommand(command); // Send immediately
    _sendTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      _sendCommand(command); // Periodically send the new command
    });
  }

  void _stopSending() {
    HapticFeedback.mediumImpact();
    setState(() {
      _currentCommand = 'stop';
    });
    _sendTimer?.cancel();
    _sendCommand('stop');
  }

  void _sendCommand(String command) {
    if (context.read<ConnectionModel>().connected) {
      context.read<ConnectionModel>().send(command);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

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
              scheme.primary.withOpacity(0.1),
              scheme.surface,
            ],
          ),
        ),
        child: Center(
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
              const SizedBox(height: 60),
              SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: _ControlButton(
                        command: 'forward',
                        icon: Icons.keyboard_arrow_up_rounded,
                        onStart: _startSending,
                        onEnd: _stopSending,
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: _ControlButton(
                        command: 'backward',
                        icon: Icons.keyboard_arrow_down_rounded,
                        onStart: _startSending,
                        onEnd: _stopSending,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ControlButton(
                        command: 'left',
                        icon: Icons.keyboard_arrow_left_rounded,
                        onStart: _startSending,
                        onEnd: _stopSending,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _ControlButton(
                        command: 'right',
                        icon: Icons.keyboard_arrow_right_rounded,
                        onStart: _startSending,
                        onEnd: _stopSending,
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
    required this.onStart,
    required this.onEnd,
  });

  final String command;
  final IconData icon;
  final ValueChanged<String> onStart;
  final VoidCallback onEnd;

  @override
  State<_ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<_ControlButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: (_) {
        setState(() => _isPressed = true);
        widget.onStart(widget.command);
      },
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onEnd();
      },
      onTapCancel: () {
        setState(() => _isPressed = false);
        widget.onEnd();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: _isPressed ? 72 : 64,
        height: _isPressed ? 72 : 64,
        decoration: BoxDecoration(
          color: _isPressed ? scheme.primary : scheme.surfaceVariant,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withOpacity(0.3),
              blurRadius: _isPressed ? 15 : 8,
              spreadRadius: _isPressed ? 4 : 2,
            ),
          ],
        ),
        child: Icon(
          widget.icon,
          color: _isPressed ? scheme.onPrimary : scheme.onSurfaceVariant,
          size: 40,
        ),
      ),
    );
  }
}
