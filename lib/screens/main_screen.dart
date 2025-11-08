import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';
import '../managers/playback_manager.dart';
import '../config/app_config.dart';

/// 主畫面 - 影片播放
class MainScreen extends StatefulWidget {
  final PlaybackManager playbackManager;
  final bool isAdminMode;
  final Position? latestPosition;
  final DateTime? lastLocationSentTime;
  final VoidCallback onSettingsRequested;

  const MainScreen({
    Key? key,
    required this.playbackManager,
    required this.isAdminMode,
    this.latestPosition,
    this.lastLocationSentTime,
    required this.onSettingsRequested,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // 點擊計數器
  int _tapCount = 0;
  DateTime? _firstTapTime;

  @override
  void initState() {
    super.initState();

    // 監聽播放狀態變化
    widget.playbackManager.onStateChanged = (state) {
      if (mounted) {
        setState(() {});
      }
    };

    // 監聽播放項目變化
    widget.playbackManager.onItemChanged = (item) {
      if (mounted) {
        setState(() {});
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _handleTap,
        child: Stack(
          children: [
            // 影片播放器或提示畫面
            Center(child: _buildContent()),

            // 管理員模式資訊疊層
            if (widget.isAdminMode &&
                widget.playbackManager.state != PlaybackState.idle)
              Positioned(top: 40, left: 20, child: _buildStatusIndicator()),

            // 隊列指示器
            if (widget.isAdminMode && widget.playbackManager.queueLength > 0)
              Positioned(top: 40, right: 20, child: _buildQueueIndicator()),

            if (widget.isAdminMode)
              Positioned(
                left: 20,
                bottom: 40,
                child: _buildAdminInfoPanel(),
              ),
          ],
        ),
      ),
    );
  }

  /// 建立內容（影片或提示）
  Widget _buildContent() {
    final controller = widget.playbackManager.controller;
    final state = widget.playbackManager.state;

    // 如果是閒置狀態且沒有控制器，顯示提示畫面
    if (state == PlaybackState.idle && controller == null) {
      return _buildWelcomeScreen();
    }

    // 如果正在載入
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // 顯示影片
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  /// 建立歡迎/提示畫面
  Widget _buildWelcomeScreen() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Logo 或圖標
          const Icon(Icons.local_taxi, size: 100, color: Colors.white70),
          const SizedBox(height: 40),

          // 標題
          const Text(
            'Taxi 廣告播放系統',
            style: TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // 說明文字
          const Text(
            '尚未找到預設播放影片',
            style: TextStyle(color: Colors.white70, fontSize: 20),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          const Text(
            '請進入設定頁面配置伺服器地址\n系統將自動接收並播放廣告',
            style: TextStyle(color: Colors.white60, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 60),

          // 進入設定按鈕
          ElevatedButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 28),
            label: const Text('進入設定', style: TextStyle(fontSize: 20)),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          // 提示文字
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline, color: Colors.white60, size: 20),
                SizedBox(width: 12),
                Text(
                  '或點擊螢幕 5 下快速進入設定',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminInfoPanel() {
    final Position? position = widget.latestPosition;
    final DateTime? sentTime = widget.lastLocationSentTime;
    final PlaybackItem? currentItem = widget.playbackManager.currentItem;
    final styleBase = const TextStyle(color: Colors.white, fontSize: 14);

    final latitude =
        position != null ? position.latitude.toStringAsFixed(6) : '--';
    final longitude =
        position != null ? position.longitude.toStringAsFixed(6) : '--';
    final speedKmh =
        position != null ? (position.speed * 3.6).clamp(0, double.infinity) : null;
    final sentTimeText = _formatDateTime(sentTime);
    final playbackSource = _describePlaybackSource(currentItem);
    final videoName = currentItem?.advertisementName ?? '尚未播放';

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '管理員資訊',
            style: TextStyle(
              color: Colors.blueAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text('影片: $videoName', style: styleBase),
          const SizedBox(height: 4),
          Text('來源: $playbackSource', style: styleBase),
          const Divider(height: 18, color: Colors.white24),
          Text('經度: $longitude', style: styleBase),
          Text('緯度: $latitude', style: styleBase),
          Text(
            '速度: ${speedKmh != null ? '${speedKmh.toStringAsFixed(1)} km/h' : '--'}',
            style: styleBase,
          ),
          Text('最後發送: $sentTimeText', style: styleBase),
        ],
      ),
    );
  }

  /// 建立狀態指示器
  Widget _buildStatusIndicator() {
    final state = widget.playbackManager.state;
    final currentItem = widget.playbackManager.currentItem;

    IconData icon;
    String text;
    Color color;

    switch (state) {
      case PlaybackState.loading:
        icon = Icons.download;
        text = '載入中';
        color = Colors.orange;
        break;
      case PlaybackState.playing:
        icon = Icons.play_circle;
        text = currentItem?.advertisementName ?? '播放中';
        color = Colors.green;
        break;
      case PlaybackState.paused:
        icon = Icons.pause_circle;
        text = '已暫停';
        color = Colors.yellow;
        break;
      case PlaybackState.error:
        icon = Icons.error;
        text = '錯誤';
        color = Colors.red;
        break;
      default:
        icon = Icons.info;
        text = '閒置';
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 建立隊列指示器
  Widget _buildQueueIndicator() {
    final queueLength = widget.playbackManager.queueLength;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text(
            '隊列: $queueLength',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 處理螢幕點擊
  void _handleTap() {
    final now = DateTime.now();

    // 檢查是否在檢測時間窗口內
    if (_firstTapTime == null ||
        now.difference(_firstTapTime!) > AppConfig.tapDetectionWindow) {
      // 重置計數器
      _tapCount = 1;
      _firstTapTime = now;
      print('👆 點擊 1/${AppConfig.tapCountToSettings}');
    } else {
      // 增加計數
      _tapCount++;
      print('👆 點擊 $_tapCount/${AppConfig.tapCountToSettings}');

      // 檢查是否達到設定次數
      if (_tapCount >= AppConfig.tapCountToSettings) {
        _tapCount = 0;
        _firstTapTime = null;
        _openSettings();
      }
    }
  }

  /// 開啟設定頁面
  void _openSettings() {
    print('⚙️ 開啟設定頁面');
    widget.onSettingsRequested();
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _describePlaybackSource(PlaybackItem? item) {
    if (item == null) {
      return '尚未播放';
    }

    if (item.isOverride || item.trigger == 'admin_override') {
      return '推播插播';
    }

    if (item.trigger == 'location_based') {
      return 'GPS 被動播放';
    }

    if (item.advertisementId.startsWith('local-')) {
      return '本地循環播放';
    }

    if (item.trigger == 'http_heartbeat') {
      return '後端推播';
    }

    return '一般播放';
  }

  @override
  void dispose() {
    super.dispose();
  }
}
