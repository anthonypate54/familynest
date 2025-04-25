import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/invitations_screen.dart';
import 'dart:async';
import '../models/invitation.dart';

class BottomNavigation extends StatefulWidget {
  final int currentIndex;
  final ApiService apiService;
  final int userId;
  final String? userRole;
  final Function(int) onSendInvitation;

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    required this.apiService,
    required this.userId,
    this.userRole,
    required this.onSendInvitation,
  });

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  bool _hasPendingInvitations = false;
  Timer? _invitationCheckTimer;
  Set<int> _userFamilyIds = {};

  @override
  void initState() {
    super.initState();
    _getUserFamilies();
    _checkForInvitations();
    // Set up a timer to periodically check for invitations (every 15 seconds)
    _invitationCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkForInvitations();
    });
  }

  @override
  void dispose() {
    _invitationCheckTimer?.cancel();
    super.dispose();
  }

  // Get the families the user is already a member of
  Future<void> _getUserFamilies() async {
    try {
      final userData = await widget.apiService.getUserById(widget.userId);
      if (userData['familyId'] != null) {
        setState(() {
          _userFamilyIds.add(userData['familyId']);
        });
        debugPrint('User belongs to family: ${userData['familyId']}');
      }
    } catch (e) {
      debugPrint('Error getting user family data: $e');
    }
  }

  Future<void> _checkForInvitations() async {
    try {
      final response = await widget.apiService.getInvitations();
      final invitations =
          response.map((json) => Invitation.fromJson(json)).toList();

      // Find accepted invitations to update user family IDs
      final acceptedFamilyIds =
          invitations
              .where((inv) => inv.status == 'ACCEPTED')
              .map((inv) => inv.familyId)
              .toSet();

      if (acceptedFamilyIds.isNotEmpty) {
        setState(() {
          _userFamilyIds.addAll(acceptedFamilyIds);
        });
      }

      // Check if there are any relevant pending invitations (not for families the user is already in)
      final relevantPendingInvitations =
          invitations
              .where(
                (invitation) =>
                    invitation.status == 'PENDING' &&
                    !_userFamilyIds.contains(invitation.familyId),
              )
              .toList();

      final hasPending = relevantPendingInvitations.isNotEmpty;

      if (mounted && hasPending != _hasPendingInvitations) {
        setState(() {
          _hasPendingInvitations = hasPending;
        });

        // If we're on the invitations screen and there are no pending invitations, force refresh
        if (!hasPending && widget.currentIndex == 3) {
          _checkForInvitations();
        }
      }
    } catch (e) {
      debugPrint('Error checking for invitations: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Theme.of(context).colorScheme.primary,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white70,
      currentIndex: widget.currentIndex,
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.message),
          label: 'Messages',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_add),
          label: 'Invite',
        ),
        BottomNavigationBarItem(
          icon: Stack(
            children: [
              const Icon(Icons.mail),
              if (_hasPendingInvitations)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child: const Text(
                      '',
                      style: TextStyle(color: Colors.white, fontSize: 8),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          label: 'Invitations',
        ),
      ],
      onTap: (index) {
        if (index == widget.currentIndex) return;

        switch (index) {
          case 0: // Messages
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => HomeScreen(
                      apiService: widget.apiService,
                      userId: widget.userId,
                    ),
              ),
            );
            break;
          case 1: // Profile
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => ProfileScreen(
                      apiService: widget.apiService,
                      userId: widget.userId,
                      role: widget.userRole,
                    ),
              ),
            );
            break;
          case 2: // Invite
            widget.onSendInvitation(index);
            break;
          case 3: // Invitations
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => InvitationsScreen(
                      apiService: widget.apiService,
                      userId: widget.userId,
                    ),
              ),
            );
            break;
        }
      },
    );
  }
}
