/// 設備資訊
class DeviceInfo {
  final String deviceId;
  final String deviceType;
  final List<String> groups;
  final Location? lastLocation;
  final String status;
  final DateTime createdAt;

  DeviceInfo({
    required this.deviceId,
    required this.deviceType,
    required this.groups,
    this.lastLocation,
    required this.status,
    required this.createdAt,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['device_id'] as String,
      deviceType: json['device_type'] as String,
      groups: (json['groups'] as List<dynamic>?)?.cast<String>() ?? [],
      lastLocation: json['last_location'] != null
          ? Location.fromJson(json['last_location'] as Map<String, dynamic>)
          : null,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'device_id': deviceId,
      'device_type': deviceType,
      'groups': groups,
      'last_location': lastLocation?.toJson(),
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 位置資訊
class Location {
  final double longitude;
  final double latitude;

  Location({required this.longitude, required this.latitude});

  factory Location.fromJson(Map<String, dynamic> json) {
    return Location(
      longitude: (json['longitude'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'longitude': longitude, 'latitude': latitude};
  }
}
