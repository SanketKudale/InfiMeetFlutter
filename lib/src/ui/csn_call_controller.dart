import 'package:flutter/foundation.dart';

import 'csn_call_models.dart';

abstract class CsnCallController extends ChangeNotifier {
  CsnCallUiState get state;
  bool get localAudioEnabled;
  bool get localVideoEnabled;
  bool get speakerEnabled;
  bool get screenSharingEnabled;

  Future<void> initialize();
  Future<void> join(String roomId);
  Future<void> leave();

  Future<void> toggleAudio();
  Future<void> toggleVideo();
  Future<void> toggleScreenShare();
  Future<void> switchCamera();
  Future<void> toggleSpeaker();
}
