import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:nova3d_frontend/core/constants.dart';
import 'package:nova3d_frontend/core/network/transient_retry.dart';
import 'package:nova3d_frontend/features/auth/data/auth_service.dart';
import 'package:nova3d_frontend/features/chat/data/chat_snapshot_codec.dart';
import 'package:nova3d_frontend/shared/models/conversation_model.dart';
import 'package:nova3d_frontend/shared/models/message_model.dart';

class RemoteMessageReceipt {
  const RemoteMessageReceipt({required this.id, required this.inserted});

  final String id;
  final bool inserted;
}

class ChatService {
  final AuthService _auth;
  late final Dio _dio;

  ChatService(this._auth) {
    _dio = Dio(
      BaseOptions(
        baseUrl: kApiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        // Conversation/history requests must never leave the UI waiting
        // indefinitely on a server that accepted a connection but stopped
        // responding. Generation streaming uses a separate Dio client below.
        receiveTimeout: const Duration(seconds: 15),
      ),
    );
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await _auth.getToken();
    if (token == null) throw AuthException('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  // ── Conversations ─────────────────────────────────────────────────────────

  Future<List<ConversationModel>> getConversations({
    int limit = 50,
    int offset = 0,
  }) async {
    final headers = await _authHeaders();
    final options = Options(headers: headers);
    final resp = await retryIdempotentDio(
      () => _dio.get(
        '/conversations',
        queryParameters: {
          'kind': 'generation',
          'limit': limit,
          'offset': offset,
        },
        options: options,
      ),
    );
    final list = _items(resp.data);
    return list
        .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ConversationModel> createConversation(
    String firstMessage, {
    Map<String, dynamic>? metadata,
  }) async {
    final headers = await _authHeaders();
    final resp = await _dio.post(
      '/conversations',
      data: {
        'source': 'flutter',
        'kind': 'generation',
        'title': firstMessage.length > 50
            ? '${firstMessage.substring(0, 50)}...'
            : firstMessage,
        ...?(metadata == null ? null : {'conversation_metadata': metadata}),
      },
      options: Options(headers: headers),
    );
    return ConversationModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ConversationModel> updateConversationSnapshot(
    String id, {
    required String title,
    required List<MessageModel> messages,
  }) async {
    final headers = await _authHeaders();
    final resp = await _dio.patch(
      '/conversations/$id',
      data: {
        'title': title,
        'kind': 'generation',
        'conversation_metadata': buildChatSnapshotMetadata(messages),
      },
      options: Options(headers: headers),
    );
    return ConversationModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<RemoteMessageReceipt> appendMessage(
    String conversationId,
    MessageModel message,
  ) async {
    final headers = await _authHeaders();
    final resp = await _dio.post(
      '/conversations/$conversationId/messages',
      data: {
        'client_message_id': message.id,
        'role': message.role == MessageRole.user ? 'user' : 'assistant',
        'status': message.isStreaming ? 'pending' : 'completed',
        'content_text': message.text,
        'content_json': message.toContentJson(),
        'sent_at': message.createdAt.toUtc().toIso8601String(),
      },
      options: Options(headers: headers),
    );
    final data = resp.data as Map<String, dynamic>;
    return RemoteMessageReceipt(
      id: data['id'] as String,
      inserted: resp.statusCode == 201,
    );
  }

  Future<void> linkWorkflowToMessage(
    String conversationId, {
    required String workflowId,
    required String remoteMessageId,
    required String operation,
  }) async {
    final headers = await _authHeaders();
    await _dio.post(
      '/conversations/$conversationId/workflow-links',
      data: {
        'workflow_id': workflowId,
        'message_id': remoteMessageId,
        'relation_type': 'message_result',
        'link_metadata': {
          'operation': operation,
          'client': 'flutter',
          'client_relation': 'asset_version',
        },
      },
      options: Options(headers: headers),
    );
  }

  Future<void> deleteConversation(String id) async {
    final headers = await _authHeaders();
    await _dio.delete('/conversations/$id', options: Options(headers: headers));
  }

  // ── Messages ──────────────────────────────────────────────────────────────

  Future<List<MessageModel>> getMessages(String conversationId) async {
    final headers = await _authHeaders();
    final resp = await _dio.get(
      '/conversations/$conversationId/messages',
      options: Options(headers: headers),
    );
    final list = _items(resp.data);
    return list
        .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<MessageModel>> getSnapshotMessages(String conversationId) async {
    final headers = await _authHeaders();
    final resp = await _dio.get(
      '/conversations/$conversationId',
      options: Options(headers: headers),
    );
    final conv = ConversationModel.fromJson(resp.data as Map<String, dynamic>);
    return parseChatSnapshotMessages(conv.metadata);
  }

  List<dynamic> _items(Object? data) {
    if (data is List) return data;
    if (data is Map && data['items'] is List) return data['items'] as List;
    return const [];
  }

  // ── Streaming send ────────────────────────────────────────────────────────
  // Yields partial MessageModel updates as the server streams JSON lines.
  Stream<MessageModel> sendMessage(String conversationId, String text) async* {
    final token = await _auth.getToken();
    if (token == null) throw AuthException('Not authenticated');

    final client = Dio(BaseOptions(baseUrl: kApiBaseUrl));
    final placeholder = MessageModel(
      id: 'streaming',
      role: MessageRole.assistant,
      text: '',
      createdAt: DateTime.now(),
      isStreaming: true,
    );
    yield placeholder;

    final response = await client.post(
      '/conversations/$conversationId/chat',
      data: {'message': text},
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.stream,
      ),
    );

    final stream = response.data.stream as Stream<List<int>>;
    final buffer = StringBuffer();
    String accumulated = '';

    await for (final chunk in stream) {
      final decoded = utf8.decode(chunk);
      buffer.write(decoded);
      final lines = buffer.toString().split('\n');
      buffer.clear();
      if (!decoded.endsWith('\n')) {
        buffer.write(lines.removeLast());
      }
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final data = json.decode(trimmed) as Map<String, dynamic>;
          if (data['text'] != null) {
            accumulated += data['text'] as String;
            yield placeholder.copyWith(text: accumulated);
          }
          if (data['done'] == true) {
            final finalMsg = data['message'] != null
                ? MessageModel.fromJson(data['message'] as Map<String, dynamic>)
                : placeholder.copyWith(text: accumulated, isStreaming: false);
            yield finalMsg;
          }
        } catch (_) {
          // non-JSON chunk, skip
        }
      }
    }
  }
}
