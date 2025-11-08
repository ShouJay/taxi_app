/// 播放廣告命令
class PlayAdCommand {
  final String command;
  final String videoFilename;
  final String advertisementId;
  final String advertisementName;
  final String trigger;
  final String? priority;
  final String? campaignId; // 活動ID
  final DateTime timestamp;

  PlayAdCommand({
    required this.command,
    required this.videoFilename,
    required this.advertisementId,
    required this.advertisementName,
    required this.trigger,
    this.priority,
    this.campaignId,
    required this.timestamp,
  });

  factory PlayAdCommand.fromJson(Map<String, dynamic> json) {
    return PlayAdCommand(
      command: json['command'] as String? ?? 'PLAY_VIDEO',
      videoFilename: json['video_filename'] as String,
      advertisementId: json['advertisement_id'] as String? ?? 'unknown',
      advertisementName: json['advertisement_name'] as String? ?? '未命名廣告',
      trigger: json['trigger'] as String? ?? 'unknown',
      priority: json['priority'] as String?,
      campaignId: json['campaign_id'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }

  bool get isOverride => priority?.toLowerCase() == 'override';
  bool get isLocationBased => trigger.toLowerCase() == 'location_based';
}

/// 下載影片命令
class DownloadVideoCommand {
  final String command;
  final String advertisementId;
  final String advertisementName;
  final String videoFilename;
  final int fileSize;
  final String downloadMode;
  final String priority;
  final String trigger;
  final String? campaignId; // 活動ID
  final int chunkSize;
  final int totalChunks;
  final String downloadUrl;
  final String downloadInfoUrl;
  final DateTime timestamp;

  DownloadVideoCommand({
    required this.command,
    required this.advertisementId,
    required this.advertisementName,
    required this.videoFilename,
    required this.fileSize,
    required this.downloadMode,
    required this.priority,
    required this.trigger,
    this.campaignId,
    required this.chunkSize,
    required this.totalChunks,
    required this.downloadUrl,
    required this.downloadInfoUrl,
    required this.timestamp,
  });

  factory DownloadVideoCommand.fromJson(Map<String, dynamic> json) {
    return DownloadVideoCommand(
      command: json['command'] as String,
      advertisementId: json['advertisement_id'] as String,
      advertisementName: json['advertisement_name'] as String,
      videoFilename: json['video_filename'] as String,
      fileSize: json['file_size'] as int,
      downloadMode: json['download_mode'] as String,
      priority: json['priority'] as String,
      trigger: json['trigger'] as String,
      campaignId: json['campaign_id'] as String?,
      chunkSize: json['chunk_size'] as int,
      totalChunks: json['total_chunks'] as int,
      downloadUrl: json['download_url'] as String,
      downloadInfoUrl: json['download_info_url'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
