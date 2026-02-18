import 'dart:async';
import 'dart:convert';

import 'package:csn_flutter/csn_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _appName = 'Deafott Customer Support';

enum _StaffRole {
  admin,
  executive,
}

const String _sessionTokenKey = 'csn_session_token';
const String _sessionRoleKey = 'csn_session_role';
const String _sessionUserIdKey = 'csn_session_user_id';
const String _sessionUserNameKey = 'csn_session_user_name';
const String _sessionUserEmailKey = 'csn_session_user_email';

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
    android: AndroidInitializationSettings(
        '@drawable/ic_admin_support_notification'),
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
      icon: 'ic_admin_support_notification',
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
      title: _appName,
      debugShowCheckedModeBanner: false,
      theme: csnTheme(
        brightness: Brightness.dark,
        override: CsnThemeData.dark().copyWith(
          primary: const Color(0xFF22C3EE),
          accent: const Color(0xFF64D2FF),
          background: const Color(0xFF080D17),
          surface: const Color(0xFF111827),
          text: const Color(0xFFE6EDF7),
          mutedText: const Color(0xFF9FB0C9),
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

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newExecutiveNameController = TextEditingController();
  final _newExecutiveEmailController = TextEditingController();
  final _newExecutivePasswordController = TextEditingController();
  _StaffRole _selectedRole = _StaffRole.executive;
  String? _loginError;
  bool _authenticated = false;
  bool _sessionReady = false;
  bool _loadingLogin = false;
  bool _loadingAdminData = false;
  bool _creatingExecutive = false;

  final _notifications = FlutterLocalNotificationsPlugin();
  final Set<String> _seenQueueIds = <String>{};
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  CsnAdminRequestController? _adminController;
  String? _adminJwt;
  String? _currentUserId;
  String? _currentUserName;
  String? _currentUserEmail;
  _StaffRole? _currentRole;
  List<AuthUserProfile> _executives = [];
  List<StaffHistoryItem> _history = [];
  List<StaffHistoryItem> _executiveHistory = [];
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
      await _restoreSession();
      await _initNotifications();
      await _initFirebaseMessaging();
      await _requestMediaPermissionsOnce();
      if (mounted) {
        setState(() {
          _sessionReady = true;
        });
      }
    });
  }

  Future<void> _initNotifications() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings(
          '@drawable/ic_admin_support_notification'),
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
    if (_currentRole == _StaffRole.executive &&
        adminJwt.isNotEmpty &&
        token != null &&
        token.isNotEmpty) {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: adminJwt);
      unawaited(api.unregisterAdminPushToken(token).whenComplete(api.close));
    }
    _emailController.dispose();
    _passwordController.dispose();
    _newExecutiveNameController.dispose();
    _newExecutiveEmailController.dispose();
    _newExecutivePasswordController.dispose();
    _adminController?.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_loadingLogin) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _loginError = 'Email and password are required';
      });
      return;
    }
    _loadingLogin = true;
    setState(() {});
    try {
      final client = CsnApiClient(baseUrl: _baseUrl);
      final login = _selectedRole == _StaffRole.admin
          ? await client.loginAdmin(email: email, password: password)
          : await client.loginExecutive(email: email, password: password);
      client.close();
      _adminJwt = login.token;
      _currentUserId = login.user.id;
      _currentUserName = login.user.name;
      _currentUserEmail = login.user.email;
      _currentRole = _selectedRole;
      await _saveSession();
      setState(() {
        _authenticated = true;
        _loginError = null;
      });
      if (_selectedRole == _StaffRole.executive) {
        await _connectExecutive();
      } else {
        await _loadAdminDashboard();
      }
    } catch (error, stackTrace) {
      debugLog('Staff login failed', error, stackTrace);
      setState(() {
        _loginError = 'Invalid email or password';
      });
    } finally {
      _loadingLogin = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _saveSession() async {
    final token = _adminJwt?.trim() ?? '';
    final role = _currentRole;
    final userId = _currentUserId?.trim() ?? '';
    if (token.isEmpty || role == null || userId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionTokenKey, token);
    await prefs.setString(_sessionRoleKey, role.name);
    await prefs.setString(_sessionUserIdKey, userId);
    await prefs.setString(_sessionUserNameKey, _currentUserName ?? '');
    await prefs.setString(_sessionUserEmailKey, _currentUserEmail ?? '');
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionTokenKey);
    await prefs.remove(_sessionRoleKey);
    await prefs.remove(_sessionUserIdKey);
    await prefs.remove(_sessionUserNameKey);
    await prefs.remove(_sessionUserEmailKey);
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_sessionTokenKey)?.trim() ?? '';
    final roleValue = prefs.getString(_sessionRoleKey)?.trim() ?? '';
    if (token.isEmpty || roleValue.isEmpty || _isJwtExpired(token)) {
      await _clearSession();
      return;
    }
    final role = _StaffRole.values.where((it) => it.name == roleValue).toList();
    if (role.isEmpty) {
      await _clearSession();
      return;
    }
    _adminJwt = token;
    _currentRole = role.first;
    _selectedRole = role.first;
    _currentUserId = prefs.getString(_sessionUserIdKey);
    _currentUserName = prefs.getString(_sessionUserNameKey);
    _currentUserEmail = prefs.getString(_sessionUserEmailKey);
    _authenticated = true;
    if (_currentRole == _StaffRole.executive) {
      await _connectExecutive();
    } else {
      await _loadAdminDashboard();
    }
  }

  bool _isJwtExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return true;
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final json = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (json is! Map<String, dynamic>) return true;
      final exp = json['exp'];
      if (exp is! num) return true;
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000);
      return DateTime.now().isAfter(expiresAt);
    } catch (_) {
      return true;
    }
  }

  Future<void> _connectExecutive() async {
    if (_connectingAdmin) return;
    _connectingAdmin = true;
    setState(() {});
    try {
      if ((_adminJwt ?? '').isEmpty) {
        _showToast('Login required');
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
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: _adminJwt);
      _executiveHistory = await api.getExecutiveHistory(limit: 150);
      api.close();
    } catch (error, stackTrace) {
      debugLog('Connect executive failed', error, stackTrace);
      final message = error.toString();
      if (message.contains('401')) {
        _showToast('Session expired. Please login again.');
        _logout();
      } else {
        _showToast('Failed to connect executive');
      }
    } finally {
      _connectingAdmin = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _loadAdminDashboard() async {
    final jwt = (_adminJwt ?? '').trim();
    if (jwt.isEmpty) return;
    _loadingAdminData = true;
    setState(() {});
    try {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: jwt);
      final executives = await api.listExecutives();
      final history = await api.getAdminHistory(limit: 300);
      api.close();
      _executives = executives;
      _history = history;
    } catch (error, stackTrace) {
      debugLog('Load admin dashboard failed', error, stackTrace);
      final message = error.toString();
      if (message.contains('401')) {
        _showToast('Session expired. Please login again.');
        _logout();
      } else {
        _showToast('Failed to load admin dashboard');
      }
    } finally {
      _loadingAdminData = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _createExecutive() async {
    if (_creatingExecutive) return;
    final jwt = (_adminJwt ?? '').trim();
    if (jwt.isEmpty) return;
    final name = _newExecutiveNameController.text.trim();
    final email = _newExecutiveEmailController.text.trim();
    final password = _newExecutivePasswordController.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      _showToast('Name, email and password are required');
      return;
    }

    _creatingExecutive = true;
    setState(() {});
    try {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: jwt);
      await api.createExecutive(name: name, email: email, password: password);
      api.close();
      _newExecutiveNameController.clear();
      _newExecutiveEmailController.clear();
      _newExecutivePasswordController.clear();
      await _loadAdminDashboard();
      _showToast('Executive created');
    } catch (error, stackTrace) {
      debugLog('Create executive failed', error, stackTrace);
      _showToast('Failed to create executive');
    } finally {
      _creatingExecutive = false;
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
        icon: 'ic_admin_support_notification',
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
    if (_currentRole != _StaffRole.executive) return;
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
    final resolvedRequestType = await _resolveRequestType(item);
    final roomId = await admin.accept(item.requestId);
    if (roomId == null) return;
    _activeRequestId = item.requestId;
    Future<void> onEnded() async {
      if (_activeRequestId != null) {
        await admin.end(_activeRequestId!);
        _activeRequestId = null;
        final jwt = (_adminJwt ?? '').trim();
        if (jwt.isNotEmpty) {
          final api = CsnApiClient(baseUrl: _baseUrl, jwt: jwt);
          _executiveHistory = await api.getExecutiveHistory(limit: 150);
          api.close();
        }
      }
    }
    if (resolvedRequestType == CsnSupportRequestType.liveChat) {
      await _openLiveChat(
        jwt: (_adminJwt ?? '').trim(),
        roomId: roomId,
        localUserId: _currentUserId ?? 'executive',
        onEnded: onEnded,
      );
      return;
    }
    await _openCall(
      jwt: (_adminJwt ?? '').trim(),
      roomId: roomId,
      localUserId: _currentUserId ?? 'executive',
      onEnded: onEnded,
    );
  }

  Future<CsnSupportRequestType?> _resolveRequestType(AdminQueueItem item) async {
    if (item.requestType != null) return item.requestType;
    final jwt = (_adminJwt ?? '').trim();
    if (jwt.isEmpty) return null;
    try {
      final api = CsnApiClient(baseUrl: _baseUrl, jwt: jwt);
      final status = await api.getCallRequestStatus(item.requestId);
      api.close();
      return status.requestType;
    } catch (error, stackTrace) {
      debugLog('Resolve request type failed', error, stackTrace);
      return null;
    }
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
            onEndCall: () {
              unawaited(onEnded());
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

  Future<void> _openLiveChat({
    required String jwt,
    required String roomId,
    required String localUserId,
    required Future<void> Function() onEnded,
  }) async {
    if (_joiningCall) return;
    _joiningCall = true;
    try {
      final sdk = CsnSdk(
        baseUrl: _baseUrl,
        wsUrl: _normalizeWsUrl(_wsUrl),
        jwt: jwt,
      );
      final controller = CsnLiveChatController(
        signalingClient: sdk.signaling(),
        localUserId: localUserId,
        roomId: roomId,
      );
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CsnLiveChatScreen(
            controller: controller,
            title: 'Support Chat',
            onEndChat: onEnded,
          ),
        ),
      );
      controller.dispose();
    } catch (error, stackTrace) {
      debugLog('Open live chat failed', error, stackTrace);
      _showToast('Failed to start live chat');
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

  Widget _buildLoginPage(CsnThemeData theme) {
    return Scaffold(
      backgroundColor: theme.background,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050914), Color(0xFF111827), Color(0xFF0C162B)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xAA0F172A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2E3E5B)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55000000),
                      blurRadius: 22,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _SupportLogo(size: 80),
                    const SizedBox(height: 14),
                    Text(
                      _appName,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Staff Login',
                      style: TextStyle(color: theme.mutedText),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<_StaffRole>(
                      segments: const [
                        ButtonSegment<_StaffRole>(
                          value: _StaffRole.executive,
                          icon: Icon(Icons.support_agent),
                          label: Text('Executive'),
                        ),
                        ButtonSegment<_StaffRole>(
                          value: _StaffRole.admin,
                          icon: Icon(Icons.admin_panel_settings),
                          label: Text('Admin'),
                        ),
                      ],
                      selected: {_selectedRole},
                      onSelectionChanged: (value) {
                        setState(() {
                          _selectedRole = value.first;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _emailController,
                      style: TextStyle(color: theme.text),
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      style: TextStyle(color: theme.text),
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                      onSubmitted: (_) => unawaited(_handleLogin()),
                    ),
                    if (_loginError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _loginError!,
                        style: const TextStyle(color: Color(0xFFF87171)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _loadingLogin
                            ? null
                            : () => unawaited(_handleLogin()),
                        icon: const Icon(Icons.login),
                        label: Text(_loadingLogin ? 'Logging in...' : 'Login'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _logout() {
    unawaited(_clearSession());
    _adminController?.dispose();
    _adminController = null;
    setState(() {
      _authenticated = false;
      _loginError = null;
      _passwordController.clear();
      _adminJwt = null;
      _currentUserId = null;
      _currentUserName = null;
      _currentUserEmail = null;
      _currentRole = null;
      _executives = [];
      _history = [];
      _executiveHistory = [];
    });
  }

  Widget _buildExecutivePage(CsnThemeData theme) {
    final admin = _adminController;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.surface,
        titleSpacing: 12,
        title: const Row(
          children: [
            _SupportLogo(size: 34),
            SizedBox(width: 10),
            Expanded(child: Text(_appName, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF080D17), Color(0xFF0F172A)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xCC111827),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A3A52)),
              ),
              child: Column(
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _connectingAdmin ? null : _connectExecutive,
                        icon: const Icon(Icons.support_agent),
                        label: Text(
                          _connectingAdmin
                              ? 'Connecting...'
                              : 'Connect Executive',
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: admin?.refreshQueue,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh Queue'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Executive', value: _currentUserName ?? '-'),
                  _InfoRow(
                    label: 'Live',
                    value:
                        admin?.connected == true ? 'Connected' : 'Disconnected',
                  ),
                  _InfoRow(
                    label: 'Active Calls',
                    value: admin?.activeCount.toString() ?? '-',
                  ),
                  _InfoRow(
                    label: 'Avg Call (sec)',
                    value: admin?.averageCallSeconds.toString() ?? '-',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            for (final item in admin?.queue ?? const <AdminQueueItem>[])
              Card(
                color: const Color(0xFF141C2E),
                child: ListTile(
                  title: Text(
                    'User ${item.userId}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    '${item.requestType == CsnSupportRequestType.liveChat ? 'Live Chat' : 'Video Call'}'
                    ' | Pos ${item.position}  ETA ${item.etaSeconds}s',
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
            const SizedBox(height: 16),
            const Text(
              'My History',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 8),
            for (final item in _executiveHistory)
              Card(
                color: const Color(0xFF141C2E),
                child: ListTile(
                  title: Text('User ${item.userId}'),
                  subtitle: Text(
                    'Status: ${item.status} | Time: ${item.timeTakenSeconds ?? 0}s',
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminPage(CsnThemeData theme) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: theme.surface,
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadingAdminData ? null : _loadAdminDashboard,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: _logout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xCC111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2A3A52)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: 'Admin', value: _currentUserName ?? '-'),
                _InfoRow(label: 'Email', value: _currentUserEmail ?? '-'),
                _InfoRow(
                  label: 'Executives',
                  value: _executives.length.toString(),
                ),
                _InfoRow(
                  label: 'History Items',
                  value: _history.length.toString(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xFF141C2E),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Executive',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newExecutiveNameController,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newExecutiveEmailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newExecutivePasswordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _creatingExecutive
                        ? null
                        : () => unawaited(_createExecutive()),
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(_creatingExecutive
                        ? 'Creating...'
                        : 'Create Executive'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Executives',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          for (final executive in _executives)
            Card(
              color: const Color(0xFF141C2E),
              child: ListTile(
                title: Text(executive.name),
                subtitle: Text(executive.email),
                trailing: Text(executive.isActive ? 'Active' : 'Inactive'),
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Call History',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_loadingAdminData) const LinearProgressIndicator(),
          for (final item in _history)
            Card(
              color: const Color(0xFF141C2E),
              child: ListTile(
                title: Text(
                  '${item.executiveName ?? 'Unassigned'} -> ${item.userId}',
                ),
                subtitle: Text(
                  'Status: ${item.status} | Time: ${item.timeTakenSeconds ?? 0}s',
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = CsnTheme.of(context);
    if (!_sessionReady) {
      return Scaffold(
        backgroundColor: theme.background,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_authenticated) return _buildLoginPage(theme);
    if (_currentRole == _StaffRole.admin) return _buildAdminPage(theme);
    return _buildExecutivePage(theme);
  }
}

class _SupportLogo extends StatelessWidget {
  const _SupportLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22C3EE), Color(0xFF1E5BFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x5522C3EE),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Icon(
        Icons.support_agent_rounded,
        color: Colors.white,
        size: size * 0.58,
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
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF9FB0C9),
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
