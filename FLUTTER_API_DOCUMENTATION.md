# Flutter App API 開發文件

本文檔詳細說明Flutter廣告播放App與後端系統的API通訊規範。

## 目錄

1. [概述](#概述)
2. [WebSocket通訊](#websocket通訊)
3. [HTTP API](#http-api)
4. [資料格式](#資料格式)
5. [Flutter實現範例](#flutter實現範例)
6. [錯誤處理](#錯誤處理)

---

## 概述

### App功能
1. **廣告播放**：播放廣告影片
2. **自動插播**：接收後端推送的廣告指令並插播
3. **背景下載**：在背景下載廣告檔案
4. **管理設定**：點擊5下螢幕進入設定介面
   - 設定設備ID
   - 查看通訊狀況

### 通訊方式
- **WebSocket**：主要通訊方式，用於即時推播、心跳、狀態回報
- **HTTP**：用於下載廣告檔案（支援分片下載）

### 基礎配置

```dart
// 後端服務地址
const String BASE_URL = "http://your-server.com";
const String WS_URL = "ws://your-server.com";

// 設備ID（可在設定頁面修改）
String deviceId = "taxi-AAB-1234-rooftop";
```

---

## WebSocket通訊

### 連接流程

```dart
// 1. 連接到WebSocket伺服器
socket.connect();

// 2. 連接成功後註冊設備
socket.emit('register', {
  'device_id': deviceId
});
```

### 連接到伺服器

**事件**: `connect`

```dart
@override
void onConnect() {
  print('✅ 已連接到伺服器');
  // 連接成功後發送註冊請求
  emit('register', {'device_id': deviceId});
}
```

---

## WebSocket事件

### 客戶端發送事件

#### 1. 設備註冊 (`register`)

**用途**: 註冊設備到伺服器

**發送格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop"
}
```

**範例**:
```dart
socket.emit('register', {
  'device_id': deviceId
});
```

---

#### 2. 位置更新 (`location_update`)

**用途**: 發送設備位置，觸發廣告決策

**發送格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop",
  "longitude": 121.5645,
  "latitude": 25.0330
}
```

**範例**:
```dart
socket.emit('location_update', {
  'device_id': deviceId,
  'longitude': 121.5645,
  'latitude': 25.0330
});
```

**頻率建議**: 每5-10秒發送一次

---

#### 3. 心跳 (`heartbeat`)

**用途**: 保持連接活躍

**發送格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop"
}
```

**範例**:
```dart
socket.emit('heartbeat', {
  'device_id': deviceId
});
```

**頻率建議**: 每30-60秒發送一次

---

#### 4. 下載請求 (`download_request`)

**用途**: 主動請求下載廣告

**發送格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop",
  "advertisement_id": "adv-001"
}
```

**範例**:
```dart
socket.emit('download_request', {
  'device_id': deviceId,
  'advertisement_id': 'adv-001'
});
```

---

#### 5. 下載狀態回報 (`download_status`)

**用途**: 回報下載進度和狀態

**發送格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop",
  "advertisement_id": "adv-001",
  "status": "downloading",  // downloading, completed, failed, paused
  "progress": 50,  // 0-100
  "downloaded_chunks": [0, 1, 2, 3],
  "total_chunks": 10,
  "error_message": null
}
```

**範例**:
```dart
socket.emit('download_status', {
  'device_id': deviceId,
  'advertisement_id': 'adv-001',
  'status': 'downloading',
  'progress': 45,
  'downloaded_chunks': [0, 1, 2],
  'total_chunks': 10
});
```

---

### 伺服器發送事件

#### 1. 連接建立 (`connection_established`)

**用途**: 連接成功後收到的歡迎訊息

**接收格式**:
```json
{
  "message": "連接成功！請發送 register 事件註冊您的設備",
  "sid": "session-id",
  "timestamp": "2024-01-01T00:00:00"
}
```

---

#### 2. 註冊成功 (`registration_success`)

**用途**: 設備註冊成功

**接收格式**:
```json
{
  "message": "設備 taxi-AAB-1234-rooftop 註冊成功",
  "device_id": "taxi-AAB-1234-rooftop",
  "device_type": "rooftop_display",
  "timestamp": "2024-01-01T00:00:00"
}
```

---

#### 3. 註冊失敗 (`registration_error`)

**用途**: 設備註冊失敗

**接收格式**:
```json
{
  "error": "設備不存在於系統中"
}
```

---

#### 4. 播放廣告命令 (`play_ad`)

**用途**: 收到播放廣告指令

**接收格式**:
```json
{
  "command": "PLAY_VIDEO",
  "video_filename": "video.mp4",
  "advertisement_id": "adv-001",
  "advertisement_name": "廣告名稱",
  "trigger": "location_based",  // location_based, admin_override, http_heartbeat
  "priority": "override",
  "timestamp": "2024-01-01T00:00:00"
}
```

**處理邏輯**:
- 將廣告加入播放隊列
- 若為 `override` 優先級，立即插播
- 若為 `location_based`，排入下一輪播放

---

#### 5. 位置更新確認 (`location_ack`)

**用途**: 位置更新處理完成

**接收格式**:
```json
{
  "message": "位置更新已處理，廣告已推送",
  "video_filename": "video.mp4",
  "timestamp": "2024-01-01T00:00:00"
}
```

---

#### 6. 心跳確認 (`heartbeat_ack`)

**用途**: 心跳回應

**接收格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop",
  "timestamp": "2024-01-01T00:00:00"
}
```

---

#### 7. 下載命令 (`download_video`)

**用途**: 收到下載廣告命令

**接收格式**:
```json
{
  "command": "DOWNLOAD_VIDEO",
  "advertisement_id": "adv-001",
  "advertisement_name": "廣告名稱",
  "video_filename": "video.mp4",
  "file_size": 12345678,
  "download_mode": "chunked",
  "priority": "high",
  "trigger": "admin_push",
  "chunk_size": 10485760,
  "total_chunks": 3,
  "download_url": "/api/v1/device/videos/adv-001/chunk",
  "download_info_url": "/api/v1/device/videos/adv-001/download",
  "timestamp": "2024-01-01T00:00:00"
}
```

**處理邏輯**:
- 若檔案已存在，跳過
- 啟動背景下載任務
- 支援斷點續傳
- 下載完成後自動加入播放隊列

---

#### 8. 斷開連接 (`disconnect`)

**用途**: 伺服器主動斷開

**接收格式**:
```json
{
  "reason": "設備已被刪除"
}
```

---

## HTTP API

### 基礎URL
```
http://your-server.com/api/v1
```

---

### 1. 獲取下載信息

**端點**: `GET /device/videos/<advertisement_id>/download`

**用途**: 獲取影片下載資訊（分片資訊）

**請求範例**:
```dart
final response = await http.get(
  Uri.parse('$BASE_URL/device/videos/adv-001/download?chunk_size=10485760')
);
```

**回應格式**:
```json
{
  "status": "success",
  "download_info": {
    "advertisement_id": "adv-001",
    "filename": "video.mp4",
    "file_size": 12345678,
    "chunk_size": 10485760,
    "total_chunks": 3,
    "download_url": "/api/v1/device/videos/adv-001/chunk",
    "download_mode": "chunked"
  }
}
```

---

### 2. 下載分片

**端點**: `GET /device/videos/<advertisement_id>/chunk`

**用途**: 下載影片分片

**請求參數**:
- `chunk`: 分片編號（從0開始）
- `chunk_size`: 分片大小（bytes）

**請求範例**:
```dart
final response = await http.get(
  Uri.parse('$BASE_URL/device/videos/adv-001/chunk?chunk=0&chunk_size=10485760')
);
```

**回應**:
- 狀態碼: `200 OK`
- Content-Type: `application/octet-stream`
- Headers:
  - `Content-Range`: 分片範圍
  - `Content-Length`: 分片大小
  - `X-Chunk-Number`: 分片編號
  - `X-Total-Chunks`: 總分片數
  - `X-Advertisement-ID`: 廣告ID
  - `X-File-Size`: 總檔案大小

**回應範例**:
```
Content-Range: bytes 0-10485759/12345678
Content-Length: 10485760
X-Chunk-Number: 0
X-Total-Chunks: 3
X-Advertisement-ID: adv-001
X-File-Size: 12345678
```

---

### 3. HTTP心跳（備用）

**端點**: `POST /device/heartbeat`

**用途**: HTTP心跳（建議使用WebSocket heartbeat）

**請求格式**:
```json
{
  "device_id": "taxi-AAB-1234-rooftop",
  "location": {
    "longitude": 121.5645,
    "latitude": 25.0330
  }
}
```

**回應格式**:
```json
{
  "command": "PLAY_VIDEO",
  "video_filename": "video.mp4"
}
```

**範例**:
```dart
final response = await http.post(
  Uri.parse('$BASE_URL/device/heartbeat'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'device_id': deviceId,
    'location': {
      'longitude': 121.5645,
      'latitude': 25.0330
    }
  })
);
```

---

## 資料格式

### 設備資訊

```dart
class DeviceInfo {
  final String deviceId;
  final String deviceType;
  final List<String> groups;
  final Point? lastLocation;
  final String status;
  final DateTime createdAt;
}
```

---

### 廣告資訊

```dart
class AdvertisementInfo {
  final String advertisementId;
  final String name;
  final String videoFilename;
  final String? videoPath;
  final int? fileSize;
  final int? duration;
  final String status;
  final String type;
  final int priority;
  final List<String> targetGroups;
  final DateTime? createdAt;
}
```

---

### 下載資訊

```dart
class DownloadInfo {
  final String advertisementId;
  final String filename;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final String downloadUrl;
  final String downloadMode;
}
```

---

### 分片資訊

```dart
class ChunkInfo {
  final int chunkNumber;
  final int totalChunks;
  final int startByte;
  final int endByte;
  final int dataSize;
}
```

---

## Flutter實現範例

### WebSocket管理器

```dart
import 'package:socket_io_client/socket_io_client.dart' as IO;

class WebSocketManager {
  IO.Socket? socket;
  String deviceId;
  final String serverUrl;

  WebSocketManager({
    required this.deviceId,
    required this.serverUrl,
  });

  void connect() {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    // 設置事件監聽
    socket!.onConnect((_) {
      print('✅ 已連接到伺服器');
      _registerDevice();
    });

    socket!.onDisconnect((_) {
      print('❌ 已斷開連接');
    });

    // 設置伺服器事件監聽
    socket!.on('connection_established', _onConnectionEstablished);
    socket!.on('registration_success', _onRegistrationSuccess);
    socket!.on('registration_error', _onRegistrationError);
    socket!.on('play_ad', _onPlayAd);
    socket!.on('location_ack', _onLocationAck);
    socket!.on('heartbeat_ack', _onHeartbeatAck);
    socket!.on('download_video', _onDownloadVideo);
    socket!.on('download_status_ack', _onDownloadStatusAck);
    socket!.on('force_disconnect', _onForceDisconnect);

    // 連接
    socket!.connect();
  }

  void _registerDevice() {
    socket!.emit('register', {'device_id': deviceId});
  }

  void sendLocationUpdate(double longitude, double latitude) {
    if (socket != null && socket!.connected) {
      socket!.emit('location_update', {
        'device_id': deviceId,
        'longitude': longitude,
        'latitude': latitude,
      });
    }
  }

  void sendHeartbeat() {
    if (socket != null && socket!.connected) {
      socket!.emit('heartbeat', {'device_id': deviceId});
    }
  }

  void sendDownloadStatus({
    required String advertisementId,
    required String status,
    required int progress,
    required List<int> downloadedChunks,
    required int totalChunks,
    String? errorMessage,
  }) {
    if (socket != null && socket!.connected) {
      socket!.emit('download_status', {
        'device_id': deviceId,
        'advertisement_id': advertisementId,
        'status': status,
        'progress': progress,
        'downloaded_chunks': downloadedChunks,
        'total_chunks': totalChunks,
        'error_message': errorMessage,
      });
    }
  }

  void _onConnectionEstablished(dynamic data) {
    print('📡 連接建立: ${data['message']}');
  }

  void _onRegistrationSuccess(dynamic data) {
    print('✅ 註冊成功: ${data['message']}');
  }

  void _onRegistrationError(dynamic data) {
    print('❌ 註冊失敗: ${data['error']}');
  }

  void _onPlayAd(dynamic data) {
    print('🎬 收到廣告推送命令');
    print('   影片: ${data['video_filename']}');
    print('   觸發: ${data['trigger']}');
    
    // 處理廣告播放
    _handlePlayAd(data);
  }

  void _onLocationAck(dynamic data) {
    print('✅ 位置更新確認: ${data['message']}');
  }

  void _onHeartbeatAck(dynamic data) {
    print('💓 心跳確認');
  }

  void _onDownloadVideo(dynamic data) {
    print('📥 收到下載命令');
    print('   廣告ID: ${data['advertisement_id']}');
    print('   文件大小: ${data['file_size']} bytes');
    
    // 處理下載任務
    _handleDownloadVideo(data);
  }

  void _onDownloadStatusAck(dynamic data) {
    print('📊 下載狀態確認: ${data['message']}');
  }

  void _onForceDisconnect(dynamic data) {
    print('⚠️ 伺服器強制斷開: ${data['reason']}');
    disconnect();
  }

  void _handlePlayAd(Map<String, dynamic> data) {
    // TODO: 實作廣告播放邏輯
    // 1. 解析廣告資訊
    // 2. 檢查本地是否存在檔案
    // 3. 若不存在，先下載
    // 4. 加入播放隊列
  }

  void _handleDownloadVideo(Map<String, dynamic> data) {
    // TODO: 實作下載邏輯
    // 1. 解析下載資訊
    // 2. 啟動背景下載任務
    // 3. 支援斷點續傳
    // 4. 回報下載進度
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
  }
}
```

---

### HTTP下載管理器

```dart
import 'dart:io';
import 'package:http/http.dart' as http;

class DownloadManager {
  final String baseUrl;

  DownloadManager({required this.baseUrl});

  // 獲取下載資訊
  Future<DownloadInfo?> getDownloadInfo(String advertisementId, {int chunkSize = 10485760}) async {
    try {
      final uri = Uri.parse('$baseUrl/device/videos/$advertisementId/download')
          .replace(queryParameters: {'chunk_size': chunkSize.toString()});
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DownloadInfo.fromJson(data['download_info']);
      } else {
        print('獲取下載資訊失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('獲取下載資訊錯誤: $e');
      return null;
    }
  }

  // 下載單個分片
  Future<Uint8List?> downloadChunk({
    required String advertisementId,
    required int chunkNumber,
    required int chunkSize,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/device/videos/$advertisementId/chunk')
          .replace(queryParameters: {
        'chunk': chunkNumber.toString(),
        'chunk_size': chunkSize.toString(),
      });
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        print('下載分片失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('下載分片錯誤: $e');
      return null;
    }
  }

  // 下載完整影片
  Future<bool> downloadVideo({
    required String advertisementId,
    required DownloadInfo downloadInfo,
    required Function(int, int) onProgress,
  }) async {
    try {
      final totalChunks = downloadInfo.totalChunks;
      final chunkSize = downloadInfo.chunkSize;
      
      // 建立本地檔案
      final file = File('${await _getDownloadPath()}/${downloadInfo.filename}');
      final fileWriter = file.openWrite();
      
      // 下載每個分片
      for (int i = 0; i < totalChunks; i++) {
        final chunkData = await downloadChunk(
          advertisementId: advertisementId,
          chunkNumber: i,
          chunkSize: chunkSize,
        );
        
        if (chunkData == null) {
          await fileWriter.close();
          await file.delete();
          return false;
        }
        
        await fileWriter.add(chunkData);
        
        // 更新進度
        final progress = ((i + 1) / totalChunks * 100).round();
        onProgress(i + 1, totalChunks);
      }
      
      await fileWriter.close();
      return true;
    } catch (e) {
      print('下載影片錯誤: $e');
      return false;
    }
  }

  Future<String> _getDownloadPath() async {
    // TODO: 實作本地儲存路徑
    return '/path/to/download';
  }
}

// 資料類別
class DownloadInfo {
  final String advertisementId;
  final String filename;
  final int fileSize;
  final int chunkSize;
  final int totalChunks;
  final String downloadUrl;
  final String downloadMode;

  DownloadInfo({
    required this.advertisementId,
    required this.filename,
    required this.fileSize,
    required this.chunkSize,
    required this.totalChunks,
    required this.downloadUrl,
    required this.downloadMode,
  });

  factory DownloadInfo.fromJson(Map<String, dynamic> json) {
    return DownloadInfo(
      advertisementId: json['advertisement_id'],
      filename: json['filename'],
      fileSize: json['file_size'],
      chunkSize: json['chunk_size'],
      totalChunks: json['total_chunks'],
      downloadUrl: json['download_url'],
      downloadMode: json['download_mode'],
    );
  }
}
```

---

### 播放管理器

```dart
import 'package:video_player/video_player.dart';

class PlaybackManager {
  VideoPlayerController? _currentController;
  final List<String> _playQueue = [];
  final String _defaultVideo = 'default_ad.mp4';

  // 播放預設影片
  void playDefaultVideo() {
    _playVideo(_defaultVideo);
  }

  // 插播廣告
  void insertAd(String videoFilename, {bool isOverride = false}) {
    if (isOverride) {
      // 優先級廣告，立即播放
      _playVideo(videoFilename);
    } else {
      // 普通廣告，加入隊列
      _playQueue.add(videoFilename);
    }
  }

  void _playVideo(String videoFilename) {
    // TODO: 實作影片播放邏輯
    print('播放影片: $videoFilename');
    
    // 實作播放邏輯
    // 1. 檢查檔案是否存在
    // 2. 載入播放器
    // 3. 開始播放
    // 4. 播放完成後播放下一個
  }

  void _onVideoFinished() {
    // 影片播放完成
    if (_playQueue.isNotEmpty) {
      final nextVideo = _playQueue.removeAt(0);
      _playVideo(nextVideo);
    } else {
      // 播完預設影片
      playDefaultVideo();
    }
  }
}
```

---

### 管理設定頁面

```dart
import 'package:flutter/material.dart';

class SettingsPage extends StatefulWidget {
  final String deviceId;
  final Function(String) onDeviceIdChanged;

  const SettingsPage({
    Key? key,
    required this.deviceId,
    required this.onDeviceIdChanged,
  }) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _deviceIdController;
  
  @override
  void initState() {
    super.initState();
    _deviceIdController = TextEditingController(text: widget.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('設定'),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '設備設定',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _deviceIdController,
              decoration: InputDecoration(
                labelText: '設備ID',
                border: OutlineInputBorder(),
                helperText: '在此輸入您的設備ID',
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveDeviceId,
              child: Text('儲存'),
            ),
            SizedBox(height: 32),
            Text(
              '通訊狀況',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            // TODO: 顯示通訊狀態
            Text('連線狀態: 已連接'),
            Text('最後更新: 剛剛'),
          ],
        ),
      ),
    );
  }

  void _saveDeviceId() {
    final newDeviceId = _deviceIdController.text;
    widget.onDeviceIdChanged(newDeviceId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('設備ID已更新')),
    );
  }
}
```

---

## 錯誤處理

### WebSocket錯誤處理

```dart
// 處理連接錯誤
socket.on('error', (error) {
  print('WebSocket錯誤: $error');
  // TODO: 實作重連邏輯
});

// 處理下載狀態錯誤
void _onDownloadStatusError(dynamic data) {
  print('❌ 下載狀態錯誤: ${data['error']}');
  // TODO: 實作錯誤處理
}

// 處理下載請求錯誤
void _onDownloadRequestError(dynamic data) {
  print('❌ 下載請求錯誤: ${data['error']}');
  // TODO: 實作錯誤處理
}
```

### HTTP錯誤處理

```dart
try {
  final response = await http.get(uri);
  
  if (response.statusCode == 200) {
    // 處理成功
  } else if (response.statusCode == 404) {
    // 處理檔案不存在
  } else if (response.statusCode >= 500) {
    // 處理伺服器錯誤
  }
} catch (e) {
  if (e is SocketException) {
    // 處理網路錯誤
  } else {
    // 處理其他錯誤
  }
}
```

---

## 結語

本文檔詳細說明了Flutter App與後端系統的API通訊規範。開發時請確保：

1. 正確處理WebSocket連線和斷線
2. 定期發送位置更新和心跳
3. 支援分片下載大型檔案
4. 實現廣告播放隊列和插播機制
5. 提供完整的錯誤處理和重試機制
6. 實作管理設定頁面

如需更多協助，請參考程式碼註釋或聯繫開發團隊。

