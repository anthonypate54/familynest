import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'dart:io';
import '../services/api_service.dart';
import '../services/share_service.dart';
import '../services/dm_message_view_tracker.dart';
import '../utils/video_thumbnail_util.dart';
import '../config/app_config.dart';
import '../dialogs/large_video_dialog.dart';
import '../widgets/gradient_background.dart';
import '../widgets/video_message_card.dart';
import '../widgets/external_video_message_card.dart';
import '../theme/app_theme.dart';
import 'package:provider/provider.dart';
import '../models/dm_message.dart';
import '../providers/dm_message_provider.dart';
import '../services/websocket_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'group_management_screen.dart';
import '../screens/messages_home_screen.dart';

class DMThreadScreen extends StatefulWidget {
  final int currentUserId;
  final int otherUserId;
  final String otherUserName;
  final String? otherUserPhoto;
  final int conversationId;

  // Group chat specific fields
  final bool isGroup;
  final int? participantCount;
  final List<Map<String, dynamic>>? participants;
  final VoidCallback?
  onMarkAsRead; // Callback when conversation is marked as read

  const DMThreadScreen({
    super.key,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserPhoto,
    required this.conversationId,
    this.isGroup = false,
    this.participantCount,
    this.participants,
    this.onMarkAsRead,
  });

  @override
  State<DMThreadScreen> createState() => _DMThreadScreenState();
}

