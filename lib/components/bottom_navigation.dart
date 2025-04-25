import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../screens/profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/invitations_screen.dart';

class BottomNavigation extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      backgroundColor: Theme.of(context).colorScheme.primary,
      selectedItemColor: Colors.white,
      unselectedItemColor: Colors.white70,
      currentIndex: currentIndex,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.message), label: 'Messages'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        BottomNavigationBarItem(icon: Icon(Icons.person_add), label: 'Invite'),
        BottomNavigationBarItem(icon: Icon(Icons.mail), label: 'Invitations'),
      ],
      onTap: (index) {
        if (index == currentIndex) return;

        switch (index) {
          case 0: // Messages
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) =>
                        HomeScreen(apiService: apiService, userId: userId),
              ),
            );
            break;
          case 1: // Profile
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => ProfileScreen(
                      apiService: apiService,
                      userId: userId,
                      role: userRole,
                    ),
              ),
            );
            break;
          case 2: // Invite
            onSendInvitation(index);
            break;
          case 3: // Invitations
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder:
                    (context) => InvitationsScreen(
                      apiService: apiService,
                      userId: userId,
                    ),
              ),
            );
            break;
        }
      },
    );
  }
}
