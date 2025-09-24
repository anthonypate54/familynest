import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/api_service.dart';

import '../theme/app_theme.dart';
import '../theme/app_styles.dart';
import '../providers/theme_provider.dart';
import '../providers/text_size_provider.dart';
import '../widgets/gradient_background.dart';
import '../widgets/demographics_dialog.dart';
import '../utils/auth_utils.dart';

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

class SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _notificationPreferences;
  bool _loadingNotifications = false;

  @override
  void initState() {
    super.initState();
    _loadNotificationPreferences();
    // Add observer to detect when app returns from background
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Refresh notification preferences when app becomes active
    // This catches cases where user granted permission via system settings
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        '🔔 SETTINGS: App resumed, refreshing notification preferences',
      );
      _loadNotificationPreferences();
    }
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
        title: const Text('Settings', style: AppStyles.appBarTitleStyle),
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

            _buildSectionHeader('About'),
            _buildAboutSettings(),

            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      color: Colors.grey[100],
      child: Text(
        title,
        style: const TextStyle(
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
          onTap: () async {
            await DemographicsDialog.show(
              context: context,
              userId: widget.userId,
              apiService: widget.apiService,
            );
          },
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('Change Password'),
          subtitle: const Text('Update your login credentials'),
          onTap: () {
            _showChangePasswordDialog();
          },
        ),

        ListTile(
          leading: const Icon(Icons.logout, color: Colors.red),
          title: const Text('Logout', style: TextStyle(color: Colors.red)),
          onTap: () async {
            await AuthUtils.showLogoutConfirmation(context, widget.apiService);
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

    final bool devicePermissionGranted =
        _notificationPreferences?['devicePermissionGranted'] ?? false;
    final bool pushEnabled =
        _notificationPreferences?['pushNotificationsEnabled'] ?? false;
    final bool emailEnabled =
        _notificationPreferences?['emailNotificationsEnabled'] ?? false;

    // DEBUG: Log what we're getting from API
    debugPrint('🔔 SETTINGS: API response: $_notificationPreferences');
    debugPrint(
      '🔔 SETTINGS: devicePermissionGranted = $devicePermissionGranted',
    );
    debugPrint('🔔 SETTINGS: pushEnabled = $pushEnabled');
    debugPrint('🔔 SETTINGS: emailEnabled = $emailEnabled');

    return Column(
      children: [
        // Push Notifications
        SwitchListTile(
          title: const Text('Push Notifications'),
          subtitle: Text(
            devicePermissionGranted
                ? 'Receive push notifications on your device'
                : 'Enable in iOS Settings > Notifications > FamilyNest first',
          ),
          secondary: Icon(
            Icons.notifications,
            color: devicePermissionGranted ? null : Colors.grey,
          ),
          value: devicePermissionGranted ? pushEnabled : false,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged:
              devicePermissionGranted
                  ? (value) async {
                    await _updateNotificationSetting(
                      'pushNotificationsEnabled',
                      value,
                    );
                  }
                  : null, // Disabled when no device permission
        ),

        // Show helper text when device permission not granted
        if (!devicePermissionGranted)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              '💡 To enable push notifications, first allow notifications in your device settings, then return here to turn them on.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.orange[300],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        // Email Notifications (always functional)
        SwitchListTile(
          title: const Text('Email Notifications'),
          subtitle: const Text('Receive email notifications'),
          secondary: const Icon(Icons.email),
          value: emailEnabled,
          activeColor: Colors.white,
          activeTrackColor: AppTheme.getSwitchColor(context),
          onChanged: (value) async {
            await _updateNotificationSetting(
              'emailNotificationsEnabled',
              value,
            );
          },
        ),

        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            'These settings control all notifications from FamilyNest including messages, invitations, and family updates.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.grey[400],
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
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
            _showHelpAndSupportDialog();
          },
        ),
        ListTile(
          leading: const Icon(Icons.rate_review),
          title: const Text('Rate the App'),
          subtitle: const Text('Share your feedback'),
          onTap: () {
            _showRateAppDialog();
          },
        ),
      ],
    );
  }

  void _showRateAppDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Rate FamilyNest'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star, size: 48, color: Colors.amber),
                SizedBox(height: 16),
                Text(
                  'Enjoying FamilyNest? Please take a moment to rate us!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Your feedback helps us improve and reach more families.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Maybe Later'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _openAppStore();
                },
                child: const Text('Rate Now'),
              ),
            ],
          ),
    );
  }

  Future<void> _openAppStore() async {
    // You'll need to replace these with your actual app store URLs
    const iosAppId = 'your-ios-app-id'; // Replace with actual App Store ID
    const androidPackageName =
        'com.familynest.app'; // Replace with actual package name

    try {
      // Try iOS App Store first
      final iosUri = Uri.parse('https://apps.apple.com/app/id$iosAppId');
      if (await canLaunchUrl(iosUri)) {
        await launchUrl(iosUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Try Android Play Store
      final androidUri = Uri.parse(
        'https://play.google.com/store/apps/details?id=$androidPackageName',
      );
      if (await canLaunchUrl(androidUri)) {
        await launchUrl(androidUri, mode: LaunchMode.externalApplication);
        return;
      }

      // Fallback to generic app stores
      final fallbackUri = Uri.parse('https://familynest.app/download');
      if (await canLaunchUrl(fallbackUri)) {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please search for "FamilyNest" in your app store'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please search for "FamilyNest" in your app store'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showHelpAndSupportDialog() {
    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('Help & Support'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Need help with FamilyNest? Choose an option below:',
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 16),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _contactSupport();
                },
                child: const Text('Contact Support'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _openFAQ();
                },
                child: const Text('View FAQ'),
              ),
            ],
          ),
    );
  }

  Future<void> _contactSupport() async {
    const supportEmail = 'support@familynest.app';
    const subject = 'FamilyNest Support Request';
    const body = 'Hello FamilyNest Support Team,\n\nI need help with:\n\n';

    final emailUri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query:
          'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );

    try {
      if (await canLaunchUrl(emailUri)) {
        await launchUrl(emailUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please contact us at support@familynest.app'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please contact us at support@familynest.app'),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _openFAQ() async {
    const faqUrl = 'https://familynest.app/faq';
    final uri = Uri.parse(faqUrl);

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Visit familynest.app/faq for frequently asked questions',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Visit familynest.app/faq for frequently asked questions',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _showAboutDialog() async {
    // Get package info
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String version = packageInfo.version;
    final String buildNumber = packageInfo.buildNumber;

    if (!mounted) return;

    showDialog(
      context: context,
      builder:
          (BuildContext dialogContext) => AlertDialog(
            title: const Text('About FamilyNest'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Version: $version (Build $buildNumber)'),
                const SizedBox(height: 8),
                const Text(
                  'FamilyNest is an app designed to connect families through sharing messages, photos, and videos.',
                ),
                const SizedBox(height: 16),
                const Text('© 2023-2025 FamilyNest Inc.'),
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

  // Simplified notification preference update method
  Future<void> _updateNotificationSetting(String key, bool value) async {
    debugPrint(
      '🔔 SETTINGS: _updateNotificationSetting called with $key = $value',
    );
    try {
      final currentPrefs = _notificationPreferences ?? {};
      debugPrint('🔔 SETTINGS: currentPrefs = $currentPrefs');

      // Create updated preferences map
      final updatedPrefs = <String, bool>{
        'pushNotificationsEnabled':
            key == 'pushNotificationsEnabled'
                ? value
                : (currentPrefs['pushNotificationsEnabled'] ?? false) as bool,
        'emailNotificationsEnabled':
            key == 'emailNotificationsEnabled'
                ? value
                : (currentPrefs['emailNotificationsEnabled'] ?? false) as bool,
      };
      debugPrint('🔔 SETTINGS: updatedPrefs = $updatedPrefs');

      final success = await widget.apiService.updateNotificationPreferences(
        widget.userId,
        updatedPrefs,
      );

      if (success) {
        // Update local state - preserve devicePermissionGranted from previous API response
        setState(() {
          _notificationPreferences = {
            ...updatedPrefs,
            'devicePermissionGranted':
                _notificationPreferences?['devicePermissionGranted'] ?? false,
            'userId': _notificationPreferences?['userId'],
          };
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update notification setting'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating notification setting: $e')),
        );
      }
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

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrentPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;
    bool isLoading = false;

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                title: const Text('Change Password'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrentPassword,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          focusNode: FocusNode(skipTraversal: true),
                          icon: Icon(
                            obscureCurrentPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              obscureCurrentPassword = !obscureCurrentPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          focusNode: FocusNode(skipTraversal: true),
                          icon: Icon(
                            obscureNewPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              obscureNewPassword = !obscureNewPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          focusNode: FocusNode(skipTraversal: true),
                          icon: Icon(
                            obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              obscureConfirmPassword = !obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Password must be at least 6 characters long',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: !isLoading ? () => Navigator.pop(context) : null,
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed:
                        !isLoading
                            ? () async {
                              setState(() {
                                isLoading = true;
                              });

                              await _handleChangePassword(
                                currentPasswordController.text,
                                newPasswordController.text,
                                confirmPasswordController.text,
                                context,
                                setState,
                              );

                              if (mounted) {
                                setState(() {
                                  isLoading = false;
                                });
                              }
                            }
                            : null,
                    child:
                        isLoading
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Text('Change Password'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _handleChangePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
    BuildContext dialogContext,
    StateSetter setDialogState,
  ) async {
    // Validation
    if (currentPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your current password')),
      );
      return;
    }

    if (newPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a new password')),
      );
      return;
    }

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be at least 6 characters long'),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }

    if (currentPassword == newPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New password must be different from current password'),
        ),
      );
      return;
    }

    // Set loading state
    setDialogState(() {
      // This will be handled by the calling method
    });

    try {
      final result = await widget.apiService.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      if (!mounted) return;

      if (result != null && result.containsKey('error')) {
        // Show error message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error']),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (result != null && result.containsKey('message')) {
        // Success
        if (mounted) {
          // ignore: use_build_context_synchronously
          Navigator.pop(dialogContext); // Close dialog
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message']),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // Unexpected response
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('An unexpected error occurred'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