class _DMThreadScreenState extends State<DMThreadScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Remove local messages state since we'll use provider
  bool _isLoading = true;
  bool _isSending = false;

  // Media handling state variables (copied from message_screen.dart)
  File? _selectedDMMediaFile;
  String? _selectedDMMediaType;
  VideoPlayerController? _dmVideoController;
  ChewieController? _dmChewieController;
  File? _selectedDMVideoThumbnail;

  // Video playback tracking for DM messages
  int? _currentlyPlayingVideoId;

  // WebSocket state variables
  WebSocketMessageHandler? _dmMessageHandler;
  bool _isWebSocketConnected = false;
  ConnectionStatusHandler? _connectionListener;
  WebSocketService? _webSocketService;
  DMMessageProvider? _dmMessageProvider;

  @override
  void initState() {
    super.initState();
    // Store WebSocket service reference early
    _webSocketService = Provider.of<WebSocketService>(context, listen: false);
    // Store DMMessageProvider reference early
    _dmMessageProvider = Provider.of<DMMessageProvider>(context, listen: false);

    // Initialize DM message view tracker
    final apiService = Provider.of<ApiService>(context, listen: false);
    DMMessageViewTracker().setApiService(apiService);

    _loadMessages();
    // Delay WebSocket initialization until after first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initWebSocket();
    });
  }

  // Load real messages from the API
  Future<void> _loadMessages({bool showLoading = true}) async {
    debugPrint('🔄 DM: _loadMessages called (showLoading: $showLoading)');
    if (showLoading) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final response = await apiService.getDMMessages(
        conversationId: widget.conversationId,
      );

      //    debugPrint('DM: Raw response from API: $response');

      if (mounted && response != null) {
        // Extract messages from the paginated response
        final messagesJson = response['messages'];
        //      debugPrint('DM: Raw messages from response: $messagesJson');

        if (messagesJson is List) {
          final messages =
              messagesJson
                  .whereType<Map<String, dynamic>>()
                  .map((json) => DMMessage.fromJson(json))
                  .toList();
          //         debugPrint('DM: Parsed messages: $messages');

          // Update provider only
          Provider.of<DMMessageProvider>(
            context,
            listen: false,
          ).setMessages(widget.conversationId, messages);

          if (showLoading) {
            setState(() {
              _isLoading = false;
            });
          }

          // Auto-scroll to bottom if there are new messages
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottomIfNeeded();
          });

          // Mark all messages in this conversation as read
          _markConversationAsRead();
        } else {
          if (mounted) {
            setState(() {
              if (showLoading) _isLoading = false;
            });
          }
        }
      } else {
        if (mounted) {
          setState(() {
            if (showLoading) _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (showLoading) _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading messages: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    // Clean up WebSocket subscription
    if (_dmMessageHandler != null && _webSocketService != null) {
      _webSocketService!.unsubscribe(
        '/topic/dm-thread/${widget.currentUserId}',
        _dmMessageHandler!,
      );
    }

    // Clean up connection listener
    if (_connectionListener != null && _webSocketService != null) {
      _webSocketService!.removeConnectionListener(_connectionListener!);
    }

    _messageController.dispose();
    _scrollController.dispose();
    // Clean up DM media controllers
    _dmVideoController?.dispose();
    _dmChewieController?.dispose();
    super.dispose();
  }

  // Send a real message using the API
  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty && _selectedDMMediaFile == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);

      Map<String, dynamic>? result;

      if (_selectedDMMediaFile != null) {
        // Send message with media using DMController's new postMessage endpoint
        result = await apiService.sendDMMessage(
          conversationId: widget.conversationId,
          content: content,
          mediaPath: _selectedDMMediaFile!.path,
          mediaType: _selectedDMMediaType!,
        );
      } else {
        // Send text message
        result = await apiService.sendDMMessage(
          conversationId: widget.conversationId,
          content: content,
        );
      }

      if (result != null && mounted) {
        // Clear input
        _messageController.clear();
        setState(() {
          _selectedDMMediaFile = null;
          _selectedDMMediaType = null;
          _dmVideoController?.dispose();
          _dmChewieController?.dispose();
          _dmVideoController = null;
          _dmChewieController = null;
          _selectedDMVideoThumbnail = null;
        });

        // Add the message to sender's provider immediately (optimistic update)
        // WebSocket will only broadcast to the recipient, not the sender
        final sentMessage = DMMessage.fromJson(result);
        _dmMessageProvider?.addMessage(widget.conversationId, sentMessage);

        // Update the conversation list immediately with the new message
        // Call the static callback to MessagesHomeScreen
        if (MessagesHomeScreen.updateConversationWithMessage != null) {
          MessagesHomeScreen.updateConversationWithMessage!(sentMessage);
        }

        // Scroll to show the new message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0.0, // With reverse: true, 0 is the bottom (newest messages)
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message sent!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to send message'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending DM message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  // DM Media Picker Methods (copied and adapted from message_screen.dart)
  void _showDMMediaPicker() {
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
                  _pickDMMedia('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDMMedia('photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDMMedia('video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickDMMedia('video');
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickDMMedia(String type) async {
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
        debugPrint('🔍 DM: Picked file path: ${file.path}');
        debugPrint('🔍 DM: Picked file name: ${file.name}');
        debugPrint('🔍 DM: Picked file size: ${file.size}');
        debugPrint('🔍 DM: File identifier: ${file.identifier}');

        // Determine file source
        bool isCloudFile =
            file.identifier != null &&
            file.identifier!.startsWith('content://') &&
            !file.identifier!.contains('com.android.providers.media.documents');

        if (isCloudFile) {
          debugPrint('🔍 DM: ☁️ CLOUD FILE detected (cached)');
        } else {
          debugPrint('🔍 DM: ✅ LOCAL FILE detected');
        }

        if (type == 'video') {
          final int fileSizeBytes = file.size;
          final double fileSizeMB = fileSizeBytes / (1024 * 1024);
          debugPrint(
            '🔍 DM: File size: ${fileSizeMB}MB, limit: ${AppConfig.maxFileUploadSizeMB}MB',
          );

          if (fileSizeMB > AppConfig.maxFileUploadSizeMB) {
            // LARGE FILE - different handling based on source
            if (isCloudFile) {
              // LARGE CLOUD FILE (cached) - handle as external video
              debugPrint(
                '🔍 DM: Large cloud file - handling as external video',
              );
              await _processDMExternalVideo(File(file.path!));
            } else {
              // LARGE LOCAL FILE - show upload dialog
              debugPrint('🔍 DM: Large local file - showing upload dialog');
              final action = await LargeVideoDialog.show(context, fileSizeMB);

              if (action == VideoSizeAction.chooseDifferent) {
                _showDMMediaPicker();
              } else if (action == VideoSizeAction.shareAsLink) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Upload your video to Google Drive or Dropbox first, then select it from there.',
                    ),
                    duration: Duration(seconds: 4),
                  ),
                );
                _showDMMediaPicker();
              }
            }
            return; // Exit early for large files
          }
        }

        // SMALL FILE (any source) - process normally
        debugPrint('🔍 DM: Small file - processing normally');
        await _processDMLocalFile(File(file.path!), type);
      }
    } catch (e) {
      if (e is PlatformException && e.code == 'unknown_path') {
        // VERY LARGE CLOUD FILE - couldn't cache
        debugPrint('🔍 DM: Very large cloud file - showing URL input dialog');
        if (!mounted) return;
        await _handleDMVeryLargeCloudFile('video');
      } else {
        debugPrint('DM Error picking media: $e');
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

  Future<void> _handleDMVeryLargeCloudFile(String type) async {
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
            // Send DM message with external video URL
            if (!mounted) return;
            final apiService = Provider.of<ApiService>(context, listen: false);
            final result = await apiService.sendDMMessage(
              conversationId: widget.conversationId,
              content:
                  userMessage.isNotEmpty
                      ? userMessage
                      : 'Shared external video',
              videoUrl: userUrl,
            );

            if (result != null && mounted) {
              // Reload messages to get the latest
              await _loadMessages();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('External video shared successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            } else {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Failed to share video'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          } catch (e) {
            debugPrint('Error sharing external video in DM: $e');
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
          if (!mounted) return;
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

  Future<void> _processDMLocalFile(File file, String type) async {
    // Dispose previous controllers
    _dmVideoController?.dispose();
    _dmChewieController?.dispose();
    _dmVideoController = null;
    _dmChewieController = null;
    _selectedDMVideoThumbnail = null;

    if (type == 'video') {
      // Generate thumbnail
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path}',
      );
      _selectedDMVideoThumbnail = thumbnailFile;

      // Initialize video controller
      _dmVideoController = VideoPlayerController.file(file);
      await _dmVideoController!.initialize();

      // Initialize Chewie controller
      _dmChewieController = ChewieController(
        videoPlayerController: _dmVideoController!,
        aspectRatio: _dmVideoController!.value.aspectRatio,
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
          bufferedColor: Colors.lightBlue.withValues(alpha: 0.5),
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
      _selectedDMMediaFile = file;
      _selectedDMMediaType = type;
    });
  }

  Future<void> _processDMExternalVideo(File file) async {
    // LARGE CLOUD FILE (cached) - we have cached file + cloud URI
    try {
      // Generate thumbnail from cached file
      final File? thumbnailFile = await VideoThumbnailUtil.generateThumbnail(
        'file://${file.path}',
      );

      if (thumbnailFile != null) {
        debugPrint('🔍 DM: Generated thumbnail for external video');

        // Show URL input dialog
        if (!mounted) return;
        final String? dialogResult = await ShareService.showVideoUrlDialog(
          context,
        );

        if (dialogResult != null && dialogResult.trim().isNotEmpty) {
          // Parse the result - format is "message|||url"
          final parts = dialogResult.split('|||');
          final userMessage = parts.isNotEmpty ? parts[0].trim() : '';
          final userUrl = parts.length > 1 ? parts[1].trim() : '';

          if (ShareService.isValidVideoUrl(userUrl)) {
            debugPrint('🔍 DM: Valid URL provided: $userUrl');
            debugPrint('🔍 DM: User message: $userMessage');

            try {
              // Send DM message with external video URL and thumbnail
              if (!mounted) return;
              final apiService = Provider.of<ApiService>(
                context,
                listen: false,
              );
              final result = await apiService.sendDMMessage(
                conversationId: widget.conversationId,
                content:
                    userMessage.isNotEmpty
                        ? userMessage
                        : 'Shared external video',
                videoUrl: userUrl,
                // For external videos with thumbnails, we need to upload the thumbnail first
                mediaPath: thumbnailFile.path,
                mediaType: 'image',
              );

              if (result != null && mounted) {
                // Reload messages to get the latest
                await _loadMessages();

                // Show success message
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('External video shared successfully!'),
                    duration: Duration(seconds: 3),
                    backgroundColor: Colors.green,
                  ),
                );

                // Scroll to bottom
                _scrollToBottomIfNeeded();
              } else {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to share video'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            } catch (e) {
              debugPrint('Error sharing external video in DM: $e');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error sharing external video: $e'),
                  duration: const Duration(seconds: 3),
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
          debugPrint('🔍 DM: User cancelled URL input');
        }
      } else {
        debugPrint('🔍 DM: Failed to generate thumbnail');

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not generate thumbnail for external video'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing external video in DM: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing external video: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _scrollToBottomIfNeeded() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0, // With reverse: true, 0 is the bottom (newest messages)
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onVideoTap(int messageId) {
    setState(() {
      if (_currentlyPlayingVideoId == messageId) {
        _currentlyPlayingVideoId = null; // Stop playing if already playing
      } else {
        _currentlyPlayingVideoId = messageId; // Start playing this video
      }
    });
  }

  // Initialize WebSocket for DM messages
  void _initWebSocket() {
    if (_webSocketService == null) return;

    // Create message handler for DM messages
    _dmMessageHandler = (Map<String, dynamic> data) {
      _handleIncomingDMMessage(data);
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

    // Subscribe to DM messages for this user
    _webSocketService!.subscribe(
      '/topic/dm-thread/${widget.currentUserId}',
      _dmMessageHandler!,
    );

    // Listen for connection status changes
    _webSocketService!.addConnectionListener(_connectionListener!);

    // Initialize WebSocket connection if not already connected
    _webSocketService!.initialize();
  }

  // Handle incoming DM messages from WebSocket
  void _handleIncomingDMMessage(Map<String, dynamic> data) {
    try {
      debugPrint('📨 DM: Received WebSocket message: $data');

      // Check if this is a DM message type
      final messageType = data['type'] as String?;
      if (messageType != null && messageType != 'DM_MESSAGE') {
        debugPrint('⚠️ DM: Not a DM message, ignoring');
        return;
      }

      final message = DMMessage.fromJson(data);
      debugPrint('📨 DM: Parsed message: $message');

      // Only add message if it belongs to this conversation
      if (message.conversationId == widget.conversationId) {
        // Use stored provider reference instead of Provider.of
        _dmMessageProvider?.addMessage(widget.conversationId, message);

        debugPrint(
          '✅ DM: Added new message to conversation ${widget.conversationId}',
        );

        // Auto-scroll to show new message
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToBottomIfNeeded();
        });
      } else {
        debugPrint(
          '⚠️ DM: Message for different conversation: ${message.conversationId} vs ${widget.conversationId}',
        );
      }
    } catch (e, stackTrace) {
      debugPrint('❌ DM: Error handling WebSocket message: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  // Mark all messages in this conversation as read
  Future<void> _markConversationAsRead() async {
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      await apiService.markDMConversationAsRead(widget.conversationId);
      debugPrint('✅ DM: Marked conversation ${widget.conversationId} as read');

      // Use callback to update parent screen
      widget.onMarkAsRead?.call();
      debugPrint('✅ DM: Called onMarkAsRead callback');
    } catch (e) {
      debugPrint('❌ DM: Error marking conversation as read: $e');
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

  // Helper method to build group avatar for AppBar
  Widget _buildGroupAvatar() {
    if (widget.participants == null || widget.participants!.isEmpty) {
      // Fallback to simple group avatar
      return CircleAvatar(
        radius: 16,
        backgroundColor: Colors.deepPurple.shade400,
        child: const Icon(Icons.group, color: Colors.white, size: 16),
      );
    }

    final participants = widget.participants!;
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Special case for single participant - center it
    if (participants.length == 1) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Center(
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 1),
            ),
            child: ClipOval(
              child: _buildParticipantAvatar(
                participants[0],
                apiService,
                radius: 14,
              ),
            ),
          ),
        ),
      );
    } else {
      // Google Messages style: max 4 avatars in corners for multiple participants
      return SizedBox(
        width: 32,
        height: 32,
        child: Stack(
          children: [
            // First participant (top-left)
            if (participants.isNotEmpty)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.5),
                  ),
                  child: ClipOval(
                    child: _buildParticipantAvatar(
                      participants[0],
                      apiService,
                      radius: 8,
                    ),
                  ),
                ),
              ),
            // Second participant (bottom-right)
            if (participants.length > 1)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.5),
                  ),
                  child: ClipOval(
                    child: _buildParticipantAvatar(
                      participants[1],
                      apiService,
                      radius: 8,
                    ),
                  ),
                ),
              ),
            // Third participant (top-right)
            if (participants.length > 2)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.5),
                  ),
                  child: ClipOval(
                    child: _buildParticipantAvatar(
                      participants[2],
                      apiService,
                      radius: 8,
                    ),
                  ),
                ),
              ),
            // Fourth participant (bottom-left)
            if (participants.length > 3)
              Positioned(
                left: 0,
                bottom: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 0.5),
                  ),
                  child: ClipOval(
                    child: _buildParticipantAvatar(
                      participants[3],
                      apiService,
                      radius: 8,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
  }

  // Helper method to build participant avatar
  Widget _buildParticipantAvatar(
    Map<String, dynamic> participant,
    ApiService apiService, {
    double radius = 12,
  }) {
    final String firstName = participant['firstName'] as String? ?? '';
    final String lastName = participant['lastName'] as String? ?? '';
    final String username = participant['username'] as String? ?? '';
    final String? photoUrl = participant['photo'] as String?;

    final String initials = _getInitials(firstName, lastName, username);

    if (photoUrl != null && photoUrl.isNotEmpty) {
      final String fullUrl =
          photoUrl.startsWith('http')
              ? photoUrl
              : '${apiService.mediaBaseUrl}$photoUrl';

      return CircleAvatar(
        radius: radius,
        backgroundColor: Color(initials.hashCode | 0xFF000000),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            fit: BoxFit.cover,
            width: radius * 2,
            height: radius * 2,
            placeholder: (context, url) => const CircularProgressIndicator(),
            errorWidget: (context, url, error) {
              return Text(
                initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: radius * 0.7,
                ),
              );
            },
          ),
        ),
      );
    } else {
      final avatarColor = _getAvatarColor(initials);
      return CircleAvatar(
        radius: 16,
        backgroundColor: avatarColor,
        child: Text(
          initials.isNotEmpty ? initials[0].toUpperCase() : '?',
          style: TextStyle(
            color: _getTextColor(avatarColor),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }
  }

  // Helper method to get initials
  String _getInitials(String firstName, String lastName, String username) {
    if (firstName.isNotEmpty && lastName.isNotEmpty) {
      return '${firstName[0]}${lastName[0]}'.toUpperCase();
    } else if (firstName.isNotEmpty) {
      return firstName[0].toUpperCase();
    } else if (username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return '?';
  }

  // Google Messages-style avatar colors
  static const List<Color> _avatarColors = [
    Color(0xFFFDD835), // Yellow
    Color(0xFF8E24AA), // Purple
    Color(0xFF42A5F5), // Light blue
    Color(0xFF66BB6A), // Green
    Color(0xFFFF7043), // Orange
    Color(0xFFEC407A), // Pink
    Color(0xFF26A69A), // Teal
    Color(0xFF5C6BC0), // Indigo
  ];

  // Get avatar color based on name (consistent per user)
  Color _getAvatarColor(String name) {
    // Get first letter and map to color index (A=0, B=1, etc.)
    if (name.isEmpty) return _avatarColors[0];

    final firstLetter = name[0].toUpperCase();
    final letterIndex = firstLetter.codeUnitAt(0) - 'A'.codeUnitAt(0);

    // Map letters A-Z to our 8 colors (repeating pattern)
    final colorIndex = letterIndex % _avatarColors.length;
    return _avatarColors[colorIndex];
  }

  // Get text color based on background color
  Color _getTextColor(Color backgroundColor) {
    // Use black text for yellow, white for others
    if (backgroundColor == const Color(0xFFFDD835)) {
      // Yellow
      return Colors.black;
    }
    return Colors.white;
  }

  // Navigate to group management screen
  void _navigateToGroupManagement() {
    if (!widget.isGroup) return;

    debugPrint(
      '🔧 Navigating to group management for conversation ${widget.conversationId}',
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (context) => GroupManagementScreen(
              conversationId: widget.conversationId,
              groupName: widget.otherUserName,
              currentUserId: widget.currentUserId,
              participants: widget.participants ?? [],
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.getAppBarColor(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            widget.isGroup
                ? GestureDetector(
                  onTap: () => _navigateToGroupManagement(),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: _buildGroupAvatar(),
                  ),
                )
                : _buildAvatarForSender(
                  widget.otherUserPhoto,
                  widget.otherUserName,
                ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.isGroup) ...[
                        Icon(
                          Icons.group,
                          size: 14,
                          color: Colors.white.withOpacity(0.8),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          widget.otherUserName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    widget.isGroup
                        ? '${widget.participantCount ?? 0} members'
                        : 'Online',
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            _buildConnectionStatus(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {
              // TODO: Add menu options
            },
          ),
        ],
      ),
      body: GradientBackground(
        child: Column(
          children: [
            // Messages list
            Expanded(
              child:
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Consumer<DMMessageProvider>(
                        builder: (context, provider, child) {
                          final messages = provider.getMessages(
                            widget.conversationId,
                          );
                          return messages.isEmpty
                              ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.message_outlined,
                                      size: 64,
                                      color: Colors.white.withAlpha(179),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'No messages yet',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Start the conversation with ${widget.otherUserName}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withAlpha(204),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                              : Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withAlpha(26),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(20),
                                    topRight: Radius.circular(20),
                                  ),
                                ),
                                child: RefreshIndicator(
                                  onRefresh: () async {
                                    await _loadMessages();
                                  },
                                  child: ListView.builder(
                                    controller: _scrollController,
                                    reverse: true,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: messages.length,
                                    itemBuilder: (context, index) {
                                      final message = messages[index];
                                      return _buildMessageRow(message);
                                    },
                                  ),
                                ),
                              );
                        },
                      ),
            ),

            // Media preview (if any)
            if (_selectedDMMediaFile != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child:
                    _selectedDMMediaType == 'photo'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child: Image.file(
                                  _selectedDMMediaFile!,
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
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _selectedDMMediaFile = null;
                                          _selectedDMMediaType = null;
                                        });
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        : _selectedDMMediaType == 'video'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            children: [
                              SizedBox(
                                width: MediaQuery.of(context).size.width * 0.7,
                                height: 200,
                                child:
                                    _dmChewieController != null
                                        ? Chewie(
                                          key: const ValueKey(
                                            'dm-composition-video',
                                          ),
                                          controller: _dmChewieController!,
                                        )
                                        : _selectedDMVideoThumbnail != null
                                        ? Image.file(
                                          _selectedDMVideoThumbnail!,
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
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () {
                                        setState(() {
                                          _selectedDMMediaFile = null;
                                          _selectedDMMediaType = null;
                                          _dmVideoController?.dispose();
                                          _dmChewieController?.dispose();
                                          _dmVideoController = null;
                                          _dmChewieController = null;
                                          _selectedDMVideoThumbnail = null;
                                        });
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                        : const SizedBox.shrink(),
              ),

            // Message input
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    // Attachment button (dummy)
                    IconButton(
                      icon: const Icon(
                        Icons.add_circle_outline,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        // Use the new DM media picker
                        _showDMMediaPicker();
                      },
                    ),

                    // Text input
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(
                          color:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors
                                      .black87 // Dark text on white background in dark mode
                                  : Colors
                                      .black87, // Dark text on white background in light mode
                        ),
                        decoration: InputDecoration(
                          hintText: 'Message ${widget.otherUserName}...',
                          hintStyle: TextStyle(color: Colors.grey.shade600),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        maxLines: null,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),

                    // Send button
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor:
                          _isSending
                              ? Colors.grey.shade400
                              : Theme.of(context).colorScheme.primary,
                      child:
                          _isSending
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                              : IconButton(
                                icon: const Icon(
                                  Icons.send,
                                  color: Colors.white,
                                ),
                                onPressed: _isSending ? null : _sendMessage,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
        radius: 16,
        backgroundColor: _getAvatarColor(displayName),
        child:
            senderPhoto != null && senderPhoto.isNotEmpty
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: senderPhoto,
                    fit: BoxFit.cover,
                    width: 32,
                    height: 32,
                    placeholder:
                        (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      final avatarColor = _getAvatarColor(displayName);
                      return Text(
                        displayName.isNotEmpty
                            ? displayName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: _getTextColor(avatarColor),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                )
                : Text(
                  displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                  style: TextStyle(
                    color: _getTextColor(_getAvatarColor(displayName)),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
      ),
    );
  }

  // Build message row with sender avatar for group chats
  Widget _buildMessageRow(DMMessage message) {
    final bool isMe = message.senderId == widget.currentUserId;
    final apiService = Provider.of<ApiService>(context, listen: false);

    // For group chats, show sender avatar
    if (widget.isGroup && !isMe) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Sender avatar
            Container(
              margin: const EdgeInsets.only(right: 8, bottom: 4),
              child: _buildSenderAvatar(message, apiService),
            ),
            // Message bubble
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildMessageBubble(message),
              ),
            ),
          ],
        ),
      );
    } else {
      // For 1:1 chats or own messages, no sender avatar needed
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: _buildMessageBubble(message),
        ),
      );
    }
  }

  // Build sender avatar for group messages
  Widget _buildSenderAvatar(DMMessage message, ApiService apiService) {
    final String firstName = message.senderFirstName ?? '';
    final String lastName = message.senderLastName ?? '';
    final String username = message.senderUsername ?? '';
    final String? photoUrl = message.senderPhoto;

    final String initials = _getInitials(firstName, lastName, username);

    if (photoUrl != null && photoUrl.isNotEmpty) {
      final String fullUrl =
          photoUrl.startsWith('http')
              ? photoUrl
              : '${apiService.mediaBaseUrl}$photoUrl';

      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: fullUrl,
            fit: BoxFit.cover,
            width: 32,
            height: 32,
            placeholder:
                (context, url) => Container(
                  color: Colors.grey.shade300,
                  child: const Icon(Icons.person, size: 16, color: Colors.grey),
                ),
            errorWidget: (context, url, error) {
              return CircleAvatar(
                radius: 16,
                backgroundColor: Color(initials.hashCode | 0xFF000000),
                child: Text(
                  initials.isNotEmpty ? initials[0].toUpperCase() : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      final avatarColor = _getAvatarColor(initials);
      return CircleAvatar(
        radius: 16,
        backgroundColor: avatarColor,
        child: Text(
          initials.isNotEmpty ? initials[0].toUpperCase() : '?',
          style: TextStyle(
            color: _getTextColor(avatarColor),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      );
    }
  }

  Widget _buildMessageBubble(DMMessage message) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final int senderId = message.senderId;
    final bool isMe = senderId == widget.currentUserId;
    final String content = message.content;
    final String? mediaUrl = message.mediaUrl;
    final String? mediaType = message.mediaType;
    final String? thumbnailUrl = message.mediaThumbnail;

    // Construct full URLs for media
    final String? fullMediaUrl =
        mediaUrl != null
            ? (mediaUrl.startsWith('http')
                ? mediaUrl
                : apiService.mediaBaseUrl + mediaUrl)
            : null;
    final String? fullThumbnailUrl =
        thumbnailUrl != null
            ? (thumbnailUrl.startsWith('http')
                ? thumbnailUrl
                : apiService.mediaBaseUrl + thumbnailUrl)
            : null;
    final String senderName =
        isMe
            ? 'You'
            : '${message.senderFirstName ?? ''} ${message.senderLastName ?? ''}'
                .trim();

    // Format timestamp
    String timeString = '';
    final DateTime messageTime = message.createdAt;
    final DateTime now = DateTime.now();
    final difference = now.difference(messageTime);

    if (difference.inMinutes < 1) {
      timeString = 'now';
    } else if (difference.inMinutes < 60) {
      timeString = '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      timeString = '${difference.inHours}h ago';
    } else {
      timeString = '${difference.inDays}d ago';
    }

    // Wrap with VisibilityDetector for read tracking (only for messages from other users)
    Widget messageContent = Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (isMe)
            const Spacer(flex: 1), // Subtle push right (reduced from flex: 2)
          Flexible(
            flex: 6, // Increased from 5 to give more space to message
            child: Container(
              constraints: BoxConstraints(
                maxWidth:
                    MediaQuery.of(context).size.width *
                    0.75, // Increased from 0.6
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color:
                    isMe
                        ? (Theme.of(context).brightness == Brightness.dark
                            ? Colors
                                .grey
                                .shade700 // Muted grey for dark mode
                            : Theme.of(context).colorScheme.primary)
                        : (Theme.of(context).brightness == Brightness.dark
                            ? Theme.of(context).colorScheme.surface
                            : Colors.grey.shade200),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display media if present
                  if (fullMediaUrl != null && mediaType != null) ...[
                    if (mediaType == 'photo' || mediaType == 'image') ...[
                      GestureDetector(
                        onTap: () {
                          // TODO: Add full-screen image view
                          debugPrint('Photo tapped: $fullMediaUrl');
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: double.infinity,
                            height: 200,
                            child: Image.network(
                              fullMediaUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: double.infinity,
                                  height: 200,
                                  color: Colors.grey.shade300,
                                  child: Icon(
                                    Icons.broken_image,
                                    color: Colors.grey.shade600,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (content.isNotEmpty) const SizedBox(height: 8),
                    ] else if (mediaType == 'video' ||
                        mediaType == 'cloud_video') ...[
                      // Debug prints for video URLs
                      Builder(
                        builder: (context) {
                          debugPrint('🎥 DM Video URL: $fullMediaUrl');
                          debugPrint('🖼️ DM Thumbnail URL: $fullThumbnailUrl');
                          debugPrint('📊 DM Media Type: $mediaType');
                          return const SizedBox.shrink();
                        },
                      ),
                      mediaType == 'cloud_video'
                          ? // External video - use ExternalVideoMessageCard
                          ExternalVideoMessageCard(
                            externalVideoUrl: fullMediaUrl,
                            thumbnailUrl: fullThumbnailUrl,
                            apiService: apiService,
                          )
                          : // Local video - use VideoMessageCard
                          GestureDetector(
                            onTap: () => _onVideoTap(message.id),
                            child: VideoMessageCard(
                              videoUrl: fullMediaUrl,
                              thumbnailUrl: fullThumbnailUrl,
                              apiService: apiService,
                              isCurrentlyPlaying:
                                  _currentlyPlayingVideoId == (message.id),
                            ),
                          ),
                      if (content.isNotEmpty) const SizedBox(height: 8),
                    ],
                  ],
                  // Display text content if present
                  if (content.isNotEmpty)
                    Text(
                      content,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            (!isMe && !message.isRead)
                                ? FontWeight.bold
                                : FontWeight.normal,
                        color:
                            isMe
                                ? (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors
                                        .white // White text on grey background in dark mode
                                    : Colors
                                        .white) // White text on primary color in light mode
                                : (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87),
                      ),
                    ),
                  if (timeString.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      timeString,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isMe
                                ? Colors.white70
                                : (Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white70
                                    : Colors.grey.shade600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatarForSender(null, 'You'), // Current user avatar
          ],
        ],
      ),
    );

    // Only wrap with VisibilityDetector for messages from other users
    if (!isMe) {
      return VisibilityDetector(
        key: Key('dm_message_${message.id}'),
        onVisibilityChanged: (visibilityInfo) {
          final dmMessageId = message.id.toString();
          final visibleFraction = visibilityInfo.visibleFraction;

          // Removed excessive visibility logging to reduce console spam

          if (visibleFraction > 0) {
            DMMessageViewTracker().onMessageVisible(
              dmMessageId,
              visibleFraction,
            );
          } else {
            DMMessageViewTracker().onMessageInvisible(dmMessageId);
          }
        },
        child: messageContent,
      );
    } else {
      // For current user's messages, just return the content without tracking
      debugPrint(
        '👁️ DM_VISIBILITY: Skipping DM message ${message.id} - current user\'s message',
      );
      return messageContent;
    }
  }
}
