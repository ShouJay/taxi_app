import 'dart:async';
import 'dart:io';
import 'package:video_player/video_player.dart';
import '../services/download_manager.dart';

/// 播放項目
class PlaybackItem {
  final String videoFilename;
  final String advertisementId;
  final String advertisementName;
  final bool isOverride;
  final String trigger; // location_based, admin_override, http_heartbeat
  final String? campaignId; // 活動ID，用於管理同一個活動的廣告

  PlaybackItem({
    required this.videoFilename,
    required this.advertisementId,
    required this.advertisementName,
    this.isOverride = false,
    this.trigger = 'unknown',
    this.campaignId,
  });
}

/// 播放狀態
enum PlaybackState { idle, loading, playing, paused, error }

/// 播放管理器
class PlaybackManager {
  VideoPlayerController? _currentController;
  final DownloadManager downloadManager;
  final List<PlaybackItem> _playQueue = [];
  List<String> _localVideoPlaylist = [];
  int _currentLocalVideoIndex = 0;

  // 當前活動的 location_based 廣告列表（用於循環播放）
  List<PlaybackItem> _locationBasedAds = [];
  int _currentLocationAdIndex = 0;
  String? _currentCampaignId;
  DateTime? _lastLocationAdReceivedTime; // 最後一次收到位置廣告的時間

  PlaybackState _state = PlaybackState.idle;
  PlaybackState get state => _state;

  PlaybackItem? _currentItem;
  PlaybackItem? get currentItem => _currentItem;

  // 事件回調
  Function(PlaybackState)? onStateChanged;
  Function(PlaybackItem)? onItemChanged;
  Function(String)? onError;

  // 當前播放器控制器（用於 UI）
  VideoPlayerController? get controller => _currentController;

  PlaybackManager({required this.downloadManager}) {
    _loadLocalVideoPlaylist();
  }

  /// 載入本地影片播放列表
  Future<void> _loadLocalVideoPlaylist() async {
    _localVideoPlaylist = await downloadManager.getAllDownloadedVideos();
    if (_localVideoPlaylist.isNotEmpty) {
      print('🎬 本地影片播放列表已載入：${_localVideoPlaylist.length} 個影片');
    }
  }

  /// 刷新本地影片播放列表
  Future<void> refreshLocalPlaylist() async {
    await _loadLocalVideoPlaylist();
  }

  /// 插播廣告
  Future<void> insertAd({
    required String videoFilename,
    required String advertisementId,
    required String advertisementName,
    bool isOverride = false,
    String trigger = 'unknown',
    String? campaignId,
  }) async {
    final item = PlaybackItem(
      videoFilename: videoFilename,
      advertisementId: advertisementId,
      advertisementName: advertisementName,
      isOverride: isOverride,
      trigger: trigger,
      campaignId: campaignId,
    );

    if (isOverride) {
      print('🎬 插播優先廣告: $advertisementName');
      // 優先級廣告，立即插播
      _playQueue.insert(0, item);

      // 如果當前正在播放，停止並播放新廣告
      if (_state == PlaybackState.playing) {
        await _stopCurrentVideo();
        await _playNext();
      } else {
        await _playNext();
      }
    } else if (trigger == 'location_based' && campaignId != null) {
      // 處理位置相關的廣告
      _handleLocationBasedAd(item, campaignId);
    } else {
      print('📋 加入播放隊列: $advertisementName');
      // 普通廣告，加入隊列
      _playQueue.add(item);

      // 如果沒有正在播放，開始播放
      if (_state == PlaybackState.idle) {
        await _playNext();
      }
    }
  }

