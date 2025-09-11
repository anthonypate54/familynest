import 'package:flutter/material.dart';

import '../controllers/bottom_navigation_controller.dart';

class BottomNavigation extends StatefulWidget {
  final int currentIndex;
  final int userId;
  final String userRole;
  final BottomNavigationController? controller;
  final int pendingInvitationsCount;
  // Add callback for handling tab changes
  final Function(int)? onTabChanged;

  const BottomNavigation({
    super.key,
    required this.currentIndex,
    required this.userId,
    this.userRole = 'USER',
    this.controller,
    this.pendingInvitationsCount = 0,
    this.onTabChanged,
  });

  @override
  State<BottomNavigation> createState() => _BottomNavigationState();
}

class _BottomNavigationState extends State<BottomNavigation> {
  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: widget.currentIndex,
      onTap: (index) {
        // Just call the callback to notify MainAppContainer to update its state
        if (widget.onTabChanged != null) {
          widget.onTabChanged!(index);
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.dynamic_feed),
          label: 'Feed',
        ),
        const BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'DMs'),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: 'Profile',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.family_restroom),
          label: 'Family',
        ),
        BottomNavigationBarItem(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.mail),
              if (widget.pendingInvitationsCount > 0)
                Positioned(
                  top: -5,
                  right: -5,
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
                    child: Text(
                      '${widget.pendingInvitationsCount}',
                      style: const TextStyle(color: Colors.white, fontSize: 8),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          label: 'Invitations',
        ),
      ],
      type: BottomNavigationBarType.fixed,
      selectedItemColor:
          Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Theme.of(context).primaryColor,
      unselectedItemColor:
          Theme.of(context).brightness == Brightness.dark
              ? Colors.white54
              : Colors.grey,
    );
  }
}
