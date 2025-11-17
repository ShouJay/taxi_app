import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/app_config.dart';
import '../models/play_ad_command.dart';

/// WebSocket 管理器
class WebSocketManager {
  IO.Socket? _socket;
  String deviceId;
  final String serverUrl;

  // 連接狀態
  bool get isConnected => _socket?.connected ?? false;
  bool get isRegistered => isConnected && _isRegistered;

  bool _isRegistered = false;

  // 事件回調
  Function(PlayAdCommand)? onPlayAdCommand;
  Function(DownloadVideoCommand)? onDownloadVideoCommand;
  Function()? onConnected;
  Function()? onDisconnected;
  Function(String)? onRegistrationSuccess;
  Function(String)? onRegistrationError;
  Function(Map<String, dynamic>)? onLocationAck;
  Function(String, List<dynamic>)? onStartCampaignPlayback;
  Function()? onRevertToLocalPlaylist;

  // 定時器
  Timer? _heartbeatTimer;
  Timer? _locationTimer;

  WebSocketManager({required this.deviceId, required this.serverUrl});

  /// 連接到 WebSocket 伺服器
  void connect() {
    _isRegistered = false;
    _socket = IO.io(
      serverUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    // 設置事件監聽
    _setupEventListeners();

    // 連接
    _socket!.connect();
  }

  /// 設置所有事件監聽器
  void _setupEventListeners() {
    // 連接事件
    _socket!.onConnect((_) {
      print('✅ 已連接到伺服器');
      _isRegistered = false;
      _registerDevice();
      _startHeartbeat();
      onConnected?.call();
    });

    _socket!.onDisconnect((_) {
      print('❌ 已斷開連接');
      _isRegistered = false;
      _stopHeartbeat();
      _stopLocationUpdates();
      onDisconnected?.call();

      // 5秒後自動重連
      Future.delayed(AppConfig.reconnectDelay, () {
        if (!isConnected) {
          print('🔄 嘗試重新連接...');
          connect();
        }
      });
    });

    _socket!.onError((error) {
      print('❌ WebSocket 錯誤: $error');
    });

    // 伺服器事件
    _socket!.on('connection_established', _onConnectionEstablished);
    _socket!.on('registration_success', _onRegistrationSuccess);
    _socket!.on('registration_error', _onRegistrationError);
    _socket!.on('play_ad', _onPlayAd);
    _socket!.on('location_ack', _onLocationAck);
    _socket!.on('heartbeat_ack', _onHeartbeatAck);
    _socket!.on('download_video', _onDownloadVideo);
    _socket!.on('download_status_ack', _onDownloadStatusAck);
    _socket!.on('force_disconnect', _onForceDisconnect);
    _socket!.on('start_campaign_playback', _onStartCampaignPlayback);
    _socket!.on('revert_to_local_playlist', _onRevertToLocalPlaylist);
  }

  /// 註冊設備
  void _registerDevice() {
    if (!isConnected) return;

    print('📝 註冊設備: $deviceId');
    _socket!.emit('register', {'device_id': deviceId});
  }

  /// 發送位置更新
  void sendLocationUpdate(double longitude, double latitude) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送位置');
      return;
    }

    // 驗證經緯度範圍
    if (longitude < -180 || longitude > 180) {
      print('❌ 經度超出範圍: $longitude (應為 -180 到 180)');
      return;
    }

    if (latitude < -90 || latitude > 90) {
      print('❌ 緯度超出範圍: $latitude (應為 -90 到 90)');
      return;
    }

    // 發送位置更新事件
    _socket!.emit('location_update', {
      'device_id': deviceId, // 必填：設備ID，字串
      'longitude': longitude, // 必填：經度，數字，範圍 -180 到 180
      'latitude': latitude, // 必填：緯度，數字，範圍 -90 到 90
      'timestamp': DateTime.now().toIso8601String(), // 選填：時間戳
    });

