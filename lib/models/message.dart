import 'package:flutter/material.dart';

/*                     messageMap.put("id", message.get("id"));
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
                messageMap.put("viewCount", message.get("view_count"));
                messageMap.put("likeCount", message.get("like_count"));
                messageMap.put("loveCount", message.get("love_count"));
                messageMap.put("commentCount", message.get("comment_count"));
                
                // Add thumbnail URL without excessive logging
                messageMap.put("thumbnailUrl", message.get("thumbnail_url")); 

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
  final String? thumbnailUrl;
  final String? senderPhoto;
  final int? likeCount;
  final int? loveCount;
  final int? commentCount;
  final int? parentMessageId;
  final String? userName;
  final bool isLiked;
  final bool isLoved;
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
    this.thumbnailUrl,
    this.senderPhoto,
    this.likeCount,
    this.loveCount,
    this.commentCount,
    this.parentMessageId,
    this.userName,
    this.isLiked = false,
    this.isLoved = false,
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
      mediaUrl: json['mediaUrl'] as String? ?? json['media_url'] as String?,
      mediaType: json['mediaType'] as String? ?? json['media_type'] as String?,
      createdAt:
          json['timestamp'] != null
              ? (json['timestamp'] is int
                  ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'])
                  : DateTime.tryParse(json['timestamp'].toString()))
              : (json['createdAt'] != null
                  ? DateTime.tryParse(json['createdAt'].toString())
                  : null),
      senderId: json['senderId']?.toString() ?? json['sender_id']?.toString(),
      senderUserName:
          json['senderUserName']
              as String? // <-- add this line!
              ??
          json['senderUsername'] as String? ??
          json['sender_username'] as String?,
      userName:
          json['senderUsername'] as String? ??
          json['sender_username'] as String?,
      thumbnailUrl:
          json['thumbnailUrl'] as String? ?? json['thumbnail_url'] as String?,
      senderPhoto:
          json['senderPhoto'] as String? ?? json['sender_photo'] as String?,
      likeCount: json['likeCount'] as int? ?? json['like_count'] as int?,
      loveCount: json['loveCount'] as int? ?? json['love_count'] as int?,
      commentCount:
          json['commentCount'] as int? ?? json['comment_count'] as int?,
      parentMessageId:
          json['parentMessageId'] as int? ?? json['parent_message_id'] as int?,
      isLiked: json['isLiked'] as bool? ?? json['is_liked'] as bool? ?? false,
      isLoved: json['isLoved'] as bool? ?? json['is_loved'] as bool? ?? false,
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
      'thumbnailUrl': thumbnailUrl,
      'senderPhoto': senderPhoto,
      'likeCount': likeCount,
      'loveCount': loveCount,
      'commentCount': commentCount,
      'parentMessageId': parentMessageId,
      'userName': userName,
      'isLiked': isLiked,
      'isLoved': isLoved,
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
    int? likeCount,
    int? loveCount,
    int? commentCount,
    int? parentMessageId,
    String? userName,
    bool? isLiked,
    bool? isLoved,
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
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      senderPhoto: senderPhoto ?? this.senderPhoto,
      likeCount: likeCount ?? this.likeCount,
      loveCount: loveCount ?? this.loveCount,
      commentCount: commentCount ?? this.commentCount,
      parentMessageId: parentMessageId ?? this.parentMessageId,
      userName: userName ?? this.userName,
      isLiked: isLiked ?? this.isLiked,
      isLoved: isLoved ?? this.isLoved,
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
}
