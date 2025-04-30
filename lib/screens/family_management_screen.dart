import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';
import '../components/bottom_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FamilyManagementScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final BottomNavigationController? navigationController;

  const FamilyManagementScreen({
    super.key,
    required this.apiService,
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadUserData();
    _loadUserPreferences();
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
        _loadInvitations(),
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

  // Load invitations
  Future<void> _loadInvitations() async {
    try {
      final invitations = await widget.apiService.getFamilyInvitationsForUser(
        widget.userId,
      );

      // Process each invitation to add missing information
      List<Map<String, dynamic>> processedInvitations = [];

      for (var invitation in invitations) {
        // Make a mutable copy of the invitation
        final processedInvitation = Map<String, dynamic>.from(invitation);

        // If familyName is missing but we have familyId, try to get it
        if ((processedInvitation['familyName'] == null ||
                processedInvitation['familyName'].toString().isEmpty) &&
            processedInvitation['familyId'] != null) {
          try {
            final familyId = processedInvitation['familyId'];
            final familyDetails = await widget.apiService.getFamily(familyId);
            processedInvitation['familyName'] = familyDetails['name'];
          } catch (e) {
            debugPrint('Error fetching family details: $e');
            // Keep the fallback handled in the UI
          }
        }

        // If inviterName is missing but we have inviterId, try to get it
        if ((processedInvitation['inviterName'] == null ||
                processedInvitation['inviterName'].toString().isEmpty) &&
            processedInvitation['inviterId'] != null) {
          try {
            final inviterId = processedInvitation['inviterId'];
            final inviterDetails = await widget.apiService.getUserById(
              inviterId,
            );
            processedInvitation['inviterName'] =
                '${inviterDetails['firstName']} ${inviterDetails['lastName']}';
          } catch (e) {
            debugPrint('Error fetching inviter details: $e');
            // Keep the fallback handled in the UI
          }
        }

        processedInvitations.add(processedInvitation);
      }

      if (mounted) {
        setState(() {
          _invitations = processedInvitations;
        });
      }
    } catch (e) {
      debugPrint('Error loading invitations: $e');
    }
  }

  // Respond to an invitation (accept or decline)
  Future<void> _respondToInvitation(int invitationId, bool accept) async {
    try {
      setState(() => _isLoading = true);

      if (accept) {
        await widget.apiService.respondToFamilyInvitation(invitationId, true);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation accepted!')));
      } else {
        await widget.apiService.respondToFamilyInvitation(invitationId, false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation declined')));
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

  // Dialog to show family members
  void _showFamilyMembersDialog(
    Map<String, dynamic> family,
    List<Map<String, dynamic>> members,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              '${family['familyName']} Family Members',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        final isCurrentUser = member['userId'] == widget.userId;

                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                isCurrentUser
                                    ? Colors.blue.shade100
                                    : Colors.green.shade100,
                            child: Text(
                              (member['firstName'] as String? ?? 'U')[0],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color:
                                    isCurrentUser
                                        ? Colors.blue.shade700
                                        : Colors.green.shade700,
                              ),
                            ),
                          ),
                          title: Text(
                            '${member['firstName']} ${member['lastName']}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color:
                                  isCurrentUser ? Colors.blue.shade700 : null,
                            ),
                          ),
                          subtitle: Text(
                            member['username'] ?? 'No username',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing:
                              isCurrentUser
                                  ? const Chip(
                                    label: Text(
                                      'You',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                      ),
                                    ),
                                    backgroundColor: Colors.blue,
                                    labelPadding: EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 0,
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: EdgeInsets.zero,
                                  )
                                  : null,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(fontSize: 14)),
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
    setState(() {
      _isLoading = true;
    });

    try {
      _userData = await widget.apiService.getUserById(widget.userId);
      debugPrint('Loaded user data: $_userData');

      // Try to load family details if the user belongs to a family
      if (_userData != null && _userData!['familyId'] != null) {
        try {
          // Load family members to get family details
          final members = await widget.apiService.getFamilyMembers(
            widget.userId,
          );
          debugPrint('Loaded family members: $members');

          // If the family name is not already in userData, try to get it from the first member
          if (members.isNotEmpty && members[0].containsKey('familyName')) {
            setState(() {
              _userData!['familyName'] = members[0]['familyName'];
            });
            debugPrint('Updated family name: ${_userData!['familyName']}');
          } else if (members.isNotEmpty && members[0].containsKey('lastName')) {
            // If there's no familyName field but there's a lastName, use that
            setState(() {
              _userData!['familyName'] = members[0]['lastName'];
            });
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadFamilyMembers() async {
    try {
      final members = await widget.apiService.getFamilyMembers(widget.userId);
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

    setState(() => _isLoading = true);

    try {
      // Check if user already owns a family (either from user data or _ownedFamily)
      final userData = await widget.apiService.getUserById(widget.userId);
      final existingFamilyId = userData['familyId'];

      if (existingFamilyId != null || _ownedFamily != null) {
        // User already owns a family - show error
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You already belong to a family. You can only create one family.',
            ),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Force leaving any existing family memberships by setting leaveCurrentFamily to true
      await widget.apiService.createFamily(widget.userId, familyName);
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
            'You already belong to a family. Please leave that family first.';
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _leaveFamily() async {
    try {
      await widget.apiService.leaveFamily(widget.userId);
      await _loadUserData(); // Reload user data with updated family info
      setState(() {}); // Trigger FutureBuilder to reload
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

    setState(() => _isLoading = true);

    try {
      // Use the owned family ID or active family ID for invitations
      final inviteFamilyId = _ownedFamily!['familyId'];

      // Make sure we're using the family we own for sending invitations
      await widget.apiService.inviteUser(widget.userId, email);

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
      setState(() => _isLoading = false);
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
        toolbarHeight: 65,
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
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              // User info header with either "Family Created" or "Create Family" button
              Padding(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 4,
                  bottom: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // User info (left side)
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

                    // Either Family Created indicator or Create Family button
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

              // TabBar - only show one tab now that we've redesigned the UI
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.people, size: 16),
                    text: 'Your Families',
                  ),
                  Tab(icon: Icon(Icons.mail, size: 16), text: 'Invitations'),
                ],
                indicatorColor: Colors.white,
                labelStyle: const TextStyle(fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          // Add invite button if user owns a family
          if (_ownedFamily != null)
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.white, size: 18),
              onPressed: () => _showInviteDialog(),
              tooltip: 'Send invitation to new family members',
            ),
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white, size: 18),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => ProfileScreen(
                        apiService: widget.apiService,
                        userId: widget.userId,
                        role: _userData?['role'],
                      ),
                ),
              );
            },
            tooltip: 'View and edit your profile settings',
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigation(
        currentIndex: 3, // Family management tab
        apiService: widget.apiService,
        userId: widget.userId,
        onSendInvitation: (_) => _showInviteDialog(),
        controller: widget.navigationController,
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

                      // Invitations tab
                      _buildInvitationsTab(),
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
          // Family selector - only show if user has at least one family
          if (_ownedFamily != null || _joinedFamilies.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'Select Active Family for Messages',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            // Active family selector
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              color: Colors.white.withAlpha(230),
              child: Column(
                children: [
                  // Make sure we have a default family selected
                  Builder(
                    builder: (context) {
                      // Create dropdown items first
                      final dropdownItems = <DropdownMenuItem<int>>[];
                      final familyIds = <int>[];

                      // Add owned family to the dropdown if it exists
                      if (_ownedFamily != null) {
                        final ownedFamilyId = _ownedFamily!['familyId'];
                        familyIds.add(ownedFamilyId);
                        dropdownItems.add(
                          DropdownMenuItem<int>(
                            value: ownedFamilyId,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.home,
                                  color: Colors.green,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${_ownedFamily!['familyName']} (Owner)',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      // Add joined families to the dropdown
                      for (final family in _joinedFamilies) {
                        final familyId = family['familyId'];
                        if (familyId != _ownedFamily?['familyId']) {
                          familyIds.add(familyId);
                          dropdownItems.add(
                            DropdownMenuItem<int>(
                              value: familyId,
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.group,
                                    color: Colors.blue,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${family['familyName']} (Member)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      // Now validate _activeFamilyId exists in dropdown options
                      if (_activeFamilyId == null ||
                          !familyIds.contains(_activeFamilyId)) {
                        // Set a valid family ID if current one is invalid
                        if (_ownedFamily != null) {
                          _activeFamilyId = _ownedFamily!['familyId'];
                        } else if (_joinedFamilies.isNotEmpty) {
                          _activeFamilyId = _joinedFamilies[0]['familyId'];
                        }
                      }

                      // Final check - if we have no valid families
                      final hasNoValidFamilyId =
                          _activeFamilyId == null || dropdownItems.isEmpty;

                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child:
                            hasNoValidFamilyId
                                ? const Text(
                                  'No families available for messaging',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                                : DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: _activeFamilyId,
                                    icon: const Icon(Icons.arrow_drop_down),
                                    iconSize: 24,
                                    elevation: 16,
                                    onChanged: (int? newValue) {
                                      setState(() {
                                        _activeFamilyId = newValue;
                                        _saveUserPreferences();
                                      });
                                    },
                                    items: dropdownItems,
                                  ),
                                ),
                      );
                    },
                  ),

                  // Option to send messages to multiple families
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 8.0,
                      right: 16.0,
                      bottom: 8.0,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _allowMultipleFamilyMessages,
                          onChanged: (bool? value) {
                            setState(() {
                              _allowMultipleFamilyMessages = value ?? false;
                              _saveUserPreferences();

                              // Show feedback to the user
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _allowMultipleFamilyMessages
                                        ? 'Messages will be sent to all your families'
                                        : 'Messages will be sent only to the selected family',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            });
                          },
                        ),
                        const Text(
                          'Send messages to all my families',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
          ],

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

          // Families you're a member of section
          if (_joinedFamilies.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Families You\'re A Member Of',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ..._joinedFamilies
                .where((f) => f['familyId'] != _ownedFamily?['familyId'])
                .map(
                  (family) => _buildFamilyCard(
                    family,
                    isOwned: false,
                    onTapView: () => _viewFamilyMembers(family),
                    onTapLeave: () => _promptLeaveFamily(family),
                  ),
                ),
            const SizedBox(height: 16),
          ],

          // No families message
          if (_ownedFamily == null && _joinedFamilies.isEmpty)
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
                    const Text(
                      'You don\'t have any families yet.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create a family or wait for an invitation to join one.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
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
    setState(() => _isLoading = true);

    try {
      // Load family members directly from API
      final members = await widget.apiService.getFamilyMembers(widget.userId);

      if (!mounted) return;

      // Show the members dialog
      _showFamilyMembersDialog(family, members);
    } catch (e) {
      debugPrint('Error loading family members: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading family members: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
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
            title: Text(
              familyName.toString(),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // View members button (always shown)
              if (onTapView != null)
                OutlinedButton.icon(
                  onPressed: onTapView,
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View Members'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                  ),
                ),

              // Leave button (only shown for joined families)
              if (!isOwned && onTapLeave != null)
                OutlinedButton.icon(
                  onPressed: onTapLeave,
                  icon: const Icon(Icons.exit_to_app, size: 16),
                  label: const Text('Leave'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvitationsTab() {
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
                  ).colorScheme.primary.withAlpha(204),
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
                            color: Colors.grey[600],
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

  // Method to get all families the user is associated with
  Future<void> _getUserFamilies() async {
    try {
      debugPrint('Loading user families');

      // First check if user has a familyId directly in their profile
      final userData = await widget.apiService.getUserById(widget.userId);

      // Get both the owned and joined families
      try {
        // Get family user owns (if any)
        final ownedFamily = await widget.apiService.getOwnedFamily(
          widget.userId,
        );
        if (ownedFamily != null) {
          debugPrint(
            'User owns family: ${ownedFamily['familyName']} (ID: ${ownedFamily['familyId']})',
          );
        }

        // Get families user has joined
        final joinedFamilies = await widget.apiService.getJoinedFamilies(
          widget.userId,
        );
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
            final familyDetails = await widget.apiService.getFamily(familyId);

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
          await widget.apiService.getInvitations();
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
              final Map<String, dynamic> familyDetails = await widget.apiService
                  .getFamily(familyId);

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
}
