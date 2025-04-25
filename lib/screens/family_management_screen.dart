import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'profile_screen.dart';

class FamilyManagementScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const FamilyManagementScreen({
    super.key,
    required this.apiService,
    required this.userId,
  });

  @override
  FamilyManagementScreenState createState() => FamilyManagementScreenState();
}

class FamilyManagementScreenState extends State<FamilyManagementScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _familyNameController = TextEditingController();
  final TextEditingController _familyIdController = TextEditingController();
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

  Future<void> _joinFamily() async {
    if (_familyIdController.text.isEmpty) return;
    try {
      final familyId = int.parse(_familyIdController.text);
      await widget.apiService.joinFamily(widget.userId, familyId);
      _familyIdController.clear();
      await _loadUserData(); // Reload user data with new family info
      setState(() {}); // Trigger FutureBuilder to reload
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Joined family successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      // Create a more user-friendly error message
      String errorMessage = 'Unable to join family';

      if (e.toString().contains('already in that family')) {
        errorMessage = 'You are already a member of this family';
      } else if (e.toString().contains('already in a family')) {
        errorMessage =
            'You are already a member of another family. Please leave your current family first.';
      } else if (e.toString().contains('not found') ||
          e.toString().contains('does not exist')) {
        errorMessage =
            'Family not found. Please check the family ID and try again.';
      } else if (e.toString().contains('invitation')) {
        errorMessage = 'You need an invitation to join this family.';
      } else {
        errorMessage = 'Error joining family: $e';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
          duration: const Duration(seconds: 5),
        ),
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

    try {
      await widget.apiService.inviteUser(
        widget.userId,
        _inviteEmailController.text,
      );
      _inviteEmailController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invitation sent successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending invitation: $e'),
          backgroundColor: Colors.red,
        ),
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
      // This would be a new API endpoint to get all families for a user
      // For now we'll use existing methods
      final members = await widget.apiService.getFamilyMembers(widget.userId);
      final currentFamilyId = _userData?['familyId'] as int?;

      // Get list of families user is a member of
      _joinedFamilies = [];

      if (currentFamilyId != null) {
        _joinedFamilies.add({
          'familyId': currentFamilyId,
          'familyName':
              _userData?['familyName'] ?? _userData?['lastName'] ?? 'Family',
          'isOwner': _isOwnerOfFamily(members),
        });
      }

      // For now, we'll just check if user has created a family
      _ownedFamily =
          currentFamilyId != null && _isOwnerOfFamily(members)
              ? {
                'familyId': currentFamilyId,
                'familyName':
                    _userData?['familyName'] ??
                    _userData?['lastName'] ??
                    'Family',
                'members': members,
              }
              : null;

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
        backgroundColor: Colors.green,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.family_restroom), text: 'Your Families'),
            Tab(icon: Icon(Icons.add_home), text: 'Create Family'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Families the user is a member of
                  _buildFamiliesTab(),

                  // Tab 2: Create new family
                  _buildCreateFamilyTab(),
                ],
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
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _joinedFamilies.isNotEmpty
                              ? Colors.green.shade50
                              : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _joinedFamilies.isNotEmpty
                              ? Icons.family_restroom
                              : Icons.person_outline,
                          color:
                              _joinedFamilies.isNotEmpty
                                  ? Colors.green
                                  : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _joinedFamilies.isNotEmpty
                                ? 'Member of ${_joinedFamilies.length} ${_joinedFamilies.length == 1 ? 'family' : 'families'}'
                                : 'Not a member of any family',
                            style: TextStyle(
                              color:
                                  _joinedFamilies.isNotEmpty
                                      ? Colors.green.shade700
                                      : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Family membership section
          if (_joinedFamilies.isEmpty) ...[
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.family_restroom, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text(
                      'You\'re not a member of any family',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Join a family using an invitation or create your own',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const Text(
              'Your Families',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 8),
            // Family membership cards
            ...List.generate(_joinedFamilies.length, (index) {
              final family = _joinedFamilies[index];
              return _buildFamilyCard(family);
            }),
          ],

          // Join existing family section at the bottom
          const SizedBox(height: 24),
          Card(
            elevation: 3,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Join an Existing Family',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _familyIdController,
                    decoration: InputDecoration(
                      labelText: 'Family ID to Join',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.grey[200],
                      prefixIcon: const Icon(Icons.input),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Join Family'),
                      onPressed: _joinFamily,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
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

  // Building card for each family user is a member of
  Widget _buildFamilyCard(Map<String, dynamic> family) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: widget.apiService.getFamilyMembers(widget.userId),
      builder: (context, snapshot) {
        // Get family members for this family
        final members = snapshot.data ?? [];
        final isOwner = family['isOwner'] ?? false;

        return Card(
          elevation: 4,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isOwner ? Icons.manage_accounts : Icons.family_restroom,
                      size: 28,
                      color: isOwner ? Colors.green : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'The ${family['familyName']} Family',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color:
                              isOwner
                                  ? Colors.green.shade700
                                  : Colors.blue.shade700,
                        ),
                      ),
                    ),
                    Text(
                      isOwner ? 'Admin' : 'Member',
                      style: TextStyle(
                        fontSize: 14,
                        color: isOwner ? Colors.green : Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Divider(),
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
                        backgroundColor: Colors.blue,
                      ),
                    ),
                    if (isOwner)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.person_add),
                        label: const Text('Invite'),
                        onPressed: () {
                          _showInviteDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      )
                    else
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
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.add_home_work,
                        size: 28,
                        color: Colors.purple,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Create Your Own Family',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.purple.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Each user can create and manage one family of their own, while being a member of multiple families.',
                          style: TextStyle(color: Colors.purple.shade800),
                        ),
                        const SizedBox(height: 16),
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
                                  'The ${_ownedFamily!['familyName']} Family (ID: ${_ownedFamily!['familyId']})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          TextField(
                            controller: _familyNameController,
                            decoration: InputDecoration(
                              labelText: 'Family Name',
                              hintText: 'Enter a name for your new family',
                              border: const OutlineInputBorder(),
                              filled: true,
                              fillColor: Colors.white,
                              prefixIcon: const Icon(Icons.group_add),
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_joinedFamilies.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.amber.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.amber[700],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'You\'re already a member of another family. Creating a new family won\'t affect your existing memberships.',
                                      style: TextStyle(
                                        color: Colors.amber[800],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Create Family'),
                              onPressed: _createFamily,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.purple,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 16,
                                ),
                              ),
                            ),
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
}
