import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../csn_flutter.dart';

class CsnBasicCallController extends CsnCallController {
  CsnBasicCallController({
    required this.apiClient,
    required this.signalingClient,
    required this.localUserId,
  });

  final CsnApiClient apiClient;
  final CsnSignalingClient signalingClient;
  final String localUserId;

  final List<CsnParticipant> _participants = [];
  CsnCallConnectionState _connectionState = CsnCallConnectionState.idle;
  bool _localAudioEnabled = true;
  bool _localVideoEnabled = true;
  bool _speakerEnabled = true;
  String _roomId = '';
  String? _errorMessage;

  StreamSubscription<CsnSignalMessage>? _sub;
  Completer<void>? _joinCompleter;
  Timer? _joinTimeout;
  RTCPeerConnection? _peerConnection;
  RTCRtpSender? _audioSender;
  RTCRtpSender? _videoSender;
  MediaStream? _localStream;
  MediaStream? _localPreviewStream;
  String? _remoteUserId;
  bool _makingOffer = false;
  bool _handlingOffer = false;
  bool _negotiating = false;

  @override
  CsnCallUiState get state => CsnCallUiState(
        roomId: _roomId,
        connectionState: _connectionState,
        participants: List.unmodifiable(_participants),
        errorMessage: _errorMessage,
      );

  @override
  bool get localAudioEnabled => _localAudioEnabled;

  @override
  bool get localVideoEnabled => _localVideoEnabled;

  @override
  bool get speakerEnabled => _speakerEnabled;

  @override
  Future<void> initialize() async {
    await _createLocalMedia();
    _ensureLocalParticipant();
    notifyListeners();
  }

