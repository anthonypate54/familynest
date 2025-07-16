import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../theme/app_theme.dart';
import '../utils/video_thumbnail_util.dart';
import '../widgets/gradient_background.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/message_provider.dart';
import '../dialogs/large_video_dialog.dart';
import '../config/app_config.dart';
import '../services/share_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MessageScreen extends StatefulWidget {
  final String userId;
  final int? scrollToMessageId;

  const MessageScreen({Key? key, required this.userId, this.scrollToMessageId})
    : super(key: key);

  @override
  State<MessageScreen> createState() => _MessageScreenState();
}

class _MessageScreenState extends State<MessageScreen>
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

  bool _isLoading = true;
  bool _isFirstTimeUser = true; // Track if user is truly new

  // --- Inline video playback for message feed ---
  String? _currentlyPlayingVideoId;

  // WebSocket state variables
  WebSocketMessageHandler? _familyMessageHandler;
  WebSocketMessageHandler? _reactionHandler;
  WebSocketMessageHandler? _commentCountHandler;
  bool _isWebSocketConnected = false;
  ConnectionStatusHandler? _connectionListener;
  WebSocketService? _webSocketService;
  MessageProvider? _messageProvider;
  int? _currentUserId;
  int? _currentFamilyId;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadMessages(showLoading: false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Add lifecycle observer
    _messageController.addListener(() {
      _isSendButtonEnabled.value = _messageController.text.trim().isNotEmpty;
    });

    // Store provider references early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _messageProvider = Provider.of<MessageProvider>(context, listen: false);

    _loadMessages();
    _initializeUserAndWebSocket();
  }

  Future<void> _initializeUserAndWebSocket() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final currentUser = await apiService.getCurrentUser();

      if (currentUser != null && mounted) {
        final userId = currentUser['userId'] as int;

        // Get user details to find family ID
        final userDetails = await apiService.getUserById(userId);
        final familyId = userDetails['familyId'] as int?;

        setState(() {
          _currentUserId = userId;
          _currentFamilyId = familyId;
        });

        debugPrint('🔍 MessageScreen: User ID: $userId, Family ID: $familyId');

        // Initialize WebSocket after getting user info
        _initWebSocket();
      }
    } catch (e) {
      debugPrint('❌ Error getting current user for WebSocket: $e');
      // Still try to initialize WebSocket even if user fetch fails
      _initWebSocket();
    }
  }

  Future<void> _loadMessages({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final messages = await apiService.getUserMessages(widget.userId);
      if (mounted) {
        // Always use setMessages - refresh should get authoritative database state
        Provider.of<MessageProvider>(
          context,
          listen: false,
        ).setMessages(messages);

        if (showLoading) {
          setState(() {
            _isLoading = false;
          });
        }

        // Scroll to specific message if requested
        if (widget.scrollToMessageId != null) {
          _scrollToMessage(widget.scrollToMessageId!);
        }
      }
    } catch (e) {
      if (mounted) {
        if (showLoading) {
          setState(() {
            _isLoading = false;
          });
        }
        if (showLoading) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
        }
      }
    }
  }

  // Method to scroll to a specific message
  void _scrollToMessage(int messageId) {
    // Wait for the next frame to ensure the list is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final messageProvider = Provider.of<MessageProvider>(
        context,
        listen: false,
      );
      final messages = messageProvider.messages;

      // Find the index of the message
      final messageIndex = messages.indexWhere(
        (message) => message.id == messageId,
      );

      if (messageIndex != -1 && _scrollController.hasClients) {
        // Calculate the scroll position
        // Each message item has some height, so we need to estimate
        final estimatedItemHeight = 100.0; // Approximate height per message
        final scrollPosition =
            (messages.length - 1 - messageIndex) * estimatedItemHeight;

        _scrollController.animateTo(
          scrollPosition,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );

        debugPrint('Scrolled to message $messageId at index $messageIndex');
      } else {
        debugPrint(
          'Message $messageId not found or scroll controller not ready',
        );
      }
    });
  }

  // Check if user is a first-time user using SharedPreferences
  Future<void> _checkIfFirstTimeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenWelcome = prefs.getBool('hasSeenWelcome') ?? false;

      if (hasSeenWelcome) {
        // User has already seen welcome or has activity - not first time
        if (mounted) {
          setState(() {
            _isFirstTimeUser = false;
          });
        }
        return;
      }

      // Check if user has any activity (DMs or messages)
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Check for DMs and messages in parallel
      final results = await Future.wait([
        apiService.getOrCreateConversation(int.parse(widget.userId)),
        apiService.getUserMessages(widget.userId),
      ]);

      final conversations = results[0] as List<dynamic>;
      final messages = results[1] as List<Message>;

      final hasActivity = conversations.isNotEmpty || messages.isNotEmpty;

      if (mounted) {
        setState(() {
          _isFirstTimeUser = !hasActivity;
        });

        // If user has activity, mark them as having seen welcome
        if (hasActivity) {
          await prefs.setBool('hasSeenWelcome', true);
          debugPrint('🔍 User has activity - marked hasSeenWelcome = true');
        } else {
          debugPrint('🔍 New user - will show welcome dialog');
        }
      }
    } catch (e) {
      debugPrint('Error checking first-time user status: $e');
      // If error, assume first-time user (safer for UX)
      if (mounted) {
        setState(() {
          _isFirstTimeUser = true;
        });
      }
    }
  }

  // Method to mark user as having seen welcome (call when they take any action)
  Future<void> _markWelcomeSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasSeenWelcome', true);
      if (mounted) {
        setState(() {
          _isFirstTimeUser = false;
        });
      }
      print('🔍 User took action - marked hasSeenWelcome = true');
    } catch (e) {
      print('Error marking welcome as seen: $e');
    }
  }

  // Initialize WebSocket for family messages
  void _initWebSocket() {
    if (_webSocketService == null) return;

    // Create message handler for family messages
    _familyMessageHandler = (Map<String, dynamic> data) {
      _handleIncomingFamilyMessage(data);
    };

    // Create reaction handler for live reaction updates only
    _reactionHandler = (Map<String, dynamic> data) {
      _handleIncomingReaction(data);
    };

    // Create dedicated comment count handler
    _commentCountHandler = (Map<String, dynamic> data) {
      _handleIncomingCommentCount(data);
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

    // Use the new simplified WebSocket subscription that handles all family memberships
    if (_currentUserId != null) {
      // Subscribe to user-specific new messages (separated from comments)
      _webSocketService!.subscribe(
        '/user/$_currentUserId/messages',
        _familyMessageHandler!,
      );
      debugPrint(
        '🔌 MessageScreen: Subscribed to /user/$_currentUserId/messages',
      );

      // Subscribe to user-specific reactions
      _webSocketService!.subscribe(
        '/user/$_currentUserId/reactions',
        _reactionHandler!,
      );
      debugPrint(
        '🔌 MessageScreen: Subscribed to /user/$_currentUserId/reactions',
      );

      // Subscribe to user-specific comment counts
      _webSocketService!.subscribe(
        '/user/$_currentUserId/comment-counts',
        _commentCountHandler!,
      );
      debugPrint(
        '🔌 MessageScreen: Subscribed to /user/$_currentUserId/comment-counts',
      );
    }

    // Listen for connection status changes
    _webSocketService!.addConnectionListener(_connectionListener!);

    // Initialize WebSocket connection if not already connected
    _webSocketService!.initialize();
  }

  // Handle incoming new messages from WebSocket
  void _handleIncomingFamilyMessage(Map<String, dynamic> data) {
    try {
      debugPrint('📨 MESSAGE: Received WebSocket message: $data');

      // Check if this is a new message type
      final messageType = data['type'] as String?;
      if (messageType != 'NEW_MESSAGE') {
        debugPrint('⚠️ MESSAGE: Not a new message, ignoring');
        return;
      }

      debugPrint('📨 MESSAGE: Message ID type: ${data['id'].runtimeType}');
      debugPrint('📨 MESSAGE: Message ID value: ${data['id']}');

      final message = Message.fromJson(data);
      debugPrint('📨 MESSAGE: Parsed message: ${message.id}');
      debugPrint(
        '📨 MESSAGE: Parsed message ID type: ${message.id.runtimeType}',
      );

      // Check if provider is available
      if (_messageProvider == null) {
        debugPrint('❌ MESSAGE: MessageProvider is null!');
        return;
      }

      // Check current messages in provider
      final currentMessages = _messageProvider!.messages;
      debugPrint(
        '📨 MESSAGE: Current message count in provider: ${currentMessages.length}',
      );

      if (currentMessages.isNotEmpty) {
        debugPrint(
          '📨 MESSAGE: First message ID in provider: ${currentMessages.first.id} (${currentMessages.first.id.runtimeType})',
        );
      }

      // Add message to provider
      _messageProvider!.addMessage(message);

      debugPrint('✅ MESSAGE: Added new message to provider');

      // Auto-scroll to show new message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e, stackTrace) {
      debugPrint('❌ MESSAGE: Error handling WebSocket message: $e');
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

      // Update message provider with new reaction data
      if (_messageProvider != null) {
        _messageProvider!.updateMessageReactions(
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

  // Handle incoming comment count updates from WebSocket
  void _handleIncomingCommentCount(Map<String, dynamic> data) {
    try {
      debugPrint('📨 COMMENT_COUNT: Received comment count update: $data');

      final messageId = data['messageId']?.toString();
      final commentCount = data['commentCount'] as int?;

      if (messageId == null || commentCount == null) {
        debugPrint('⚠️ COMMENT_COUNT: Missing message ID or comment count');
        return;
      }

      debugPrint(
        '📨 COMMENT_COUNT: Updating message $messageId comment count to $commentCount',
      );

      // Update message provider with new comment count
      if (_messageProvider != null) {
        _messageProvider!.updateMessageCommentCount(messageId, commentCount);
        debugPrint('✅ COMMENT_COUNT: Updated message $messageId comment count');
      } else {
        debugPrint('❌ COMMENT_COUNT: MessageProvider is null!');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ COMMENT_COUNT: Error handling comment count update: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  @override
  void dispose() {
    // Clean up WebSocket subscriptions
    if (_familyMessageHandler != null &&
        _webSocketService != null &&
        _currentUserId != null) {
      _webSocketService!.unsubscribe(
        '/user/$_currentUserId/messages',
        _familyMessageHandler!,
      );
    }

    if (_reactionHandler != null &&
        _webSocketService != null &&
        _currentUserId != null) {
      _webSocketService!.unsubscribe(
        '/user/$_currentUserId/reactions',
        _reactionHandler!,
      );
    }

    if (_commentCountHandler != null &&
        _webSocketService != null &&
        _currentUserId != null) {
      _webSocketService!.unsubscribe(
        '/user/$_currentUserId/comment-counts',
        _commentCountHandler!,
      );
    }

    // Clean up connection listener
    if (_connectionListener != null && _webSocketService != null) {
      _webSocketService!.removeConnectionListener(_connectionListener!);
    }

    WidgetsBinding.instance.removeObserver(this); // Remove lifecycle observer
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
                  _pickMedia('photo');
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
                  _pickMedia('video');
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

  Future<void> _pickMedia(String type) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: type == 'photo' ? FileType.image : FileType.video,
        allowMultiple: false,
        withData: false, // Don't download large cloud files to memory
      );

      if (!mounted) return;

      if (result != null) {
        PlatformFile file = result.files.first;

        // Debug output
        debugPrint('🔍 Picked file path: ${file.path}');
        debugPrint('🔍 Picked file name: ${file.name}');
        debugPrint('🔍 Picked file size: ${file.size}');
        debugPrint('🔍 File identifier: ${file.identifier}');

        // Determine file source
        bool isCloudFile =
            file.identifier != null &&
            file.identifier!.startsWith('content://') &&
            !file.identifier!.contains('com.android.providers.media.documents');

        if (isCloudFile) {
          debugPrint('🔍 ☁️ CLOUD FILE detected (cached)');
        } else {
          debugPrint('🔍 ✅ LOCAL FILE detected');
        }

        if (type == 'video') {
          final int fileSizeBytes = file.size;
          final double fileSizeMB = fileSizeBytes / (1024 * 1024);
          debugPrint(
            '🔍 File size: ${fileSizeMB}MB, limit: ${AppConfig.maxFileUploadSizeMB}MB',
          );

          if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
            // LARGE FILE - different handling based on source
            if (isCloudFile) {
              // LARGE CLOUD FILE (cached) - handle as external video
              debugPrint('🔍 Large cloud file - handling as external video');
              await _processExternalVideo(File(file.path!));
            } else {
              // LARGE LOCAL FILE - show upload dialog
              debugPrint('🔍 Large local file - showing upload dialog');
              final action = await LargeVideoDialog.show(context, fileSizeMB);

              if (action == VideoSizeAction.chooseDifferent) {
                _showMediaPicker();
              } else if (action == VideoSizeAction.shareAsLink) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Upload your video to Google Drive or Dropbox first, then select it from there.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
                _showMediaPicker();
              }
            }
            return; // Exit early for large files
          }
        }

        // SMALL FILE (any source) - process normally
        debugPrint('🔍 Small file - processing normally');
        await _processLocalFile(File(file.path!), type);
      }
    } catch (e) {
      if (e is PlatformException && e.code == 'unknown_path') {
        // VERY LARGE CLOUD FILE - couldn't cache
        debugPrint('🔍 Very large cloud file - showing URL input dialog');
        if (!mounted) return;
        await _handleVeryLargeCloudFile('video');
      } else {
        debugPrint('Error picking media: $e');
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking media: $e'),
            duration: const Duration(seconds: 10),
          ),
        );
      }
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

      if (dialogResult != null) {
        final parts = dialogResult.split('|||');
        final userMessage = parts.length > 1 ? parts[0] : '';
        final userUrl = parts.length > 1 ? parts[1] : parts[0];

        if (ShareService.isValidVideoUrl(userUrl)) {
          try {
            final apiService = Provider.of<ApiService>(context, listen: false);
            await apiService.postMessage(
              int.tryParse(widget.userId) ?? 0,
              userMessage.isNotEmpty ? userMessage : 'Shared external video',
              videoUrl: userUrl,
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('External video shared successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            debugPrint('Error posting external video: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error sharing video: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a valid HTTPS video URL'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
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

      // Initialize Chewie controller
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
  }

  Future<void> _processExternalVideo(File file) async {
    // LARGE CLOUD FILE (cached) - we have cached file + cloud URI
    try {
      // Generate thumbnail from cached file
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path!}',
      );

      if (thumbnailFile != null) {
        debugPrint('🔍 Generated thumbnail for external video');

        // Show URL input dialog
        if (!mounted) return;
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

            // Post the external video message with thumbnail
            try {
              final apiService = Provider.of<ApiService>(
                context,
                listen: false,
              );

              Message newMessage = await apiService.postMessage(
                int.tryParse(widget.userId) ?? 0,
                userMessage.isNotEmpty
                    ? userMessage
                    : 'Shared external video', // Use user message or fallback
                mediaPath: thumbnailFile.path, // Thumbnail file path
                mediaType: 'image', // Thumbnail is an image
                videoUrl: userUrl, // External video URL
              );

              // DO NOT manually add the message here - let WebSocket handle it
              // This prevents duplication since WebSocket will broadcast to all clients
              if (!mounted) return;
              _scrollToBottom();

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
              _scrollToBottom();
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

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _postMessage(ApiService apiService) async {
    final text = _messageController.text.trim();
    if (_isFirstTimeUser) {
      await _markWelcomeSeen();
    }

    debugPrint('🚀 _postMessage: Starting to post message: "$text"');

    Message? newMessage;
    if (_selectedMediaFile != null) {
      debugPrint('🚀 _postMessage: Posting message with media');
      newMessage = await apiService.postMessage(
        int.tryParse(widget.userId) ?? 0,
        text,
        mediaPath: _selectedMediaFile!.path,
        mediaType: _selectedMediaType ?? 'photo',
      );
      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
      });
    } else if (text.isNotEmpty) {
      debugPrint('🚀 _postMessage: Posting text-only message');
      newMessage = await apiService.postMessage(
        int.tryParse(widget.userId) ?? 0,
        text,
      );
    }

    if (newMessage != null) {
      debugPrint(
        '🚀 _postMessage: Got new message back from API: ${newMessage.id}',
      );
      debugPrint('🚀 _postMessage: Message content: "${newMessage.content}"');

      // Add the message to provider immediately as fallback
      // Access provider directly instead of using stored reference
      try {
        if (mounted) {
          final messageProvider = Provider.of<MessageProvider>(
            context,
            listen: false,
          );
          messageProvider.addMessage(newMessage);
          debugPrint('✅ _postMessage: Successfully added message to provider');
        }
      } catch (e) {
        debugPrint('❌ _postMessage: Error adding message to provider: $e');
      }

      _messageController.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } else {
      debugPrint('❌ _postMessage: newMessage is null - API call failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return Scaffold(
      backgroundColor: UIConfig.useDarkMode ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        title: const Text('Messages'),
        actions: [
          _buildConnectionStatus(),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: () {
              _loadMessages(); // Manual refresh
            },
            tooltip: 'Refresh Messages',
          ),
          IconButton(
            icon: Icon(
              Icons.logout,
              color: Theme.of(context).colorScheme.onPrimary,
            ),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                        onRefresh: () async {
                          await _loadMessages();
                        },
                        child: Consumer<MessageProvider>(
                          builder: (context, messageProvider, child) {
                            return MessageService.buildMessageListView(
                              context,
                              messageProvider.messages,
                              apiService: apiService,
                              scrollController: _scrollController,
                              currentUserId: widget.userId.toString(),
                              onTap: (message) {
                                if (message.mediaType == 'video') {
                                  setState(() {
                                    _currentlyPlayingVideoId = message.id;
                                  });
                                }
                              },
                              currentlyPlayingVideoId: _currentlyPlayingVideoId,
                              isFirstTimeUser: _isFirstTimeUser,
                            );
                          },
                        ),
                      ),
            ),
            if (_selectedMediaFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child:
                    _selectedMediaType == 'photo'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child: Image.file(
                                  _selectedMediaFile!,
                                  width:
                                      MediaQuery.of(context).size.width * 0.7,
                                  height: 200,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 2,
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
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child:
                                    _chewieController != null
                                        ? Chewie(
                                          key: const ValueKey(
                                            'message-composition-video',
                                          ),
                                          controller: _chewieController!,
                                        )
                                        : _selectedVideoThumbnail != null
                                        ? Image.file(
                                          _selectedVideoThumbnail!,
                                          width:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.7,
                                          height: 200,
                                          fit: BoxFit.cover,
                                        )
                                        : Container(
                                          color: Colors.black,
                                          child: const Center(
                                            child: CircularProgressIndicator(),
                                          ),
                                        ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 2,
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
                                        _videoController?.dispose();
                                        _chewieController?.dispose();
                                        _videoController = null;
                                        _chewieController = null;
                                        _selectedVideoThumbnail = null;
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
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _showMediaPicker,
                    tooltip: 'Attach Media',
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: _isSendButtonEnabled,
                    builder: (context, isEnabled, child) {
                      return IconButton(
                        icon: const Icon(Icons.send),
                        onPressed:
                            isEnabled ? () => _postMessage(apiService) : null,
                        tooltip: 'Send Message',

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
      ),
    );
  }
}
