import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../widgets/video_message_card.dart';
import '../widgets/external_video_message_card.dart';
import '../screens/thread_screen.dart';
import '../utils/page_transitions.dart';
import '../services/share_service.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../services/message_view_tracker.dart';
import '../services/comment_notification_tracker.dart';

class MessageService {
  static Widget buildMessageListView(
    BuildContext context,
    List<Message> messages, {
    required ApiService apiService,
    ScrollController? scrollController,
    void Function(Message)? onTap,
    String? currentUserId,
    void Function(Message)? onThreadTap,
    String? currentlyPlayingVideoId,
    String? content,
    bool isThreadView = false,
    bool isFirstTimeUser = true,
  }) {
    // Show empty state when no messages
    if (messages.isEmpty) {
      return _buildEmptyState(context, isFirstTimeUser: isFirstTimeUser);
    }

    return ListView.builder(
      controller: scrollController,
      reverse: !isThreadView,
      itemCount: messages.length,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      itemBuilder: (context, index) {
        final message = messages[index];
        String timeText = '';
        String dayText = '';
        String dateSeparatorText = '';
        DateTime? messageDateTime;
        if (message.createdAt != null) {
          messageDateTime = message.createdAt;
          timeText = _formatTime(context, messageDateTime);
          dayText = _getShortDayName(messageDateTime);
        }

        bool shouldShowDateSeparator = false;
        final currentMessage = messages[index];
        final currentDate = currentMessage.createdAt;

        // Show separator logic depends on whether ListView is reversed
        if (!isThreadView) {
          // Main screen: ListView is reversed (newest at bottom visually, but top of array)
          // We want separators at the END of each day group (bottom of visual day)
          if (index == messages.length - 1) {
            // Last item in array (visually first/newest)
            shouldShowDateSeparator = true;
          } else {
            final nextMessage = messages[index + 1];
            final nextDate = nextMessage.createdAt;
            if (currentDate != null &&
                nextDate != null &&
                !_isSameDay(currentDate, nextDate)) {
              // Next message is from different day
              shouldShowDateSeparator = true;
            }
          }
        } else {
          // Thread view: ListView is normal order (newest at top)
          if (index == 0) {
            // First message (newest)
            shouldShowDateSeparator = true;
          } else {
            final previousMessage = messages[index - 1];
            final previousDate = previousMessage.createdAt;
            if (currentDate != null &&
                previousDate != null &&
                !_isSameDay(currentDate, previousDate)) {
              shouldShowDateSeparator = true;
            }
          }
        }
        if (shouldShowDateSeparator && messageDateTime != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));
          final messageDate = DateTime(
            messageDateTime.year,
            messageDateTime.month,
            messageDateTime.day,
          );

          if (messageDate == today) {
            dateSeparatorText = 'Today';
          } else if (messageDate == yesterday) {
            dateSeparatorText = 'Yesterday';
          } else if (today.difference(messageDate).inDays < 7) {
            dateSeparatorText = DateFormat(
              'EEEE',
            ).format(messageDate); // e.g., "Monday"
          } else {
            dateSeparatorText = DateFormat(
              'MMM d, yyyy',
            ).format(messageDate); // e.g., "Jan 15, 2023"
          }
        }
        final suppressDateSeparator = isThreadView && index == 0;

        return Column(
          children: [
            if (!suppressDateSeparator &&
                shouldShowDateSeparator &&
                (dateSeparatorText.isNotEmpty))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10.0),
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    dateSeparatorText,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),

            MessageCard(
              key: ValueKey(message.id),
              message: message,
              apiService: apiService,
              onTap: onTap,
              timeText: timeText,
              dayText: dayText,
              shouldShowDateSeparator: shouldShowDateSeparator,
              dateSeparatorText: dateSeparatorText,
              currentUserId: currentUserId,
              onThreadTap: onThreadTap,
              currentlyPlayingVideoId: currentlyPlayingVideoId,
              showCommentIcon: !isThreadView,
              suppressDateSeparator: suppressDateSeparator,
              isThreadView: isThreadView,
            ),
          ],
        );
      },
    );
  }

  static String _formatTime(BuildContext context, DateTime? dateTime) {
    if (dateTime == null) return '';
    return TimeOfDay.fromDateTime(dateTime).format(context);
  }

  // Add a public method that wraps the private one
  static String formatTime(BuildContext context, DateTime? dateTime) {
    return _formatTime(context, dateTime);
  }

  static String _getShortDayName(DateTime? dateTime) {
    if (dateTime == null) return '';
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dateTime.weekday -
        1];
  }

  static String getShortDayName(DateTime? dateTime) {
    return _getShortDayName(dateTime);
  }

  static bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool isSameDay(DateTime? a, DateTime? b) {
    return _isSameDay(a, b);
  }

  // Build beautiful empty state for new users
  static Widget _buildEmptyState(
    BuildContext context, {
    bool isFirstTimeUser = true,
  }) {
    // If user is not a first-time user (has DMs), show simple empty state
    if (!isFirstTimeUser) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.message_outlined,
                  size: 30,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No messages yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Start sharing photos and messages with your family',
                style: TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Show full welcome dialog for first-time users
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Welcome Icon - smaller
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.family_restroom,
                size: 40,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 16),

            // Welcome Title - smaller
            const Text(
              'Welcome to Family Nest! 👋',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description - smaller
            const Text(
              'Share photos, videos, and messages with your family members in a private space.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Getting Started Steps - more compact
            _buildCompactCard(
              icon: Icons.home_filled,
              title: 'Create or Join a Family',
              actionText: 'Go to Family Tab',
              onTap: () => _navigateToFamilyManagement(context),
            ),
            const SizedBox(height: 12),

            _buildCompactCard(
              icon: Icons.photo_camera,
              title: 'Share Photos & Messages',
              actionText: 'See How',
              onTap: () => _showHelpDialog(context),
            ),
            const SizedBox(height: 12),

            _buildCompactCard(
              icon: Icons.people,
              title: 'Invite Family Members',
              actionText: 'Learn About Invites',
              onTap: () => _showInvitationHelp(context),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build compact getting started cards
  static Widget _buildCompactCard({
    required IconData icon,
    required String title,
    required String actionText,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.blue, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 32),
              ),
              child: Text(actionText, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // Navigation helper
  static void _navigateToFamilyManagement(BuildContext context) {
    // Try to find the MainAppContainer and switch to Family tab (index 2)
    try {
      // Navigate up the widget tree to find the PageController
      // For now, use a simpler approach: direct navigation
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) {
            // We need to get the userId from somewhere
            // Let's try a different approach - just show helpful dialog with clear instructions
            return _buildNavigationHelpDialog(context);
          },
        ),
      );
    } catch (e) {
      // Fallback: show dialog with clear instructions
      _showNavigationHelpDialog(context);
    }
  }

  // Show navigation help as a full dialog
  static Widget _buildNavigationHelpDialog(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black54,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.family_restroom, size: 48, color: Colors.blue),
              const SizedBox(height: 16),
              const Text(
                'Get Started with Families',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'To create or join a family and start sharing messages:',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              _buildStep('1', 'Tap the "Family" tab at the bottom'),
              _buildStep(
                '2',
                'Create your own family or wait for an invitation',
              ),
              _buildStep('3', 'Start sharing photos and messages!'),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: const Text('Got it!'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper to build step widgets
  static Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              color: Colors.blue,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }

  // Fallback dialog
  static void _showNavigationHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.family_restroom, color: Colors.blue),
                SizedBox(width: 8),
                Text('Get Started with Families'),
              ],
            ),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'To create or join a family and start sharing messages:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 12),
                Text('1. Tap the "Family" tab at the bottom of the screen'),
                SizedBox(height: 8),
                Text('2. Create your own family or wait for an invitation'),
                SizedBox(height: 8),
                Text('3. Start sharing photos and messages!'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it!'),
              ),
            ],
          ),
    );
  }

  // Help dialog
  static void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('How to Share Messages'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Tap the + button to attach photos or videos'),
                SizedBox(height: 8),
                Text('• Type your message in the text field'),
                SizedBox(height: 8),
                Text('• Tap send to share with your family'),
                SizedBox(height: 8),
                Text('• Long press messages to like or favorite them'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it!'),
              ),
            ],
          ),
    );
  }

  // Invitation help dialog
  static void _showInvitationHelp(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('About Family Invitations'),
            content: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Only family owners can send invitations'),
                SizedBox(height: 8),
                Text('• Invitations are sent by email address'),
                SizedBox(height: 8),
                Text('• You can join multiple families as a member'),
                SizedBox(height: 8),
                Text('• But you can only own/create one family'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Understood'),
              ),
            ],
          ),
    );
  }
}

