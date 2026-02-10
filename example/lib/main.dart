import 'dart:async';

import 'package:csn_flutter/csn_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // no-op
  }
  final plugin = FlutterLocalNotificationsPlugin();
  const settings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
  );
  await plugin.initialize(settings);
  await _showIncomingRequestNotificationFromMessage(plugin, message);
}

Future<void> _showIncomingRequestNotificationFromMessage(
  FlutterLocalNotificationsPlugin notifications,
  RemoteMessage message,
) async {
  final data = message.data;
  if (data['type'] != 'incoming_call_request') return;
  final requestId = (data['requestId'] ?? '').toString();
  final userId = (data['userId'] ?? 'User').toString();
  final id = requestId.isEmpty ? DateTime.now().millisecondsSinceEpoch : requestId.hashCode;
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'incoming_calls',
      'Incoming Calls',
      channelDescription: 'Incoming queue request alerts',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    ),
  );
  await notifications.show(
    id,
    'Incoming call request',
    'User $userId is waiting',
    details,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  } catch (error, stackTrace) {
    debugLog('Firebase initialize failed', error, stackTrace);
  }
  runApp(const CsnExampleApp());
}

class CsnExampleApp extends StatelessWidget {
  const CsnExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSN Example',
      theme: csnTheme(
        brightness: Brightness.light,
        override: CsnThemeData.light().copyWith(
          primary: const Color(0xFF3B82F6),
          accent: const Color(0xFF22D3EE),
        ),
      ),
      home: const CsnHomePage(),
    );
  }
}

class CsnHomePage extends StatefulWidget {
  const CsnHomePage({super.key});

  @override
  State<CsnHomePage> createState() => _CsnHomePageState();
}

class _CsnHomePageState extends State<CsnHomePage> {
  final _baseUrl = TextEditingController(text: 'http://192.168.0.96:6713');
  final _wsUrl = TextEditingController(text: 'ws://192.168.0.96:6713/ws');
  final _userId = TextEditingController();
  final _adminJwt = TextEditingController();
  final _adminUserId = TextEditingController(text: 'admin-1');

