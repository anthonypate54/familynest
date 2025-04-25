import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../components/bottom_navigation.dart';
import 'login_screen.dart';

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
  bool _darkModeEnabled = false;
  bool _autoRefreshEnabled = true;
  String _refreshInterval = '5 min';
  bool _showOfflineContent = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: AppStyles.appBarTitleStyle),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
      ),
      bottomNavigationBar: BottomNavigation(
        currentIndex: 2, // Settings tab
        apiService: widget.apiService,
        userId: widget.userId,
        userRole: widget.userRole,
        onSendInvitation: (_) => _sendInvitation(),
      ),
      body: ListView(
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
    );
  }

  Future<void> _sendInvitation() async {
    final TextEditingController emailController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Send Invitation'),
          content: TextField(
            controller: emailController,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await widget.apiService.inviteUser(
                    widget.userId,
                    emailController.text,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Invitation sent successfully!'),
                    ),
                  );
                  Navigator.pop(context);
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Send'),
            ),
          ],
        );
      },
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
          onTap: () {
            widget.apiService.logout();
            if (!mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                builder:
                    (context) => LoginScreen(apiService: widget.apiService),
              ),
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
          value: _darkModeEnabled,
          onChanged: (value) {
            setState(() {
              _darkModeEnabled = value;
            });
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
          subtitle: const Text('Change font size'),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('Text Size tapped')));
          },
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return Column(
      children: [
        SwitchListTile(
          title: const Text('Enable Notifications'),
          subtitle: const Text('Show app notifications'),
          secondary: const Icon(Icons.notifications),
          value: _notificationsEnabled,
          onChanged: (value) {
            setState(() {
              _notificationsEnabled = value;
            });
          },
        ),
        ListTile(
          leading: const Icon(Icons.message),
          title: const Text('Message Notifications'),
          subtitle: Text(_notificationsEnabled ? 'Enabled' : 'Disabled'),
          enabled: _notificationsEnabled,
          onTap: () {
            if (_notificationsEnabled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Message notifications settings')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.family_restroom),
          title: const Text('Family Updates'),
          subtitle: Text(_notificationsEnabled ? 'Enabled' : 'Disabled'),
          enabled: _notificationsEnabled,
          onTap: () {
            if (_notificationsEnabled) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Family updates settings')),
              );
            }
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Refresh Interval'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIntervalOption('1 min'),
              _buildIntervalOption('5 min'),
              _buildIntervalOption('15 min'),
              _buildIntervalOption('30 min'),
              _buildIntervalOption('1 hour'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildIntervalOption(String interval) {
    return RadioListTile<String>(
      title: Text(interval),
      value: interval,
      groupValue: _refreshInterval,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _refreshInterval = value;
          });
          Navigator.pop(context);
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear App Data'),
          content: const Text(
            'This will delete all cached data including saved messages and media. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
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
        );
      },
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
      builder: (context) {
        return AlertDialog(
          title: const Text('About FamilyNest'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Version: 1.0.0'),
              const SizedBox(height: 8),
              const Text(
                'FamilyNest is an app designed to connect families through sharing messages, photos, and videos.',
              ),
              const SizedBox(height: 16),
              const Text('© 2023 FamilyNest Inc.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