  /// 處理位置相關的廣告
  void _handleLocationBasedAd(PlaybackItem item, String campaignId) {
    // 更新最後收到位置廣告的時間
    _lastLocationAdReceivedTime = DateTime.now();

    // 如果是新的活動，清空舊的位置廣告
    if (_currentCampaignId != null && _currentCampaignId != campaignId) {
      print('🔄 檢測到新活動 ($campaignId)，清空舊的位置廣告');
      _clearLocationBasedAds();
    }

    // 檢查是否已經存在這個廣告（避免重複添加）
    final exists = _locationBasedAds.any(
      (ad) => ad.advertisementId == item.advertisementId,
    );

    if (exists) {
      print('⚠️ 位置廣告已存在，跳過: ${item.advertisementName}');
      return;
    }

    _currentCampaignId = campaignId;
    _locationBasedAds.add(item);
    print('📍 加入位置廣告循環列表: ${item.advertisementName}');
    print('   活動ID: $campaignId');
    print('   當前位置廣告數量: ${_locationBasedAds.length}');

    // 如果當前沒有在播放，或者正在播放本地影片，開始播放位置廣告
    if (_state == PlaybackState.idle ||
        (_currentItem != null &&
            _currentItem!.advertisementId.startsWith('local-'))) {
      _playNextLocationAd();
    }
  }

  /// 播放下一個位置廣告（循環）
  Future<void> _playNextLocationAd() async {
    if (_locationBasedAds.isEmpty) {
      print('⚠️ 位置廣告列表為空，播放本地影片');
      await _playNextLocalVideo();
      return;
    }

    final item = _locationBasedAds[_currentLocationAdIndex];
    _currentItem = item;
    onItemChanged?.call(item);

    print(
      '▶️ 播放位置廣告 (${_currentLocationAdIndex + 1}/${_locationBasedAds.length}): ${item.advertisementName}',
    );
    await _playVideo(item.videoFilename);

    // 移動到下一個位置廣告索引（循環）
    _currentLocationAdIndex =
        (_currentLocationAdIndex + 1) % _locationBasedAds.length;
  }

  /// 清空位置相關的廣告
  void _clearLocationBasedAds() {
    print('🗑️ 清空位置廣告列表 (${_locationBasedAds.length} 個)');
    _locationBasedAds.clear();
    _currentLocationAdIndex = 0;
    _currentCampaignId = null;
    _lastLocationAdReceivedTime = null;
  }

