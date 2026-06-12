import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatMessage {
  final String role;
  final String content;
  final List<Uint8List> imageBytes;
  final List<String> imageLabels;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.content,
    this.imageBytes = const [],
    this.imageLabels = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get hasImages => imageBytes.isNotEmpty;

  ChatMessage copyWith({
    String? role,
    String? content,
    List<Uint8List>? imageBytes,
    List<String>? imageLabels,
    DateTime? timestamp,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      imageBytes: imageBytes ?? this.imageBytes,
      imageLabels: imageLabels ?? this.imageLabels,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatConversation {
  final String id;
  final String title;
  final List<ChatMessage> messages;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatConversation({
    required this.id,
    required this.title,
    this.messages = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  int get messageCount => messages.length;
  String get lastMessagePreview {
    if (messages.isEmpty) return '';
    final last = messages.last;
    final text = last.content.replaceAll('\n', ' ');
    return text.length > 80 ? '${text.substring(0, 80)}...' : text;
  }

  ChatConversation copyWith({
    String? id,
    String? title,
    List<ChatMessage>? messages,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatConversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? this.messages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory ChatConversation.fromJson(Map<String, dynamic> json) {
    return ChatConversation(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Chat',
      messages: (json['messages'] as List? ?? [])
          .whereType<Map>()
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m)))
          .toList(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatConversationStore {
  static const _key = 'aiCoachChatConversations';

  const ChatConversationStore();

  Future<List<ChatConversation>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.trim().isEmpty) return [];
    final decoded = jsonDecode(raw) as Object?;
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((m) => ChatConversation.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  }

  Future<void> saveAll(List<ChatConversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(conversations.map((c) => c.toJson()).toList()),
    );
  }

  Future<ChatConversation> saveConversation(
    ChatConversation conversation,
  ) async {
    final all = await loadAll();
    final index = all.indexWhere((c) => c.id == conversation.id);
    final updated = conversation.copyWith(updatedAt: DateTime.now());
    if (index >= 0) {
      all[index] = updated;
    } else {
      all.insert(0, updated);
    }
    await saveAll(all);
    return updated;
  }

  Future<void> deleteConversation(String id) async {
    final all = await loadAll();
    all.removeWhere((c) => c.id == id);
    await saveAll(all);
  }

  Future<void> deleteAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

String generateConversationId() {
  final now = DateTime.now();
  return 'chat_${now.millisecondsSinceEpoch}_${now.microsecond}';
}
