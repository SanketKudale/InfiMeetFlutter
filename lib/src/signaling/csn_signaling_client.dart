import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';

import 'messages.dart';
import '../utils/debug_log.dart';

class CsnSignalingClient {
  CsnSignalingClient({required this.wsUrl, this.jwt});

  final String wsUrl;
  final String? jwt;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  bool _closedManually = false;
  bool _connecting = false;
  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _keepAliveTimer;
  final _controller = StreamController<CsnSignalMessage>.broadcast();

  Stream<CsnSignalMessage> get messages => _controller.stream;
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    _closedManually = false;
    _reconnectTimer?.cancel();
    if (_channel != null || _connecting) return;
    await _connectInternal();
  }

  Future<void> _connectInternal() async {
    if (_channel != null || _connecting || _closedManually) return;
    _connecting = true;
    final uri = _buildWsUri();
    try {
      debugLog(
        'Connecting signaling',
        {
          'url': uri.toString(),
        },
      );
      _channel = IOWebSocketChannel.connect(uri);
      _reconnectAttempts = 0;
      _startKeepAlive();
      _channelSubscription = _channel!.stream.listen(
        (data) {
          final jsonData = jsonDecode(data as String) as Map<String, dynamic>;
          _emit(CsnSignalMessage.fromJson(jsonData));
        },
        onError: (Object error, StackTrace stackTrace) {
          debugLog('Signaling socket error', error, stackTrace);
          _emitError(error, stackTrace);
          _channel = null;
          _channelSubscription = null;
          _stopKeepAlive();
          _scheduleReconnect();
        },
        onDone: () {
          debugLog('Signaling socket closed');
          _channel = null;
          _channelSubscription = null;
          _stopKeepAlive();
          _scheduleReconnect();
        },
      );
    } catch (error, stackTrace) {
      debugLog('Failed to connect signaling: $uri', error, stackTrace);
      _channel = null;
      _scheduleReconnect();
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  void send(CsnSignalMessage message) {
    if (_channel == null) {
      debugLog(
          'Attempted to send signaling message before connect: ${message.type}');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
    } catch (error, stackTrace) {
      debugLog('Failed to send signaling message: ${message.type}', error,
          stackTrace);
      _emitError(error, stackTrace);
    }
  }

  void joinRoom(String roomId) =>
      send(CsnSignalMessage('join', {'roomId': roomId}));
  void leaveRoom() => send(CsnSignalMessage('leave'));
  void getRtpCapabilities() => send(CsnSignalMessage('get-rtp-capabilities'));
  void createTransport() => send(CsnSignalMessage('create-transport'));
  void connectTransport(
          String transportId, Map<String, dynamic> dtlsParameters) =>
      send(CsnSignalMessage('connect-transport', {
        'transportId': transportId,
        'dtlsParameters': dtlsParameters,
      }));

  void produce(String transportId, String kind,
          Map<String, dynamic> rtpParameters) =>
      send(CsnSignalMessage('produce', {
        'transportId': transportId,
        'kind': kind,
        'rtpParameters': rtpParameters,
      }));

  void consume(String transportId, String producerId,
          Map<String, dynamic> rtpCapabilities) =>
      send(CsnSignalMessage('consume', {
        'transportId': transportId,
        'producerId': producerId,
        'rtpCapabilities': rtpCapabilities,
      }));

  void closeProducer(String producerId) =>
      send(CsnSignalMessage('close-producer', {
        'producerId': producerId,
      }));

  void pauseProducer(String producerId) =>
      send(CsnSignalMessage('pause-producer', {
        'producerId': producerId,
      }));

  void resumeProducer(String producerId) =>
      send(CsnSignalMessage('resume-producer', {
        'producerId': producerId,
      }));

  void pauseConsumer(String consumerId) =>
      send(CsnSignalMessage('pause-consumer', {
        'consumerId': consumerId,
      }));

  void resumeConsumer(String consumerId) =>
      send(CsnSignalMessage('resume-consumer', {
        'consumerId': consumerId,
      }));

  void getMediaStats() => send(CsnSignalMessage('get-media-stats'));

  Future<void> close() async {
    try {
      _closedManually = true;
      _reconnectTimer?.cancel();
      _stopKeepAlive();
      await _channelSubscription?.cancel();
      _channelSubscription = null;
      await _channel?.sink.close();
      if (!_controller.isClosed) {
        await _controller.close();
      }
    } catch (error, stackTrace) {
      debugLog('Failed to close signaling client', error, stackTrace);
    } finally {
      _channel = null;
    }
  }

  void _scheduleReconnect() {
    if (_closedManually) return;
    if (_reconnectTimer != null && _reconnectTimer!.isActive) return;
    final attempt = _reconnectAttempts + 1;
    _reconnectAttempts = attempt;
    final seconds = attempt > 6 ? 12 : attempt * 2;
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      unawaited(_connectInternal());
    });
  }

  void _startKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_channel == null || _closedManually) return;
      send(CsnSignalMessage('ping'));
    });
  }

  void _stopKeepAlive() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
  }

  void _emit(CsnSignalMessage message) {
    if (_controller.isClosed) return;
    _controller.add(message);
  }

  void _emitError(Object error, StackTrace stackTrace) {
    if (_controller.isClosed) return;
    _controller.addError(error, stackTrace);
  }

  Uri _buildWsUri() {
    final raw = wsUrl.trim();
    final normalized = raw.startsWith('http://')
        ? raw.replaceFirst('http://', 'ws://')
        : raw.startsWith('https://')
            ? raw.replaceFirst('https://', 'wss://')
            : raw;
    final baseUri = Uri.parse(normalized);
    if (baseUri.scheme != 'ws' && baseUri.scheme != 'wss') {
      throw ArgumentError('wsUrl must start with ws:// or wss://');
    }
    final query = Map<String, String>.from(baseUri.queryParameters);
    if (jwt != null && jwt!.isNotEmpty) {
      query['token'] = jwt!;
    }
    return baseUri.replace(
      queryParameters: query.isEmpty ? null : query,
      fragment: '',
    );
  }
}
