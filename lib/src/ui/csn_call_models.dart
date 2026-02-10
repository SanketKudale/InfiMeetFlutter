import 'package:flutter_webrtc/flutter_webrtc.dart';

class CsnParticipant {
  CsnParticipant({
    required this.id,
    required this.displayName,
    required this.isLocal,
    this.videoEnabled = true,
    this.audioEnabled = true,
    this.renderer,
  });

  final String id;
  final String displayName;
  final bool isLocal;
  bool videoEnabled;
  bool audioEnabled;
  RTCVideoRenderer? renderer;
}

enum CsnCallConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  ended,
  error,
}

class CsnCallUiState {
  const CsnCallUiState({
    required this.roomId,
    required this.connectionState,
    required this.participants,
    this.errorMessage,
  });

  final String roomId;
  final CsnCallConnectionState connectionState;
  final List<CsnParticipant> participants;
  final String? errorMessage;
}