  /// 檢查並清理過期的位置廣告（如果超過一定時間沒有收到新的位置廣告）
  void checkAndClearExpiredLocationAds({
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (_locationBasedAds.isEmpty) {
      return;
    }

    if (_lastLocationAdReceivedTime == null) {
      return;
    }

    final now = DateTime.now();
    final timeSinceLastAd = now.difference(_lastLocationAdReceivedTime!);

    if (timeSinceLastAd > timeout) {
      print('⏰ 超過 ${timeout.inSeconds} 秒未收到位置廣告，清空位置廣告列表');
      clearLocationBasedAds();
    }
  }

  /// 清空所有位置相關的廣告（離開範圍時調用）
  void clearLocationBasedAds() {
    _clearLocationBasedAds();

    // 如果當前正在播放位置廣告，切換到本地影片
    if (_currentItem != null && _currentItem!.trigger == 'location_based') {
      if (_state == PlaybackState.playing) {
        // 播放下一個（會自動切換到本地影片）
        _playNext();
      }
    }
  }

  /// 開始自動播放（啟動時調用）
  Future<void> startAutoPlay() async {
    // 等待本地影片列表載入完成
    await Future.delayed(const Duration(milliseconds: 500));

    // 檢查是否有本地影片可播放
    if (_localVideoPlaylist.isNotEmpty) {
      print('✅ 開始循環播放本地影片');
      await _playNextLocalVideo();
    } else {
      print('⚠️ 沒有任何影片可播放，顯示歡迎畫面');
      _updateState(PlaybackState.idle);
    }
  }

  /// 播放下一個影片
  Future<void> _playNext() async {
    // 優先播放隊列中的廣告（非 location_based）
    if (_playQueue.isNotEmpty) {
      final item = _playQueue.removeAt(0);
      _currentItem = item;
      onItemChanged?.call(item);

      print('▶️ 播放隊列廣告: ${item.advertisementName}');
      await _playVideo(item.videoFilename);
      return;
    }

    // 播放位置相關的廣告（循環）
    if (_locationBasedAds.isNotEmpty) {
      await _playNextLocationAd();
      return;
    }

    // 如果隊列為空，播放本地影片
    if (_localVideoPlaylist.isNotEmpty) {
      print('📋 播放隊列為空，播放本地影片');
      await _playNextLocalVideo();
      return;
    }

    // 如果沒有任何影片，保持閒置狀態
    print('📋 沒有任何影片可播放');
    _updateState(PlaybackState.idle);
  }

  /// 播放下一個本地影片
  Future<void> _playNextLocalVideo() async {
    if (_localVideoPlaylist.isEmpty) {
      print('⚠️ 本地影片列表為空');
      _updateState(PlaybackState.idle);
      return;
    }

    // 循環播放本地影片
    final videoFilename = _localVideoPlaylist[_currentLocalVideoIndex];

    // 更新當前項目
    _currentItem = PlaybackItem(
      videoFilename: videoFilename,
      advertisementId: 'local-$_currentLocalVideoIndex',
      advertisementName: '本地影片: $videoFilename',
      isOverride: false,
    );
    onItemChanged?.call(_currentItem!);

    print(
      '▶️ 播放本地影片 (${_currentLocalVideoIndex + 1}/${_localVideoPlaylist.length}): $videoFilename',
    );
    await _playVideo(videoFilename);

    // 移動到下一個影片索引（循環）
    _currentLocalVideoIndex =
        (_currentLocalVideoIndex + 1) % _localVideoPlaylist.length;
  }

  /// 播放影片
  Future<void> _playVideo(
    String videoFilename, {
    bool isDefault = false,
  }) async {
    try {
      _updateState(PlaybackState.loading);

      // 檢查檔案是否存在（非預設影片）
      if (!isDefault) {
        final videoExists = await downloadManager.isVideoExists(videoFilename);
        if (!videoExists) {
          print('❌ 影片檔案不存在: $videoFilename');
          _updateState(PlaybackState.error);
          onError?.call('影片檔案不存在');

          // 播放下一個
          await _playNext();
          return;
        }
      }

      // 停止當前播放
      await _stopCurrentVideo();

      // 建立播放器
      VideoPlayerController controller;

      if (isDefault) {
        // 預設影片從 assets 載入（需要先添加到 pubspec.yaml）
        // 這裡假設預設影片放在 assets/videos/ 目錄
        controller = VideoPlayerController.asset(
          'assets/videos/$videoFilename',
        );
      } else {
        // 從本地檔案載入
        final videoPath = await downloadManager.getVideoPath(videoFilename);
        controller = VideoPlayerController.file(File(videoPath));
      }

      await controller.initialize();

      // 設置循環播放（僅預設影片）
      controller.setLooping(isDefault);

      // 監聽播放完成
      controller.addListener(() {
        if (controller.value.position == controller.value.duration &&
            controller.value.duration.inMilliseconds > 0) {
          _onVideoFinished();
        }
      });

      _currentController = controller;
      await controller.play();

      _updateState(PlaybackState.playing);
      print('✅ 開始播放: $videoFilename');
    } catch (e) {
      print('❌ 播放影片錯誤: $e');
      _updateState(PlaybackState.error);
      onError?.call('播放失敗: $e');

      // 嘗試播放下一個
      await _playNext();
    }
  }

  /// 影片播放完成
  Future<void> _onVideoFinished() async {
    print('✅ 影片播放完成');

    // 延遲 1 秒後播放下一個，避免過快切換
    await Future.delayed(const Duration(seconds: 1));
    await _playNext();
  }

  /// 停止當前影片
  Future<void> _stopCurrentVideo() async {
    if (_currentController != null) {
      await _currentController!.pause();
      await _currentController!.dispose();
      _currentController = null;
    }
  }

  /// 暫停播放
  Future<void> pause() async {
    if (_currentController != null && _state == PlaybackState.playing) {
      await _currentController!.pause();
      _updateState(PlaybackState.paused);
      print('⏸️ 已暫停');
    }
  }

  /// 恢復播放
  Future<void> resume() async {
    if (_currentController != null && _state == PlaybackState.paused) {
      await _currentController!.play();
      _updateState(PlaybackState.playing);
      print('▶️ 已恢復');
    }
  }

  /// 跳過當前影片
  Future<void> skip() async {
    print('⏭️ 跳過當前影片');
    await _playNext();
  }

  /// 更新狀態
  void _updateState(PlaybackState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(newState);
    }
  }

