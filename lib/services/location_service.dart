import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../services/websocket_manager.dart';
import '../config/app_config.dart';

/// GPS 定位服務
class LocationService {
  final WebSocketManager webSocketManager;
  Timer? _locationTimer;
  Position? _currentPosition;
  bool _isRunning = false;
  StreamSubscription<Position>? _positionSubscription;

  // 位置確認追蹤
  DateTime? _lastLocationSentTime;
  DateTime? _lastLocationAckTime;
  int _sentCount = 0;
  int _ackCount = 0;

  // 事件回調
  Function(Position)? onLocationUpdate;
  Function(String)? onError;
  Function(DateTime)? onLocationAcknowledged;

  LocationService({required this.webSocketManager}) {
    // 監聽位置確認事件
    webSocketManager.onLocationAck = (data) {
      _lastLocationAckTime = DateTime.now();
      _ackCount++;
      print('✅ 後端確認收到位置 (#$_ackCount)');
      print('   確認時間: ${_lastLocationAckTime!.toString().substring(0, 19)}');

      if (_currentPosition != null) {
        print(
          '   當前位置: ${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
        );
      }

      if (data['message'] != null) {
        print('   後端訊息: ${data['message']}');
      }

      if (data['video_filename'] != null) {
        print('   推送影片: ${data['video_filename']}');
      }

      // 計算確認延遲
      if (_lastLocationSentTime != null) {
        final delay = _lastLocationAckTime!.difference(_lastLocationSentTime!);
        print('   確認延遲: ${delay.inMilliseconds}ms');
      }

      onLocationAcknowledged?.call(_lastLocationAckTime!);
    };
  }

  /// 當前位置
  Position? get currentPosition => _currentPosition;

  /// 是否正在運行
  bool get isRunning => _isRunning;

  /// 最後一次發送位置的時間
  DateTime? get lastLocationSentTime => _lastLocationSentTime;

  /// 最後一次收到位置確認的時間
  DateTime? get lastLocationAckTime => _lastLocationAckTime;

  /// 已發送的位置數量
  int get sentCount => _sentCount;

  /// 已確認的位置數量
  int get ackCount => _ackCount;

  /// 位置確認狀態（是否在合理時間內收到確認）
  bool get isLocationAcknowledged {
    if (_lastLocationSentTime == null || _lastLocationAckTime == null) {
      return false;
    }
    // 如果最後一次確認在最後一次發送之後，認為是正常的
    return _lastLocationAckTime!.isAfter(_lastLocationSentTime!);
  }

  /// 獲取位置確認統計資訊
  String getLocationAckStatus() {
    if (_lastLocationSentTime == null) {
      return '尚未發送位置';
    }

    if (_lastLocationAckTime == null) {
      final duration = DateTime.now().difference(_lastLocationSentTime!);
      return '等待確認中... (已等待 ${duration.inSeconds} 秒)';
    }

    if (_lastLocationAckTime!.isAfter(_lastLocationSentTime!)) {
      final duration = DateTime.now().difference(_lastLocationAckTime!);
      return '✅ 已確認 (${_durationToString(duration)}前)';
    } else {
      final duration = DateTime.now().difference(_lastLocationSentTime!);
      return '⏳ 等待確認 (${_durationToString(duration)}前發送)';
    }
  }

