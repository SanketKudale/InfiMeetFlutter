class CsnSignalMessage {
  CsnSignalMessage(this.type, [this.payload]);

  final String type;
  final Map<String, dynamic>? payload;

  Map<String, dynamic> toJson() => {
        'type': type,
        if (payload != null) ...payload!,
      };

  static CsnSignalMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'unknown';
    final payload = Map<String, dynamic>.from(json)..remove('type');
    return CsnSignalMessage(type, payload);
  }
}

class CsnRoomState {
  CsnRoomState({required this.roomId, required this.producers, required this.peers, this.settings});

  final String roomId;
  final List<CsnProducerInfo> producers;
  final List<String> peers;
  final CsnRoomSettingsInfo? settings;

  factory CsnRoomState.fromJson(Map<String, dynamic> json) => CsnRoomState(
        roomId: json['roomId'] as String,
        producers: (json['producers'] as List<dynamic>? ?? [])
            .map((item) => CsnProducerInfo.fromJson(item as Map<String, dynamic>))
            .toList(),
        peers: (json['peers'] as List<dynamic>? ?? [])
            .map((item) => item['userId'] as String)
            .toList(),
        settings: json['settings'] == null
            ? null
            : CsnRoomSettingsInfo.fromJson(json['settings'] as Map<String, dynamic>),
      );
}

class CsnProducerInfo {
  CsnProducerInfo({required this.producerId, required this.userId, required this.kind, this.codec});

  final String producerId;
  final String userId;
  final String kind;
  final String? codec;

  factory CsnProducerInfo.fromJson(Map<String, dynamic> json) => CsnProducerInfo(
        producerId: json['producerId'] as String,
        userId: json['userId'] as String,
        kind: json['kind'] as String,
        codec: json['codec'] as String?,
      );
}

class CsnRoomSettingsInfo {
  CsnRoomSettingsInfo({required this.allowAudio, required this.allowVideo, required this.isLocked});

  final bool allowAudio;
  final bool allowVideo;
  final bool isLocked;

  factory CsnRoomSettingsInfo.fromJson(Map<String, dynamic> json) => CsnRoomSettingsInfo(
        allowAudio: json['allowAudio'] as bool,
        allowVideo: json['allowVideo'] as bool,
        isLocked: json['isLocked'] as bool? ?? false,
      );
}
