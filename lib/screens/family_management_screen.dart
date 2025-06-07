import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/service_provider.dart';
import '../services/invitation_service.dart';
import 'profile_screen.dart';
import '../components/bottom_navigation.dart';
import '../dialogs/families_message_dialog.dart';
import '../dialogs/member_message_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../utils/page_transitions.dart';
import '../controllers/bottom_navigation_controller.dart';
import 'package:provider/provider.dart';

class FamilyManagementScreen extends StatefulWidget {
  final int userId;
  final BottomNavigationController? navigationController;

  const FamilyManagementScreen({
    super.key,
    required this.userId,
    this.navigationController,
  });

  @override
  FamilyManagementScreenState createState() => FamilyManagementScreenState();
}

class FamilyManagementScreenState extends State<FamilyManagementScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _familyNameController = TextEditingController();
  final TextEditingController _inviteEmailController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String _searchQuery = '';

  // For managing the tab view
  late TabController _tabController;
  List<Map<String, dynamic>> _joinedFamilies = [];
  Map<String, dynamic>? _ownedFamily;
  List<Map<String, dynamic>> _invitations = [];

  // Track which family is active for invitations
  int? _activeFamilyId;

  // New state variables
  String? _errorMessage;
  bool _allowMultipleFamilyMessages = false;

  // Services
  late InvitationService _invitationService;

  // Add this to the state class variables
  List<Map<String, dynamic>> _messagePreferences = [];
  bool _loadingPreferences = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadUserData();
    _loadUserPreferences();
    _loadMessagePreferences();

    // Add delayed ServiceProvider initialization check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServiceProvider();
    });
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _inviteEmailController.dispose();
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // Load all data needed for the screen
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      await Future.wait([
        _loadUserData(),
        _getUserFamilies(),
        _loadMessagePreferences(),
      ]);
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Method to refresh data
  Future<void> _refreshData() async {
    await _loadData();
  }

  // Load invitations using the improved invitation service
  Future<void> _loadInvitations() async {
    try {
      // Check if ServiceProvider is initialized before accessing services
      final serviceProvider = ServiceProvider();

      // Wait for ServiceProvider to be initialized if it's not ready yet
      if (!serviceProvider.isInitialized) {
        debugPrint(
          'ServiceProvider not ready yet, skipping invitation loading',
        );
        return; // Exit gracefully, invitations will remain empty
      }

      final invitationService = serviceProvider.invitationService;

      await invitationService.loadInvitations(
        userId: widget.userId,
        setLoadingState: (isLoading) {
          if (mounted) {
            setState(() {
              // We'll leave the main _isLoading state unchanged since it's controlled by _loadData
              // But we could update a dedicated invitation loading state if needed
            });
          }
        },
        setInvitationsState: (invitations) {
          if (mounted) {
            setState(() {
              _invitations = invitations;
            });
          }
        },
        checkIfMounted: () => mounted,
      );
    } catch (e) {
      debugPrint('Error loading invitations (ServiceProvider not ready): $e');
      // Invitations will remain empty, which is fine - screen will work without them
      if (mounted) {
        setState(() {
          // Keep loading state consistent
        });
      }
    }
  }

  // Respond to an invitation (accept or decline)
  Future<void> _respondToInvitation(int invitationId, bool accept) async {
    try {
      setState(() => _isLoading = true);

      final success = await _invitationService.respondToInvitation(
        invitationId,
        accept,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept ? 'Invitation accepted!' : 'Invitation declined',
            ),
          ),
        );
      } else {
        throw Exception('Failed to process invitation');
      }

      // Refresh all data
      await _loadData();
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

  // Show the dialog to create a new family
  void _showCreateFamilyDialog() {
    _familyNameController.clear();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Create Your Family',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter a name for your family. After creating a family, you can invite members to join.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _familyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Family Name',
                    hintText: 'Enter name for your family',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  _createFamily();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  // Dialog to invite user to family
  void _showInviteDialog() {
    _inviteEmailController.clear();
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Invite to Family',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Show which family the invitation is for
                if (_ownedFamily != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Text(
                      'You are inviting a new member to join:\n${_ownedFamily!['familyName']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blue,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(
                    'Enter the email address of the person you want to invite to your family. They will receive an invitation to join.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                TextField(
                  controller: _inviteEmailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter email to invite',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[200],
                    prefixIcon: const Icon(Icons.email),
                    labelStyle: const TextStyle(fontSize: 14),
                    hintStyle: const TextStyle(fontSize: 14),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(fontSize: 16),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 16)),
              ),
              ElevatedButton(
                onPressed: () {
                  _inviteUserToFamily();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text(
                  'Send Invitation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
    );
  }

  // Filter members based on search query
  List<Map<String, dynamic>> _getFilteredMembers(
    List<Map<String, dynamic>> members,
  ) {
    if (_searchQuery.isEmpty) {
      return members;
    }

    final searchTerms =
        _searchQuery.split(' ').where((term) => term.isNotEmpty).toList();

    return members.where((member) {
      final firstName = (member['firstName'] as String?)?.toLowerCase() ?? '';
      final lastName = (member['lastName'] as String?)?.toLowerCase() ?? '';
      final username = (member['username'] as String?)?.toLowerCase() ?? '';
      final fullName = '$firstName $lastName'.toLowerCase();

      // Check if any search term is found in any of the fields
      for (final term in searchTerms) {
        if (firstName.contains(term) ||
            lastName.contains(term) ||
            username.contains(term) ||
            fullName.contains(term)) {
          return true;
        }
      }

      return false;
    }).toList();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      _userData = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getUserById(widget.userId);
      debugPrint('Loaded user data: $_userData');

      // Try to load family details if the user belongs to a family
      if (_userData != null && _userData!['familyId'] != null) {
        try {
          // Load family members to get family details
          final members = await Provider.of<ApiService>(
            context,
            listen: false,
          ).getFamilyMembers(widget.userId);
          debugPrint('Loaded family members: $members');

          // If the family name is not already in userData, try to get it from the first member
          if (members.isNotEmpty && members[0].containsKey('familyName')) {
            if (mounted) {
              setState(() {
                _userData!['familyName'] = members[0]['familyName'];
              });
            }
            debugPrint('Updated family name: ${_userData!['familyName']}');
          } else if (members.isNotEmpty && members[0].containsKey('lastName')) {
            // If there's no familyName field but there's a lastName, use that
            if (mounted) {
              setState(() {
                _userData!['familyName'] = members[0]['lastName'];
              });
            }
            debugPrint(
              'Using lastName as family name: ${_userData!['familyName']}',
            );
          }
        } catch (e) {
          debugPrint('Error loading family details: $e');
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadFamilyMembers() async {
    try {
      final members = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getFamilyMembers(widget.userId);
      return members;
    } catch (e) {
      debugPrint('Error loading family members: $e');
      return [];
    }
  }

  Future<void> _createFamily() async {
    final familyName = _familyNameController.text.trim();
    if (familyName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a family name')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Check if user already owns a family
      // Only prevent creation if they own a family, not if they're a member of one
      if (_ownedFamily != null) {
        // User already owns a family - show error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You already own a family. You can only create one family.',
            ),
          ),
        );
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      // Proceed with family creation - user can be member of other families
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).createFamily(widget.userId, familyName);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Family created successfully!')),
      );
      await _refreshData();
    } catch (e) {
      debugPrint('Error creating family: $e');
      // Show a more user-friendly error message
      String errorMessage = 'Error creating family';
      if (e.toString().contains('already belongs to a family')) {
        errorMessage =
            'Server error: This API needs to be updated to support multiple families.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _leaveFamily() async {
    try {
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).leaveFamily(widget.userId);
      await _loadUserData(); // Reload user data with updated family info
      if (mounted) {
        setState(() {}); // Trigger FutureBuilder to reload
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Left family successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error leaving family: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _inviteUserToFamily() async {
    final email = _inviteEmailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    if (_ownedFamily == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You need to create a family first')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Use invitation service to send invitation
      final success = await _invitationService.inviteUserToFamily(
        widget.userId,
        email,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invitation sent to $email'),
            backgroundColor: Colors.green,
          ),
        );

        // Clear the input field
        _inviteEmailController.clear();

        // Refresh data to show new pending invitations
        await _refreshData();
      } else {
        throw Exception('Failed to send invitation');
      }
    } catch (e) {
      debugPrint('Error sending invitation: $e');

      // Show a user-friendly error message
      String errorMessage = 'Failed to send invitation';

      if (e.toString().contains('not found')) {
        errorMessage = 'User not found. Please check the email address.';
      } else if (e.toString().contains('already belongs to')) {
        errorMessage = 'User already belongs to a family.';
      } else if (e.toString().contains('already invited')) {
        errorMessage = 'User has already been invited to this family.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Check if user is the family creator/owner
  bool _isOwnerOfFamily(List<Map<String, dynamic>> members) {
    // The person who created the family is usually the first member
    if (members.isEmpty) return false;

    // Try to find the member with role 'FAMILY_ADMIN' or similar
    final member = members.firstWhere(
      (m) => m['userId'] == widget.userId,
      orElse: () => {},
    );

    return member.containsKey('role') &&
        (member['role'] == 'ADMIN' || member['role'] == 'FAMILY_ADMIN');
  }

  // Get family relationship text based on ownership
  String _getFamilyRelationshipText(bool isOwner) {
    return isOwner ? 'Family Admin' : 'Family Details';
  }

  String _getFamilyNameDisplayText() {
    final familyName = _userData?['familyName'];
    if (familyName != null) {
      return 'Member of the $familyName Family';
    } else {
      // Try to use last name if available
      final lastName = _userData?['lastName'];
      if (lastName != null) {
        return 'Member of the $lastName Family';
      }
      return 'Member of a Family';
    }
  }

  // Load all families the user is associated with
  Future<void> _loadFamilies() async {
    try {
      await _loadUserData();
      await _getUserFamilies();
      await _loadAcceptedInvitations();
      setState(() {});
    } catch (e) {
      debugPrint('Error loading families: $e');
    }
  }

  // Check if user already owns (created) a family
  bool _isUserFamilyOwner() {
    // If we have an owned family data, user is the owner
    return _ownedFamily != null;
  }

  // Build method that handles both tabs
  @override
  Widget build(BuildContext context) {
    // User owns a family only if _ownedFamily is set
    bool userOwnsFamily = _ownedFamily != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        elevation: 0,
        toolbarHeight: 40,
        title: const Text(
          'Manage Family',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 0,
                  bottom: 16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.white.withAlpha(76),
                            child: Text(
                              _userData?['firstName']?[0] ?? 'U',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            _userData?['username'] ?? 'User',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    userOwnsFamily
                        ? Row(
                          children: const [
                            Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Family Created',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        )
                        : GestureDetector(
                          onTap: () {
                            _showCreateFamilyDialog();
                          },
                          child: Row(
                            children: const [
                              Icon(
                                Icons.home_filled,
                                color: Colors.white,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Create Family',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white, size: 18),
            onPressed: () {
              slidePush(
                context,
                ProfileScreen(
                  userId: widget.userId,
                  userRole: _userData?['role'],
                ),
              );
            },
            tooltip: 'View and edit your profile settings',
          ),
        ],
      ),

      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
          child:
              _isLoading
                  ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                  : TabBarView(
                    controller: _tabController,
                    children: [
                      // Families tab
                      _buildFamiliesTab(),
                    ],
                  ),
        ),
      ),
    );
  }

  Widget _buildFamiliesTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // User Info Card
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.green.shade100,
                        child: Text(
                          _userData?['firstName']?[0] ?? 'U',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_userData?['firstName'] ?? 'User'} ${_userData?['lastName'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _userData?['username'] ?? 'Username',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Family Summary Dashboard - Quick overview of all families
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Family Dashboard',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Count of owned and joined families
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryItem(
                          title: 'You Own',
                          count: _ownedFamily != null ? 1 : 0,
                          icon: Icons.admin_panel_settings,
                          color: Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _buildSummaryItem(
                          title: 'Member Of',
                          count: _isUserMemberOfOtherFamilies() ? 1 : 0,
                          icon: Icons.people,
                          color: Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _buildSummaryItem(
                          title: 'Total Members',
                          count: _getTotalFamilyMembers(),
                          icon: Icons.groups,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Family you own section (if any)
          if (_ownedFamily != null) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Family You Own',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildFamilyCard(
              _ownedFamily!,
              isOwned: true,
              onTapView: () => _viewFamilyMembers(_ownedFamily!),
            ),
            const SizedBox(height: 24),
          ],

          // No families message - only show if user doesn't own a family
          if (_ownedFamily == null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.family_restroom,
                      size: 64,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _joinedFamilies.isEmpty
                          ? 'You don\'t have any families yet.'
                          : 'You haven\'t created your own family yet.',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _joinedFamilies.isEmpty
                          ? 'Create a family or wait for an invitation to join one.'
                          : 'Create your own family to manage and invite others.',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _showCreateFamilyDialog,
                      icon: const Icon(Icons.add_home),
                      label: const Text('Create Family'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Show a confirmation dialog before leaving a family
  void _promptLeaveFamily(Map<String, dynamic> family) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Leave Family?'),
            content: Text(
              'Are you sure you want to leave the ${family['familyName']} family? This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _leaveFamily();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Leave Family'),
              ),
            ],
          ),
    );
  }

  // Open the members screen for a family
  void _viewFamilyMembers(Map<String, dynamic> family) async {
    // Prevent multiple rapid taps
    if (_isLoading) return;

    // Show the dialog immediately with no loading indicators
    showDialog(
      context: context,
      builder:
          (context) =>
              MemberMessageDialog(userId: widget.userId, family: family),
    );
  }

  // Build card for an individual family
  Widget _buildFamilyCard(
    Map<String, dynamic> family, {
    required bool isOwned,
    VoidCallback? onTapView,
    VoidCallback? onTapLeave,
  }) {
    final familyId = family['familyId'];
    final familyName = family['familyName'];
    final memberCount = family['memberCount'] ?? 0;
    final isActive = _activeFamilyId == familyId;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        side:
            isActive
                ? BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2.0,
                )
                : BorderSide.none,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with family name and role
          ListTile(
            leading: Icon(
              isOwned ? Icons.home : Icons.mail,
              color: isOwned ? Colors.green : Colors.blue,
              size: 28,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    familyName.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                // Add the buttons in a row
                if (isOwned) ...[
                  // Invite button
                  IconButton(
                    icon: const Icon(Icons.person_add, size: 18),
                    tooltip: 'Invite family members',
                    onPressed: () => _showInviteDialog(),
                  ),
                  // Edit button
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: 'Edit family name',
                    onPressed: () => _showEditFamilyNameDialog(family),
                  ),
                ],
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isOwned ? Colors.green : Colors.blue,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                isOwned ? 'Owner' : 'Member',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Divider
          const Divider(height: 1),

          // Family details
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                const Text('Family ID: '),
                Text(
                  '$familyId',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  isOwned && memberCount <= 1
                      ? 'Just you (Owner)'
                      : '$memberCount members',
                ),
              ],
            ),
          ),

          // Status message
          if (isOwned)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Invite family members to join your family!',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // View members button (always shown)
                if (onTapView != null)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTapView,
                      icon: const Icon(Icons.visibility, size: 18),
                      label: const Text('Members'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),

                // Add Families button to manage message preferences
                if (onTapView != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _showFamiliesMessageDialog(),
                      icon: const Icon(Icons.family_restroom, size: 18),
                      label: const Text('Families'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],

                // Leave button (only shown for joined families)
                if (!isOwned && onTapLeave != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onTapLeave,
                      icon: const Icon(Icons.exit_to_app, size: 18),
                      label: const Text('Leave'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Show the families message dialog
  void _showFamiliesMessageDialog() {
    showDialog(
      context: context,
      builder: (context) => FamiliesMessageDialog(userId: widget.userId),
    );
  }

  // Method to get all families the user is associated with
  Future<void> _getUserFamilies() async {
    try {
      debugPrint('Loading user families');

      // First check if user has a familyId directly in their profile
      final userData = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getUserById(widget.userId);

      // Get both the owned and joined families
      try {
        // Get family user owns (if any)
        final ownedFamily = await Provider.of<ApiService>(
          context,
          listen: false,
        ).getOwnedFamily(widget.userId);
        if (ownedFamily != null) {
          debugPrint(
            'User owns family: ${ownedFamily['familyName']} (ID: ${ownedFamily['familyId']})',
          );
        }

        // Get families user has joined
        final joinedFamilies = await Provider.of<ApiService>(
          context,
          listen: false,
        ).getJoinedFamilies(widget.userId);
        debugPrint('User joined ${joinedFamilies.length} families');

        if (mounted) {
          setState(() {
            _ownedFamily = ownedFamily;
            _joinedFamilies = joinedFamilies;

            // Set active family ID if not already set
            if (_activeFamilyId == null) {
              // Prefer the owned family as active if it exists
              if (ownedFamily != null) {
                _activeFamilyId = ownedFamily['familyId'];
              }
              // Otherwise use the first joined family
              else if (joinedFamilies.isNotEmpty) {
                _activeFamilyId = joinedFamilies[0]['familyId'];
              }
            }
          });
        }
      } catch (e) {
        // API endpoints not available
        debugPrint('Error loading multiple families: $e');

        // Fallback to single family ID approach
        final familyId = userData['familyId'] as int?;
        if (familyId != null) {
          try {
            final familyDetails = await Provider.of<ApiService>(
              context,
              listen: false,
            ).getFamily(familyId);

            // Determine if user is owner by checking if they're the creator
            final isOwner = familyDetails['createdBy'] == widget.userId;

            if (mounted) {
              setState(() {
                if (isOwner) {
                  _ownedFamily = {
                    'familyId': familyId,
                    'familyName': familyDetails['name'] ?? userData['lastName'],
                    'memberCount': familyDetails['memberCount'] ?? 0,
                    'isOwner': true,
                    'role': 'ADMIN',
                  };

                  // Also add to joined families list for UI consistency
                  _joinedFamilies = [_ownedFamily!];
                } else {
                  // User is just a member, add to joined families
                  final family = {
                    'familyId': familyId,
                    'familyName': familyDetails['name'] ?? 'Family #$familyId',
                    'memberCount': familyDetails['memberCount'] ?? 0,
                    'isOwner': false,
                    'role': 'MEMBER',
                  };
                  _joinedFamilies = [family];
                  // Ensure _ownedFamily is null since user is not the owner
                  _ownedFamily = null;
                }

                // Set active family
                _activeFamilyId = familyId;
              });
            }
          } catch (e) {
            debugPrint('Error getting family details: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading user families: $e');
    }
  }

  // Check if the user is a member of other families
  bool _isUserMemberOfOtherFamilies() {
    // Check if any family in joined families is not owned by the user
    return _joinedFamilies.any(
      (f) => !(f['isOwner'] ?? false) || (f['fromInvitation'] ?? false),
    );
  }

  // Load accepted invitations as these represent families the user is a member of
  Future<void> _loadAcceptedInvitations() async {
    try {
      List<Map<String, dynamic>> invitations =
          await Provider.of<ApiService>(
            context,
            listen: false,
          ).getInvitations();
      debugPrint('Loaded ${invitations.length} invitations');

      List<Map<String, dynamic>> acceptedInvitations = [];
      for (var invitation in invitations) {
        // Only consider accepted invitations
        if (invitation['status'] == 'ACCEPTED') {
          final familyId = invitation['familyId'];
          final inviterId = invitation['inviterId'];

          debugPrint(
            'User has ACCEPTED invitation to family $familyId from user $inviterId',
          );

          // Check if we already have this family in our list
          if (!_joinedFamilies.any((f) => f['familyId'] == familyId) &&
              !acceptedInvitations.any((i) => i['familyId'] == familyId)) {
            // Try to get family details
            try {
              final Map<String, dynamic> familyDetails =
                  await Provider.of<ApiService>(
                    context,
                    listen: false,
                  ).getFamily(familyId);

              final newFamily = {
                'familyId': familyId,
                'familyName': familyDetails['name'],
                'isOwner': false,
                'memberCount': familyDetails['memberCount'] ?? 0,
                'isActive': false,
                'fromInvitation': true,
              };

              acceptedInvitations.add(newFamily);
              debugPrint(
                'Added family ${familyDetails['name']} with ID $familyId from invitation',
              );
            } catch (e) {
              debugPrint('Error getting family details for invitation: $e');
            }
          }
        }
      }

      // Now safely add all the accepted invitations to joined families
      if (acceptedInvitations.isNotEmpty) {
        setState(() {
          _joinedFamilies.addAll(acceptedInvitations);
        });
      }

      // Debug log all families
      debugPrint(
        'After loading invitations, user has ${_joinedFamilies.length} families:',
      );
      for (var family in _joinedFamilies) {
        debugPrint(
          '- Family: ${family['familyName']} (ID: ${family['familyId']}), isOwner: ${family['isOwner']}, fromInvitation: ${family['fromInvitation'] ?? false}',
        );
      }
    } catch (e) {
      debugPrint('Error loading invitations: $e');
    }
  }

  // Get family name for display
  String _getFamilyName(Map<String, dynamic> family) {
    return family['familyName'] ?? 'Unnamed Family';
  }

  // Load user preferences from SharedPreferences
  Future<void> _loadUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _activeFamilyId = prefs.getInt('activeFamilyId');
      _allowMultipleFamilyMessages =
          prefs.getBool('allowMultipleFamilyMessages') ?? false;
    });
  }

  // Save user preferences to SharedPreferences
  Future<void> _saveUserPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('activeFamilyId', _activeFamilyId ?? -1);
    await prefs.setBool(
      'allowMultipleFamilyMessages',
      _allowMultipleFamilyMessages,
    );
  }

  // Show dialog to edit family name
  void _showEditFamilyNameDialog(Map<String, dynamic> family) {
    final TextEditingController nameController = TextEditingController();
    nameController.text = family['familyName'] ?? '';

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              'Edit Family Name',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter a new name for your family.',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Family Name',
                    hintText: 'Enter new name for your family',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  _updateFamilyName(
                    family['familyId'],
                    nameController.text.trim(),
                  );
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  // Update family name
  Future<void> _updateFamilyName(int familyId, String newName) async {
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a family name')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).updateFamilyDetails(familyId, newName);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Family name updated to "$newName"')),
      );
      await _refreshData();
    } catch (e) {
      debugPrint('Error updating family name: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating family name: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Add this method to load message preferences
  Future<void> _loadMessagePreferences() async {
    setState(() => _loadingPreferences = true);

    try {
      final preferences = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getMessagePreferences(widget.userId);

      if (mounted) {
        setState(() {
          _messagePreferences = preferences;
          _loadingPreferences = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading message preferences: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load message preferences: $e')),
        );
        setState(() => _loadingPreferences = false);
      }
    }
  }

  // Build a summary item for the family dashboard
  Widget _buildSummaryItem({
    required String title,
    required int count,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  // Calculate the total number of family members across all families
  int _getTotalFamilyMembers() {
    int total = 0;

    // Add members from owned family
    if (_ownedFamily != null) {
      total += _ownedFamily!['memberCount'] as int? ?? 0;
    }

    // Add members from joined families, excluding the owned family if it's in the list
    for (var family in _joinedFamilies) {
      // Skip the owned family if it's in the joined families list to avoid counting twice
      if (_ownedFamily != null &&
          family['familyId'] == _ownedFamily!['familyId']) {
        continue;
      }
      total += family['memberCount'] as int? ?? 0;
    }

    // If total is 0, return at least 1 for the current user
    return total > 0 ? total : 1;
  }

  // Add this new method
  void _initializeServiceProvider() {
    try {
      if (ServiceProvider().isInitialized) {
        _invitationService = ServiceProvider().invitationService;
        _loadInvitations(); // Load invitations only after ServiceProvider is ready
      } else {
        // Retry after a short delay
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _initializeServiceProvider();
          }
        });
      }
    } catch (e) {
      debugPrint('ServiceProvider not ready yet, will retry: $e');
      // Retry after a longer delay
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          _initializeServiceProvider();
        }
      });
    }
  }
}
