import 'dart:async';

import 'package:flutter/foundation.dart';

import '../signaling/csn_signaling_client.dart';
import '../signaling/messages.dart';
import '../utils/debug_log.dart';

class CsnLiveChatMessage {
  const CsnLiveChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
  });

  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;
}

class CsnLiveChatController extends ChangeNotifier {
  CsnLiveChatController({
    required this.signalingClient,
    required this.localUserId,
    required this.roomId,
  });

  final CsnSignalingClient signalingClient;
  final String localUserId;
  final String roomId;

  final List<CsnLiveChatMessage> _messages = <CsnLiveChatMessage>[];
  StreamSubscription<CsnSignalMessage>? _sub;
  bool _connected = false;
  bool _connecting = false;
  bool _ending = false;
  String? _remoteUserId;
  String? _errorMessage;

  List<CsnLiveChatMessage> get messages => List.unmodifiable(_messages);
  bool get connected => _connected;
  bool get connecting => _connecting;
  String? get errorMessage => _errorMessage;

  Future<void> connect() async {
    if (_connected || _connecting) return;
    _connecting = true;
    notifyListeners();
    try {
      await signalingClient.connect();
      _sub ??= signalingClient.messages.listen(
        _handleSignal,
        onError: (Object error, StackTrace stackTrace) {
          debugLog('Live chat signaling error', error, stackTrace);
          _errorMessage = error.toString();
          notifyListeners();
        },
      );
      signalingClient.joinRoom(roomId);
      _connected = true;
      _errorMessage = null;
    } catch (error, stackTrace) {
      debugLog('Live chat connect failed', error, stackTrace);
      _errorMessage = error.toString();
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  void sendMessage(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    final remoteUserId = _remoteUserId;
    if (remoteUserId == null) {
      _errorMessage = 'Peer not connected yet';
      notifyListeners();
      return;
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final local = CsnLiveChatMessage(
      id: '${DateTime.now().microsecondsSinceEpoch}_$localUserId',
      senderId: localUserId,
      text: text,
      sentAt: DateTime.now(),
    );
    _messages.add(local);
    _errorMessage = null;
    notifyListeners();
    signalingClient.send(
      CsnSignalMessage('chat-message', {
        'targetUserId': remoteUserId,
        'payload': {
          'text': text,
          'sentAt': now,
        },
      }),
    );
  }

  Future<void> leave() async {
    if (_ending) return;
    _ending = true;
    try {
      try {
        signalingClient.leaveRoom();
      } catch (_) {
        // no-op
      }
      await _sub?.cancel();
      _sub = null;
      await signalingClient.close();
      _connected = false;
      notifyListeners();
    } finally {
      _ending = false;
    }
  }

  void _handleSignal(CsnSignalMessage message) {
    if (message.type == 'room-state') {
      final room = CsnRoomState.fromJson(message.payload ?? {});
      final remotes = room.peers.where((id) => id != localUserId).toList();
      if (remotes.isNotEmpty) {
        _remoteUserId = remotes.first;
      }
      notifyListeners();
      return;
    }
    if (message.type == 'peer-joined') {
      final userId = message.payload?['userId']?.toString();
      if (userId != null && userId != localUserId) {
        _remoteUserId = userId;
      }
      notifyListeners();
      return;
    }
    if (message.type == 'peer-left') {
      _errorMessage = 'Peer left chat';
      unawaited(leave());
      return;
    }
    if (message.type == 'request-updated') {
      final status = message.payload?['status']?.toString();
      final updatedRoomId = message.payload?['roomId']?.toString();
      if ((status == 'ended' || status == 'declined') &&
          (updatedRoomId == null || updatedRoomId == roomId)) {
        _errorMessage = 'Chat ended';
        unawaited(leave());
      }
      return;
    }
    if (message.type != 'chat-message') return;
    final from = message.payload?['fromUserId']?.toString();
    final wrapped = message.payload?['payload'];
    String? text;
    String? sentAtRaw;
    if (wrapped is Map<String, dynamic>) {
      text = wrapped['text']?.toString();
      sentAtRaw = wrapped['sentAt']?.toString();
    } else if (message.payload != null) {
      text = message.payload?['text']?.toString();
      sentAtRaw = message.payload?['sentAt']?.toString();
    }
    if (text == null || text.trim().isEmpty) return;
    final senderId = from ??
        message.payload?['senderId']?.toString() ??
        _remoteUserId ??
        'peer';
    if (senderId == localUserId) return;
    final sentAt = DateTime.tryParse(sentAtRaw ?? '') ?? DateTime.now();
    _messages.add(
      CsnLiveChatMessage(
        id: '${DateTime.now().microsecondsSinceEpoch}_$senderId',
        senderId: senderId,
        text: text.trim(),
        sentAt: sentAt,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(signalingClient.close());
    super.dispose();
  }
}
