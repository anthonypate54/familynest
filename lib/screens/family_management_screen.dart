import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/family_service.dart';
import '../models/family.dart';
import '../widgets/gradient_background.dart';
import 'package:intl/intl.dart';
import '../controllers/bottom_navigation_controller.dart';
import '../theme/app_theme.dart';

class FamilyManagementScreen extends StatefulWidget {
  final int userId;
  final BottomNavigationController? navigationController;

  const FamilyManagementScreen({
    Key? key,
    required this.userId,
    this.navigationController,
  }) : super(key: key);

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<Family> _families = [];
  Family? _selectedFamily;
  Family? _ownedFamily;
  List<Map<String, dynamic>> _allMembers = [];
  List<Map<String, dynamic>> _filteredMembers = [];
  List<Map<String, dynamic>> _pendingInvitations = [];
  List<Map<String, dynamic>> _sentInvitations = [];
  Map<int, int> _familyPendingInviteCounts = {};
  List<Map<String, dynamic>> _upcomingBirthdays = [];
  bool _loadingBirthdays = false;
  Map<String, dynamic>? _weeklyActivity;
  bool _loadingWeeklyActivity = false;

  // Period selection state
  String _selectedPeriod = 'Wk'; // 'Wk', 'Mo', 'Yr'
  Map<String, dynamic>? _currentActivity;
  bool _loadingActivity = false;

  // Notification preferences state
  Map<String, dynamic>? _notificationPreferences;
  bool _loadingNotifications = false;

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

  Future<void> _loadPendingInvitations() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.getSentInvitations();

      debugPrint('🔍 SENT INVITATIONS DEBUG - Response: $response');