  final _notifications = FlutterLocalNotificationsPlugin();
  final Set<String> _seenQueueIds = <String>{};
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  CsnUserRequestController? _userController;
  CsnAdminRequestController? _adminController;
  String? _activeRequestId;
  String? _fcmToken;
  bool _joiningCall = false;
  bool _permissionsRequested = false;
  bool _generatingAdminToken = false;
  bool _firebaseReady = false;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<String>? _onTokenRefreshSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initNotifications();
      await _initFirebaseMessaging();
      await _requestMediaPermissionsOnce();
    });
  }

  Future<void> _initNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _notifications.initialize(settings);
    final android = _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    const channel = AndroidNotificationChannel(
      'incoming_calls',
      'Incoming Calls',
      description: 'Incoming queue request alerts',
      importance: Importance.max,
    );
    await android?.createNotificationChannel(channel);
  }

  Future<void> _initFirebaseMessaging() async {
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (error, stackTrace) {
      debugLog('Firebase init unavailable', error, stackTrace);
      _firebaseReady = false;
      return;
    }

    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _fcmToken = await _messaging.getToken();
    if (_fcmToken != null && _fcmToken!.isNotEmpty) {
      await _registerAdminPushTokenIfPossible(_fcmToken!);
    }

    _onTokenRefreshSub = _messaging.onTokenRefresh.listen((token) async {
      _fcmToken = token;
      await _registerAdminPushTokenIfPossible(token);
    });

    _onMessageSub = FirebaseMessaging.onMessage.listen((message) async {
      await _showIncomingRequestNotificationFromMessage(_notifications, message);
    });
  }

  Future<void> _requestMediaPermissionsOnce() async {
    if (_permissionsRequested) return;
    _permissionsRequested = true;
    try {
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': true,
      });
      for (final track in stream.getTracks()) {
        await track.stop();
      }
      await stream.dispose();
    } catch (error, stackTrace) {
      debugLog('Media permission request failed', error, stackTrace);
    }
  }

  @override
  void dispose() {
    unawaited(_onMessageSub?.cancel());
    unawaited(_onTokenRefreshSub?.cancel());
    final adminJwt = _adminJwt.text.trim();
    final token = _fcmToken;
    if (adminJwt.isNotEmpty && token != null && token.isNotEmpty) {
      final api = CsnApiClient(baseUrl: _baseUrl.text.trim(), jwt: adminJwt);
      unawaited(api.unregisterAdminPushToken(token).whenComplete(api.close));
    }
    _userController?.dispose();
    _adminController?.dispose();
    _baseUrl.dispose();
    _wsUrl.dispose();
    _userId.dispose();
    _adminJwt.dispose();
    _adminUserId.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final controller = CsnUserRequestController(
      baseUrl: _baseUrl.text.trim(),
      wsUrl: _normalizeWsUrl(_wsUrl.text.trim()),
    );
    _userController?.dispose();
    _userController = controller;
    controller.addListener(_onUserUpdate);
    setState(() {});
    await controller.submitRequest(
      userId: _userId.text.trim().isEmpty ? null : _userId.text.trim(),
    );
  }

  Future<void> _onUserUpdate() async {
    final state = _userController?.state;
    if (state == null) return;
    if (state.status == 'accepted' &&
        state.roomId != null &&
        state.token != null &&
        !_joiningCall) {
        await _openCall(
          jwt: state.token!,
          roomId: state.roomId!,
          localUserId: state.userId ?? 'guest',
          onEnded: () async {},
        );
      }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _connectAdmin() async {
    if (_adminJwt.text.trim().isEmpty) {
      _showToast('Admin JWT is required');
      return;
    }
    _adminController?.dispose();
    _adminController = CsnAdminRequestController(
      baseUrl: _baseUrl.text.trim(),
      adminJwt: _adminJwt.text.trim(),
      wsUrl: _normalizeWsUrl(_wsUrl.text.trim()),
    );
    _adminController!.addListener(_onAdminUpdate);
    setState(() {});
    await _registerAdminPushTokenIfPossible(_fcmToken);
    await _adminController!.refreshQueue();
  }

  Future<void> _onAdminUpdate() async {
    final controller = _adminController;
    if (controller == null) return;
    for (final item in controller.queue) {
      if (_seenQueueIds.add(item.requestId)) {
        await _showIncomingRequestNotification(item);
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showIncomingRequestNotification(AdminQueueItem item) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'incoming_calls',
        'Incoming Calls',
        channelDescription: 'Incoming queue request alerts',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: true,
        category: AndroidNotificationCategory.call,
      ),
    );
    await _notifications.show(
      item.requestId.hashCode,
      'Incoming call request',
      'User ${item.userId} is waiting',
      details,
    );
  }

  Future<void> _generateAdminToken() async {
    if (_generatingAdminToken) return;
    _generatingAdminToken = true;
    setState(() {});
    try {
      final client = CsnApiClient(baseUrl: _baseUrl.text.trim());
      final token = await client.createAdminToken(
        userId: _adminUserId.text.trim().isEmpty ? null : _adminUserId.text.trim(),
      );
      _adminJwt.text = token.token;
      if (_adminUserId.text.trim().isEmpty) {
        _adminUserId.text = token.userId;
      }
      await _registerAdminPushTokenIfPossible(_fcmToken);
      client.close();
      _showToast('Admin token generated');
    } catch (error, stackTrace) {
      debugLog('Generate admin token failed', error, stackTrace);
      _showToast('Failed to generate token');
    } finally {
      _generatingAdminToken = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _registerAdminPushTokenIfPossible(String? token) async {
    if (!_firebaseReady) return;
    final adminJwt = _adminJwt.text.trim();
    final cleanToken = token?.trim() ?? '';
    if (adminJwt.isEmpty || cleanToken.isEmpty) return;
    try {
      final api = CsnApiClient(baseUrl: _baseUrl.text.trim(), jwt: adminJwt);
      await api.registerAdminPushToken(cleanToken);
      api.close();
      debugLog('Admin FCM token registered');
    } catch (error, stackTrace) {
      debugLog('Admin FCM token register failed', error, stackTrace);
    }
  }

  Future<void> _accept(AdminQueueItem item) async {
    final admin = _adminController;
    if (admin == null) return;
    final roomId = await admin.accept(item.requestId);
    if (roomId == null) return;
    _activeRequestId = item.requestId;
    await _openCall(
      jwt: _adminJwt.text.trim(),
      roomId: roomId,
      localUserId: _adminUserId.text.trim().isEmpty
          ? 'admin-1'
          : _adminUserId.text.trim(),
      onEnded: () async {
        if (_activeRequestId != null) {
          await admin.end(_activeRequestId!);
          _activeRequestId = null;
        }
      },
    );
  }

  Future<void> _openCall({
    required String jwt,
    required String roomId,
    required String localUserId,
    required Future<void> Function() onEnded,
  }) async {
    if (_joiningCall) return;
    _joiningCall = true;
    try {
      await _requestMediaPermissionsOnce();
      final sdk = CsnSdk(
        baseUrl: _baseUrl.text.trim(),
        wsUrl: _normalizeWsUrl(_wsUrl.text.trim()),
        jwt: jwt,
      );
      final controller = CsnBasicCallController(
        apiClient: sdk.api,
        signalingClient: sdk.signaling(),
        localUserId: localUserId,
      );
      await controller.initialize();
      await controller.join(roomId);
      if (!mounted) {
        await controller.leave();
        controller.dispose();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CsnCallScreen(
            controller: controller,
            onEndCall: () async {
              await controller.leave();
              await onEnded();
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ),
      );
      controller.dispose();
    } catch (error, stackTrace) {
      debugLog('Open call failed', error, stackTrace);
      _showToast('Failed to start call');
    } finally {
      _joiningCall = false;
    }
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _normalizeWsUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('ws://') || trimmed.startsWith('wss://')) {
      return trimmed;
    }
    if (trimmed.startsWith('http://')) {
      return trimmed.replaceFirst('http://', 'ws://');
    }
    if (trimmed.startsWith('https://')) {
      return trimmed.replaceFirst('https://', 'wss://');
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = CsnTheme.of(context);
    final userState = _userController?.state;
    final admin = _adminController;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('CSN Example'),
          backgroundColor: theme.primary,
          bottom: const TabBar(tabs: [Tab(text: 'User'), Tab(text: 'Admin')]),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Field(label: 'API Base URL', controller: _baseUrl),
                _Field(label: 'WS URL', controller: _wsUrl),
                _Field(label: 'User ID', controller: _userId),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _submitRequest,
                  child: const Text('Request Call'),
                ),
                const SizedBox(height: 8),
                _InfoRow(label: 'Status', value: userState?.status ?? 'idle'),
                _InfoRow(
                  label: 'Position',
                  value: userState?.position?.toString() ?? '-',
                ),
                _InfoRow(
                  label: 'ETA',
                  value: userState?.etaSeconds?.toString() ?? '-',
                ),
                _InfoRow(label: 'Room', value: userState?.roomId ?? '-'),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Field(label: 'API Base URL', controller: _baseUrl),
                _Field(label: 'WS URL', controller: _wsUrl),
                _Field(label: 'Admin User ID', controller: _adminUserId),
                _Field(label: 'Admin JWT', controller: _adminJwt, obscure: true),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    ElevatedButton(
                      onPressed: _connectAdmin,
                      child: const Text('Connect Admin'),
                    ),
                    OutlinedButton(
                      onPressed:
                          _generatingAdminToken ? null : _generateAdminToken,
                      child: Text(
                        _generatingAdminToken ? 'Generating...' : 'Get Token',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: admin?.refreshQueue,
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow(
                  label: 'Live',
                  value: admin?.connected == true ? 'Connected' : 'Disconnected',
                ),
                _InfoRow(
                  label: 'Active Calls',
                  value: admin?.activeCount.toString() ?? '-',
                ),
                _InfoRow(
                  label: 'Avg Call (sec)',
                  value: admin?.averageCallSeconds.toString() ?? '-',
                ),
                for (final item in admin?.queue ?? const <AdminQueueItem>[])
                  Card(
                    child: ListTile(
                      title: Text('User ${item.userId}'),
                      subtitle: Text(
                        'Pos ${item.position}  ETA ${item.etaSeconds}s',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => _accept(item),
                            child: const Text('Accept'),
                          ),
                          TextButton(
                            onPressed: () => admin?.decline(item.requestId),
                            child: const Text('Decline'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.obscure = false,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
