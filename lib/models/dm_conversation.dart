import 'package:flutter/foundation.dart';

class DMConversation {
  final int id;
  final int user1Id; // Always the lower user_id
  final int user2Id; // Always the higher user_id
  final int? familyContextId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Additional fields that might come from API joins
  final String? otherUserName;
  final String? otherUserPhoto;
  final String? otherUserFirstName;
  final String? otherUserLastName;

  // Last message details (from API)
  final String? lastMessageContent;
  final DateTime? lastMessageTime;
  final int? lastMessageSenderId;
  final bool? hasUnreadMessages;
  final int? unreadCount;

  DMConversation({
    required this.id,
    required this.user1Id,
    required this.user2Id,
    this.familyContextId,
    required this.createdAt,
    required this.updatedAt,
    this.otherUserName,
    this.otherUserPhoto,
    this.otherUserFirstName,
    this.otherUserLastName,
    this.lastMessageContent,
    this.lastMessageTime,
    this.lastMessageSenderId,
    this.hasUnreadMessages,
    this.unreadCount,
  });

  // Factory constructor for creating a DMConversation from JSON
  factory DMConversation.fromJson(Map<String, dynamic> json) {
    // Helper function to safely parse integer values
    int parseIntSafe(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      if (value is num) return value.toInt();
      return 0;
    }

    return DMConversation(
      id: parseIntSafe(json['id']),
      user1Id: parseIntSafe(json['user1_id']),
      user2Id: parseIntSafe(json['user2_id']),
      familyContextId:
          json['family_context_id'] != null
              ? parseIntSafe(json['family_context_id'])
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
      otherUserName: json['other_user_name'] as String?,
      otherUserPhoto: json['other_user_photo'] as String?,
      otherUserFirstName: json['other_user_first_name'] as String?,
      otherUserLastName: json['other_user_last_name'] as String?,
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageTime:
          json['last_message_time'] != null
              ? (json['last_message_time'] is String
                  ? DateTime.parse(json['last_message_time'])
                  : DateTime.fromMillisecondsSinceEpoch(
                    json['last_message_time'] as int,
                  ))
              : null,
      lastMessageSenderId:
          json['last_message_sender_id'] != null
              ? parseIntSafe(json['last_message_sender_id'])
              : null,
      hasUnreadMessages: json['has_unread_messages'] as bool?,
      unreadCount:
          json['unread_count'] != null
              ? parseIntSafe(json['unread_count'])
              : null,
    );
  }

  // Convert DMConversation to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user1_id': user1Id,
      'user2_id': user2Id,
      'family_context_id': familyContextId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'other_user_name': otherUserName,
      'other_user_photo': otherUserPhoto,
      'other_user_first_name': otherUserFirstName,
      'other_user_last_name': otherUserLastName,
      'last_message_content': lastMessageContent,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'last_message_sender_id': lastMessageSenderId,
      'has_unread_messages': hasUnreadMessages,
      'unread_count': unreadCount,
    };
  }

  // Convert to the format expected by MessagesHomeScreen
  Map<String, dynamic> toMessageScreenFormat(int currentUserId) {
    // Determine the other user ID based on current user
    final otherUserId = currentUserId == user1Id ? user2Id : user1Id;

    return {
      'conversation_id': id,
      'other_user_id': otherUserId,
      'other_username': otherUserName,
      'other_first_name': otherUserFirstName,
      'other_last_name': otherUserLastName,
      'other_user_photo': otherUserPhoto,
      'last_message_content': lastMessageContent,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'last_message_sender_id': lastMessageSenderId,
      'unread_count': unreadCount ?? 0,
      'has_unread_messages': hasUnreadMessages ?? false,
    };
  }

  // Create a copy of the conversation with modified fields
  DMConversation copyWith({
    int? id,
    int? user1Id,
    int? user2Id,
    int? familyContextId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? otherUserName,
    String? otherUserPhoto,
    String? otherUserFirstName,
    String? otherUserLastName,
    String? lastMessageContent,
    DateTime? lastMessageTime,
    int? lastMessageSenderId,
    bool? hasUnreadMessages,
    int? unreadCount,
  }) {
    return DMConversation(
      id: id ?? this.id,
      user1Id: user1Id ?? this.user1Id,
      user2Id: user2Id ?? this.user2Id,
      familyContextId: familyContextId ?? this.familyContextId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      otherUserName: otherUserName ?? this.otherUserName,
      otherUserPhoto: otherUserPhoto ?? this.otherUserPhoto,
      otherUserFirstName: otherUserFirstName ?? this.otherUserFirstName,
      otherUserLastName: otherUserLastName ?? this.otherUserLastName,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      hasUnreadMessages: hasUnreadMessages ?? this.hasUnreadMessages,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  // Helper method to get other user display name
  String getOtherUserDisplayName() {
    if (otherUserFirstName != null && otherUserLastName != null) {
      return '$otherUserFirstName $otherUserLastName';
    }
    return otherUserName ?? 'Unknown User';
  }

  // Helper method to get initials from other user name
  String getOtherUserInitials() {
    if (otherUserFirstName != null && otherUserLastName != null) {
      return '${otherUserFirstName![0]}${otherUserLastName![0]}'.toUpperCase();
    }
    if (otherUserName != null && otherUserName!.isNotEmpty) {
      final words = otherUserName!.split(' ');
      if (words.length == 1) {
        return words[0][0].toUpperCase();
      }
      if (words.length > 1) {
        return '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
    }
    return '?';
  }

  // Helper to get the other user ID based on current user ID
  int getOtherUserId(int currentUserId) {
    return currentUserId == user1Id ? user2Id : user1Id;
  }

  // Static method to convert a list of DMConversation to the format expected by MessagesHomeScreen
  static List<Map<String, dynamic>> convertListToMessageScreenFormat(
    List<DMConversation> conversations,
    int currentUserId,
  ) {
    return conversations
        .map(
          (conversation) => conversation.toMessageScreenFormat(currentUserId),
        )
        .toList();
  }
}
