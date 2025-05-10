import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_styles.dart';

class MessageThreadScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> message;

  const MessageThreadScreen({
    Key? key,
    required this.apiService,
    required this.userId,
    required this.message,
  }) : super(key: key);

  @override
  _MessageThreadScreenState createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final TextEditingController _commentController = TextEditingController();
  // Initialize _commentsFuture with an empty list to avoid LateInitializationError
  Future<List<Map<String, dynamic>>> _commentsFuture = Future.value([]);
  bool _isLoadingComments = false;
  VideoPlayerController? _videoController;
  bool _isReacting = false;
  List<String> _userReactions = [];

  @override
  void initState() {
    super.initState();

    // Check if the message has a valid ID
    final bool hasValidId = widget.message['hasValidId'] == true;

    if (!hasValidId) {
      // Set empty data for invalid messages
      _commentsFuture = Future.value([]);
      debugPrint('Message does not have a valid ID, skipping API calls');

      // Show a message to the user
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Cannot load message details. This message does not have a valid ID.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }
      });
      return;
    }

    // Debug: Print message keys for troubleshooting
    debugPrint(
      'MessageThreadScreen: Message keys: ${widget.message.keys.toList().join(', ')}',
    );
    debugPrint('MessageThreadScreen: Message ID: ${widget.message['id']}');

    _loadComments();
    _loadReactions();

    // Mark message as viewed
    _markMessageAsViewed();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  // Load comments for this message
  Future<void> _loadComments() async {
    if (mounted) {
      setState(() {
        _isLoadingComments = true;
      });
    }

    try {
      // Check if message has an ID
      final messageId = widget.message['id'];
      if (messageId == null) {
        debugPrint('Error: Cannot load comments - Message ID is null');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot load comments: message ID is missing'),
              duration: Duration(seconds: 2),
            ),
          );

          // Set empty comments list
          _commentsFuture = Future.value([]);
        }
        return;
      }

      final response = await widget.apiService.getMessageComments(
        messageId,
        sortDir: 'asc', // Show oldest first
      );

      if (mounted) {
        // If response contains an error field, it means we couldn't fetch comments
        if (response.containsKey('error')) {
          debugPrint('Error loading comments: ${response['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading comments: ${response['error']}'),
              duration: const Duration(seconds: 2),
            ),
          );
          // Set empty comments list
          _commentsFuture = Future.value([]);
          return;
        }

        // Check if we have a 'comments' field in the response (new format) or 'content' (old format)
        List<dynamic> commentsList = [];
        if (response.containsKey('comments')) {
          commentsList = response['comments'] as List<dynamic>;
        } else if (response.containsKey('content')) {
          commentsList = response['content'] as List<dynamic>;
        } else {
          debugPrint('Unexpected comments response format: $response');
          // Set empty comments list for unexpected format
          _commentsFuture = Future.value([]);
          return;
        }

        debugPrint('Loaded ${commentsList.length} comments');

        // Convert dynamic list to List<Map<String, dynamic>>
        _commentsFuture = Future.value(
          commentsList
              .map((comment) => comment as Map<String, dynamic>)
              .toList(),
        );

        // Update the comment count in the message object using totalItems or totalElements
        if (response.containsKey('totalItems')) {
          widget.message['commentCount'] = response['totalItems'];
        } else if (response.containsKey('totalElements')) {
          widget.message['commentCount'] = response['totalElements'];
        }
      }
    } catch (e) {
      debugPrint('Error loading comments: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading comments: $e')));
        // Set empty comments list on error
        _commentsFuture = Future.value([]);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
      }
    }
  }

  // Helper function to format timestamp as "time ago"
  String _getTimeAgo(DateTime dateTime) {
    final Duration difference = DateTime.now().difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} year(s) ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} month(s) ago';
    } else if (difference.inDays > 7) {
      return '${(difference.inDays / 7).floor()} week(s) ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} day(s) ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour(s) ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute(s) ago';
    } else {
      return 'Just now';
    }
  }

  // Load the reactions for this message
  Future<void> _loadReactions() async {
    try {
      // Check if message has an ID
      final messageId = widget.message['id'];
      if (messageId == null) {
        debugPrint('Error: Cannot load reactions - Message ID is null');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot load reactions: message ID is missing'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      final reactionsResponse = await widget.apiService.getMessageReactions(
        messageId,
      );

      // If the response contains an error field, handle it
      if (reactionsResponse.containsKey('error')) {
        debugPrint('Error loading reactions: ${reactionsResponse['error']}');
        return;
      }

      if (mounted) {
        setState(() {
          // Extract user's reactions
          final reactions = reactionsResponse['reactions'] as List<dynamic>;
          _userReactions =
              reactions
                  .where((r) => r['userId'] == widget.userId)
                  .map((r) => r['reactionType'] as String)
                  .toList();

          // Update message with reaction counts
          final Map<String, dynamic> counts =
              reactionsResponse['counts'] as Map<String, dynamic>;
          widget.message['reactionCounts'] = counts;
        });
      }
    } catch (e) {
      debugPrint('Error loading reactions: $e');
    }
  }

  // Mark the message as viewed
  Future<void> _markMessageAsViewed() async {
    try {
      // Check if message has an ID
      final messageId = widget.message['id'];
      if (messageId == null) {
        debugPrint('Error: Cannot mark message as viewed - Message ID is null');
        return;
      }

      // Use the API service to mark the message as viewed
      final response = await widget.apiService.markMessageAsViewed(messageId);

      // If the response contains an error field, handle it
      if (response.containsKey('error')) {
        debugPrint('Error marking message as viewed: ${response['error']}');
        return;
      }

      debugPrint('Message $messageId marked as viewed');
    } catch (e) {
      debugPrint('Error marking message as viewed: $e');
    }
  }

  // Post a new comment
  Future<void> _postComment() async {
    if (_commentController.text.isEmpty) return;

    try {
      // Check if message has an ID
      final messageId = widget.message['id'];
      if (messageId == null) {
        debugPrint('Error: Cannot post comment - Message ID is null');

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot post comment: message ID is missing'),
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      final commentText = _commentController.text;

      // Clear the input field immediately for better UX
      _commentController.clear();

      // Use the API service to post the comment
      final response = await widget.apiService.addComment(
        messageId,
        commentText,
      );

      // Check if the response contains an error
      if (response.containsKey('error')) {
        debugPrint('Error posting comment: ${response['error']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting comment: ${response['error']}'),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      debugPrint('Comment posted successfully: $response');

      // Reload comments to include the new one
      _loadComments();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Comment posted successfully!'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Error posting comment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error posting comment: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Get count for a specific reaction type
  int _getReactionCount(String reactionType) {
    if (widget.message['reactionCounts'] != null) {
      try {
        // Handle any Map type safely
        final countsMap = widget.message['reactionCounts'];

        // If reactionType exists in the map, try to convert its value to an int
        if (countsMap.containsKey(reactionType)) {
          final count = countsMap[reactionType];
          if (count is int) return count;
          if (count is num) return count.toInt();
          if (count is String) return int.tryParse(count) ?? 0;
        }
      } catch (e) {
        debugPrint('Error getting reaction count: $e');
      }
    }
    return 0;
  }

  // Add a reaction to the message
  Future<void> _addReaction(String reactionType) async {
    if (_isReacting) return;

    setState(() {
      _isReacting = true;
    });

    try {
      // Check if message has an ID
      final messageId = widget.message['id'];
      if (messageId == null) {
        debugPrint('Error: Cannot add reaction - Message ID is null');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot add reaction: message ID is missing'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      // Check if user already reacted with this type
      final bool alreadyReacted = _userReactions.contains(reactionType);

      if (alreadyReacted) {
        // Remove the reaction
        final result = await widget.apiService.removeReaction(
          messageId,
          reactionType,
        );

        if (!result) {
          debugPrint('Failed to remove reaction');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to remove reaction'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            _userReactions.remove(reactionType);
          });
        }
      } else {
        // Add the reaction
        final response = await widget.apiService.addReaction(
          messageId,
          reactionType,
        );

        // If the response contains an error field, handle it
        if (response.containsKey('error')) {
          debugPrint('Error adding reaction: ${response['error']}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error adding reaction: ${response['error']}'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            _userReactions.add(reactionType);
          });
        }
      }

      // Reload reactions to get updated counts
      await _loadReactions();
    } catch (e) {
      debugPrint('Error adding reaction: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error adding reaction: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isReacting = false;
        });
      }
    }
  }

  void _handleLargeMedia(
    String mediaUrl,
    String mediaType,
    BuildContext context,
  ) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(
              mediaType == 'photo_large' ? 'Large Photo' : 'Large Video',
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This ${mediaType == 'photo_large' ? 'photo' : 'video'} exceeds the automatic loading size limit.',
                ),
                const SizedBox(height: 16),
                const Text('Options:'),
                const SizedBox(height: 8),
                const Text('• Open in browser to view full file'),
                const Text('• Download to your device'),
                const Text('• View in a media player app'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  _launchUrl(mediaUrl);
                  Navigator.of(context).pop();
                },
                child: const Text('Open in Browser'),
              ),
              if (mediaType == 'video_large')
                TextButton(
                  onPressed: () {
                    // Play video anyway
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Video player coming soon!'),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  child: const Text('Try Playing Anyway'),
                ),
              if (mediaType == 'photo_large')
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder:
                          (context) => Dialog(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                InteractiveViewer(
                                  panEnabled: true,
                                  boundaryMargin: const EdgeInsets.all(80),
                                  minScale: 0.5,
                                  maxScale: 4,
                                  child: Image.network(
                                    mediaUrl,
                                    loadingBuilder: (
                                      context,
                                      child,
                                      loadingProgress,
                                    ) {
                                      if (loadingProgress == null) return child;
                                      return Center(
                                        child: CircularProgressIndicator(
                                          value:
                                              loadingProgress
                                                          .expectedTotalBytes !=
                                                      null
                                                  ? loadingProgress
                                                          .cumulativeBytesLoaded /
                                                      loadingProgress
                                                          .expectedTotalBytes!
                                                  : null,
                                        ),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      return Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.error,
                                            color: Colors.red,
                                            size: 50,
                                          ),
                                          const SizedBox(height: 16),
                                          const Text('Error loading image'),
                                          const SizedBox(height: 8),
                                          TextButton(
                                            onPressed: () {
                                              _launchUrl(mediaUrl);
                                            },
                                            child: const Text(
                                              'Open in Browser',
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                    },
                                    child: const Text('Close'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                    );
                  },
                  child: const Text('Try Viewing Anyway'),
                ),
            ],
          ),
    );
  }

  void _launchUrl(String url) {
    // Can't directly open URLs without additional packages, so show instructions
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Open in Browser'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Media URL:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    url,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Copy this URL and open it in your browser.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photoUrl = widget.message['senderPhoto'] as String?;
    final mediaType = widget.message['mediaType'];
    final mediaUrl = widget.message['mediaUrl'];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        title: const Text('Thread'),
        titleTextStyle: AppStyles.appBarTitleStyle,
      ),
      body: Column(
        children: [
          // Scrollable content (message and comments)
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Original message card
                  Card(
                    margin: const EdgeInsets.all(8.0),
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Message header with sender info
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Profile Photo
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.blue,
                                    width: 2,
                                  ),
                                ),
                                child: ClipOval(
                                  child:
                                      photoUrl != null
                                          ? Image.network(
                                            '${widget.apiService.baseUrl}$photoUrl',
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) {
                                              return const Icon(
                                                Icons.person,
                                                color: Colors.blue,
                                              );
                                            },
                                          )
                                          : const Icon(
                                            Icons.person,
                                            color: Colors.blue,
                                          ),
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Message Content
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.message['senderUsername'],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.message.containsKey(
                                            'formattedTimestamp',
                                          )
                                          ? widget.message['formattedTimestamp']
                                          : '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Message text content
                          if (widget.message['content'].isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              widget.message['content'],
                              style: const TextStyle(fontSize: 16),
                            ),
                          ],

                          // Message media content
                          if (mediaUrl != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child:
                                  mediaType == 'photo'
                                      ? Image.network(
                                        '${widget.apiService.baseUrl}$mediaUrl',
                                        fit: BoxFit.cover,
                                        errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                        ) {
                                          return const Center(
                                            child: Icon(
                                              Icons.error,
                                              color: Colors.red,
                                            ),
                                          );
                                        },
                                      )
                                      : mediaType == 'video'
                                      ? GestureDetector(
                                        onTap: () {
                                          // Play video functionality would go here
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Video player coming soon!',
                                              ),
                                            ),
                                          );
                                        },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              height: 200,
                                              width: double.infinity,
                                              color: Colors.black,
                                              child: const Center(
                                                child: Icon(
                                                  Icons.video_library,
                                                  color: Colors.white,
                                                  size: 50,
                                                ),
                                              ),
                                            ),
                                            const Icon(
                                              Icons.play_circle_filled,
                                              color: Colors.white,
                                              size: 64,
                                            ),
                                          ],
                                        ),
                                      )
                                      : mediaType == 'photo_large' ||
                                          mediaType == 'video_large'
                                      ? GestureDetector(
                                        onTap: () {
                                          _handleLargeMedia(
                                            '${widget.apiService.baseUrl}$mediaUrl',
                                            mediaType,
                                            context,
                                          );
                                        },
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            Container(
                                              height: 120,
                                              width: double.infinity,
                                              decoration: BoxDecoration(
                                                color: Colors.grey[200],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Center(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      mediaType == 'photo_large'
                                                          ? Icons.image
                                                          : Icons.video_file,
                                                      color: Colors.grey[700],
                                                      size: 40,
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      mediaType == 'photo_large'
                                                          ? 'Large Photo (Tap to View)'
                                                          : 'Large Video (Tap to View)',
                                                      style: TextStyle(
                                                        color: Colors.grey[700],
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Size exceeds automatic loading limit',
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      : const Text('Unsupported media type'),
                            ),
                          ],

                          // Engagement metrics
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              // Comments count
                              Row(
                                children: [
                                  Icon(
                                    Icons.comment_outlined,
                                    size: 20,
                                    color: Colors.grey[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.message['commentCount']
                                            ?.toString() ??
                                        '0',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),

                              // Like/Upvote button
                              IconButton(
                                icon: const Icon(Icons.thumb_up_alt_outlined),
                                color:
                                    _userReactions.contains('LIKE')
                                        ? Colors.blue
                                        : Colors.grey,
                                onPressed: () => _addReaction('LIKE'),
                                tooltip: 'Like',
                              ),
                              // Text to show reaction count
                              Text(
                                _getReactionCount('LIKE').toString(),
                                style: TextStyle(
                                  color:
                                      _userReactions.contains('LIKE')
                                          ? Colors.blue
                                          : Colors.grey,
                                ),
                              ),

                              const SizedBox(width: 16),

                              // Heart/Love button
                              IconButton(
                                icon: const Icon(Icons.favorite_outline),
                                color:
                                    _userReactions.contains('LOVE')
                                        ? Colors.red
                                        : Colors.grey,
                                onPressed: () => _addReaction('LOVE'),
                                tooltip: 'Love',
                              ),
                              // Text to show reaction count
                              Text(
                                _getReactionCount('LOVE').toString(),
                                style: TextStyle(
                                  color:
                                      _userReactions.contains('LOVE')
                                          ? Colors.red
                                          : Colors.grey,
                                ),
                              ),

                              const SizedBox(width: 16),

                              // Laugh button
                              IconButton(
                                icon: const Icon(Icons.emoji_emotions_outlined),
                                color:
                                    _userReactions.contains('LAUGH')
                                        ? Colors.amber
                                        : Colors.grey,
                                onPressed: () => _addReaction('LAUGH'),
                                tooltip: 'Laugh',
                              ),
                              // Text to show reaction count
                              Text(
                                _getReactionCount('LAUGH').toString(),
                                style: TextStyle(
                                  color:
                                      _userReactions.contains('LAUGH')
                                          ? Colors.amber
                                          : Colors.grey,
                                ),
                              ),

                              // Views count
                              Row(
                                children: [
                                  Icon(
                                    Icons.visibility_outlined,
                                    size: 20,
                                    color: Colors.grey[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.message['viewCount']?.toString() ??
                                        '0',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ],
                              ),

                              // Share button
                              IconButton(
                                icon: Icon(
                                  Icons.share_outlined,
                                  size: 20,
                                  color: Colors.grey[700],
                                ),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Share feature coming soon!',
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Comments section divider
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      children: [
                        const Text(
                          'Comments',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const Spacer(),
                        if (_isLoadingComments)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),

                  // Comments section
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _commentsFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20.0),
                            child: CircularProgressIndicator(),
                          ),
                        );
                      }

                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Text(
                              'Error loading comments: ${snapshot.error}',
                            ),
                          ),
                        );
                      }

                      final comments = snapshot.data ?? [];

                      if (comments.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text(
                              'No comments yet. Be the first to comment!',
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: comments.length,
                        itemBuilder: (context, index) {
                          final comment = comments[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                              vertical: 4.0,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Comment author photo
                                  CircleAvatar(
                                    backgroundImage:
                                        comment['userPhoto'] != null
                                            ? NetworkImage(
                                              '${widget.apiService.baseUrl}${comment['userPhoto']}',
                                            )
                                            : null,
                                    child:
                                        comment['userPhoto'] == null
                                            ? const Icon(Icons.person)
                                            : null,
                                  ),
                                  const SizedBox(width: 12),

                                  // Comment content
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          comment['username'] ?? 'Unknown User',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(comment['content'] ?? ''),
                                        const SizedBox(height: 4),
                                        Text(
                                          comment['timestamp'] ?? '',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Comment composer
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: const Offset(0, -1),
                ),
              ],
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: Text(
                    widget.userId.toString().substring(0, 1),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Add a comment...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blue,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    onPressed: _postComment,
                    tooltip: 'Post Comment',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
