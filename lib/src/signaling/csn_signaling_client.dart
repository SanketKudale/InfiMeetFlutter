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
  final _controller = StreamController<CsnSignalMessage>.broadcast();

  Stream<CsnSignalMessage> get messages => _controller.stream;

  Future<void> connect() async {
    if (_channel != null) return;
    final uri = _buildWsUri();
    try {
      debugLog(
        'Connecting signaling',
        {
          'url': uri.toString(),
        },
      );
      _channel = IOWebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (data) {
          final jsonData = jsonDecode(data as String) as Map<String, dynamic>;
          _controller.add(CsnSignalMessage.fromJson(jsonData));
        },
        onError: (Object error, StackTrace stackTrace) {
          debugLog('Signaling socket error', error, stackTrace);
          _controller.addError(error, stackTrace);
        },
        onDone: () {
          debugLog('Signaling socket closed');
          _channel = null;
        },
      );
    } catch (error, stackTrace) {
      debugLog('Failed to connect signaling: $uri', error, stackTrace);
      _channel = null;
      rethrow;
    }
  }

  void send(CsnSignalMessage message) {
    if (_channel == null) {
      debugLog('Attempted to send signaling message before connect: ${message.type}');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
    } catch (error, stackTrace) {
      debugLog('Failed to send signaling message: ${message.type}', error, stackTrace);
      _controller.addError(error, stackTrace);
    }
  }

  void joinRoom(String roomId) => send(CsnSignalMessage('join', {'roomId': roomId}));
  void leaveRoom() => send(CsnSignalMessage('leave'));
  void getRtpCapabilities() => send(CsnSignalMessage('get-rtp-capabilities'));
  void createTransport() => send(CsnSignalMessage('create-transport'));
  void connectTransport(String transportId, Map<String, dynamic> dtlsParameters) =>
      send(CsnSignalMessage('connect-transport', {
        'transportId': transportId,
        'dtlsParameters': dtlsParameters,
      }));

  void produce(String transportId, String kind, Map<String, dynamic> rtpParameters) =>
      send(CsnSignalMessage('produce', {
        'transportId': transportId,
        'kind': kind,
        'rtpParameters': rtpParameters,
      }));

  void consume(String transportId, String producerId, Map<String, dynamic> rtpCapabilities) =>
      send(CsnSignalMessage('consume', {
        'transportId': transportId,
        'producerId': producerId,
        'rtpCapabilities': rtpCapabilities,
      }));

  void closeProducer(String producerId) => send(CsnSignalMessage('close-producer', {
        'producerId': producerId,
      }));

  void pauseProducer(String producerId) => send(CsnSignalMessage('pause-producer', {
        'producerId': producerId,
      }));

  void resumeProducer(String producerId) => send(CsnSignalMessage('resume-producer', {
        'producerId': producerId,
      }));

  void pauseConsumer(String consumerId) => send(CsnSignalMessage('pause-consumer', {
        'consumerId': consumerId,
      }));

  void resumeConsumer(String consumerId) => send(CsnSignalMessage('resume-consumer', {
        'consumerId': consumerId,
      }));

  void getMediaStats() => send(CsnSignalMessage('get-media-stats'));

  Future<void> close() async {
    try {
      await _controller.close();
      await _channel?.sink.close();
    } catch (error, stackTrace) {
      debugLog('Failed to close signaling client', error, stackTrace);
    } finally {
      _channel = null;
    }
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
