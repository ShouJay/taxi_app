/// 應用程式配置
class AppConfig {
  // 後端服務地址（請根據實際環境修改）
  static const String baseUrl = 'https://robusttaxi.azurewebsites.net';
  static const String wsUrl = 'wss://robusttaxi.azurewebsites.net';

  // API 版本
  static const String apiVersion = 'v1';

  // API 端點
  static String get apiBaseUrl => '$baseUrl/api/$apiVersion';

  // WebSocket 配置
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration locationUpdateInterval = Duration(seconds: 5);
  static const Duration reconnectDelay = Duration(seconds: 5);

  // 下載配置
  static const int defaultChunkSize = 10485760; // 10MB
  static const int maxConcurrentDownloads = 3;
  static const int downloadRetryAttempts = 3;

  // 本地儲存鍵值
  static const String deviceIdKey = 'device_id';
  static const String defaultDeviceId = 'taxi-AAB-1234-rooftop';

  // 播放配置
  static const int tapCountToSettings = 5;
  static const Duration tapDetectionWindow = Duration(seconds: 3);
}
