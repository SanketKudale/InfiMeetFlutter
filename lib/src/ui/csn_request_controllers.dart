import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/csn_api_client.dart';
import '../api/models.dart';
import '../signaling/csn_signaling_client.dart';
import '../signaling/messages.dart';
import '../utils/debug_log.dart';

class CsnUserRequestState {
  CsnUserRequestState({
    this.requestId,
    this.userId,
    this.status = 'idle',
    this.position,
    this.etaSeconds,
    this.roomId,
    this.token,
    this.timeoutWarningSeconds,
    this.errorMessage,
  });

  final String? requestId;
  final String? userId;
  final String status;
  final int? position;
  final int? etaSeconds;
  final String? roomId;
  final String? token;
  final int? timeoutWarningSeconds;
  final String? errorMessage;

  CsnUserRequestState copyWith({
    String? requestId,
    String? userId,
    String? status,
    int? position,
    int? etaSeconds,
    String? roomId,
    String? token,
    int? timeoutWarningSeconds,
    String? errorMessage,
  }) {
    return CsnUserRequestState(
      requestId: requestId ?? this.requestId,
      userId: userId ?? this.userId,
      status: status ?? this.status,
      position: position ?? this.position,
      etaSeconds: etaSeconds ?? this.etaSeconds,
      roomId: roomId ?? this.roomId,
      token: token ?? this.token,
      timeoutWarningSeconds: timeoutWarningSeconds ?? this.timeoutWarningSeconds,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class CsnUserRequestController extends ChangeNotifier {
  CsnUserRequestController({
    required this.baseUrl,
    required this.wsUrl,
  });

  final String baseUrl;
  final String wsUrl;

  CsnUserRequestState _state = CsnUserRequestState();
  CsnUserRequestState get state => _state;

  CsnApiClient? _apiClient;
  CsnSignalingClient? _signalingClient;
  StreamSubscription? _sub;

  Future<void> submitRequest({String? userId}) async {
    try {
      _state = _state.copyWith(status: 'submitting', errorMessage: null);
      notifyListeners();

      final api = CsnApiClient(baseUrl: baseUrl);
      final result = await api.createCallRequest(userId: userId);
      _apiClient = CsnApiClient(baseUrl: baseUrl, jwt: result.token);
      _signalingClient = CsnSignalingClient(wsUrl: wsUrl, jwt: result.token);

      _state = _state.copyWith(
        requestId: result.requestId,
        userId: result.userId,
        status: result.status,
        position: result.position,
        etaSeconds: result.etaSeconds,
        token: result.token,
      );
      notifyListeners();

      await _connectSignaling();
    } catch (error, stackTrace) {
      debugLog('Submit request failed', error, stackTrace);
      _state = _state.copyWith(status: 'error', errorMessage: error.toString());
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    final requestId = _state.requestId;
    if (requestId == null || _apiClient == null) return;
    try {
      final status = await _apiClient!.getCallRequestStatus(requestId);
      _applyStatus(status);
    } catch (error, stackTrace) {
      debugLog('Refresh request failed', error, stackTrace);
    }
  }

  Future<void> _connectSignaling() async {
    final signaling = _signalingClient;
    if (signaling == null) return;
    try {
      await signaling.connect();
      _sub ??= signaling.messages.listen(
        _handleSignal,
        onError: (Object error, StackTrace stackTrace) {
          debugLog('Request signaling error', error, stackTrace);
        },
      );
    } catch (error, stackTrace) {
      debugLog('Request signaling connect failed', error, stackTrace);
    }
  }

  void _handleSignal(dynamic message) {
    if (message is! CsnSignalMessage) return;
    if (message.type == 'request-warning') {
      _handleWarning(message.payload ?? {});
      return;
    }
    if (message.type != 'request-updated') return;
    final payload = message.payload ?? {};
    final update = CallRequestStatusResponse.fromJson({
      'requestId': payload['requestId'],
      'userId': payload['userId'] ?? _state.userId ?? '',
      'status': payload['status'] ?? _state.status,
      'position': payload['position'],
      'etaSeconds': payload['etaSeconds'],
      'roomId': payload['roomId'],
    });
    _applyStatus(update);
  }

  void _handleWarning(Map<String, dynamic> payload) {
    final seconds = payload['secondsRemaining'];
    if (seconds is int) {
      _state = _state.copyWith(timeoutWarningSeconds: seconds);
      notifyListeners();
    }
  }

  void _applyStatus(CallRequestStatusResponse status) {
    _state = _state.copyWith(
      status: status.status,
      position: status.position,
      etaSeconds: status.etaSeconds,
      roomId: status.roomId,
      timeoutWarningSeconds: null,
      errorMessage: null,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_signalingClient?.close());
    _apiClient?.close();
    super.dispose();
  }
}

class CsnAdminRequestController extends ChangeNotifier {
  CsnAdminRequestController({
    required this.baseUrl,
    required this.adminJwt,
    required this.wsUrl,
  }) {
    _apiClient = CsnApiClient(baseUrl: baseUrl, jwt: adminJwt);
    _signalingClient = CsnSignalingClient(wsUrl: wsUrl, jwt: adminJwt);
    _connectSignaling();
  }

  final String baseUrl;
  final String adminJwt;
  final String wsUrl;
  late final CsnApiClient _apiClient;
  CsnSignalingClient? _signalingClient;
  StreamSubscription? _sub;
  DateTime? _lastQueueUpdate;
  bool _connected = false;

  DateTime? get lastQueueUpdate => _lastQueueUpdate;
  bool get connected => _connected;

  List<AdminQueueItem> _queue = [];
  List<AdminQueueItem> get queue => List.unmodifiable(_queue);

  int _averageCallSeconds = 0;
  int get averageCallSeconds => _averageCallSeconds;

  int _activeCount = 0;
  int get activeCount => _activeCount;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  bool _loading = false;
  bool get loading => _loading;

  Future<void> refreshQueue() async {
    try {
      _loading = true;
      _errorMessage = null;
      notifyListeners();
      final response = await _apiClient.getAdminQueue();
      _queue = response.items;
      _averageCallSeconds = response.averageCallSeconds;
      _activeCount = response.activeCount;
      _lastQueueUpdate = DateTime.now();
    } catch (error, stackTrace) {
      debugLog('Load admin queue failed', error, stackTrace);
      _errorMessage = error.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _connectSignaling() async {
    final signaling = _signalingClient;
    if (signaling == null) return;
    try {
      await signaling.connect();
      _connected = true;
      notifyListeners();
      _sub ??= signaling.messages.listen(
        _handleSignal,
        onError: (Object error, StackTrace stackTrace) {
          debugLog('Admin signaling error', error, stackTrace);
          _connected = false;
          notifyListeners();
        },
      );
    } catch (error, stackTrace) {
      debugLog('Admin signaling connect failed', error, stackTrace);
      _connected = false;
      notifyListeners();
    }
  }

  void _handleSignal(CsnSignalMessage message) {
    if (message.type != 'queue-updated') return;
    final items = (message.payload?['items'] as List<dynamic>? ?? [])
        .map((item) => AdminQueueItem.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    _queue = items;
    _averageCallSeconds =
        (message.payload?['averageCallSeconds'] as num?)?.round() ?? _averageCallSeconds;
    _activeCount = (message.payload?['activeCount'] as num?)?.round() ?? _activeCount;
    _lastQueueUpdate = DateTime.now();
    _errorMessage = null;
    notifyListeners();
  }

  Future<String?> accept(String requestId) async {
    try {
      final roomId = await _apiClient.acceptRequest(requestId);
      await refreshQueue();
      return roomId;
    } catch (error, stackTrace) {
      debugLog('Accept request failed', error, stackTrace);
      return null;
    }
  }

  Future<void> decline(String requestId) async {
    try {
      await _apiClient.declineRequest(requestId);
      await refreshQueue();
    } catch (error, stackTrace) {
      debugLog('Decline request failed', error, stackTrace);
    }
  }

  Future<void> end(String requestId) async {
    try {
      await _apiClient.endRequest(requestId);
      await refreshQueue();
    } catch (error, stackTrace) {
      debugLog('End request failed', error, stackTrace);
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_signalingClient?.close());
    _apiClient.close();
    super.dispose();
  }
}
