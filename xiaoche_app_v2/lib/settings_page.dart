import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'settings_model.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final scheme = Theme.of(context).colorScheme;

    if (settings.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle(context, '连接设置'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('断线自动重连'),
                  subtitle: const Text('当连接意外断开时，自动尝试重新连接。'),
                  value: settings.autoReconnectEnabled,
                  onChanged: (value) => settings.setAutoReconnect(value),
                ),
                _buildIntSettingTile(
                  context,
                  title: '最大重连次数',
                  subtitle: '${settings.reconnectAttempts} 次',
                  value: settings.reconnectAttempts,
                  onSave: (value) => settings.setReconnectAttempts(value),
                  label: '次数',
                ),
                _buildIntSettingTile(
                  context,
                  title: '重连间隔',
                  subtitle: '${settings.reconnectInterval} 秒',
                  value: settings.reconnectInterval,
                  onSave: (value) => settings.setReconnectInterval(value),
                  label: '秒',
                ),
                _buildIntSettingTile(
                  context,
                  title: '默认端口号',
                  subtitle: '当前: ${settings.defaultPort}',
                  value: settings.defaultPort,
                  onSave: (value) => settings.setDefaultPort(value),
                  label: '端口',
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '视频设置'),
          Card(
            child: Column(
              children: [
                _buildStringSettingTile(
                  context,
                  title: 'Atlas IP 地址',
                  subtitle: settings.atlasIp,
                  value: settings.atlasIp,
                  onSave: (value) => settings.setAtlasIp(value),
                  label: 'IP 地址',
                  validator: _validateHost,
                ),
                _buildStringSettingTile(
                  context,
                  title: 'Atlas 状态回传IP（可选）',
                  subtitle: settings.atlasStatusIp.isEmpty ? '留空则使用 Atlas IP' : settings.atlasStatusIp,
                  value: settings.atlasStatusIp,
                  onSave: (value) => settings.setAtlasStatusIp(value),
                  label: '留空则使用 Atlas IP',
                  validator: _validateOptionalHost,
                ),
                _buildIntSettingTile(
                  context,
                  title: 'RTSP 端口',
                  subtitle: settings.rtspPort.toString(),
                  value: settings.rtspPort,
                  onSave: (value) => settings.setRtspPort(value),
                  label: '端口',
                ),
                _buildStringSettingTile(
                  context,
                  title: 'Live 流路径',
                  subtitle: settings.streamPathLive,
                  value: settings.streamPathLive,
                  onSave: (value) => settings.setStreamPathLive(value),
                  label: '路径',
                ),
                _buildStringSettingTile(
                  context,
                  title: 'Yolo 流路径',
                  subtitle: settings.streamPathYolo,
                  value: settings.streamPathYolo,
                  onSave: (value) => settings.setStreamPathYolo(value),
                  label: '路径',
                ),
                _buildStringSettingTile(
                  context,
                  title: 'RTSP 用户名',
                  subtitle: settings.rtspUsername.isEmpty ? '未设置' : settings.rtspUsername,
                  value: settings.rtspUsername,
                  onSave: (value) => settings.setRtspUsername(value),
                  label: '用户名',
                ),
                _buildStringSettingTile(
                  context,
                  title: 'RTSP 密码',
                  subtitle: settings.rtspPassword.isEmpty
                      ? '未设置'
                      : '已设置（${settings.rtspPassword.length}位）',
                  value: settings.rtspPassword,
                  onSave: (value) => settings.setRtspPassword(value),
                  label: '密码',
                  obscureText: true,
                ),
                SwitchListTile(
                  title: const Text('RTSP 使用 TCP 传输'),
                  subtitle: Text(settings.rtspUseTcp ? '当前：TCP（更稳定）' : '当前：UDP（更低延迟）'),
                  value: settings.rtspUseTcp,
                  onChanged: (value) => settings.setRtspTransport(value ? 'tcp' : 'udp'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '外观'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '主题颜色',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _ColorPicker(settings: settings),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionTitle(context, '数据管理'),
          Card(
            child: ListTile(
              title: const Text('清空历史与缓存'),
              subtitle: const Text('将清除最近连接 IP 和所有指令日志。'),
              leading: Icon(Icons.delete_forever_rounded, color: scheme.error),
              onTap: () => _showClearCacheDialog(context, settings),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  Future<void> _showIntSettingDialog(
    BuildContext context,
    String title,
    int currentValue,
    String label,
    void Function(int) onSave,
  ) async {
    final controller = TextEditingController(text: currentValue.toString());
    final value = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              if (val != null) {
                Navigator.pop(context, val);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (value != null) {
      onSave(value);
    }
  }

  Future<void> _showStringSettingDialog(
    BuildContext context,
    String title,
    String currentValue,
    String label,
    void Function(String) onSave, {
    bool obscureText = false,
    String? Function(String)? validator,
  }) async {
    final controller = TextEditingController(text: currentValue);
    String? errorText;

    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
            decoration: InputDecoration(labelText: label, errorText: errorText),
          autofocus: true,
          obscureText: obscureText,
            onChanged: (_) {
              if (errorText != null) {
                setState(() => errorText = null);
              }
            },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () {
                final input = controller.text.trim();
                final err = validator?.call(input);
                if (err != null) {
                  setState(() => errorText = err);
                  return;
                }
                Navigator.pop(context, input);
              },
            child: const Text('保存'),
          ),
        ],
        ),
      ),
    );

    if (value != null) {
      onSave(value.trim());
    }
  }

  Widget _buildIntSettingTile(
    BuildContext context, {
      required String title,
      required String subtitle,
      required int value,
      required void Function(int) onSave,
      required String label,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _showIntSettingDialog(context, title, value, label, onSave),
    );
  }

  Widget _buildStringSettingTile(
    BuildContext context, {
      required String title,
      required String subtitle,
      required String value,
      required void Function(String) onSave,
      required String label,
      bool obscureText = false,
    String? Function(String)? validator,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.edit_outlined),
      onTap: () => _showStringSettingDialog(
        context,
        title,
        value,
        label,
        onSave,
        obscureText: obscureText,
        validator: validator,
      ),
    );
  }

  String? _validateHost(String input) {
    final text = input.trim();
    if (text.isEmpty) return '请输入 IP 或域名';

    final ipv4 = RegExp(
      r'^(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}$',
    );
    final host = RegExp(r'^[a-zA-Z0-9.-]+$');

    if (ipv4.hasMatch(text) || host.hasMatch(text)) {
      return null;
    }
    return '格式无效，请输入 IPv4 或域名';
  }

  String? _validateOptionalHost(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    return _validateHost(text);
  }

  Future<void> _showClearCacheDialog(BuildContext context, SettingsModel settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认操作'),
        content: const Text('此操作将清除所有历史记录和缓存，且不可恢复。确定要继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await settings.clearHistoryAndCache();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('历史与缓存已清空。')),
        );
      }
    }
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.settings});

  final SettingsModel settings;

  static const List<Color> _presetColors = [
    Color(0xFF2F6BFF),
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.pink,
    Colors.indigo,
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _presetColors.length,
      itemBuilder: (context, index) {
        final color = _presetColors[index];
        final isSelected = settings.themeColor.value == color.value;
        return GestureDetector(
          onTap: () => settings.setThemeColor(color),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                    )
                  : null,
            ),
            child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
          ),
        );
      },
    );
  }
}
