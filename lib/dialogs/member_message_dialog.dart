// Let's reimplement this file correctly
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'package:provider/provider.dart';

class MemberMessageDialog extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> family;

  const MemberMessageDialog({
    Key? key,
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
      final familyId = widget.family['familyId'] as int;
      debugPrint(
        'MemberMessageDialog: Starting to load data for family ${widget.family["familyName"]} (ID: $familyId)',
      );

      // Use the new method to get family members specific to this family
      debugPrint(
        'MemberMessageDialog: Calling getFamilyMembersByFamilyId for family $familyId (user ${widget.userId})',
      );
      final results = await Future.wait([
        Provider.of<ApiService>(
          context,
          listen: false,
        ).getFamilyMembersByFamilyId(widget.userId, familyId),
        Provider.of<ApiService>(
          context,
          listen: false,
        ).getMemberMessagePreferences(widget.userId),
      ]);

      if (!mounted) return;

      setState(() {
        _members = results[0] as List<Map<String, dynamic>>;
        debugPrint(
          'MemberMessageDialog: Got ${_members.length} members for family $familyId',
        );

        // Log all members for diagnostic purposes
        for (var member in _members) {
          debugPrint('MemberMessageDialog: MEMBER DATA DUMP: $member');
          debugPrint(
            'MemberMessageDialog: Member: ${member["memberUserId"]} - name: ${member["memberFirstName"] ?? "Unknown"} ${member["memberLastName"] ?? ""}',
          );
        }

        _memberPreferences = results[1] as List<Map<String, dynamic>>;
        _localLoading = false;

        // Build preference map for easy lookup
        for (var member in _members) {
          final memberId = member['memberUserId'] as int?;
          if (memberId != null) {
            // Find existing preference
            final preference = _memberPreferences.firstWhere(
              (pref) =>
                  pref['familyId'] == familyId &&
                  pref['memberUserId'] == memberId,
              orElse: () => {'receiveMessages': true},
            );
            _memberPreferenceMap[memberId] =
                preference['receiveMessages'] ??
                member['receiveMessages'] ??
                true;
            debugPrint(
              'MemberMessageDialog: Set preference for member $memberId to ${_memberPreferenceMap[memberId]}',
            );
          }
        }
      });
    } catch (e) {
      debugPrint('MemberMessageDialog: Error loading data: $e');
      if (mounted) {
        setState(() => _localLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load data: $e')));
      }
    }
  }

  // Update member message preference with debouncing
  void _debouncedUpdatePreference(
    int familyId,
    int memberUserId,
    bool newValue,
  ) {
    final key = "$familyId-$memberUserId";

    // Store the pending update value
    _pendingUpdates[key] = newValue;

    // Cancel any existing timer for this key
    _pendingUpdateTimers[key]?.cancel();

    // Create a new timer
    _pendingUpdateTimers[key] = Timer(const Duration(milliseconds: 300), () {
      // If there's still a pending update when the timer fires, apply it
      if (_pendingUpdates.containsKey(key)) {
        final valueToApply = _pendingUpdates[key]!;

        // Remove from pending updates
        _pendingUpdates.remove(key);

        // Call the actual update method
        _updateMemberMessagePreference(familyId, memberUserId, valueToApply);
      }
    });
  }

  // Update member preference for receiving messages from this user
  Future<void> _updateMemberMessagePreference(
    int familyId,
    int memberUserId,
    bool receiveMessages,
  ) async {
    debugPrint(
      'Applying debounced preference update: $familyId-$memberUserId = $receiveMessages',
    );

    try {
      // Call API to update preference
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).updateMemberMessagePreference(
        widget.userId,
        familyId,
        memberUserId,
        receiveMessages,
      );

      if (mounted) {
        // Update local state
        setState(() {
          final index = _members.indexWhere(
            (member) => member['memberUserId'] == memberUserId,
          );
          if (index >= 0) {
            _members[index]['receiveMessages'] = receiveMessages;
          }
        });

        // Show feedback if ScaffoldMessenger is available
        try {
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
        } catch (snackBarError) {
          // In a test environment, ScaffoldMessenger might not be available
          debugPrint('Could not show SnackBar: $snackBarError');
        }
      }
    } catch (e) {
      debugPrint('Error updating member preference: $e');
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating preference: $e')),
          );
        } catch (snackBarError) {
          // In a test environment, ScaffoldMessenger might not be available
          debugPrint('Could not show error SnackBar: $snackBarError');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final familyName = widget.family['familyName'] ?? 'Unknown Family';
    final familyId = widget.family['familyId'] as int;

    debugPrint(
      'MemberMessageDialog: Building UI for family $familyName (ID: $familyId)',
    );
    debugPrint(
      'MemberMessageDialog: Loading state: $_localLoading, Members count: ${_members.length}',
    );

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
              child: const Column(
                children: [
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
                    children: [
                      const Icon(
                        Icons.people_alt,
                        color: Colors.grey,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No members found in this family',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Family ID: $familyId',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
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
                    debugPrint(
                      'MemberMessageDialog: Building list item for index $index',
                    );
                    final member = _members[index];
                    final memberId = member['memberUserId'] as int?;
                    debugPrint(
                      'MemberMessageDialog: Member at index $index has ID: $memberId',
                    );

                    final isCurrentUser = memberId == widget.userId;

                    if (memberId == null) {
                      debugPrint(
                        'MemberMessageDialog: Skipping member at index $index due to null ID',
                      );
                      return const SizedBox.shrink();
                    }

                    // Get current preference state
                    final receiveMessages =
                        _memberPreferenceMap[memberId] ??
                        member['receiveMessages'] ??
                        true;

                    debugPrint(
                      'MemberMessageDialog: Building item for member $memberId, isCurrentUser=$isCurrentUser, receiveMessages=$receiveMessages',
                    );

                    return GestureDetector(
                      onTap:
                          isCurrentUser
                              ? null
                              : () {
                                // Toggle the state on tap
                                final newValue = !receiveMessages;
                                debugPrint(
                                  'MemberMessageDialog: Toggling preference for member $memberId to $newValue',
                                );

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
                                    debugPrint(
                                      'MemberMessageDialog: Checkbox changed for member $memberId to $newValue',
                                    );
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
                                    'MemberMessageDialog: Member object keys: ${member.keys.join(", ")}',
                                  );

                                  // Always show first and last name
                                  String firstName =
                                      member['memberFirstName'] ?? 'Unknown';
                                  String lastName =
                                      member['memberLastName'] ?? '';
                                  String fullName = '$firstName $lastName';
                                  debugPrint(
                                    'MemberMessageDialog: Showing full name: $fullName',
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
                              const Tooltip(
                                message: 'Family Owner',
                                child: Padding(
                                  padding: EdgeInsets.only(left: 8.0),
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
                              : member['memberUsername'] ?? 'No username',
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
