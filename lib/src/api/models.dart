class HealthResponse {
  HealthResponse({required this.status, required this.uptime});

  final String status;
  final num uptime;

  factory HealthResponse.fromJson(Map<String, dynamic> json) => HealthResponse(
        status: json['status'] as String,
        uptime: json['uptime'] as num,
      );
}

class RoomSettings {
  RoomSettings({
    required this.id,
    required this.maxParticipants,
    required this.allowAudio,
    required this.allowVideo,
    required this.isLocked,
  });

  final String id;
  final int? maxParticipants;
  final bool allowAudio;
  final bool allowVideo;
  final bool isLocked;

  factory RoomSettings.fromJson(Map<String, dynamic> json) => RoomSettings(
        id: json['id'] as String,
        maxParticipants: json['maxParticipants'] as int?,
        allowAudio: json['allowAudio'] as bool,
        allowVideo: json['allowVideo'] as bool,
        isLocked: json['isLocked'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'maxParticipants': maxParticipants,
        'allowAudio': allowAudio,
        'allowVideo': allowVideo,
        'isLocked': isLocked,
      };
}

class RoomPeerList {
  RoomPeerList({required this.roomId, required this.peers});

  final String roomId;
  final List<String> peers;

  factory RoomPeerList.fromJson(Map<String, dynamic> json) => RoomPeerList(
        roomId: json['roomId'] as String,
        peers: (json['peers'] as List<dynamic>)
            .map((peer) => peer['userId'] as String)
            .toList(),
      );
}

class RoomMember {
  RoomMember({required this.userId, required this.joinedAt});

  final String userId;
  final String joinedAt;

  factory RoomMember.fromJson(Map<String, dynamic> json) => RoomMember(
        userId: json['userId'] as String,
        joinedAt: json['joinedAt'] as String,
      );
}

class RoomMemberHistory {
  RoomMemberHistory({
    required this.userId,
    required this.joinedAt,
    required this.leftAt,
    required this.reason,
  });

  final String userId;
  final String joinedAt;
  final String? leftAt;
  final String? reason;

  factory RoomMemberHistory.fromJson(Map<String, dynamic> json) =>
      RoomMemberHistory(
        userId: json['userId'] as String,
        joinedAt: json['joinedAt'] as String,
        leftAt: json['leftAt'] as String?,
        reason: json['reason'] as String?,
      );
}

class TransportOptions {
  TransportOptions({
    required this.id,
    required this.iceParameters,
    required this.iceCandidates,
    required this.dtlsParameters,
  });

  final String id;
  final Map<String, dynamic> iceParameters;
  final List<dynamic> iceCandidates;
  final Map<String, dynamic> dtlsParameters;

  factory TransportOptions.fromJson(Map<String, dynamic> json) =>
      TransportOptions(
        id: json['id'] as String,
        iceParameters: Map<String, dynamic>.from(json['iceParameters'] as Map),
        iceCandidates: List<dynamic>.from(json['iceCandidates'] as List),
        dtlsParameters:
            Map<String, dynamic>.from(json['dtlsParameters'] as Map),
      );
}

class ProducerResponse {
  ProducerResponse({required this.id, required this.kind, this.codec});

  final String id;
  final String kind;
  final String? codec;

  factory ProducerResponse.fromJson(Map<String, dynamic> json) =>
      ProducerResponse(
        id: json['id'] as String,
        kind: json['kind'] as String,
        codec: json['codec'] as String?,
      );
}

class ConsumerResponse {
  ConsumerResponse({
    required this.id,
    required this.producerId,
    required this.kind,
    required this.rtpParameters,
    this.codec,
  });

  final String id;
  final String producerId;
  final String kind;
  final Map<String, dynamic> rtpParameters;
  final String? codec;

  factory ConsumerResponse.fromJson(Map<String, dynamic> json) =>
      ConsumerResponse(
        id: json['id'] as String,
        producerId: json['producerId'] as String,
        kind: json['kind'] as String,
        rtpParameters: Map<String, dynamic>.from(json['rtpParameters'] as Map),
        codec: json['codec'] as String?,
      );
}

enum CsnSupportRequestType {
  videoCall('video_call'),
  liveChat('live_chat');

  const CsnSupportRequestType(this.wireValue);

  final String wireValue;

  static CsnSupportRequestType? fromWireValue(String? value) {
    for (final type in CsnSupportRequestType.values) {
      if (type.wireValue == value) return type;
    }
    return null;
  }
}

class CallRequestCreateResponse {
  CallRequestCreateResponse({
    required this.requestId,
    required this.userId,
    required this.status,
    required this.position,
    required this.etaSeconds,
    required this.token,
    required this.requestType,
  });

