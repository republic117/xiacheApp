import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'connection_model.dart';
import 'settings_model.dart';
import 'speech_service.dart';

class CommandPage extends StatefulWidget {
  const CommandPage({super.key});

  @override
  State<CommandPage> createState() => _CommandPageState();
}

class _CommandPageState extends State<CommandPage> {
  final TextEditingController _controller = TextEditingController();
  final SpeechService _speech = SpeechService();

  static const Set<String> _motionCmds = <String>{
    'forward',
    'backward',
    'left',
    'right',
    'stop',
  };

  bool _speechReady = false;
  final Map<String, int> _lastSentSpeedByCmd = <String, int>{};

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final ok = await _speech.initialize();
    if (!mounted) return;
    setState(() => _speechReady = ok);
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stopListening();
    super.dispose();
  }

  void _showSpeechErrorHint(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _toggleListening(ConnectionModel model) async {
    if (!_speechReady) {
      _showSpeechErrorHint('语音不可用，请检查麦克风权限/系统语音服务。');
      return;
    }

    if (!model.connected) {
      _showSpeechErrorHint('请先连接小车再使用语音输入。');
      return;
    }

    if (_speech.isListening) {
      await _speech.stopListening();
      if (!mounted) return;
      setState(() {});
    } else {
      await _speech.startListening((text) {
        if (!mounted) return;

        if (text.startsWith('ERR:')) {
          final reason = text.substring(4);
          String hint = '语音识别失败：$reason';
          if (reason.contains('网络')) {
            hint = '语音识别失败：网络错误（模拟器常见）。建议用真机测试，或安装/启用 Google 语音服务后再试。';
          } else if (reason.contains('权限')) {
            hint = '语音识别失败：麦克风权限不足。请到系统设置为本 App 打开麦克风权限。';
          }

          _showSpeechErrorHint(hint);
          return;
        }

        setState(() {
          _controller.text = text;
        });
      });
      if (!mounted) return;
      setState(() {});
    }
  }

  int _percentToU16(double percent) {
    final p = percent.clamp(0, 100);
    return (p * 65535 / 100).round();
  }

  String _normalizeOutgoingCommand(String raw, SettingsModel settings) {
    final input = raw.trim();
    if (input.isEmpty) return input;

    final parts = input.split(RegExp(r'\s+'));
    final cmd = parts.first.toLowerCase();

    if (!_motionCmds.contains(cmd)) {
      return input;
    }

    if (cmd == 'stop') {
      _lastSentSpeedByCmd['stop'] = 0;
      return 'stop 0';
    }

    int speed;
    if (parts.length >= 2) {
      speed = int.tryParse(parts[1]) ?? _percentToU16(settings.manualSpeedPercent);
    } else {
      speed = _percentToU16(settings.manualSpeedPercent);
    }
    speed = speed.clamp(0, 65535);
    _lastSentSpeedByCmd[cmd] = speed;

    return '$cmd $speed';
  }

  String _displayLogText(LogEntry entry) {
    final text = entry.text.trim();
    if (text.isEmpty) return entry.text;

    final upper = text.toUpperCase();
    if (!upper.startsWith('OK')) return entry.text;

    final parts = text.split(RegExp(r'\s+'));
    if (parts.length < 2) return entry.text;

    final cmd = parts[1].toLowerCase();
    if (!_motionCmds.contains(cmd) || cmd == 'stop') return entry.text;

    if (parts.length >= 3 && int.tryParse(parts[2]) != null) {
      return entry.text;
    }

    final speed = _lastSentSpeedByCmd[cmd] ?? 30000;
    return 'OK $cmd $speed';
  }

  Future<void> _send(BuildContext context) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    final settings = context.read<SettingsModel>();
    final normalized = _normalizeOutgoingCommand(text, settings);

    await context.read<ConnectionModel>().send(normalized);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ConnectionModel>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.secondary.withValues(alpha: 0.12),
              scheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: '返回',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '指令控制台',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            model.connected ? '已连接：${model.url}' : '未连接',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: model.connected
                            ? Colors.green.withValues(alpha: 0.14)
                            : scheme.error.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: model.connected
                              ? Colors.green.withValues(alpha: 0.40)
                              : scheme.error.withValues(alpha: 0.40),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: model.connected
                                  ? Colors.green
                                  : scheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            model.connected ? 'ONLINE' : 'OFFLINE',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: '虚拟手柄',
                      onPressed: model.connected
                          ? () {
                              Navigator.of(context).pushNamed('/control');
                            }
                          : null,
                      icon: const Icon(Icons.gamepad_outlined),
                    ),
                    IconButton(
                      tooltip: '清空日志',
                      onPressed: model.logs.isEmpty
                          ? null
                          : () => context.read<ConnectionModel>().clearLogs(),
                      icon: const Icon(Icons.delete_sweep_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: model.logs.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 42,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '暂无日志',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '连接后发送指令，这里会显示指令与小车回包。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(top: 10, bottom: 12),
                          reverse: true,
                          itemCount: model.logs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final entry = model.logs[index];
                            final isClient = entry.source == LogSource.client;
                            final isServer = entry.source == LogSource.server;

                            final alignment = isClient
                                ? Alignment.centerRight
                                : Alignment.centerLeft;

                            Color bg;
                            Color fg;
                            IconData icon;

                            if (isClient) {
                              bg = scheme.primaryContainer;
                              fg = scheme.onPrimaryContainer;
                              icon = Icons.north_east_rounded;
                            } else if (isServer) {
                              final t = entry.text.trimLeft();
                              final upper = t.toUpperCase();
                              if (upper.startsWith('OK')) {
                                bg = Colors.green.withValues(alpha: 0.16);
                                fg = Colors.green.shade800;
                                icon = Icons.check_circle_outline_rounded;
                              } else if (upper.startsWith('ERR')) {
                                bg = scheme.errorContainer;
                                fg = scheme.onErrorContainer;
                                icon = Icons.error_outline_rounded;
                              } else {
                                bg = scheme.secondaryContainer;
                                fg = scheme.onSecondaryContainer;
                                icon = Icons.south_west_rounded;
                              }
                            } else {
                              bg = scheme.surfaceContainerHighest;
                              fg = scheme.onSurface;
                              icon = Icons.info_outline_rounded;
                            }

                            return Align(
                              alignment: alignment,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: bg,
                                    borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(16),
                                      topRight: const Radius.circular(16),
                                      bottomLeft:
                                          Radius.circular(isClient ? 16 : 6),
                                      bottomRight:
                                          Radius.circular(isClient ? 6 : 16),
                                    ),
                                    border: Border.all(
                                      color: scheme.outlineVariant,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 10, 12, 10),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(icon, size: 16, color: fg),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _displayLogText(entry),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: fg,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  10,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        TextField(
                          controller: _controller,
                          minLines: 2,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            labelText: '输入指令',
                            hintText: '例如：forward / left / stop',
                            prefixIcon: Icon(Icons.terminal_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _controller.text.isEmpty
                                    ? null
                                    : () => _controller.clear(),
                                icon: const Icon(Icons.clear_rounded),
                                label: const Text('清空输入'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: model.connected
                                    ? () => _send(context)
                                    : null,
                                icon: const Icon(Icons.send_rounded),
                                label: const Text('发送'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              onPressed: (_speechReady)
                                  ? () => _toggleListening(model)
                                  : null,
                              icon: Icon(
                                _speech.isListening
                                    ? Icons.stop_rounded
                                    : Icons.mic_rounded,
                              ),
                              tooltip: _speech.isListening ? '停止语音' : '语音输入',
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _QuickChip(
                                label: 'stop',
                                onTap: model.connected
                                    ? () async {
                                        _controller.text = 'stop';
                                        await _send(context);
                                      }
                                    : null,
                              ),
                              _QuickChip(
                                label: 'forward',
                                onTap: model.connected
                                    ? () {
                                        _controller.text = 'forward';
                                      }
                                    : null,
                              ),
                              _QuickChip(
                                label: 'backward',
                                onTap: model.connected
                                    ? () {
                                        _controller.text = 'backward';
                                      }
                                    : null,
                              ),
                              _QuickChip(
                                label: 'left',
                                onTap: model.connected
                                    ? () {
                                        _controller.text = 'left';
                                      }
                                    : null,
                              ),
                              _QuickChip(
                                label: 'right',
                                onTap: model.connected
                                    ? () {
                                        _controller.text = 'right';
                                      }
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        label: Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        onPressed: onTap,
        backgroundColor: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}
