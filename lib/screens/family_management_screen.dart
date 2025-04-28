import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';
import '../components/bottom_navigation.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadUserData();
    _loadFamilies();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
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
    if (_familyNameController.text.isEmpty) return;
    try {
      final familyId = await widget.apiService.createFamily(
        widget.userId,
        _familyNameController.text,
      );
      _familyNameController.clear();
      await _loadUserData(); // Reload user data with new family info
      setState(() {}); // Trigger FutureBuilder to reload

      // Refresh the bottom navigation to enable the invite button
      widget.navigationController?.refreshUserFamilies();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Family created with ID: $familyId'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Error creating family: $e';
      if (e.toString().contains('Only ADMIN can create families')) {
        errorMessage = 'Only admins can create families';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
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
    if (_inviteEmailController.text.isEmpty) return;

    // Default to owned family if none selected
    final familyId = _activeFamilyId ?? (_ownedFamily?['familyId'] as int?);
    if (familyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No family selected for invitation'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await widget.apiService.inviteUser(
        widget.userId,
        _inviteEmailController.text,
      );
      _inviteEmailController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invitation sent to join ${_getFamilyName(familyId)}!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Error sending invitation: $e');
      if (!mounted) return;

      // Create user-friendly error message
      String errorMessage = 'Failed to send invitation';

      if (e.toString().contains('500') ||
          e.toString().contains('Internal Server Error')) {
        errorMessage =
            'Server error. Please check that your family exists and try again later.';
      } else if (e.toString().contains('404')) {
        errorMessage = 'User not found. Please check the email address.';
      } else if (e.toString().contains('400')) {
        errorMessage = 'Invalid request. Please check your inputs.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
      );
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
      // Get the user's data to check their family
      final userData = await widget.apiService.getUserById(widget.userId);
      final currentFamilyId = userData['familyId'] as int?;

      // Get family members if user is in a family
      List<Map<String, dynamic>> members = [];
      if (currentFamilyId != null) {
        members = await widget.apiService.getFamilyMembers(widget.userId);
      }

      // Clear previous data
      _joinedFamilies = [];
      _ownedFamily = null;

      // If user has a family, add it to the appropriate list
      if (currentFamilyId != null) {
        // Get the actual family name from the database
        Map<String, dynamic> familyData;
        String familyName;

        try {
          familyData = await widget.apiService.getFamily(currentFamilyId);
          familyName = familyData['name'];
          debugPrint(
            'Loaded family name: $familyName for family ID: $currentFamilyId',
          );
        } catch (e) {
          debugPrint('Error loading family details: $e');
          // Fallback to a generic name if we can't load the actual name
          familyName = "Family #$currentFamilyId";
        }

        // Determine if user is the owner (you might need proper logic here)
        // For now, we'll assume the first user (ID 1) is the owner of family 1
        bool isOwner = widget.userId == 1 && currentFamilyId == 1;

        if (isOwner) {
          // User owns this family
          _ownedFamily = {
            'familyId': currentFamilyId,
            'familyName': familyName,
            'members': members,
          };
        }

        // Always add to joined families
        _joinedFamilies.add({
          'familyId': currentFamilyId,
          'familyName': familyName,
          'isOwner': isOwner,
        });
      }

      setState(() {});
    } catch (e) {
      debugPrint('Error loading families: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Family'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.family_restroom), text: 'Your Families'),
            Tab(icon: Icon(Icons.add_home), text: 'Create Family'),
          ],
          indicatorColor: Colors.white,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
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
            tooltip: 'Go to Profile',
          ),
        ],
      ),
      body: Container(
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
                    // Tab 1: Families the user is a member of
                    _buildFamiliesTab(),

                    // Tab 2: Create new family
                    _buildCreateFamilyTab(),
                  ],
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
            margin: const EdgeInsets.only(bottom: 16),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.green.shade100,
                        child: Text(
                          _userData?['firstName']?[0] ?? 'U',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_userData?['firstName'] ?? 'User'} ${_userData?['lastName'] ?? ''}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _userData?['username'] ?? 'Username',
                              style: TextStyle(
                                fontSize: 14,
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

          // 1. Family You Own Section (always at the top)
          if (_ownedFamily != null) ...[
            const Text(
              'Family You Own',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            _buildOwnedFamilyCard(_ownedFamily!),
          ],

          // 2. Families You're A Member Of (but don't own)
          if (_joinedFamilies.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Families You\'re A Member Of',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: 8),
            // Family membership cards - exclude owned family
            ...List.generate(_joinedFamilies.length, (index) {
              final family = _joinedFamilies[index];
              // Skip this family if it's the owned family
              if (_ownedFamily != null &&
                  family['familyId'] == _ownedFamily!['familyId'] &&
                  family['isOwner'] == true) {
                return const SizedBox.shrink(); // Return empty widget
              }
              return _buildFamilyCard(family);
            }).where(
              (widget) => widget is! SizedBox,
            ), // Filter out empty widgets
          ],

          // 3. Family Members Section - search across all families
          if (_joinedFamilies.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'Family Members',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 8),
            _buildFamilyMembersSearch(),
          ],
        ],
      ),
    );
  }

  // Building card for owned family with special styling
  Widget _buildOwnedFamilyCard(Map<String, dynamic> family) {
    final members = family['members'] ?? [];

    return Card(
      elevation: 4,
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.green.shade50, // Special background color for owned family
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.manage_accounts,
                  size: 28,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    family['familyName'],
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
                const Text(
                  'Owner',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Family ID: ${family['familyId']}',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${members.length} members',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.visibility),
                  label: const Text('View Members'),
                  onPressed: () {
                    _showFamilyMembersDialog(family, members);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add),
                  label: const Text('Invite'),
                  onPressed: () {
                    // Set the active family ID for invitations
                    _activeFamilyId = family['familyId'];
                    _showInviteDialog();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Building card for each family user is a member of (but doesn't own)
  Widget _buildFamilyCard(Map<String, dynamic> family) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.apiService.getFamilyMembers(widget.userId),
      builder: (context, snapshot) {
        // Get family members for this family
        final members = snapshot.data ?? [];
        final isOwner = family['isOwner'] ?? false;

        // Skip if this is the owned family (shouldn't happen due to the filter)
        if (isOwner &&
            _ownedFamily != null &&
            family['familyId'] == _ownedFamily!['familyId']) {
          return const SizedBox.shrink();
        }

        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          color: Colors.blue.shade50, // Special color for membership
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.family_restroom,
                      size: 28,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        family['familyName'],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                    const Text(
                      'Member',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Family ID: ${family['familyId']}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${members.length} members',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text('View Members'),
                      onPressed: () {
                        _showFamilyMembersDialog(family, members);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('Leave'),
                      onPressed: _leaveFamily,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // Create a widget for the family members search that works with all families
  Widget _buildFamilyMembersSearch() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadAllFamilyMembers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error loading family members: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final members = snapshot.data ?? [];

        if (members.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No family members found'),
            ),
          );
        }

        // Add search box for members
        return Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search All Family Members',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[200],
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon:
                        _searchQuery.isNotEmpty
                            ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                              },
                            )
                            : null,
                  ),
                ),
                const SizedBox(height: 16),

                // Filter members based on search
                ..._getFilteredMembers(members).map((member) {
                  final isCurrentUser = member['id'] == widget.userId;
                  final familyId = member['familyId'];
                  final isFromOwnedFamily =
                      _ownedFamily != null &&
                      familyId == _ownedFamily!['familyId'];

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isCurrentUser
                              ? Colors.purple.shade100
                              : isFromOwnedFamily
                              ? Colors.green.shade100
                              : Colors.blue.shade100,
                      child: Text(
                        (member['firstName'] as String? ?? 'U')[0],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color:
                              isCurrentUser
                                  ? Colors.purple.shade700
                                  : isFromOwnedFamily
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    title: Text(
                      '${member['firstName']} ${member['lastName']}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isCurrentUser ? Colors.purple.shade700 : null,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Text(member['username'] ?? 'No username'),
                        const SizedBox(width: 8),
                        Chip(
                          label: Text(
                            _getFamilyName(familyId),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                          backgroundColor:
                              isFromOwnedFamily ? Colors.green : Colors.blue,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    trailing:
                        isCurrentUser
                            ? const Chip(
                              label: Text('You'),
                              backgroundColor: Colors.purple,
                              labelStyle: TextStyle(color: Colors.white),
                            )
                            : null,
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  // Helper to get family name from ID
  String _getFamilyName(int? familyId) {
    if (familyId == null) return 'No Family';

    // First check our cached family data
    if (_ownedFamily != null && familyId == _ownedFamily!['familyId']) {
      return _ownedFamily!['familyName'];
    }

    for (final family in _joinedFamilies) {
      if (family['familyId'] == familyId) {
        return family['familyName'];
      }
    }

    // If we can't find the family name, use a standard format
    // We don't fetch from API here to avoid async issues in UI rendering
    return 'Family #$familyId';
  }

  // Helper to load a family name asynchronously for cases where we need it
  Future<String> _loadFamilyName(int familyId) async {
    try {
      final familyData = await widget.apiService.getFamily(familyId);
      return familyData['name'];
    } catch (e) {
      debugPrint('Error fetching family name: $e');
      return 'Family #$familyId';
    }
  }

  // Load members from all families the user belongs to
  Future<List<Map<String, dynamic>>> _loadAllFamilyMembers() async {
    List<Map<String, dynamic>> allMembers = [];

    try {
      // For each family the user is in, get the members
      for (final family in _joinedFamilies) {
        final familyId = family['familyId'];
        final members = await widget.apiService.getFamilyMembers(widget.userId);

        // Add family ID to each member for filtering
        for (final member in members) {
          member['familyId'] = familyId;
        }

        allMembers.addAll(members);
      }
    } catch (e) {
      debugPrint('Error loading all family members: $e');
    }

    return allMembers;
  }

  // Add a field to track which family is active for invitations
  int? _activeFamilyId;

  // Dialog to show family members
  void _showFamilyMembersDialog(
    Map<String, dynamic> family,
    List<Map<String, dynamic>> members,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('${family['familyName']} Family Members'),
            content: Container(
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
                          leading: CircleAvatar(
                            backgroundColor:
                                isCurrentUser
                                    ? Colors.blue.shade100
                                    : Colors.green.shade100,
                            child: Text(
                              (member['firstName'] as String? ?? 'U')[0],
                              style: TextStyle(
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
                              color:
                                  isCurrentUser ? Colors.blue.shade700 : null,
                            ),
                          ),
                          subtitle: Text(member['username'] ?? 'No username'),
                          trailing:
                              isCurrentUser
                                  ? const Chip(
                                    label: Text('You'),
                                    backgroundColor: Colors.blue,
                                    labelStyle: TextStyle(color: Colors.white),
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
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  // Dialog to invite user to family
  void _showInviteDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Invite to Family'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _inviteEmailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter email to invite',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[200],
                    prefixIcon: const Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
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
                  _inviteUserToFamily();
                  Navigator.pop(context);
                },
                child: const Text('Send Invitation'),
              ),
            ],
          ),
    );
  }

  // Create family tab
  Widget _buildCreateFamilyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Create a new family section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.add_home_work,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create Your Own Family',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Each user can create and manage their own family. You can be both an owner of your own family and a member of other families.',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Check if user already manages a family
                        if (_ownedFamily != null) ...[
                          Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  size: 48,
                                  color: Colors.green,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'You already manage a family',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${_ownedFamily!['familyName']} (ID: ${_ownedFamily!['familyId']})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          // Form to create a new family
                          Column(
                            children: [
                              TextField(
                                controller: _familyNameController,
                                decoration: InputDecoration(
                                  labelText: 'Family Name',
                                  hintText: 'Enter name for your family',
                                  border: OutlineInputBorder(),
                                  filled: true,
                                  fillColor: Colors.grey[200],
                                ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _createFamily,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                ),
                                child: const Text(
                                  'Create Family',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
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
}
