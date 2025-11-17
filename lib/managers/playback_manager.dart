import 'dart:async';
import 'dart:io';
import 'package:video_player/video_player.dart';
import '../services/download_manager.dart';
import '../services/websocket_manager.dart';

/// 播放項目
class PlaybackItem {
  final String videoFilename;
  final String advertisementId;
  final String advertisementName;
  final String trigger;
  final String? campaignId;
  final bool isOverride;
  final DateTime addedAt;

  PlaybackItem({
    required this.videoFilename,
    required this.advertisementId,
    required this.advertisementName,
    required this.trigger,
    this.campaignId,
    this.isOverride = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();
}

/// 播放狀態
enum PlaybackState { idle, loading, playing, paused, error }

/// 播放模式
enum PlaybackMode { local, campaign }

/// 播放資訊（用於顯示播放列表）
class PlaybackInfo {
  final String filename;
  final String title;
  final bool isCurrentPlaying;
  final bool isLocalVideo;
  final String? advertisementId;

  PlaybackInfo({
    required this.filename,
    required this.title,
    required this.isCurrentPlaying,
    required this.isLocalVideo,
    this.advertisementId,
  });
}

/// 播放管理器
class PlaybackManager {
  // 依賴服務
  final DownloadManager downloadManager;
  final WebSocketManager webSocketManager;

  // 當前播放控制器
  VideoPlayerController? _currentController;

  // 播放狀態
  PlaybackState _state = PlaybackState.idle;
  PlaybackMode _playbackMode = PlaybackMode.local;

  // 播放隊列（用於插入廣告、覆蓋播放等）
  final List<PlaybackItem> _queue = [];

  // 當前播放項目
  PlaybackItem? _currentItem;

  // 本地播放列表（循環播放用）
  List<PlaybackItem> _localPlaylist = [];
  int _localPlaylistIndex = 0;

  // 活動播放列表
  List<PlaybackItem>? _campaignPlaylist;
  int _campaignPlaylistIndex = 0;
  String? _activeCampaignId;

  // 位置觸發的廣告（追蹤最後一次位置觸發的廣告，用於過期清理）
  final Map<String, DateTime> _locationBasedAds = {};

  // 播放啟用狀態
  bool _isPlaybackEnabled = true;

  // 狀態監聽器
  Function(PlaybackState)? onStateChanged;
  Function(PlaybackItem?)? onItemChanged;
  Function(bool)? onPlaybackEnabledChanged;

  // 內部狀態
  bool _isDisposed = false;
  bool _playbackCompletedHandled = false; // 防止重複處理播放完成

  // 播放配置
  static const Duration _errorRetryDelay = Duration(seconds: 2);

  PlaybackManager({
    required this.downloadManager,
    required this.webSocketManager,
  });

  // Getters
  VideoPlayerController? get controller => _currentController;
  PlaybackState get state => _state;
  PlaybackMode get playbackMode => _playbackMode;
  PlaybackItem? get currentItem => _currentItem;
  int get queueLength => _queue.length;
  bool get isPlaybackEnabled => _isPlaybackEnabled;
  String? get activeCampaignId => _activeCampaignId;

  /// 初始化並開始自動播放
  Future<void> startAutoPlay() async {
    if (_isDisposed) return;

    print('🎬 開始自動播放...');

    // 設置為本地循環播放模式
    _playbackMode = PlaybackMode.local;
    _localPlaylistIndex = 0;

    await refreshLocalPlaylist();

    if (_localPlaylist.isNotEmpty) {
      print('✅ 找到 ${_localPlaylist.length} 個本地影片，開始循環播放');
      await _playNext();
    } else {
      print('⚠️ 沒有找到本地影片');
      _setState(PlaybackState.idle);
    }
  }

  /// 刷新本地播放列表
  Future<void> refreshLocalPlaylist() async {
    try {
      final videoFilenames = await downloadManager.getAllDownloadedVideos();

      _localPlaylist = videoFilenames
          .map(
            (filename) => PlaybackItem(
              videoFilename: filename,
              advertisementId: 'local-$filename',
              advertisementName: filename,
              trigger: 'local_loop',
            ),
          )
          .toList();

      print('📋 本地播放列表已刷新: ${_localPlaylist.length} 個影片');
    } catch (e) {
      print('❌ 刷新本地播放列表失敗: $e');
      _localPlaylist = [];
    }
  }

  /// 插入廣告到播放隊列
  Future<void> insertAd({
    required String videoFilename,
    required String advertisementId,
    required String advertisementName,
    required String trigger,
    String? campaignId,
    bool isOverride = false,
  }) async {
    if (_isDisposed) return;

    final item = PlaybackItem(
      videoFilename: videoFilename,
      advertisementId: advertisementId,
      advertisementName: advertisementName,
      trigger: trigger,
      campaignId: campaignId,
      isOverride: isOverride,
    );

    // 覆蓋播放：立即清除隊列並播放
    if (isOverride) {
      print('🚨 覆蓋播放: $advertisementName');
      _queue.clear();
      _queue.add(item);
      // 如果正在 loading，等待完成後再播放
      if (_state == PlaybackState.loading) {
        // 將覆蓋項目加入隊列，等待當前 loading 完成
        return;
      }
      await _playNext();
      return;
    }

    // 位置觸發的廣告：記錄時間戳
    if (trigger == 'location_based') {
      _locationBasedAds[advertisementId] = DateTime.now();
    }

    // 一般插入到隊列
    _queue.add(item);
    print('📥 廣告已加入隊列: $advertisementName (隊列長度: ${_queue.length})');

    // 如果當前沒有在播放，立即播放（但不要在 loading 時打斷）
    if (_state == PlaybackState.idle || _state == PlaybackState.error) {
      await _playNext();
    }
    // loading 狀態時，不執行播放，等待當前載入完成
  }

  /// 開始活動播放
  Future<void> startCampaignPlayback({
    required String campaignId,
    required List<PlaybackItem> playlist,
  }) async {
    if (_isDisposed || playlist.isEmpty) return;

    print('🎬 開始活動播放: $campaignId (${playlist.length} 個影片)');

    _campaignPlaylist = playlist;
    _campaignPlaylistIndex = 0;
    _activeCampaignId = campaignId;
    _playbackMode = PlaybackMode.campaign;

    // 清空一般隊列，活動播放優先
    _queue.clear();

    // 開始播放活動列表的第一個影片
    await _playCampaignItem();
  }

  /// 恢復到本地播放
  Future<void> revertToLocalPlayback() async {
    if (_isDisposed) return;

    print('🏠 恢復到本地播放');

    _campaignPlaylist = null;
    _campaignPlaylistIndex = 0;
    _activeCampaignId = null;
    _playbackMode = PlaybackMode.local;
    // 重置本地播放索引，從頭開始循環
    _localPlaylistIndex = 0;

    // 停止當前播放
    await _stopCurrentVideo();

    // 確保本地播放列表是最新的
    await refreshLocalPlaylist();

    // 開始本地播放
    if (_localPlaylist.isNotEmpty) {
      print('✅ 恢復到本地循環播放，列表有 ${_localPlaylist.length} 個影片');
      await _playNext();
    } else {
      print('⚠️ 本地播放列表為空');
      _setState(PlaybackState.idle);
    }
  }

  /// 檢查並清理過期的位置廣告
  void checkAndClearExpiredLocationAds({required Duration timeout}) {
    final now = DateTime.now();
    final expiredAds = <String>[];

    _locationBasedAds.forEach((adId, timestamp) {
      if (now.difference(timestamp) > timeout) {
        expiredAds.add(adId);
      }
    });

    if (expiredAds.isNotEmpty) {
      print('🗑️ 清理過期位置廣告: ${expiredAds.length} 個');
      for (final adId in expiredAds) {
        _locationBasedAds.remove(adId);
        // 從隊列中移除過期的位置廣告
        _queue.removeWhere(
          (item) =>
              item.advertisementId == adId && item.trigger == 'location_based',
        );
      }
    }
  }

  /// 設置播放啟用狀態
  Future<void> setPlaybackEnabled(bool enabled) async {
    if (_isDisposed) return;

    _isPlaybackEnabled = enabled;
    onPlaybackEnabledChanged?.call(enabled);

    // 如果正在 loading，不要改變狀態，等待載入完成
    if (_state == PlaybackState.loading) {
      print('⏳ 正在載入中，等待載入完成後再改變播放狀態');
      return;
    }

    if (!enabled) {
      // 停用：暫停當前播放
      await pause();
    } else {
      // 啟用：恢復播放或開始播放
      if (_state == PlaybackState.paused) {
        await resume();
      } else if (_state == PlaybackState.idle) {
        await _playNext();
      }
    }
  }

  /// 暫停播放
  Future<void> pause() async {
    if (_isDisposed || _currentController == null) return;

    // 如果正在 loading，不要暫停，等待載入完成
    if (_state == PlaybackState.loading) {
      print('⏳ 正在載入中，無法暫停');
      return;
    }

    if (_state == PlaybackState.playing) {
      await _currentController!.pause();
      _setState(PlaybackState.paused);
    }
  }

  /// 恢復播放
  Future<void> resume() async {
    if (_isDisposed || _currentController == null) return;

    // 如果正在 loading，不要恢復，等待載入完成
    if (_state == PlaybackState.loading) {
      print('⏳ 正在載入中，無法恢復播放');
      return;
    }

    if (_state == PlaybackState.paused && _isPlaybackEnabled) {
      await _currentController!.play();
      _setState(PlaybackState.playing);
    }
  }

  /// 播放活動列表中的項目
  Future<void> _playCampaignItem() async {
    if (_isDisposed || _campaignPlaylist == null) {
      return;
    }

    // 如果索引超出範圍，循環播放（重置索引）
    if (_campaignPlaylistIndex >= _campaignPlaylist!.length) {
      _campaignPlaylistIndex = 0;
      print('🔄 活動播放列表循環，回到第一個影片');
    }

    final item = _campaignPlaylist![_campaignPlaylistIndex];
    await _playItem(item);
  }

  /// 播放下一個項目
  Future<void> _playNext() async {
    if (_isDisposed || !_isPlaybackEnabled) return;

    // 如果正在 loading，不要執行新的播放操作
    if (_state == PlaybackState.loading) {
      print('⏳ 正在載入中，等待載入完成...');
      return;
    }

    // 優先播放隊列中的項目
    if (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      await _playItem(item);
      return;
    }

    // 活動播放模式：播放活動列表
    if (_playbackMode == PlaybackMode.campaign && _campaignPlaylist != null) {
      await _playCampaignItem();
      return;
    }

    // 本地播放模式：循環播放本地列表
    if (_localPlaylist.isNotEmpty) {
      // 確保索引在有效範圍內（使用模運算實現循環）
      _localPlaylistIndex = _localPlaylistIndex % _localPlaylist.length;
      final item = _localPlaylist[_localPlaylistIndex];
      final currentIndex = _localPlaylistIndex;
      _localPlaylistIndex++; // 準備播放下一個

      print(
        '📺 播放本地影片 [${currentIndex + 1}/${_localPlaylist.length}]: ${item.advertisementName}',
      );
      print('   模式: $_playbackMode, 下一個索引: $_localPlaylistIndex');
      await _playItem(item);
      return;
    }

    print('⚠️ 本地播放列表為空，無法播放');

    // 沒有可播放的項目
    _setState(PlaybackState.idle);
  }

  /// 播放指定項目
  Future<void> _playItem(PlaybackItem item) async {
    if (_isDisposed) return;

    // 如果已經在 loading 狀態，不要重複執行
    if (_state == PlaybackState.loading) {
      print('⏳ 正在載入中，跳過新的播放請求');
      return;
    }

    print('▶️ 播放影片: ${item.advertisementName} (${item.videoFilename})');

    // 檢查影片是否存在
    final exists = await downloadManager.isVideoExists(item.videoFilename);
    if (!exists) {
      print('❌ 影片不存在: ${item.videoFilename}');
      _setState(PlaybackState.error);

      // 延遲後嘗試播放下一個
      Future.delayed(_errorRetryDelay, () {
        if (!_isDisposed) {
          _playNext();
        }
      });
      return;
    }

    // 獲取影片路徑
    final videoPath = await downloadManager.getVideoPath(item.videoFilename);

    // 停止當前播放
    await _stopCurrentVideo();

    // 設置狀態為載入中
    _setState(PlaybackState.loading);
    _setCurrentItem(item);

    try {
      // 創建新的播放控制器
      final controller = VideoPlayerController.file(File(videoPath));

      // 初始化控制器
      await controller.initialize();

      // 本地循環播放：單個影片不循環，讓列表循環（通過播放完成後播放下一個實現）
      // 這樣可以實現：影片1 → 影片2 → ... → 影片N → 影片1 → ... 的循環效果
      // 如果設置單個影片循環，會導致同一個影片重複播放，無法切換到下一個
      controller.setLooping(false);

      // 設置音量
      await controller.setVolume(1.0);

      // 保存控制器
      _currentController = controller;

      // 重置播放完成標記
      _playbackCompletedHandled = false;

      // 監聽播放完成事件
      controller.addListener(_onVideoControllerUpdate);

      // 開始播放
      if (_isPlaybackEnabled) {
        await controller.play();
        _setState(PlaybackState.playing);
        print('✅ 影片播放開始: ${item.advertisementName}');
        print('   時長: ${controller.value.duration.inSeconds}s');

        // loading 完成後，檢查隊列中是否有待播放項目（特別是覆蓋播放）
        // 如果隊列中有項目，但當前項目不是覆蓋播放，則繼續播放當前項目
        // 覆蓋播放會在下一個週期自動處理
      } else {
        _setState(PlaybackState.paused);
      }
    } catch (e) {
      print('❌ 播放影片失敗: $e');
      _setState(PlaybackState.error);
      _currentController?.dispose();
      _currentController = null;

      // 延遲後嘗試播放下一個
      Future.delayed(_errorRetryDelay, () {
        if (!_isDisposed) {
          _playNext();
        }
      });
    }
  }

  /// 視頻控制器更新監聽
  void _onVideoControllerUpdate() {
    if (_isDisposed || _currentController == null) return;

    final controller = _currentController!;
    final value = controller.value;

    // 檢查錯誤
    if (value.hasError) {
      print('❌ 播放器錯誤: ${value.errorDescription}');
      _setState(PlaybackState.error);

      // 延遲後嘗試播放下一個
      Future.delayed(_errorRetryDelay, () {
        if (!_isDisposed) {
          _playNext();
        }
      });
      return;
    }

    // 檢查播放完成（使用播放器狀態判定）
    // 防止重複處理
    if (_playbackCompletedHandled) {
      return;
    }

    // 使用播放器狀態判定播放完成：
    // 1. 不是循環播放
    // 2. 影片已初始化且有有效的時長
    // 3. 播放器已停止播放（isPlaying == false）
    // 4. 位置達到或接近結尾（確認是自然播放完成，而非手動暫停）
    if (!value.isLooping &&
        value.isInitialized &&
        value.duration > Duration.zero &&
        !value.isPlaying) {
      // 確認是播放完成而非暫停：位置必須達到總時長的 90% 以上
      final position = value.position;
      final duration = value.duration;
      final isNearEnd = position >= duration * 0.9;

      if (isNearEnd) {
        // 防止重複觸發
        _playbackCompletedHandled = true;

        print('✅ 影片播放完成（狀態判定）: ${_currentItem?.advertisementName}');
        print('   播放狀態: 已停止');
        print('   位置: ${position.inSeconds}s / 總時長: ${duration.inSeconds}s');
        print(
          '   播放進度: ${((position.inMilliseconds / duration.inMilliseconds) * 100).toStringAsFixed(1)}%',
        );

        // 移除監聽器，避免重複觸發
        controller.removeListener(_onVideoControllerUpdate);

        // 播放完成後，繼續播放下一個
        Future.delayed(const Duration(milliseconds: 100), () {
          if (!_isDisposed) {
            // 如果是活動播放，移動到下一個
            if (_playbackMode == PlaybackMode.campaign &&
                _campaignPlaylist != null) {
              _campaignPlaylistIndex++;
              _playCampaignItem();
            } else {
              // 本地循環模式或其他模式：播放下一個
              // _playNext() 會自動處理本地列表的循環（索引會自動重置）
              print('🔄 播放完成，準備播放下一個（模式: $_playbackMode）');
              _playNext();
            }
          }
        });
        return;
      }
    }
  }

  /// 停止當前播放
  Future<void> _stopCurrentVideo() async {
    if (_currentController == null) return;

    try {
      // 移除監聽器
      _currentController!.removeListener(_onVideoControllerUpdate);
      await _currentController!.pause();
      await _currentController!.dispose();
    } catch (e) {
      print('⚠️ 停止播放時發生錯誤: $e');
    } finally {
      _currentController = null;
      // 重置播放完成標記
      _playbackCompletedHandled = false;
    }
  }

  /// 設置播放狀態
  void _setState(PlaybackState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(_state);
    }
  }

  /// 設置當前播放項目
  void _setCurrentItem(PlaybackItem? item) {
    if (_currentItem?.advertisementId != item?.advertisementId) {
      _currentItem = item;
      onItemChanged?.call(_currentItem);
    }
  }

  /// 獲取完整播放列表（用於顯示）
  List<PlaybackInfo> getFullPlaylist() {
    final List<PlaybackInfo> playlist = [];

    // 添加隊列中的項目
    for (var item in _queue) {
      playlist.add(
        PlaybackInfo(
          filename: item.videoFilename,
          title: item.advertisementName,
          isCurrentPlaying: false,
          isLocalVideo: false,
          advertisementId: item.advertisementId,
        ),
      );
    }

    // 添加活動播放列表
    if (_campaignPlaylist != null) {
      for (var i = 0; i < _campaignPlaylist!.length; i++) {
        final item = _campaignPlaylist![i];
        final isCurrent =
            i == _campaignPlaylistIndex &&
            _currentItem?.advertisementId == item.advertisementId;
        playlist.add(
          PlaybackInfo(
            filename: item.videoFilename,
            title: item.advertisementName,
            isCurrentPlaying: isCurrent,
            isLocalVideo: false,
            advertisementId: item.advertisementId,
          ),
        );
      }
    }

    // 添加本地播放列表
    for (var i = 0; i < _localPlaylist.length; i++) {
      final item = _localPlaylist[i];
      final isCurrent =
          _playbackMode == PlaybackMode.local &&
          i == (_localPlaylistIndex - 1) % _localPlaylist.length &&
          _currentItem?.advertisementId == item.advertisementId;
      playlist.add(
        PlaybackInfo(
          filename: item.videoFilename,
          title: item.advertisementName,
          isCurrentPlaying: isCurrent,
          isLocalVideo: true,
          advertisementId: item.advertisementId,
        ),
      );
    }

    return playlist;
  }

  /// 刪除影片
  Future<bool> deleteVideo(String filename) async {
    try {
      // 獲取影片路徑
      final videoPath = await downloadManager.getVideoPath(filename);
      final file = File(videoPath);

      // 檢查檔案是否存在
      if (!await file.exists()) {
        print('⚠️ 影片不存在: $filename');
        return false;
      }

      // 如果正在播放這個影片，先停止
      if (_currentItem?.videoFilename == filename) {
        await _stopCurrentVideo();
        _setCurrentItem(null);
        _setState(PlaybackState.idle);
      }

      // 從本地播放列表中移除
      _localPlaylist.removeWhere((item) => item.videoFilename == filename);

      // 刪除檔案
      await file.delete();
      print('✅ 影片已刪除: $filename');

      // 如果當前沒有播放，嘗試播放下一個
      if (_state == PlaybackState.idle && _localPlaylist.isNotEmpty) {
        await _playNext();
      }

      return true;
    } catch (e) {
      print('❌ 刪除影片失敗: $e');
      return false;
    }
  }

  /// 清理資源
  void dispose() {
    if (_isDisposed) return;

    print('🗑️ 清理播放管理器...');
    _isDisposed = true;

    // 停止並釋放控制器
    _stopCurrentVideo();

    // 清空列表
    _queue.clear();
    _localPlaylist.clear();
    _campaignPlaylist = null;
    _locationBasedAds.clear();

    print('✅ 播放管理器已清理');
  }
}
