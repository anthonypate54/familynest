import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:async';

class FamiliesMessageDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;

  const FamiliesMessageDialog({
    Key? key,
    required this.apiService,
    required this.userId,
  }) : super(key: key);

  @override
  State<FamiliesMessageDialog> createState() => _FamiliesMessageDialogState();
}

class _FamiliesMessageDialogState extends State<FamiliesMessageDialog> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _families = [];
  List<Map<String, dynamic>> _messagePreferences = [];

  // For debouncing updates
  final Map<String, Timer> _pendingUpdateTimers = {};
  final Map<String, bool> _pendingUpdates = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    // Cancel any pending timers
    _pendingUpdateTimers.forEach((_, timer) => timer.cancel());
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load message preferences only - it contains all families user belongs to
      final preferences = await widget.apiService.getMessagePreferences(
        widget.userId,
      );

      if (mounted) {
        setState(() {
          // Use raw API response directly
          _families = preferences;
          _messagePreferences = preferences;
          _isLoading = false;

          // Debug log the loaded data
          debugPrint('Loaded ${_families.length} families');
          for (final family in _families) {
            debugPrint(
              'Family: ${family['familyName'] ?? 'Unknown'} (ID: ${family['familyId']}), role: ${family['role']}',
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  // Get the receive messages setting for a family
  bool _getReceiveMessagesForFamily(int familyId) {
    final preference = _messagePreferences.firstWhere(
      (pref) => pref['familyId'] == familyId,
      orElse: () => {'receiveMessages': true},
    );
    return preference['receiveMessages'] ?? true;
  }

  // Update message preference for a family with debouncing
  void _debouncedUpdateFamilyPreference(int familyId, bool newValue) {
    final key = familyId.toString();

    // Store the pending update value
    _pendingUpdates[key] = newValue;

    // Cancel any existing timer for this key
    _pendingUpdateTimers[key]?.cancel();

    // Create a new timer
    _pendingUpdateTimers[key] = Timer(const Duration(milliseconds: 300), () {
      // If there's still a pending update when the timer fires, apply it
      if (_pendingUpdates.containsKey(key)) {
        final valueToApply = _pendingUpdates[key]!;
        debugPrint(
          'Applying debounced family preference update: $key = $valueToApply',
        );

        // Remove from pending updates
        _pendingUpdates.remove(key);

        // Call the actual update method
        _updateFamilyPreference(familyId, valueToApply);
      }
    });
  }

  // Update message preference for a family
  Future<void> _updateFamilyPreference(
    int familyId,
    bool receiveMessages,
  ) async {
    try {
      // Update preference in backend
      await widget.apiService.updateMessagePreference(
        widget.userId,
        familyId,
        receiveMessages,
      );

      // Update local state
      if (mounted) {
        setState(() {
          final index = _messagePreferences.indexWhere(
            (pref) => pref['familyId'] == familyId,
          );

          if (index >= 0) {
            _messagePreferences[index]['receiveMessages'] = receiveMessages;
          } else {
            _messagePreferences.add({
              'familyId': familyId,
              'receiveMessages': receiveMessages,
            });
          }
        });

        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              receiveMessages
                  ? 'You will receive messages from this family'
                  : 'You won\'t receive messages from this family',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating family preference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating preference: $e')),
        );
      }
    }
  }

  // Navigate to member preferences for a specific family
  void _viewFamilyMemberPreferences(Map<String, dynamic> family) {
    Navigator.pop(context); // Close the current dialog

    debugPrint(
      'Opening member preferences for family: ${family['familyName']} (ID: ${family['familyId']})',
    );

    // Call the callback to show the members dialog
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => FamilyMembersPreferencesScreen(
              apiService: widget.apiService,
              userId: widget.userId,
              familyId: family['familyId'],
              familyName: family['familyName'] ?? 'Unknown Family',
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Families You Belong To',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

            // Content area
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_families.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Center(
                  child: Column(
                    children: const [
                      Icon(Icons.people_alt, color: Colors.grey, size: 40),
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
                  itemCount: _families.length,
                  itemBuilder: (context, index) {
                    final family = _families[index];
                    final familyId = family['familyId'] as int;
                    final familyName =
                        family['familyName'] as String? ?? 'Unknown Family';
                    final isOwner = family['role'] == 'ADMIN';
                    final receiveMessages = _getReceiveMessagesForFamily(
                      familyId,
                    );

                    return GestureDetector(
                      onTap: () {
                        final newValue = !receiveMessages;
                        setState(() {
                          bool found = false;
                          for (int i = 0; i < _messagePreferences.length; i++) {
                            if (_messagePreferences[i]['familyId'] ==
                                familyId) {
                              _messagePreferences[i]['receiveMessages'] =
                                  newValue;
                              found = true;
                              break;
                            }
                          }
                          if (!found) {
                            _messagePreferences.add({
                              'familyId': familyId,
                              'receiveMessages': newValue,
                            });
                          }
                        });
                        _debouncedUpdateFamilyPreference(familyId, newValue);
                      },
                      child: CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        value: receiveMessages,
                        onChanged: (newValue) {
                          if (newValue != null) {
                            // Update UI immediately for responsiveness
                            setState(() {
                              // Find and update existing preference
                              bool found = false;
                              for (
                                int i = 0;
                                i < _messagePreferences.length;
                                i++
                              ) {
                                if (_messagePreferences[i]['familyId'] ==
                                    familyId) {
                                  _messagePreferences[i]['receiveMessages'] =
                                      newValue;
                                  found = true;
                                  break;
                                }
                              }

                              // If no existing preference, add a new one
                              if (!found) {
                                _messagePreferences.add({
                                  'familyId': familyId,
                                  'receiveMessages': newValue,
                                });
                              }
                            });

                            // Update with debouncing
                            _debouncedUpdateFamilyPreference(
                              familyId,
                              newValue,
                            );
                          }
                        },
                        secondary: CircleAvatar(
                          radius: 20,
                          backgroundColor:
                              isOwner
                                  ? Colors.green.shade100
                                  : Colors.blue.shade100,
                          child: Text(
                            familyName.isNotEmpty
                                ? familyName[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  isOwner
                                      ? Colors.green.shade700
                                      : Colors.blue.shade700,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                familyName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (isOwner)
                              Tooltip(
                                message: 'Family Owner',
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Icon(
                                    Icons.home,
                                    color: Colors.amber,
                                    size: 16,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.settings,
                                size: 16,
                                color: Colors.blue,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed:
                                  () => _viewFamilyMemberPreferences(family),
                              tooltip: 'Member Settings',
                            ),
                          ],
                        ),
                        subtitle: const Text(
                          'family',
                          style: TextStyle(fontSize: 12),
                        ),
                        activeColor: Theme.of(context).colorScheme.primary,
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
          child: const Text('Close'),
        ),
      ],
    );
  }
}

// Members screen
class FamilyMembersPreferencesScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int familyId;
  final String familyName;

  const FamilyMembersPreferencesScreen({
    Key? key,
    required this.apiService,
    required this.userId,
    required this.familyId,
    required this.familyName,
  }) : super(key: key);

  @override
  State<FamilyMembersPreferencesScreen> createState() =>
      _FamilyMembersPreferencesScreenState();
}

class _FamilyMembersPreferencesScreenState
    extends State<FamilyMembersPreferencesScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _memberPreferences = [];

  // For debouncing updates
  final Map<String, Timer> _pendingUpdateTimers = {};
  final Map<String, bool> _pendingUpdates = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    // Cancel any pending timers
    _pendingUpdateTimers.forEach((_, timer) => timer.cancel());
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Load family members and member preferences
      final results = await Future.wait([
        widget.apiService.getFamilyMembers(widget.userId),
        widget.apiService.getMemberMessagePreferences(widget.userId),
      ]);

      if (mounted) {
        setState(() {
          // Filter members to only include those from this family
          _members =
              (results[0] as List<Map<String, dynamic>>)
                  .where((member) => member['familyId'] == widget.familyId)
                  .toList();

          _memberPreferences = results[1] as List<Map<String, dynamic>>;
          _isLoading = false;

          // Debug log the loaded data
          debugPrint(
            'Loaded ${_members.length} family members for family ${widget.familyId} (${widget.familyName})',
          );
          for (final member in _members) {
            debugPrint(
              'Member: ${member['firstName'] ?? member['memberFirstName']} ${member['lastName'] ?? member['memberLastName']} (ID: ${member['userId']})',
            );
          }

          debugPrint('Loaded ${_memberPreferences.length} member preferences');
          for (final pref in _memberPreferences) {
            if (pref['familyId'] == widget.familyId) {
              debugPrint(
                'Member preference: familyId=${pref['familyId']}, memberUserId=${pref['memberUserId']}, receive=${pref['receiveMessages']}',
              );
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading data: $e')));
      }
    }
  }

  // Get the receive messages setting for a member
  bool _getReceiveMessagesForMember(int memberId) {
    final preference = _memberPreferences.firstWhere(
      (pref) =>
          pref['familyId'] == widget.familyId &&
          pref['memberUserId'] == memberId,
      orElse: () => {'receiveMessages': true},
    );
    return preference['receiveMessages'] ?? true;
  }

  // Update member preference with debouncing
  void _debouncedUpdateMemberPreference(int memberId, bool newValue) {
    final key = "${widget.familyId}-$memberId";

    // Store the pending update value
    _pendingUpdates[key] = newValue;

    // Cancel any existing timer for this key
    _pendingUpdateTimers[key]?.cancel();

    // Create a new timer
    _pendingUpdateTimers[key] = Timer(const Duration(milliseconds: 300), () {
      // If there's still a pending update when the timer fires, apply it
      if (_pendingUpdates.containsKey(key)) {
        final valueToApply = _pendingUpdates[key]!;
        debugPrint(
          'Applying debounced member preference update: $key = $valueToApply',
        );

        // Remove from pending updates
        _pendingUpdates.remove(key);

        // Call the actual update method
        _updateMemberPreference(memberId, valueToApply);
      }
    });
  }

  // Update message preference for a member
  Future<void> _updateMemberPreference(
    int memberId,
    bool receiveMessages,
  ) async {
    try {
      // Update preference in backend
      await widget.apiService.updateMemberMessagePreference(
        widget.userId,
        widget.familyId,
        memberId,
        receiveMessages,
      );

      // Update local state
      if (mounted) {
        setState(() {
          final index = _memberPreferences.indexWhere(
            (pref) =>
                pref['familyId'] == widget.familyId &&
                pref['memberUserId'] == memberId,
          );

          if (index >= 0) {
            _memberPreferences[index]['receiveMessages'] = receiveMessages;
          } else {
            _memberPreferences.add({
              'familyId': widget.familyId,
              'memberUserId': memberId,
              'receiveMessages': receiveMessages,
            });
          }
        });

        // Show feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              receiveMessages
                  ? 'You will receive messages from this member'
                  : 'You won\'t receive messages from this member',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating member preference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating preference: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // MODIFIED: Fixed _messagePreferences typo to _memberPreferences in onChanged
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.familyName} Family Members'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          // Header card with message preferences info
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Icon(Icons.notifications, color: Colors.blue, size: 32),
                const SizedBox(height: 8),
                const Text(
                  'Message Preferences',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Control which family members you receive messages from by checking or unchecking the box next to their name.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_members.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.people_alt, color: Colors.grey, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'No members found in this family',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: _members.length,
                padding: EdgeInsets.zero,
                itemBuilder: (context, index) {
                  final member = _members[index];
                  final memberId = member['userId'] as int?;
                  if (memberId == null) return const SizedBox.shrink();

                  final isCurrentUser = memberId == widget.userId;
                  final firstName =
                      member['firstName'] ??
                      member['memberFirstName'] ??
                      'Unknown';
                  final lastName =
                      member['lastName'] ?? member['memberLastName'] ?? '';
                  final username =
                      member['username'] ??
                      member['memberUsername'] ??
                      'No username';
                  final isOwner = member['isOwner'] == true;
                  final receiveMessages = _getReceiveMessagesForMember(
                    memberId,
                  );

                  return CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    value: receiveMessages,
                    onChanged:
                        isCurrentUser
                            ? null
                            : (newValue) {
                              if (newValue != null) {
                                // Update UI immediately for responsiveness
                                setState(() {
                                  // Find and update existing preference
                                  bool found = false;
                                  for (
                                    int i = 0;
                                    i < _memberPreferences.length;
                                    i++
                                  ) {
                                    if (_memberPreferences[i]['familyId'] ==
                                            widget.familyId &&
                                        _memberPreferences[i]['memberUserId'] ==
                                            memberId) {
                                      _memberPreferences[i]['receiveMessages'] =
                                          newValue;
                                      found = true;
                                      break;
                                    }
                                  }

                                  // If no existing preference, add a new one
                                  // REMOVED: _messagePreferences.add({
                                  // ADDED: Fixed typo to use _memberPreferences
                                  if (!found) {
                                    _memberPreferences.add({
                                      'familyId': widget.familyId,
                                      'memberUserId': memberId,
                                      'receiveMessages': newValue,
                                    });
                                  }
                                });

                                // Update with debouncing
                                _debouncedUpdateMemberPreference(
                                  memberId,
                                  newValue,
                                );
                              }
                            },
                    secondary: CircleAvatar(
                      backgroundColor:
                          isCurrentUser
                              ? Colors.blue.shade100
                              : Colors.green.shade100,
                      child: Text(
                        firstName.toString()[0].toUpperCase(),
                        style: TextStyle(
                          color:
                              isCurrentUser
                                  ? Colors.blue.shade700
                                  : Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$firstName $lastName',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  isCurrentUser ? Colors.blue.shade700 : null,
                            ),
                          ),
                        ),
                        if (isOwner)
                          Icon(Icons.home, color: Colors.amber, size: 18),
                      ],
                    ),
                    subtitle: Text(
                      isCurrentUser ? 'This is you' : username,
                      style: const TextStyle(fontSize: 12),
                    ),
                    activeColor: Theme.of(context).colorScheme.primary,
                    checkColor: Colors.white,
                  );
                },
              ),
            ),
          const Divider(height: 1, thickness: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Close'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
