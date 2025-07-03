import 'package:flutter/foundation.dart';
import '../services/api_service.dart';

class InvitationService {
  final ApiService apiService;

  InvitationService({required this.apiService});

  // Load invitations with proper state management
  Future<void> loadInvitations({
    required int userId,
    required Function(bool) setLoadingState,
    required Function(List<Map<String, dynamic>>) setInvitationsState,
    required Function() checkIfMounted,
  }) async {
    // Set loading state to true
    setLoadingState(true);

    try {
      final invitations = await apiService.getFamilyInvitationsForUser(userId);

      // Process each invitation to add missing information
      List<Map<String, dynamic>> processedInvitations = [];

      for (var invitation in invitations) {
        // Make a mutable copy of the invitation
        final processedInvitation = Map<String, dynamic>.from(invitation);

        // If familyName is missing but we have familyId, try to get it
        if ((processedInvitation['familyName'] == null ||
                processedInvitation['familyName'].toString().isEmpty) &&
            processedInvitation['familyId'] != null) {
          try {
            final familyId = processedInvitation['familyId'];
            final familyDetails = await apiService.getFamily(familyId);
            processedInvitation['familyName'] = familyDetails['name'];
          } catch (e) {
            debugPrint('Error fetching family details: $e');
            // Keep the fallback handled in the UI
          }
        }

        // If inviterName is missing but we have inviterId, try to get it
        if ((processedInvitation['inviterName'] == null ||
                processedInvitation['inviterName'].toString().isEmpty) &&
            processedInvitation['inviterId'] != null) {
          try {
            final inviterId = processedInvitation['inviterId'];
            final inviterDetails = await apiService.getUserById(inviterId);
            processedInvitation['inviterName'] =
                '${inviterDetails['firstName']} ${inviterDetails['lastName']}';
          } catch (e) {
            debugPrint('Error fetching inviter details: $e');
            // Keep the fallback handled in the UI
          }
        }

        processedInvitations.add(processedInvitation);
      }

      // Check if component is still mounted before updating state
      if (checkIfMounted()) {
        // Set invitations state
        setInvitationsState(processedInvitations);
        // Set loading state to false
        setLoadingState(false);
      }
    } catch (e) {
      debugPrint('Error loading invitations: $e');
      // Check if component is still mounted before updating state
      if (checkIfMounted()) {
        // Set loading state to false on error too
        setLoadingState(false);
      }
    }
  }

  // The original method is still useful for some cases
  Future<List<Map<String, dynamic>>> getProcessedInvitations(int userId) async {
    try {
      final invitations = await apiService.getFamilyInvitationsForUser(userId);

      // Process each invitation to add missing information
      List<Map<String, dynamic>> processedInvitations = [];

      for (var invitation in invitations) {
        // Make a mutable copy of the invitation
        final processedInvitation = Map<String, dynamic>.from(invitation);

        // If familyName is missing but we have familyId, try to get it
        if ((processedInvitation['familyName'] == null ||
                processedInvitation['familyName'].toString().isEmpty) &&
            processedInvitation['familyId'] != null) {
          try {
            final familyId = processedInvitation['familyId'];
            final familyDetails = await apiService.getFamily(familyId);
            processedInvitation['familyName'] = familyDetails['name'];
          } catch (e) {
            debugPrint('Error fetching family details: $e');
            // Keep the fallback handled in the UI
          }
        }

        // If inviterName is missing but we have inviterId, try to get it
        if ((processedInvitation['inviterName'] == null ||
                processedInvitation['inviterName'].toString().isEmpty) &&
            processedInvitation['inviterId'] != null) {
          try {
            final inviterId = processedInvitation['inviterId'];
            final inviterDetails = await apiService.getUserById(inviterId);
            processedInvitation['inviterName'] =
                '${inviterDetails['firstName']} ${inviterDetails['lastName']}';
          } catch (e) {
            debugPrint('Error fetching inviter details: $e');
            // Keep the fallback handled in the UI
          }
        }

        processedInvitations.add(processedInvitation);
      }

      return processedInvitations;
    } catch (e) {
      debugPrint('Error loading invitations: $e');
      return [];
    }
  }

  // Respond to an invitation (accept or decline)
  Future<bool> respondToInvitation(int invitationId, bool accept) async {
    try {
      debugPrint(
        '🔍 Attempting to ${accept ? 'accept' : 'decline'} invitation ID: $invitationId',
      );
      final result = await apiService.respondToFamilyInvitation(
        invitationId,
        accept,
      );
      debugPrint(
        '✅ Successfully responded to invitation: ${result.toString()}',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error responding to invitation: $e');
      return false;
    }
  }

  // Send an invitation to join family
  Future<Map<String, dynamic>> inviteUserToFamily(
    int userId,
    String email,
  ) async {
    try {
      final response = await apiService.inviteUser(userId, email);

      // The enhanced response includes:
      // - userExists: boolean
      // - suggestedEmails: List<String> (if userExists is false)
      // - message: enhanced message
      // - recipientName: String (if userExists is true)

      return {
        'success': true,
        'userExists': response['userExists'] ?? false,
        'message': response['message'] ?? 'Invitation sent successfully',
        'recipientName': response['recipientName'],
        'suggestedEmails':
            response['suggestedEmails'] != null
                ? (response['suggestedEmails'] as List<dynamic>).cast<String>()
                : null,
        'suggestionMessage': response['suggestionMessage'],
      };
    } catch (e) {
      debugPrint('Error sending invitation: $e');

      // Check if it's our custom InvitationException with suggestions
      if (e is InvitationException) {
        return {
          'success': false,
          'error': e.message,
          'userExists': e.userExists,
          'suggestedEmails': e.suggestedEmails,
        };
      }

      // For other exceptions, return simple error
      return {'success': false, 'error': e.toString()};
    }
  }
}
