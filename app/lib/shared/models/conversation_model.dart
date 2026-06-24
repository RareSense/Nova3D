class ConversationModel {
  final String id;
  final String title;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? metadata;

  const ConversationModel({
    required this.id,
    required this.title,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.metadata,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) =>
      ConversationModel(
        id: json['id'] as String,
        title: (json['title'] as String?) ?? 'New Conversation',
        userId: (json['user_id'] as String?) ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(
          (json['updated_at'] as String?) ?? json['created_at'] as String,
        ),
        metadata: _asStringMap(json['conversation_metadata']),
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'user_id': userId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    if (metadata != null) 'conversation_metadata': metadata,
  };

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}
