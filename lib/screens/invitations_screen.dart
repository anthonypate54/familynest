import 'package:flutter/material.dart';
import 'package:familynest/services/api_service.dart';
import 'package:familynest/models/invitation.dart';
import '../components/bottom_navigation.dart';
import 'login_screen.dart';

class InvitationsScreen extends StatefulWidget {
  final ApiService apiService;
  final int? userId; // Make this optional to handle invitations list

  const InvitationsScreen({Key? key, required this.apiService, this.userId})
    : super(key: key);

  @override
  _InvitationsScreenState createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends State<InvitationsScreen> {
  late Future<List<Invitation>> _invitationsFuture;

  @override
  void initState() {
    super.initState();
    _loadInvitations();
  }

  void _loadInvitations() {
    _invitationsFuture = _fetchInvitations();
  }

  Future<List<Invitation>> _fetchInvitations() async {
    try {
      final response = await widget.apiService.getInvitations();
      return response.map((json) => Invitation.fromJson(json)).toList();
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
      await widget.apiService.acceptInvitation(invitationId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation accepted')));
      }
      setState(() {
        _loadInvitations();
      });
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
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error sending invitation: $e')),
                  );
                }
                Navigator.pop(context);
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
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
      body: FutureBuilder<List<Invitation>>(
        future: _invitationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No invitations found.'));
          } else {
            return ListView.builder(
              itemCount: snapshot.data!.length,
              itemBuilder: (context, index) {
                final invitation = snapshot.data![index];
                return ListTile(
                  title: Text('Family ID: ${invitation.familyId}'),
                  subtitle: Text(
                    'Status: ${invitation.status} | Expires: ${invitation.expiresAt}',
                  ),
                  trailing:
                      invitation.status == 'PENDING'
                          ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                ),
                                onPressed:
                                    () => _acceptInvitation(invitation.id),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed:
                                    () => _rejectInvitation(invitation.id),
                              ),
                            ],
                          )
                          : null,
                );
              },
            );
          }
        },
      ),
    );
  }
}
