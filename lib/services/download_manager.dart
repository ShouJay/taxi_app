import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import '../config/app_config.dart';
import '../models/download_info.dart';

/// 下載任務
class DownloadTask {
  final String advertisementId;
  final DownloadInfo downloadInfo;
  DownloadStatus status;
  int progress;
  List<int> downloadedChunks;
  String? errorMessage;
  File? outputFile;

  DownloadTask({
    required this.advertisementId,
    required this.downloadInfo,
    this.status = DownloadStatus.pending,
    this.progress = 0,
    List<int>? downloadedChunks,
    this.errorMessage,
    this.outputFile,
  }) : downloadedChunks = downloadedChunks ?? [];

  int get totalChunks => downloadInfo.totalChunks;
}

/// 下載管理器
class DownloadManager {
  final String baseUrl;
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, StreamController<DownloadTask>> _progressControllers = {};

  DownloadManager({required this.baseUrl});

  /// 獲取下載資訊
  Future<DownloadInfo?> getDownloadInfo(
    String advertisementId, {
    int chunkSize = AppConfig.defaultChunkSize,
  }) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/device/videos/$advertisementId/download',
      ).replace(queryParameters: {'chunk_size': chunkSize.toString()});

      print('📋 獲取下載資訊: $uri');
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final downloadInfo = DownloadInfo.fromJson(data['download_info']);
        print('✅ 下載資訊獲取成功: ${downloadInfo.filename}');
        print('   檔案大小: ${downloadInfo.fileSize} bytes');
        print('   分片大小: ${downloadInfo.chunkSize} bytes');
        print('   總分片數: ${downloadInfo.totalChunks}');
        return downloadInfo;
      } else {
        print('❌ 獲取下載資訊失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ 獲取下載資訊錯誤: $e');
      return null;
    }
  }

  /// 下載單個分片
  Future<Uint8List?> downloadChunk({
    required String advertisementId,
    required int chunkNumber,
    required int chunkSize,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/device/videos/$advertisementId/chunk')
          .replace(
            queryParameters: {
              'chunk': chunkNumber.toString(),
              'chunk_size': chunkSize.toString(),
            },
          );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        print('✅ 分片 $chunkNumber 下載完成 (${response.bodyBytes.length} bytes)');
        return response.bodyBytes;
      } else {
        print('❌ 下載分片 $chunkNumber 失敗: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ 下載分片 $chunkNumber 錯誤: $e');
      return null;
    }
  }

  /// 開始下載影片
  Future<bool> startDownload({
    required String advertisementId,
    Function(DownloadTask)? onProgress,
  }) async {
    // 檢查是否已經在下載
    if (_tasks.containsKey(advertisementId)) {
      print('⚠️ 影片 $advertisementId 已在下載隊列中');
      return false;
    }

    try {
      // 獲取下載資訊
      final downloadInfo = await getDownloadInfo(advertisementId);
      if (downloadInfo == null) {
        print('❌ 無法獲取下載資訊');
        return false;
      }

      // 檢查檔案是否已存在
      final videoPath = await _getVideoPath(downloadInfo.filename);
      final file = File(videoPath);

      if (await file.exists()) {
        final fileSize = await file.length();
        if (fileSize == downloadInfo.fileSize) {
          print('✅ 檔案已存在: ${downloadInfo.filename}');
          return true;
        } else {
          print('⚠️ 檔案大小不符，重新下載');
          await file.delete();
        }
      }

      // 建立下載任務
      final task = DownloadTask(
        advertisementId: advertisementId,
        downloadInfo: downloadInfo,
        status: DownloadStatus.downloading,
        outputFile: file,
      );
      _tasks[advertisementId] = task;

      // 建立進度控制器
      final controller = StreamController<DownloadTask>.broadcast();
      _progressControllers[advertisementId] = controller;

      if (onProgress != null) {
        controller.stream.listen(onProgress);
      }

      // 開始背景下載
      _downloadInBackground(task);

      return true;
    } catch (e) {
      print('❌ 啟動下載失敗: $e');
      return false;
    }
  }

  /// 背景下載
  Future<void> _downloadInBackground(DownloadTask task) async {
    final downloadInfo = task.downloadInfo;
    final advertisementId = task.advertisementId;

    try {
      // 建立輸出檔案
      final file = task.outputFile!;
      final fileWriter = file.openWrite();

      // 下載每個分片
      for (int i = 0; i < downloadInfo.totalChunks; i++) {
        // 檢查是否已下載
        if (task.downloadedChunks.contains(i)) {
          continue;
        }

        // 下載分片（支援重試）
        Uint8List? chunkData;
        int retryCount = 0;

        while (retryCount < AppConfig.downloadRetryAttempts) {
          chunkData = await downloadChunk(
            advertisementId: advertisementId,
            chunkNumber: i,
            chunkSize: downloadInfo.chunkSize,
          );

          if (chunkData != null) {
            break;
          }

          retryCount++;
          if (retryCount < AppConfig.downloadRetryAttempts) {
            print('🔄 重試下載分片 $i (第 $retryCount 次)');
            await Future.delayed(Duration(seconds: retryCount * 2));
          }
        }

        if (chunkData == null) {
          // 下載失敗
          task.status = DownloadStatus.failed;
          task.errorMessage = '下載分片 $i 失敗';
          _notifyProgress(task);
          await fileWriter.close();
          await file.delete();
          return;
        }

        // 寫入分片
        fileWriter.add(chunkData);
        task.downloadedChunks.add(i);

        // 更新進度
        task.progress =
            ((task.downloadedChunks.length / downloadInfo.totalChunks) * 100)
                .round();
        _notifyProgress(task);
      }

      // 完成下載
      await fileWriter.close();
      task.status = DownloadStatus.completed;
      task.progress = 100;
      _notifyProgress(task);

      print('✅ 下載完成: ${downloadInfo.filename}');
      print('   路徑: ${file.path}');
    } catch (e) {
      print('❌ 下載過程錯誤: $e');
      task.status = DownloadStatus.failed;
      task.errorMessage = e.toString();
      _notifyProgress(task);

      // 清理失敗的檔案
      if (task.outputFile != null && await task.outputFile!.exists()) {
        await task.outputFile!.delete();
      }
    }
  }

  /// 通知進度更新
  void _notifyProgress(DownloadTask task) {
    final controller = _progressControllers[task.advertisementId];
    if (controller != null && !controller.isClosed) {
      controller.add(task);
    }
  }

  /// 取消下載
  Future<void> cancelDownload(String advertisementId) async {
    final task = _tasks[advertisementId];
    if (task != null) {
      task.status = DownloadStatus.paused;
      _notifyProgress(task);

      // 清理未完成的檔案
      if (task.outputFile != null && await task.outputFile!.exists()) {
        await task.outputFile!.delete();
      }

      _tasks.remove(advertisementId);
      _progressControllers[advertisementId]?.close();
      _progressControllers.remove(advertisementId);

      print('⏸️ 已取消下載: $advertisementId');
    }
  }

  /// 獲取任務狀態
  DownloadTask? getTask(String advertisementId) {
    return _tasks[advertisementId];
  }

  /// 獲取影片路徑
  Future<String> _getVideoPath(String filename) async {
    final directory = await getApplicationDocumentsDirectory();
    final videoDir = Directory('${directory.path}/videos');

    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }

    return '${videoDir.path}/$filename';
  }

  /// 檢查影片是否存在
  Future<bool> isVideoExists(String filename) async {
    final videoPath = await _getVideoPath(filename);
    final file = File(videoPath);
    return await file.exists();
  }

  /// 獲取影片完整路徑
  Future<String> getVideoPath(String filename) async {
    return await _getVideoPath(filename);
  }

  /// 獲取所有已下載的影片列表
  Future<List<String>> getAllDownloadedVideos() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final videoDir = Directory('${directory.path}/videos');

      if (!await videoDir.exists()) {
        return [];
      }

      final files = await videoDir.list().toList();
      final videoFiles = files
          .where((file) => file is File)
          .map((file) => file.path.split('/').last)
          .where(
            (filename) =>
                filename.endsWith('.mp4') ||
                filename.endsWith('.mov') ||
                filename.endsWith('.avi'),
          )
          .toList();

      print('📁 找到 ${videoFiles.length} 個已下載的影片');
      for (var filename in videoFiles) {
        print('   - $filename');
      }

      return videoFiles;
    } catch (e) {
      print('❌ 獲取已下載影片列表失敗: $e');
      return [];
    }
  }

  /// 清理所有任務
  void dispose() {
    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();
    _tasks.clear();
  }
}
