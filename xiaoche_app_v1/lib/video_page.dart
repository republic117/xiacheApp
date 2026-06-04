import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'atlas_command_ws_client.dart';
import 'atlas_status_ws_client.dart';
import 'connection_model.dart';
import 'settings_model.dart';

enum VideoStreamKind { live, yolo }

enum VideoUiState { idle, connecting, playing, reconnecting, error }

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

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoStreamKind _kind = VideoStreamKind.live;

  late final Player _player;
  late final VideoController _videoController;
  final AtlasStatusWsClient _statusClient = AtlasStatusWsClient();
  final AtlasCommandWsClient _commandClient = AtlasCommandWsClient();

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String>? _errorSub;
  StreamSubscription<AtlasStatusConnState>? _statusStateSub;
  StreamSubscription<AtlasTelemetry>? _statusDataSub;
  StreamSubscription<AtlasCommandConnState>? _cmdStateSub;

  String? _currentUrl;
  VideoUiState _state = VideoUiState.idle;
  String? _videoError;
  String? _videoRawError;

  Timer? _firstFrameTimer;
  Timer? _retryTimer;

  int _retryCount = 0;
  bool _isStarting = false;
  bool _restartQueued = false;

  AtlasStatusConnState _statusConn = AtlasStatusConnState.disconnected;
  AtlasCommandConnState _cmdConn = AtlasCommandConnState.disconnected;
  AtlasTelemetry _telemetry = AtlasTelemetry.defaults();
  String? _statusUrl;
  String? _commandUrl;
  DateTime? _lastTelemetryUiAt;

  final TextEditingController _atlasCmdController = TextEditingController();
  bool _atlasCmdSending = false;
  AtlasCommandResponse? _lastAtlasResponse;
  String? _atlasCmdUiHint;

  static const Duration _firstFrameTimeout = Duration(seconds: 8);
  static const Duration _telemetryUiMinGap = Duration(milliseconds: 200);

  static const double _fabSize = 58;
  static const double _fabMargin = 12;

  String _currentCommand = 'stop';
  DateTime? _lastCmdSendAt;
  double? _draftSpeedPercent;
  bool _remotePanelVisible = false;
  Offset _remoteFabOffset = const Offset(0, 0);
  bool _fabReady = false;

  String _buildRtspUrl(SettingsModel settings, VideoStreamKind kind) {
    final path =
        (kind == VideoStreamKind.live) ? settings.streamPathLive : settings.streamPathYolo;
    final p = path.trim().replaceFirst(RegExp(r'^/+'), '');

    final user = settings.rtspUsername.trim();
    final pass = settings.rtspPassword.trim();
    final auth = user.isEmpty
        ? ''
        : '${Uri.encodeComponent(user)}:${Uri.encodeComponent(pass)}@';

    return 'rtsp://$auth${settings.atlasIp}:${settings.rtspPort}/$p';
  }

  String _buildStatusWsUrl(SettingsModel settings) {
    final statusIp = settings.atlasStatusIp.trim();
    final ip = statusIp.isNotEmpty ? statusIp : settings.atlasIp.trim();
    return 'ws://$ip:8765';
  }

  String _buildCommandWsUrl(SettingsModel settings) {
    final ip = settings.atlasIp.trim();
    return 'ws://$ip:8766';
  }

  void _log(String text) {
    debugPrint('[VideoPage] $text');
  }

  String _mapError(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('401') || m.contains('403') || m.contains('auth')) {
      return '鉴权失败，请检查用户名/密码或后端流权限';
    }
    if (m.contains('timeout') || m.contains('timed out')) {
      return '连接超时，请检查 Atlas 地址和网络';
    }
    if (m.contains('unreachable') || m.contains('refused') || m.contains('network')) {
      return '连接失败，请确认手机和 Atlas 在同一局域网';
    }
    if (m.contains('decoder') || m.contains('codec') || m.contains('h264')) {
      return '解码失败，请确认推流编码为 H264';
    }
    if (m.contains('eof')) {
      return '流中断（EOF），请检查网络稳定性';
    }
    return '播放失败，请检查 RTSP 地址/鉴权/流路径';
  }

  Duration _backoffDelay(int retry) {
    final sec = (1 << (retry - 1)).clamp(1, 5);
    return Duration(seconds: sec);
  }

  Future<void> _startPlay() async {
    if (_isStarting) {
      _restartQueued = true;
      return;
    }

    _isStarting = true;
    try {
      final settings = context.read<SettingsModel>();
      final url = _buildRtspUrl(settings, _kind);

      _retryTimer?.cancel();
      _firstFrameTimer?.cancel();

      _currentUrl = url;
      _videoError = null;
      _videoRawError = null;
      _state = _retryCount > 0 ? VideoUiState.reconnecting : VideoUiState.connecting;
      if (mounted) setState(() {});

      _log('start connect: url=$url, retry=$_retryCount');

      try {
        await _player.open(Media(url), play: true);
      } catch (e) {
        _handlePlayError(e.toString());
        return;
      }

      _firstFrameTimer = Timer(_firstFrameTimeout, () {
        if (!mounted) return;
        if (_state != VideoUiState.playing) {
          _handlePlayError('first frame timeout');
        }
      });
    } finally {
      _isStarting = false;
      if (_restartQueued && mounted) {
        _restartQueued = false;
        unawaited(_startPlay());
      }
    }
  }

  void _handlePlayError(String raw) {
    final text = raw == 'first frame timeout' ? '首帧超时（8秒无画面）' : _mapError(raw);

    _videoError = text;
    _videoRawError = raw;
    _state = VideoUiState.error;
    if (mounted) setState(() {});

    _firstFrameTimer?.cancel();

    _log('play error: url=$_currentUrl, raw=$raw');

    _retryCount += 1;
    final delay = _backoffDelay(_retryCount);
    _state = VideoUiState.reconnecting;
    if (mounted) setState(() {});

    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      if (!mounted) return;
      _startPlay();
    });

    _log('schedule reconnect: retry=$_retryCount, after=${delay.inSeconds}s');
  }

  Future<void> _manualRefresh() async {
    _retryCount = 0;
    await _startPlay();
  }

  String _stateText() {
    switch (_state) {
      case VideoUiState.idle:
        return '空闲';
      case VideoUiState.connecting:
        return '连接中';
      case VideoUiState.playing:
        return '播放中';
      case VideoUiState.reconnecting:
        return '重连中';
      case VideoUiState.error:
        return '错误';
    }
  }

  Color _stateColor(ColorScheme scheme) {
    switch (_state) {
      case VideoUiState.playing:
        return Colors.green;
      case VideoUiState.connecting:
      case VideoUiState.reconnecting:
        return scheme.primary;
      case VideoUiState.error:
        return scheme.error;
      case VideoUiState.idle:
        return scheme.onSurfaceVariant;
    }
  }

  String _statusConnText() {
    switch (_statusConn) {
      case AtlasStatusConnState.connecting:
        return '连接中';
      case AtlasStatusConnState.connected:
        return '已连接';
      case AtlasStatusConnState.disconnected:
        return '断开';
    }
  }

  Color _statusConnColor(ColorScheme scheme) {
    switch (_statusConn) {
      case AtlasStatusConnState.connecting:
        return scheme.primary;
      case AtlasStatusConnState.connected:
        return Colors.green;
      case AtlasStatusConnState.disconnected:
        return scheme.error;
    }
  }

  String _cmdConnText() {
    switch (_cmdConn) {
      case AtlasCommandConnState.connecting:
        return '连接中';
      case AtlasCommandConnState.connected:
        return '已连接';
      case AtlasCommandConnState.disconnected:
        return '断开';
    }
  }

  Color _cmdConnColor(ColorScheme scheme) {
    switch (_cmdConn) {
      case AtlasCommandConnState.connecting:
        return scheme.primary;
      case AtlasCommandConnState.connected:
        return Colors.green;
      case AtlasCommandConnState.disconnected:
        return scheme.error;
    }
  }

  String _matchText() {
    final suggestion = _telemetry.llmApplied.trim().toLowerCase();
    final executed = _telemetry.currentCmd.trim().toLowerCase();
    if (suggestion.isEmpty) return '暂无模型建议';
    if (executed.isEmpty) return '已有建议，未见执行命令';
    return suggestion == executed ? '模型建议与最终执行一致' : '模型建议与最终执行不一致';
  }

  Future<void> _sendAtlasNaturalCommand() async {
    final text = _atlasCmdController.text.trim();
    if (text.isEmpty || _atlasCmdSending) return;

    setState(() {
      _atlasCmdSending = true;
      _atlasCmdUiHint = null;
    });

    final response = await _commandClient.sendText(text);

    if (!mounted) return;

    final accepted = response.accepted;
    final decision = response.decision;

    setState(() {
      _atlasCmdSending = false;
      _lastAtlasResponse = response;
      _atlasCmdUiHint = accepted
          ? '已下发：${decision.cmd}（${decision.durationMs} ms）'
          : '指令未执行${decision.rejectReason.isNotEmpty ? '：${decision.rejectReason}' : ''}';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_atlasCmdUiHint ?? (accepted ? '已执行' : '指令未执行')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _fmtDouble(double v, {int digits = 2}) {
    if (v.isNaN || v.isInfinite) return '0';
    return v.toStringAsFixed(digits);
  }

  Widget _kvItem(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  bool _canSendCommandNow() {
    final now = DateTime.now();
    final last = _lastCmdSendAt;
    if (last != null && now.difference(last).inMilliseconds < 80) {
      return false;
    }
    _lastCmdSendAt = now;
    return true;
  }

  Future<void> _onRemoteSpeedChanged(double percent) async {
    setState(() => _draftSpeedPercent = percent);
    await context.read<SettingsModel>().setManualSpeedPercent(percent);
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

    final speed = forceStop ? 0 : percentToU16(_draftSpeedPercent ?? settings.manualSpeedPercent);
    final payloadCmd = MotionCmd(cmd: cmd, speed: cmd == 'stop' ? 0 : speed);

    final wireText = settings.manualUseTextProtocol
        ? '${payloadCmd.cmd} ${payloadCmd.speed}'
        : jsonEncode(payloadCmd.toJson());

    try {
      await model.send(wireText);
      if (!mounted) return;
      setState(() => _currentCommand = payloadCmd.cmd);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('发送失败，请检查连接状态')),
      );
    }
  }

  Future<void> _handleRemoteCommandTap(String cmd) async {
    if (!_canSendCommandNow()) return;
    if (cmd == 'stop') {
      HapticFeedback.mediumImpact();
      await _sendMotionCommand('stop', forceStop: true);
      return;
    }
    HapticFeedback.lightImpact();
    await _sendMotionCommand(cmd);
  }

  void _ensureFabOffset(BoxConstraints constraints) {
    if (_fabReady) return;
    _fabReady = true;
    _remoteFabOffset = Offset(
      constraints.maxWidth - _fabSize - _fabMargin,
      constraints.maxHeight - _fabSize - _fabMargin,
    );
  }

  void _onFabDrag(DragUpdateDetails details, BoxConstraints constraints) {
    final next = _remoteFabOffset + details.delta;
    final maxX = (constraints.maxWidth - _fabSize).clamp(0.0, double.infinity);
    final maxY = (constraints.maxHeight - _fabSize).clamp(0.0, double.infinity);
    setState(() {
      _remoteFabOffset = Offset(
        next.dx.clamp(0.0, maxX),
        next.dy.clamp(0.0, maxY),
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _playingSub = _player.stream.playing.listen((playing) {
      if (!mounted || !playing) return;
      _firstFrameTimer?.cancel();
      _retryCount = 0;
      _state = VideoUiState.playing;
      setState(() {});
    });

    _errorSub = _player.stream.error.listen((error) {
      if (!mounted || error.isEmpty) return;
      _handlePlayError(error);
    });

    _statusStateSub = _statusClient.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _statusConn = state);
    });

    _statusDataSub = _statusClient.telemetryStream.listen((telemetry) {
      if (!mounted) return;
      final now = DateTime.now();
      final last = _lastTelemetryUiAt;
      if (last != null && now.difference(last) < _telemetryUiMinGap) {
        return;
      }
      _lastTelemetryUiAt = now;
      setState(() => _telemetry = telemetry);
    });

    _cmdStateSub = _commandClient.stateStream.listen((state) {
      if (!mounted) return;
      setState(() => _cmdConn = state);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPlay();
      final settings = context.read<SettingsModel>();
      final statusUrl = _buildStatusWsUrl(settings);
      _statusUrl = statusUrl;
      _statusClient.start(statusUrl);

      final cmdUrl = _buildCommandWsUrl(settings);
      _commandUrl = cmdUrl;
      _commandClient.start(cmdUrl);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = context.read<SettingsModel>();

    final nextStatusUrl = _buildStatusWsUrl(settings);
    if (_statusUrl != nextStatusUrl) {
      _statusUrl = nextStatusUrl;
      _statusClient.start(nextStatusUrl);
    }

    final nextCommandUrl = _buildCommandWsUrl(settings);
    if (_commandUrl != nextCommandUrl) {
      _commandUrl = nextCommandUrl;
      _commandClient.start(nextCommandUrl);
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _firstFrameTimer?.cancel();
    _playingSub?.cancel();
    _errorSub?.cancel();
    _statusStateSub?.cancel();
    _statusDataSub?.cancel();
    _cmdStateSub?.cancel();
    _atlasCmdController.dispose();
    _player.dispose();
    _statusClient.dispose();
    _commandClient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final scheme = Theme.of(context).colorScheme;

    final currentUrl = _buildRtspUrl(settings, _kind);
    final statusWsUrl = _buildStatusWsUrl(settings);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '视频监控',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: SegmentedButton<VideoStreamKind>(
              showSelectedIcon: true,
              segments: const [
                ButtonSegment(
                  value: VideoStreamKind.live,
                  label: Text('live'),
                  icon: Icon(Icons.check, size: 18),
                ),
                ButtonSegment(
                  value: VideoStreamKind.yolo,
                  label: Text('yolo'),
                  icon: Icon(Icons.auto_awesome_rounded, size: 18),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (value) async {
                _kind = value.first;
                _retryCount = 0;
                if (mounted) setState(() {});
                await _startPlay();
              },
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _ensureFabOffset(constraints);
          final conn = context.watch<ConnectionModel>();
          final speedPercent = _draftSpeedPercent ?? settings.manualSpeedPercent;
          final speedU16 = percentToU16(speedPercent);

          return Stack(
            children: [
              Column(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      children: [
                        Container(
                          color: Colors.black,
                          child: Video(
                            controller: _videoController,
                            controls: NoVideoControls,
                            fit: BoxFit.contain,
                          ),
                        ),
                        Positioned(
                          left: 12,
                          top: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.circle, size: 10, color: _stateColor(scheme)),
                                const SizedBox(width: 6),
                                Text(
                                  '${_stateText()} · RTSP(${settings.rtspUseTcp ? 'TCP' : 'UDP'})',
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link_rounded,
                            color: scheme.primary.withValues(alpha: 0.7),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _currentUrl ?? currentUrl,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    letterSpacing: 0.3,
                                  ),
                            ),
                          ),
                          IconButton(
                            onPressed: _manualRefresh,
                            icon: Icon(Icons.refresh_rounded, color: scheme.onSurface, size: 28),
                          ),
                        ],
                      ),
                    ),
                    if (_videoError != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _videoError!,
                                style: TextStyle(color: scheme.onErrorContainer),
                              ),
                              if (_videoRawError != null && _videoRawError!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '原始错误：${_videoRawError!}',
                                  style: TextStyle(
                                    color: scheme.onErrorContainer.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Atlas 状态回传',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusConnColor(scheme).withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _statusConnColor(scheme).withValues(alpha: 0.32),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.circle, size: 9, color: _statusConnColor(scheme)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _statusConnText(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _statusConnColor(scheme),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              statusWsUrl,
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                            if (settings.atlasStatusIp.trim().isEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '状态回传IP未单独设置，当前跟随 Atlas IP',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                            _kvItem(context, '决策状态', _telemetry.decisionState),
                            const SizedBox(height: 6),
                            _kvItem(context, '障碍方向', _telemetry.obstacleSide),
                            const SizedBox(height: 6),
                            _kvItem(context, '置信度', _fmtDouble(_telemetry.confidence, digits: 3)),
                            const SizedBox(height: 6),
                            _kvItem(context, 'AI FPS', _fmtDouble(_telemetry.fps, digits: 2)),
                            const SizedBox(height: 6),
                            _kvItem(context, '推理时延', '${_fmtDouble(_telemetry.latencyMs, digits: 1)} ms'),
                            const SizedBox(height: 6),
                            _kvItem(context, '当前命令', _telemetry.currentCmd),
                            const SizedBox(height: 6),
                            _kvItem(context, '控制源', _telemetry.cmdSource),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  'Atlas 指令口（LLM）',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _cmdConnColor(scheme).withValues(alpha: 0.16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: _cmdConnColor(scheme).withValues(alpha: 0.32),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.circle, size: 9, color: _cmdConnColor(scheme)),
                                      const SizedBox(width: 6),
                                      Text(
                                        _cmdConnText(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: _cmdConnColor(scheme),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _commandUrl ?? _buildCommandWsUrl(settings),
                              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _atlasCmdController,
                              minLines: 1,
                              maxLines: 3,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendAtlasNaturalCommand(),
                              decoration: InputDecoration(
                                labelText: '自然语言指令',
                                hintText: '例如：前进两秒，然后停下',
                                prefixIcon: const Icon(Icons.auto_awesome_rounded),
                                suffixIcon: _atlasCmdSending
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2.2),
                                        ),
                                      )
                                    : IconButton(
                                        tooltip: '发送到 Atlas',
                                        onPressed: _sendAtlasNaturalCommand,
                                        icon: const Icon(Icons.send_rounded),
                                      ),
                              ),
                            ),
                            if (_atlasCmdUiHint != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _atlasCmdUiHint!,
                                style: TextStyle(
                                  color: (_lastAtlasResponse?.accepted ?? false)
                                      ? Colors.green
                                      : scheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            if (_lastAtlasResponse != null) ...[
                              const SizedBox(height: 10),
                              _kvItem(context, '受理', _lastAtlasResponse!.ok ? 'true' : 'false'),
                              const SizedBox(height: 6),
                              _kvItem(context, '有效决策', _lastAtlasResponse!.decision.valid ? 'true' : 'false'),
                              const SizedBox(height: 6),
                              _kvItem(context, '动作', _lastAtlasResponse!.decision.cmd.isEmpty ? '-' : _lastAtlasResponse!.decision.cmd),
                              const SizedBox(height: 6),
                              _kvItem(context, '模式', _lastAtlasResponse!.decision.mode.isEmpty ? '-' : _lastAtlasResponse!.decision.mode),
                              const SizedBox(height: 6),
                              _kvItem(context, '时长', '${_lastAtlasResponse!.decision.durationMs} ms'),
                              const SizedBox(height: 6),
                              _kvItem(context, '拒绝原因', _lastAtlasResponse!.decision.rejectReason.isEmpty ? '-' : _lastAtlasResponse!.decision.rejectReason),
                              if ((_lastAtlasResponse!.llmRaw ?? '').isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'llm_raw: ${_lastAtlasResponse!.llmRaw!}',
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '模型建议 vs 最终执行',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 10),
                            _kvItem(context, '模型建议', _telemetry.llmApplied.isEmpty ? '-' : _telemetry.llmApplied),
                            const SizedBox(height: 6),
                            _kvItem(context, '最终执行', _telemetry.currentCmd.isEmpty ? '-' : _telemetry.currentCmd),
                            const SizedBox(height: 6),
                            _kvItem(context, '控制源', _telemetry.cmdSource),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: _matchText().contains('一致')
                                    ? Colors.green.withValues(alpha: 0.12)
                                    : scheme.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                _matchText(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _matchText().contains('一致') ? Colors.green : scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 40),
                      child: Text(
                        '若仍黑屏：请确认 Atlas IP 为局域网地址，且 RTSP 路径与鉴权信息正确。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_remotePanelVisible)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 20,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
                      ),
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Icon(
                                conn.connected ? Icons.sensors : Icons.sensors_off,
                                size: 18,
                                color: conn.connected ? Colors.green : scheme.error,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                conn.connected ? '遥控已连接' : '遥控未连接',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: conn.connected ? Colors.green : scheme.error,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${speedPercent.round()}%（$speedU16）',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: speedPercent,
                            min: 0,
                            max: 100,
                            divisions: 100,
                            label: '${speedPercent.round()}%',
                            onChanged: _onRemoteSpeedChanged,
                          ),
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: Stack(
                              children: [
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: _RemotePadButton(
                                    command: 'forward',
                                    icon: Icons.keyboard_arrow_up_rounded,
                                    enabled: conn.connected,
                                    onTap: _handleRemoteCommandTap,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: _RemotePadButton(
                                    command: 'backward',
                                    icon: Icons.keyboard_arrow_down_rounded,
                                    enabled: conn.connected,
                                    onTap: _handleRemoteCommandTap,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _RemotePadButton(
                                    command: 'left',
                                    icon: Icons.keyboard_arrow_left_rounded,
                                    enabled: conn.connected,
                                    onTap: _handleRemoteCommandTap,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _RemotePadButton(
                                    command: 'right',
                                    icon: Icons.keyboard_arrow_right_rounded,
                                    enabled: conn.connected,
                                    onTap: _handleRemoteCommandTap,
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.center,
                                  child: _RemotePadButton(
                                    command: 'stop',
                                    icon: Icons.stop_rounded,
                                    enabled: conn.connected,
                                    onTap: _handleRemoteCommandTap,
                                    isStop: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '当前指令：${_currentCommand.toUpperCase()}',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: _remoteFabOffset.dx,
                top: _remoteFabOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) => _onFabDrag(details, constraints),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => setState(() => _remotePanelVisible = !_remotePanelVisible),
                      child: Ink(
                        width: _fabSize,
                        height: _fabSize,
                        decoration: BoxDecoration(
                          color: _remotePanelVisible
                              ? scheme.primaryContainer.withValues(alpha: 0.92)
                              : scheme.primary.withValues(alpha: 0.92),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.24),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Icon(
                          _remotePanelVisible ? Icons.close_rounded : Icons.gamepad_rounded,
                          color: _remotePanelVisible ? scheme.onPrimaryContainer : scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RemotePadButton extends StatefulWidget {
  const _RemotePadButton({
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
  State<_RemotePadButton> createState() => _RemotePadButtonState();
}

class _RemotePadButtonState extends State<_RemotePadButton> {
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
