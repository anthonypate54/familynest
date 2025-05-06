import 'package:flutter/material.dart';

// Ensure correct imports for your screen classes
// Adjust paths based on your project structure
import '../screens/home_screen.dart';
import '../screens/family_management_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/invitations_screen.dart';
import '../utils/page_transitions.dart'; // Import the page transitions

import '../services/api_service.dart'; // Import ApiService if not already imported

class BottomNavigationController {
  void refreshUserFamilies() {
    // Implementation to refresh family data
  }
}

class BottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ApiService apiService;
  final int userId;
  final String? userRole;
  final BottomNavigationController? controller;
  final int pendingInvitationsCount; // Count of pending invitations

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    required this.apiService,
    required this.userId,
    this.userRole,
    required this.controller,
    this.pendingInvitationsCount = 0, // Default to 0 if not provided
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) {
        // Messages tab (index 0)
        if (index == 0 && currentIndex != 0) {
          slidePushReplacement(
            context,
            HomeScreen(apiService: apiService, userId: userId),
          );
        }
        // Profile tab (index 1)
        else if (index == 1 && currentIndex != 1) {
          slidePushReplacement(
            context,
            ProfileScreen(
              apiService: apiService,
              userId: userId,
              userRole: userRole,
            ),
          );
        }
        // Family tab (index 2)
        else if (index == 2 && currentIndex != 2) {
          slidePushReplacement(
            context,
            FamilyManagementScreen(
              apiService: apiService,
              userId: userId,
              navigationController: controller,
            ),
          );
        }
        // Invitations tab (index 3)
        else if (index == 3 && currentIndex != 3) {
          slidePushReplacement(
            context,
            InvitationsScreen(
              apiService: apiService,
              userId: userId,
              navigationController: controller,
            ),
          );
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.message),
          label: 'Messages',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.group), label: 'Family'),
        // Invitations tab with badge for pending invitations
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.mail),
              if (pendingInvitationsCount > 0)
                Positioned(
                  right: -5,
                  top: -5,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 12,
                      minHeight: 12,
                    ),
                    child:
                        pendingInvitationsCount > 9
                            ? const Text(
                              '9+',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            )
                            : pendingInvitationsCount > 0
                            ? Text(
                              '$pendingInvitationsCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            )
                            : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
          label: 'Invitations',
        ),
      ],
      selectedItemColor: Theme.of(context).colorScheme.primary,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
    );
  }
}