class MessageCard extends StatefulWidget {
  final Message message;
  final ApiService apiService;
  final void Function(Message)? onTap;
  final String? timeText;
  final String? dayText;
  final bool shouldShowDateSeparator;
  final String? dateSeparatorText;
  final String? currentUserId;
  final void Function(Message)? onThreadTap;
  final String? currentlyPlayingVideoId;
  final bool suppressDateSeparator;
  final bool showCommentIcon;
  final String? parentId;
  final bool isThreadView;

  const MessageCard({
    Key? key,
    required this.message,
    required this.apiService,
    this.onTap,
    this.timeText,
    this.dayText,
    this.shouldShowDateSeparator = false,
    this.dateSeparatorText,
    this.currentUserId,
    this.onThreadTap,
    this.currentlyPlayingVideoId,
    this.suppressDateSeparator = false,
    this.showCommentIcon = true,
    this.parentId,
    this.isThreadView = false,
  }) : super(key: key);

  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard> {
  bool isLiked = false;
  bool isLoved = false;

  @override
  void initState() {
    super.initState();
    // Initialize like state from the message
    isLiked = widget.message.isLiked;
    isLoved = widget.message.isLoved;
    debugPrint('Message ${widget.message.id} initial state:');
    debugPrint('- isLiked: $isLiked');
    debugPrint('- isLoved: $isLoved');
    debugPrint('- likeCount: ${widget.message.likeCount}');
    debugPrint('- loveCount: ${widget.message.loveCount}');
  }

  @override
  void didUpdateWidget(MessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update states when message changes
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.isLiked != widget.message.isLiked ||
        oldWidget.message.isLoved != widget.message.isLoved) {
      setState(() {
        isLiked = widget.message.isLiked;
        isLoved = widget.message.isLoved;
      });
    }
  }

