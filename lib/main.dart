import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'services/websocket_manager.dart';
import 'services/download_manager.dart';
import 'services/location_service.dart';
import 'managers/playback_manager.dart';
import 'screens/main_screen.dart';
import 'screens/settings_screen.dart';
import 'models/play_ad_command.dart';
import 'models/download_info.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 設置全螢幕模式
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // 設置橫向模式
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(const TaxiApp());
}

class TaxiApp extends StatelessWidget {
  const TaxiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Taxi 廣告播放系統',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const AppContainer(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// App 容器 - 管理所有服務和狀態
class AppContainer extends StatefulWidget {
  const AppContainer({Key? key}) : super(key: key);

  @override
  State<AppContainer> createState() => _AppContainerState();
}

class _AppContainerState extends State<AppContainer>
    with WidgetsBindingObserver {
  late WebSocketManager _webSocketManager;
  late DownloadManager _downloadManager;
  late PlaybackManager _playbackManager;
  late LocationService _locationService;

  bool _showSettings = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  /// 初始化應用
  Future<void> _initialize() async {
    try {
      print('🚀 初始化應用...');

      // 1. 載入設備 ID
      final deviceId = await _loadDeviceId();
      print('📱 設備 ID: $deviceId');

      // 2. 初始化管理器
      _webSocketManager = WebSocketManager(
        deviceId: deviceId,
        serverUrl: AppConfig.wsUrl,
      );

      _downloadManager = DownloadManager(baseUrl: AppConfig.apiBaseUrl);

      _playbackManager = PlaybackManager(downloadManager: _downloadManager);

      // 初始化位置服務
      _locationService = LocationService(webSocketManager: _webSocketManager);

      // 3. 設置 WebSocket 事件處理
      _setupWebSocketHandlers();

      // 4. 連接到伺服器
      _webSocketManager.connect();

      // 5. 啟動位置服務
      await _locationService.start();

      // 6. 開始自動播放（優先預設影片，其次本地影片）
      await _playbackManager.startAutoPlay();

      setState(() {
        _isInitialized = true;
      });

      print('✅ 應用初始化完成');
    } catch (e) {
      print('❌ 初始化失敗: $e');
    }
  }

  /// 載入設備 ID
  Future<String> _loadDeviceId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString(AppConfig.deviceIdKey);

      if (deviceId != null && deviceId.isNotEmpty) {
        return deviceId;
      }

      // 使用預設設備 ID
      await prefs.setString(AppConfig.deviceIdKey, AppConfig.defaultDeviceId);
      return AppConfig.defaultDeviceId;
    } catch (e) {
      print('❌ 載入設備 ID 失敗: $e');
      return AppConfig.defaultDeviceId;
    }
  }

  /// 設置 WebSocket 事件處理
  void _setupWebSocketHandlers() {
    // 處理播放廣告命令
    _webSocketManager.onPlayAdCommand = (command) {
      _handlePlayAdCommand(command);
    };

    // 處理下載影片命令
    _webSocketManager.onDownloadVideoCommand = (command) {
      _handleDownloadVideoCommand(command);
    };

    // 處理連接事件
    _webSocketManager.onConnected = () {
      print('✅ WebSocket 已連接');
    };

    _webSocketManager.onDisconnected = () {
      print('❌ WebSocket 已斷開');
    };

    // 處理位置確認（檢測是否離開範圍）
    _webSocketManager.onLocationAck = (data) {
      // 如果位置確認中沒有推送影片，可能表示離開了範圍
      if (data['video_filename'] == null) {
        print('📍 位置確認：無新廣告推送');
        // 檢查並清理過期的位置廣告（超過 30 秒未收到新廣告）
        _playbackManager.checkAndClearExpiredLocationAds(
          timeout: const Duration(seconds: 30),
        );
      }
    };
  }

  /// 處理播放廣告命令
  Future<void> _handlePlayAdCommand(PlayAdCommand command) async {
    print('🎬 處理播放廣告命令: ${command.advertisementName}');
    print('   來源：後端推送');
    print('   影片檔名: ${command.videoFilename}');

    // 檢查影片是否存在
    final exists = await _downloadManager.isVideoExists(command.videoFilename);

    if (!exists) {
      print('⚠️ 影片不存在: ${command.videoFilename}');
      print('   這是後端推送的播放命令，但本地沒有該影片');

      // 如果後端沒有提供 advertisement_id，無法請求下載
      if (command.advertisementId == 'unknown') {
        print('⚠️ 後端未提供 advertisement_id，無法請求下載');
        print('   提示：請確保後端在 play_ad 事件中包含 advertisement_id 字段');
        print('   後端應發送格式：');
        print('   {');
        print('     "command": "PLAY_VIDEO",');
        print('     "video_filename": "影片檔名",');
        print('     "advertisement_id": "adv-xxx",  ← 必須提供');
        print('     "advertisement_name": "廣告名稱",');
        print('     "trigger": "location_based",');
        print('     "timestamp": "2025-01-26T12:34:56"');
        print('   }');
        return;
      }

      print('📥 請求下載: ${command.advertisementId}');
      _webSocketManager.sendDownloadRequest(command.advertisementId);
      return;
    }

    // 影片存在，直接播放
    print('✅ 影片已存在，加入播放隊列');
    await _playbackManager.insertAd(
      videoFilename: command.videoFilename,
      advertisementId: command.advertisementId,
      advertisementName: command.advertisementName,
      isOverride: command.isOverride,
      trigger: command.trigger,
      campaignId: command.campaignId,
    );
  }

  /// 處理下載影片命令
  Future<void> _handleDownloadVideoCommand(DownloadVideoCommand command) async {
    print('📥 處理下載影片命令: ${command.advertisementName}');

    // 檢查影片是否已存在
    final exists = await _downloadManager.isVideoExists(command.videoFilename);
    if (exists) {
      print('✅ 影片已存在: ${command.videoFilename}');

      // 發送完成狀態
      _webSocketManager.sendDownloadStatus(
        advertisementId: command.advertisementId,
        status: 'completed',
        progress: 100,
        downloadedChunks: List.generate(command.totalChunks, (i) => i),
        totalChunks: command.totalChunks,
      );
      return;
    }

    // 開始下載
    final success = await _downloadManager.startDownload(
      advertisementId: command.advertisementId,
      onProgress: (task) {
        // 發送下載進度
        _webSocketManager.sendDownloadStatus(
          advertisementId: task.advertisementId,
          status: task.status.value,
          progress: task.progress,
          downloadedChunks: task.downloadedChunks,
          totalChunks: task.totalChunks,
          errorMessage: task.errorMessage,
        );

        // 下載完成後刷新本地播放列表並加入隊列
        if (task.status == DownloadStatus.completed) {
          print('✅ 下載完成: ${command.videoFilename}');

          // 刷新本地影片列表
          _playbackManager.refreshLocalPlaylist();

          // 加入播放隊列
          _playbackManager.insertAd(
            videoFilename: command.videoFilename,
            advertisementId: command.advertisementId,
            advertisementName: command.advertisementName,
            isOverride: false,
            trigger: command.trigger,
            campaignId: command.campaignId,
          );
        }
      },
    );

    if (!success) {
      print('❌ 啟動下載失敗: ${command.advertisementId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('初始化中...', style: TextStyle(fontSize: 18)),
            ],
          ),
        ),
      );
    }

    return _showSettings
        ? SettingsScreen(
            webSocketManager: _webSocketManager,
            playbackManager: _playbackManager,
            downloadManager: _downloadManager,
            locationService: _locationService,
            onBack: () {
              setState(() {
                _showSettings = false;
              });
            },
          )
        : MainScreen(
            playbackManager: _playbackManager,
            onSettingsRequested: () {
              setState(() {
                _showSettings = true;
              });
            },
          );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 處理應用生命週期變化
    if (state == AppLifecycleState.paused) {
      print('⏸️ 應用進入背景');
      // 可以在這裡暫停某些操作
    } else if (state == AppLifecycleState.resumed) {
      print('▶️ 應用恢復前景');
      // 重新連接 WebSocket（如果斷開）
      if (!_webSocketManager.isConnected) {
        _webSocketManager.connect();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _webSocketManager.dispose();
    _downloadManager.dispose();
    _playbackManager.dispose();
    _locationService.dispose();
    super.dispose();
  }
}
