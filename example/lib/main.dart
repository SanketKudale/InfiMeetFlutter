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
  final id = requestId.isEmpty
      ? DateTime.now().millisecondsSinceEpoch
      : requestId.hashCode;
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
  static const String _baseUrl = 'https://api.deafott.com/';
  static const String _wsUrl = 'wss://api.deafott.com/ws';
  static const String _adminUserId = 'inclusigninnovations@gmail.com';

  final _notifications = FlutterLocalNotificationsPlugin();
  final Set<String> _seenQueueIds = <String>{};
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  CsnAdminRequestController? _adminController;
  String? _adminJwt;
  String? _activeRequestId;
  String? _fcmToken;
  bool _joiningCall = false;
  bool _connectingAdmin = false;
  bool _permissionsRequested = false;
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
    final android = _notifications.resolvePlatformSpecificImplementation<
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
      await _showIncomingRequestNotificationFromMessage(
          _notifications, message);
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
    final adminJwt = (_adminJwt ?? '').trim();
    final token = _fcmToken;
    if (adminJwt.isNotEmpty && token != null && token.isNotEmpty) {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: adminJwt);
      unawaited(api.unregisterAdminPushToken(token).whenComplete(api.close));
    }
    _adminController?.dispose();
    super.dispose();
  }

  Future<void> _connectAdmin() async {
    if (_connectingAdmin) return;
    _connectingAdmin = true;
    setState(() {});
    try {
      final client = CsnApiClient(baseUrl: _baseUrl);
      final token = await client.createAdminToken(userId: _adminUserId);
      _adminJwt = token.token;
      client.close();

      if ((_adminJwt ?? '').isEmpty) {
        _showToast('Failed to fetch admin token');
        return;
      }

      _adminController?.dispose();
      _adminController = CsnAdminRequestController(
        baseUrl: _baseUrl,
        adminJwt: _adminJwt!,
        wsUrl: _normalizeWsUrl(_wsUrl),
      );
      _adminController!.addListener(_onAdminUpdate);
      await _registerAdminPushTokenIfPossible(_fcmToken);
      await _adminController!.refreshQueue();
    } catch (error, stackTrace) {
      debugLog('Connect admin failed', error, stackTrace);
      _showToast('Failed to connect admin');
    } finally {
      _connectingAdmin = false;
      if (mounted) setState(() {});
    }
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

  Future<void> _registerAdminPushTokenIfPossible(String? token) async {
    if (!_firebaseReady) return;
    final adminJwt = (_adminJwt ?? '').trim();
    final cleanToken = token?.trim() ?? '';
    if (adminJwt.isEmpty || cleanToken.isEmpty) return;
    try {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: adminJwt);
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
      jwt: (_adminJwt ?? '').trim(),
      roomId: roomId,
      localUserId: _adminUserId,
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
        baseUrl: _baseUrl,
        wsUrl: _normalizeWsUrl(_wsUrl),
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
    final admin = _adminController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CSN Admin'),
        backgroundColor: theme.primary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton(
                onPressed: _connectingAdmin ? null : _connectAdmin,
                child: Text(
                  _connectingAdmin ? 'Connecting...' : 'Connect Admin',
                ),
              ),
              OutlinedButton(
                onPressed: admin?.refreshQueue,
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _InfoRow(
            label: 'Admin',
            value: _adminUserId,
          ),
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
