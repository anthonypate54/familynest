import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/subscription_api_service.dart';
import '../services/clean_onboarding_service.dart';
import '../models/subscription.dart';
import '../screens/subscription_required_screen.dart';

class SubscriptionGate extends StatefulWidget {
  final int userId;
  final String userRole;
  final int? initialTabIndex;

  const SubscriptionGate({
    Key? key,
    required this.userId,
    required this.userRole,
    this.initialTabIndex,
  }) : super(key: key);

  @override
  State<SubscriptionGate> createState() => _SubscriptionGateState();
}

class _SubscriptionGateState extends State<SubscriptionGate> {
  static const String _logTag = '🔒 SubscriptionGate';
  bool _isLoading = true;
  bool _hasAccess = false;
  Subscription? _subscription;
  String? _username;

  @override
  void initState() {
    super.initState();
    _validateAccess();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh when returning from subscription screen
    if (!_isLoading) {
      _validateAccess();
    }
  }

  Future<void> _validateAccess() async {
    debugPrint('$_logTag: Validating access for user ${widget.userId}');

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final subscriptionApi = SubscriptionApiService(apiService);

      // Get subscription status
      final subscriptionData = await subscriptionApi.getSubscriptionStatus();

      if (subscriptionData != null) {
        _subscription = Subscription.fromJson(subscriptionData);

        // Get the has_active_access field directly from backend
        final hasAccess = subscriptionData['has_active_access'] ?? false;

        debugPrint('$_logTag: Backend says has_active_access: $hasAccess');
        debugPrint('$_logTag: Subscription status: ${_subscription?.status}');
        debugPrint('$_logTag: Trial expired: ${_subscription?.trialExpired}');

        // Also get username for display
        final userMap = await apiService.getUserById(widget.userId);
        _username = userMap['username'] ?? 'User';

        setState(() {
          _hasAccess = hasAccess;
          _isLoading = false;
        });
      } else {
        debugPrint(
          '$_logTag: ❌ Failed to get subscription data - denying access',
        );
        setState(() {
          _hasAccess = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('$_logTag: ❌ Error validating access: $e');
      setState(() {
        _hasAccess = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _routeAfterAccessGranted() async {
    debugPrint('$_logTag: Routing through original onboarding flow');

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final userResponse = await apiService.getUserById(widget.userId);

      if (userResponse != null && mounted) {
        final onboardingState = userResponse['onboardingState'] ?? 0;

        // Route through the original onboarding service
        await CleanOnboardingService.routeAfterLogin(
          context,
          widget.userId,
          widget.userRole,
          onboardingState,
        );
      }
    } catch (e) {
      debugPrint('$_logTag: Error in onboarding routing: $e');
      // Fallback to direct routing if onboarding fails
      if (mounted) {
        CleanOnboardingService.normalFlow(
          context,
          widget.userId,
          widget.userRole,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Checking subscription status...'),
            ],
          ),
        ),
      );
    }

    if (_hasAccess) {
      // User has access - route through proper onboarding flow
      debugPrint(
        '$_logTag: ✅ Access granted - routing through onboarding flow',
      );
      // Use FutureBuilder to handle the async onboarding routing
      return FutureBuilder(
        future: _routeAfterAccessGranted(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // This should never be reached as routing will replace this widget
          return const Scaffold(body: Center(child: Text('Routing...')));
        },
      );
    } else {
      // User doesn't have access - show subscription required screen
      debugPrint(
        '$_logTag: ❌ Access denied - showing subscription required screen',
      );
      return SubscriptionRequiredScreen(
        username: _username ?? 'User',
        subscription: _subscription,
      );
    }
  }
}

/// Internal widget that routes users through the proper onboarding flow
/// after subscription validation passes
class _SubscriptionGateRouter extends StatefulWidget {
  final int userId;
  final String userRole;
  final int? initialTabIndex;

  const _SubscriptionGateRouter({
    required this.userId,
    required this.userRole,
    this.initialTabIndex,
  });

  @override
  State<_SubscriptionGateRouter> createState() =>
      _SubscriptionGateRouterState();
}

class _SubscriptionGateRouterState extends State<_SubscriptionGateRouter> {
  @override
  void initState() {
    super.initState();
    // Trigger the proper routing after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routeThroughOnboardingFlow();
    });
  }

  Future<void> _routeThroughOnboardingFlow() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final userResponse = await apiService.getUserById(widget.userId);

      if (userResponse != null && mounted) {
        final onboardingState = userResponse['onboarding_state'] ?? 0;

        debugPrint(
          '🔒 SubscriptionGate: Routing user ${widget.userId} with onboarding_state: $onboardingState',
        );

        // Use the original onboarding flow logic
        await CleanOnboardingService.routeAfterLogin(
          context,
          widget.userId,
          widget.userRole,
          onboardingState,
        );
      }
    } catch (e) {
      debugPrint('🔒 SubscriptionGate: Error in onboarding routing: $e');
      // Fallback to direct routing if onboarding fails
      if (mounted) {
        CleanOnboardingService.normalFlow(
          context,
          widget.userId,
          widget.userRole,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading while we determine the proper route
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ],
        ),
      ),
    );
  }
}
