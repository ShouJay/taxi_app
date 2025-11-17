import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';
import '../managers/playback_manager.dart';
import '../services/download_manager.dart';
import '../config/app_config.dart';

/// 主畫面 - 影片播放
class MainScreen extends StatefulWidget {
  final PlaybackManager playbackManager;
  final DownloadManager downloadManager;
  final bool isAdminMode;
  final Position? latestPosition;
  final DateTime? lastLocationSentTime;
  final VoidCallback onSettingsRequested;

  const MainScreen({
    Key? key,
    required this.playbackManager,
    required this.downloadManager,
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

    // 監聽播放啟用狀態變化
    widget.playbackManager.onPlaybackEnabledChanged = (enabled) {
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

            // 播放控制按鈕（管理員模式）
            if (widget.isAdminMode)
              Positioned(
                top: 40,
                left: 0,
                right: 0,
                child: Center(child: _buildPlaybackControlButton()),
              ),

            // 設定圖標（管理員模式）
            if (widget.isAdminMode)
              Positioned(top: 20, right: 20, child: _buildSettingsButton()),

            if (widget.isAdminMode)
              Positioned(left: 20, bottom: 40, child: _buildAdminInfoPanel()),
          ],
        ),
      ),
    );
  }

  /// 建立內容（影片或提示）
  Widget _buildContent() {
    final controller = widget.playbackManager.controller;
    final state = widget.playbackManager.state;

    // 在載入過程中顯示黑屏幕
    if (state == PlaybackState.loading) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }

    if (state == PlaybackState.error) {
      return _buildErrorScreen();
    }

    // 如果是閒置狀態且沒有控制器，顯示提示畫面
    if (state == PlaybackState.idle && controller == null) {
      return _buildWelcomeScreen();
    }

    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.expand(child: ColoredBox(color: Colors.black));
    }

    // 顯示影片
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio,
      child: VideoPlayer(controller, key: ValueKey(controller)),
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
    final bool isCampaignMode =
        widget.playbackManager.playbackMode == PlaybackMode.campaign;
    final String campaignId = widget.playbackManager.activeCampaignId ?? '未提供';
    final styleBase = const TextStyle(color: Colors.white, fontSize: 14);

    final latitude = position != null
        ? position.latitude.toStringAsFixed(6)
        : '--';
    final longitude = position != null
        ? position.longitude.toStringAsFixed(6)
        : '--';
    final speedKmh = position != null
        ? (position.speed * 3.6).clamp(0, double.infinity)
        : null;
    final sentTimeText = _formatDateTime(sentTime);
    final playbackSource = _describePlaybackSource(currentItem);
    // 顯示影片名稱，如果不是檔號格式（不包含 .mp4 等擴展名），則直接顯示
    final videoName = _getDisplayName(currentItem);

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
          if (isCampaignMode) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(
                  Icons.campaign,
                  color: Colors.purpleAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text('活動播放中 (ID: $campaignId)', style: styleBase),
              ],
            ),
          ],
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

  Widget _buildErrorScreen() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
          SizedBox(height: 16),
          Text('播放發生錯誤', style: TextStyle(color: Colors.white, fontSize: 20)),
          SizedBox(height: 8),
          Text(
            '系統將自動嘗試播放下一支影片',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// 建立狀態指示器
  Widget _buildStatusIndicator() {
    final state = widget.playbackManager.state;
    final currentItem = widget.playbackManager.currentItem;
    final bool isCampaignMode =
        widget.playbackManager.playbackMode == PlaybackMode.campaign;
    final String campaignId = widget.playbackManager.activeCampaignId ?? '未提供';

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
        text = _getDisplayName(currentItem);
        // 如果是"尚未播放"，改為"播放中"
        if (text == '尚未播放') {
          text = '播放中';
        }
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          if (isCampaignMode) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.campaign,
                  color: Colors.purpleAccent,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  '活動播放中 (ID: $campaignId)',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ],
            ),
          ],
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

  /// 獲取顯示名稱（優先顯示影片名稱，如果是檔號則處理）
  String _getDisplayName(PlaybackItem? item) {
    if (item == null) {
      return '尚未播放';
    }

    // 如果 advertisementName 存在且不是檔號格式（不包含 .mp4, .mov 等擴展名），直接使用
    final name = item.advertisementName;
    if (name.isNotEmpty) {
      // 檢查是否是檔號格式（包含視頻文件擴展名）
      final hasVideoExtension =
          name.toLowerCase().endsWith('.mp4') ||
          name.toLowerCase().endsWith('.mov') ||
          name.toLowerCase().endsWith('.avi') ||
          name.toLowerCase().endsWith('.mkv') ||
          name.toLowerCase().endsWith('.webm');

      // 如果不是檔號格式，直接使用
      if (!hasVideoExtension) {
        return name;
      }

      // 如果是檔號格式，提取檔名（不含擴展名）作為顯示名稱
      final nameWithoutExt = name.replaceAll(RegExp(r'\.[^.]+$'), '');
      // 如果去掉擴展名後還有內容，使用它；否則使用原始名稱
      return nameWithoutExt.isNotEmpty ? nameWithoutExt : name;
    }

    // 如果 advertisementName 為空，嘗試從 videoFilename 提取
    final filename = item.videoFilename;
    if (filename.isNotEmpty) {
      final nameWithoutExt = filename.replaceAll(RegExp(r'\.[^.]+$'), '');
      return nameWithoutExt.isNotEmpty ? nameWithoutExt : filename;
    }

    return '未命名影片';
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

    return '本地循環播放';
  }

  /// 建立播放控制按鈕（管理員模式）
  Widget _buildPlaybackControlButton() {
    final isEnabled = widget.playbackManager.isPlaybackEnabled;
    final isPlaying = widget.playbackManager.state == PlaybackState.playing;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isEnabled ? Colors.green : Colors.red,
          width: 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isEnabled
                  ? (isPlaying ? Icons.pause_circle : Icons.play_circle)
                  : Icons.stop_circle,
              color: isEnabled ? Colors.green : Colors.red,
              size: 28,
            ),
            onPressed: () async {
              await widget.playbackManager.setPlaybackEnabled(!isEnabled);
            },
            tooltip: isEnabled ? '暫停播放' : '開始播放',
          ),
          const SizedBox(width: 8),
          Text(
            isEnabled ? (isPlaying ? '播放中' : '已啟用') : '已停用',
            style: TextStyle(
              color: isEnabled ? Colors.green : Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 建立設定按鈕（管理員模式）
  Widget _buildSettingsButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: Colors.blueAccent.withOpacity(0.6), width: 2),
      ),
      child: IconButton(
        icon: const Icon(Icons.settings, color: Colors.blueAccent, size: 28),
        onPressed: () {
          print('⚙️ 開啟設定頁面');
          widget.onSettingsRequested();
        },
        tooltip: '開啟設定',
        padding: const EdgeInsets.all(8),
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
