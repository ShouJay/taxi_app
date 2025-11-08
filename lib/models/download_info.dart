/// 下載資訊
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
      advertisementId: json['advertisement_id'] as String,
      filename: json['filename'] as String,
      fileSize: json['file_size'] as int,
      chunkSize: json['chunk_size'] as int,
      totalChunks: json['total_chunks'] as int,
      downloadUrl: json['download_url'] as String,
      downloadMode: json['download_mode'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'advertisement_id': advertisementId,
      'filename': filename,
      'file_size': fileSize,
      'chunk_size': chunkSize,
      'total_chunks': totalChunks,
      'download_url': downloadUrl,
      'download_mode': downloadMode,
    };
  }
}

/// 分片資訊
class ChunkInfo {
  final int chunkNumber;
  final int totalChunks;
  final int startByte;
  final int endByte;
  final int dataSize;

  ChunkInfo({
    required this.chunkNumber,
    required this.totalChunks,
    required this.startByte,
    required this.endByte,
    required this.dataSize,
  });
}

/// 下載狀態
enum DownloadStatus { pending, downloading, completed, failed, paused }

extension DownloadStatusExtension on DownloadStatus {
  String get value {
    switch (this) {
      case DownloadStatus.pending:
        return 'pending';
      case DownloadStatus.downloading:
        return 'downloading';
      case DownloadStatus.completed:
        return 'completed';
      case DownloadStatus.failed:
        return 'failed';
      case DownloadStatus.paused:
        return 'paused';
    }
  }
}
