import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/service_provider.dart';
import '../services/invitation_service.dart';
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

  // Services
  late InvitationService _invitationService;

  // Add this to the state class variables
  List<Map<String, dynamic>> _messagePreferences = [];
  bool _loadingPreferences = false;

  // Add these state variables for member-level message preferences
  List<Map<String, dynamic>> _memberMessagePreferences = [];
  bool _loadingMemberPreferences = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    // Initialize the invitation service
    _invitationService = ServiceProvider().invitationService;
    _loadData();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
    _loadUserData();
    _loadUserPreferences();
    _loadMessagePreferences();
    _loadMemberMessagePreferences();
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
        _loadMessagePreferences(),
        _loadMemberMessagePreferences(),
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
    // Get the service just when needed
    final invitationService = ServiceProvider().invitationService;

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

  // Dialog to show family members
  void _showFamilyMembersDialog(
    Map<String, dynamic> family,
    List<Map<String, dynamic>> members,
  ) {
    // Extract and validate familyId
    final familyId = family['familyId'] as int?;
    if (familyId == null) {
      debugPrint('Warning: Family ID is null in _showFamilyMembersDialog');
      return; // Exit early if familyId is null
    }

    // Debug log the members data
    debugPrint('Family members data: $members');

    if (members.isEmpty) {
      debugPrint('No family members found for familyId: $familyId');
    }

    // Create a map to track member preference states during dialog interaction
    Map<int, bool> memberPreferences = {};
    for (final member in members) {
      final memberId = member['userId'] as int?;
      if (memberId != null) {
        // Check if preference already exists
        bool preferenceExists = false;
        bool receiveMessages = true; // Default value

        // Look for existing preference
        for (var pref in _memberMessagePreferences) {
          if (pref['familyId'] == familyId &&
              pref['memberUserId'] == memberId) {
            preferenceExists = true;
            receiveMessages = pref['receiveMessages'] ?? true;
            break;
          }
        }

        // Store the current preference state
        memberPreferences[memberId] = receiveMessages;

        // If not, add a default preference with receiveMessages = true
        if (!preferenceExists && memberId != widget.userId) {
          debugPrint(
            'Initializing default preference for member $memberId with receiveMessages=true',
          );
          _memberMessagePreferences.add({
            'familyId': familyId,
            'memberUserId': memberId,
            'receiveMessages': true,
          });
        }
      }
    }

    // Show the dialog with its own StatefulBuilder for managing dialog state
    showDialog(
      context: context,
      builder: (buildContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                '${family['familyName'] ?? 'Unknown Family'} Family Members',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Add a header with feature explanation
                    Container(
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      child: Column(
                        children: const [
                          Icon(
                            Icons.notifications_active,
                            color: Colors.blue,
                            size: 20,
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Message Preferences',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Control which family members you receive messages from by checking or unchecking the box next to their name.',
                            style: TextStyle(fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                    const SizedBox(height: 8),

                    if (members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Center(
                          child: Column(
                            children: const [
                              Icon(
                                Icons.people_alt,
                                color: Colors.grey,
                                size: 40,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'No members found in this family',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: members.length,
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final memberId = member['userId'] as int?;
                            final isCurrentUser = memberId == widget.userId;

                            // Debug log the member data
                            debugPrint('Member data: $member');

                            if (memberId == null) {
                              debugPrint('Warning: Member has null userId');
                              return const SizedBox.shrink();
                            }

                            // Get current state from memberPreferences map
                            final receiveMessages =
                                memberPreferences[memberId] ?? true;

                            return GestureDetector(
                              // Add onTap for entire row tapping
                              onTap:
                                  isCurrentUser
                                      ? null
                                      : () {
                                        // Toggle the state on tap
                                        final newValue = !receiveMessages;

                                        // Update local dialog state
                                        setDialogState(() {
                                          memberPreferences[memberId] =
                                              newValue;
                                        });

                                        // Also update backend and parent state
                                        _updateMemberMessagePreference(
                                          familyId,
                                          memberId,
                                          newValue,
                                        );
                                      },
                              child: CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                value: receiveMessages,
                                onChanged:
                                    isCurrentUser
                                        ? null // Can't toggle your own messages
                                        : (bool? newValue) {
                                          if (newValue != null) {
                                            // Update local dialog state
                                            setDialogState(() {
                                              memberPreferences[memberId] =
                                                  newValue;
                                            });

                                            // Also update backend and parent state
                                            _updateMemberMessagePreference(
                                              familyId,
                                              memberId,
                                              newValue,
                                            );
                                          }
                                        },
                                secondary: CircleAvatar(
                                  radius: 20,
                                  backgroundColor:
                                      isCurrentUser
                                          ? Colors.blue.shade100
                                          : Colors.green.shade100,
                                  child: Text(
                                    (() {
                                      // Get first letter of first name
                                      String firstLetter = 'U'; // Default
                                      if (member.containsKey(
                                            'memberFirstName',
                                          ) &&
                                          member['memberFirstName'] != null &&
                                          member['memberFirstName']
                                              .toString()
                                              .isNotEmpty) {
                                        firstLetter =
                                            member['memberFirstName']
                                                .toString()[0];
                                      }
                                      return firstLetter;
                                    })(),
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
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        (() {
                                          // Debug - print all keys in member object
                                          debugPrint(
                                            'Member object keys: ${member.keys.join(", ")}',
                                          );

                                          // Try to detect if user is a family owner
                                          bool isOwner = false;

                                          // Use isOwner field from API if available
                                          if (member.containsKey('isOwner')) {
                                            isOwner = member['isOwner'] == true;
                                            debugPrint(
                                              'Using isOwner field from API: $isOwner',
                                            );
                                          } else if (member.containsKey(
                                            'isowner',
                                          )) {
                                            isOwner = member['isowner'] == true;
                                            debugPrint(
                                              'Using isowner field from API: $isOwner',
                                            );
                                          }

                                          // If user owns a family, show family name
                                          if (isOwner) {
                                            // Try to get owned family name from API if available
                                            String? ownedFamilyName;
                                            if (member.containsKey(
                                              'ownedFamilyName',
                                            )) {
                                              ownedFamilyName =
                                                  member['ownedFamilyName']
                                                      ?.toString();
                                            } else if (member.containsKey(
                                              'ownedfamilyname',
                                            )) {
                                              ownedFamilyName =
                                                  member['ownedfamilyname']
                                                      ?.toString();
                                            }

                                            // If we have the family name, use it
                                            if (ownedFamilyName != null &&
                                                ownedFamilyName.isNotEmpty) {
                                              debugPrint(
                                                'Showing owned family name: $ownedFamilyName',
                                              );
                                              return ownedFamilyName;
                                            }
                                          }

                                          // For non-owners, show first and last name
                                          String firstName =
                                              member['firstName'] ??
                                              member['memberFirstName'] ??
                                              'Unknown';
                                          String lastName =
                                              member['lastName'] ??
                                              member['memberLastName'] ??
                                              '';
                                          String fullName =
                                              '$firstName $lastName';
                                          debugPrint(
                                            'Showing full name: $fullName',
                                          );
                                          return fullName;
                                        })(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color:
                                              isCurrentUser
                                                  ? Colors.blue.shade700
                                                  : null,
                                        ),
                                      ),
                                    ),

                                    // Family ownership icon
                                    if (member.containsKey('isOwner') &&
                                        member['isOwner'] == true)
                                      Tooltip(
                                        message: 'Family Owner',
                                        child: Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8.0,
                                          ),
                                          child: Icon(
                                            Icons.home,
                                            color: Colors.amber,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  isCurrentUser
                                      ? 'This is you'
                                      : member['username'] ??
                                          member['memberUsername'] ??
                                          'No username',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                activeColor:
                                    Theme.of(context).colorScheme.primary,
                                checkColor: Colors.white,
                              ),
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
            );
          },
        );
      },
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
        setState(() => _isLoading = false);
        return;
      }

      // Proceed with family creation - user can be member of other families
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
            'Server error: This API needs to be updated to support multiple families.';
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
                        userRole: _userData?['role'],
                      ),
                ),
              );
            },
            tooltip: 'View and edit your profile settings',
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigation(
        currentIndex: 2, // Family management tab
        apiService: widget.apiService,
        userId: widget.userId,
        controller: widget.navigationController ?? BottomNavigationController(),
        pendingInvitationsCount:
            _invitations.where((inv) => inv['status'] == 'PENDING').length,
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
      debugPrint(
        'Viewing members for family: ${family['familyName']} (ID: ${family['familyId']})',
      );

      // Load family members directly from API
      final members = await widget.apiService.getFamilyMembers(widget.userId);
      debugPrint('Loaded ${members.length} family members from API');

      // Print the member details for debugging
      debugPrint('DETAILED MEMBER DATA:');
      for (var member in members) {
        debugPrint(
          'Member: ${member['firstName']} ${member['lastName']} (ID: ${member['userId']}) - familyName: ${member['familyName']}',
        );
        debugPrint('Full member data: $member');
      }

      // Refresh member message preferences
      await _loadMemberMessagePreferences();
      debugPrint(
        'Loaded ${_memberMessagePreferences.length} member message preferences',
      );

      if (!mounted) return;

      // Show the members dialog
      _showFamilyMembersDialog(family, members);
    } catch (e) {
      debugPrint('Error loading family members: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading family members: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                if (isOwned)
                  IconButton(
                    icon: const Icon(Icons.edit, size: 16),
                    tooltip: 'Edit family name',
                    onPressed: () => _showEditFamilyNameDialog(family),
                  ),
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
      await widget.apiService.updateFamilyDetails(familyId, newName);
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
      final preferences = await widget.apiService.getMessagePreferences(
        widget.userId,
      );

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

  // Add this method to update message preference for a family
  Future<void> _updateMessagePreference(
    int familyId,
    bool receiveMessages,
  ) async {
    try {
      await widget.apiService.updateMessagePreference(
        widget.userId,
        familyId,
        receiveMessages,
      );

      // Update local state
      setState(() {
        final index = _messagePreferences.indexWhere(
          (p) => p['familyId'] == familyId,
        );
        if (index >= 0) {
          _messagePreferences[index]['receiveMessages'] = receiveMessages;
        }
      });

      if (!receiveMessages) {
        // Show feedback to user when they mute a family
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You won\'t receive messages from this family'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating message preference: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update preference: $e')),
      );
    }
  }

  // Add this method to load member message preferences
  Future<void> _loadMemberMessagePreferences() async {
    setState(() => _loadingMemberPreferences = true);

    try {
      final preferences = await widget.apiService.getMemberMessagePreferences(
        widget.userId,
      );

      if (mounted) {
        setState(() {
          _memberMessagePreferences = preferences;
          _loadingMemberPreferences = false;

          // Log the loaded preferences
          debugPrint(
            'Loaded ${_memberMessagePreferences.length} member preferences:',
          );
          for (final pref in _memberMessagePreferences) {
            debugPrint(
              '- Family: ${pref['familyId']}, Member: ${pref['memberUserId']}, Receive: ${pref['receiveMessages']}',
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading member message preferences: $e');
      if (mounted) {
        setState(() => _loadingMemberPreferences = false);
      }
    }
  }

  // Add this method to update member message preference
  Future<void> _updateMemberMessagePreference(
    int familyId,
    int? memberUserId,
    bool receiveMessages,
  ) async {
    // Validate parameters
    if (memberUserId == null) {
      debugPrint('Cannot update message preference for null member ID');
      return;
    }

    debugPrint(
      'Updating member preference: family=$familyId, member=$memberUserId, receive=$receiveMessages',
    );

    try {
      final result = await widget.apiService.updateMemberMessagePreference(
        widget.userId,
        familyId,
        memberUserId,
        receiveMessages,
      );

      debugPrint('Backend response for member preference update: $result');

      // Update local state
      setState(() {
        final index = _memberMessagePreferences.indexWhere(
          (p) => p['familyId'] == familyId && p['memberUserId'] == memberUserId,
        );

        if (index >= 0) {
          debugPrint('Updating existing member preference at index $index');
          _memberMessagePreferences[index]['receiveMessages'] = receiveMessages;
        } else {
          debugPrint('Adding new member preference to state');
          // Add new preference if it doesn't exist
          _memberMessagePreferences.add({
            'familyId': familyId,
            'memberUserId': memberUserId,
            'receiveMessages': receiveMessages,
          });
        }
      });

      // Show feedback to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              receiveMessages
                  ? 'You will receive messages from this family member'
                  : 'You won\'t receive messages from this family member',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating member message preference: $e');
      if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update preference: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Helper method to check if a user should receive messages from a specific member
  bool _shouldReceiveMessagesFromMember(int familyId, int? memberUserId) {
    debugPrint(
      'Checking message preference for family $familyId, member $memberUserId',
    );

    // If memberUserId is null, default to true
    if (memberUserId == null) {
      debugPrint('Member ID is null, defaulting to true');
      return true;
    }

    // First check if we should receive messages from this family at all
    final familyPreference = _messagePreferences.firstWhere(
      (pref) => pref['familyId'] == familyId,
      orElse: () => {'receiveMessages': true},
    );

    // If family messages are disabled, member messages are disabled too
    if (!(familyPreference['receiveMessages'] ?? true)) {
      debugPrint(
        'Family messages are disabled for family $familyId, returning false',
      );
      return false;
    }

    // Check if this is the user viewing their own preferences - always true
    if (memberUserId == widget.userId) {
      debugPrint('This is the current user, always showing as true');
      return true;
    }

    // Then check member-specific preference - default to true if not found
    final memberPreference = _memberMessagePreferences.firstWhere(
      (pref) =>
          pref['familyId'] == familyId && pref['memberUserId'] == memberUserId,
      orElse: () => {'receiveMessages': true},
    );

    final result = memberPreference['receiveMessages'] ?? true;
    debugPrint(
      'Message preference for member $memberUserId in family $familyId: $result',
    );
    return result;
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
}
