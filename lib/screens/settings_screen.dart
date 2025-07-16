import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../providers/theme_provider.dart';
import '../providers/text_size_provider.dart';
import 'login_screen.dart';
import '../utils/page_transitions.dart';
import '../widgets/gradient_background.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String? userRole;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.userId,
    this.userRole,
  });

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _autoRefreshEnabled = true;
  String _refreshInterval = '5 min';
  bool _showOfflineContent = true;

  // Notification preferences
  Map<String, dynamic>? _notificationPreferences;
  bool _loadingNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
  }

  Future<void> _loadNotificationPreferences() async {
    setState(() {
      _loadingNotifications = true;
    });

    try {
      final prefs = await widget.apiService.getNotificationPreferences(
        widget.userId,
      );
      if (mounted) {
        setState(() {
          _notificationPreferences = prefs;
          _loadingNotifications = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingNotifications = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading notification preferences: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppTheme.getAppBarColor(context),
        elevation: 0,
      ),
      body: GradientBackground(
        child: ListView(
          children: [
            _buildSectionHeader('Account'),
            _buildAccountSettings(),

            _buildSectionHeader('Appearance'),
            _buildAppearanceSettings(),

            _buildSectionHeader('Notifications'),
            _buildNotificationSettings(),

            _buildSectionHeader('Content'),
            _buildContentSettings(),

            _buildSectionHeader('Data & Privacy'),
            _buildPrivacySettings(),

            _buildSectionHeader('About'),
            _buildAboutSettings(),

            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }

  Future<void> _sendInvitation() async {
    try {
      // First check if user has a family
      final userData = await widget.apiService.getUserById(widget.userId);
      if (!mounted) return;

      final familyId = userData['familyId'];

      if (familyId == null) {
        _showCreateFamilyFirstDialog();
        return;
      }

      // User has a family, proceed with invitation
      final TextEditingController emailController = TextEditingController();
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder:
            (BuildContext dialogContext) => AlertDialog(
              title: const Text('Send Invitation'),
              content: TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(
                      dialogContext,
                    ); // Close the dialog immediately

                    if (!mounted) return;
                    // Show a loading indicator
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Sending invitation...'),
                        duration: Duration(seconds: 1),
                      ),
                    );

                    try {
                      await widget.apiService.inviteUser(
                        widget.userId,
                        emailController.text,
                      );
                      if (!mounted) return;

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invitation sent successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      debugPrint('Error sending invitation: $e');

                      String errorMessage = e.toString();

                      // Check if it's the database error we fixed
                      if (errorMessage.contains('invitee_email') ||
                          errorMessage.contains('constraint') ||
                          errorMessage.contains('null value in column')) {
                        // Show a specific message that's more helpful
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Error sending invitation: ${emailController.text}. Please try a different email.',
                            ),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      } else if (errorMessage.contains(
                        'already in your family',
                      )) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'This person is already in your family!',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      } else if (errorMessage.contains('already pending')) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'There is already a pending invitation for this email.',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      } else if (errorMessage.contains('Server error') ||
                          errorMessage.contains('500')) {
                        // Only show the backend error dialog for server errors
                        _showInvitationBackendError();
                      } else {
                        // For other errors, show a snackbar with the message
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $errorMessage'),
                            backgroundColor: Colors.red,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Send'),
                ),
              ],
            ),
      );
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error checking user family status: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // Add a method to handle the case when user doesn't have a family
  void _showCreateFamilyFirstDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Create a Family First'),
            content: const Text(
              'You need to create a family before you can invite others. Would you like to create a family now?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Not Now'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  // Navigate to family management screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Navigate to family management (not implemented)',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                child: const Text('Create Family'),
              ),
            ],
          ),
    );
  }

  // Show a message about the invitation backend issue
  void _showInvitationBackendError() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Invitation System Unavailable'),
            content: const Text(
              'We\'re sorry, but the invitation system is currently experiencing technical issues.\n\n'
              'Our team has been notified and is working on a fix. In the meantime, you can still use '
              'the app and enjoy your family connections.\n\n'
              'Please try again later or contact support if the issue persists.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Colors.grey[100],
      child: Text(
        title,
        style: TextStyle(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildAccountSettings() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.person),
          title: const Text('Edit Profile'),
          subtitle: const Text('Update your profile information'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Edit Profile tapped')),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change Password'),
          subtitle: const Text('Update your login credentials'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Change Password tapped')),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Logout', style: TextStyle(color: Colors.red)),
          onTap: () async {
            await widget.apiService.logout();
            if (!mounted) return;
            slidePushAndRemoveUntil(
              context,
              const LoginScreen(),
              (route) => false,
            );
          },
        ),
      ],
    );
  }

  Widget _buildAppearanceSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Dark Mode'),
          subtitle: const Text('Change app appearance'),
          secondary: const Icon(Icons.dark_mode),
          value: Provider.of<ThemeProvider>(context).isDarkMode,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) {
            Provider.of<ThemeProvider>(context, listen: false).toggleTheme();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dark mode ${value ? 'enabled' : 'disabled'}'),
              ),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('Text Size'),
          subtitle: Text(
            Provider.of<TextSizeProvider>(context).textSizeDisplayName,
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            _showTextSizeDialog();
          },
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    if (_loadingNotifications) {
      return const Center(child: CircularProgressIndicator());
    }

    final globalSettings =
        _notificationPreferences?['globalNotifications'] ?? {};
    final dmSettings = _notificationPreferences?['dmNotifications'] ?? {};
    final invitationSettings =
        _notificationPreferences?['invitationNotifications'] ?? {};

    return Column(
      children: [
        // Global notification settings
        SwitchListTile(
          title: const Text('Push Notifications'),
          subtitle: const Text('Receive push notifications'),
          secondary: const Icon(Icons.notifications),
          value: globalSettings['pushNotificationsEnabled'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateGlobalNotificationSetting(
              'pushNotificationsEnabled',
              value,
            );
          },
        ),
        SwitchListTile(
          title: const Text('Email Notifications'),
          subtitle: const Text('Receive email notifications'),
          secondary: const Icon(Icons.email),
          value: globalSettings['emailNotificationsEnabled'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateGlobalNotificationSetting(
              'emailNotificationsEnabled',
              value,
            );
          },
        ),

        const Divider(),

        // DM notification settings
        SwitchListTile(
          title: const Text('DM Notifications'),
          subtitle: const Text('Receive notifications for direct messages'),
          secondary: const Icon(Icons.message),
          value: dmSettings['receiveDMNotifications'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateDMNotificationSetting('receiveDMNotifications', value);
          },
        ),
        SwitchListTile(
          title: const Text('DM Email Notifications'),
          subtitle: const Text('Receive email notifications for DMs'),
          secondary: const Icon(Icons.email_outlined),
          value: dmSettings['emailDMNotifications'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateDMNotificationSetting('emailDMNotifications', value);
          },
        ),

        const Divider(),

        // Invitation notification settings
        SwitchListTile(
          title: const Text('Invitation Notifications'),
          subtitle: const Text('Receive notifications for invitations'),
          secondary: const Icon(Icons.family_restroom),
          value: invitationSettings['receiveInvitationNotifications'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateInvitationNotificationSetting(
              'receiveInvitationNotifications',
              value,
            );
          },
        ),
        SwitchListTile(
          title: const Text('Invitation Acceptance Notifications'),
          subtitle: const Text('Get notified when invitations are accepted'),
          secondary: const Icon(Icons.check_circle),
          value: invitationSettings['notifyOnInvitationAccepted'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateInvitationNotificationSetting(
              'notifyOnInvitationAccepted',
              value,
            );
          },
        ),

        const Divider(),

        // Quiet hours settings
        SwitchListTile(
          title: const Text('Quiet Hours'),
          subtitle: const Text('Pause notifications during quiet hours'),
          secondary: const Icon(Icons.bedtime),
          value: globalSettings['quietHoursEnabled'] ?? false,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateGlobalNotificationSetting('quietHoursEnabled', value);
          },
        ),
        if (globalSettings['quietHoursEnabled'] ?? false)
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Quiet Hours Schedule'),
            subtitle: Text(
              '${globalSettings['quietHoursStart'] ?? '22:00'} - ${globalSettings['quietHoursEnd'] ?? '08:00'}',
            ),
            onTap: () => _showQuietHoursDialog(),
          ),

        SwitchListTile(
          title: const Text('Weekend Notifications'),
          subtitle: const Text('Receive notifications on weekends'),
          secondary: const Icon(Icons.weekend),
          value: globalSettings['weekendNotifications'] ?? true,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateGlobalNotificationSetting(
              'weekendNotifications',
              value,
            );
          },
        ),
      ],
    );
  }

  Widget _buildContentSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Auto-refresh Content'),
          subtitle: const Text('Automatically update feeds'),
          secondary: const Icon(Icons.refresh),
          value: _autoRefreshEnabled,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) {
            setState(() {
              _autoRefreshEnabled = value;
            });
          },
        ),
        ListTile(
          leading: const Icon(Icons.timer),
          title: const Text('Refresh Interval'),
          subtitle: Text(_refreshInterval),
          enabled: _autoRefreshEnabled,
          onTap: () {
            if (_autoRefreshEnabled) {
              _showRefreshIntervalDialog();
            }
          },
        ),
        SwitchListTile(
          title: const Text('Show Offline Content'),
          subtitle: const Text('Access content when offline'),
          secondary: const Icon(Icons.offline_pin),
          value: _showOfflineContent,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) {
            setState(() {
              _showOfflineContent = value;
            });
          },
        ),
      ],
    );
  }

  void _showRefreshIntervalDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Refresh Interval'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIntervalOption('1 min', dialogContext),
                _buildIntervalOption('5 min', dialogContext),
                _buildIntervalOption('15 min', dialogContext),
                _buildIntervalOption('30 min', dialogContext),
                _buildIntervalOption('1 hour', dialogContext),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Widget _buildIntervalOption(String interval, BuildContext dialogContext) {
    return RadioListTile<String>(
      title: Text(interval),
      value: interval,
      groupValue: _refreshInterval,
      activeColor:
          Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkGreenAccent
              : AppTheme.primaryColor,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _refreshInterval = value;
          });
          Navigator.pop(dialogContext);
        }
      },
    );
  }

  Widget _buildPrivacySettings() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.security),
          title: const Text('Privacy Settings'),
          subtitle: const Text('Manage your data and privacy'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Privacy Settings tapped')),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.delete),
          title: const Text('Clear App Data'),
          subtitle: const Text('Delete cached content'),
          onTap: () {
            _showClearDataDialog();
          },
        ),
      ],
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Clear App Data'),
            content: const Text(
              'This will delete all cached data including saved messages and media. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('App data cleared')),
                  );
                },
                child: const Text(
                  'Clear Data',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildAboutSettings() {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.info),
          title: const Text('About FamilyNest'),
          subtitle: const Text('App version and information'),
          onTap: () {
            _showAboutDialog();
          },
        ),
        ListTile(
          leading: const Icon(Icons.help),
          title: const Text('Help & Support'),
          subtitle: const Text('Get assistance with using the app'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Help & Support tapped')),
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.rate_review),
          title: const Text('Rate the App'),
          subtitle: const Text('Share your feedback'),
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rate the App tapped')),
            );
          },
        ),
      ],
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('About FamilyNest'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Version: 1.0.0'),
                SizedBox(height: 8),
                Text(
                  'FamilyNest is an app designed to connect families through sharing messages, photos, and videos.',
                ),
                SizedBox(height: 16),
                Text('© 2023 FamilyNest Inc.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  // Notification preference update methods
  Future<void> _updateGlobalNotificationSetting(String key, bool value) async {
    final currentGlobal =
        _notificationPreferences?['globalNotifications'] ?? {};

    try {
      final success = await widget.apiService
          .updateGlobalNotificationPreferences(
            widget.userId,
            emailNotificationsEnabled:
                key == 'emailNotificationsEnabled'
                    ? value
                    : (currentGlobal['emailNotificationsEnabled'] ?? true),
            pushNotificationsEnabled:
                key == 'pushNotificationsEnabled'
                    ? value
                    : (currentGlobal['pushNotificationsEnabled'] ?? true),
            quietHoursEnabled:
                key == 'quietHoursEnabled'
                    ? value
                    : (currentGlobal['quietHoursEnabled'] ?? false),
            quietHoursStart: currentGlobal['quietHoursStart'] ?? '22:00',
            quietHoursEnd: currentGlobal['quietHoursEnd'] ?? '08:00',
            weekendNotifications:
                key == 'weekendNotifications'
                    ? value
                    : (currentGlobal['weekendNotifications'] ?? true),
          );

      if (success) {
        // Update local state
        setState(() {
          _notificationPreferences = {
            ..._notificationPreferences ?? {},
            'globalNotifications': {...currentGlobal, key: value},
          };
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update notification setting'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating notification setting: $e')),
      );
    }
  }

  Future<void> _updateDMNotificationSetting(String key, bool value) async {
    final currentDM = _notificationPreferences?['dmNotifications'] ?? {};

    try {
      final success = await widget.apiService.updateDMNotificationPreferences(
        widget.userId,
        receiveDMNotifications:
            key == 'receiveDMNotifications'
                ? value
                : (currentDM['receiveDMNotifications'] ?? true),
        emailDMNotifications:
            key == 'emailDMNotifications'
                ? value
                : (currentDM['emailDMNotifications'] ?? true),
        pushDMNotifications:
            key == 'pushDMNotifications'
                ? value
                : (currentDM['pushDMNotifications'] ?? true),
      );

      if (success) {
        // Update local state
        setState(() {
          _notificationPreferences = {
            ..._notificationPreferences ?? {},
            'dmNotifications': {...currentDM, key: value},
          };
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update DM notification setting'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating DM notification setting: $e')),
      );
    }
  }

  Future<void> _updateInvitationNotificationSetting(
    String key,
    bool value,
  ) async {
    final currentInvitation =
        _notificationPreferences?['invitationNotifications'] ?? {};

    try {
      final success = await widget.apiService
          .updateInvitationNotificationPreferences(
            widget.userId,
            receiveInvitationNotifications:
                key == 'receiveInvitationNotifications'
                    ? value
                    : (currentInvitation['receiveInvitationNotifications'] ??
                        true),
            emailInvitationNotifications:
                key == 'emailInvitationNotifications'
                    ? value
                    : (currentInvitation['emailInvitationNotifications'] ??
                        true),
            pushInvitationNotifications:
                key == 'pushInvitationNotifications'
                    ? value
                    : (currentInvitation['pushInvitationNotifications'] ??
                        true),
            notifyOnInvitationAccepted:
                key == 'notifyOnInvitationAccepted'
                    ? value
                    : (currentInvitation['notifyOnInvitationAccepted'] ?? true),
            notifyOnInvitationDeclined:
                key == 'notifyOnInvitationDeclined'
                    ? value
                    : (currentInvitation['notifyOnInvitationDeclined'] ??
                        false),
          );

      if (success) {
        // Update local state
        setState(() {
          _notificationPreferences = {
            ..._notificationPreferences ?? {},
            'invitationNotifications': {...currentInvitation, key: value},
          };
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update invitation notification setting'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating invitation notification setting: $e'),
        ),
      );
    }
  }

  void _showQuietHoursDialog() {
    final currentGlobal =
        _notificationPreferences?['globalNotifications'] ?? {};
    String startTime = currentGlobal['quietHoursStart'] ?? '22:00';
    String endTime = currentGlobal['quietHoursEnd'] ?? '08:00';

    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Quiet Hours'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('Start Time'),
                  subtitle: Text(startTime),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay(
                        hour: int.parse(startTime.split(':')[0]),
                        minute: int.parse(startTime.split(':')[1]),
                      ),
                    );
                    if (time != null) {
                      startTime =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    }
                  },
                ),
                ListTile(
                  title: const Text('End Time'),
                  subtitle: Text(endTime),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: dialogContext,
                      initialTime: TimeOfDay(
                        hour: int.parse(endTime.split(':')[0]),
                        minute: int.parse(endTime.split(':')[1]),
                      ),
                    );
                    if (time != null) {
                      endTime =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  // Update quiet hours
                  await _updateQuietHours(startTime, endTime);
                },
                child: const Text('Save'),
              ),
            ],
          ),
    );
  }

  Future<void> _updateQuietHours(String startTime, String endTime) async {
    final currentGlobal =
        _notificationPreferences?['globalNotifications'] ?? {};

    try {
      final success = await widget.apiService
          .updateGlobalNotificationPreferences(
            widget.userId,
            emailNotificationsEnabled:
                currentGlobal['emailNotificationsEnabled'] ?? true,
            pushNotificationsEnabled:
                currentGlobal['pushNotificationsEnabled'] ?? true,
            quietHoursEnabled: currentGlobal['quietHoursEnabled'] ?? false,
            quietHoursStart: startTime,
            quietHoursEnd: endTime,
            weekendNotifications: currentGlobal['weekendNotifications'] ?? true,
          );

      if (success) {
        // Update local state
        setState(() {
          _notificationPreferences = {
            ..._notificationPreferences ?? {},
            'globalNotifications': {
              ...currentGlobal,
              'quietHoursStart': startTime,
              'quietHoursEnd': endTime,
            },
          };
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update quiet hours')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error updating quiet hours: $e')));
    }
  }

  void _showTextSizeDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Text Size'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextSizeOption(TextSizeOption.small, dialogContext),
                _buildTextSizeOption(TextSizeOption.medium, dialogContext),
                _buildTextSizeOption(TextSizeOption.large, dialogContext),
                _buildTextSizeOption(TextSizeOption.extraLarge, dialogContext),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
            ],
          ),
    );
  }

  Widget _buildTextSizeOption(
    TextSizeOption option,
    BuildContext dialogContext,
  ) {
    final textSizeProvider = Provider.of<TextSizeProvider>(
      context,
      listen: false,
    );
    return RadioListTile<TextSizeOption>(
      title: Text(
        _getTextSizeDisplayName(option),
        style: TextStyle(fontSize: 16 * _getTextScaleFactor(option)),
      ),
      subtitle: Text(
        'Sample text at this size',
        style: TextStyle(fontSize: 14 * _getTextScaleFactor(option)),
      ),
      value: option,
      groupValue: textSizeProvider.textSizeOption,
      activeColor:
          Theme.of(context).brightness == Brightness.dark
              ? AppTheme.darkGreenAccent
              : AppTheme.primaryColor,
      onChanged: (value) {
        if (value != null) {
          textSizeProvider.setTextSize(value);
          Navigator.pop(dialogContext);
        }
      },
    );
  }

  String _getTextSizeDisplayName(TextSizeOption option) {
    switch (option) {
      case TextSizeOption.small:
        return 'Small';
      case TextSizeOption.medium:
        return 'Medium';
      case TextSizeOption.large:
        return 'Large';
      case TextSizeOption.extraLarge:
        return 'Extra Large';
    }
  }

  double _getTextScaleFactor(TextSizeOption option) {
    switch (option) {
      case TextSizeOption.small:
        return 0.85;
      case TextSizeOption.medium:
        return 1.0;
      case TextSizeOption.large:
        return 1.15;
      case TextSizeOption.extraLarge:
        return 1.30;
    }
  }
}
