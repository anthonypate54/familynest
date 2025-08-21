import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../providers/message_provider.dart';
import '../providers/comment_provider.dart';
import '../models/message.dart';
import './compose_message_screen.dart';
import '../config/ui_config.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';
import '../services/websocket_service.dart';
import '../utils/auth_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../utils/video_thumbnail_util.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_config.dart';
import '../dialogs/large_video_dialog.dart';
import '../services/share_service.dart';
import '../services/cloud_file_service.dart';
// Removed comment notification tracker import (performance optimization)
import '../widgets/emoji_message_input.dart';
import '../services/ios_media_picker.dart';

class ThreadScreen extends StatefulWidget {
  final int userId;
  final Map<String, dynamic> message; // Add this

  const ThreadScreen({
    Key? key,
    required this.userId,
    required this.message, // Add this
  }) : super(key: key);

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final ValueNotifier<bool> _isSendButtonEnabled = ValueNotifier(false);
  File? _selectedMediaFile;
  String? _selectedMediaType;
  // Video preview fields for composing
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  File? _selectedVideoThumbnail;
  String? _currentlyPlayingVideoId;
  bool _isLoading = true;
  String? _error;
  bool _isSending = false; // Prevent duplicate comment sending

  // WebSocket state variables
  WebSocketMessageHandler? _commentMessageHandler;
  WebSocketMessageHandler? _reactionHandler;
  bool _isWebSocketConnected = false;
  ConnectionStatusHandler? _connectionListener;
  WebSocketService? _webSocketService;
  CommentProvider? _commentProvider;
  int? _parentMessageId;

