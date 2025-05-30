import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../widgets/video_message_card.dart';
import '../screens/thread_screen.dart';
import '../utils/page_transitions.dart';
import 'package:provider/provider.dart';
import '../providers/message_provider.dart';

class MessageService {
  static Widget buildMessageListView(
    List<Message> messages, {
    required ApiService apiService,
    ScrollController? scrollController,
    void Function(Message)? onTap,
    String? currentUserId,
    void Function(Message)? onThreadTap,
    String? currentlyPlayingVideoId,
    String? content,
    bool isThreadView = false,
  }) {
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      itemCount: messages.length,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      itemBuilder: (context, index) {
        final message = messages[index];
        // Calculate time and day
        String timeText = '';
        String dayText = '';
        String dateSeparatorText = '';
        DateTime? messageDateTime;
        if (message.createdAt != null) {
          messageDateTime = message.createdAt;
          timeText = _formatTime(context, messageDateTime);
          dayText = _getShortDayName(messageDateTime);
        }
        // Date separator logic
        bool shouldShowDateSeparator = false;
        if (index == messages.length - 1) {
          shouldShowDateSeparator = true;
        } else {
          final nextCreatedAt = messages[index + 1].createdAt;
          if (messageDateTime != null && nextCreatedAt != null) {
            if (!_isSameDay(messageDateTime, nextCreatedAt)) {
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

        return MessageCard(
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
  }) : super(key: key);

  @override
  State<MessageCard> createState() => _MessageCardState();
}

class _MessageCardState extends State<MessageCard> {
  late bool isFavorite;
  late bool isLiked;

  late int userId;

  @override
  void initState() {
    super.initState();
    isFavorite = false;
    isLiked = false;
    // Initialize metrics from message
    userId = int.tryParse(widget.message.senderId ?? '0') ?? 0;
  }

  Future<void> _toggleFavorite() async {
    try {
      setState(() {
        isFavorite = !isFavorite;
      });

      if (!widget.showCommentIcon) {
        // This is a comment
        // parentId: the id of the parent message
        // widget.message.id: the id of the comment
        final provider = Provider.of<MessageProvider>(context, listen: false);
        final parentMessage = provider.messages.firstWhere(
          (m) => m.id == widget.parentId,
        );

        final commentIndex = parentMessage.replies.indexWhere(
          (c) => c.id == widget.message.id,
        );
        if (commentIndex != -1) {
          final newLoveCount =
              (parentMessage.replies[commentIndex].loveCount ?? 0) +
              (isFavorite ? 1 : -1);
          final updatedComment = parentMessage.replies[commentIndex].copyWith(
            loveCount: newLoveCount,
          );
          final updatedReplies = List<Message>.from(parentMessage.replies)
            ..[commentIndex] = updatedComment;
          final updatedParentMessage = parentMessage.copyWith(
            replies: updatedReplies,
          );

          provider.updateMessage(updatedParentMessage);
        }

        // Call your API for comment love
        await widget.apiService.toggleCommentLove(
          widget.message.id,
          isFavorite,
        );
      } else {
        // This is a main message
        final newLoveCount =
            (widget.message.loveCount ?? 0) + (isFavorite ? 1 : -1);
        final updatedMessage = widget.message.copyWith(loveCount: newLoveCount);

        Provider.of<MessageProvider>(
          context,
          listen: false,
        ).updateMessage(updatedMessage);

        // Call your API for message love
        await widget.apiService.toggleMessageLove(
          widget.message.id,
          isFavorite,
        );
      }
    } catch (e) {
      setState(() {
        isFavorite = !isFavorite;
      });
      debugPrint('Failed to update favorite: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update favorite: $e')));
    }
  }

  Future<void> _toggleLike() async {
    try {
      setState(() {
        isLiked = !isLiked;
      });
      final newLikeCount = (widget.message.likeCount ?? 0) + (isLiked ? 1 : -1);
      final updatedMessage = widget.message.copyWith(likeCount: newLikeCount);

      Provider.of<MessageProvider>(
        context,
        listen: false,
      ).updateMessage(updatedMessage);

      if (isLiked) {
        await widget.apiService.toggleMessageLike(widget.message.id, true);
      } else {
        await widget.apiService.toggleMessageLike(widget.message.id, false);
      }
    } catch (e) {
      setState(() {
        isLiked = !isLiked;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update like: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCurrentUser =
        widget.currentUserId != null &&
        widget.message.senderId == widget.currentUserId;
    final String displayName =
        widget.message.senderUserName ?? widget.message.senderId ?? '?';
    final String initials = _getInitials(displayName);
    final String displayTime = widget.timeText ?? '';
    final String displayDay = widget.dayText ?? '';
    final String? mediaType = widget.message.mediaType;
    final String? mediaUrl = widget.message.mediaUrl;

    return Column(
      children: [
        // Date separator if needed (only before first message of a new day)
        if (!widget.suppressDateSeparator &&
            widget.shouldShowDateSeparator &&
            (widget.dateSeparatorText != null &&
                widget.dateSeparatorText!.isNotEmpty))
          // Render date separator
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
                widget.dateSeparatorText!,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),

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
                            ).colorScheme.background.withAlpha(220),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                spreadRadius: 1,
                                blurRadius: 2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: SelectableText(
                            widget.message.content,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Align(
                        alignment: Alignment.center,
                        child: Text(
                          displayDay.isNotEmpty ? displayDay : '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Row 2: Media (if present)
                  if (mediaUrl != null && mediaUrl.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Center(
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.9,
                          child: _buildMediaWidgetAligned(
                            context,
                            widget.apiService,
                          ),
                        ),
                      ),
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

  String _getInitials(String name) {
    final words = name.split(' ');
    if (words.length == 1) {
      return words[0][0].toUpperCase();
    } else if (words.length > 1) {
      return words[0][0].toUpperCase() + words[1][0].toUpperCase();
    }
    return '?';
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
        widget.message.mediaUrl!.isNotEmpty) {
      if (widget.message.mediaType == 'image' ||
          widget.message.mediaType == 'photo') {
        final displayUrl =
            widget.message.mediaUrl!.startsWith('http')
                ? widget.message.mediaUrl!
                : apiService.mediaBaseUrl + widget.message.mediaUrl!;
        debugPrint(
          '🖼️ Image URL: $displayUrl for message ${widget.message.id}',
        );
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
            errorWidget:
                (context, url, error) => Container(
                  color: Colors.grey[300],
                  width: double.infinity,
                  height: 200,
                  child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
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
            Navigator.push(
              context,
              SlidePageRoute(
                page: ThreadScreen(userId: currentUserId, message: message),
              ),
            );
          },
          child: Row(
            children: [
              if (showCommentIcon)
                Icon(
                  Icons.comment_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              const SizedBox(width: 2),
              if (showCommentIcon)
                Text(
                  commentCount.toString(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontSize: 12),
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
              likeCount.toString(),
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
              onTap: _toggleFavorite,
              child: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_outline,
                size: 16,
                color: customColors.redColor,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              loveCount.toString(),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 12),
            ),
          ],
        ),

        const SizedBox(width: 12),
        // Share icon (no count)
        Icon(
          Icons.share_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ],
    );
  }
}
