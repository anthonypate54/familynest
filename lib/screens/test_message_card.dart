import 'package:flutter/material.dart';
import '../models/message.dart';
import '../config/ui_config.dart';
import '../config/app_config.dart';
import 'package:cached_network_image/cached_network_image.dart';

class TestMessageCard extends StatelessWidget {
  final Message message;
  final VoidCallback? onTap;
  final String? timeText;
  final String? dayText;

  const TestMessageCard({
    Key? key,
    required this.message,
    this.onTap,
    this.timeText,
    this.dayText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final String displayTime =
        timeText ?? TimeOfDay.fromDateTime(now).format(context);
    final String displayDay =
        dayText ??
        ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][now.weekday - 1];
    String initials = '?';
    if (message.content.isNotEmpty) {
      final words = message.content.split(' ');
      if (words.length == 1) {
        initials = words[0][0].toUpperCase();
      } else {
        initials = words[0][0].toUpperCase() + words[1][0].toUpperCase();
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar
              Padding(
                padding: const EdgeInsets.only(right: 12.0, top: 4.0),
                child: CircleAvatar(
                  backgroundColor: Colors.blue.shade200,
                  radius: 24,
                  child: Text(
                    initials,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
              // Message card
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 8.0),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.content,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color:
                                  UIConfig.useDarkMode
                                      ? Colors.white
                                      : Colors.black,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Depth: ${message.depth}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      UIConfig.useDarkMode
                                          ? Colors.grey[300]
                                          : Colors.grey[700],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    displayTime,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          UIConfig.useDarkMode
                                              ? Colors.grey[300]
                                              : Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Day indicator outside the card, vertically centered
              Padding(
                padding: const EdgeInsets.only(left: 8.0, right: 4.0),
                child: Text(
                  displayDay,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          if (message.mediaType == 'image' && message.mediaUrl != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child:
                        message.mediaUrl!.startsWith('assets/')
                            ? Image.asset(
                              message.mediaUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            )
                            : Image.network(
                              message.mediaUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 120,
                                  height: 120,
                                  color: Colors.grey[300],
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey[700],
                                  ),
                                );
                              },
                            ),
                  ),
                ],
              ),
            ),
          if (message.mediaType == 'video')
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Container(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: onTap,
                      child: Container(
                        width: MediaQuery.of(context).size.width * 0.7,
                        height: 200,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          border: Border.all(
                            color: Colors.red,
                            width: 2,
                          ), // Debug border
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              message.effectiveThumbnailUrl != null &&
                                      message.effectiveThumbnailUrl!.isNotEmpty
                                  ? CachedNetworkImage(
                                    imageUrl:
                                        message.effectiveThumbnailUrl!
                                                .startsWith('http')
                                            ? message.effectiveThumbnailUrl!
                                            : AppConfig().baseUrl +
                                                message.effectiveThumbnailUrl!,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    placeholder:
                                        (context, url) => Container(
                                          color: Colors.black54,
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                                    errorWidget:
                                        (context, url, error) => Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade800,
                                            shape: BoxShape.circle,
                                          ),
                                          padding: const EdgeInsets.all(16),
                                          child: const Icon(
                                            Icons.videocam,
                                            color: Colors.white,
                                            size: 40,
                                          ),
                                        ),
                                  )
                                  : Container(
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade800,
                                      shape: BoxShape.circle,
                                    ),
                                    padding: const EdgeInsets.all(16),
                                    child: const Icon(
                                      Icons.videocam,
                                      color: Colors.white,
                                      size: 40,
                                    ),
                                  ),
                              // Play icon overlay
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.black38,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(8),
                                child: const Icon(
                                  Icons.play_arrow,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(
              left: 50.0,
              right: 50.0,
              top: 0.0,
              bottom: 12.0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.comment_outlined,
                  size: 16,
                  color:
                      UIConfig.useDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
                const SizedBox(width: 4),
                Text(
                  '3',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        UIConfig.useDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.thumb_up_alt_outlined,
                  size: 16,
                  color:
                      UIConfig.useDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
                const SizedBox(width: 4),
                Text(
                  '7',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        UIConfig.useDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.favorite_border,
                  size: 16,
                  color:
                      UIConfig.useDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
                const SizedBox(width: 4),
                Text(
                  '2',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        UIConfig.useDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.visibility_outlined,
                  size: 16,
                  color:
                      UIConfig.useDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
                const SizedBox(width: 4),
                Text(
                  '15',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        UIConfig.useDarkMode
                            ? Colors.grey[300]
                            : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 16),
                Icon(
                  Icons.share,
                  size: 16,
                  color:
                      UIConfig.useDarkMode
                          ? Colors.grey[300]
                          : Colors.grey[700],
                ),
              ],
            ),
          ),
          Divider(
            color: Colors.grey[600],
            thickness: 0.5,
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
        ],
      ),
    );
  }
}