      if (response['success'] != false) {
        final List<dynamic> invitations = response['invitations'] ?? [];

        debugPrint('🔍 SENT INVITATIONS DEBUG - Raw invitations: $invitations');

        // Process invitations and count pending ones by family
        Map<int, int> pendingCounts = {};
        List<Map<String, dynamic>> sentInvitations = [];

        for (var invitation in invitations) {
          final invitationMap = invitation as Map<String, dynamic>;
          debugPrint(
            '🔍 SENT INVITATIONS DEBUG - Processing invitation: $invitationMap',
          );

          sentInvitations.add(invitationMap);

          // Count pending invitations by family
          if (invitationMap['status'] == 'PENDING') {
            final familyId = invitationMap['familyId'];
            if (familyId != null) {
              // Convert to int if it's a string or number
              int familyIdInt;
              if (familyId is String) {
                familyIdInt = int.tryParse(familyId) ?? 0;
              } else if (familyId is int) {
                familyIdInt = familyId;
              } else {
                continue; // Skip if we can't parse family ID
              }

              pendingCounts[familyIdInt] =
                  (pendingCounts[familyIdInt] ?? 0) + 1;
            }
          }
        }

        debugPrint(
          '🔍 SENT INVITATIONS DEBUG - Pending counts: $pendingCounts',
        );

        if (mounted) {
          setState(() {
            _sentInvitations = sentInvitations;
            _familyPendingInviteCounts = pendingCounts;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading pending invitations: $e');
    }
  }

  Future<void> _loadUpcomingBirthdays() async {
    final selectedFamily = _selectedFamily;
    if (selectedFamily == null) return;

    if (mounted) {
      setState(() {
        _loadingBirthdays = true;
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final birthdays = await apiService.getUpcomingBirthdays(
        selectedFamily.id,
      );

      debugPrint(
        '🎂 BIRTHDAYS DEBUG - Loaded ${birthdays.length} birthdays for family ${selectedFamily.id}',
      );

      if (mounted) {
        setState(() {
          _upcomingBirthdays = birthdays;
          _loadingBirthdays = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading upcoming birthdays: $e');
      if (mounted) {
        setState(() {
          _loadingBirthdays = false;
        });
      }
    }
  }

  Future<void> _loadWeeklyActivity() async {
    final selectedFamily = _selectedFamily;
    if (selectedFamily == null) return;

    if (mounted) {
      setState(() {
        _loadingWeeklyActivity = true;
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final activity = await apiService.getWeeklyActivity(selectedFamily.id);

      debugPrint(
        '📊 WEEKLY ACTIVITY DEBUG - Loaded activity for family ${selectedFamily.id}: $activity',
      );

      if (mounted) {
        setState(() {
          _weeklyActivity = activity;
          _loadingWeeklyActivity = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading weekly activity: $e');
      if (mounted) {
        setState(() {
          _loadingWeeklyActivity = false;
        });
      }
    }
  }

  Future<void> _loadActivity({String? period}) async {
    final selectedFamily = _selectedFamily;
    if (selectedFamily == null) return;

    final targetPeriod = period ?? _selectedPeriod;

    if (mounted) {
      setState(() {
        _loadingActivity = true;
        if (period != null) {
          _selectedPeriod = period;
        }
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      Map<String, dynamic>? activity;

      switch (targetPeriod) {
        case 'Wk':
          activity = await apiService.getWeeklyActivity(selectedFamily.id);
          break;
        case 'Mo':
          activity = await apiService.getYearlyActivity(selectedFamily.id);
          break;
        case 'Yr':
          activity = await apiService.getMultiYearActivity(selectedFamily.id);
          break;
        default:
          activity = await apiService.getWeeklyActivity(selectedFamily.id);
      }

      debugPrint(
        '📊 ACTIVITY DEBUG - Loaded $targetPeriod activity for family ${selectedFamily.id}: $activity',
      );

      if (mounted) {
        setState(() {
          _currentActivity = activity;
          _weeklyActivity = activity; // Keep for backward compatibility
          _loadingActivity = false;
          _loadingWeeklyActivity = false; // Keep for backward compatibility
        });
      }
    } catch (e) {
      debugPrint('Error loading $targetPeriod activity: $e');
      if (mounted) {
        setState(() {
          _loadingActivity = false;
          _loadingWeeklyActivity = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final familyService = FamilyService.of(context);
      final apiService = Provider.of<ApiService>(context, listen: false);

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

      // If user has no families, fetch pending invitations
      List<Map<String, dynamic>> pendingInvitations = [];
      if (families.isEmpty) {
        try {} catch (e) {
          debugPrint('Error fetching pending invitations: $e');
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
          _pendingInvitations = pendingInvitations;
        });

        // Apply initial filtering
        _filterMembers();

        // Load pending invitations count for families (only if user has families)
        if (families.isNotEmpty) {
          await _loadPendingInvitations();
        }

        // Load upcoming birthdays for selected family
        if (_selectedFamily != null) {
          await _loadUpcomingBirthdays();
        }

        // Load weekly activity for selected family
        if (_selectedFamily != null) {
          await _loadActivity();
        }
      }
    } catch (e) {
      debugPrint('Error in _loadData: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Management'),
        backgroundColor: AppTheme.getAppBarColor(context),
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

            // Only show these cards if user has families
            if (_families.isNotEmpty) ...[
              const SizedBox(height: 6),
              // Birthdays Card
              _buildBirthdaysCard(),
              const SizedBox(height: 6),
              // Activity Chart Card
              _buildWeeklyUsageCard(),
            ],
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
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
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
                    _onFamilySelected(newFamily);
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
            color: AppTheme.getAppBarColor(context),
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
                      dropdownColor: AppTheme.getAppBarColor(context),
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
            color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
            color: Theme.of(context).colorScheme.surface.withOpacity(0.1),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
                  activeColor: Colors.white,
                  activeTrackColor: AppTheme.getSwitchColor(context),
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
      // Check if user has pending invitations
      if (_pendingInvitations.isNotEmpty) {
        final invitation = _pendingInvitations.first;
        final inviterName = invitation['senderName'] ?? 'Someone';
        final familyName = invitation['familyName'] ?? 'Unknown Family';

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.mail_outline, size: 32, color: Colors.blue[600]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'You have been invited!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Join the "$familyName" family',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Invited by $inviterName',
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
                const SizedBox(height: 16),

                // Accept/Decline buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _acceptInvitation(invitation),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Accept'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _declineInvitation(invitation),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[400],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Secondary option - Create own family
                Center(
                  child: Column(
                    children: [
                      Text(
                        'Or you can always create a family of your own',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _showCreateFamilyDialog,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        child: const Text(
                          'Create Family',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        // No pending invitations - show create family option
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.family_restroom,
                  size: 48,
                  color: Colors.orange,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Create Your Family',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start connecting with your family members',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _showCreateFamilyDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Create Family'),
                ),
              ],
            ),
          ),
        );
      }
    }

    final isOwner = selectedFamily.isOwned;
    final createdAt = selectedFamily.createdAt;
    final memberCount = selectedFamily.members.length;

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
                    'Created on ${DateFormat('MMM dd, yyyy').format(createdAt)}',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Total members info
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.blue[600]),
                      const SizedBox(width: 4),
                      Text(
                        '$memberCount Total Members',
                        style: TextStyle(
                          color: Colors.blue[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Pending invites info - only show if user is owner AND has pending invites
                  if (isOwner &&
                      (_familyPendingInviteCounts[selectedFamily.id] ?? 0) >
                          0) ...[
                    InkWell(
                      onTap: () => _showPendingInvitesDialog(selectedFamily),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.mail_outline,
                            size: 16,
                            color: Colors.orange[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_familyPendingInviteCounts[selectedFamily.id] ?? 0} Pending Invites',
                            style: TextStyle(
                              color: Colors.orange[600],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: Colors.orange[600],
                          ),
                        ],
                      ),
                    ),
                  ],
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
                    Builder(
                      builder: (context) {
                        // Find the owner from members list
                        final owner =
                            selectedFamily.members
                                .where((member) => member.isOwner)
                                .firstOrNull;

                        if (owner != null) {
                          return Text(
                            'DM your family owner "${owner.displayName}" to invite new members.',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          );
                        } else {
                          return Text(
                            'Contact family admin to invite new members',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 10,
                            ),
                            textAlign: TextAlign.center,
                          );
                        }
                      },
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
                const Spacer(),
                if (_loadingBirthdays)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.orange[600]!,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_upcomingBirthdays.isEmpty && !_loadingBirthdays)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.celebration, color: Colors.grey[400], size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'No birthdays in the next 7 days',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...(_upcomingBirthdays.map((birthday) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _buildBirthdayItem(
                    '${birthday['firstName']} ${birthday['lastName']}',
                    birthday['description'] ?? 'Unknown',
                    birthday['daysUntil'] ?? 0,
                  ),
                );
              }).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdayItem(String name, String description, int daysUntil) {
    Color dotColor;
    if (daysUntil == 0) {
      dotColor = Colors.red[400]!; // Today - red
    } else if (daysUntil == 1) {
      dotColor = Colors.orange[400]!; // Tomorrow - orange
    } else {
      dotColor = Colors.orange[400]!; // Future - orange
    }

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$name - $description',
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  void _onFamilySelected(Family? newFamily) {
    if (newFamily != null && newFamily != _selectedFamily) {
      setState(() {
        _selectedFamily = newFamily;
      });
      _filterMembers();
      _loadUpcomingBirthdays(); // Load birthdays for the new family
      _loadActivity(); // Load activity for the new family
    }
  }

  Widget _buildWeeklyUsageCard() {
    // Use current activity data based on selected period
    final activityData = _currentActivity ?? _weeklyActivity;

    // Extract data based on selected period
    List<dynamic> timeActivity;
    int periodTotal;
    String periodLabel;
    List<double> defaultChartData;
    List<String> defaultLabels;

    switch (_selectedPeriod) {
      case 'Mo':
        timeActivity = activityData?['monthlyActivity'] as List<dynamic>? ?? [];
        periodTotal = activityData?['yearlyTotal'] as int? ?? 0;
        periodLabel = 'past year';
        defaultChartData = List.filled(12, 0.0); // 12 months
        defaultLabels = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        break;
      case 'Yr':
        timeActivity = activityData?['yearlyActivity'] as List<dynamic>? ?? [];
        periodTotal = activityData?['allYearsTotal'] as int? ?? 0;
        periodLabel = 'past years';
        defaultChartData = List.filled(5, 0.0); // 5 years
        defaultLabels = [
          '2020',
          '2021',
          '2022',
          '2023',
          '2024',
        ]; // Will be dynamic from data
        break;
      default: // 'Wk'
        timeActivity = activityData?['dailyActivity'] as List<dynamic>? ?? [];
        periodTotal = activityData?['weeklyTotal'] as int? ?? 0;
        periodLabel = 'week';
        defaultChartData = List.filled(7, 0.0); // 7 days
        defaultLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    }

    final totalMessages = activityData?['totalMessages'] as int? ?? 0;

    // Convert activity to chart data
    final chartData =
        timeActivity.map((item) {
          return (item['messageCount'] as num).toDouble();
        }).toList();

    // Get labels from the data
    final labels =
        timeActivity.map((item) {
          // Use the appropriate label for each period
          switch (_selectedPeriod) {
            case 'Mo':
              return item['monthLabel'] as String? ?? 'X';
            case 'Yr':
              return item['yearLabel'] as String? ?? 'X';
            default: // 'Wk'
              return item['dayLabel'] as String? ?? 'X';
          }
        }).toList();

    // Use actual data if available, otherwise use defaults
    final displayChartData =
        chartData.isNotEmpty ? chartData : defaultChartData;
    final displayLabels = labels.isNotEmpty ? labels : defaultLabels;

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
                Row(
                  children: [
                    Icon(Icons.analytics, color: Colors.blue[600], size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'Activity Chart',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (_loadingActivity || _loadingWeeklyActivity)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.blue[600]!,
                          ),
                        ),
                      )
                    else ...[
                      _buildPeriodButton('Wk', _selectedPeriod == 'Wk'),
                      const SizedBox(width: 4),
                      _buildPeriodButton('Mo', _selectedPeriod == 'Mo'),
                      const SizedBox(width: 4),
                      _buildPeriodButton('Yr', _selectedPeriod == 'Yr'),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (activityData == null &&
                !_loadingActivity &&
                !_loadingWeeklyActivity)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No activity data available',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else ...[
              // Y-axis labels and chart area
              Row(
                children: [
                  // Y-axis labels - calculate max value from data
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildYAxisLabel(
                        _getMaxValue(displayChartData).toString(),
                      ),
                      _buildYAxisLabel(
                        (_getMaxValue(displayChartData) * 0.8)
                            .round()
                            .toString(),
                      ),
                      _buildYAxisLabel(
                        (_getMaxValue(displayChartData) * 0.6)
                            .round()
                            .toString(),
                      ),
                      _buildYAxisLabel(
                        (_getMaxValue(displayChartData) * 0.4)
                            .round()
                            .toString(),
                      ),
                      _buildYAxisLabel(
                        (_getMaxValue(displayChartData) * 0.2)
                            .round()
                            .toString(),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),

                  // Chart area
                  Expanded(
                    child: CustomPaint(
                      painter: CompactLineChartPainter(
                        dataPoints: displayChartData,
                        maxValue: _getMaxValue(displayChartData).toDouble(),
                      ),
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
                    displayLabels
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
                    'Messages this $periodLabel: $periodTotal',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    'Total messages: $totalMessages',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  int _getMaxValue(List<double> data) {
    if (data.isEmpty) return 25;
    final max = data.reduce((a, b) => a > b ? a : b);
    // Return a nice round number that's at least as big as the max
    if (max <= 5) return 5;
    if (max <= 10) return 10;
    if (max <= 15) return 15;
    if (max <= 20) return 20;
    if (max <= 25) return 25;
    if (max <= 50) return 50;
    if (max <= 100) return 100;
    return ((max / 50).ceil() * 50).toInt(); // Round up to nearest 50
  }

  Widget _buildPeriodButton(String period, bool isSelected) {
    return GestureDetector(
      onTap: () {
        if (!isSelected && !_loadingActivity) {
          _loadActivity(period: period);
        }
      },
      child: Container(
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
      ),
    );
  }

  Widget _buildYAxisLabel(String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        value,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
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

  // Helper method to format birth date like the profile screen
  String _formatBirthDateFromMap(dynamic birthDate) {
    if (birthDate == null) return '';

    try {
      // If it's already a string in a readable format, convert to user-friendly format
      if (birthDate is String) {
        final parsedDate = DateTime.tryParse(birthDate);
        if (parsedDate != null) {
          return DateFormat('MMMM dd, yyyy').format(parsedDate);
        }
        return birthDate;
      }

      // If it's an integer timestamp, convert it to a date string
      if (birthDate is int) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate);
        return DateFormat('MMMM dd, yyyy').format(date);
      }

      // If it's a double, convert to int first
      if (birthDate is double) {
        final date = DateTime.fromMillisecondsSinceEpoch(birthDate.toInt());
        return DateFormat('MMMM dd, yyyy').format(date);
      }

      return '';
    } catch (e) {
      debugPrint('Error formatting birth date: $e');
      return '';
    }
  }

  // Helper method to format phone number
  String _formatPhoneNumber(String? phoneNumber) {
    debugPrint('🔧 PHONE FORMAT INPUT: "$phoneNumber"');

    if (phoneNumber == null || phoneNumber.isEmpty) {
      debugPrint('🔧 PHONE FORMAT RESULT: empty input');
      return '';
    }

    // Remove any existing formatting
    String cleaned = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
    debugPrint(
      '🔧 PHONE FORMAT CLEANED: "$cleaned" (length: ${cleaned.length})',
    );

    String result = '';

    // Format based on cleaned digits
    if (cleaned.length == 10) {
      // Format as (123) 456-7890
      result =
          '(${cleaned.substring(0, 3)}) ${cleaned.substring(3, 6)}-${cleaned.substring(6)}';
    } else if (cleaned.length == 11 && cleaned.startsWith('1')) {
      // Format as +1 (123) 456-7890
      String phoneDigits = cleaned.substring(1);
      result =
          '+1 (${phoneDigits.substring(0, 3)}) ${phoneDigits.substring(3, 6)}-${phoneDigits.substring(6)}';
    } else if (cleaned.length == 7) {
      // Format as 123-4567
      result = '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
    } else if (cleaned.length > 0) {
      // For other lengths, try to apply some formatting
      if (cleaned.length <= 3) {
        result = cleaned;
      } else if (cleaned.length <= 6) {
        result = '${cleaned.substring(0, 3)}-${cleaned.substring(3)}';
      } else {
        // Fallback - just return the original
        result = phoneNumber;
      }
    } else {
      // Return original if no formatting applied
      result = phoneNumber;
    }

    debugPrint('🔧 PHONE FORMAT RESULT: "$result"');
    return result;
  }

  void _showDemographicsDialog(Map<String, dynamic> userDetails) {
    // Debug print to see what data we're getting
    debugPrint('Demographics data: $userDetails');

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              '${userDetails['firstName'] ?? ''} ${userDetails['lastName'] ?? ''}'
                  .trim(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            content: Container(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Basic Information Section
                    _buildDemographicsSection('Basic Information', [
                      if (userDetails['username'] != null)
                        _buildDemographicsItem(
                          'Username',
                          '@${userDetails['username']}',
                          Icons.person,
                        ),
                      if (userDetails['email'] != null)
                        _buildDemographicsItem(
                          'Email',
                          userDetails['email'],
                          Icons.email,
                        ),
                    ]),

                    // Contact Information Section
                    _buildDemographicsSection('Contact Information', [
                      if (userDetails['phoneNumber'] != null &&
                          userDetails['phoneNumber'].toString().isNotEmpty)
                        _buildDemographicsItem(
                          'Phone',
                          _formatPhoneNumber(userDetails['phoneNumber']),
                          Icons.phone,
                        ),
                    ]),

                    // Address Section - Check for any address-related fields
                    _buildDemographicsSection('Address', [
                      if (_hasAddress(userDetails))
                        _buildDemographicsItem(
                          'Street Address',
                          _getAddress(userDetails),
                          Icons.home,
                        ),
                      if (_hasLocation(userDetails))
                        _buildDemographicsItem(
                          'Location',
                          _buildLocationString(userDetails),
                          Icons.location_on,
                        ),
                      if (_hasCountry(userDetails))
                        _buildDemographicsItem(
                          'Country',
                          userDetails['country'],
                          Icons.public,
                        ),
                    ]),

                    // Personal Information Section
                    _buildDemographicsSection('Personal Information', [
                      if (userDetails['birthDate'] != null)
                        _buildDemographicsItem(
                          'Birthday',
                          _formatBirthDateFromMap(userDetails['birthDate']),
                          Icons.cake,
                        ),
                      if (_hasBio(userDetails))
                        _buildDemographicsItem(
                          'Bio',
                          userDetails['bio'],
                          Icons.info_outline,
                        ),
                    ]),

                    // Show message if no demographic data available
                    if (_hasNoDemographicData(userDetails))
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 48,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 8),
                            Text(
                              'No additional information available',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
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

  // Helper methods for checking field existence and getting values
  bool _hasAddress(Map<String, dynamic> userDetails) {
    final address = userDetails['address'];
    return address != null && address.toString().trim().isNotEmpty;
  }

  String _getAddress(Map<String, dynamic> userDetails) {
    return userDetails['address']?.toString() ?? '';
  }

  bool _hasLocation(Map<String, dynamic> userDetails) {
    return (userDetails['city'] != null &&
            userDetails['city'].toString().trim().isNotEmpty) ||
        (userDetails['state'] != null &&
            userDetails['state'].toString().trim().isNotEmpty) ||
        (userDetails['zipCode'] != null &&
            userDetails['zipCode'].toString().trim().isNotEmpty);
  }

  bool _hasCountry(Map<String, dynamic> userDetails) {
    final country = userDetails['country'];
    return country != null && country.toString().trim().isNotEmpty;
  }

  bool _hasBio(Map<String, dynamic> userDetails) {
    final bio = userDetails['bio'];
    return bio != null && bio.toString().trim().isNotEmpty;
  }

  // Helper method to build demographic sections
  Widget _buildDemographicsSection(String title, List<Widget> items) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
        const SizedBox(height: 8),
        ...items,
        const SizedBox(height: 16),
      ],
    );
  }

  // Helper method to build individual demographic items
  Widget _buildDemographicsItem(String label, String value, IconData icon) {
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to build location string
  String _buildLocationString(Map<String, dynamic> userDetails) {
    List<String> locationParts = [];

    if (userDetails['city'] != null &&
        userDetails['city'].toString().isNotEmpty) {
      locationParts.add(userDetails['city']);
    }
    if (userDetails['state'] != null &&
        userDetails['state'].toString().isNotEmpty) {
      locationParts.add(userDetails['state']);
    }
    if (userDetails['zipCode'] != null &&
        userDetails['zipCode'].toString().isNotEmpty) {
      locationParts.add(userDetails['zipCode']);
    }

    return locationParts.join(', ');
  }

  // Helper method to check if there's no demographic data
  bool _hasNoDemographicData(Map<String, dynamic> userDetails) {
    final fieldsToCheck = [
      'phoneNumber',
      'address',
      'city',
      'state',
      'zipCode',
      'country',
      'birthDate',
      'bio',
    ];

    for (String field in fieldsToCheck) {
      final value = userDetails[field];
      if (value != null && value.toString().isNotEmpty) {
        return false;
      }
    }
    return true;
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
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an email address')),
      );
      return;
    }

    try {
      final selectedFamily = _selectedFamily;
      if (selectedFamily == null || !selectedFamily.isOwned) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Must create family before invite')),
        );
        return;
      }

      await Provider.of<ApiService>(
        context,
        listen: false,
      ).inviteUserToFamily(selectedFamily.id, email);

      // Refresh pending invitation counts
      await _loadPendingInvitations();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invitation sent to $email')));
        _inviteEmailController.clear();

        // Update the UI to show the new pending count
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error sending invitation: $e')));
      }
    }
  }

  Future<void> _acceptInvitation(Map<String, dynamic> invitation) async {
    try {
      final invitationId = invitation['id'];
      if (invitationId == null) {
        throw Exception('Invalid invitation ID');
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.respondToFamilyInvitation(invitationId, true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invitation accepted! Welcome to the family!'),
          ),
        );

        // Reload data to show the new family
        await _loadData();

        // Update navigation controller's invitation count
        if (widget.navigationController != null) {
          try {
            final invitations = await apiService.getInvitations();
            final pendingCount =
                invitations
                    .where(
                      (inv) =>
                          inv['status'] != null && inv['status'] == 'PENDING',
                    )
                    .length;
            widget.navigationController!.setPendingInvitationsCount(
              pendingCount,
            );
          } catch (e) {
            debugPrint('Error updating invitation count: $e');
          }
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

  Future<void> _declineInvitation(Map<String, dynamic> invitation) async {
    try {
      final invitationId = invitation['id'];
      if (invitationId == null) {
        throw Exception('Invalid invitation ID');
      }

      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.respondToFamilyInvitation(invitationId, false);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invitation declined')));

        // Reload data to remove the declined invitation
        await _loadData();

        // Update navigation controller's invitation count
        if (widget.navigationController != null) {
          try {
            final invitations = await apiService.getInvitations();
            final pendingCount =
                invitations
                    .where(
                      (inv) =>
                          inv['status'] != null && inv['status'] == 'PENDING',
                    )
                    .length;
            widget.navigationController!.setPendingInvitationsCount(
              pendingCount,
            );
          } catch (e) {
            debugPrint('Error updating invitation count: $e');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error declining invitation: $e')),
        );
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
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withOpacity(0.7),
                        fontSize: 14,
                      ),
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

  void _showPendingInvitesDialog(Family? family) {
    if (family == null) return;

    final pendingInvites =
        _sentInvitations.where((inv) {
          final invFamilyId = inv['familyId'];
          final invStatus = inv['status'];
          final familyMatches =
              (invFamilyId == family.id) ||
              (invFamilyId.toString() == family.id.toString());
          final statusMatches = invStatus == 'PENDING';

          return familyMatches && statusMatches;
        }).toList();

    if (pendingInvites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pending invitations for this family.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Pending Invitations for ${family.name}'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: pendingInvites.length,
                itemBuilder: (context, index) {
                  final invite = pendingInvites[index];
                  final email = invite['email'];
                  final createdAt = invite['createdAt'];
                  final expiresAt = invite['expiresAt'];

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(
                        Icons.mail_outline,
                        color: Colors.orange,
                      ),
                      title: Text('Invitation to $email'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status: Pending'),
                          Text(
                            'Sent: ${createdAt?.substring(0, 10) ?? 'Unknown'}',
                          ),
                          Text(
                            'Expires: ${expiresAt?.substring(0, 10) ?? 'Unknown'}',
                          ),
                        ],
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'cancel') {
                            _cancelInvitation(invite);
                          } else if (value == 'resend') {
                            _resendInvitation(invite);
                          }
                        },
                        itemBuilder:
                            (context) => [
                              const PopupMenuItem(
                                value: 'resend',
                                child: Text('Resend'),
                              ),
                              const PopupMenuItem(
                                value: 'cancel',
                                child: Text('Cancel'),
                              ),
                            ],
                      ),
                    ),
                  );
                },
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

  void _cancelInvitation(Map<String, dynamic> invitation) {
    Navigator.pop(context);
    // TODO: Implement cancel invitation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cancel invitation feature coming soon!')),
    );
  }

  void _resendInvitation(Map<String, dynamic> invitation) {
    Navigator.pop(context);
    // TODO: Implement resend invitation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Resend invitation feature coming soon!')),
    );
  }
}

class CompactLineChartPainter extends CustomPainter {
  final List<double> dataPoints;
  final double maxValue;

  CompactLineChartPainter({required this.dataPoints, required this.maxValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.blue
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke;

    final path = Path();

    // Use passed-in data or default to empty chart
    final points =
        dataPoints.isNotEmpty
            ? dataPoints
            : [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
    final max = maxValue > 0 ? maxValue : 25.0;

    // Add some padding from top and bottom
    final paddingTop = size.height * 0.1;
    final paddingBottom = size.height * 0.1;
    final chartHeight = size.height - paddingTop - paddingBottom;

    // Draw horizontal grid lines (y-axis: 0, 20%, 40%, 60%, 80%, 100% of max)
    final gridPaint =
        Paint()
          ..color = Colors.grey.withOpacity(0.3)
          ..strokeWidth = 0.5;

    for (int i = 0; i <= 5; i++) {
      final value = (i / 5.0) * max; // 0%, 20%, 40%, 60%, 80%, 100% of max
      final y = paddingTop + (1.0 - (value / max)) * chartHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Calculate and draw the data line
    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = paddingTop + (1.0 - (points[i] / max)) * chartHeight;

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

    for (int i = 0; i < points.length; i++) {
      final x = (i / (points.length - 1)) * size.width;
      final y = paddingTop + (1.0 - (points[i] / max)) * chartHeight;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is CompactLineChartPainter &&
        (oldDelegate.dataPoints != dataPoints ||
            oldDelegate.maxValue != maxValue);
  }
}
