import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'settings_model.dart';

enum VideoStreamKind { live, yolo }

enum VideoUiState { idle, connecting, playing, reconnecting, error }

class VideoPage extends StatefulWidget {
  const VideoPage({super.key});

  @override
  State<VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<VideoPage> {
  VideoStreamKind _kind = VideoStreamKind.live;

  late final Player _player;
  late final VideoController _videoController;

  StreamSubscription<bool>? _playingSub;
  StreamSubscription<String>? _errorSub;

  String? _currentUrl;
  VideoUiState _state = VideoUiState.idle;
  String? _videoError;
  String? _videoRawError;

  Timer? _firstFrameTimer;
  Timer? _retryTimer;

  int _retryCount = 0;
  bool _isStarting = false;
  bool _restartQueued = false;

  static const Duration _firstFrameTimeout = Duration(seconds: 8);

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startPlay();
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _firstFrameTimer?.cancel();
    _playingSub?.cancel();
    _errorSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final scheme = Theme.of(context).colorScheme;

    final currentUrl = _buildRtspUrl(settings, _kind);

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
      body: Column(
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
                  const Text(
                    '提示',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前默认：$currentUrl\n当前传输：RTSP(${settings.rtspUseTcp ? 'TCP' : 'UDP'})，失败会自动重连。',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
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
    );
  }
}
