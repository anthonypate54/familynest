import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/family_service.dart';
import '../models/family.dart';
import '../widgets/gradient_background.dart';

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
  List<Family> _families = [];
  Family? _selectedFamily;
  Family? _ownedFamily;
  bool _isLoading = true;
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
    setState(() => _isLoading = true);
    try {
      final familyService = FamilyService.of(context);

      final families = await familyService.loadUserFamilies(widget.userId);

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
          _selectedFamily = families.isNotEmpty ? families.first : null;
          _ownedFamily =
              families.where((f) => f.isOwned).isNotEmpty
                  ? families.firstWhere((f) => f.isOwned)
                  : null;
          _allMembers = allMembers;
          _filteredMembers = allMembers;
          _isLoading = false;
        });

        // Apply initial filtering
        _filterMembers();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Management'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: GradientBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Container(
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    // Tab bar
                    TabBar(
                      controller: _tabController,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      indicatorColor: Colors.white,
                      tabs: const [
                        Tab(text: 'Family'),
                        Tab(text: 'Members'),
                        Tab(text: 'Settings'),
                      ],
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
          },
        ),
      ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
        child: Column(
          children: [
            // Family selector dropdown (for all families)
            if (_families.isNotEmpty) ...[
              _buildFamilySelector(),
              const SizedBox(height: 8),
            ],

            // Family Overview Card with complex layout
            _buildFamilyOverviewCard(),
            const SizedBox(height: 6),

            // Birthdays Card
            _buildBirthdaysCard(),
            const SizedBox(height: 6),

            // Activity Chart Card
            _buildWeeklyUsageCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildFamilySelector() {
    final selectedFamily = _selectedFamily;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.family_restroom, color: Colors.blue, size: 20),
            const SizedBox(width: 12),
            const Text(
              'Viewing:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Family>(
                  value: selectedFamily,
                  isExpanded: true,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  items:
                      _families.map((family) {
                        String roleLabel = family.isOwned ? 'Owner' : 'Member';
                        return DropdownMenuItem<Family>(
                          value: family,
                          child: Text('${family.name} ($roleLabel)'),
                        );
                      }).toList(),
                  onChanged: (Family? newFamily) {
                    if (newFamily != null) {
                      setState(() {
                        _selectedFamily = newFamily;
                      });
                    }
                  },
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

  Widget _buildFamilyOverviewCard() {
    final selectedFamily = _selectedFamily;

    if (selectedFamily == null) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Left column - Create Family
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.family_restroom,
                      size: 32,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Create Your Family',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start connecting with your family members',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Right column - Empty for non-admin
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      size: 32,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No Admin Functions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create family first',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isOwner = selectedFamily.isOwned;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Left column - Family Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.family_restroom,
                        size: 32,
                        color: isOwner ? Colors.blue : Colors.green,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          selectedFamily.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Created January 2024',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  // Total members info
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 4),
                      Text(
                        '3 Total Members',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Pending invites info
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mail_outline,
                        size: 16,
                        color: Colors.orange[600],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '2 Pending Invites',
                        style: TextStyle(
                          color: Colors.orange[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Right column - Admin Functions or Member View
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isOwner) ...[
                    // Owner view - Admin functions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          size: 20,
                          color: Colors.blue[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Family Admin',
                          style: TextStyle(
                            color: Colors.blue[600],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          _showInviteDialog();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add, size: 16),
                            SizedBox(width: 4),
                            Text(
                              'Invite Members',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Member view
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person, size: 20, color: Colors.green[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Family Member',
                          style: TextStyle(
                            color: Colors.green[600],
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Contact family admin to invite new members',
                      style: TextStyle(color: Colors.grey[600], fontSize: 10),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdaysCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cake, color: Colors.orange[600], size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Upcoming Birthdays',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildBirthdayItem('Amy Johnson', 'Tue Jun 6'),
            const SizedBox(height: 6),
            _buildBirthdayItem('Mike Stevens', 'Fri Jun 16'),
            const SizedBox(height: 6),
            _buildBirthdayItem('Sarah Williams', 'Wed Jun 28'),
            const SizedBox(height: 6),
            _buildBirthdayItem('David Chen', 'Mon Jul 3'),
            const SizedBox(height: 6),
            _buildBirthdayItem('Emily Rodriguez', 'Thu Jul 8'),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdayItem(String name, String date) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.orange[400],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('$name - $date', style: const TextStyle(fontSize: 14)),
        ),
      ],
    );
  }

  Widget _buildWeeklyUsageCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Activity Chart',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    _buildPeriodButton('Wk', true),
                    const SizedBox(width: 4),
                    _buildPeriodButton('Mo', false),
                    const SizedBox(width: 4),
                    _buildPeriodButton('Yr', false),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Y-axis labels and chart area
            Row(
              children: [
                // Y-axis labels
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildYAxisLabel('25'),
                    _buildYAxisLabel('20'),
                    _buildYAxisLabel('15'),
                    _buildYAxisLabel('10'),
                    _buildYAxisLabel('5'),
                  ],
                ),
                const SizedBox(width: 8),

                // Chart area
                Expanded(
                  child: CustomPaint(
                    painter: CompactLineChartPainter(),
                    child: Container(height: 49),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Day labels
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children:
                  ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                      .map(
                        (day) => Text(
                          day,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      )
                      .toList(),
            ),

            const SizedBox(height: 12),

            // Message counts
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Messages this week: 247',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                Text(
                  'Total messages: 1,234',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodButton(String period, bool isSelected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.green : Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        period,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : Colors.grey[600],
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildYAxisLabel(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        value,
        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
}

class CompactLineChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    final path = Path();

    // Sample data points (messages per day) - can be made dynamic later
    final dataPoints = [12.0, 8.0, 15.0, 20.0, 18.0, 25.0, 22.0];
    final maxValue = 25.0;

    // Add some padding from top and bottom
    final paddingTop = size.height * 0.1;
    final paddingBottom = size.height * 0.1;
    final chartHeight = size.height - paddingTop - paddingBottom;

    // Draw horizontal grid lines (y-axis: 0, 5, 10, 15, 20, 25)
    final gridPaint =
        Paint()
          ..color = Colors.grey.withOpacity(0.3)
          ..strokeWidth = 0.5;

    for (int i = 0; i <= 5; i++) {
      final value = i * 5.0; // 0, 5, 10, 15, 20, 25
      final y = paddingTop + (1.0 - (value / maxValue)) * chartHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Calculate and draw the data line
    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final y = paddingTop + (1.0 - (dataPoints[i] / maxValue)) * chartHeight;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);

    // Draw dots at data points
    final dotPaint =
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;

    for (int i = 0; i < dataPoints.length; i++) {
      final x = (i / (dataPoints.length - 1)) * size.width;
      final y = paddingTop + (1.0 - (dataPoints[i] / maxValue)) * chartHeight;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
