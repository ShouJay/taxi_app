import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../managers/playback_manager.dart';
import '../config/app_config.dart';

/// 主畫面 - 影片播放
class MainScreen extends StatefulWidget {
  final PlaybackManager playbackManager;
  final VoidCallback onSettingsRequested;

  const MainScreen({
    Key? key,
    required this.playbackManager,
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

            // 狀態指示器（調試用）
            if (widget.playbackManager.state != PlaybackState.idle)
              Positioned(top: 40, left: 20, child: _buildStatusIndicator()),

            // 隊列指示器
            if (widget.playbackManager.queueLength > 0)
              Positioned(top: 40, right: 20, child: _buildQueueIndicator()),
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

  @override
  void dispose() {
    super.dispose();
  }
}
