import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../main.dart';

class FreshUserOnboardingScreen extends StatefulWidget {
  final int userId;
  final String userRole;

  const FreshUserOnboardingScreen({
    super.key,
    required this.userId,
    required this.userRole,
  });

  @override
  FreshUserOnboardingScreenState createState() =>
      FreshUserOnboardingScreenState();
}

class FreshUserOnboardingScreenState extends State<FreshUserOnboardingScreen> {
  PageController _pageController = PageController();
  int _currentPage = 0;
  bool _hasPendingInvitations = false;
  bool _checkingInvitations = true;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '🆕 FRESH_USER_ONBOARDING: Screen initialized for user ${widget.userId}',
    );
    _checkForPendingInvitations();
  }

  Future<void> _checkForPendingInvitations() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final invitations = await apiService.getInvitations();

      // Count only PENDING invitations
      final pendingCount =
          invitations.where((invitation) {
            return invitation['status'] == 'PENDING';
          }).length;

      debugPrint(
        '🆕 FRESH_USER_ONBOARDING: Found $pendingCount pending invitations',
      );

      if (mounted) {
        setState(() {
          _hasPendingInvitations = pendingCount > 0;
          _checkingInvitations = false;
        });
      }
    } catch (e) {
      debugPrint('🆕 FRESH_USER_ONBOARDING: Error checking invitations: $e');
      if (mounted) {
        setState(() {
          _hasPendingInvitations = false;
          _checkingInvitations = false;
        });
      }
    }
  }

  @override
  void dispose() {
    debugPrint('🆕 FRESH_USER_ONBOARDING: Screen disposed');
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Progress indicator
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  for (int i = 0; i < 3; i++)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              i <= _currentPage
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Page view content
          Expanded(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              children: [
                _buildWelcomePage(),
                _buildFeaturePage(),
                _buildGetStartedPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Welcome icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              Icons.family_restroom,
              size: 64,
              color: Theme.of(context).primaryColor,
            ),
          ),

          const SizedBox(height: 32),

          const Text(
            'Welcome to FamilyNest!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          const Text(
            'Connect with your family members and share precious moments together in a private, secure space.',
            style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _nextPage(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Get Started',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturePage() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(60),
            ),
            child: const Icon(Icons.auto_awesome, size: 64, color: Colors.blue),
          ),

          const SizedBox(height: 32),

          const Text(
            'Family Features',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          _buildFeatureItem(Icons.message, 'Share messages and photos'),
          _buildFeatureItem(Icons.video_library, 'Share videos and memories'),
          _buildFeatureItem(Icons.group, 'Connect multiple families'),
          _buildFeatureItem(
            Icons.notifications,
            'Stay updated with notifications',
          ),
          _buildFeatureItem(Icons.privacy_tip, 'Private and secure'),

          const SizedBox(height: 48),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _nextPage(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Continue',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGetStartedPage() {
    // Show loading if still checking for invitations
    if (_checkingInvitations) {
      return const Padding(
        padding: EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 24),
            Text(
              'Checking for invitations...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon and title based on invitation status
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color:
                  _hasPendingInvitations
                      ? Theme.of(context).colorScheme.secondary.withOpacity(0.1)
                      : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              _hasPendingInvitations ? Icons.mail : Icons.rocket_launch,
              size: 64,
              color:
                  _hasPendingInvitations
                      ? Theme.of(context).colorScheme.secondary
                      : Colors.green,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            _hasPendingInvitations ? 'You\'re Invited!' : 'Ready to Begin?',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            _hasPendingInvitations
                ? 'Great news! You have pending family invitations waiting for you.'
                : 'Choose how you\'d like to start your FamilyNest journey.',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.grey,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 48),

          // Action buttons - order based on invitation status
          if (_hasPendingInvitations) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _checkInvitations(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'View Invitations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _createFamily(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Create Your Own Family',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _createFamily(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Create Your Family',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _checkInvitations(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Check for Invitations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          TextButton(
            onPressed: () => _exploreApp(),
            child: const Text(
              'Skip for now',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).primaryColor, size: 20),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _createFamily() {
    debugPrint(
      '🆕 FRESH_USER_ONBOARDING: User wants to create family - closing tour',
    );

    // Simply close the tour modal
    // OnboardingService will handle navigation to FamilyManagementScreen
    Navigator.of(context).pop();
  }

  void _checkInvitations() {
    debugPrint(
      '🆕 FRESH_USER_ONBOARDING: Checking invitations for user ${widget.userId}',
    );

    // Close onboarding modal first
    Navigator.of(context).pop();

    // Then navigate to MainAppContainer with invitations tab
    Future.delayed(const Duration(milliseconds: 100), () {
      debugPrint(
        '🆕 FRESH_USER_ONBOARDING: Navigating to invitations tab for user ${widget.userId}',
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder:
                (context) => MainAppContainer(
                  userId: widget.userId,
                  userRole: widget.userRole,
                  initialTabIndex: 4, // Invitations tab
                ),
          ),
        );
      }
    });
  }

  void _exploreApp() {
    debugPrint(
      '🆕 FRESH_USER_ONBOARDING: User ${widget.userId} exploring the app',
    );
    // Simply close the onboarding and let user explore the main app
    Navigator.of(context).pop();
  }
}
