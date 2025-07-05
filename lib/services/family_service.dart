import 'package:flutter/material.dart';
import '../models/family.dart';
import '../services/api_service.dart';
import 'package:provider/provider.dart';

class FamilyService {
  final ApiService _apiService;

  FamilyService(this._apiService);

  // Load all families for a user - single API call, no processing needed
  Future<List<Family>> loadUserFamilies(int userId) async {
    try {
      debugPrint(
        'FamilyService: Loading complete family data for user $userId',
      );

      // Get all data in one call - backend does all processing
      final completeData = await _apiService.getCompleteFamilyData();

      final familiesData = completeData['families'] as List<dynamic>? ?? [];

      // Simple conversion - no loops, no grouping, no preference mapping
      List<Family> families =
          familiesData.map((familyData) {
            final membersData = familyData['members'] as List<dynamic>? ?? [];

            // Members come pre-processed with preferences applied
            final familyMembers =
                membersData
                    .map((memberData) => FamilyMember.fromJson(memberData))
                    .toList();

            return Family(
              id: familyData['familyId'] as int,
              name: familyData['familyName'] as String? ?? 'Unknown Family',
              isOwned: familyData['isOwner'] as bool? ?? false,
              userRole: _parseRole(familyData['role'] as String?),
              members: familyMembers,
              createdAt: DateTime.now(), // TODO: Parse from API
              isMuted: familyData['isMuted'] as bool? ?? false,
              receiveMessages: familyData['receiveMessages'] as bool? ?? true,
              receiveInvitations: true, // TODO: Get from API
              receiveReactions: true, // TODO: Get from API
            );
          }).toList();

      debugPrint(
        'FamilyService: Loaded ${families.length} families with ${families.fold(0, (sum, f) => sum + f.members.length)} total members',
      );
      return families;
    } catch (e) {
      debugPrint('FamilyService: Error loading families: $e');
      return [];
    }
  }

  // Load family members - now just extracts from complete data (still needed for some use cases)
  Future<List<FamilyMember>> loadFamilyMembers(int userId, int familyId) async {
    try {
      debugPrint('FamilyService: Loading members for family $familyId');

      // Get complete data and extract the specific family
      final families = await loadUserFamilies(userId);
      final family = families.firstWhere(
        (f) => f.id == familyId,
        orElse: () => throw Exception('Family not found'),
      );

      debugPrint(
        'FamilyService: Loaded ${family.members.length} members for family $familyId',
      );
      return family.members;
    } catch (e) {
      debugPrint('FamilyService: Error loading family members: $e');
      return [];
    }
  }

  // Mute/unmute entire family
  Future<bool> updateFamilyMuteStatus(
    int userId,
    int familyId,
    bool mute,
  ) async {
    try {
      debugPrint(
        'FamilyService: ${mute ? 'Muting' : 'Unmuting'} family $familyId for user $userId',
      );

      await _apiService.updateMessagePreference(userId, familyId, !mute);

      debugPrint('FamilyService: Successfully updated family mute status');
      return true;
    } catch (e) {
      debugPrint('FamilyService: Error updating family mute status: $e');
      return false;
    }
  }

  // Mute/unmute specific family member
  Future<bool> updateMemberMuteStatus(
    int userId,
    int familyId,
    int memberUserId,
    bool mute,
  ) async {
    try {
      debugPrint(
        'FamilyService: ${mute ? 'Muting' : 'Unmuting'} member $memberUserId in family $familyId',
      );

      await _apiService.updateMemberMessagePreference(
        userId,
        familyId,
        memberUserId,
        !mute,
      );

      debugPrint('FamilyService: Successfully updated member mute status');
      return true;
    } catch (e) {
      debugPrint('FamilyService: Error updating member mute status: $e');
      return false;
    }
  }

  // Create a new family
  Future<Family?> createFamily(int userId, String familyName) async {
    try {
      debugPrint(
        'FamilyService: Creating family "$familyName" for user $userId',
      );

      final response = await _apiService.createFamily(userId, familyName);

      if (response['id'] != null) {
        // Create a Family object from the response
        final family = Family(
          id: response['id'],
          name: familyName,
          isOwned: true,
          userRole: FamilyRole.admin,
          members: [],
          createdAt: DateTime.now(),
        );

        debugPrint('FamilyService: Successfully created family');
        return family;
      }

      return null;
    } catch (e) {
      debugPrint('FamilyService: Error creating family: $e');
      return null;
    }
  }

