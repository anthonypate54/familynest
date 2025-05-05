// Message Preferences Test Data Generator
// This file provides mock data for testing the message preferences functionality in the app

import 'dart:math';

/// Generates mock data for testing the message preferences feature
class MessagePreferencesTestData {
  /// Generate mock family message preferences data
  static List<Map<String, dynamic>> getFamilyMessagePreferences() {
    return [
      {
        'familyId': 1,
        'familyName': 'Test Family 1',
        'receiveMessages': true,
        'role': 'ADMIN',
        'isActive': true,
        'lastUpdated': DateTime.now().toString(),
      },
      {
        'familyId': 2,
        'familyName': 'Test Family 2',
        'receiveMessages': false,
        'role': 'MEMBER',
        'isActive': true,
        'lastUpdated': DateTime.now().toString(),
      },
      {
        'familyId': 3,
        'familyName': 'Test Family 3',
        'receiveMessages': true,
        'role': 'MEMBER',
        'isActive': true,
        'lastUpdated': DateTime.now().toString(),
      },
    ];
  }

  /// Generate mock member message preferences data
  static List<Map<String, dynamic>> getMemberMessagePreferences() {
    // Create 10 mock family members with different preference settings
    List<Map<String, dynamic>> members = [];

    // Add 5 members for Family 1
    for (int i = 1; i <= 5; i++) {
      members.add({
        'userId': 1, // Current user
        'familyId': 1,
        'memberUserId': i + 10, // Members have IDs starting from 11
        'receiveMessages': i % 2 == 0, // Alternate true/false
        'lastUpdated': DateTime.now().toString(),
        'memberFirstName': 'Member',
        'memberLastName': '$i',
        'memberUsername': 'member$i',
        'memberOfFamilyName': 'Test Family 1',
        'isOwner': i == 1, // First member is owner
        'ownedFamilyName': i == 1 ? 'Owned Family' : null,
      });
    }

    // Add 3 members for Family 2
    for (int i = 1; i <= 3; i++) {
      members.add({
        'userId': 1, // Current user
        'familyId': 2,
        'memberUserId': i + 20, // Members have IDs starting from 21
        'receiveMessages': true, // All receive messages
        'lastUpdated': DateTime.now().toString(),
        'memberFirstName': 'Person',
        'memberLastName': '$i',
        'memberUsername': 'person$i',
        'memberOfFamilyName': 'Test Family 2',
        'isOwner': i == 2, // Second member is owner
        'ownedFamilyName': i == 2 ? 'Another Family' : null,
      });
    }

    // Add 2 members for Family 3
    for (int i = 1; i <= 2; i++) {
      members.add({
        'userId': 1, // Current user
        'familyId': 3,
        'memberUserId': i + 30, // Members have IDs starting from 31
        'receiveMessages': false, // None receive messages
        'lastUpdated': DateTime.now().toString(),
        'memberFirstName': 'User',
        'memberLastName': '$i',
        'memberUsername': 'user$i',
        'memberOfFamilyName': 'Test Family 3',
        'isOwner': false, // No owner
      });
    }

    return members;
  }

  /// Generate a random preference value (true/false)
  static bool randomPreference() {
    return Random().nextBool();
  }

  /// Create a mock response for updating a family message preference
  static Map<String, dynamic> updateFamilyMessagePreference(
    int familyId,
    bool receiveMessages,
  ) {
    return {
      'userId': 1,
      'familyId': familyId,
      'familyName': 'Test Family $familyId',
      'receiveMessages': receiveMessages,
      'lastUpdated': DateTime.now().toString(),
    };
  }

  /// Create a mock response for updating a member message preference
  static Map<String, dynamic> updateMemberMessagePreference(
    int familyId,
    int memberUserId,
    bool receiveMessages,
  ) {
    return {
      'userId': 1,
      'familyId': familyId,
      'memberOfFamilyName': 'Test Family $familyId',
      'memberUserId': memberUserId,
      'memberFirstName': 'Test',
      'memberLastName': 'Member',
      'memberUsername': 'testmember',
      'receiveMessages': receiveMessages,
      'lastUpdated': DateTime.now().toString(),
      'isOwner': false,
      'message': 'Member message preference updated successfully',
    };
  }
}
