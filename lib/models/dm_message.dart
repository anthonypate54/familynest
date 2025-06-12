import 'package:flutter/foundation.dart';

class DMMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String content;

  // Media fields
  final String? mediaUrl;
  final String? mediaType;
  final String? mediaThumbnail;
  final String? mediaFilename;
  final int? mediaSize;
  final int? mediaDuration;

  // DM-specific fields
  final bool isRead;
  final DateTime? deliveredAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Additional fields that might come from API joins
  final String? senderUsername;
  final String? senderPhoto;
  final String? senderFirstName;
  final String? senderLastName;

  DMMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.mediaUrl,
    this.mediaType,
    this.mediaThumbnail,
    this.mediaFilename,
    this.mediaSize,
    this.mediaDuration,
    this.isRead = false,
    this.deliveredAt,
    required this.createdAt,
    required this.updatedAt,
    this.senderUsername,
    this.senderPhoto,
    this.senderFirstName,
    this.senderLastName,
  });

  // Factory constructor for creating a DMMessage from JSON
  factory DMMessage.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse integer values
    int parseIntSafe(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is num) return value.toInt();
      return 0;
    }

    return DMMessage(
      id: parseIntSafe(json['id']),
      conversationId: parseIntSafe(json['conversation_id']),
      senderId: parseIntSafe(json['sender_id']),
      content: json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      mediaType: json['media_type'] as String?,
      mediaThumbnail: json['media_thumbnail'] as String?,
      mediaFilename: json['media_filename'] as String?,
      mediaSize: json['media_size'] as int?,
      mediaDuration: json['media_duration'] as int?,
      isRead: json['is_read'] as bool? ?? false,
      deliveredAt:
          json['delivered_at'] != null
              ? DateTime.parse(json['delivered_at'].toString())
              : null,
      createdAt:
          json['created_at'] != null
              ? (json['created_at'] is String
                  ? DateTime.parse(json['created_at'])
                  : DateTime.fromMillisecondsSinceEpoch(
                    json['created_at'] as int,
                  ))
              : DateTime.now(),
      updatedAt:
          json['updated_at'] != null
              ? (json['updated_at'] is String
                  ? DateTime.parse(json['updated_at'])
                  : DateTime.fromMillisecondsSinceEpoch(
                    json['updated_at'] as int,
                  ))
              : DateTime.now(),
      senderUsername: json['sender_username'] as String?,
      senderPhoto: json['sender_photo'] as String?,
      senderFirstName: json['sender_first_name'] as String?,
      senderLastName: json['sender_last_name'] as String?,
    );
  }

  // Convert DMMessage to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'mediaThumbnail': mediaThumbnail,
      'mediaFilename': mediaFilename,
      'mediaSize': mediaSize,
      'mediaDuration': mediaDuration,
      'isRead': isRead,
      'deliveredAt': deliveredAt?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'senderUsername': senderUsername,
      'senderPhoto': senderPhoto,
      'senderFirstName': senderFirstName,
      'senderLastName': senderLastName,
    };
  }

  // Create a copy of the message with modified fields
  DMMessage copyWith({
    int? id,
    int? conversationId,
    int? senderId,
    String? content,
    String? mediaUrl,
    String? mediaType,
    String? mediaThumbnail,
    String? mediaFilename,
    int? mediaSize,
    int? mediaDuration,
    bool? isRead,
    DateTime? deliveredAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? senderUsername,
    String? senderPhoto,
    String? senderFirstName,
    String? senderLastName,
  }) {
    return DMMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      mediaThumbnail: mediaThumbnail ?? this.mediaThumbnail,
      mediaFilename: mediaFilename ?? this.mediaFilename,
      mediaSize: mediaSize ?? this.mediaSize,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      isRead: isRead ?? this.isRead,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      senderUsername: senderUsername ?? this.senderUsername,
      senderPhoto: senderPhoto ?? this.senderPhoto,
      senderFirstName: senderFirstName ?? this.senderFirstName,
      senderLastName: senderLastName ?? this.senderLastName,
    );
  }

  // Helper method to get sender display name
  String getSenderDisplayName() {
    if (senderFirstName != null && senderLastName != null) {
      return '$senderFirstName $senderLastName';
    }
    return senderUsername ?? 'Unknown User';
  }

  // Helper method to get initials from sender name
  String getInitials() {
    if (senderFirstName != null && senderLastName != null) {
      return '${senderFirstName![0]}${senderLastName![0]}'.toUpperCase();
    }
    if (senderUsername != null && senderUsername!.isNotEmpty) {
      final words = senderUsername!.split(' ');
      if (words.length == 1) {
        return words[0][0].toUpperCase();
      }
      return '${words[0][0]}${words[1][0]}'.toUpperCase();
    }
    return '?';
  }
}
