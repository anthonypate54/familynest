import 'package:flutter/material.dart';

/*       messageMap.put("id", message.get("id"));
                messageMap.put("content", message.get("content"));
                messageMap.put("senderUsername", message.get("sender_username"));
                messageMap.put("senderId", message.get("sender_id"));
                messageMap.put("senderPhoto", message.get("sender_photo"));
                messageMap.put("senderFirstName", message.get("sender_first_name"));
                messageMap.put("senderLastName", message.get("sender_last_name"));
                messageMap.put("familyId", message.get("family_id"));
                messageMap.put("familyName", message.get("family_name"));
                messageMap.put("timestamp", message.get("timestamp").toString());
                messageMap.put("mediaType", message.get("media_type"));
                messageMap.put("mediaUrl", message.get("media_url"));
       */
class Message {
  final String id;
  final String content;
  final List<Message> replies;
  final int depth;
  final String? mediaUrl;
  final String? mediaType;
  final DateTime? createdAt;
  final String? senderId;
  final String? senderUserName;
  final Map<String, dynamic>? metrics;
  final String? thumbnailUrl;
  final String? senderPhoto;

  Message({
    required this.id,
    required this.content,
    this.replies = const [],
    this.depth = 0,
    this.mediaUrl,
    this.mediaType,
    this.createdAt,
    this.senderId,
    this.senderUserName,
    this.metrics,
    this.thumbnailUrl,
    this.senderPhoto,
  });

  // Factory constructor for creating a Message from JSON
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'].toString(),
      content: json['content'] as String,
      replies:
          (json['replies'] as List<dynamic>?)
              ?.map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      depth: json['depth'] as int? ?? 0,
      mediaUrl: json['mediaUrl'] as String?,
      mediaType: json['mediaType'] as String?,
      createdAt:
          json['timestamp'] != null
              ? (json['timestamp'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'])
                  : DateTime.tryParse(json['timestamp'].toString()))
              : (json['createdAt'] != null
                  ? DateTime.tryParse(json['createdAt'].toString())
                  : null),
      senderId: json['senderId']?.toString(),
      senderUserName: json['senderUsername'] as String?,
      metrics: json['metrics'] as Map<String, dynamic>?,
      thumbnailUrl:
          json['thumbnailUrl'] as String? ?? json['thumbnail_url'] as String?,
      senderPhoto: json['senderPhoto'] as String?,
    );
  }

  // Convert Message to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'replies': replies.map((e) => e.toJson()).toList(),
      'depth': depth,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'createdAt': createdAt?.toIso8601String(),
      'senderId': senderId,
      'senderUserName': senderUserName,
      'metrics': metrics,
      'thumbnailUrl': thumbnailUrl,
      'senderPhoto': senderPhoto,
    };
  }

  // Create a copy of the message with modified fields
  Message copyWith({
    String? id,
    String? content,
    List<Message>? replies,
    int? depth,
    String? mediaUrl,
    String? mediaType,
    DateTime? createdAt,
    String? senderId,
    String? senderUserName,
    Map<String, dynamic>? metrics,
    String? thumbnailUrl,
    String? senderPhoto,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      replies: replies ?? this.replies,
      depth: depth ?? this.depth,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      createdAt: createdAt ?? this.createdAt,
      senderId: senderId ?? this.senderId,
      senderUserName: senderUserName ?? this.senderUserName,
      metrics: metrics ?? this.metrics,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      senderPhoto: senderPhoto ?? this.senderPhoto,
    );
  }

  // Helper method to get initials from sender name or text
  String getInitials() {
    if (senderUserName != null && senderUserName!.isNotEmpty) {
      final words = senderUserName!.split(' ');
      if (words.length == 1) {
        return words[0][0].toUpperCase();
      }
      return words[0][0].toUpperCase() + words[1][0].toUpperCase();
    }

    if (content.isNotEmpty) {
      final words = content.split(' ');
      if (words.length == 1) {
        return words[0][0].toUpperCase();
      }
      return words[0][0].toUpperCase() + words[1][0].toUpperCase();
    }

    return '?';
  }

  // Helper method to get default metrics if none exist
  Map<String, int> getDefaultMetrics() {
    return metrics as Map<String, int>? ??
        {'comments': 0, 'likes': 0, 'hearts': 0, 'views': 0};
  }

  // Getter for video thumbnail URL
  String? get effectiveThumbnailUrl {
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) return thumbnailUrl;
    if (metrics != null) {
      if (metrics!.containsKey('thumbnailUrl')) {
        return metrics!['thumbnailUrl'] as String?;
      } else if (metrics!.containsKey('thumbnail_url')) {
        return metrics!['thumbnail_url'] as String?;
      }
    }
    return null;
  }
}
