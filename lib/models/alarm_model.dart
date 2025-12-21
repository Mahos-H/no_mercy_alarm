class AlarmModel {
  final int id;
  final DateTime time;
  final String password;
  final bool isActive;
  final String? soundPath;

  AlarmModel({
    required this.id,
    required this.time,
    required this.password,
    this.isActive = true,
    this.soundPath,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'time': time.toIso8601String(),
      'password': password,
      'isActive': isActive,
      'soundPath': soundPath,
    };
  }

  factory AlarmModel.fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      id: json['id'] as int,
      time: DateTime.parse(json['time'] as String),
      password: json['password'] as String,
      isActive: json['isActive'] as bool? ?? true,
      soundPath: json['soundPath'] as String?,
    );
  }

  AlarmModel copyWith({
    int? id,
    DateTime? time,
    String? password,
    bool? isActive,
    String? soundPath,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      time: time ?? this.time,
      password: password ?? this.password,
      isActive: isActive ?? this.isActive,
      soundPath: soundPath ?? this.soundPath,
    );
  }

  String getTimeString() {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}