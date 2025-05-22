import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:async';
import 'member_message_dialog.dart';
import 'package:provider/provider.dart';

class FamiliesMessageDialog extends StatefulWidget {
  final int userId;

  const FamiliesMessageDialog({Key? key, required this.userId})
    : super(key: key);

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
      debugPrint(
        'FamiliesMessageDialog: Starting to load message preferences for user ${widget.userId}',
      );

      // Load message preferences only - it contains all families user belongs to
      final preferences = await Provider.of<ApiService>(
        context,
        listen: false,
      ).getMessagePreferences(widget.userId);

      debugPrint(
        'FamiliesMessageDialog: Got ${preferences.length} families from preferences',
      );

      if (mounted) {
        setState(() {
          // Use raw API response directly
          _families = preferences;
          _messagePreferences = preferences;
          _isLoading = false;

          // Debug log the loaded data
          debugPrint(
            'FamiliesMessageDialog: Loaded ${_families.length} families',
          );
          for (final family in _families) {
            debugPrint(
              'FamiliesMessageDialog: Family: ${family['familyName'] ?? 'Unknown'} (ID: ${family['familyId']}), role: ${family['role']}',
            );
          }
        });
      }
    } catch (e) {
      debugPrint('FamiliesMessageDialog: Error loading data: $e');
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

  // Update preference for a family with debouncing finish
  Future<void> _updateFamilyPreference(
    int familyId,
    bool receiveMessages,
  ) async {
    try {
      // Update preference in backend
      await Provider.of<ApiService>(
        context,
        listen: false,
      ).updateMessagePreference(widget.userId, familyId, receiveMessages);

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

        // Show feedback if ScaffoldMessenger is available
        try {
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
        } catch (snackBarError) {
          // In a test environment, ScaffoldMessenger might not be available
          debugPrint('Could not show SnackBar: $snackBarError');
        }
      }
    } catch (e) {
      debugPrint('Error updating family preference: $e');
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

  // Navigate to member preferences for a specific family
  void _viewFamilyMemberPreferences(Map<String, dynamic> family) {
    debugPrint(
      'Opening member preferences for family: ${family['familyName']} (ID: ${family['familyId']})',
    );

    // Use showDialog to display MemberMessageDialog instead of navigating to a new screen
    showDialog(
      context: context,
      builder:
          (context) =>
              MemberMessageDialog(userId: widget.userId, family: family),
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