  // Emoji picker state (managed by reusable component)
  EmojiPickerState _emojiPickerState = const EmojiPickerState(isVisible: false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reload comments when app comes back to foreground
      debugPrint('🔄 ThreadScreen: App resumed, reloading comments...');
      _loadComments(showLoading: false);
    }
  }

  @override
  void initState() {
    super.initState();

    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    _messageController.addListener(() {
      _isSendButtonEnabled.value = _messageController.text.trim().isNotEmpty;
    });

    // Store service references early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _commentProvider = Provider.of<CommentProvider>(context, listen: false);
    _parentMessageId = int.tryParse(widget.message['id'].toString());

    _loadComments();

    // Initialize WebSocket after the first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebSocket();
    });
  }

  // Initialize WebSocket for comment updates
  void _initWebSocket() {
    if (_webSocketService == null) return;

    // Create message handler for comment messages
    _commentMessageHandler = (Map<String, dynamic> data) {
      _handleIncomingCommentMessage(data);
    };

    // Create reaction handler for live reaction updates
    _reactionHandler = (Map<String, dynamic> data) {
      _handleIncomingReaction(data);
    };

    // Create connection status listener
    _connectionListener = (isConnected) {
      if (mounted) {
        // Use post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _isWebSocketConnected = isConnected;
            });
          }
        });
      }
    };

    // Subscribe to thread-specific comment topic (separated from main messages)
    _webSocketService!.subscribe(
      '/user/${widget.userId}/comments/${_parentMessageId}',
      _commentMessageHandler!,
    );
    debugPrint(
      '🔌 ThreadScreen: Subscribed to /user/${widget.userId}/comments/${_parentMessageId} for thread comments',
    );

    // Subscribe to user-specific reactions
    _webSocketService!.subscribe(
      '/user/${widget.userId}/reactions',
      _reactionHandler!,
    );
    debugPrint(
      '🔌 ThreadScreen: Subscribed to /user/${widget.userId}/reactions',
    );

    // Listen for connection status changes
    _webSocketService!.addConnectionListener(_connectionListener!);

    // Initialize WebSocket connection if not already connected
    _webSocketService!.initialize();
  }

  // Handle incoming comment messages from WebSocket
  void _handleIncomingCommentMessage(Map<String, dynamic> data) {
    try {
      debugPrint('📨 COMMENT: Received WebSocket message: $data');

      // Check if this is a comment type message
      final messageType = data['type'] as String?;
      if (messageType != 'COMMENT') {
        debugPrint('⚠️ COMMENT: Not a comment message, ignoring');
        return;
      }

      final message = Message.fromJson(data);
      debugPrint(
        '📨 COMMENT: Parsed comment: ${message.id} - "${message.content}"',
      );

      // Since we're subscribed to a thread-specific topic, we know this comment belongs to our thread
      debugPrint(
        '✅ COMMENT: Adding comment ${message.id} to thread ${_parentMessageId}',
      );

      // Add comment to provider (provider will handle duplicates)
      _commentProvider?.addComment(message);

      // Mark parent message as read since user is actively viewing the thread
      if (_parentMessageId != null) {
        final apiService = Provider.of<ApiService>(context, listen: false);
        apiService
            .markMessageAsRead(_parentMessageId!)
            .then((result) {
                          if (!result.containsKey('error')) {
              
              // Update local MessageProvider to reflect read status immediately
              final messageProvider = Provider.of<MessageProvider>(context, listen: false);
              messageProvider.markMessageAsRead(_parentMessageId!.toString());
            }
            })
            .catchError((e) {
              debugPrint('❌ THREAD: Failed to auto-mark message as read: $e');
            });
      }

      // Auto-scroll to show new comment
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e, stackTrace) {
      debugPrint('❌ COMMENT: Error handling WebSocket message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Handle incoming reaction updates from WebSocket
  void _handleIncomingReaction(Map<String, dynamic> data) {
    try {
      debugPrint('📨 REACTION: Received WebSocket reaction: $data');

      // Check if this is a reaction type
      final messageType = data['type'] as String?;
      if (messageType != 'REACTION') {
        debugPrint('⚠️ REACTION: Not a reaction, ignoring');
        return;
      }

      final targetType = data['target_type'] as String?;
      final messageId = data['id']?.toString();
      final likeCount = data['like_count'] as int?;
      final loveCount = data['love_count'] as int?;
      final isLiked = data['is_liked'] as bool?;
      final isLoved = data['is_loved'] as bool?;

      if (messageId == null) {
        debugPrint('⚠️ REACTION: Missing message ID');
        return;
      }

      debugPrint(
        '📨 REACTION: Updating $targetType $messageId - likes: $likeCount, loves: $loveCount, isLiked: $isLiked, isLoved: $isLoved',
      );

      // Update comment provider with new reaction data
      if (_commentProvider != null) {
        _commentProvider!.updateMessageReactions(
          messageId,
          likeCount: likeCount,
          loveCount: loveCount,
          isLiked: isLiked,
          isLoved: isLoved,
        );
        debugPrint('✅ REACTION: Updated message $messageId reactions');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ REACTION: Error handling WebSocket reaction: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _loadComments({bool showLoading = true}) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final commentProvider = Provider.of<CommentProvider>(
        context,
        listen: false,
      );
      final comments = await apiService.getComments(
        widget.message['id'].toString(),
      );
      if (mounted) {
        commentProvider.setComments([
          Message.fromJson(widget.message), // Add parent message at the start
          ...comments,
        ]);

        // Removed comment notification tracking (performance optimization)

        setState(() {
          _isLoading = false;
        });
        // Add scroll after loading completes
        await Future.delayed(const Duration(milliseconds: 100));
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load comments: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Clean up WebSocket subscription
    if (_commentMessageHandler != null &&
        _webSocketService != null &&
        _parentMessageId != null) {
      _webSocketService!.unsubscribe(
        '/user/${widget.userId}/comments/${_parentMessageId}',
        _commentMessageHandler!,
      );
    }

    // Clean up reaction handler subscription
    if (_reactionHandler != null && _webSocketService != null) {
      _webSocketService!.unsubscribe(
        '/user/${widget.userId}/reactions',
        _reactionHandler!,
      );
    }

    // Clean up connection listener
    if (_connectionListener != null && _webSocketService != null) {
      _webSocketService!.removeConnectionListener(_connectionListener!);
    }

    _scrollController.dispose();
    _messageController.dispose();
    _isSendButtonEnabled.dispose();
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  /// Handle logout action
  void _logout() async {
    await AuthUtils.showLogoutConfirmation(
      context,
      Provider.of<ApiService>(context, listen: false),
    );
  }

  void _showMediaPicker() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMediaFromCamera('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMediaFromCamera('video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia('video');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Unified media picker that accesses Photos AND Files
  Future<void> _pickMedia(String type) async {
    try {
      final File? file = await UnifiedMediaPicker.pickMedia(
        context: context,
        type: type,
        onShowPicker: () => _showMediaPicker(),
      );

      if (!mounted) return;

      if (file != null) {
        await _processLocalFile(file, type);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking media: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _pickMediaFromCamera(String type) async {
    try {
      XFile? pickedFile;

      if (type == 'photo') {
        pickedFile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1920,
          maxHeight: 1920,
        );
      } else if (type == 'video') {
        pickedFile = await ImagePicker().pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 5),
        );
      }

      if (!mounted) return;

      if (pickedFile != null) {
        File file = File(pickedFile.path);
        debugPrint('📸 Camera ${type} captured: ${file.path}');

        // Process the captured file
        await _processLocalFile(file, type);
      }
    } catch (e) {
      debugPrint('Error capturing ${type} with camera: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error accessing camera: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _processLocalFile(File file, String type) async {
    // Dispose previous controllers
    _videoController?.dispose();
    _chewieController?.dispose();
    _videoController = null;
    _chewieController = null;
    _selectedVideoThumbnail = null;

    if (type == 'video') {
      // Generate thumbnail
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path}',
      );
      _selectedVideoThumbnail = thumbnailFile;

      // Initialize video controller
      _videoController = VideoPlayerController.file(file);
      await _videoController!.initialize();

      // Initialize Chewie controller (same as your existing code)
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        aspectRatio: _videoController!.value.aspectRatio,
        autoPlay: false,
        looping: false,
        autoInitialize: true,
        showControls: true,
        placeholder:
            thumbnailFile != null
                ? Image.file(
                  thumbnailFile,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                )
                : Container(
                  color: Colors.black,
                  child: const Center(child: CircularProgressIndicator()),
                ),
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue,
          handleColor: Colors.blueAccent,
          backgroundColor: Colors.grey.shade700,
          bufferedColor: Colors.lightBlue.withOpacity(0.5),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              'Error: $errorMessage',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
      );
    }

    setState(() {
      _selectedMediaFile = file;
      _selectedMediaType = type;
    });

    // Auto-scroll to show the media preview
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _scrollToBottom();
      }
    });
  }

  Future<void> _processExternalVideo(File videoFile) async {
    try {
      // Generate thumbnail
      final thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${videoFile.path}',
      );
      if (thumbnailFile != null) {
        // Show URL input dialog
        final String? dialogResult = await ShareService.showVideoUrlDialog(
          context,
        );

        if (dialogResult != null && dialogResult.trim().isNotEmpty) {
          // Parse the result - format is "message|||url"
          final parts = dialogResult.split('|||');
          final userMessage = parts.length > 0 ? parts[0].trim() : '';
          final userUrl = parts.length > 1 ? parts[1].trim() : '';

          if (ShareService.isValidVideoUrl(userUrl)) {
            debugPrint('🔍 Valid URL provided: $userUrl');
            debugPrint('🔍 User message: $userMessage');

            // Post the external video message
            try {
              if (!mounted) return;
              final apiService = Provider.of<ApiService>(
                context,
                listen: false,
              );
              final commentProvider = Provider.of<CommentProvider>(
                context,
                listen: false,
              );

              Message newMessage = await apiService.postComment(
                widget.userId,
                int.parse(widget.message['id']),
                userMessage.isNotEmpty ? userMessage : 'Shared external video',
                mediaPath: thumbnailFile.path,
                mediaType: 'image',
                videoUrl: userUrl,
                familyId: widget.message['familyId'] as int?,
              );

              // Add to Provider
              commentProvider.addComment(newMessage, insertAtBeggining: true);

              // Show success message
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('External video posted successfully!'),
                  duration: Duration(seconds: 3),
                  backgroundColor: Colors.green,
                ),
              );

              // Scroll to bottom
              _scrollToBottomIfNeeded();
            } catch (e) {
              debugPrint('Error posting external video message: $e');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error posting external video: $e'),
                  duration: const Duration(seconds: 3),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } else {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Please enter a valid video URL (must start with https://)',
                ),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          debugPrint('🔍 User cancelled URL input');
        }
      } else {
        debugPrint('🔍 Failed to generate thumbnail');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate thumbnail for external video'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing external video: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing external video: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _handleVeryLargeCloudFile(String type) async {
    // VERY LARGE CLOUD FILE - no cached file available, need user URL
    if (type == 'video') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Video too large to cache. You can still share it using a direct link.',
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Show URL input dialog for very large cloud files
      final String? dialogResult = await ShareService.showVideoUrlDialog(
        context,
      );

      if (dialogResult != null && dialogResult.trim().isNotEmpty) {
        // Parse the result - format is "message|||url"
        final parts = dialogResult.split('|||');
        final userMessage = parts.isNotEmpty ? parts[0].trim() : '';
        final userUrl = parts.length > 1 ? parts[1].trim() : '';

        if (ShareService.isValidVideoUrl(userUrl)) {
          debugPrint('🔍 Very large file - Valid URL provided: $userUrl');
          debugPrint('🔍 Very large file - User message: $userMessage');

          // Post the external video message without thumbnail (very large file)
          try {
            if (!mounted) return;
            final apiService = Provider.of<ApiService>(context, listen: false);
            final commentProvider = Provider.of<CommentProvider>(
              context,
              listen: false,
            );

            Message newMessage = await apiService.postComment(
              widget.userId,
              int.parse(widget.message['id']),
              userMessage.isNotEmpty ? userMessage : 'Shared external video',
              videoUrl: userUrl,
              familyId: widget.message['familyId'] as int?,
            );

            // Add to Provider
            commentProvider.addComment(newMessage);

            // Show success message
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('External video posted successfully!'),
                duration: Duration(seconds: 3),
                backgroundColor: Colors.green,
              ),
            );

            // Scroll to bottom
            _scrollToBottomIfNeeded();
          } catch (e) {
            debugPrint('Error posting very large external video: $e');
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error posting external video: $e'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please enter a valid video URL (must start with https://)',
              ),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        debugPrint('🔍 User cancelled very large file URL input');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Photo too large to process.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _scrollToBottomIfNeeded() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onVideoTap(String messageId) {
    setState(() {
      if (_currentlyPlayingVideoId == messageId) {
        _currentlyPlayingVideoId = null; // Stop playing if already playing
      } else {
        _currentlyPlayingVideoId = messageId; // Start playing this video
      }
    });
  }

  // Build custom send button with circular progress indicator
  Widget _buildCustomSendButton() {
    return ValueListenableBuilder<bool>(
      valueListenable: _isSendButtonEnabled,
      builder: (context, hasText, child) {
        final isEnabled = !_isSending && hasText;
        final isProcessing = _isSending;

        return CircleAvatar(
          backgroundColor:
              isEnabled || isProcessing
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey.shade400,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Single progress indicator with background track
              if (isProcessing)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    value: null, // Indeterminate for now
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                  ),
                ),

              // Send icon
              IconButton(
                icon: Icon(
                  isProcessing ? Icons.upload : Icons.send,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed:
                    isEnabled
                        ? () => _postComment(
                          Provider.of<ApiService>(context, listen: false),
                        )
                        : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _postComment(ApiService apiService) async {
    // Prevent duplicate sends
    if (_isSending) {
      debugPrint('⚠️ _postComment: Already sending, ignoring duplicate tap');
      return;
    }

    final commentProvider = Provider.of<CommentProvider>(
      context,
      listen: false,
    );
    final messageProvider = Provider.of<MessageProvider>(
      context,
      listen: false,
    ); // Add this line

    final userMessage = _messageController.text.trim();
    if (userMessage.isEmpty && _selectedMediaFile == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      Message? newComment;
      if (_selectedMediaFile != null) {
        if (_selectedMediaType == 'photo') {
          newComment = await apiService.postComment(
            widget.userId,
            int.parse(widget.message['id'].toString()),
            userMessage.isNotEmpty ? userMessage : 'Shared a photo',
            mediaPath: _selectedMediaFile!.path,
            mediaType: 'image',
            familyId: widget.message['familyId'] as int?,
          );
        } else if (_selectedMediaType == 'video') {
          newComment = await apiService.postComment(
            widget.userId,
            int.parse(widget.message['id'].toString()),
            userMessage.isNotEmpty ? userMessage : 'Shared a video',
            mediaPath: _selectedMediaFile!.path,
            mediaType: 'video',
            familyId: widget.message['familyId'] as int?,
          );
        }
      } else {
        newComment = await apiService.postComment(
          widget.userId,
          int.parse(widget.message['id'].toString()),
          userMessage,
          familyId: widget.message['familyId'] as int?,
        );
      }

      if (newComment != null && mounted) {
        commentProvider.addComment(newComment);
        messageProvider.incrementCommentCount(widget.message['id'].toString());

        // Mark message as read since user just participated by posting a comment
        final messageId = int.tryParse(widget.message['id'].toString());
        if (messageId != null) {
          debugPrint(
            '### 📖 Marking message $messageId as read after posting comment',
          );
          apiService.markMessageAsRead(messageId);
        }

        _messageController.clear();
        setState(() {
          _selectedMediaFile = null;
          _selectedMediaType = null;
          _videoController?.dispose();
          _chewieController?.dispose();
          _videoController = null;
          _chewieController = null;
        });
        await Future.delayed(
          const Duration(milliseconds: 100),
        ); // Wait for UI to update

        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error posting comment: $e')));
      }
    } finally {
      // Always reset sending state, even on errors
      setState(() {
        _isSending = false;
      });
    }
  }

  // Show WebSocket connection status
  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isWebSocketConnected ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            _isWebSocketConnected ? 'Live' : 'Offline',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        title: const Text('Thread'),
        actions: [
          _buildConnectionStatus(),
          const SizedBox(width: 8),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside text field
          FocusScope.of(context).unfocus();
          // Also dismiss emoji picker if visible
          if (_emojiPickerState.isVisible) {
            setState(() {
              _emojiPickerState = const EmojiPickerState(isVisible: false);
            });
          }
        },
        child: GradientBackground(
          child: Column(
            children: [
              Expanded(
                child:
                    _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : RefreshIndicator(
                          onRefresh: () async {
                            await _loadComments();
                          },
                          child: Consumer<CommentProvider>(
                            builder: (context, commentProvider, child) {
                              if (_error != null) {
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(_error!),
                                      ElevatedButton(
                                        onPressed: _loadComments,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                );
                              }
                              return MessageService.buildMessageListView(
                                context,
                                commentProvider.comments,
                                apiService: apiService,
                                scrollController: _scrollController,
                                currentUserId: widget.userId.toString(),
                                onTap: (message) {
                                  if (message.mediaType == 'video') {
                                    _onVideoTap(message.id);
                                  }
                                },
                                currentlyPlayingVideoId:
                                    _currentlyPlayingVideoId,
                                isThreadView: true,
                                isFirstTimeUser: false,
                              );
                            },
                          ),
                        ),
              ),
              // Add back the media preview
              if (_selectedMediaFile != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child:
                      _selectedMediaType == 'photo'
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              children: [
                                Image.file(
                                  _selectedMediaFile!,
                                  width:
                                      MediaQuery.of(context).size.width * 0.7,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                                // Close button
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.black,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      splashRadius: 18,
                                      onPressed: () {
                                        setState(() {
                                          _selectedMediaFile = null;
                                          _selectedMediaType = null;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          : _selectedMediaType == 'video'
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Stack(
                              children: [
                                Container(
                                  width:
                                      MediaQuery.of(context).size.width * 0.7,
                                  height: 200,
                                  constraints: const BoxConstraints(
                                    maxHeight: 200,
                                    minHeight: 200,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxHeight: 200,
                                      minHeight: 200,
                                    ),
                                    child: ClipRect(
                                      child:
                                          _chewieController != null
                                              ? Chewie(
                                                key: const ValueKey(
                                                  'thread-composition-video',
                                                ),
                                                controller: _chewieController!,
                                              )
                                              : const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              ),
                                    ),
                                  ),
                                ),
                                // Close button
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.black,
                                        size: 18,
                                      ),
                                      padding: EdgeInsets.zero,
                                      splashRadius: 18,
                                      onPressed: () {
                                        setState(() {
                                          _selectedMediaFile = null;
                                          _selectedMediaType = null;
                                          // Clean up video controllers
                                          _videoController?.dispose();
                                          _chewieController?.dispose();
                                          _videoController = null;
                                          _chewieController = null;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              _buildMessageComposer(),

              // Emoji picker (when visible)
              if (_emojiPickerState.isVisible)
                _emojiPickerState.emojiPickerWidget ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    // Thread comment input using reusable component
    return EmojiMessageInput(
      controller: _messageController,
      hintText: 'Add a comment...',
      onSend:
          () => _postComment(Provider.of<ApiService>(context, listen: false)),
      onMediaAttach: _showMediaPicker,
      enabled: true,
      isDarkMode: Theme.of(context).brightness == Brightness.dark,
      onEmojiPickerStateChanged: (state) {
        setState(() {
          _emojiPickerState = state;
        });
      },
      sendButton: _buildCustomSendButton(),
    );
  }
}