  String _durationToString(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}分${duration.inSeconds % 60}秒';
    }
    return '${duration.inSeconds}秒';
  }

  /// 開始位置服務
  Future<bool> start() async {
    if (_isRunning) {
      print('⚠️ 位置服務已在運行中');
      return true;
    }

    try {
      // 檢查位置服務是否啟用
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ 位置服務未啟用，請在設定中開啟位置服務');
        onError?.call('位置服務未啟用，請在設定中開啟位置服務');
        return false;
      }

      // 檢查權限狀態
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        print('📋 請求位置權限...');
        permission = await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          print('❌ 位置權限被拒絕');
          onError?.call('位置權限被拒絕，請在設定中允許位置權限');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ 位置權限被永久拒絕，請在設定中手動開啟');
        onError?.call('位置權限被永久拒絕，請在設定中手動開啟');
        return false;
      }

      print('✅ 位置權限已授予');
      _isRunning = true;

      // 獲取當前位置
      await _getCurrentLocation();

      // 開始定期發送位置更新
      _startLocationUpdates();

      // 監聽位置變化（移動時更新）
      _startLocationStream();

      return true;
    } catch (e) {
      print('❌ 啟動位置服務失敗: $e');
      _isRunning = false;
      onError?.call('啟動位置服務失敗: $e');
      return false;
    }
  }

  /// 停止位置服務
  void stop() {
    if (!_isRunning) {
      return;
    }

    _locationTimer?.cancel();
    _locationTimer = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isRunning = false;

    print('⏹️ 位置服務已停止');
  }

  /// 獲取當前位置
  Future<void> _getCurrentLocation() async {
    try {
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      if (_currentPosition != null) {
        // print('📍 當前位置:');
        // print('   緯度: ${_currentPosition!.latitude.toStringAsFixed(6)}');
        // print('   經度: ${_currentPosition!.longitude.toStringAsFixed(6)}');
        // print('   精度: ${_currentPosition!.accuracy.toStringAsFixed(0)} 米');
        // print('   海拔: ${_currentPosition!.altitude.toStringAsFixed(1)} 米');
        // print('   速度: ${_currentPosition!.speed.toStringAsFixed(1)} m/s');
        // print('   方位: ${_currentPosition!.heading.toStringAsFixed(0)}°');

        // 立即發送一次位置
        _sendLocationUpdate(_currentPosition!);
        onLocationUpdate?.call(_currentPosition!);
      }
    } catch (e) {
      print('❌ 獲取當前位置失敗: $e');
      onError?.call('獲取當前位置失敗: $e');
    }
  }

  /// 開始定期發送位置更新
  void _startLocationUpdates() {
    _locationTimer?.cancel();

    // 立即發送一次
    if (_currentPosition != null) {
      _sendLocationUpdate(_currentPosition!);
    }

    // 定期發送（根據配置的間隔）
    _locationTimer = Timer.periodic(AppConfig.locationUpdateInterval, (_) {
      if (_currentPosition != null) {
        _sendLocationUpdate(_currentPosition!);
      } else {
        // 如果沒有當前位置，嘗試獲取
        _getCurrentLocation();
      }
    });

    print('✅ 已啟動定期位置更新，間隔: ${AppConfig.locationUpdateInterval.inSeconds} 秒');
  }

  /// 監聽位置變化（移動時更新）
  void _startLocationStream() {
    _positionSubscription?.cancel();
    final positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: 10, // 移動 10 米才更新
      ),
    );

    _positionSubscription = positionStream.listen(
      (position) {
        _currentPosition = position;
        // print('📍 位置更新 (移動觸發):');
        // print('   緯度: ${position.latitude.toStringAsFixed(6)}');
        // print('   經度: ${position.longitude.toStringAsFixed(6)}');
        // print('   精度: ${position.accuracy.toStringAsFixed(0)} 米');
        // print('   海拔: ${position.altitude.toStringAsFixed(1)} 米');
        // print('   速度: ${position.speed.toStringAsFixed(1)} m/s');

        // 發送位置更新
        _sendLocationUpdate(position);
        onLocationUpdate?.call(position);
      },
      onError: (error) {
        final message = '位置監聽錯誤: $error';
        print('❌ $message');
        onError?.call(message);

        if (error is TimeoutException) {
          // 重新啟動位置串流，避免因超時而停止更新
          Future.delayed(const Duration(seconds: 1), () {
            if (_isRunning) {
              _startLocationStream();
            }
          });
        }
      },
    );

    print('✅ 已啟動位置變化監聽');
  }

  /// 發送位置更新到伺服器
  void _sendLocationUpdate(Position position) {
    if (!webSocketManager.isConnected) {
      print('⚠️ WebSocket 未連接，無法發送位置更新');
      return;
    }

    _lastLocationSentTime = DateTime.now();
    _sentCount++;

    // print('📤 發送位置 #$_sentCount:');
    // print('   緯度: ${position.latitude.toStringAsFixed(6)}');
    // print('   經度: ${position.longitude.toStringAsFixed(6)}');
    // print('   精度: ${position.accuracy.toStringAsFixed(0)} 米');
    // print('   海拔: ${position.altitude.toStringAsFixed(1)} 米');
    // print('   速度: ${position.speed.toStringAsFixed(1)} m/s');
    // print('   時間: ${_lastLocationSentTime!.toString().substring(0, 19)}');

    webSocketManager.sendLocationUpdate(position.longitude, position.latitude);
  }

  /// 手動發送當前位置
  Future<void> sendCurrentLocation() async {
    if (_currentPosition != null) {
      _sendLocationUpdate(_currentPosition!);
    } else {
      await _getCurrentLocation();
    }
  }

  /// 獲取位置資訊字串
  String getLocationInfo() {
    if (_currentPosition == null) {
      return '位置未知';
    }

    return '緯度: ${_currentPosition!.latitude.toStringAsFixed(6)}\n'
        '經度: ${_currentPosition!.longitude.toStringAsFixed(6)}\n'
        '精度: ${_currentPosition!.accuracy.toStringAsFixed(0)} 米';
  }

  /// 獲取詳細的位置和確認狀態
  Map<String, dynamic> getLocationStatus() {
    return {
      'currentPosition': _currentPosition != null
          ? {
              'latitude': _currentPosition!.latitude,
              'longitude': _currentPosition!.longitude,
              'accuracy': _currentPosition!.accuracy,
            }
          : null,
      'lastSentTime': _lastLocationSentTime?.toIso8601String(),
      'lastAckTime': _lastLocationAckTime?.toIso8601String(),
      'sentCount': _sentCount,
      'ackCount': _ackCount,
      'isAcknowledged': isLocationAcknowledged,
      'status': getLocationAckStatus(),
    };
  }

  /// 清理資源
  void dispose() {
    stop();
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }
}
