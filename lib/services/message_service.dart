import 'package:flutter/material.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../widgets/video_message_card.dart';

class MessageService {
  static Widget buildMessageListView(
    List<Message> messages, {
    required ApiService apiService,
    ScrollController? scrollController,
    void Function(Message)? onTap,
    String? currentUserId,
    void Function(Message)? onThreadTap,
    String? currentlyPlayingVideoId,
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
        return MessageCard(
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
        );
      },
    );
  }

  static String _formatTime(BuildContext context, DateTime? dateTime) {
    if (dateTime == null) return '';
    return TimeOfDay.fromDateTime(dateTime).format(context);
  }

  static String _getShortDayName(DateTime? dateTime) {
    if (dateTime == null) return '';
    return ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][dateTime.weekday -
        1];
  }

  static bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class MessageCard extends StatelessWidget {
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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isCurrentUser =
        currentUserId != null && message.senderId == currentUserId;
    final String displayName =
        message.senderUserName ?? message.senderId ?? '?';
    final String initials = _getInitials(displayName);
    final String displayTime = timeText ?? '';
    final String displayDay = dayText ?? '';
    final String? mediaType = message.mediaType;
    final String? mediaUrl = message.mediaUrl;
    // Metrics fallback
    final Map<String, dynamic> metrics = message.metrics ?? {};
    final int commentCount = metrics['commentCount'] ?? 0;
    final int likeCount = metrics['likeCount'] ?? 0;
    final int loveCount = metrics['loveCount'] ?? 0;
    final int laughCount = metrics['laughCount'] ?? 0;
    final int viewCount = metrics['viewCount'] ?? 0;

    return Column(
      children: [
        // Date separator if needed (only before first message of a new day)
        if (shouldShowDateSeparator &&
            (dateSeparatorText != null && dateSeparatorText!.isNotEmpty))
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
                dateSeparatorText!,
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
                      _buildAvatarForSender(message.senderPhoto, displayName),
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
                            message.content,
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
                          child: _buildMediaWidgetAligned(context, apiService),
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
                    commentCount,
                    likeCount,
                    loveCount,
                    laughCount,
                    viewCount,
                    context,
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
                            : apiService.mediaBaseUrl + senderPhoto,
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
    if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
      if (message.mediaType == 'image') {
        final displayUrl =
            message.mediaUrl!.startsWith('http')
                ? message.mediaUrl!
                : apiService.mediaBaseUrl + message.mediaUrl!;
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
      } else if (message.mediaType == 'video') {
        return VideoMessageCard(
          videoUrl: message.mediaUrl!,
          thumbnailUrl: message.thumbnailUrl,
          apiService: apiService,
          isCurrentlyPlaying: currentlyPlayingVideoId == message.id,
        );
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildMetricsRow(
    int commentCount,
    int likeCount,
    int loveCount,
    int laughCount,
    int viewCount,
    BuildContext context,
  ) {
    final customColors = Theme.of(context).extension<CustomColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Reply (comment) icon with count
        Icon(
          Icons.comment_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(width: 2),
        Text(
          commentCount.toString(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 12),
        ),
        const SizedBox(width: 12),
        // Thumbs up icon with count
        Icon(
          Icons.thumb_up_outlined,
          size: 16,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(width: 2),
        Text(
          likeCount.toString(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 12),
        ),
        const SizedBox(width: 12),
        // Heart icon with count
        Icon(Icons.favorite_outline, size: 16, color: customColors.redColor),
        const SizedBox(width: 2),
        Text(
          loveCount.toString(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 12,
            color: customColors.redColor,
          ),
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
