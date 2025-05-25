import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';

class ThreadScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> message;

  const ThreadScreen({Key? key, required this.userId, required this.message})
    : super(key: key);

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  late Future<List<Map<String, dynamic>>> _commentsFuture = Future.value([]);
  bool _isLoadingComments = false;
  late ApiService _apiService;

  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _apiService = Provider.of<ApiService>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _commentsFuture = Future.value([]);
    _loadComments(); // Add this line to load comments when screen opens
  }

  Future<void> _loadComments() async {
    if (mounted) {
      setState(() {
        _isLoadingComments = true;
      });
    }

    try {
      // Check if message has an ID
      final messageId = int.parse(widget.message['id'].toString());

      final response = await _apiService.getMessageComments(
        messageId,
        sortDir: 'asc', // Show oldest first
      );

      if (mounted) {
        if (response.containsKey('error')) {
          debugPrint('Error loading comments: ${response['error']}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading comments: ${response['error']}'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }

        // Get the comments list from the response
        List<dynamic> commentsList = [];
        if (response.containsKey('comments')) {
          commentsList = response['comments'] as List<dynamic>;
        }

        // Update the comments future
        _commentsFuture = Future.value(
          commentsList
              .map((comment) => comment as Map<String, dynamic>)
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('Error loading comments: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading comments: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingComments = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Stubbed method to fetch replies (fill in later)
  Future<void> _fetchReplies() async {
    // TODO: Implement API call to get comments
    // Example:
    // final replies = await ApiService().getComments(widget.message['id']);
    // setState(() { _replies = replies; });
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isNotEmpty) {
      try {
        // Get message ID and convert to int
        final messageId = int.parse(widget.message['id'].toString());

        // Post the comment using API service
        final response = await _apiService.addComment(messageId, text);

        // Check for errors
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

        // Clear the input field
        _commentController.clear();

        // Reload comments to show the new one
        _loadComments();

        // Scroll to bottom
        _scrollToBottom();
      } catch (e) {
        debugPrint('Error posting comment: $e');
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to post comment: $e')));
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = ApiService(); // Replace with Provider if needed
    final message = Message(
      id: widget.message['id'] as String,
      content: widget.message['content'] as String,
      senderId: widget.message['senderId'] as String?,
      senderUserName: widget.message['senderUserName'] as String?,
      senderPhoto: widget.message['senderPhoto'] as String?,
      mediaType: widget.message['mediaType'] as String?,
      mediaUrl: widget.message['mediaUrl'] as String?,
      thumbnailUrl: widget.message['thumbnailUrl'] as String?,
      createdAt:
          widget.message['createdAt'] != null
              ? DateTime.parse(widget.message['createdAt'] as String)
              : null,
      metrics: widget.message['metrics'] as Map<String, dynamic>?,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Conversation')),
      body: Column(
        children: [
          // Original message
          MessageCard(
            message: message,
            apiService: apiService,
            currentUserId:
                widget.userId
                    .toString(), // Convert int to String for MessageCard
            timeText: MessageService.formatTime(context, message.createdAt),
            dayText: MessageService.getShortDayName(message.createdAt),
            shouldShowDateSeparator: false,
            dateSeparatorText: null,
            onTap: (msg) {
              if (msg.mediaType == 'video') {
                // Trigger video playback if needed
                // Currently handled by VideoMessageCard
              }
            },
            onThreadTap: null, // Disable further threading
            currentlyPlayingVideoId: null, // Adjust if video playback is needed
          ),
          // Divider
          Divider(
            color: Colors.grey[600],
            thickness: 0.5,
            height: 1,
            indent: 16,
            endIndent: 16,
          ),
          // Reply list
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _commentsFuture,
              builder: (context, snapshot) {
                if (_isLoadingComments) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('No comments yet'));
                }

                return ListView.builder(
                  controller: _scrollController,
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final comment = snapshot.data![index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          (comment['user']?['username']
                                      ?.toString()
                                      .isNotEmpty ??
                                  false)
                              ? comment['user']!['username'].toString()[0]
                              : '?',
                        ),
                      ),
                      title: Text(comment['user']?['username'] ?? 'Unknown'),
                      subtitle: Text(comment['content'] ?? ''),
                      trailing: Text(
                        MessageService.formatTime(
                          context,
                          DateTime.fromMillisecondsSinceEpoch(
                            comment['createdAt'],
                          ),
                        ),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    );
                  },
                );
              },
            ),
          ), // Comment input
          Container(
            padding: const EdgeInsets.all(8.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: const InputDecoration(
                      hintText: 'Add a reply...',
                      border: InputBorder.none,
                    ),
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _commentController,
                  builder: (context, value, child) {
                    final isEnabled = value.text.trim().isNotEmpty;
                    return IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: isEnabled ? _postComment : null,
                      tooltip: 'Send Reply',
                      color:
                          isEnabled
                              ? Theme.of(context).primaryColor
                              : Colors.grey,
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Placeholder Comment model (adjust based on models/message.dart)
class Comment {
  final String id;
  final String text;
  final String? senderUserName;
  final DateTime? createdAt;

  Comment({
    required this.id,
    required this.text,
    this.senderUserName,
    this.createdAt,
  });
}