    print('📍 發送位置: ($latitude, $longitude)');
  }

  /// 發送心跳
  void sendHeartbeat() {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送心跳');
      return;
    }

    _socket!.emit('heartbeat', {'device_id': deviceId});
    print('💓 發送心跳');
  }

  /// 發送下載狀態
  void sendDownloadStatus({
    required String advertisementId,
    required String status,
    required int progress,
    required List<int> downloadedChunks,
    required int totalChunks,
    String? errorMessage,
  }) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送下載狀態');
      return;
    }

    _socket!.emit('download_status', {
      'device_id': deviceId,
      'advertisement_id': advertisementId,
      'status': status,
      'progress': progress,
      'downloaded_chunks': downloadedChunks,
      'total_chunks': totalChunks,
      'error_message': errorMessage,
    });

    print('📊 發送下載狀態: $advertisementId - $status ($progress%)');
  }

  /// 發送下載請求
  void sendDownloadRequest(String advertisementId) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送下載請求');
      return;
    }

    _socket!.emit('download_request', {
      'device_id': deviceId,
      'advertisement_id': advertisementId,
    });

    print('📥 請求下載: $advertisementId');
  }

  void _emitPlaybackEvent(String event, Map<String, dynamic> payload) {
    if (!isConnected) {
      print('⚠️ 未連接，無法發送 $event');
      return;
    }

    final data = {
      'device_id': deviceId,
      'event': event,
      'timestamp': DateTime.now().toIso8601String(),
      ...payload,
    };

    _socket!.emit(event, data);
    print('📡 發送 $event: $data');
  }

  void sendPlaybackStarted({
    required String mode,
    required String advertisementId,
    required String videoFilename,
    String? campaignId,
    String? trigger,
    int? playlistIndex,
    int? playlistLength,
  }) {
    final payload = <String, dynamic>{
      'mode': mode,
      'advertisement_id': advertisementId,
      'video_filename': videoFilename,
    };

    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }

    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }

    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }

    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }

    _emitPlaybackEvent('playback_started', payload);
  }

  void sendPlaybackCompleted({
    required String mode,
    required String advertisementId,
    required String videoFilename,
    String? campaignId,
    String? trigger,
    int? playlistIndex,
    int? playlistLength,
    int? nextPlaylistIndex,
    Duration? playbackDuration,
  }) {
    final payload = <String, dynamic>{
      'mode': mode,
      'advertisement_id': advertisementId,
      'video_filename': videoFilename,
    };

    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }

    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }

    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }

    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }

    if (nextPlaylistIndex != null) {
      payload['next_playlist_index'] = nextPlaylistIndex;
    }

    if (playbackDuration != null) {
      payload['playback_duration_ms'] = playbackDuration.inMilliseconds;
    }

    _emitPlaybackEvent('playback_completed', payload);
  }

  void sendPlaybackModeChange({
    required String mode,
    String? campaignId,
    String? reason,
    String? previousMode,
  }) {
    final payload = <String, dynamic>{'mode': mode};

    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }

    if (reason != null && reason.isNotEmpty) {
      payload['reason'] = reason;
    }

    if (previousMode != null && previousMode.isNotEmpty) {
      payload['previous_mode'] = previousMode;
    }

    _emitPlaybackEvent('playback_mode_change', payload);
  }

  /// 開始心跳
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(AppConfig.heartbeatInterval, (_) {
      sendHeartbeat();
    });
  }

  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 開始位置更新
  void startLocationUpdates(double longitude, double latitude) {
    _stopLocationUpdates();

    // 立即發送一次
    sendLocationUpdate(longitude, latitude);

    // 定期發送
    _locationTimer = Timer.periodic(AppConfig.locationUpdateInterval, (_) {
      sendLocationUpdate(longitude, latitude);
    });
  }

  /// 停止位置更新
  void _stopLocationUpdates() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  // === 事件處理 ===

  void _onConnectionEstablished(dynamic data) {
    print('📡 連接建立: ${data['message']}');
    print('   Session ID: ${data['sid']}');
  }

  void _onRegistrationSuccess(dynamic data) {
    print('✅ 註冊成功: ${data['message']}');
    print('   設備類型: ${data['device_type']}');
    _isRegistered = true;
    onRegistrationSuccess?.call(data['message'] as String);
  }

  void _onRegistrationError(dynamic data) {
    print('❌ 註冊失敗: ${data['error']}');
    _isRegistered = false;
    onRegistrationError?.call(data['error'] as String);
  }

  void _onPlayAd(dynamic data) {
    print('🎬 收到播放廣告命令 (後端推送)');
    print('   原始數據: $data');

    try {
      final command = PlayAdCommand.fromJson(data as Map<String, dynamic>);
      print('   影片檔名: ${command.videoFilename}');
      print('   廣告ID: ${command.advertisementId}');
      print('   廣告名稱: ${command.advertisementName}');
      print('   觸發: ${command.trigger}');
      print('   優先級: ${command.priority}');

      // 檢查是否缺少必要字段
      if (command.advertisementId == 'unknown') {
        print('   ⚠️ 警告：後端未提供 advertisement_id');
      }

      onPlayAdCommand?.call(command);
    } catch (e, stackTrace) {
      print('❌ 解析播放命令失敗: $e');
      print('錯誤堆疊: $stackTrace');
    }
  }

  void _onLocationAck(dynamic data) {
    print('✅ 位置更新確認: ${data['message']}');
    if (data['video_filename'] != null) {
      print('   推送影片: ${data['video_filename']}');
    }

    // 觸發位置確認回調
    onLocationAck?.call(data as Map<String, dynamic>);
  }

  void _onHeartbeatAck(dynamic data) {
    // 心跳確認（靜默處理，避免過多日誌）
  }

  void _onDownloadVideo(dynamic data) {
    print('📥 收到下載命令');
    print('   廣告ID: ${data['advertisement_id']}');
    print('   檔案: ${data['video_filename']}');
    print('   大小: ${data['file_size']} bytes');
    print('   分片數: ${data['total_chunks']}');

    try {
      final command = DownloadVideoCommand.fromJson(
        data as Map<String, dynamic>,
      );
      onDownloadVideoCommand?.call(command);
    } catch (e) {
      print('❌ 解析下載命令失敗: $e');
    }
  }

  void _onDownloadStatusAck(dynamic data) {
    print('📊 下載狀態確認: ${data['message']}');
  }

  void _onForceDisconnect(dynamic data) {
    print('⚠️ 伺服器強制斷開: ${data['reason']}');
    disconnect();
  }

  void _onStartCampaignPlayback(dynamic data) {
    final campaignId = data is Map<String, dynamic>
        ? data['campaign_id'] as String? ?? ''
        : '';
    final playlist = data is Map<String, dynamic>
        ? (data['playlist'] as List<dynamic>? ?? [])
        : const [];

    if (campaignId.isEmpty) {
      print('⚠️ 收到活動播放命令但缺少 campaign_id: $data');
      return;
    }

    print('🎬 收到活動播放命令: $campaignId (項目: ${playlist.length})');
    onStartCampaignPlayback?.call(campaignId, playlist);
  }

  void _onRevertToLocalPlaylist(dynamic data) {
    print('🏠 收到切換回本地播放命令');
    onRevertToLocalPlaylist?.call();
  }

  void sendPlaybackError({
    required String error,
    required String videoFilename,
    String? campaignId,
    String? advertisementId,
    String mode = 'unknown',
    int? playlistIndex,
    int? playlistLength,
    String? trigger,
  }) {
    final payload = <String, dynamic>{
      'error': error,
      'video_filename': videoFilename,
      'mode': mode,
      'advertisement_id': advertisementId ?? 'unknown',
    };

    if (campaignId != null && campaignId.isNotEmpty) {
      payload['campaign_id'] = campaignId;
    }

    if (playlistIndex != null) {
      payload['playlist_index'] = playlistIndex;
    }

    if (playlistLength != null) {
      payload['playlist_length'] = playlistLength;
    }

    if (trigger != null && trigger.isNotEmpty) {
      payload['trigger'] = trigger;
    }

    _emitPlaybackEvent('playback_error', payload);
  }

  /// 更新設備 ID
  void updateDeviceId(String newDeviceId) {
    deviceId = newDeviceId;
    if (isConnected) {
      // 重新連接以使用新的設備 ID
      _isRegistered = false;
      disconnect();
      Future.delayed(const Duration(seconds: 1), () {
        connect();
      });
    }
  }

  /// 斷開連接
  void disconnect() {
    _stopHeartbeat();
    _stopLocationUpdates();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isRegistered = false;
    print('🔌 已斷開連接');
  }

  /// 清理資源
  void dispose() {
    disconnect();
  }
}
