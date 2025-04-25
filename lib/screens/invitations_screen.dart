import 'package:flutter/material.dart';
import 'package:familynest/services/api_service.dart';
import 'package:familynest/models/invitation.dart';
import '../components/bottom_navigation.dart';
import 'login_screen.dart';
import 'dart:async';
import 'home_screen.dart';

class InvitationsScreen extends StatefulWidget {
  final ApiService apiService;
  final int? userId; // Make this optional to handle invitations list

  const InvitationsScreen({Key? key, required this.apiService, this.userId})
    : super(key: key);

  @override
  _InvitationsScreenState createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  Future<List<Invitation>>? _invitationsFuture;
  Timer? _refreshTimer;
  String _lastRefreshed = "Never";
  Set<int> _acceptedFamilyIds = {};

  @override
  void initState() {
    super.initState();
    _loadInvitations();
    _updateRefreshTimestamp();

    // Set up periodic refresh for invitations (every 15 seconds instead of 5 for better performance)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) {
        setState(() {
          _loadInvitations();
          _updateRefreshTimestamp();
          debugPrint("Auto-refreshing invitations...");
        });
      }
    });
  }

  void _updateRefreshTimestamp() {
    final now = DateTime.now();
    _lastRefreshed =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Pull-to-refresh function
  Future<void> _refreshData() async {
    debugPrint("Manual refresh triggered");
    if (mounted) {
      setState(() {
        _loadInvitations();
        _updateRefreshTimestamp();
      });
    }
    return Future.delayed(
      const Duration(milliseconds: 800),
    ); // minimum refresh duration
  }

  void _loadInvitations() {
    _invitationsFuture = _fetchInvitations();
  }

  Future<List<Invitation>> _fetchInvitations() async {
    try {
      final response = await widget.apiService.getInvitations();
      final invitations =
          response.map((json) => Invitation.fromJson(json)).toList();

      // Update the set of accepted family IDs
      _acceptedFamilyIds =
          invitations
              .where((inv) => inv.status == 'ACCEPTED')
              .map((inv) => inv.familyId)
              .toSet();

      debugPrint('User is a member of families: $_acceptedFamilyIds');

      return invitations;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading invitations: $e')),
        );
      }
      return [];
    }
  }

  Future<void> _acceptInvitation(int invitationId) async {
    try {
      final result = await widget.apiService.acceptInvitation(invitationId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation accepted')));

        // Refresh the invitations list
        setState(() {
          _loadInvitations();
        });

        // Navigate to the home screen to see new family messages
        if (widget.userId != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder:
                  (context) => HomeScreen(
                    apiService: widget.apiService,
                    userId: widget.userId!,
                  ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error accepting invitation: $e')),
        );
      }
    }
  }

  Future<void> _rejectInvitation(int invitationId) async {
    try {
      await widget.apiService.rejectInvitation(invitationId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation rejected')));
      }
      setState(() {
        _loadInvitations();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error rejecting invitation: $e')),
        );
      }
    }
  }

  Future<void> _sendInvitation() async {
    if (widget.userId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User ID not available')));
      return;
    }

    final TextEditingController emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Invitation'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await widget.apiService.inviteUser(
                    widget.userId!,
                    emailController.text,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invitation sent successfully!'),
                    ),
                  );
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  // Show a more detailed error message
                  debugPrint('Error sending invitation: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                  // Keep the dialog open so they can fix the email
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  // Display improved UI for each invitation
  Widget _buildInvitationCard(Invitation invitation) {
    // Check if this is a duplicate invitation
    bool isDuplicate = _isDuplicateInvitation(invitation);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.family_restroom,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Family ID: ${invitation.familyId}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (isDuplicate)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Already Joined',
                                style: TextStyle(
                                  color: Colors.orange,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (invitation.email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'From: ${invitation.email}',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Status: ${invitation.status}',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color:
                              invitation.status == 'PENDING'
                                  ? Colors.orange
                                  : invitation.status == 'ACCEPTED'
                                  ? Colors.green
                                  : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Expires: ${_formatDateTime(invitation.expiresAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (invitation.status == 'PENDING' && !isDuplicate)
                  Row(
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Accept'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _acceptInvitation(invitation.id),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => _rejectInvitation(invitation.id),
                      ),
                    ],
                  ),
                // For duplicate invitations, show a simpler "Decline" button
                if (invitation.status == 'PENDING' && isDuplicate)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close),
                    label: const Text('Decline'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                    onPressed: () => _rejectInvitation(invitation.id),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to check if an invitation is for a family the user is already in
  bool _isDuplicateInvitation(Invitation invitation) {
    // Check if this invitation is for a family the user is already accepted into
    return invitation.status == 'PENDING' &&
        _acceptedFamilyIds.contains(invitation.familyId);
  }

  // Format date time string to be more readable
  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      return "${dateTime.month}/${dateTime.day}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateTimeStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitations'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshData,
            tooltip: 'Refresh Invitations',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              widget.apiService.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => LoginScreen(apiService: widget.apiService),
                ),
                (route) => false,
              );
            },
            tooltip: 'Logout',
          ),
        ],
      ),
      bottomNavigationBar:
          widget.userId != null
              ? BottomNavigation(
                currentIndex: 3, // Invitations tab
                apiService: widget.apiService,
                userId: widget.userId!,
                onSendInvitation: (_) => _sendInvitation(),
              )
              : null,
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: FutureBuilder<List<Invitation>>(
          future: _invitationsFuture ?? _fetchInvitations(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return Center(child: Text('Error: ${snapshot.error}'));
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Last refreshed: $_lastRefreshed',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 100),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mark_email_read,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No invitations found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'When someone invites you to their family,\nyou\'ll see it here',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ],
              );
            } else {
              // Filter out pending invitations for families the user is already a member of
              final filteredInvitations =
                  snapshot.data!.where((inv) {
                    // Always show accepted invitations
                    if (inv.status == 'ACCEPTED') return true;

                    // For pending invitations, only show if not duplicate
                    return !_isDuplicateInvitation(inv);
                  }).toList();

              if (filteredInvitations.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Last refreshed: $_lastRefreshed',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 100),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 64,
                          color: Colors.green[400],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No new invitations',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'You\'ve handled all your invitations',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ],
                );
              }

              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: filteredInvitations.length + 1, // +1 for timestamp
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Last refreshed: $_lastRefreshed',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  final invitation = filteredInvitations[index - 1];
                  return _buildInvitationCard(invitation);
                },
              );
            }
          },
        ),
      ),
    );
  }
}
