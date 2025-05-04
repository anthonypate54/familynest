// Let's reimplement this file correctly
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:async';

class MemberMessageDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> family;

  const MemberMessageDialog({
    Key? key,
    required this.apiService,
    required this.userId,
    required this.family,
  }) : super(key: key);

  @override
  State<MemberMessageDialog> createState() => _MemberMessageDialogState();
}

class _MemberMessageDialogState extends State<MemberMessageDialog> {
  bool _localLoading = true;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _memberPreferences = [];

  // For debouncing updates
  final Map<String, Timer> _pendingUpdateTimers = {};
  final Map<String, bool> _pendingUpdates = {};

  // Member preferences map for UI reactivity
  Map<int, bool> _memberPreferenceMap = {};

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
    if (!mounted) return;

    setState(() => _localLoading = true);

    try {
      // Load data in parallel
      final results = await Future.wait([
        widget.apiService.getFamilyMembers(widget.userId),
        widget.apiService.getMemberMessagePreferences(widget.userId),
      ]);

      if (!mounted) return;

      final familyId = widget.family['familyId'] as int;

      setState(() {
        _members = results[0] as List<Map<String, dynamic>>;
        _memberPreferences = results[1] as List<Map<String, dynamic>>;
        _localLoading = false;

        // Build preference map for easy lookup
        for (var member in _members) {
          final memberId = member['userId'] as int?;
          if (memberId != null) {
            // Find existing preference
            final preference = _memberPreferences.firstWhere(
              (pref) =>
                  pref['familyId'] == familyId &&
                  pref['memberUserId'] == memberId,
              orElse: () => {'receiveMessages': true},
            );
            _memberPreferenceMap[memberId] =
                preference['receiveMessages'] ?? true;
          }
        }

        // Debug logging
        debugPrint('Family members data: $_members');
        for (var member in _members) {
          debugPrint('Member data: $member');
        }
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _localLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
      }
    }
  }

  // Update member message preference with debouncing
  void _debouncedUpdatePreference(int familyId, int memberId, bool newValue) {
    final key = "$familyId-$memberId";

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
          'Applying debounced preference update: $key = $valueToApply',
        );

        // Remove from pending updates
        _pendingUpdates.remove(key);

        // Call the actual update method
        _updateMemberMessagePreference(familyId, memberId, valueToApply);
      }
    });
  }

  // Update message preference for a specific family member
  Future<void> _updateMemberMessagePreference(
    int familyId,
    int memberId,
    bool receiveMessages,
  ) async {
    try {
      // Update preference in backend
      await widget.apiService.updateMemberMessagePreference(
        widget.userId,
        familyId,
        memberId,
        receiveMessages,
      );

      // Update local state
      if (mounted) {
        setState(() {
          final index = _memberPreferences.indexWhere(
            (pref) =>
                pref['familyId'] == familyId &&
                pref['memberUserId'] == memberId,
          );

          if (index >= 0) {
            _memberPreferences[index]['receiveMessages'] = receiveMessages;
          } else {
            _memberPreferences.add({
              'familyId': familyId,
              'memberUserId': memberId,
              'receiveMessages': receiveMessages,
            });
          }

          // Also update preference map
          _memberPreferenceMap[memberId] = receiveMessages;
        });

        // Provide user feedback
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
      debugPrint('Error updating member preference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update preference: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyName = widget.family['familyName'] ?? 'Unknown Family';
    final familyId = widget.family['familyId'] as int;

    return AlertDialog(
      title: Text(
        '$familyName Family Members',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
            if (_localLoading)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_members.isEmpty)
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
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    final memberId = member['userId'] as int?;
                    final isCurrentUser = memberId == widget.userId;

                    if (memberId == null) {
                      return const SizedBox.shrink();
                    }

                    // Get current preference state
                    final receiveMessages =
                        _memberPreferenceMap[memberId] ?? true;

                    return GestureDetector(
                      onTap:
                          isCurrentUser
                              ? null
                              : () {
                                // Toggle the state on tap
                                final newValue = !receiveMessages;

                                // Update UI state immediately
                                setState(() {
                                  _memberPreferenceMap[memberId] = newValue;
                                });

                                // Update with debouncing
                                _debouncedUpdatePreference(
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
                                    // Update UI state immediately
                                    setState(() {
                                      _memberPreferenceMap[memberId] = newValue;
                                    });

                                    // Update with debouncing
                                    _debouncedUpdatePreference(
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
                              if (member.containsKey('memberFirstName') &&
                                  member['memberFirstName'] != null &&
                                  member['memberFirstName']
                                      .toString()
                                      .isNotEmpty) {
                                firstLetter =
                                    member['memberFirstName'].toString()[0];
                              } else if (member.containsKey('firstName') &&
                                  member['firstName'] != null &&
                                  member['firstName'].toString().isNotEmpty) {
                                firstLetter = member['firstName'].toString()[0];
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
                                  } else if (member.containsKey('isowner')) {
                                    isOwner = member['isowner'] == true;
                                    debugPrint(
                                      'Using isowner field from API: $isOwner',
                                    );
                                  }

                                  // If user owns a family, show family name
                                  if (isOwner) {
                                    // Try to get owned family name from API if available
                                    String? ownedFamilyName;
                                    if (member.containsKey('ownedFamilyName')) {
                                      ownedFamilyName =
                                          member['ownedFamilyName']?.toString();
                                    } else if (member.containsKey(
                                      'ownedfamilyname',
                                    )) {
                                      ownedFamilyName =
                                          member['ownedfamilyname']?.toString();
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
                                  String fullName = '$firstName $lastName';
                                  debugPrint('Showing full name: $fullName');
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
                                  padding: const EdgeInsets.only(left: 8.0),
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