  final String requestId;
  final String userId;
  final String status;
  final int position;
  final int etaSeconds;
  final String token;
  final CsnSupportRequestType? requestType;

  factory CallRequestCreateResponse.fromJson(Map<String, dynamic> json) =>
      CallRequestCreateResponse(
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        status: json['status'] as String,
        position: json['position'] as int,
        etaSeconds: json['etaSeconds'] as int,
        token: json['token'] as String,
        requestType:
            CsnSupportRequestType.fromWireValue(json['requestType'] as String?),
      );
}

class CallRequestStatusResponse {
  CallRequestStatusResponse({
    required this.requestId,
    required this.userId,
    required this.status,
    required this.position,
    required this.etaSeconds,
    required this.roomId,
    required this.requestType,
  });

  final String requestId;
  final String userId;
  final String status;
  final int? position;
  final int? etaSeconds;
  final String? roomId;
  final CsnSupportRequestType? requestType;

  factory CallRequestStatusResponse.fromJson(Map<String, dynamic> json) =>
      CallRequestStatusResponse(
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        status: json['status'] as String,
        position: json['position'] as int?,
        etaSeconds: json['etaSeconds'] as int?,
        roomId: json['roomId'] as String?,
        requestType:
            CsnSupportRequestType.fromWireValue(json['requestType'] as String?),
      );
}

class AdminQueueItem {
  AdminQueueItem({
    required this.requestId,
    required this.userId,
    required this.createdAt,
    required this.position,
    required this.etaSeconds,
  });

  final String requestId;
  final String userId;
  final String createdAt;
  final int position;
  final int etaSeconds;

  factory AdminQueueItem.fromJson(Map<String, dynamic> json) => AdminQueueItem(
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        createdAt: json['createdAt'] as String,
        position: json['position'] as int,
        etaSeconds: json['etaSeconds'] as int,
      );
}

class AdminQueueResponse {
  AdminQueueResponse({
    required this.items,
    required this.averageCallSeconds,
    required this.activeCount,
  });

  final List<AdminQueueItem> items;
  final int averageCallSeconds;
  final int activeCount;

  factory AdminQueueResponse.fromJson(Map<String, dynamic> json) =>
      AdminQueueResponse(
        items: (json['items'] as List<dynamic>? ?? [])
            .map(
                (item) => AdminQueueItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        averageCallSeconds: (json['averageCallSeconds'] as num?)?.round() ?? 0,
        activeCount: (json['activeCount'] as num?)?.round() ?? 0,
      );
}

class AdminTokenResponse {
  AdminTokenResponse({
    required this.userId,
    required this.token,
  });

  final String userId;
  final String token;

  factory AdminTokenResponse.fromJson(Map<String, dynamic> json) =>
      AdminTokenResponse(
        userId: json['userId'] as String,
        token: json['token'] as String,
      );
}

class AuthUserProfile {
  AuthUserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final bool isActive;
  final String createdAt;

  factory AuthUserProfile.fromJson(Map<String, dynamic> json) =>
      AuthUserProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        email: json['email'] as String,
        role: json['role'] as String,
        isActive: json['isActive'] as bool? ?? true,
        createdAt: json['createdAt'] as String? ?? '',
      );
}

class AuthLoginResponse {
  AuthLoginResponse({
    required this.token,
    required this.user,
  });

  final String token;
  final AuthUserProfile user;

  factory AuthLoginResponse.fromJson(Map<String, dynamic> json) =>
      AuthLoginResponse(
        token: json['token'] as String,
        user: AuthUserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}

class StaffHistoryItem {
  StaffHistoryItem({
    required this.requestId,
    required this.userId,
    required this.executiveId,
    required this.executiveName,
    required this.status,
    required this.createdAt,
    required this.acceptedAt,
    required this.endedAt,
    required this.timeTakenSeconds,
  });

  final String requestId;
  final String userId;
  final String? executiveId;
  final String? executiveName;
  final String status;
  final String createdAt;
  final String? acceptedAt;
  final String? endedAt;
  final int? timeTakenSeconds;

  factory StaffHistoryItem.fromJson(Map<String, dynamic> json) =>
      StaffHistoryItem(
        requestId: json['requestId'] as String,
        userId: json['userId'] as String,
        executiveId: json['executiveId'] as String?,
        executiveName: json['executiveName'] as String?,
        status: json['status'] as String,
        createdAt: json['createdAt'] as String,
        acceptedAt: json['acceptedAt'] as String?,
        endedAt: json['endedAt'] as String?,
        timeTakenSeconds: json['timeTakenSeconds'] as int?,
      );
}