  // Leave a family
  Future<bool> leaveFamily(int userId, int familyId) async {
    try {
      debugPrint('FamilyService: User $userId leaving family $familyId');

      await _apiService.leaveFamily(userId);

      debugPrint('FamilyService: Successfully left family');
      return true;
    } catch (e) {
      debugPrint('FamilyService: Error leaving family: $e');
      return false;
    }
  }

  // Update family name
  Future<bool> updateFamilyName(int familyId, String newName) async {
    try {
      debugPrint('FamilyService: Updating family $familyId name to "$newName"');

      await _apiService.updateFamilyDetails(familyId, newName);

      debugPrint('FamilyService: Successfully updated family name');
      return true;
    } catch (e) {
      debugPrint('FamilyService: Error updating family name: $e');
      return false;
    }
  }

  // Send family invitation
  Future<Map<String, dynamic>?> sendInvitation(
    int userId,
    String email,
    String familyName,
  ) async {
    try {
      debugPrint(
        'FamilyService: Sending invitation to $email from user $userId',
      );

      final response = await _apiService.inviteUser(userId, email);

      debugPrint('FamilyService: Successfully sent invitation');
      return response;
    } catch (e) {
      debugPrint('FamilyService: Error sending invitation: $e');
      rethrow;
    }
  }

  // Get family notification preferences
  Future<FamilyNotificationPreferences> getFamilyNotificationPreferences(
    int userId,
    int familyId,
  ) async {
    try {
      // Get the specific family which already has preferences applied
      final families = await loadUserFamilies(userId);
      final family = families.firstWhere(
        (f) => f.id == familyId,
        orElse: () => throw Exception('Family not found'),
      );

      // Extract muted member IDs from the pre-processed members
      List<int> mutedMemberIds =
          family.members
              .where((member) => member.isMuted)
              .map((member) => member.id)
              .toList();

      return FamilyNotificationPreferences(
        receiveMessages: family.receiveMessages,
        receiveInvitations: true, // TODO: Add to API
        receiveReactions: true, // TODO: Add to API
        receiveComments: true, // TODO: Add to API
        muteFamily: family.isMuted,
        mutedMemberIds: mutedMemberIds,
        emailNotifications: true, // TODO: Add to API
        pushNotifications: true, // TODO: Add to API
      );
    } catch (e) {
      debugPrint('FamilyService: Error getting notification preferences: $e');
      return FamilyNotificationPreferences();
    }
  }

  // Update family notification preferences
  Future<bool> updateFamilyNotificationPreferences(
    int userId,
    int familyId,
    FamilyNotificationPreferences preferences,
  ) async {
    try {
      debugPrint(
        'FamilyService: Updating notification preferences for family $familyId',
      );

      // Update family-level preferences
      await _apiService.updateMessagePreference(
        userId,
        familyId,
        preferences.receiveMessages,
      );

      // TODO: Update other notification types when API supports them

      debugPrint(
        'FamilyService: Successfully updated notification preferences',
      );
      return true;
    } catch (e) {
      debugPrint('FamilyService: Error updating notification preferences: $e');
      return false;
    }
  }

  // Helper method to parse role from API data
  FamilyRole _parseRole(String? role) {
    switch (role?.toUpperCase()) {
      case 'ADMIN':
      case 'FAMILY_ADMIN':
        return FamilyRole.admin;
      default:
        return FamilyRole.member;
    }
  }

  // Get family by ID
  Future<Family?> getFamilyById(int userId, int familyId) async {
    try {
      final families = await loadUserFamilies(userId);
      return families.firstWhere(
        (family) => family.id == familyId,
        orElse: () => throw Exception('Family not found'),
      );
    } catch (e) {
      debugPrint('FamilyService: Error getting family by ID: $e');
      return null;
    }
  }

  // Static method to create service instance
  static FamilyService of(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return FamilyService(apiService);
  }
}