  Future<void> _toggleLike() async {
    try {
      if (widget.message.parentMessageId == null) {
        // This is a main message
        await widget.apiService.toggleMessageLike(widget.message.id, !isLiked);
      } else {
        // This is a comment
        await widget.apiService.toggleCommentLike(widget.message.id, !isLiked);
      }
      // WebSocket will handle the UI update - no local state changes needed
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error toggling like: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update like: $e')));
    }
  }

  Future<void> _toggleLove() async {
    try {
      if (widget.message.parentMessageId == null) {
        // This is a main message
        await widget.apiService.toggleMessageLove(widget.message.id, !isLoved);
      } else {
        // This is a comment
        await widget.apiService.toggleCommentLove(widget.message.id, !isLoved);
      }
      // WebSocket will handle the UI update - no local state changes needed
    } catch (e) {
      if (!mounted) return;
      debugPrint('Error toggling love: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update love: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCurrentUser =
        widget.currentUserId != null &&
        widget.message.senderId == widget.currentUserId;
    final String displayName =
        widget.message.senderUserName ?? widget.message.senderId ?? '?';
    final String displayTime = widget.timeText ?? '';

    final String displayDay = widget.dayText ?? '';
    final String? mediaUrl = widget.message.mediaUrl;

    if (displayDay.isEmpty) {
      debugPrint('Message is null: widget.dayText = $widget.dayText');
    }

    return ValueListenableBuilder<int>(
      valueListenable: MessageViewTracker().viewedMessagesNotifier,
      builder: (context, _, __) {
        final bool isMessageViewed = MessageViewTracker().isMessageViewed(
          widget.message.id,
        );
        final bool isReadOrOwnMessage = isMessageViewed || isCurrentUser;

        // Debug logging for thread view issues
        if (isCurrentUser) {
          debugPrint(
            '🔍 READ_TRACKING: Message ${widget.message.id} is current user\'s message - treating as read (currentUserId: ${widget.currentUserId}, senderId: ${widget.message.senderId})',
          );
        }

        return VisibilityDetector(
          key: Key('message_${widget.message.id}'),
          onVisibilityChanged: (VisibilityInfo info) {
            // Don't track own messages as viewed
            if (!isCurrentUser && widget.message.id.isNotEmpty) {
              final messageId = widget.message.id;
              final viewTracker = MessageViewTracker();
              // Set the authenticated ApiService instance
              viewTracker.setApiService(widget.apiService);

              debugPrint(
                '👁️ VISIBILITY: Message $messageId visibility changed to ${(info.visibleFraction * 100).toInt()}% (isCurrentUser: $isCurrentUser)',
              );

              if (info.visibleFraction > 0) {
                // Message became visible
                viewTracker.onMessageVisible(messageId, info.visibleFraction);
              } else {
                // Message became invisible
                viewTracker.onMessageInvisible(messageId);
              }
            } else {
              if (isCurrentUser) {
                debugPrint(
                  '👁️ VISIBILITY: Skipping message ${widget.message.id} - current user\'s message',
                );
              }
            }
          },
          child: _buildMessageContent(
            context,
            isCurrentUser,
            displayName,
            displayTime,
            displayDay,
            mediaUrl,
            isReadOrOwnMessage,
          ),
        );
      },
    );
  }

  Widget _buildMessageContent(
    BuildContext context,
    bool isCurrentUser,
    String displayName,
    String displayTime,
    String displayDay,
    String? mediaUrl,
    bool isReadOrOwnMessage,
  ) {
    return Column(
      children: [
        // Message card
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Column(
            children: [
              // Main content column that will contain text row and media
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row 1: Avatar, text box, day text
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildAvatarForSender(
                        widget.message.senderPhoto,
                        displayName,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withAlpha(220),
                            borderRadius: BorderRadius.circular(12),
                            // Add left border for unread messages
                            border:
                                !isReadOrOwnMessage
                                    ? Border(
                                      left: BorderSide(
                                        color:
                                            Theme.of(context).brightness ==
                                                    Brightness.light
                                                ? Colors.indigo[800]!
                                                : Colors.white,
                                        width: 4.0,
                                      ),
                                    )
                                    : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                spreadRadius: 1,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.message.content,
                                style: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.copyWith(
                                  color:
                                      !isReadOrOwnMessage
                                          ? (Theme.of(context).brightness ==
                                                  Brightness.light
                                              ? Colors.indigo[800]!
                                              : Colors.white)
                                          : Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                  fontWeight:
                                      !isReadOrOwnMessage
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                ),
                              ),
                              if (mediaUrl != null && mediaUrl.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Center(
                                    child: SizedBox(
                                      width:
                                          MediaQuery.of(context).size.width *
                                          0.9,
                                      child: _buildMediaWidgetAligned(
                                        context,
                                        widget.apiService,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Align(
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Unread indicator dot
                            if (!isReadOrOwnMessage)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color:
                                      Theme.of(context).brightness ==
                                              Brightness.light
                                          ? Colors.indigo[800]!
                                          : Colors.white,
                                  shape: BoxShape.circle,
                                  // Add a subtle shadow to make it more visible
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 2,
                                      spreadRadius: 0.5,
                                    ),
                                  ],
                                ),
                              ),
                            Text(
                              displayDay.isNotEmpty ? displayDay : '',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Row 3: Timestamp (centered)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Center(
                      child: Text(
                        displayTime,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  // Row 4: Metrics row
                  _buildMetricsRow(
                    widget.message.commentCount ?? 0,
                    widget.message.likeCount ?? 0,
                    widget.message.loveCount ?? 0,
                    int.parse(widget.currentUserId ?? '0'),
                    widget.message.toJson(),
                    context,
                    widget.showCommentIcon,
                  ),
                ],
              ),
            ],
          ),
        ),

        // Add a divider after each message
        Divider(
          color: Colors.grey[600],
          thickness: 0.5,
          height: 1,
          indent: 16,
          endIndent: 16,
        ),
      ],
    );
  }

  Widget _buildAvatarForSender(String? senderPhoto, String displayName) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Color(displayName.hashCode | 0xFF000000),
        child:
            senderPhoto != null && senderPhoto.isNotEmpty
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl:
                        senderPhoto.startsWith('http')
                            ? senderPhoto
                            : widget.apiService.mediaBaseUrl + senderPhoto,
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    placeholder:
                        (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      return Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      );
                    },
                  ),
                )
                : Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
      ),
    );
  }

  Widget _buildMediaWidgetAligned(BuildContext context, ApiService apiService) {
    if (widget.message.mediaUrl != null &&
        widget.message.mediaType == 'cloud_video') {
      return ExternalVideoMessageCard(
        externalVideoUrl: widget.message.mediaUrl!,
        thumbnailUrl: widget.message.thumbnailUrl,
        apiService: apiService,
      );
    } else if (widget.message.mediaUrl != null &&
        widget.message.mediaUrl!.isNotEmpty) {
      if (widget.message.mediaType == 'image' ||
          widget.message.mediaType == 'photo') {
        final displayUrl =
            widget.message.mediaUrl!.startsWith('http')
                ? widget.message.mediaUrl!
                : apiService.mediaBaseUrl + widget.message.mediaUrl!;
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: CachedNetworkImage(
            imageUrl: displayUrl,
            fit: BoxFit.contain,
            width: double.infinity,
            height: 200,
            placeholder:
                (context, url) => Container(
                  color: Colors.grey[300],
                  width: double.infinity,
                  height: 200,
                  child: const Center(child: CircularProgressIndicator()),
                ),
            errorWidget: (context, url, error) {
              // Handle fake/corrupted images gracefully
              if (error.toString().contains('Invalid image data') ||
                  error.toString().contains('Image file is corrupted') ||
                  error.toString().contains('HttpException') ||
                  url.contains(
                    '15',
                  ) || // catch any suspiciously small file references
                  error.toString().toLowerCase().contains('format')) {
                // Show user-friendly message for corrupted images
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Image temporarily unavailable'),
                        duration: Duration(seconds: 2),
                        backgroundColor: Colors.orange,
                      ),
                    );
                  }
                });
              }
              // Always return the broken image icon, don't log the error
              return Container(
                color: Colors.grey[300],
                width: double.infinity,
                height: 200,
                child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey),
                ),
              );
            },
          ),
        );
      } else if (widget.message.mediaType == 'video') {
        return VideoMessageCard(
          videoUrl: widget.message.mediaUrl!,
          thumbnailUrl: widget.message.thumbnailUrl,
          apiService: apiService,
          isCurrentlyPlaying:
              widget.currentlyPlayingVideoId == widget.message.id,
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildMetricsRow(
    int commentCount,
    int likeCount,
    int loveCount,
    int currentUserId,
    Map<String, dynamic> message,
    BuildContext context,
    bool showCommentIcon,
  ) {
    final customColors = Theme.of(context).extension<CustomColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: () {
            // If this is a comment (has parentMessageId), navigate to the parent message's thread
            // If this is a root message, navigate to its own thread
            Map<String, dynamic> threadMessage = message;

            if (message['parentMessageId'] != null) {
              // This is a comment - we need to create a thread message for the parent
              threadMessage = {
                'id': message['parentMessageId'],
                'content':
                    'Original Message', // Placeholder - will be loaded in thread
                'commentCount': message['commentCount'] ?? 0,
                // Add other required fields with defaults
                'senderId': message['senderId'],
                'senderUserName': message['senderUserName'],
                'timestamp': message['timestamp'],
                'mediaType': null,
                'mediaUrl': null,
                'thumbnailUrl': null,
                'senderPhoto': message['senderPhoto'],
                'likeCount': 0,
                'loveCount': 0,
                'parentMessageId': null, // Root message has no parent
                'isLiked': false,
                'isLoved': false,
              };
              debugPrint(
                '🔍 Navigating to parent thread for comment ${message['id']} -> parent ${message['parentMessageId']}',
              );
            } else {
              debugPrint(
                '🔍 Navigating to root message thread ${message['id']}',
              );
            }

            Navigator.push(
              context,
              SlidePageRoute(
                page: ThreadScreen(
                  userId: currentUserId,
                  message: threadMessage,
                ),
              ),
            );
          },
          child: Row(
            children: [
              if (showCommentIcon)
                FutureBuilder<bool>(
                  future: CommentNotificationTracker().hasNewComments(
                    message['id'].toString(),
                    commentCount,
                  ),
                  builder: (context, snapshot) {
                    final hasNewComments = snapshot.data ?? false;
                    final Color commentColor =
                        hasNewComments
                            ? (Theme.of(context).brightness == Brightness.light
                                ? Colors.indigo[800]!
                                : Colors.white)
                            : Theme.of(context).colorScheme.onSurface;
                    final IconData commentIcon =
                        hasNewComments
                            ? Icons
                                .comment // filled = "bolder"
                            : Icons.comment_outlined; // outlined = normal

                    return Icon(commentIcon, size: 16, color: commentColor);
                  },
                ),
              const SizedBox(width: 2),
              if (showCommentIcon)
                FutureBuilder<bool>(
                  future: CommentNotificationTracker().hasNewComments(
                    message['id'].toString(),
                    commentCount,
                  ),
                  builder: (context, snapshot) {
                    final hasNewComments = snapshot.data ?? false;
                    final Color textColor =
                        hasNewComments
                            ? (Theme.of(context).brightness == Brightness.light
                                ? Colors.indigo[800]!
                                : Colors.white)
                            : Theme.of(context).colorScheme.onSurface;

                    return Text(
                      commentCount.toString(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 12,
                        color: textColor,
                        fontWeight:
                            hasNewComments
                                ? FontWeight.bold
                                : FontWeight.normal,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Heart icon with count
        Row(
          children: [
            GestureDetector(
              onTap: _toggleLike,
              child: Icon(
                isLiked ? Icons.thumb_up : Icons.thumb_up_outlined,
                size: 16,
                color: customColors.redColor,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              widget.message.likeCount.toString(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(width: 12),
        //
        Row(
          children: [
            GestureDetector(
              onTap: _toggleLove,
              child: Icon(
                isLoved ? Icons.favorite : Icons.favorite_outline,
                size: 16,
                color: customColors.redColor,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              widget.message.loveCount.toString(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 12),
            ),
          ],
        ),

        const SizedBox(width: 12),
        // Share icon (no count)
        // Share icon (no count)
        GestureDetector(
          onTap: () {
            ShareService.shareMessage(
              context,
              message,
              widget.apiService.baseUrl,
            );
          },
          child: Icon(
            Icons.share_outlined,
            size: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
