import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../controllers/bottom_navigation_controller.dart';
import 'package:provider/provider.dart';
import '../widgets/gradient_background.dart';
import '../services/service_provider.dart';
import '../services/websocket_service.dart';

class InvitationsScreen extends StatefulWidget {
  final int userId;
  final BottomNavigationController? navigationController;

  const InvitationsScreen({
    Key? key,
    required this.userId,
    this.navigationController,
  }) : super(key: key);

  @override
  _InvitationsScreenState createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen>
    with WidgetsBindingObserver {
  late ApiService _apiService;
  List<Map<String, dynamic>> _invitations = [];
  bool _isLoading = false;
  WebSocketMessageHandler? _invitationHandler;

  @override
  void initState() {
    super.initState();
    _apiService = Provider.of<ApiService>(context, listen: false);
    WidgetsBinding.instance.addObserver(this);
    _loadInvitations();
    _setupWebSocketListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupWebSocketListener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // Refresh when app comes back into focus
      _loadInvitations();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh invitations when screen comes into focus
    if (mounted && !_isLoading) {
      _loadInvitations();
    }
  }

  Future<void> _loadInvitations() async {
    try {
      setState(() => _isLoading = true);
      final response = await _apiService.getInvitations();
      if (mounted) {
        setState(() {
          _invitations = response;
          _isLoading = false;
        });

        // Count pending invitations
        final pendingCount =
            response
                .where(
                  (inv) => inv['status'] != null && inv['status'] == 'PENDING',
                )
                .length;

        // Update the badge count if navigation controller is available
        if (widget.navigationController != null) {
          widget.navigationController!.setPendingInvitationsCount(pendingCount);
        }
      }
    } catch (e) {
      debugPrint('Error loading invitations: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _respondToInvitation(int invitationId, bool accept) async {
    try {
      setState(() => _isLoading = true);

      final response = await _apiService.respondToFamilyInvitation(
        invitationId,
        accept,
      );

      // The backend returns status and message fields, not success
      if (response.containsKey('status')) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response['message'] as String? ??
                  (accept ? 'Invitation accepted!' : 'Invitation declined'),
            ),
          ),
        );
      } else {
        throw Exception('Invalid response format from server');
      }

      // Refresh invitations
      await _loadInvitations();

      // Notify navigation controller if available
      if (widget.navigationController != null) {
        widget.navigationController!.refreshUserFamilies();
      }
    } catch (e) {
      debugPrint('Error responding to invitation: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Setup WebSocket listener for real-time invitation updates
  void _setupWebSocketListener() {
    try {
      final webSocketService = WebSocketService();

      // Create invitation handler for this screen
      _invitationHandler = (Map<String, dynamic> data) {
        debugPrint('🔄 INVITATIONS_SCREEN: Received WebSocket message: $data');

        final messageType = data['type'] as String?;
        if (messageType == 'NEW_INVITATION' ||
            messageType == 'INVITATION_ACCEPTED' ||
            messageType == 'INVITATION_DECLINED') {
          // Refresh the invitations list
          if (mounted) {
            _loadInvitations();
          }
        }
      };

      // Subscribe to invitation updates for the current user
      webSocketService.subscribe(
        '/user/${widget.userId}/invitations',
        _invitationHandler!,
      );
      debugPrint(
        '🔌 INVITATIONS_SCREEN: Subscribed to /user/${widget.userId}/invitations',
      );
    } catch (e) {
      debugPrint('❌ INVITATIONS_SCREEN: Error setting up WebSocket: $e');
    }
  }

  // Cleanup WebSocket listener
  void _cleanupWebSocketListener() {
    try {
      if (_invitationHandler != null) {
        final webSocketService = WebSocketService();
        webSocketService.unsubscribe(
          '/user/${widget.userId}/invitations',
          _invitationHandler!,
        );
        debugPrint('🔌 INVITATIONS_SCREEN: Unsubscribed from WebSocket');
      }
    } catch (e) {
      debugPrint('❌ INVITATIONS_SCREEN: Error cleaning up WebSocket: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Invitations'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadInvitations,
            tooltip: 'Refresh Invitations',
          ),
        ],
      ),
      body: GradientBackground(child: _buildInvitationsContent()),
    );
  }

  Widget _buildInvitationsContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    // If there are no invitations
    if (_invitations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail, size: 64, color: Colors.white70),
              const SizedBox(height: 16),
              const Text(
                'No invitations',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'When someone invites you to join their family, you\'ll see it here.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // If there are invitations
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _invitations.length,
      itemBuilder: (context, index) {
        final invitation = _invitations[index];

        // Get invitation details with fallback values if missing
        final familyName =
            invitation['familyName'] ??
            'Family #${invitation['familyId'] ?? ''}';
        final inviterName = invitation['inviterName'] ?? 'A family member';
        final inviterId = invitation['inviterId'];
        final familyId = invitation['familyId'];
        final invitationId = invitation['id'];
        final status = invitation['status'] ?? 'PENDING';

        // Only show action buttons for pending invitations
        final isPending = status == 'PENDING';

        return Card(
          elevation: 3,
          margin: const EdgeInsets.only(bottom: 16.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with circular avatar for visual appeal
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.8),
                  child: const Icon(Icons.mail, color: Colors.white, size: 20),
                ),
                title: Text(
                  familyName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text('From: $inviterName'),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              // Invitation details
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isPending) ...[
                      const Text(
                        'Join this family?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You have been invited to join the $familyName family. Would you like to accept this invitation?',
                      ),
                    ] else ...[
                      Text(
                        status == 'ACCEPTED'
                            ? 'You are a member of this family.'
                            : 'You declined this invitation.',
                        style: TextStyle(
                          color:
                              status == 'ACCEPTED' ? Colors.green : Colors.red,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    if (familyId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'Family ID: $familyId',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Action buttons - only show for pending invitations
              if (isPending)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed:
                            () => _respondToInvitation(invitationId, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: const Text('Decline'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed:
                            () => _respondToInvitation(invitationId, true),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.green,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        child: const Text('Accept'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
