import 'package:flutter_test/flutter_test.dart';
import 'package:familynest/models/dm_conversation.dart';

void main() {
  group('DMConversation', () {
    test('should create a DMConversation instance from JSON', () {
      // Sample JSON data from API
      final json = {
        'id': 123,
        'user1_id': 1,
        'user2_id': 2,
        'family_context_id': 10,
        'created_at': '2023-01-01T12:00:00Z',
        'updated_at': '2023-01-02T12:00:00Z',
        'other_user_name': 'johndoe',
        'other_user_photo': 'https://example.com/photo.jpg',
        'other_user_first_name': 'John',
        'other_user_last_name': 'Doe',
        'last_message_content': 'Hello there!',
        'last_message_time': '2023-01-02T12:00:00Z',
        'last_message_sender_id': 2,
        'has_unread_messages': true,
        'unread_count': 3,
      };

      // Create model from JSON
      final conversation = DMConversation.fromJson(json);

      // Verify properties
      expect(conversation.id, 123);
      expect(conversation.user1Id, 1);
      expect(conversation.user2Id, 2);
      expect(conversation.familyContextId, 10);
      expect(conversation.createdAt, DateTime.parse('2023-01-01T12:00:00Z'));
      expect(conversation.updatedAt, DateTime.parse('2023-01-02T12:00:00Z'));
      expect(conversation.otherUserName, 'johndoe');
      expect(conversation.otherUserPhoto, 'https://example.com/photo.jpg');
      expect(conversation.otherUserFirstName, 'John');
      expect(conversation.otherUserLastName, 'Doe');
      expect(conversation.lastMessageContent, 'Hello there!');
      expect(
        conversation.lastMessageTime,
        DateTime.parse('2023-01-02T12:00:00Z'),
      );
      expect(conversation.lastMessageSenderId, 2);
      expect(conversation.hasUnreadMessages, true);
      expect(conversation.unreadCount, 3);
    });

    test('should convert DMConversation to JSON', () {
      // Create a conversation instance
      final conversation = DMConversation(
        id: 123,
        user1Id: 1,
        user2Id: 2,
        familyContextId: 10,
        createdAt: DateTime.parse('2023-01-01T12:00:00Z'),
        updatedAt: DateTime.parse('2023-01-02T12:00:00Z'),
        otherUserName: 'johndoe',
        otherUserPhoto: 'https://example.com/photo.jpg',
        otherUserFirstName: 'John',
        otherUserLastName: 'Doe',
        lastMessageContent: 'Hello there!',
        lastMessageTime: DateTime.parse('2023-01-02T12:00:00Z'),
        lastMessageSenderId: 2,
        hasUnreadMessages: true,
        unreadCount: 3,
      );

      // Convert to JSON
      final json = conversation.toJson();

      // Verify JSON properties
      expect(json['id'], 123);
      expect(json['user1_id'], 1);
      expect(json['user2_id'], 2);
      expect(json['family_context_id'], 10);
      expect(json['created_at'], '2023-01-01T12:00:00.000Z');
      expect(json['updated_at'], '2023-01-02T12:00:00.000Z');
      expect(json['other_user_name'], 'johndoe');
      expect(json['other_user_photo'], 'https://example.com/photo.jpg');
      expect(json['other_user_first_name'], 'John');
      expect(json['other_user_last_name'], 'Doe');
      expect(json['last_message_content'], 'Hello there!');
      expect(json['last_message_time'], '2023-01-02T12:00:00.000Z');
      expect(json['last_message_sender_id'], 2);
      expect(json['has_unread_messages'], true);
      expect(json['unread_count'], 3);
    });

    test('should get other user display name', () {
      // With first and last name
      final conversation1 = DMConversation(
        id: 1,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUserFirstName: 'John',
        otherUserLastName: 'Doe',
      );
      expect(conversation1.getOtherUserDisplayName(), 'John Doe');

      // With only username
      final conversation2 = DMConversation(
        id: 2,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUserName: 'johndoe',
      );
      expect(conversation2.getOtherUserDisplayName(), 'johndoe');

      // With no name info
      final conversation3 = DMConversation(
        id: 3,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(conversation3.getOtherUserDisplayName(), 'Unknown User');
    });

    test('should get other user initials', () {
      // With first and last name
      final conversation1 = DMConversation(
        id: 1,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUserFirstName: 'John',
        otherUserLastName: 'Doe',
      );
      expect(conversation1.getOtherUserInitials(), 'JD');

      // With only username (single word)
      final conversation2 = DMConversation(
        id: 2,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUserName: 'johndoe',
      );
      expect(conversation2.getOtherUserInitials(), 'J');

      // With only username (two words)
      final conversation3 = DMConversation(
        id: 3,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        otherUserName: 'john doe',
      );
      expect(conversation3.getOtherUserInitials(), 'JD');

      // With no name info
      final conversation4 = DMConversation(
        id: 4,
        user1Id: 1,
        user2Id: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(conversation4.getOtherUserInitials(), '?');
    });

    test('should get other user ID', () {
      final conversation = DMConversation(
        id: 1,
        user1Id: 10,
        user2Id: 20,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(conversation.getOtherUserId(10), 20);
      expect(conversation.getOtherUserId(20), 10);
    });
  });
}
