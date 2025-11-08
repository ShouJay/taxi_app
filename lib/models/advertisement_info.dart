/// 廣告資訊
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

  AdvertisementInfo({
    required this.advertisementId,
    required this.name,
    required this.videoFilename,
    this.videoPath,
    this.fileSize,
    this.duration,
    required this.status,
    required this.type,
    required this.priority,
    required this.targetGroups,
    this.createdAt,
  });

  factory AdvertisementInfo.fromJson(Map<String, dynamic> json) {
    return AdvertisementInfo(
      advertisementId: json['advertisement_id'] as String,
      name: json['name'] as String,
      videoFilename: json['video_filename'] as String,
      videoPath: json['video_path'] as String?,
      fileSize: json['file_size'] as int?,
      duration: json['duration'] as int?,
      status: json['status'] as String,
      type: json['type'] as String,
      priority: json['priority'] as int,
      targetGroups:
          (json['target_groups'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'advertisement_id': advertisementId,
      'name': name,
      'video_filename': videoFilename,
      'video_path': videoPath,
      'file_size': fileSize,
      'duration': duration,
      'status': status,
      'type': type,
      'priority': priority,
      'target_groups': targetGroups,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}