  @override
  Future<void> join(String roomId) async {
    _roomId = roomId;
    _connectionState = CsnCallConnectionState.connecting;
    notifyListeners();

    try {
      await signalingClient.connect();
      _sub ??= signalingClient.messages.listen(
        _handleSignal,
        onError: _handleSignalError,
      );

      _joinCompleter?.completeError(StateError('Join superseded'));
      _joinCompleter = Completer<void>();
      _joinTimeout?.cancel();
      _joinTimeout = Timer(const Duration(seconds: 8), () {
        if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
          _failWithError('Join timed out', null, null);
          _joinCompleter!.completeError(TimeoutException('Join timed out'));
        }
      });

      signalingClient.joinRoom(roomId);
      await _joinCompleter!.future;

      _connectionState = CsnCallConnectionState.connected;
      _errorMessage = null;
      notifyListeners();
    } catch (error, stackTrace) {
      _failWithError('Failed to join room', error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> leave() async {
    try {
      signalingClient.leaveRoom();
    } catch (_) {
      // no-op
    }
    await _disposePeerConnection();
    _connectionState = CsnCallConnectionState.ended;
    notifyListeners();
  }

  @override
  Future<void> toggleAudio() async {
    final next = !_localAudioEnabled;
    if (next) {
      final result = await _ensureLocalTrack(kind: 'audio');
      if (!result.ok) {
        _failWithError('Failed to enable microphone', result.error, result.stackTrace);
        return;
      }
      if (result.requiresRenegotiation) {
        await _safeRenegotiate();
      }
    }
    await _setLocalAudioEnabled(next);
  }

  @override
  Future<void> toggleVideo() async {
    final next = !_localVideoEnabled;
    if (next) {
      final result = await _ensureLocalTrack(kind: 'video');
      if (!result.ok) {
        _failWithError('Failed to enable camera', result.error, result.stackTrace);
        return;
      }
      if (result.requiresRenegotiation) {
        await _safeRenegotiate();
      }
    }
    await _setLocalVideoEnabled(next);
  }

  @override
  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().isNotEmpty == true
        ? _localStream!.getVideoTracks().first
        : null;
    if (track == null) return;
    await Helper.switchCamera(track);
  }

  @override
  Future<void> toggleSpeaker() async {
    _speakerEnabled = !_speakerEnabled;
    await Helper.setSpeakerphoneOn(_speakerEnabled);
    notifyListeners();
  }

  Future<void> _createLocalMedia() async {
    if (_localStream != null) return;
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 720},
        'height': {'ideal': 1280},
        'frameRate': {'ideal': 24},
      },
    });
    _localStream = stream;
    final local = _ensureLocalParticipant();
    local.renderer ??= await _createRenderer();
    await _bindLocalPreview();
    local.audioEnabled = _localAudioEnabled;
    local.videoEnabled = _localVideoEnabled;
  }

  Future<RTCVideoRenderer> _createRenderer() async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    return renderer;
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) return;
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    });
    _peerConnection = pc;

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        if (!track.enabled) continue;
        final sender = await pc.addTrack(track, stream);
        if (track.kind == 'audio') {
          _audioSender = sender;
        } else if (track.kind == 'video') {
          _videoSender = sender;
        }
      }
    }

    pc.onIceCandidate = (candidate) {
      final targetUserId = _remoteUserId;
      if (targetUserId == null) return;
      signalingClient.send(CsnSignalMessage('ice', {
        'targetUserId': targetUserId,
        'payload': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      }));
    };

    pc.onTrack = (event) async {
      if (event.streams.isEmpty) return;
      final stream = event.streams.first;
      final remote = _ensureRemoteParticipant(_remoteUserId ?? 'remote');
      remote.renderer ??= await _createRenderer();
      remote.renderer!.srcObject = stream;
      if (event.track.kind == 'audio') {
        remote.audioEnabled = event.track.enabled;
      } else if (event.track.kind == 'video') {
        remote.videoEnabled = event.track.enabled;
      }
      notifyListeners();
    };

    pc.onConnectionState = (state) {
      debugLog('Peer connection state', state.toString());
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _failWithError('Peer connection closed', null, null);
      }
    };
  }

  Future<void> _createAndSendOffer() async {
    if (_makingOffer) return;
    final target = _remoteUserId;
    if (target == null) return;
    await _ensurePeerConnection();
    final pc = _peerConnection;
    if (pc == null) return;
    _makingOffer = true;
    try {
      final offer = await pc.createOffer({});
      await pc.setLocalDescription(offer);
      signalingClient.send(CsnSignalMessage('offer', {
        'targetUserId': target,
        'payload': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
      }));
    } finally {
      _makingOffer = false;
    }
  }

  Future<void> _handleSignal(CsnSignalMessage message) async {
    if (message.type == 'joined') {
      _completeJoin();
      return;
    }

    if (message.type == 'room-state') {
      final room = CsnRoomState.fromJson(message.payload ?? {});
      _syncParticipants(room);
      final remotes = room.peers.where((id) => id != localUserId).toList();
      if (remotes.isNotEmpty) {
        _remoteUserId = remotes.first;
        final shouldOffer =
            localUserId.compareTo(_remoteUserId!) < 0;
        if (shouldOffer) {
          await _createAndSendOffer();
        }
      }
      return;
    }

    if (message.type == 'peer-joined') {
      final userId = message.payload?['userId'] as String?;
      if (userId == null || userId == localUserId) return;
      _remoteUserId = userId;
      _ensureRemoteParticipant(userId);
      notifyListeners();
      _sendLocalMediaState();
      final shouldOffer = localUserId.compareTo(userId) < 0;
      if (shouldOffer) {
        await _createAndSendOffer();
      }
      return;
    }

    if (message.type == 'peer-left') {
      final userId = message.payload?['userId'] as String?;
      if (userId != null) {
        await _removeParticipant(userId);
      }
      _remoteUserId = null;
      await _disposePeerConnection();
      notifyListeners();
      return;
    }

    if (message.type == 'offer') {
      final from = message.payload?['fromUserId'] as String?;
      final payload = message.payload?['payload'] as Map<String, dynamic>?;
      if (from == null || payload == null) return;
      _remoteUserId = from;
      _ensureRemoteParticipant(from);
      await _ensurePeerConnection();
      final pc = _peerConnection;
      if (pc == null) return;
      if (_handlingOffer) return;
      _handlingOffer = true;
      try {
        await pc.setRemoteDescription(
          RTCSessionDescription(
            payload['sdp'] as String?,
            payload['type'] as String?,
          ),
        );
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        signalingClient.send(CsnSignalMessage('answer', {
          'targetUserId': from,
          'payload': {
            'type': answer.type,
            'sdp': answer.sdp,
          },
        }));
      } finally {
        _handlingOffer = false;
      }
      return;
    }

    if (message.type == 'media-state') {
      final from = message.payload?['fromUserId'] as String?;
      final payload = message.payload?['payload'] as Map<String, dynamic>?;
      if (from == null || payload == null) return;
      final participant = _ensureRemoteParticipant(from);
      final audio = payload['audioEnabled'];
      final video = payload['videoEnabled'];
      if (audio is bool) {
        participant.audioEnabled = audio;
      }
      if (video is bool) {
        participant.videoEnabled = video;
      }
      notifyListeners();
      return;
    }

    if (message.type == 'answer') {
      final payload = message.payload?['payload'] as Map<String, dynamic>?;
      final pc = _peerConnection;
      if (payload == null || pc == null) return;
      await pc.setRemoteDescription(
        RTCSessionDescription(
          payload['sdp'] as String?,
          payload['type'] as String?,
        ),
      );
      return;
    }

    if (message.type == 'ice') {
      final payload = message.payload?['payload'] as Map<String, dynamic>?;
      final pc = _peerConnection;
      if (payload == null || pc == null) return;
      final candidate = payload['candidate'] as String?;
      if (candidate == null || candidate.isEmpty) return;
      await pc.addCandidate(
        RTCIceCandidate(
          candidate,
          payload['sdpMid'] as String?,
          payload['sdpMLineIndex'] as int?,
        ),
      );
      return;
    }

    if (message.type == 'error') {
      _failWithError(
        message.payload?['code']?.toString() ?? 'error',
        null,
        null,
      );
      _completeJoinError(message.payload?['code']?.toString() ?? 'error');
    }
  }

  void _handleSignalError(Object error, StackTrace stackTrace) {
    _failWithError('Signaling error', error, stackTrace);
    _completeJoinError('Signaling error', error);
  }

  void _failWithError(String message, Object? error, StackTrace? stackTrace) {
    debugLog(message, error, stackTrace);
    _connectionState = CsnCallConnectionState.error;
    _errorMessage = _normalizeErrorMessage(message, error);
    notifyListeners();
  }

  void _completeJoin() {
    _joinTimeout?.cancel();
    if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
      _joinCompleter!.complete();
    }
  }

  void _completeJoinError(String message, [Object? error]) {
    _joinTimeout?.cancel();
    if (_joinCompleter != null && !_joinCompleter!.isCompleted) {
      _joinCompleter!.completeError(
        StateError(_normalizeErrorMessage(message, error)),
      );
    }
  }

  String _normalizeErrorMessage(String message, Object? error) {
    if (error == null) return message;
    final text = error.toString();
    if (text.isEmpty) return message;
    return '$message: $text';
  }

  void _syncParticipants(CsnRoomState room) {
    final peerIds = room.peers.toSet();
    final existingIds = _participants.map((p) => p.id).toSet();
    for (final peerId in peerIds) {
      if (!existingIds.contains(peerId)) {
        _participants.add(
          CsnParticipant(
            id: peerId,
            displayName: peerId,
            isLocal: peerId == localUserId,
          ),
        );
      }
    }
    _participants.removeWhere((p) => !peerIds.contains(p.id));
    _ensureLocalParticipant();
    notifyListeners();
  }

  CsnParticipant _ensureLocalParticipant() {
    final existing = _participants.where((p) => p.id == localUserId).toList();
    if (existing.isNotEmpty) return existing.first;
    final local = CsnParticipant(
      id: localUserId,
      displayName: 'You',
      isLocal: true,
      audioEnabled: _localAudioEnabled,
      videoEnabled: _localVideoEnabled,
    );
    _participants.add(local);
    return local;
  }

  CsnParticipant _ensureRemoteParticipant(String userId) {
    final existing = _participants.where((p) => p.id == userId).toList();
    if (existing.isNotEmpty) return existing.first;
    final remote = CsnParticipant(
      id: userId,
      displayName: userId,
      isLocal: false,
    );
    _participants.add(remote);
    return remote;
  }

  Future<void> _removeParticipant(String userId) async {
    final match = _participants.where((p) => p.id == userId).toList();
    if (match.isEmpty) return;
    final participant = match.first;
    final renderer = participant.renderer;
    if (renderer != null) {
      try {
        await renderer.dispose();
      } catch (_) {
        // no-op
      }
    }
    _participants.removeWhere((p) => p.id == userId);
  }

  Future<void> _disposePeerConnection() async {
    final pc = _peerConnection;
    _peerConnection = null;
    _audioSender = null;
    _videoSender = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {
        // no-op
      }
      try {
        await pc.dispose();
      } catch (_) {
        // no-op
      }
    }
  }

  Future<_TrackEnsureResult> _ensureLocalTrack({required String kind}) async {
    try {
      final stream = _localStream;
      if (stream == null) {
        return _TrackEnsureResult.error(StateError('Local stream is not initialized'));
      }

      final existingTracks = kind == 'audio' ? stream.getAudioTracks() : stream.getVideoTracks();
      final staleTracks = List<MediaStreamTrack>.from(existingTracks);

      final extra = await navigator.mediaDevices.getUserMedia({
        'audio': kind == 'audio',
        'video': kind == 'video'
            ? {
                'facingMode': 'user',
              }
            : false,
      });
      final newTrack = kind == 'audio'
          ? (extra.getAudioTracks().isNotEmpty ? extra.getAudioTracks().first : null)
          : (extra.getVideoTracks().isNotEmpty ? extra.getVideoTracks().first : null);
      if (newTrack == null) {
        await extra.dispose();
        return _TrackEnsureResult.error(StateError('No $kind track available'));
      }

      stream.addTrack(newTrack);
      for (final old in staleTracks) {
        try {
          await old.stop();
        } catch (_) {
          // no-op
        }
        stream.removeTrack(old);
      }
      final renegotiate = await _replaceOrAddSenderTrack(newTrack);

      if (kind == 'video') {
        final local = _ensureLocalParticipant();
        local.renderer ??= await _createRenderer();
        local.renderer!.srcObject = stream;
      }
      return _TrackEnsureResult(ok: true, requiresRenegotiation: renegotiate);
    } catch (error, stackTrace) {
      return _TrackEnsureResult.error(error, stackTrace);
    }
  }

  Future<bool> _replaceOrAddSenderTrack(MediaStreamTrack track) async {
    final pc = _peerConnection;
    final stream = _localStream;
    if (pc == null || stream == null) return false;
    if (track.kind == 'audio' && _audioSender != null) {
      await _audioSender!.replaceTrack(track);
      return false;
    }
    if (track.kind == 'video' && _videoSender != null) {
      await _videoSender!.replaceTrack(track);
      return false;
    }
    final senders = await pc.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == track.kind) {
        await sender.replaceTrack(track);
        if (track.kind == 'audio') {
          _audioSender = sender;
        } else if (track.kind == 'video') {
          _videoSender = sender;
        }
        return false;
      }
    }
    final sender = await pc.addTrack(track, stream);
    if (track.kind == 'audio') {
      _audioSender = sender;
    } else if (track.kind == 'video') {
      _videoSender = sender;
    }
    return true;
  }

  Future<void> _setLocalAudioEnabled(bool enabled) async {
    _localAudioEnabled = enabled;
    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getAudioTracks()) {
        track.enabled = enabled;
      }
    }
    if (_audioSender != null) {
      if (enabled) {
        final activeTrack = _localStream?.getAudioTracks().isNotEmpty == true
            ? _localStream!.getAudioTracks().first
            : null;
        if (activeTrack != null) {
          await _audioSender!.replaceTrack(activeTrack);
        }
      } else {
        await _audioSender!.replaceTrack(null);
      }
    }
    final local = _ensureLocalParticipant();
    local.audioEnabled = enabled;
    notifyListeners();
    _sendLocalMediaState();
  }

  Future<void> _setLocalVideoEnabled(bool enabled) async {
    _localVideoEnabled = enabled;
    final stream = _localStream;
    if (stream != null) {
      final videoTracks = List<MediaStreamTrack>.from(stream.getVideoTracks());
      for (final track in videoTracks) {
        track.enabled = enabled;
        if (!enabled) {
          try {
            await track.stop();
          } catch (_) {
            // no-op
          }
          stream.removeTrack(track);
        }
      }
    }
    if (_videoSender != null) {
      if (enabled) {
        final activeTrack = _localStream?.getVideoTracks().isNotEmpty == true
            ? _localStream!.getVideoTracks().first
            : null;
        if (activeTrack != null) {
          await _videoSender!.replaceTrack(activeTrack);
        }
      } else {
        await _videoSender!.replaceTrack(null);
      }
    }
    final local = _ensureLocalParticipant();
    if (!enabled && local.renderer != null) {
      local.renderer!.srcObject = null;
      await _disposeLocalPreviewStream();
    }
    if (enabled) {
      await _refreshLocalPreview();
    }
    local.videoEnabled = enabled;
    notifyListeners();
    _sendLocalMediaState();
  }

  Future<void> _refreshLocalPreview() async {
    final stream = _localStream;
    if (stream == null) return;
    final hasVideo = stream.getVideoTracks().isNotEmpty;
    if (!hasVideo) return;
    final local = _ensureLocalParticipant();
    final previous = local.renderer;
    if (previous != null) {
      try {
        previous.srcObject = null;
      } catch (_) {
        // no-op
      }
      try {
        await previous.dispose();
      } catch (_) {
        // no-op
      }
    }
    final freshRenderer = await _createRenderer();
    local.renderer = freshRenderer;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await _bindLocalPreview(renderer: freshRenderer);
  }

  Future<void> _bindLocalPreview({RTCVideoRenderer? renderer}) async {
    final stream = _localStream;
    if (stream == null) return;
    final videoTracks = stream.getVideoTracks();
    if (videoTracks.isEmpty) return;
    await _disposeLocalPreviewStream();
    final preview = await createLocalMediaStream('csn_local_preview');
    preview.addTrack(videoTracks.first);
    _localPreviewStream = preview;
    final local = _ensureLocalParticipant();
    final targetRenderer = renderer ?? local.renderer;
    if (targetRenderer == null) return;
    targetRenderer.srcObject = preview;
  }

  Future<void> _disposeLocalPreviewStream() async {
    final preview = _localPreviewStream;
    _localPreviewStream = null;
    if (preview == null) return;
    try {
      await preview.dispose();
    } catch (_) {
      // no-op
    }
  }

  Future<void> _safeRenegotiate() async {
    if (_negotiating) return;
    if (_remoteUserId == null) return;
    _negotiating = true;
    try {
      await _createAndSendOffer();
    } finally {
      _negotiating = false;
    }
  }

  void _sendLocalMediaState() {
    final target = _remoteUserId;
    if (target == null) return;
    signalingClient.send(
      CsnSignalMessage(
        'media-state',
        {
          'targetUserId': target,
          'payload': {
            'audioEnabled': _localAudioEnabled,
            'videoEnabled': _localVideoEnabled,
          },
        },
      ),
    );
  }

  @override
  void dispose() {
    _joinTimeout?.cancel();
    unawaited(_sub?.cancel());
    unawaited(_disposePeerConnection());
    final stream = _localStream;
    _localStream = null;
    unawaited(_disposeLocalPreviewStream());
    if (stream != null) {
      for (final track in stream.getTracks()) {
        track.stop();
      }
      unawaited(stream.dispose());
    }
    for (final participant in _participants) {
      final renderer = participant.renderer;
      if (renderer != null) {
        unawaited(renderer.dispose());
      }
    }
    unawaited(signalingClient.close());
    apiClient.close();
    super.dispose();
  }
}

class _TrackEnsureResult {
  const _TrackEnsureResult({
    required this.ok,
    this.requiresRenegotiation = false,
  })  : error = null,
        stackTrace = null;

  const _TrackEnsureResult.error(this.error, [this.stackTrace])
      : ok = false,
        requiresRenegotiation = false;

  final bool ok;
  final bool requiresRenegotiation;
  final Object? error;
  final StackTrace? stackTrace;
}