  /// 獲取播放隊列長度
  int get queueLength => _playQueue.length;

  /// 獲取播放隊列
  List<PlaybackItem> get queue => List.unmodifiable(_playQueue);

  /// 獲取本地影片播放列表
  List<String> get localVideoPlaylist => List.unmodifiable(_localVideoPlaylist);

  /// 獲取當前播放的本地影片索引
  int get currentLocalVideoIndex => _currentLocalVideoIndex;

  /// 獲取完整的播放列表（隊列 + 本地影片）
  List<PlaybackInfo> getFullPlaylist() {
    final playlist = <PlaybackInfo>[];

    // 當前正在播放的影片
    if (_currentItem != null) {
      playlist.add(
        PlaybackInfo(
          filename: _currentItem!.videoFilename,
          title: _currentItem!.advertisementName,
          isCurrentPlaying: true,
          isLocalVideo: _currentItem!.advertisementId.startsWith('local-'),
        ),
      );
    }

    // 播放隊列中的影片（非 location_based）
    for (var item in _playQueue) {
      playlist.add(
        PlaybackInfo(
          filename: item.videoFilename,
          title: item.advertisementName,
          isCurrentPlaying: false,
          isLocalVideo: false,
        ),
      );
    }

    // 位置相關的廣告（循環播放）
    for (var i = 0; i < _locationBasedAds.length; i++) {
      final item = _locationBasedAds[i];
      final isCurrentlyPlaying =
          _currentItem != null &&
          _currentItem!.trigger == 'location_based' &&
          _currentItem!.advertisementId == item.advertisementId;

      if (!isCurrentlyPlaying) {
        playlist.add(
          PlaybackInfo(
            filename: item.videoFilename,
            title: '${item.advertisementName} (位置廣告)',
            isCurrentPlaying: false,
            isLocalVideo: false,
          ),
        );
      }
    }

    // 本地影片列表（尚未播放的）
    for (var i = 0; i < _localVideoPlaylist.length; i++) {
      final filename = _localVideoPlaylist[i];
      final item = _currentItem;
      final isCurrentlyPlaying =
          item != null &&
          item.advertisementId.startsWith('local-') &&
          int.tryParse(item.advertisementId.replaceAll('local-', '')) == i;

      if (!isCurrentlyPlaying) {
        playlist.add(
          PlaybackInfo(
            filename: filename,
            title: '本地影片: $filename',
            isCurrentPlaying: false,
            isLocalVideo: true,
          ),
        );
      }
    }

    return playlist;
  }

  /// 刪除影片
  Future<bool> deleteVideo(String filename) async {
    try {
      final videoPath = await downloadManager.getVideoPath(filename);
      final file = File(videoPath);

      if (await file.exists()) {
        await file.delete();
        print('✅ 已刪除影片: $filename');

        // 刷新本地播放列表
        await refreshLocalPlaylist();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ 刪除影片失敗: $e');
      return false;
    }
  }

  /// 清理資源
  Future<void> dispose() async {
    await _stopCurrentVideo();
    _playQueue.clear();
    _updateState(PlaybackState.idle);
  }
}

/// 播放資訊
class PlaybackInfo {
  final String filename;
  final String title;
  final bool isCurrentPlaying;
  final bool isLocalVideo;

  PlaybackInfo({
    required this.filename,
    required this.title,
    required this.isCurrentPlaying,
    required this.isLocalVideo,
  });
}
