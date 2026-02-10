import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class CsnApiClient {
  CsnApiClient({required this.baseUrl, this.jwt, http.Client? client})
      : _client = client ?? http.Client();

  final String baseUrl;
  final String? jwt;
  final http.Client _client;

  Map<String, String> _headers({bool jsonBody = false}) {
    final headers = <String, String>{};
    if (jwt != null && jwt!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwt';
    }
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    return headers;
  }

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final uri = Uri.parse(baseUrl + path);
    return query == null ? uri : uri.replace(queryParameters: query.map((k, v) => MapEntry(k, '$v')));
  }

  Future<HealthResponse> health() async {
    final response = await _client.get(_uri('/health'));
    _ensureOk(response);
    return HealthResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RoomSettings> getRoom(String roomId) async {
    final response = await _client.get(_uri('/rooms/$roomId'));
    _ensureOk(response);
    return RoomSettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RoomSettings> createRoom(String roomId) async {
    final response = await _client.post(_uri('/rooms/$roomId'), headers: _headers());
    _ensureOk(response);
    return RoomSettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RoomSettings> updateRoom(String roomId, Map<String, dynamic> patch) async {
    final response = await _client.patch(
      _uri('/rooms/$roomId'),
      headers: _headers(jsonBody: true),
      body: jsonEncode(patch),
    );
    _ensureOk(response);
    return RoomSettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> deleteRoom(String roomId) async {
    final response = await _client.delete(_uri('/rooms/$roomId'), headers: _headers());
    _ensureOk(response);
  }

  Future<RoomPeerList> getPeers(String roomId) async {
    final response = await _client.get(_uri('/rooms/$roomId/peers'));
    _ensureOk(response);
    return RoomPeerList.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<RoomMember>> getActiveMembers(String roomId) async {
    final response = await _client.get(_uri('/rooms/$roomId/members/active'));
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['members'] as List<dynamic>;
    return items.map((item) => RoomMember.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<List<RoomMemberHistory>> getHistory(String roomId, {int limit = 50}) async {
    final response = await _client.get(_uri('/rooms/$roomId/members/history', {'limit': limit}));
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['history'] as List<dynamic>;
    return items
        .map((item) => RoomMemberHistory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> kickUser(String roomId, String userId, {String? reason}) async {
    final response = await _client.post(
      _uri('/rooms/$roomId/moderation/kick'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'userId': userId, 'reason': reason}),
    );
    _ensureOk(response);
  }

  Future<RoomSettings> lockRoom(String roomId) async {
    final response = await _client.post(_uri('/rooms/$roomId/moderation/lock'), headers: _headers());
    _ensureOk(response);
    return RoomSettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<RoomSettings> unlockRoom(String roomId) async {
    final response = await _client.post(_uri('/rooms/$roomId/moderation/unlock'), headers: _headers());
    _ensureOk(response);
    return RoomSettings.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<List<String>> getAllowedUsers(String roomId) async {
    final response = await _client.get(_uri('/rooms/$roomId/moderation/allowed-users'), headers: _headers());
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return (data['users'] as List<dynamic>).map((e) => e.toString()).toList();
  }

  Future<void> addAllowedUser(String roomId, String userId) async {
    final response = await _client.post(
      _uri('/rooms/$roomId/moderation/allowed-users'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'userId': userId}),
    );
    _ensureOk(response);
  }

  Future<void> removeAllowedUser(String roomId, String userId) async {
    final response = await _client.delete(
      _uri('/rooms/$roomId/moderation/allowed-users/$userId'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> createMediasoupRoom(String roomId) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'roomId': roomId}),
    );
    _ensureOk(response);
  }

  Future<Map<String, dynamic>> getRtpCapabilities(String roomId) async {
    final response = await _client.get(_uri('/mediasoup/rooms/$roomId/rtp-capabilities'));
    _ensureOk(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<TransportOptions> createTransport(String roomId) async {
    final response = await _client.post(_uri('/mediasoup/rooms/$roomId/transports'));
    _ensureOk(response);
    return TransportOptions.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> connectTransport(String roomId, String transportId, Map<String, dynamic> dtlsParameters) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/transports/$transportId/connect'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'dtlsParameters': dtlsParameters}),
    );
    _ensureOk(response);
  }

  Future<ProducerResponse> produce(
    String roomId,
    String transportId,
    String kind,
    Map<String, dynamic> rtpParameters,
  ) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/producers'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'transportId': transportId,
        'kind': kind,
        'rtpParameters': rtpParameters,
      }),
    );
    _ensureOk(response);
    return ProducerResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<ConsumerResponse> consume(
    String roomId,
    String transportId,
    String producerId,
    Map<String, dynamic> rtpCapabilities,
  ) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/consumers'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({
        'transportId': transportId,
        'producerId': producerId,
        'rtpCapabilities': rtpCapabilities,
      }),
    );
    _ensureOk(response);
    return ConsumerResponse.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<void> pauseProducer(String roomId, String producerId) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/producers/$producerId/pause'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> resumeProducer(String roomId, String producerId) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/producers/$producerId/resume'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> pauseConsumer(String roomId, String consumerId) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/consumers/$consumerId/pause'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> resumeConsumer(String roomId, String consumerId) async {
    final response = await _client.post(
      _uri('/mediasoup/rooms/$roomId/consumers/$consumerId/resume'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<Map<String, dynamic>> producerStats(String roomId, String producerId) async {
    final response = await _client.get(_uri('/mediasoup/rooms/$roomId/producers/$producerId/stats'));
    _ensureOk(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> consumerStats(String roomId, String consumerId) async {
    final response = await _client.get(_uri('/mediasoup/rooms/$roomId/consumers/$consumerId/stats'));
    _ensureOk(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<CallRequestCreateResponse> createCallRequest({String? userId}) async {
    final response = await _client.post(
      _uri('/requests'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'userId': userId}),
    );
    _ensureOk(response);
    return CallRequestCreateResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<CallRequestStatusResponse> getCallRequestStatus(String requestId) async {
    final response = await _client.get(
      _uri('/requests/$requestId'),
      headers: _headers(),
    );
    _ensureOk(response);
    return CallRequestStatusResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AdminQueueResponse> getAdminQueue() async {
    final response = await _client.get(
      _uri('/admin/requests'),
      headers: _headers(),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AdminQueueResponse.fromJson(data);
  }

  Future<AdminTokenResponse> createAdminToken({String? userId}) async {
    final response = await _client.post(
      _uri('/admin/token'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'userId': userId}),
    );
    _ensureOk(response);
    return AdminTokenResponse.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<String> acceptRequest(String requestId) async {
    final response = await _client.post(
      _uri('/admin/requests/$requestId/accept'),
      headers: _headers(),
    );
    _ensureOk(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['roomId'] as String;
  }

  Future<void> declineRequest(String requestId) async {
    final response = await _client.post(
      _uri('/admin/requests/$requestId/decline'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> endRequest(String requestId) async {
    final response = await _client.post(
      _uri('/admin/requests/$requestId/end'),
      headers: _headers(),
    );
    _ensureOk(response);
  }

  Future<void> registerAdminPushToken(String token) async {
    final response = await _client.post(
      _uri('/admin/push-token'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'token': token}),
    );
    _ensureOk(response);
  }

  Future<void> unregisterAdminPushToken(String token) async {
    final response = await _client.delete(
      _uri('/admin/push-token'),
      headers: _headers(jsonBody: true),
      body: jsonEncode({'token': token}),
    );
    _ensureOk(response);
  }

  void close() => _client.close();

  void _ensureOk(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API error: ${response.statusCode} ${response.body}');
    }
  }
}
