import 'package:flutter/foundation.dart';

class DMConversation {
  final int id;
  final int? user1Id; // Nullable for group chats (for 1:1 chats)
  final int? user2Id; // Nullable for group chats (for 1:1 chats)
  final int? familyContextId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Group chat fields
  final bool isGroup;
  final String? name; // Group name
  final int? participantCount;
  final int? createdBy;
  final List<Map<String, dynamic>>? participants;

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
    this.user1Id, // Made optional
    this.user2Id, // Made optional
    this.familyContextId,
    required this.createdAt,
    required this.updatedAt,
    this.isGroup = false,
    this.name,
    this.participantCount,
    this.createdBy,
    this.participants,
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
      user1Id: json['user1_id'] != null ? parseIntSafe(json['user1_id']) : null,
      user2Id: json['user2_id'] != null ? parseIntSafe(json['user2_id']) : null,
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
      isGroup: json['is_group'] as bool? ?? false,
      name: json['name'] as String?,
      participantCount:
          json['participant_count'] != null
              ? parseIntSafe(json['participant_count'])
              : null,
      createdBy:
          json['created_by'] != null ? parseIntSafe(json['created_by']) : null,
      participants:
          json['participants'] != null
              ? List<Map<String, dynamic>>.from(
                (json['participants'] as List<dynamic>).map(
                  (p) => Map<String, dynamic>.from(p),
                ),
              )
              : null,
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
      'is_group': isGroup,
      'name': name,
      'participant_count': participantCount,
      'created_by': createdBy,
      'participants': participants,
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
    bool? isGroup,
    String? name,
    int? participantCount,
    int? createdBy,
    List<Map<String, dynamic>>? participants,
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
      isGroup: isGroup ?? this.isGroup,
      name: name ?? this.name,
      participantCount: participantCount ?? this.participantCount,
      createdBy: createdBy ?? this.createdBy,
      participants: participants ?? this.participants,
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
      if (otherUserFirstName!.isNotEmpty && otherUserLastName!.isNotEmpty) {
        return '${otherUserFirstName![0]}${otherUserLastName![0]}'
            .toUpperCase();
      }
    }
    if (otherUserName != null && otherUserName!.isNotEmpty) {
      final words =
          otherUserName!.split(' ').where((word) => word.isNotEmpty).toList();
      if (words.length == 1 && words[0].isNotEmpty) {
        return words[0][0].toUpperCase();
      }
      if (words.length > 1 && words[0].isNotEmpty && words[1].isNotEmpty) {
        return '${words[0][0]}${words[1][0]}'.toUpperCase();
      }
      if (words.isNotEmpty && words[0].isNotEmpty) {
        return words[0][0].toUpperCase();
      }
    }
    return '?';
  }

  // Helper to get the other user ID based on current user ID
  int getOtherUserId(int currentUserId) {
    // For group chats, return 0 as there's no single "other user"
    if (isGroup || user1Id == null || user2Id == null) {
      return 0;
    }
    return currentUserId == user1Id ? user2Id! : user1Id!;
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
