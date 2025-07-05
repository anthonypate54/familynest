import 'package:flutter/material.dart';
import '../models/family.dart';
import '../services/family_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../dialogs/family_notification_dialog.dart';
import '../widgets/gradient_background.dart';
import 'package:provider/provider.dart';

class FamilyManagementScreen extends StatefulWidget {
  final int userId;

  const FamilyManagementScreen({Key? key, required this.userId})
    : super(key: key);

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _isLoadingData = false;
  List<Family> _families = [];
  Family? _ownedFamily;
  Family? _selectedFamily;
  List<Map<String, dynamic>> _allMembers = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  final _searchController = TextEditingController();
  final _familyNameController = TextEditingController();
  final _inviteEmailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _familyNameController.dispose();
    _inviteEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (_isLoadingData) {
      debugPrint(
        'FamilyManagementScreen: _loadData already in progress, skipping...',
      );
      return;
    }

    _isLoadingData = true;
    setState(() => _isLoading = true);

    try {
      final familyService = FamilyService.of(context);
      final families = await familyService.loadUserFamilies(widget.userId);

      // Find owned family
      Family? ownedFamily =
          families.where((f) => f.isOwned).isNotEmpty
              ? families.firstWhere((f) => f.isOwned)
              : null;

      // Set default selected family to null to show all members initially
      Family? selectedFamily = null;

      // Use members that are already loaded in the Family objects
      List<Map<String, dynamic>> allMembers = [];
      for (var family in families) {
        // Use the members that are already loaded in the Family object
        for (var member in family.members) {
          allMembers.add({
            'familyId': family.id,
            'familyName': family.name,
            'userId': member.id,
            'firstName': member.firstName,
            'lastName': member.lastName,
            'username': member.username,
            'isOwner': member.isOwner,
            'joinedAt': member.joinedAt,
            'isMuted': member.isMuted,
          });
        }
      }

      if (mounted) {
        setState(() {
          _families = families;
          _ownedFamily = ownedFamily;
          _selectedFamily = selectedFamily;
          _allMembers = allMembers;
          _filteredMembers = allMembers;
          _isLoading = false;
        });

        // Apply initial filtering
        _filterMembers();
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    } finally {
      _isLoadingData = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: GradientBackground(
        child: Column(
          children: [
            // Tab bar
            Container(
              color: Colors.transparent,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'Family'),
                  Tab(text: 'Members'),
                  Tab(text: 'Settings'),
                ],
              ),
            ),

            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildFamilyTab(),
                  _buildMembersTab(),
                  _buildSettingsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Family Management',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      centerTitle: true,
      backgroundColor: Theme.of(context).colorScheme.primary,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          onPressed: _loadData,
          tooltip: 'Refresh',
        ),
      ],
    );
  }

  Widget _buildFamilyTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_ownedFamily != null)
            _buildFamilyCreatedCard()
          else
            _buildCreateFamilyCard(),

          const SizedBox(height: 16),

          // Show member families (non-owned)
          if (_families.where((f) => !f.isOwned).isNotEmpty) ...[
            _buildMemberFamiliesCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildFamilyCreatedCard() {
    if (_ownedFamily == null) return const SizedBox();

    final family = _ownedFamily!;

    // Use _allMembers for owned family count since it's populated correctly
    final ownedFamilyMembers =
        _allMembers.where((m) => m['familyId'] == family.id).toList();
    final memberCount = ownedFamilyMembers.length;

    final newMembers =
        ownedFamilyMembers.where((m) {
          final joinedAt = m['joinedAt'] as DateTime?;
          if (joinedAt == null) return false;
          final daysSinceJoined = DateTime.now().difference(joinedAt).inDays;
          return daysSinceJoined <= 7; // Show as "new" for 7 days
        }).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // "Family Created" header with checkmark
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.green),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Family Created',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Family info
            Row(
              children: [
                Icon(Icons.family_restroom, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Text(
                  family.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '$memberCount members',
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // New members highlight
            if (newMembers.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.new_releases,
                          color: Colors.blue,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'New Members',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...newMembers.map(
                      (member) => Text(
                        '• ${member['firstName']} ${member['lastName']}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Invite button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showInviteDialog(),
                icon: const Icon(Icons.person_add),
                label: const Text('Invite New Member'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateFamilyCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_circle, color: Colors.orange),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create Your Family',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Start connecting with your family members',
                        style: TextStyle(color: Colors.grey, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showCreateFamilyDialog(),
                icon: const Icon(Icons.family_restroom),
                label: const Text('Create Family'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberFamiliesCard() {
    final memberFamilies = _families.where((f) => !f.isOwned).toList();

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Member Of',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...memberFamilies.map(
              (family) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people, color: Colors.grey),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            family.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '${family.members.length} members',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembersTab() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    return Column(
      children: [
        // Search bar and family selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(20),
              bottomRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Search text field
              TextField(
                controller: _searchController,
                onChanged: (value) {
                  _filterMembers(); // Use the filtering method
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search family members...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  suffixIcon:
                      _searchController.text.isNotEmpty
                          ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white),
                            onPressed: () {
                              _searchController.clear();
                              _filterMembers();
                            },
                          )
                          : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.2),
                ),
              ),

              // Family selector dropdown (only show if multiple families)
              if (_families.length > 1) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<Family?>(
                      value: _selectedFamily,
                      isExpanded: true,
                      dropdownColor: Theme.of(context).colorScheme.primary,
                      style: const TextStyle(color: Colors.white),
                      hint: const Text(
                        'All Families',
                        style: TextStyle(color: Colors.white),
                      ),
                      items: [
                        const DropdownMenuItem<Family?>(
                          value: null,
                          child: Text(
                            'All Families',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        ..._families.map((family) {
                          return DropdownMenuItem<Family?>(
                            value: family,
                            child: Text(
                              family.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                      ],
                      onChanged: (Family? family) {
                        setState(() {
                          _selectedFamily = family;
                        });
                        _filterMembers(); // Apply filtering
                      },
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Members list
        Expanded(
          child:
              _filteredMembers.isEmpty
                  ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: Colors.white,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'No family members found',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                      ],
                    ),
                  )
                  : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _filteredMembers.length,
                    itemBuilder: (context, index) {
                      final member = _filteredMembers[index];
                      return _buildMemberCard(member);
                    },
                  ),
        ),
      ],
    );
  }

  Widget _buildMemberCard(Map<String, dynamic> member) {
    final isNew = () {
      if (member['joinedAt'] == null) return false;
      final joinedAt = member['joinedAt'] as DateTime;
      final daysSinceJoined = DateTime.now().difference(joinedAt).inDays;
      return daysSinceJoined <= 7;
    }();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _viewMemberDemographics(member),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Member avatar
              CircleAvatar(
                radius: 20,
                backgroundColor:
                    isNew
                        ? Colors.green
                        : Color(member['firstName'].hashCode | 0xFF000000),
                child: Text(
                  member['firstName'][0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Member name and info - expanded to fill space
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${member['firstName']} ${member['lastName']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (isNew) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'NEW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '@${member['username']}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Mute checkbox - right column
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Mute',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Checkbox(
                    value: member['isMuted'] ?? false,
                    onChanged: (value) {
                      _toggleMemberMute(member, value ?? false);
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Demographics Visibility
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Demographics Visibility',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text(
                    'Show my address',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Allow family members to see your address',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'Show my phone number',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Allow family members to see your phone',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'Show my birthday',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Allow family members to see your birthday',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Notification Preferences
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notification Preferences',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text(
                    'Family messages',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Receive notifications for family messages',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'New member alerts',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Get notified when someone joins the family',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
                SwitchListTile(
                  title: const Text(
                    'Invitation notifications',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Receive notifications for new invitations',
                    style: TextStyle(color: Colors.white70),
                  ),
                  value: true, // TODO: Connect to actual preference
                  onChanged: (value) {
                    // TODO: Implement preference update
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showCreateFamilyDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Create Family'),
            content: TextField(
              controller: _familyNameController,
              decoration: const InputDecoration(
                labelText: 'Family Name',
                hintText: 'Enter your family name',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => _createFamily(),
                child: const Text('Create'),
              ),
            ],
          ),
    );
  }

  void _showInviteDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Invite Member'),
            content: TextField(
              controller: _inviteEmailController,
              decoration: const InputDecoration(
                labelText: 'Email Address',
                hintText: 'Enter member email',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => _inviteMember(),
                child: const Text('Invite'),
              ),
            ],
          ),
    );
  }

  Future<void> _createFamily() async {
    final name = _familyNameController.text.trim();
    if (name.isEmpty) return;

    try {
      Navigator.pop(context);

      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.createFamily(widget.userId, name);

      _familyNameController.clear();
      await _loadData();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Family created successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating family: $e')));
      }
    }
  }

  Future<void> _inviteMember() async {
    final email = _inviteEmailController.text.trim();
    if (email.isEmpty) return;

    try {
      Navigator.pop(context);

      final familyService = FamilyService.of(context);
      await familyService.sendInvitation(
        widget.userId,
        email,
        _ownedFamily?.name ?? '',
      );

      _inviteEmailController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitation sent successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending invitation: $e')));
      }
    }
  }

  Future<void> _toggleMemberMute(Map<String, dynamic> member, bool mute) async {
    try {
      final familyService = FamilyService.of(context);
      await familyService.updateMemberMuteStatus(
        widget.userId,
        member['familyId'],
        member['userId'],
        mute,
      );

      setState(() {
        member['isMuted'] = mute;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Member ${mute ? 'muted' : 'unmuted'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error updating member: $e')));
      }
    }
  }

  Future<void> _viewMemberDemographics(Map<String, dynamic> member) async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final userDetails = await apiService.getUserById(member['userId']);

      if (mounted) {
        _showDemographicsDialog(userDetails);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading member details: $e')),
        );
      }
    }
  }

  void _showDemographicsDialog(Map<String, dynamic> userDetails) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              '${userDetails['firstName']} ${userDetails['lastName']}',
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (userDetails['address'] != null) ...[
                    const Text(
                      'Address:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(userDetails['address']),
                    const SizedBox(height: 8),
                  ],
                  if (userDetails['city'] != null) ...[
                    const Text(
                      'City:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${userDetails['city']}, ${userDetails['state']} ${userDetails['zipCode']}',
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (userDetails['phoneNumber'] != null) ...[
                    const Text(
                      'Phone:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(userDetails['phoneNumber']),
                    const SizedBox(height: 8),
                  ],
                  if (userDetails['birthDate'] != null) ...[
                    const Text(
                      'Birthday:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(userDetails['birthDate'].toString()),
                    const SizedBox(height: 8),
                  ],
                  if (userDetails['bio'] != null) ...[
                    const Text(
                      'Bio:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(userDetails['bio']),
                  ],
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

  void _filterMembers() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      _filteredMembers =
          _allMembers.where((member) {
            // Filter by selected family if one is chosen
            if (_selectedFamily != null &&
                member['familyId'] != _selectedFamily!.id) {
              return false;
            }

            // Filter by search query
            if (query.isNotEmpty) {
              final firstName =
                  member['firstName']?.toString().toLowerCase() ?? '';
              final lastName =
                  member['lastName']?.toString().toLowerCase() ?? '';
              final username =
                  member['username']?.toString().toLowerCase() ?? '';

              final fullName = '$firstName $lastName';
              return fullName.contains(query) || username.contains(query);
            }

            return true;
          }).toList();
    });
  }
}
