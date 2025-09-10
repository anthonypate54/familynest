import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import '../models/message.dart';

import '../config/ui_config.dart';
import '../services/api_service.dart';
import '../services/message_service.dart';
import '../services/websocket_service.dart';
import '../utils/auth_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';

import '../services/ios_media_picker.dart';

import '../theme/app_theme.dart';
import '../widgets/gradient_background.dart';
import 'message_search_screen.dart';
import 'login_screen.dart';

import '../providers/message_provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/emoji_message_input.dart';

import '../services/video_composition_service.dart';
import '../widgets/video_composition_preview.dart';
import '../widgets/unified_send_button.dart';
import '../utils/video_thumbnail_util.dart';
import '../utils/camera_utils.dart';

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
  // Unified video composition service (replaces all individual video state)
  late VideoCompositionService _compositionService;

  bool _isLoading = true;
  bool _isFirstTimeUser = true; // Track if user is truly new
  bool _isSending = false; // Prevent duplicate message sending

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

  // Cache provider reference to avoid unsafe lookups in lifecycle methods
  MessageProvider? _cachedMessageProvider;

  // Emoji picker state (managed by reusable component)
  EmojiPickerState _emojiPickerState = const EmojiPickerState(isVisible: false);

  // Media picker protection

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Cache provider reference for safe access in lifecycle methods
    _cachedMessageProvider = Provider.of<MessageProvider>(
      context,
      listen: false,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _cachedMessageProvider != null) {
      // Only reload if we don't have messages already
      if (_cachedMessageProvider!.messages.isEmpty) {
        debugPrint(
          '🔄 MessageScreen: App resumed with no messages, reloading...',
        );
        _loadMessages(showLoading: false);
      } else {
        debugPrint(
          '📱 MessageScreen: App resumed with ${_cachedMessageProvider!.messages.length} messages, skipping reload',
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize unified composition service
    _compositionService = VideoCompositionService();
    _messageController.addListener(() {
      _isSendButtonEnabled.value = _messageController.text.trim().isNotEmpty;
    });

    // Store provider references early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    _messageProvider = Provider.of<MessageProvider>(context, listen: false);

    // Only load messages if we don't have any yet
    final messageProvider = Provider.of<MessageProvider>(
      context,
      listen: false,
    );
    if (messageProvider.messages.isEmpty) {
      debugPrint('🔄 MessageScreen: initState with no messages, loading...');
      _loadMessages();
    } else {
      debugPrint(
        '📱 MessageScreen: initState with ${messageProvider.messages.length} messages, FORCE LOADING FOR DEBUG',
      );
      _loadMessages(); // FORCE LOAD FOR DEBUG
    }
    _initializeUserAndWebSocket();
    _checkIfFirstTimeUser(); // Check if user should see welcome screen
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
      debugPrint(
        '🔄 MessageScreen: Loading messages for user ${widget.userId}',
      );
      final messages = await apiService.getUserMessages(widget.userId);
      if (mounted) {
        debugPrint('✅ MessageScreen: Loaded ${messages.length} messages');
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
      debugPrint('❌ MessageScreen: Error loading messages: $e');

      // Check if it's an authentication error
      if (e.toString().contains('403') ||
          e.toString().contains('401') ||
          e.toString().contains('Invalid token') ||
          e.toString().contains('Session expired')) {
        debugPrint('🔒 Authentication error detected, redirecting to login');
        _redirectToLogin();
        return;
      }

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

  // Redirect to login on authentication errors
  void _redirectToLogin() {
    if (!mounted) return;
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false, // Remove all previous routes
      );
    });
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
        (message) => message.id.toString() == messageId.toString(),
      );

      if (messageIndex != -1 && _scrollController.hasClients) {
        // Calculate the scroll position
        // Each message item has some height, so we need to estimate
        const estimatedItemHeight = 100.0; // Approximate height per message
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
      if (!mounted) return;
      final apiService = Provider.of<ApiService>(context, listen: false);

      // Check for DMs and messages in parallel
      final results = await Future.wait([
        apiService.getOrCreateConversation(int.parse(widget.userId)),
        apiService.getUserMessages(widget.userId),
      ]);

      if (!mounted) return;

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
      debugPrint('🔍 User took action - marked hasSeenWelcome = true');
    } catch (e) {
      debugPrint('Error marking welcome as seen: $e');
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
      final hasUnreadComments = data['has_unread_comments'] as bool?;

      if (messageId == null || commentCount == null) {
        debugPrint('⚠️ COMMENT_COUNT: Missing message ID or comment count');
        return;
      }

      debugPrint(
        '📨 COMMENT_COUNT: Updating message $messageId comment count to $commentCount (has_unread_comments: $hasUnreadComments)',
      );

      // Update message provider with new comment count and read status
      if (_messageProvider != null) {
        _messageProvider!.updateMessageCommentCount(
          messageId,
          commentCount,
          hasUnreadComments: hasUnreadComments,
        );
        debugPrint(
          '✅ COMMENT_COUNT: Updated message $messageId comment count and read status',
        );
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
    WidgetsBinding.instance.removeObserver(this);

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

    // Cleanup all resources
    _scrollController.dispose();
    _messageController.dispose();
    _isSendButtonEnabled.dispose();

    // Cleanup composition service
    _compositionService.clearComposition();
    _compositionService.dispose();

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
    // Don't show picker if we already have media
    if (_compositionService.hasMedia) {
      return;
    }

    CameraUtils.showModernMediaPicker(
      context: context,
      onCameraPressed: _openCustomCamera,
      onGalleryPressed: _openUnifiedMediaPicker,
    );
  }

  Future<void> _openUnifiedMediaPicker() async {
    final File? file = await UnifiedMediaPicker.pickMedia(
      context: context,
      type: 'media',
      onShowPicker: () => _showMediaPicker(),
    );
    if (!mounted) return;
    if (file != null) {
      final String type = CameraUtils.getMediaType(file.path);
      await _processLocalFile(file, type);
    }
  }

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

  Future<void> _openCustomCamera() async {
    final String? capturedPath = await CameraUtils.openCustomCamera(context);

    if (!mounted) return;

    if (capturedPath != null && capturedPath.isNotEmpty) {
      File file = File(capturedPath);
      debugPrint('📸 Custom camera captured: ${file.path}');

      // Determine if it's photo or video based on file extension
      String type = CameraUtils.getMediaType(file.path);

      // Process the captured file
      await _processLocalFile(file, type);
    }
  }

  Future<void> _processLocalFile(File file, String type) async {
    // Use unified composition service
    final success = await _compositionService.processLocalFile(file, type);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error processing file'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _postMessage(ApiService apiService) async {
    // Prevent duplicate sends
    if (_isSending) {
      debugPrint('⚠️ _postMessage: Already sending, ignoring duplicate tap');
      return;
    }

    final text = _messageController.text.trim();
    if (_isFirstTimeUser) {
      await _markWelcomeSeen();
    }

    setState(() {
      _isSending = true;
    });

    debugPrint('🚀 _postMessage: Starting to post message: "$text"');

    Message? newMessage;
    try {
      if (_compositionService.hasMedia) {
        final mediaInfo = _compositionService.getSelectedMediaInfo()!;
        final mediaFile = mediaInfo['file'] as File;
        final mediaType = mediaInfo['type'] as String;

        debugPrint('🚀 _postMessage: Posting message with media');

        if (mediaType == 'video') {
          // For videos: Copy to persistent storage for instant playback
          debugPrint(
            '📱 Video: Copying to persistent storage for local playback',
          );
          final String? persistentPath = await _copyVideoToPersistentStorage(
            mediaFile.path,
          );

          newMessage = await apiService.postMessage(
            int.tryParse(widget.userId) ?? 0,
            text,
            mediaPath: mediaFile.path, // Upload the original file
            mediaType: mediaType,
            localMediaPath:
                persistentPath, // Use persistent path for local playback
          );

          // Upload video in background (don't await)
          _uploadVideoInBackground(newMessage, mediaFile);
        } else {
          // For photos: Use normal upload flow
          newMessage = await apiService.postMessage(
            int.tryParse(widget.userId) ?? 0,
            text,
            mediaPath: mediaFile.path,
            mediaType: mediaType,
          );
        }

        // Clear composition after successful send
        await _compositionService.clearComposition();

        // Additional memory cleanup after posting video
        if (mediaType == 'video') {
          VideoThumbnailUtil.clearCache();
        }
      } else if (text.isNotEmpty) {
        debugPrint('🚀 _postMessage: Posting text-only message');
        newMessage = await apiService.postMessage(
          int.tryParse(widget.userId) ?? 0,
          text,
        );
      }
    } catch (e) {
      debugPrint('❌ _postMessage: Error posting message: $e');

      // Handle "no family" error specifically
      if (e.toString().contains('User is not a member of any family') ||
          e.toString().contains(
            '"error":"User is not a member of any family"',
          )) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'You need to join a family before posting messages. Go to Family Management to join or create a family.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Family Management',
                textColor: Colors.white,
                onPressed: () {
                  // Navigate to family management (tab index 3)
                  Navigator.of(context).pop(); // Go back to main app
                  // Could add navigation to family tab here if needed
                },
              ),
            ),
          );
        }
        return; // Exit early, don't process further
      }

      // Handle other errors
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post message: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return; // Exit early on any error
    } finally {
      // Always reset sending state, even on errors
      setState(() {
        _isSending = false;
      });
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
        title: const Text('Family News'),
        actions: [
          _buildConnectionStatus(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => MessageSearchScreen(
                        userId: int.parse(widget.userId),
                        isDMSearch: false, // Search family news
                      ),
                ),
              );
            },
            tooltip: 'Search Family News',
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () {
          // Dismiss keyboard when tapping outside text field (standard iOS behavior)
          FocusScope.of(context).unfocus();
          // Also dismiss emoji picker if visible
          if (_emojiPickerState.isVisible) {
            setState(() {
              _emojiPickerState = const EmojiPickerState(isVisible: false);
            });
          }
        },
        child: Stack(
          children: [
            GradientBackground(
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
                                        // Memory-safe: Only one video plays at a time
                                        debugPrint(
                                          '🎬 Playing video inline (memory-safe): ${message.id}',
                                        );
                                        setState(() {
                                          _currentlyPlayingVideoId = message.id;
                                        });
                                      }
                                    },
                                    currentlyPlayingVideoId:
                                        _currentlyPlayingVideoId,
                                    isFirstTimeUser: _isFirstTimeUser,
                                  );
                                },
                              ),
                            ),
                  ),
                  // Use unified video composition preview widget
                  VideoCompositionPreview(
                    compositionService: _compositionService,
                    onClose: () async {
                      await _compositionService.clearComposition();
                    },
                  ),
                  // Message input (using reusable component)
                  EmojiMessageInput(
                    controller: _messageController,
                    hintText: 'Type a message...',
                    onSend: () => _postMessage(apiService),
                    onMediaAttach: _showMediaPicker,
                    enabled: !_isSending,
                    mediaEnabled: !_compositionService.hasMedia,

                    isDarkMode: UIConfig.useDarkMode,
                    onEmojiPickerStateChanged: (state) {
                      setState(() {
                        _emojiPickerState = state;
                      });
                    },
                    sendButton: _buildCustomSendButton(apiService),
                  ),

                  // Emoji picker (when visible)
                  if (_emojiPickerState.isVisible)
                    _emojiPickerState.emojiPickerWidget ??
                        const SizedBox.shrink(),
                ],
              ),
            ),

            // Loading overlay for media processing
            AnimatedBuilder(
              animation: _compositionService,
              builder: (context, child) {
                if (_compositionService.isProcessingMedia) {
                  return Container(
                    color: Colors.black.withValues(alpha: 0.7),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 4,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Processing video...',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Upload video in background and update message when complete
  void _uploadVideoInBackground(Message message, File videoFile) async {
    try {
      debugPrint('🔄 Background upload starting for message ${message.id}');

      final apiService = context.read<ApiService>();
      final videoData = await apiService.uploadVideoWithThumbnail(videoFile);

      if (videoData['videoUrl'] != null && videoData['videoUrl']!.isNotEmpty) {
        debugPrint('✅ Background upload complete: ${videoData['videoUrl']}');

        // Update the message with server URL (for other users and future loads)
        final updatedMessage = message.copyWith(
          mediaUrl: videoData['videoUrl'],
          thumbnailUrl: videoData['thumbnailUrl'],
        );

        // Update the message in the provider
        if (mounted) {
          final messageProvider = context.read<MessageProvider>();
          messageProvider.updateMessage(updatedMessage);
        }

        // Clean up temporary video file after successful upload
        try {
          if (await videoFile.exists()) {
            await videoFile.delete();
            debugPrint('🧹 Temporary video file cleaned up: ${videoFile.path}');
          }
        } catch (cleanupError) {
          debugPrint(
            '⚠️ Error cleaning up temporary video file: $cleanupError',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Background upload failed: $e');
      // Video will continue to play from local file
    } finally {
      // Additional memory cleanup after background upload
      VideoThumbnailUtil.clearCache();
    }
  }

  // Note: Video cleanup is now handled by VideoCompositionService

  // Copy video to persistent storage for instant local playback
  Future<String?> _copyVideoToPersistentStorage(String originalPath) async {
    try {
      // Get the application documents directory
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String appDocPath = appDocDir.path;

      // Create sent_videos subdirectory
      final Directory sentVideosDir = Directory('$appDocPath/sent_videos');
      if (!await sentVideosDir.exists()) {
        await sentVideosDir.create(recursive: true);
      }

      // Extract timestamp from original filename to ensure matching
      String timestamp;
      final String originalFileName = originalPath.split('/').last;
      final RegExp timestampRegex = RegExp(r'(\d{13})_REC');
      final Match? match = timestampRegex.firstMatch(originalFileName);

      if (match != null) {
        timestamp = match.group(1)!;
        debugPrint('📱 Using original video timestamp: $timestamp');
      } else {
        timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        debugPrint('⚠️ Could not extract timestamp, using current: $timestamp');
      }

      final String fileName = 'video_$timestamp.mp4';
      final String persistentPath = '${sentVideosDir.path}/$fileName';

      // Copy the video file to persistent location
      final File originalFile = File(originalPath);
      final File persistentFile = await originalFile.copy(persistentPath);

      // Ensure file is fully written to disk before returning
      await persistentFile.writeAsBytes(
        await persistentFile.readAsBytes(),
        flush: true,
      );

      // Small delay to ensure Android file system has processed the file
      await Future.delayed(const Duration(milliseconds: 200));

      debugPrint('✅ Video copied to persistent storage for instant playback');

      return persistentFile.path;
    } catch (e) {
      debugPrint('❌ Error copying video to persistent storage: $e');
      return null;
    }
  }

  // Build unified send button
  Widget _buildCustomSendButton(ApiService apiService) {
    return UnifiedSendButton(
      compositionService: _compositionService,
      messageController: _messageController,
      isSending: _isSending,
      onSend: () => _postMessage(apiService),
    );
  }
}
