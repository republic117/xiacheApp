import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'connection_model.dart';
import 'settings_model.dart';


/// 首页：负责展示连接状态、连接入口以及进入控制台的入口。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// IP/地址输入框控制器。
  final TextEditingController _ipController = TextEditingController();


  @override
  void dispose() {
    // 释放输入控制器，避免内存泄漏。
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _sendModeCommand(BuildContext context, String cmd,
      {CarControlMode? mode, String? successText}) async {
    final model = context.read<ConnectionModel>();

    if (!model.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先连接小车后再切换模式'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await model.send(cmd);

    if (mode != null) {
      model.setControlMode(mode);
    }

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successText ?? '已发送：$cmd'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 触发连接：
  /// - 支持直接输入 `ws://` / `wss://`。
  /// - 若只输入 IP，则自动补全为 `ws://ip:8080`（默认端口 8080）。
  Future<void> _connect(BuildContext context) async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    final settings = context.read<SettingsModel>();

    final url = ip.startsWith('ws://') || ip.startsWith('wss://')
        ? ip
        : 'ws://$ip:${settings.defaultPort}';

    // 通过 Provider 调用连接逻辑。
    final ok = await context.read<ConnectionModel>().connect(url);

    // await 后先判断组件是否仍在树上，避免 setState / ScaffoldMessenger 报错。
    if (!context.mounted) return;

    // 连接失败时，用 SnackBar 给出明确反馈。
    if (!ok) {
      final msg = context.read<ConnectionModel>().lastError ?? '连接失败';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<ConnectionModel>();
    final scheme = Theme.of(context).colorScheme;

    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (model.connecting) {
      statusColor = scheme.primary;
      statusIcon = Icons.wifi_tethering_rounded;
      statusText = '连接中';
    } else if (model.connected) {
      statusColor = Colors.green;
      statusIcon = Icons.wifi_rounded;
      statusText = '已连接';
    } else {
      statusColor = scheme.error;
      statusIcon = Icons.wifi_off_rounded;
      statusText = '未连接';
    }

    return Scaffold(
      body: Stack(
        children: [
          // 全屏背景渐变：使用 Positioned.fill 确保覆盖整个 body。
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.18),
                    scheme.secondary.withValues(alpha: 0.12),
                    scheme.surface,
                  ],
                  stops: const [0.0, 0.35, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -120,
            right: -140,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.35),
                    scheme.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -160,
            left: -120,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    scheme.tertiary.withValues(alpha: 0.22),
                    scheme.tertiary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            // 使用 LayoutBuilder 获取可用高度，配合 ConstrainedBox 让内容区域至少占满整屏。
            // 这样在内容较少时，背景不会在底部“露白”。
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: ConstrainedBox(
                    // 关键：让滚动内容的最小高度等于视口高度（constraints.maxHeight）。
                    constraints: BoxConstraints(minHeight: constraints.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 顶部品牌与连接状态概览。
                        _HeaderCard(
                          title: 'Smart Car',
                          subtitle: '远程控制与指令调试',
                          statusColor: statusColor,
                          statusIcon: statusIcon,
                          statusText: statusText,
                          onSettingsTap: () =>
                              Navigator.of(context).pushNamed('/settings'),
                        ),
                        const SizedBox(height: 14),
                        // 连接输入区：输入地址并进行连接/断开操作。
                        _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.link_rounded,
                                        color: scheme.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      '连接小车',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _ipController,
                                  enabled: !model.connecting,
                                  decoration: InputDecoration(
                                    labelText: '设备地址（IP 或 ws://）',
                                    hintText:
                                        '例如 192.168.1.10 或 ws://192.168.1.10:8080',
                                    prefixIcon: const Icon(Icons.wifi_rounded),
                                  ),
                                  keyboardType: TextInputType.url,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) => _connect(context),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: FilledButton.icon(
                                          onPressed: model.connecting
                                              ? null
                                              : () => _connect(context),
                                          icon: model.connecting
                                              ? SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.4,
                                                    color: scheme.onPrimary,
                                                  ),
                                                )
                                              : const Icon(Icons.power_rounded),
                                          label: Text(
                                              model.connecting ? '正在连接' : '连接'),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    SizedBox(
                                      height: 48,
                                      child: OutlinedButton.icon(
                                        onPressed: model.connecting
                                            ? () async {
                                                await context
                                                    .read<ConnectionModel>()
                                                    .cancelConnect();
                                              }
                                            : (model.connected
                                                ? () async {
                                                    await context
                                                        .read<ConnectionModel>()
                                                        .disconnect();
                                                  }
                                                : null),
                                        icon: Icon(model.connecting
                                            ? Icons.cancel_outlined
                                            : Icons.link_off_rounded),
                                        label:
                                            Text(model.connecting ? '取消' : '断开'),
                                      ),
                                    ),
                                  ],
                                ),
                                if (model.lastError != null && !model.connected)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline_rounded,
                                            color: scheme.error, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            model.lastError!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelMedium
                                                ?.copyWith(color: scheme.error),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 模式切换卡片：手动/自动/急停
                        _GlassCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.tune_rounded,
                                        color: scheme.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      '控制模式',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontWeight: FontWeight.w800),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SegmentedButton<CarControlMode>(
                                        emptySelectionAllowed: true,
                                        segments: const [
                                          ButtonSegment<CarControlMode>(
                                            value: CarControlMode.manual,
                                            label: Text('手动'),
                                            icon: Icon(Icons.sports_esports_rounded),
                                          ),
                                          ButtonSegment<CarControlMode>(
                                            value: CarControlMode.auto,
                                            label: Text('自动'),
                                            icon: Icon(Icons.auto_awesome_rounded),
                                          ),
                                        ],
                                        selected: {
                                          if (model.controlMode == CarControlMode.manual)
                                            CarControlMode.manual
                                          else if (model.controlMode == CarControlMode.auto)
                                            CarControlMode.auto,
                                        },
                                        onSelectionChanged: (selected) async {
                                          if (selected.isEmpty) return;
                                          final mode = selected.first;
                                          if (mode == CarControlMode.manual) {
                                            await _sendModeCommand(
                                              context,
                                              'MODE MANUAL',
                                              mode: CarControlMode.manual,
                                              successText: '已切换到手动模式',
                                            );
                                          } else {
                                            await _sendModeCommand(
                                              context,
                                              'MODE AUTO',
                                              mode: CarControlMode.auto,
                                              successText: '已切换到自动模式',
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    SizedBox(
                                      height: 44,
                                      child: FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: scheme.error,
                                          foregroundColor: scheme.onError,
                                        ),
                                        onPressed: () async {
                                          await _sendModeCommand(
                                            context,
                                            'MODE EMG',
                                            mode: CarControlMode.emg,
                                            successText: '已发送急停指令',
                                          );
                                        },
                                        icon: const Icon(Icons.warning_amber_rounded),
                                        label: const Text('急停'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: switch (model.controlMode) {
                                      CarControlMode.manual => Colors.blue.withValues(alpha: 0.10),
                                      CarControlMode.auto => Colors.green.withValues(alpha: 0.10),
                                      CarControlMode.emg => scheme.error.withValues(alpha: 0.12),
                                      CarControlMode.unknown => scheme.surfaceContainerHighest,
                                    },
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: switch (model.controlMode) {
                                        CarControlMode.manual => Colors.blue.withValues(alpha: 0.32),
                                        CarControlMode.auto => Colors.green.withValues(alpha: 0.32),
                                        CarControlMode.emg => scheme.error.withValues(alpha: 0.42),
                                        CarControlMode.unknown => scheme.outlineVariant,
                                      },
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        switch (model.controlMode) {
                                          CarControlMode.manual => Icons.sports_esports_rounded,
                                          CarControlMode.auto => Icons.auto_awesome_rounded,
                                          CarControlMode.emg => Icons.warning_amber_rounded,
                                          CarControlMode.unknown => Icons.help_outline_rounded,
                                        },
                                        size: 18,
                                        color: switch (model.controlMode) {
                                          CarControlMode.manual => Colors.blue.shade700,
                                          CarControlMode.auto => Colors.green.shade700,
                                          CarControlMode.emg => scheme.error,
                                          CarControlMode.unknown => scheme.onSurfaceVariant,
                                        },
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '当前模式：${switch (model.controlMode) {
                                          CarControlMode.manual => '手动',
                                          CarControlMode.auto => '自动',
                                          CarControlMode.emg => '急停',
                                          CarControlMode.unknown => '未知',
                                        }}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(fontWeight: FontWeight.w700),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),
                        // 入口卡片：视频监控。
                        _GlassCard(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            leading: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.18),
                                    scheme.tertiary.withValues(alpha: 0.14),
                                  ],
                                ),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Icon(
                                Icons.videocam_rounded,
                                color: scheme.onSurface,
                              ),
                            ),
                            title: Text(
                              '视频监控',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            subtitle: const Text('查看 live / yolo RTSP 画面'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.of(context).pushNamed('/video'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 入口卡片：进入指令控制台（仅在已连接时可点击）。
                        _GlassCard(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            leading: Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.18),
                                    scheme.secondary.withValues(alpha: 0.14),
                                  ],
                                ),
                                border: Border.all(color: scheme.outlineVariant),
                              ),
                              child: Icon(
                                Icons.terminal_rounded,
                                color: scheme.onSurface,
                              ),
                            ),
                            title: Text(
                              '指令控制台',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              model.connected ? '开始发送指令控制小车' : '先连接到小车再进入',
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: model.connected
                                ? () => Navigator.of(context).pushNamed('/command')
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '提示：默认端口为 8080，可直接输入 ws://ip:port',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.statusColor,
    required this.statusIcon,
    required this.statusText,
    this.onSettingsTap,
  });

  final String title;
  final String subtitle;
  final Color statusColor;
  final IconData statusIcon;
  final String statusText;
  final VoidCallback? onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return _GlassCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.22),
                    scheme.secondary.withValues(alpha: 0.18),
                  ],
                ),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(Icons.directions_car_rounded,
                  color: scheme.onSurface, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '设置',
              onPressed: onSettingsTap,
              icon: const Icon(Icons.settings_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.78),
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
