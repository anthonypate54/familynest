import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../services/api_service.dart';
import 'invitations_screen.dart';
import 'dart:async';
import 'package:familynest/theme/app_theme.dart';
import 'package:familynest/theme/app_styles.dart';
import '../controllers/bottom_navigation_controller.dart';
import '../utils/auth_utils.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/video_thumbnail_util.dart';
import 'package:chewie/chewie.dart';

class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final BottomNavigationController? navigationController;

  const HomeScreen({
    super.key,
    required this.apiService,
    required this.userId,
    this.navigationController,
  });

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedMediaFile;
  String? _selectedMediaType;
  VideoPlayerController? _videoController;
  // Store the local thumbnail for selected videos
  File? _selectedVideoThumbnail;
  int _lastMessageCount = 0;
  final ScrollController _scrollController = ScrollController();
  bool _isFirstLoad = true;
  Future<List<Map<String, dynamic>>>? _messagesFuture;
  Timer? _refreshTimer;
  // Store previous invitations to compare for new ones
  List<int> _previousInvitationIds = [];
  final Set<int> _userFamilyIds = {};
  // Add a list to track offline messages
  final List<Map<String, dynamic>> _offlineMessages = [];
  // Add variables to track loading state
  bool _isLoading = true;
  String? _loadError;

  // Used for AutomaticKeepAliveClientMixin
  @override
  bool get wantKeepAlive => true;

  // In-memory list of messages to avoid UI redraws
  List<Map<String, dynamic>> _messages = [];
  bool _isInitialMessagesLoaded = false;

  // Add a class-level field to cache user photo URL
  String? _cachedUserPhotoUrl;

  ChewieController? _chewieController;

  // To keep track of which video is currently playing inline
  int? _currentlyPlayingVideoId;
  VideoPlayerController? _inlineVideoController;
  ChewieController? _inlineChewieController;

  // Clean up any existing inline player when switching videos
  void _cleanupInlinePlayer() {
    if (_inlineVideoController != null) {
      _inlineVideoController!.dispose();
      _inlineVideoController = null;
    }
    if (_inlineChewieController != null) {
      _inlineChewieController!.dispose();
      _inlineChewieController = null;
    }
    _currentlyPlayingVideoId = null;
  }

  // Initialize an inline player for a specific message
  Future<void> _initializeInlinePlayer(Map<String, dynamic> message) async {
    // Clean up any existing player
    _cleanupInlinePlayer();

    // Mark this video as currently initializing
    final messageId = message['id'];
    setState(() {
      _currentlyPlayingVideoId = messageId;
    });

    final videoUrl = message['mediaUrl'].toString();
    final isLocalFile = videoUrl.startsWith('file://');

    // Get the thumbnail URL (checking both formats)
    final String thumbnailUrl =
        message['thumbnailUrl']?.toString() ??
        message['thumbnail_url']?.toString() ??
        '';

    // Check that it exists AND isn't empty
    final hasThumbnailUrl =
        (message['thumbnailUrl'] != null &&
            message['thumbnailUrl'].toString().isNotEmpty &&
            message['thumbnailUrl'].toString() != "null") ||
        (message['thumbnail_url'] != null &&
            message['thumbnail_url'].toString().isNotEmpty &&
            message['thumbnail_url'].toString() != "null");

    // Debug the thumbnail situation
    if (message['mediaType'] == 'video') {
      debugPrint('🎬 Video message: $videoUrl');
      debugPrint('🖼️ Has thumbnail? $hasThumbnailUrl');
      debugPrint('🖼️ Thumbnail URL: $thumbnailUrl');
      // Log all message keys and values for debugging
      message.forEach((key, value) {
        if (key.toLowerCase().contains('thumbnail')) {
          debugPrint('  📌 $key: $value');
        }
      });
    }

    try {
      // Create placeholder widget
      Widget buildPlaceholderWidget() {
        // Get the actual thumbnail URL (checking both camelCase and snake_case versions)
        final String thumbnailUrl =
            message['thumbnailUrl']?.toString() ??
            message['thumbnail_url']?.toString() ??
            '';

        // Use thumbnailUrl if available
        if (hasThumbnailUrl) {
          debugPrint(
            '📽️ Attempting to show thumbnail for video: $thumbnailUrl',
          );

          // For debugging: log detailed info about the thumbnail URL
          if (thumbnailUrl.isEmpty) {
            debugPrint(
              '⚠️ WARNING: thumbnailUrl is EMPTY STRING but hasThumbnailUrl is true!',
            );
          } else {
            // Try to check the validity of the URL
            bool isValidUrl =
                thumbnailUrl.startsWith('http') || thumbnailUrl.startsWith('/');
            debugPrint(
              '📊 thumbnailUrl validity check: $isValidUrl, URL: $thumbnailUrl',
            );
          }

          return CachedNetworkImage(
            imageUrl:
                thumbnailUrl.startsWith("http")
                    ? thumbnailUrl
                    : '${widget.apiService.baseUrl}$thumbnailUrl',
            width: MediaQuery.of(context).size.width * 0.8,
            height: 200,
            fit: BoxFit.cover,
            placeholder:
                (context, url) => Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      color: Colors.grey[300],
                      width: MediaQuery.of(context).size.width * 0.8,
                      height: 200,
                    ),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ),
            errorWidget: (context, url, error) {
              debugPrint('❌ Error loading thumbnail: $error for URL: $url');
              return _buildDefaultVideoPlaceholder();
            },
          );
        }

        // If no thumbnailUrl or error, use default placeholder or thumbnail file
        if (!hasThumbnailUrl) {
          // Get local thumbnail if available
          VideoThumbnailUtil.getThumbnail(videoUrl).then((thumbnailFile) {
            if (thumbnailFile != null && mounted) {
              setState(() {
                // Update the UI with the thumbnail once it's available
              });
            }
          });
        }

        // Default placeholder while waiting
        return _buildDefaultVideoPlaceholder();
      }

      // Create and initialize video controller
      if (isLocalFile) {
        final processedPath = videoUrl.replaceFirst('file://', '');
        debugPrint('Initializing local video: $processedPath');
        _inlineVideoController = VideoPlayerController.file(
          File(processedPath),
        );
      } else {
        debugPrint('Initializing network video: $videoUrl');
        _inlineVideoController = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
        );
      }

      // Initialize the controller and then create the Chewie controller
      _inlineVideoController!
          .initialize()
          .then((_) {
            if (!mounted || _currentlyPlayingVideoId != messageId) {
              _cleanupInlinePlayer();
              return;
            }

            setState(() {
              _inlineChewieController = ChewieController(
                videoPlayerController: _inlineVideoController!,
                aspectRatio:
                    _inlineVideoController!.value.aspectRatio != 0
                        ? _inlineVideoController!.value.aspectRatio
                        : 16 / 9, // Use 16:9 as fallback if ratio is 0
                autoPlay: true,
                looping: false,
                autoInitialize: true,
                showControls: true,
                allowFullScreen: false,
                allowMuting: true,
                placeholder: buildPlaceholderWidget(),
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
            });
          })
          .catchError((error) {
            debugPrint('Error initializing video: $error');
            _cleanupInlinePlayer();

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Error loading video: ${error.toString().split('\n').first}',
                  ),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          });
    } catch (e) {
      debugPrint('Error setting up video player: $e');
      _cleanupInlinePlayer();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error playing video: ${e.toString().split('\n').first}',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // Clear any previously selected media when the screen loads
    _selectedMediaFile = null;
    _selectedMediaType = null;
    if (_videoController != null) {
      _videoController!.dispose();
      _videoController = null;
    }

    // Check for family data issues that could cause messaging problems
    _checkAndFixFamilyData();

    // Cache current user photo for message avatars - this fixes the root cause
    _cacheCurrentUserPhoto();

    // Only load messages once during initial setup
    if (_messagesFuture == null) {
      _messagesFuture = _loadMessages();
      _loadInitialMessages();
    }

    // Check for invitations when the screen loads
    _checkForInvitations();

    // Set up a timer to periodically check for new invitations
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _checkForInvitations();
      }
    });
  }

  // Method to cache the current user's photo URL - fix for the root cause
  Future<void> _cacheCurrentUserPhoto() async {
    try {
      final userData = await widget.apiService.getUserById(widget.userId);
      if (!mounted) return;

      setState(() {
        // Check for both photoUrl and photo fields
        _cachedUserPhotoUrl = userData['photoUrl'] ?? userData['photo'];
      });

      debugPrint('✅ Cached user photo URL: $_cachedUserPhotoUrl');
    } catch (e) {
      debugPrint('⚠️ Error caching user photo: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This will run when the screen becomes visible again (e.g., after returning from another screen)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForInvitations();
      }
    });
  }

  Future<void> _loadInitialMessages() {
    return _messagesFuture!.then((messages) {
      if (!mounted) return;
      setState(() {
        _lastMessageCount = messages.length;
        _messages = messages;
        _isInitialMessagesLoaded = true;
        if (messages.isNotEmpty) {
          _updateRefreshTimestamp();
        }
      });

      // Check all video thumbnails after messages are loaded
      if (messages.isNotEmpty) {
        // Delay slightly to let the UI render first
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _checkAllVideoThumbnails(messages);
          }
        });
      }

      // On first load only, scroll to bottom after a delay
      if (_isFirstLoad) {
        _isFirstLoad = false;
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _scrollToBottom();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _cleanupInlinePlayer();
    _scrollController.dispose();
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
    }
    super.dispose();
  }

  // Improved scroll to bottom to show newest messages at the bottom
  void _scrollToBottom() {
    debugPrint('Scrolling to bottom to show newest messages');
    if (_scrollController.hasClients) {
      try {
        // In a reversed list, we need to scroll to minimum extent (0)
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        debugPrint('Scroll to bottom executed');
      } catch (e) {
        debugPrint('Error scrolling to bottom: $e');
      }
    } else {
      debugPrint('ScrollController has no clients, cannot scroll');
      // Schedule a scroll once the controller has clients
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          _scrollToBottom();
        }
      });
    }
  }

  // Add a method to refresh the cached photo URL
  Future<void> _refreshUserPhotoCache() async {
    try {
      debugPrint('🔄 Refreshing user photo cache');
      final userData = await widget.apiService.getUserById(widget.userId);
      if (!mounted) return;

      // Check for both photoUrl and photo fields
      final newPhotoUrl = userData['photoUrl'] ?? userData['photo'];

      // Only update if there's a change
      if (newPhotoUrl != _cachedUserPhotoUrl) {
        setState(() {
          _cachedUserPhotoUrl = newPhotoUrl;
        });

        debugPrint('✅ Updated cached photo URL: $_cachedUserPhotoUrl');
      } else {
        debugPrint('ℹ️ Photo URL unchanged, keeping current cache');
      }
    } catch (e) {
      debugPrint('⚠️ Error refreshing user photo: $e');
    }
  }

  // Modify the refresh messages function to also refresh photo cache
  Future<void> _refreshMessages({bool shouldScrollToBottom = false}) async {
    if (!mounted) return;

    debugPrint(
      'Refreshing messages (shouldScrollToBottom: $shouldScrollToBottom)',
    );
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    // Also refresh the photo cache
    await _refreshUserPhotoCache();

    try {
      final messages = await _loadMessages();
      if (!mounted) return;

      final hasNewMessages = messages.length > _lastMessageCount;

      debugPrint(
        'Refresh complete: ${messages.length} messages (previous count: $_lastMessageCount)',
      );
      if (hasNewMessages) {
        debugPrint('New messages detected during refresh');
      }

      setState(() {
        _messagesFuture = Future.value(messages);
        _messages = messages; // Update our in-memory list
        if (hasNewMessages) {
          _lastMessageCount = messages.length;
          _updateRefreshTimestamp();
        }
      });

      // Check all video thumbnails after refreshing
      if (messages.isNotEmpty) {
        // Delay slightly to let the UI render first
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) {
            _checkAllVideoThumbnails(messages);
          }
        });
      }

      if (shouldScrollToBottom || hasNewMessages) {
        // Add a small delay to ensure the ListView has rebuilt
        await Future.delayed(const Duration(milliseconds: 200));

        // Force scrolling to show newest message
        _scrollToBottom();

        // Add extra attempts with delays
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) _scrollToBottom();
        });

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _scrollToBottom();
        });

        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) _scrollToBottom();
        });
      }
    } catch (e) {
      debugPrint('Error refreshing messages: $e');
      setState(() {
        _isLoading = false;
        _loadError = e.toString();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadMessages() async {
    try {
      final response = await widget.apiService.getMessages(widget.userId);

      // Debug API response - detailed logging
      debugPrint('======== MESSAGE API RESPONSE ========');
      debugPrint('Got ${response.length} messages from server');

      if (response.isNotEmpty) {
        // Log first message as sample
        final sampleMsg = response[0];
        debugPrint('🔍 SAMPLE MESSAGE STRUCTURE:');
        debugPrint('Keys available: ${sampleMsg.keys.join(', ')}');

        // Check for sender info structure
        debugPrint('📊 SENDER INFO:');
        if (sampleMsg.containsKey('senderId')) {
          debugPrint(
            'senderId: ${sampleMsg['senderId']} (type: ${sampleMsg['senderId'].runtimeType})',
          );
        }
        if (sampleMsg.containsKey('senderUsername')) {
          debugPrint('senderUsername: ${sampleMsg['senderUsername']}');
        }
        if (sampleMsg.containsKey('senderPhoto')) {
          debugPrint('senderPhoto: ${sampleMsg['senderPhoto']}');
        }

        // Check if there's a nested sender object
        if (sampleMsg.containsKey('sender') && sampleMsg['sender'] is Map) {
          debugPrint('FOUND NESTED SENDER OBJECT:');
          final sender = sampleMsg['sender'] as Map;
          debugPrint('Sender keys: ${sender.keys.join(', ')}');
          if (sender.containsKey('photoUrl')) {
            debugPrint('sender.photoUrl: ${sender['photoUrl']}');
          }
        }

        // Look for any keys containing 'photo', 'image', 'avatar' case-insensitive
        final photoRelatedKeys =
            sampleMsg.keys
                .where(
                  (key) =>
                      key.toLowerCase().contains('photo') ||
                      key.toLowerCase().contains('image') ||
                      key.toLowerCase().contains('avatar'),
                )
                .toList();

        if (photoRelatedKeys.isNotEmpty) {
          debugPrint('📸 POTENTIAL PHOTO FIELDS FOUND:');
          for (final key in photoRelatedKeys) {
            debugPrint('$key: ${sampleMsg[key]}');
          }
        } else {
          debugPrint('⚠️ NO PHOTO-RELATED FIELDS FOUND IN MESSAGE');

          // Since no photo fields were found, let's try to fetch user profiles
          debugPrint(
            '🔍 Attempting to fetch first 3 sender profiles to check for photos...',
          );

          // Get a sample of unique sender IDs (up to 3)
          final Set<int> uniqueSenderIds = {};
          for (var msg in response.take(10)) {
            if (msg.containsKey('senderId') &&
                msg['senderId'] != null &&
                uniqueSenderIds.length < 3) {
              final senderId = msg['senderId'];
              if (senderId is int) {
                uniqueSenderIds.add(senderId);
              } else if (senderId is String) {
                try {
                  uniqueSenderIds.add(int.parse(senderId));
                } catch (e) {
                  debugPrint('⚠️ Failed to parse senderId: $senderId');
                }
              }
            }
          }

          // Fetch profile data for the sample senders
          debugPrint(
            '🔍 Found ${uniqueSenderIds.length} unique sender IDs to check',
          );
          for (final senderId in uniqueSenderIds) {
            try {
              final senderData = await widget.apiService.getUserById(senderId);
              debugPrint(
                '👤 Sender $senderId data: ${senderData.keys.join(', ')}',
              );

              if (senderData.containsKey('photoUrl')) {
                debugPrint(
                  '📸 Found photo for user $senderId: ${senderData['photoUrl']}',
                );
              } else {
                debugPrint('⚠️ No photoUrl found for user $senderId');
              }
            } catch (e) {
              debugPrint('⚠️ Error fetching sender $senderId profile: $e');
            }
          }
        }
      }
      debugPrint('====================================');

      // For any offline messages, try to find matching server messages
      final List<Map<String, dynamic>> mergedList = List.from(response);

      // Enrich messages with sender photos
      debugPrint('🖼️ ENRICHING MESSAGES WITH SENDER PHOTOS');

      // Create a map to cache user data so we don't fetch the same user multiple times
      final Map<int, Map<String, dynamic>> userDataCache = {};

      // Collect all unique sender IDs
      final Set<int> uniqueSenderIds = {};
      for (var message in mergedList) {
        if (message.containsKey('senderId') && message['senderId'] != null) {
          try {
            final int senderId =
                message['senderId'] is int
                    ? message['senderId']
                    : int.parse(message['senderId'].toString());
            uniqueSenderIds.add(senderId);
          } catch (e) {
            debugPrint('⚠️ Error parsing senderId: ${message['senderId']}');
          }
        }
      }

      debugPrint(
        '🔍 Found ${uniqueSenderIds.length} unique senders to fetch photos for',
      );

      // Fetch user data for all unique senders
      for (final senderId in uniqueSenderIds) {
        try {
          final userData = await widget.apiService.getUserById(senderId);
          userDataCache[senderId] = userData;
          debugPrint('✅ Cached user data for sender $senderId');
        } catch (e) {
          debugPrint('⚠️ Error fetching data for sender $senderId: $e');
        }
      }

      // Enrich each message with sender photo URL
      int enrichedCount = 0;
      for (var message in mergedList) {
        if (message.containsKey('senderId') && message['senderId'] != null) {
          try {
            final int senderId =
                message['senderId'] is int
                    ? message['senderId']
                    : int.parse(message['senderId'].toString());

            if (userDataCache.containsKey(senderId)) {
              final userData = userDataCache[senderId]!;

              // Check if user has a photo
              if (userData.containsKey('photoUrl') &&
                  userData['photoUrl'] != null &&
                  userData['photoUrl'].toString().isNotEmpty) {
                // Add the photo URL to the message
                message['senderPhoto'] = userData['photoUrl'];
                enrichedCount++;
                debugPrint(
                  '📸 Added photo URL for message from sender $senderId: ${userData['photoUrl']}',
                );
              } else {
                // If photoUrl doesn't exist, check for avatar, image, or photo fields
                for (var key in userData.keys) {
                  if ((key.toLowerCase().contains('photo') ||
                          key.toLowerCase().contains('image') ||
                          key.toLowerCase().contains('avatar')) &&
                      userData[key] != null &&
                      userData[key].toString().isNotEmpty) {
                    message['senderPhoto'] = userData[key];
                    enrichedCount++;
                    debugPrint(
                      '📸 Added alternative photo field ($key) for sender $senderId: ${userData[key]}',
                    );
                    break;
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error enriching message with photo: $e');
            // Skip enriching this message
          }
        }
      }

      debugPrint('📊 Enriched $enrichedCount messages with sender photos');

      // Log each message's photo field for debugging
      for (var message in mergedList.take(5)) {
        // Only log first 5 for brevity
        final senderId = message['senderId'];
        final hasSenderPhoto =
            message.containsKey('senderPhoto') &&
            message['senderPhoto'] != null;
        debugPrint(
          'Message from sender $senderId | Has photo: $hasSenderPhoto | ${hasSenderPhoto ? 'URL: ${message['senderPhoto']}' : 'No photo URL'}',
        );
      }

      if (_offlineMessages.isNotEmpty) {
        // Keep offline messages that don't have a matching ID in the response
        for (var offlineMsg in _offlineMessages) {
          final String content = offlineMsg['content'] ?? '';
          final bool hasDuplicate = response.any(
            (msg) =>
                msg['content'] == content &&
                msg['senderId'] == widget.userId &&
                (DateTime.parse(msg['timestamp']).millisecondsSinceEpoch -
                        (offlineMsg['timestamp'] as int)) <
                    60000,
          ); // 1 minute tolerance

          if (!hasDuplicate) {
            mergedList.add(offlineMsg);
          }
        }
      }

      // Sort by timestamp (descending)
      mergedList.sort((a, b) {
        // Handle different timestamp formats (string from server vs. int from offline)
        final int timestampA =
            a['timestamp'] is String
                ? DateTime.parse(a['timestamp']).millisecondsSinceEpoch
                : a['timestamp'] as int;
        final int timestampB =
            b['timestamp'] is String
                ? DateTime.parse(b['timestamp']).millisecondsSinceEpoch
                : b['timestamp'] as int;

        // Descending order (newest first)
        return timestampB.compareTo(timestampA);
      });

      return mergedList;
    } catch (e) {
      return _offlineMessages;
    }
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
                  _pickMedia(ImageSource.camera, 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.gallery, 'photo');
                },
              ),
              ListTile(
                leading: const Icon(Icons.videocam),
                title: const Text('Record a video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.camera, 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.video_library),
                title: const Text('Choose video from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickMedia(ImageSource.gallery, 'video');
                },
              ),
              ListTile(
                leading: const Icon(Icons.sd_card),
                title: const Text('Use sample video'),
                onTap: () {
                  Navigator.pop(context);
                  _showSampleVideoDialog();
                },
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: const Text('Help finding videos'),
                onTap: () {
                  Navigator.pop(context);
                  _showVideoHelpDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSampleVideoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Sample Video Information'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'About the sample_video.mp4 in DCIM:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  'The sample_video.mp4 file in your DCIM folder is causing an "UnrecognizedInputFormatException"',
                ),
                const Text(
                  'This means the video is in a format the emulator cannot decode.',
                ),
                const SizedBox(height: 16),
                const Text(
                  'What you can do:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try taking a photo instead - photos work reliably',
                ),
                const Text('2. Test on a physical device with real videos'),
                const Text(
                  '3. Create a test MP4 using the Camera app directly',
                ),
                const SizedBox(height: 16),
                const Text(
                  'Why this happens:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text('• Android emulators have limited codec support'),
                const Text(
                  '• The sample_video.mp4 might use an unsupported codec',
                ),
                const Text(
                  '• This is a common issue in emulators, not in real devices',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
            TextButton(
              onPressed: () {
                // Try camera for a photo instead
                Navigator.of(context).pop();
                _pickMedia(ImageSource.camera, 'photo');
              },
              child: const Text('Take a Photo Instead'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    try {
      // Set additional options for image/video picker to improve compatibility
      final XFile? pickedFile;
      if (type == 'photo') {
        debugPrint('Attempting to pick image from source: $source');
        pickedFile = await _picker.pickImage(
          source: source,
          maxWidth: 1800,
          maxHeight: 1800,
          imageQuality: 85,
        );
      } else {
        debugPrint('Attempting to pick video from source: $source');
        pickedFile = await _picker.pickVideo(
          source: source,
          maxDuration: const Duration(minutes: 10), // limit video size
        );
      }

      if (!mounted) return;

      if (pickedFile != null) {
        debugPrint(
          'Media picked successfully: ${pickedFile.path}, type: $type',
        );

        // Verify the file exists
        final file = File(pickedFile.path);
        if (await file.exists()) {
          if (!mounted) return;

          final fileSize = await file.length();
          debugPrint(
            'File exists at path: ${pickedFile.path}, size: $fileSize bytes',
          );

          // Special handling for 0-byte files (emulator issue)
          if (fileSize == 0 && type == 'video') {
            debugPrint(
              'Special case: 0-byte video file detected (emulator issue)',
            );
            // Try to get stats about the file
            try {
              final stat = await file.stat();
              if (!mounted) return;

              debugPrint('File stats: ${stat.toString()}');

              // Show dialog asking if they want to try anyway
              bool shouldContinue =
                  await showDialog<bool>(
                    context: context,
                    builder:
                        (context) => AlertDialog(
                          title: const Text('Video Size Issue'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'The video file appears to be empty (0 bytes).',
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'This is a common issue with Android emulators.',
                              ),
                              const SizedBox(height: 16),
                              const Text('Do you want to:'),
                              const SizedBox(height: 8),
                              const Text(
                                '1. Try sending it anyway (may not work)',
                              ),
                              const Text('2. Try using a photo instead'),
                            ],
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Try Anyway'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context, false);
                                _pickMedia(ImageSource.gallery, 'photo');
                              },
                              child: const Text('Select Photo Instead'),
                            ),
                          ],
                        ),
                  ) ??
                  false;

              if (!mounted) return;
              if (!shouldContinue) {
                return;
              }
            } catch (e) {
              debugPrint('Error getting file stats: $e');
              if (!mounted) return;
            }
          }
        } else {
          debugPrint(
            'Warning: File does not exist at path: ${pickedFile.path}',
          );
          if (!mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Selected file could not be accessed. Try again or select a different file.',
              ),
            ),
          );
          return;
        }

        setState(() {
          _selectedMediaFile = pickedFile;
          _selectedMediaType = type;
        });

        if (type == 'video' && !kIsWeb) {
          try {
            _videoController?.dispose();
            if (_chewieController != null) {
              _chewieController!.dispose();
              _chewieController = null;
            }

            debugPrint('Initializing video controller for: ${pickedFile.path}');

            // Generate thumbnail first - this will be our placeholder
            final File? thumbnailFile = await VideoThumbnailUtil.getThumbnail(
              'file://${pickedFile.path}',
            );

            // Store the thumbnail for later use when posting the message
            _selectedVideoThumbnail = thumbnailFile;
            debugPrint(
              '📸 Generated and saved video thumbnail: ${thumbnailFile?.path}',
            );

            // Build placeholder widget function
            Widget buildPlaceholderWidget() {
              if (thumbnailFile != null) {
                return Image.file(
                  thumbnailFile,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                );
              } else {
                return Container(
                  color: Colors.black,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
            }

            // Create video controller
            _videoController = VideoPlayerController.file(
              File(pickedFile.path),
            );

            // Initialize controller and create Chewie only after initialization
            _videoController!
                .initialize()
                .then((_) {
                  if (!mounted) return;

                  final duration = _videoController!.value.duration;
                  debugPrint('Video controller initialized successfully');
                  debugPrint('Video duration: $duration');

                  setState(() {
                    // For emulator/simulator, sometimes the duration can't be determined
                    // but the video might still be valid
                    if (duration.inMilliseconds > 0) {
                      // Initialize Chewie controller for better video preview
                      _chewieController = ChewieController(
                        videoPlayerController: _videoController!,
                        aspectRatio: _videoController!.value.aspectRatio,
                        autoPlay: false,
                        looping: false,
                        autoInitialize: true,
                        showControls: true,
                        placeholder: buildPlaceholderWidget(),
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

                      // Auto-play once to confirm it works
                      _videoController?.play();
                      Future.delayed(const Duration(seconds: 1), () {
                        if (!mounted) return;
                        if (_videoController?.value.isPlaying ?? false) {
                          _videoController?.pause();
                        }
                      });
                    } else {
                      debugPrint(
                        'Warning: Video has zero duration, but may still be valid',
                      );
                    }
                  });
                })
                .catchError((error) {
                  debugPrint(
                    'Error in video controller initialization: $error',
                  );
                  if (!mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not preview video: $error')),
                  );
                });
          } catch (e) {
            debugPrint('Error initializing video player: $e');
            if (!mounted) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error initializing video: $e')),
            );
          }
        }
      } else {
        debugPrint('No media selected by user');
        if (source == ImageSource.gallery && type == 'video') {
          // Show help dialog automatically when no video was selected
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _showVideoHelpDialog();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Error picking media: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking media: $e'),
          duration: const Duration(seconds: 10),
          action: SnackBarAction(
            label: 'Help',
            onPressed: _showVideoHelpDialog,
          ),
        ),
      );
    }
  }

  void _showVideoHelpDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Finding Videos in Emulator'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'To use a video from your emulator:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text('1. Open the "Files" app in your emulator'),
                const Text('2. Look for the DCIM folder (Camera)'),
                const Text(
                  '3. Create a sample video with camera app if needed',
                ),
                const SizedBox(height: 16),
                const Text(
                  'For your specific emulator setup:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try using the "Camera" app to record a short video',
                ),
                const Text('2. It will be saved in the DCIM/Camera folder'),
                const Text('3. Return to the app and select from gallery'),
                const SizedBox(height: 16),
                const Text(
                  'If still having issues:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  '1. Try using a physical device instead of emulator',
                ),
                const Text(
                  '2. Emulators sometimes have permission issues with media',
                ),
                const Text(
                  '3. You could also try creating a test image instead',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _postMessage() async {
    if (_messageController.text.isEmpty && _selectedMediaFile == null) return;

    final String messageContent = _messageController.text;
    final XFile? mediaFile = _selectedMediaFile; // Cache before clearing
    final String? mediaType = _selectedMediaType; // Cache before clearing

    debugPrint('=== ATTEMPTING TO POST MESSAGE: "$messageContent" ===');
    debugPrint('Media file: ${mediaFile?.path}, type: $mediaType');

    try {
      // Get user data first to ensure we have photo URL
      final userData = await widget.apiService.getUserById(widget.userId);

      // Fix: Check for both photoUrl and photo fields
      if (_cachedUserPhotoUrl == null) {
        final photoUrl = userData['photoUrl'] ?? userData['photo'];
        if (photoUrl != null) {
          _cachedUserPhotoUrl = photoUrl;
          debugPrint('📸 Updated cached photo URL: $_cachedUserPhotoUrl');
        }
      }

      // Clear the input fields immediately for better UX
      _messageController.clear();
      // Cache the thumbnail before clearing selections
      final File? localThumbnail = _selectedVideoThumbnail;

      setState(() {
        _selectedMediaFile = null;
        _selectedMediaType = null;
        _videoController?.dispose();
        _videoController = null;
        _selectedVideoThumbnail = null;
      });

      // Create an optimistic message to display immediately
      final Map<String, dynamic> optimisticMessage = {
        'id':
            DateTime.now().millisecondsSinceEpoch *
            -1, // Negative to avoid conflicts
        'content': messageContent,
        'senderUsername': userData['username'] ?? 'Me',
        'senderFirstName': userData['firstName'],
        'senderLastName': userData['lastName'],
        'senderId': widget.userId,
        'timestamp': DateTime.now().toIso8601String(),
        'mediaType': mediaType,
        'mediaUrl':
            mediaFile?.path != null ? 'file://${mediaFile!.path}' : null,
        'senderPhoto': _cachedUserPhotoUrl, // Use cached photo URL
        'commentCount': 0,
        'reactionCount': 0,
        'viewCount': 0,
        'hasValidId': false,
        'generatedId': true,
        'offlineMessage': true,
        'sendingFailed': false,
        'familyId': userData['familyId'],
        'familyName': userData['familyName'] ?? 'My Family',
        // Use local thumbnail path if available, otherwise mark for checking
        'localThumbnailPath':
            mediaType == 'video' && localThumbnail != null
                ? localThumbnail.path
                : null,
        'checkingThumbnail':
            mediaType == 'video' && mediaFile != null && localThumbnail == null,
      };

      // Add to offline messages and update UI immediately
      setState(() {
        // Insert at beginning of offline messages
        _offlineMessages.insert(0, optimisticMessage);

        // Insert at beginning of displayed messages
        _messages.insert(0, optimisticMessage);
      });

      // Scroll after state update
      _scrollToBottom();

      // Now send to server - use video processing if it's a video
      final bool success =
          mediaType == 'video' && mediaFile != null
              ? await widget.apiService.postMessageWithVideoProcessing(
                widget.userId,
                messageContent,
                mediaPath: mediaFile.path,
                mediaType: mediaType,
              )
              : await widget.apiService.postMessage(
                widget.userId,
                messageContent,
                mediaPath: mediaFile?.path,
                mediaType: mediaType,
              );

      if (success) {
        debugPrint('*** MESSAGE POSTED SUCCESSFULLY ***');
        debugPrint('Content: "$messageContent"');

        // Add this call to check for the thumbnail if this was a video message
        if (mediaType == 'video' && mediaFile != null) {
          _checkForVideoThumbnail(optimisticMessage);
        }

        // Add debug check to verify the message in database
        try {
          debugPrint('Verifying message in database...');
          final checkMessages = await widget.apiService.getMessages(
            widget.userId,
          );
          final foundMessage = checkMessages.any(
            (m) =>
                m['content'] == messageContent &&
                m['senderId'] == widget.userId,
          );

          debugPrint('Message found in database: $foundMessage');
          if (!foundMessage) {
            debugPrint(
              'WARNING: Message was reported as successful but not found in database!',
            );
            debugPrint('Database has ${checkMessages.length} messages');
            if (checkMessages.isNotEmpty) {
              debugPrint(
                'Latest message in DB: "${checkMessages[0]['content']}"',
              );
            }
          }
        } catch (e) {
          debugPrint('Error verifying message in database: $e');
        }

        // Message was successfully added on server, now refresh messages
        // Wait for the server to process first
        await Future.delayed(const Duration(milliseconds: 1000));

        setState(() {
          // Only remove the optimistic version if we can find it
          final messageIndex = _offlineMessages.indexWhere(
            (msg) => msg['id'] == optimisticMessage['id'],
          );
          if (messageIndex >= 0) {
            _offlineMessages.removeAt(messageIndex);
          }

          // Update the message in the in-memory list to show it as confirmed
          final index = _messages.indexWhere(
            (msg) => msg['id'] == optimisticMessage['id'],
          );
          if (index >= 0) {
            // Update the message to show it's confirmed
            _messages[index] = {
              ..._messages[index],
              'status': 'sent',
              'offlineMessage': false,
              'hasValidId': true,
            };
          }
        });

        // No need for a full refresh here

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message posted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        debugPrint('!!! MESSAGE POSTING FAILED !!!');

        // Keep the optimistic message in UI but mark it as failed
        setState(() {
          // Mark as failed in offline messages list
          final index = _offlineMessages.indexWhere(
            (msg) => msg['id'] == optimisticMessage['id'],
          );
          if (index >= 0) {
            _offlineMessages[index]['status'] = 'failed';
            _offlineMessages[index]['sendingFailed'] = true;
          }

          // Update the message in the in-memory list to show it as failed
          final msgIndex = _messages.indexWhere(
            (msg) => msg['id'] == optimisticMessage['id'],
          );
          if (msgIndex >= 0) {
            // Update the message to show it's failed
            _messages[msgIndex] = {
              ..._messages[msgIndex],
              'status': 'failed',
              'sendingFailed': true,
            };
          }
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaFile != null
                  ? 'Media upload failed. Message shown in offline mode.'
                  : 'Message syncing failed. Message shown in offline mode.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                // Re-open the composer with the failed message
                _messageController.text = messageContent;

                setState(() {
                  // Remove the failed message from offline messages
                  _offlineMessages.removeWhere(
                    (msg) => msg['id'] == optimisticMessage['id'],
                  );

                  // Remove from the in-memory list too
                  _messages.removeWhere(
                    (msg) => msg['id'] == optimisticMessage['id'],
                  );
                });
              },
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('!!! ERROR posting message: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error posting message: ${e.toString().split(":").first}',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // Add this new function to check for video thumbnails
  Future<void> _checkForVideoThumbnail(Map<String, dynamic> sentMessage) async {
    // Set this message as "checking thumbnail" to show loading indicator
    setState(() {
      int index = _messages.indexWhere((msg) => msg['id'] == sentMessage['id']);
      if (index >= 0) {
        _messages[index]['checkingThumbnail'] = true;
      }
    });

    try {
      // We could add a delay here if needed
      // await Future.delayed(const Duration(milliseconds: 800));

      // Get the latest messages - no artificial delay
      final messages = await widget.apiService.getMessages(widget.userId);
      final newMessage = messages.firstWhere(
        (msg) =>
            msg['content'] == sentMessage['content'] &&
            msg['senderId'] == widget.userId,
        orElse: () => {},
      );

      // Update our message with thumbnail if available
      setState(() {
        int index = _messages.indexWhere(
          (msg) => msg['id'] == sentMessage['id'],
        );
        if (index >= 0) {
          if (newMessage.isNotEmpty && newMessage['thumbnailUrl'] != null) {
            _messages[index]['thumbnailUrl'] = newMessage['thumbnailUrl'];
            debugPrint(
              '✅ Updated video thumbnail for message with server thumbnail',
            );

            // We'll keep the local thumbnail too - it might still be useful as a fallback
            // but don't overwrite it if it already exists
            if (newMessage['localThumbnailPath'] != null &&
                _messages[index]['localThumbnailPath'] == null) {
              _messages[index]['localThumbnailPath'] =
                  newMessage['localThumbnailPath'];
            }
          } else {
            debugPrint('❌ No server thumbnail found for message');

            // Keep using local thumbnail if available
            if (_messages[index]['localThumbnailPath'] != null) {
              debugPrint('📸 Keeping local thumbnail as fallback');
            }
          }
          // Either way, we're done checking
          _messages[index]['checkingThumbnail'] = false;
        }
      });
    } catch (e) {
      debugPrint('Error checking thumbnail: $e');
      setState(() {
        int index = _messages.indexWhere(
          (msg) => msg['id'] == sentMessage['id'],
        );
        if (index >= 0) {
          _messages[index]['checkingThumbnail'] = false;
        }
      });
    }
  }

  // Create an offline message object
  Future<Map<String, dynamic>> _createOfflineMessage(
    String content, {
    String? mediaPath,
    String? mediaType,
  }) async {
    // Get user data for message metadata
    final userData = await widget.apiService.getUserById(widget.userId);

    // Fix: Check for both photoUrl and photo fields
    if (_cachedUserPhotoUrl == null) {
      final photoUrl = userData['photoUrl'] ?? userData['photo'];
      if (photoUrl != null) {
        _cachedUserPhotoUrl = photoUrl;
        debugPrint('📸 Updated cached photo URL: $_cachedUserPhotoUrl');
      }
    }

    // Generate a unique ID for offline tracking
    final offlineId =
        DateTime.now().millisecondsSinceEpoch *
        -1; // Negative to avoid conflicts

    return {
      'id': offlineId,
      'content': content,
      'senderUsername': userData['username'] ?? 'Me',
      'senderFirstName': userData['firstName'],
      'senderLastName': userData['lastName'],
      'senderId': widget.userId,
      'timestamp': DateTime.now().toIso8601String(),
      'mediaType': mediaType,
      'mediaUrl': mediaPath != null ? 'file://$mediaPath' : null,
      'senderPhoto': _cachedUserPhotoUrl, // Use cached photo URL
      'commentCount': 0,
      'reactionCount': 0,
      'viewCount': 0,
      'hasValidId': false,
      'generatedId': true,
      'offlineMessage': true,
      'sendingFailed': false,
      'familyId': userData['familyId'],
      'familyName': userData['familyName'] ?? 'My Family',
    };
  }

  Widget _buildMediaPreview() {
    if (_selectedMediaFile == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Container(
          height: 200, // Increased height for better video playback
          width: double.infinity,
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.grey[200],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child:
                _selectedMediaType == 'photo'
                    ? kIsWeb
                        ? Image.network(
                          _selectedMediaFile!.path,
                          fit: BoxFit.contain, // Scale without cropping
                        )
                        : Image.file(
                          File(_selectedMediaFile!.path),
                          fit: BoxFit.contain, // Scale without cropping
                        )
                    : _videoController?.value.isInitialized ?? false
                    ? _chewieController != null
                        ? Chewie(controller: _chewieController!)
                        : AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              VideoPlayer(_videoController!),
                              // Add controls overlay for play/pause
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _videoController!.value.isPlaying
                                        ? _videoController!.pause()
                                        : _videoController!.play();
                                  });
                                },
                                child: Container(
                                  color: Colors.transparent,
                                  child: Center(
                                    child: Icon(
                                      _videoController!.value.isPlaying
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                      color: Colors.white.withOpacity(0.7),
                                      size: 60.0,
                                    ),
                                  ),
                                ),
                              ),
                              // Add progress indicator at bottom
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: VideoProgressIndicator(
                                  _videoController!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.blue,
                                    bufferedColor: Colors.grey,
                                    backgroundColor: Colors.black38,
                                  ),
                                  padding: const EdgeInsets.all(3.0),
                                ),
                              ),
                            ],
                          ),
                        )
                    : const Center(child: CircularProgressIndicator()),
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: CircleAvatar(
            backgroundColor: Colors.black54,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _selectedMediaFile = null;
                  _selectedMediaType = null;
                  if (_videoController != null) {
                    _videoController!.pause();
                    _videoController!.dispose();
                    _videoController = null;
                  }
                  if (_chewieController != null) {
                    _chewieController!.dispose();
                    _chewieController = null;
                  }
                });
              },
            ),
          ),
        ),
        if (_selectedMediaType == 'video' &&
            (_videoController?.value.isInitialized ?? false))
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                // Display video duration
                _videoController!.value.duration.inSeconds > 0
                    ? '${_videoController!.value.duration.inMinutes}:${(_videoController!.value.duration.inSeconds % 60).toString().padLeft(2, '0')}'
                    : 'Video',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        // Show a confirmation dialog before exiting
        final shouldExit =
            await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('Exit App?'),
                    content: const Text(
                      'Are you sure you want to exit the app?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('No'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Yes'),
                      ),
                    ],
                  ),
            ) ??
            false;

        if (shouldExit) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppTheme.primaryColor,
          elevation: 0,
          title: Text('Messages', style: AppStyles.appBarTitleStyle),
          actions: [
            // Keep only the standard refresh button and logout button
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () {
                _refreshMessages(shouldScrollToBottom: true);
              },
              tooltip: 'Refresh Messages',
            ),
            IconButton(
              icon: const Icon(Icons.logout, color: Colors.white),
              onPressed: _logout,
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
          ),
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await _refreshMessages(shouldScrollToBottom: true);
                  },
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    future: _messagesFuture ?? _loadMessages(),
                    builder: (context, snapshot) {
                      // If we have already loaded messages in memory, use those directly
                      if (_isInitialMessagesLoaded) {
                        return _buildMessagesListView(_messages);
                      }

                      // Otherwise, handle loading state and errors
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          _isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (snapshot.hasError && _loadError == null) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Failed to load messages: ${snapshot.error}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Colors.red,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 10),
                              ElevatedButton(
                                onPressed: () {
                                  _refreshMessages(shouldScrollToBottom: true);
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        );
                      }

                      // Get messages from snapshot if not loaded yet
                      final messages = snapshot.data ?? [];

                      // Store in our in-memory list
                      if (messages.isNotEmpty && !_isInitialMessagesLoaded) {
                        _messages = messages;
                        _isInitialMessagesLoaded = true;
                      }

                      if (messages.isEmpty) {
                        return RefreshIndicator(
                          onRefresh: () async {
                            await _refreshMessages(shouldScrollToBottom: true);
                          },
                          child: ListView(
                            reverse: true,
                            children: [
                              const SizedBox(height: 100),
                              const Center(
                                child: Text(
                                  'No messages yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return _buildMessagesListView(messages);
                    },
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildMediaPreview(),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: _showMediaPicker,
                          tooltip: 'Add Media',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Enter your message',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
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
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: () async {
                              // If we're sending a text-only message, use the simplified method
                              if (_selectedMediaFile == null) {
                                await _postSimpleTextMessage();
                              } else {
                                // For media messages, use the original method
                                await _postMessage();
                              }
                            },
                            tooltip: 'Send Message',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateRefreshTimestamp() {
    // No need to update timestamp string as it was removed
    // Just log the refresh
    final now = DateTime.now();
    final formattedTime =
        "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}";
    debugPrint('Messages refreshed at $formattedTime');
  }

  /// Handle logout action
  void _logout() async {
    await AuthUtils.showLogoutConfirmation(context, widget.apiService);
  }

  Future<void> _checkForInvitations() async {
    try {
      // First, determine which families the user belongs to
      try {
        final userData = await widget.apiService.getUserById(widget.userId);
        if (!mounted) return;

        if (userData['familyId'] != null) {
          _userFamilyIds.add(userData['familyId']);
        }
      } catch (e) {
        debugPrint('Error getting user data for invitations: $e');
        // Continue anyway to try fetching invitations
      }

      try {
        final response = await widget.apiService.getInvitations();
        if (!mounted) return;

        // Filter to only show pending invitations that aren't for families the user is already in
        final pendingInvitations =
            response
                .where(
                  (inv) =>
                      inv['status'] == 'PENDING' &&
                      !_userFamilyIds.contains(inv['familyId']),
                )
                .toList();

        if (pendingInvitations.isNotEmpty) {
          // Extract the IDs of the current pending invitations
          final currentInvitationIds =
              pendingInvitations.map<int>((inv) => inv['id'] as int).toList();

          // Find new invitations (those that weren't in the previous list)
          final newInvitationIds =
              currentInvitationIds
                  .where((id) => !_previousInvitationIds.contains(id))
                  .toList();

          // Update the stored IDs for next comparison
          _previousInvitationIds = currentInvitationIds;

          // If there are new invitations, show a notification
          if (newInvitationIds.isNotEmpty && mounted) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (!mounted) return;

              final newCount = newInvitationIds.length;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'You have ${newCount == 1 ? 'a new' : '$newCount new'} invitation${newCount > 1 ? 's' : ''}',
                  ),
                  backgroundColor: Colors.green,
                  action: SnackBarAction(
                    label: 'View',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder:
                              (context) => InvitationsScreen(
                                apiService: widget.apiService,
                                userId: widget.userId,
                              ),
                        ),
                      );
                    },
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            });
          }
          // If there are any pending invitations (but no new ones), show a counter in the UI
          else if (currentInvitationIds.isNotEmpty) {
            // You could update a badge count or subtle UI indicator here
            debugPrint('${currentInvitationIds.length} pending invitations');
          }
        } else {
          // No pending invitations, reset the stored list
          _previousInvitationIds = [];
        }
      } catch (e) {
        // Handle invitation errors specifically
        debugPrint('Error fetching invitations: $e');
        // Don't propagate error - this is a non-critical feature
      }
    } catch (e) {
      debugPrint('Error checking for invitations: $e');
      // Don't propagate error - this is a non-critical feature
    }
  }

  // Check and fix family data issues that might cause messaging problems
  Future<void> _checkAndFixFamilyData() async {
    try {
      // Get user data to check family ID and name
      final userData = await widget.apiService.getUserById(widget.userId);
      if (!mounted) return; // Check if still mounted after async call

      final int? familyId = userData['familyId'];
      final String? familyName = userData['familyName'];

      // If user has no family, show a guidance message
      if (familyId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'You are not in a family. Create or join a family to send messages.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Create Family',
              onPressed: () {
                // Show dialog to create a family
                _showCreateFamilyDialog();
              },
              textColor: Colors.white,
            ),
          ),
        );
        return;
      }

      // If user has a family ID but no family name, try to fix it
      if (familyId != null && (familyName == null || familyName.isEmpty)) {
        // Try to get family details - silently attempt without showing errors
        try {
          final family = await widget.apiService.getFamily(familyId);
          if (!mounted) return; // Check if still mounted after async call

          final String retrievedFamilyName = family['name'] ?? 'My Family';

          // If we found a name, update the UI with a subtle message
          if (retrievedFamilyName.isNotEmpty) {
            debugPrint('Family name retrieved: $retrievedFamilyName');
            // Only show a message if family name was completely missing before
            if (familyName == null || familyName.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Connected to family: $retrievedFamilyName'),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } catch (e) {
          // Log the error but don't show it to the user during normal usage
          debugPrint('Error fetching family details: $e');

          // Only show error if this is a critical feature for the current user
          // and you're sure they need to know about it
          // For normal usage, we'll just log it silently
        }
      }
    } catch (e) {
      // Log the error but don't show it to the user during normal usage
      debugPrint('Error checking family data: $e');
    }
  }

  // Helper method to format message day header
  String _formatMessageDay(DateTime dateTime) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return 'Today';
    } else if (messageDate == yesterday) {
      return 'Yesterday';
    } else if (today.difference(messageDate).inDays < 7) {
      // Within a week, show day name
      return DateFormat('EEEE').format(dateTime); // e.g., "Monday"
    } else {
      // Older messages, show date
      return DateFormat('MMM d').format(dateTime); // e.g., "Jan 15"
    }
  }

  // Helper method to retry failed messages
  void _retryFailedMessage(Map<String, dynamic> failedMessage) {
    // Get message content and attempt to post again
    final String messageContent = failedMessage['content'] ?? '';

    // Remove the failed message from memory directly
    setState(() {
      // Remove from offline messages
      _offlineMessages.removeWhere((msg) => msg['id'] == failedMessage['id']);

      // Remove from the in-memory list
      _messages.removeWhere((msg) => msg['id'] == failedMessage['id']);
    });

    // If message had content, put it in the text field for retrying
    if (messageContent.isNotEmpty) {
      _messageController.text = messageContent;

      // Show snackbar to confirm retry
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retry message: "$messageContent"'),
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Send Now',
            onPressed: () {
              // Try posting again
              _postSimpleTextMessage();
            },
            textColor: Colors.white,
          ),
        ),
      );
    }
  }

  // Show dialog to create a new family
  void _showCreateFamilyDialog() {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Create Family'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Create a new family to start sending messages.'),
              const SizedBox(height: 16),
              TextField(
                controller: textController,
                decoration: const InputDecoration(
                  labelText: 'Family Name',
                  hintText: 'Enter a name for your family',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final familyName = textController.text.trim();
                if (familyName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a family name'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);

                // Cache the context and check mounted flag throughout the async operations
                final currentContext = context;

                // Show loading indicator
                if (!mounted) return;
                ScaffoldMessenger.of(currentContext).showSnackBar(
                  const SnackBar(
                    content: Text('Creating family...'),
                    duration: Duration(seconds: 1),
                  ),
                );

                try {
                  // Create the family
                  await widget.apiService.createFamily(
                    widget.userId,
                    familyName,
                  );

                  if (!mounted) return;

                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Family "$familyName" created successfully!',
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 3),
                    ),
                  );

                  // Refresh messages after family creation
                  await _refreshMessages(shouldScrollToBottom: true);

                  // Show guidance for sending a message
                  if (!mounted) return;
                  Future.delayed(const Duration(seconds: 3), () {
                    if (mounted) {
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'You can now send messages to your family!',
                          ),
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                  });
                } catch (e) {
                  if (!mounted) return;

                  ScaffoldMessenger.of(currentContext).showSnackBar(
                    SnackBar(
                      content: Text('Error creating family: ${e.toString()}'),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAvatarForSender(
    int? senderId,
    String? photoUrl,
    String displayName,
  ) {
    // Create the avatar widget with Google Messages style
    final bool isCurrentUser = senderId == widget.userId;

    // REAL FIX FOR ROOT CAUSE: Use cached photo URL for current user if photoUrl is missing
    if (isCurrentUser &&
        (photoUrl == null || photoUrl.isEmpty) &&
        _cachedUserPhotoUrl != null) {
      // Use the cached photo URL directly here
      debugPrint(
        '🔄 Using cached photo URL for current user avatar: $_cachedUserPhotoUrl',
      );
      photoUrl = _cachedUserPhotoUrl;
    }

    // Debug logging for avatar
    if (photoUrl != null) {
      debugPrint('🔍 Avatar debug for $displayName: Raw photoUrl = $photoUrl');
      final String fullUrl =
          photoUrl.startsWith('http')
              ? photoUrl
              : '${widget.apiService.baseUrl}$photoUrl';
      debugPrint('🔍 Full URL constructed: $fullUrl');
    } else {
      debugPrint(
        '⚠️ No photo URL for user $displayName (fallback letter will be used)',
      );
    }

    return Container(
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
      child: CircleAvatar(
        radius: 20,
        backgroundColor: Color(displayName.hashCode | 0xFF000000),
        child:
            photoUrl != null && photoUrl.isNotEmpty
                ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl:
                        photoUrl.startsWith('http')
                            ? photoUrl
                            : '${widget.apiService.baseUrl}$photoUrl',
                    fit: BoxFit.cover,
                    width: 40,
                    height: 40,
                    placeholder:
                        (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) {
                      debugPrint(
                        '⚠️ Error loading avatar image from $url: $error',
                      );
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

  // Add a method for text-only messages
  Future<void> _postSimpleTextMessage() async {
    if (_messageController.text.isEmpty) return;

    final String messageContent = _messageController.text;

    try {
      // First, verify user has a valid family for message posting
      // Declare variables outside the inner try block to fix scoping
      Map<String, dynamic>? userData;
      Map<String, dynamic>? optimisticMessage;
      bool? success;

      try {
        userData = await widget.apiService.getUserById(widget.userId);
        if (!mounted)
          return; // Check if widget is still mounted after async call

        if (userData['familyId'] == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'You need to be in a family to send messages. Please create or join a family first.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
          return;
        }

        // Clear the input field immediately
        _messageController.clear();

        // Fix: Check for both photoUrl and photo fields
        if (_cachedUserPhotoUrl == null) {
          final photoUrl = userData['photoUrl'] ?? userData['photo'];
          if (photoUrl != null) {
            _cachedUserPhotoUrl = photoUrl;
            debugPrint('📸 Updated cached photo URL: $_cachedUserPhotoUrl');
          }
        }

        // Using the optimistic approach - add it to offline messages first
        optimisticMessage = {
          'id': DateTime.now().millisecondsSinceEpoch,
          'content': messageContent,
          'senderId': widget.userId,
          'senderUsername': userData['username'] ?? 'Unknown',
          'senderFirstName': userData['firstName'] ?? 'User',
          'senderLastName': userData['lastName'] ?? '',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'status': 'sending',
          'senderPhoto': _cachedUserPhotoUrl, // Use cached photo URL
          'familyId': userData['familyId'],
          'familyName': userData['familyDetails']?['name'] ?? 'Unknown Family',
          'offlineMessage': true,
        };

        // Add to offline messages and update UI immediately
        setState(() {
          // Insert at beginning of offline messages
          _offlineMessages.insert(0, optimisticMessage!);

          // Insert at beginning of displayed messages
          _messages.insert(0, optimisticMessage);
        });

        // Scroll after state update
        _scrollToBottom();

        // Now send to server
        success = await widget.apiService.postMessage(
          widget.userId,
          messageContent,
          familyId: userData['familyId'], // Always pass explicit family ID
        );

        if (!mounted) return; // Check mounted after async call
      } catch (e) {
        // Handle authentication errors gracefully
        if (e.toString().contains('Not authenticated')) {
          debugPrint('Authentication error in _postSimpleTextMessage: $e');
          // User is no longer authenticated, clear UI but don't show error
          return;
        }

        // Show error for other exceptions
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Update the status of the optimistic message after server response
      if (success == true && optimisticMessage != null && mounted) {
        setState(() {
          final index = _messages.indexWhere(
            (msg) =>
                msg['offlineMessage'] == true &&
                msg['content'] == messageContent,
          );
          if (index != -1) {
            _messages[index]['status'] = 'sent';
          }

          final offlineIndex = _offlineMessages.indexWhere(
            (msg) =>
                msg['offlineMessage'] == true &&
                msg['content'] == messageContent,
          );
          if (offlineIndex != -1) {
            _offlineMessages[offlineIndex]['status'] = 'sent';
          }
        });
        _refreshMessages(shouldScrollToBottom: false);
      } else if (success == false && optimisticMessage != null && mounted) {
        // Mark message as failed
        setState(() {
          final index = _messages.indexWhere(
            (msg) =>
                msg['offlineMessage'] == true &&
                msg['content'] == messageContent,
          );
          if (index != -1) {
            _messages[index]['status'] = 'failed';
          }

          final offlineIndex = _offlineMessages.indexWhere(
            (msg) =>
                msg['offlineMessage'] == true &&
                msg['content'] == messageContent,
          );
          if (offlineIndex != -1) {
            _offlineMessages[offlineIndex]['status'] = 'failed';
          }
        });
      }
    } catch (e) {
      if (!mounted)
        return; // Check mounted before accessing context in error handler

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending message: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // Helper method to get short day name (Mon, Tue, etc.)
  String _getShortDayName(DateTime dateTime) {
    // Always return the abbreviated day name (Mon, Tue, etc.)
    return DateFormat('E').format(dateTime); // E gives short weekday name
  }

  // Update to show the ListView in reverse, with newest at bottom
  Widget _buildMessagesListView(List<Map<String, dynamic>> messages) {
    debugPrint('📱 Building messages list with ${messages.length} messages');

    // Debug check for thumbnails
    for (var message in messages.take(5)) {
      // Check first 5 messages only
      if (message['mediaType'] == 'video') {
        final bool hasThumbnail =
            message['thumbnailUrl'] != null &&
            message['thumbnailUrl'].toString().isNotEmpty;
        final String thumbnailUrl =
            hasThumbnail ? message['thumbnailUrl'].toString() : 'MISSING';

        debugPrint(
          '🎬 VIDEO MESSAGE: id=${message['id']}, has thumbnail: $hasThumbnail',
        );
        if (hasThumbnail) {
          final String fullUrl =
              thumbnailUrl.startsWith('http')
                  ? thumbnailUrl
                  : '${widget.apiService.baseUrl}$thumbnailUrl';
          debugPrint('  📸 Thumbnail URL: $thumbnailUrl');
          debugPrint('  📸 Full URL: $fullUrl');

          // Try to validate the URL
          try {
            final uri = Uri.parse(fullUrl);
            debugPrint('  ✅ Valid URI: $uri');
          } catch (e) {
            debugPrint('  ⚠️ Invalid URI: $e');
          }
        }
      }
    }

    // Group messages by date for proper date separator placement
    final Map<String, List<int>> dateGroups = {};

    // Process messages to group by date
    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message['timestamp'] != null) {
        final messageDateTime =
            message['timestamp'] is String
                ? DateTime.parse(message['timestamp'])
                : DateTime.fromMillisecondsSinceEpoch(
                  message['timestamp'] as int,
                );

        final messageDate = DateTime(
          messageDateTime.year,
          messageDateTime.month,
          messageDateTime.day,
        );

        // Format date as string key for map
        final dateKey =
            "${messageDate.year}-${messageDate.month}-${messageDate.day}";

        if (!dateGroups.containsKey(dateKey)) {
          dateGroups[dateKey] = [];
        }
        dateGroups[dateKey]!.add(i);
      }
    }

    // For each date group, find the first index (which will be where we show the separator)
    final Map<String, int> firstMessageOfDateIndices = {};
    dateGroups.forEach((date, indices) {
      // Since we're in reverse order (newest at bottom), we need the max index for each date group
      // This is because messages are displayed in reverse, so the max index is actually
      // the first message of the date when displayed
      indices.sort(); // Sort to ensure we get min/max correctly
      // Get maximum index which will be the first message of that date in the reversed list
      firstMessageOfDateIndices[date] = indices.last;
    });

    debugPrint('📅 Found ${dateGroups.length} date groups in messages');

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      itemCount: messages.length,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      itemBuilder: (context, index) {
        final message = messages[index];
        final content = message['content'] ?? 'No content';
        final senderId = message['senderId'];
        final senderUsername = message['senderUsername'] ?? 'Unknown';

        // Make sure senderPhoto is not empty string which would trigger the fallback avatar
        String? senderPhoto = message['senderPhoto'];

        // FIX: Ensure current user messages always have a photo URL
        final bool isSenderCurrentUser = senderId == widget.userId;
        if (isSenderCurrentUser &&
            (senderPhoto == null || senderPhoto.isEmpty) &&
            _cachedUserPhotoUrl != null) {
          // Update the message in-place to include the cached photo URL
          message['senderPhoto'] = _cachedUserPhotoUrl;
          senderPhoto = _cachedUserPhotoUrl;
          debugPrint(
            '🔄 Updated missing photo for current user message at index $index',
          );
        } else if (senderPhoto != null && senderPhoto.isEmpty) {
          senderPhoto = null; // Set to null to ensure fallback works properly
        }

        // For offline/optimistic messages, get photo from user data if available
        if ((message['offlineMessage'] == true ||
                message['status'] == 'sending') &&
            senderId == widget.userId) {
          // Fetch user photo from cache or API
          _getUserPhotoForMessage(message);
        }

        final bool isCurrentUser = senderId == widget.userId;

        // Debug output for the first few messages to avoid flooding logs
        if (index < 5) {
          debugPrint(
            '🔍 Message $index - sender: $senderUsername, senderId: $senderId, hasPhoto: ${senderPhoto != null}',
          );
          if (senderPhoto != null) {
            debugPrint('   📸 Photo URL: $senderPhoto');
          }
        }

        // Get timestamp information for the message
        String timeText = '';
        String dayText = '';
        DateTime? messageDateTime;

        if (message['timestamp'] != null) {
          messageDateTime =
              message['timestamp'] is String
                  ? DateTime.parse(message['timestamp'])
                  : DateTime.fromMillisecondsSinceEpoch(
                    message['timestamp'] as int,
                  );

          // Format time (hour:minute)
          timeText = DateFormat('h:mm a').format(messageDateTime);

          // Get short day name
          dayText = _getShortDayName(messageDateTime);
        }

        // Determine if this message should have a date separator
        bool shouldShowDateSeparator = false;
        String? dateKey;

        if (messageDateTime != null) {
          final messageDate = DateTime(
            messageDateTime.year,
            messageDateTime.month,
            messageDateTime.day,
          );

          dateKey =
              "${messageDate.year}-${messageDate.month}-${messageDate.day}";

          // Check if this index is the first message of its date group in the reversed list
          if (firstMessageOfDateIndices.containsKey(dateKey) &&
              firstMessageOfDateIndices[dateKey] == index) {
            shouldShowDateSeparator = true;
          }
        }

        // Date separator widget
        Widget? dateSeparator;
        if (shouldShowDateSeparator && messageDateTime != null) {
          final messageDate = DateTime(
            messageDateTime.year,
            messageDateTime.month,
            messageDateTime.day,
          );

          // Create a date separator for this date
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final yesterday = today.subtract(const Duration(days: 1));

          String dateDisplay;
          if (messageDate == today) {
            dateDisplay = "Today";
          } else if (messageDate == yesterday) {
            dateDisplay = "Yesterday";
          } else {
            // For older dates, use the date format
            dateDisplay = DateFormat(
              'MMM d, yyyy',
            ).format(messageDate); // e.g., "Jan 15, 2023"
          }

          // Print debug info
          debugPrint(
            '📅 Adding date separator "$dateDisplay" at index $index (date: $dateKey)',
          );

          dateSeparator = Container(
            padding: const EdgeInsets.symmetric(vertical: 10.0),
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                dateDisplay,
                style: TextStyle(
                  color: Colors.grey[800],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          );
        }

        // Get first character of username for fallback avatar
        final String avatarText =
            senderUsername.isNotEmpty ? senderUsername[0].toUpperCase() : '?';

        // Generate color from username
        final Color avatarColor = Color(senderUsername.hashCode | 0xFF000000);

        // Create a column with the date separator and the message
        return Column(
          children: [
            // Add date separator if needed
            if (dateSeparator != null) dateSeparator,

            // Message row
            Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 8.0,
                horizontal: 4.0,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Always show avatar for all messages
                  _buildAvatarForSender(senderId, senderPhoto, senderUsername),

                  // Message content
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Sender name
                          if (!isCurrentUser)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4.0),
                              child: Text(
                                senderUsername,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.blue,
                                ),
                              ),
                            ),

                          // Message content
                          Text(content, style: const TextStyle(fontSize: 16)),

                          // Message media content (photos/videos)
                          if (message['mediaUrl'] != null &&
                              message['mediaUrl'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child:
                                  message['mediaType'] == 'photo'
                                      ? message['mediaUrl']
                                              .toString()
                                              .startsWith('file://')
                                          ? Container(
                                            constraints: BoxConstraints(
                                              maxHeight: 200,
                                              minHeight: 100,
                                            ),
                                            child: Image.file(
                                              File(
                                                message['mediaUrl']
                                                    .toString()
                                                    .replaceFirst(
                                                      'file://',
                                                      '',
                                                    ),
                                              ),
                                              fit: BoxFit.contain,
                                              errorBuilder: (
                                                context,
                                                error,
                                                stackTrace,
                                              ) {
                                                debugPrint(
                                                  'Error loading file image: $error',
                                                );
                                                return Container(
                                                  height: 100,
                                                  color: Colors.grey[300],
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.error,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                          : Container(
                                            constraints: BoxConstraints(
                                              maxHeight: 200,
                                              minHeight: 100,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  message['mediaUrl']
                                                          .toString()
                                                          .startsWith('http')
                                                      ? message['mediaUrl']
                                                      : '${widget.apiService.baseUrl}${message['mediaUrl']}',
                                              fit: BoxFit.contain,
                                              placeholder:
                                                  (context, url) => Container(
                                                    height: 100,
                                                    color: Colors.grey[300],
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  ),
                                              errorWidget: (
                                                context,
                                                url,
                                                error,
                                              ) {
                                                debugPrint(
                                                  'Error loading image: $error, URL: $url',
                                                );
                                                return Container(
                                                  height: 100,
                                                  color: Colors.grey[300],
                                                  child: const Center(
                                                    child: Icon(
                                                      Icons.error,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          )
                                      : message['mediaType'] == 'video'
                                      ? Builder(
                                        builder: (context) {
                                          final bool isPlaying =
                                              _currentlyPlayingVideoId ==
                                              message['id'];

                                          // Check if there's a server-provided thumbnail URL or local thumbnail
                                          final hasServerThumbnailUrl =
                                              (message['thumbnailUrl'] !=
                                                      null &&
                                                  message['thumbnailUrl']
                                                      .toString()
                                                      .isNotEmpty) ||
                                              (message['thumbnail_url'] !=
                                                      null &&
                                                  message['thumbnail_url']
                                                      .toString()
                                                      .isNotEmpty);

                                          // Check if there's a locally generated thumbnail path
                                          final hasLocalThumbnail =
                                              message['localThumbnailPath'] !=
                                                  null &&
                                              message['localThumbnailPath']
                                                  .toString()
                                                  .isNotEmpty;

                                          final hasThumbnailUrl =
                                              hasServerThumbnailUrl ||
                                              hasLocalThumbnail;

                                          // Handle both camelCase and snake_case versions for server URL
                                          final String actualThumbnailUrl =
                                              message['thumbnailUrl']
                                                  ?.toString() ??
                                              message['thumbnail_url']
                                                  ?.toString() ??
                                              '';

                                          // Get local thumbnail path if available
                                          final String? localThumbnailPath =
                                              message['localThumbnailPath']
                                                  ?.toString();

                                          // Debug logging for thumbnail URLs
                                          debugPrint(
                                            '📽️ VIDEO THUMBNAIL DEBUG:',
                                          );
                                          debugPrint(
                                            'Message ID: ${message['id']}',
                                          );
                                          debugPrint(
                                            'Has thumbnailUrl: $hasThumbnailUrl',
                                          );
                                          if (hasThumbnailUrl) {
                                            debugPrint(
                                              'Thumbnail URL: $actualThumbnailUrl',
                                            );

                                            if (hasLocalThumbnail) {
                                              debugPrint(
                                                '📸 Using LOCAL thumbnail: $localThumbnailPath',
                                              );
                                            }

                                            // Test thumbnail URL variants in the background
                                            widget.apiService
                                                .findWorkingThumbnailUrl(
                                                  actualThumbnailUrl,
                                                )
                                                .then((workingUrl) {
                                                  if (workingUrl != null &&
                                                      workingUrl !=
                                                          actualThumbnailUrl &&
                                                      mounted) {
                                                    debugPrint(
                                                      '🔄 Found better thumbnail URL: $workingUrl',
                                                    );
                                                    setState(() {
                                                      message['thumbnailUrl'] =
                                                          workingUrl;
                                                      message['thumbnail_url'] =
                                                          workingUrl;
                                                    });
                                                  }
                                                });
                                          } else {
                                            debugPrint(
                                              'No thumbnail URL found',
                                            );
                                          }
                                          debugPrint(
                                            'Message keys: ${message.keys.join(', ')}',
                                          );

                                          // Check if we're actively checking for a thumbnail
                                          final bool isCheckingThumbnail =
                                              message['checkingThumbnail'] ==
                                              true;
                                          final bool thumbnailFailed =
                                              message['thumbnailFailed'] ==
                                              true;

                                          // Default video placeholder - server thumbnail, local thumbnail, or generic placeholder
                                          final Widget defaultPlaceholder =
                                              hasServerThumbnailUrl
                                                  ? CachedNetworkImage(
                                                    imageUrl:
                                                        actualThumbnailUrl
                                                                .startsWith(
                                                                  "http",
                                                                )
                                                            ? actualThumbnailUrl
                                                            : '${widget.apiService.baseUrl}$actualThumbnailUrl',
                                                    width:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.7,
                                                    height: 200,
                                                    fit: BoxFit.cover,
                                                    placeholder:
                                                        (
                                                          context,
                                                          url,
                                                        ) => Container(
                                                          width:
                                                              MediaQuery.of(
                                                                context,
                                                              ).size.width *
                                                              0.7,
                                                          height: 200,
                                                          color: Colors.black,
                                                          child: const Center(
                                                            child:
                                                                CircularProgressIndicator(),
                                                          ),
                                                        ),
                                                    errorWidget: (
                                                      context,
                                                      url,
                                                      error,
                                                    ) {
                                                      debugPrint(
                                                        '❌ Error loading thumbnail in list: $error for URL: $url',
                                                      );

                                                      // Try to find a working URL if this one failed
                                                      widget.apiService
                                                          .findWorkingThumbnailUrl(
                                                            actualThumbnailUrl,
                                                          )
                                                          .then((workingUrl) {
                                                            if (workingUrl !=
                                                                    null &&
                                                                workingUrl !=
                                                                    actualThumbnailUrl &&
                                                                mounted) {
                                                              debugPrint(
                                                                '🔄 Found working thumbnail URL after error: $workingUrl',
                                                              );
                                                              setState(() {
                                                                message['thumbnailUrl'] =
                                                                    workingUrl;
                                                                message['thumbnail_url'] =
                                                                    workingUrl;
                                                              });
                                                            }
                                                          });
                                                      // Return default placeholder on error
                                                      return Container(
                                                        width:
                                                            MediaQuery.of(
                                                              context,
                                                            ).size.width *
                                                            0.7,
                                                        height: 200,
                                                        color: Colors.black,
                                                        child: Stack(
                                                          alignment:
                                                              Alignment.center,
                                                          children: [
                                                            Container(
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    Colors
                                                                        .grey
                                                                        .shade800,
                                                                shape:
                                                                    BoxShape
                                                                        .circle,
                                                              ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    16,
                                                                  ),
                                                              child: const Icon(
                                                                Icons.videocam,
                                                                color:
                                                                    Colors
                                                                        .white,
                                                                size: 40,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  )
                                                  : hasLocalThumbnail
                                                  ? Image.file(
                                                    File(localThumbnailPath!),
                                                    width:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.7,
                                                    height: 200,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) {
                                                      debugPrint(
                                                        '❌ Error loading local thumbnail: $error',
                                                      );
                                                      return _buildDefaultVideoPlaceholder();
                                                    },
                                                  )
                                                  : isCheckingThumbnail
                                                  ? SizedBox(
                                                    width:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.7, // Match video width
                                                    height:
                                                        200, // Match video height
                                                    child: Center(
                                                      child: SizedBox(
                                                        width: 50,
                                                        height: 50,
                                                        child: CircularProgressIndicator(
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                Color
                                                              >(Colors.blue),
                                                          strokeWidth: 3,
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  : Container(
                                                    width:
                                                        MediaQuery.of(
                                                          context,
                                                        ).size.width *
                                                        0.7, // Use 70% of screen width
                                                    height:
                                                        200, // Explicitly set height
                                                    color: Colors.black,
                                                    child: Stack(
                                                      alignment:
                                                          Alignment.center,
                                                      children: [
                                                        // Video icon background
                                                        Container(
                                                          decoration:
                                                              BoxDecoration(
                                                                color:
                                                                    Colors
                                                                        .grey
                                                                        .shade800,
                                                                shape:
                                                                    BoxShape
                                                                        .circle,
                                                              ),
                                                          padding:
                                                              const EdgeInsets.all(
                                                                16,
                                                              ),
                                                          child: const Icon(
                                                            Icons.videocam,
                                                            color: Colors.white,
                                                            size: 40,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );

                                          return Container(
                                            constraints: BoxConstraints(
                                              maxHeight:
                                                  isPlaying
                                                      ? 250
                                                      : 180, // Adjust max height
                                              minHeight:
                                                  isPlaying
                                                      ? 200
                                                      : 150, // Adjust min height
                                            ),
                                            width:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.7, // Match placeholder width
                                            child:
                                                isPlaying
                                                    ? ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: Stack(
                                                        children: [
                                                          // Always show placeholder as background until video loads
                                                          defaultPlaceholder,

                                                          // Only overlay the video player if it's fully initialized
                                                          if (_inlineChewieController !=
                                                              null)
                                                            Positioned.fill(
                                                              child: Chewie(
                                                                controller:
                                                                    _inlineChewieController!,
                                                              ),
                                                            ),

                                                          // Close button
                                                          Positioned(
                                                            top: 5,
                                                            right: 5,
                                                            child: GestureDetector(
                                                              onTap: () {
                                                                setState(() {
                                                                  _cleanupInlinePlayer();
                                                                });
                                                              },
                                                              child: Container(
                                                                padding:
                                                                    const EdgeInsets.all(
                                                                      4,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color:
                                                                      Colors
                                                                          .black54,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        12,
                                                                      ),
                                                                ),
                                                                child: const Icon(
                                                                  Icons.close,
                                                                  color:
                                                                      Colors
                                                                          .white,
                                                                  size: 16,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    )
                                                    : GestureDetector(
                                                      onTap: () {
                                                        _initializeInlinePlayer(
                                                          message,
                                                        );
                                                      },
                                                      child: Stack(
                                                        alignment:
                                                            Alignment.center,
                                                        children: [
                                                          // Show consistent placeholder
                                                          defaultPlaceholder,

                                                          // Play button overlay
                                                          Container(
                                                            decoration:
                                                                BoxDecoration(
                                                                  color: Colors
                                                                      .white
                                                                      .withOpacity(
                                                                        0.7,
                                                                      ),
                                                                  shape:
                                                                      BoxShape
                                                                          .circle,
                                                                ),
                                                            child: const Padding(
                                                              padding:
                                                                  EdgeInsets.all(
                                                                    8.0,
                                                                  ),
                                                              child: Icon(
                                                                Icons
                                                                    .play_arrow,
                                                                color:
                                                                    Colors
                                                                        .black87,
                                                                size: 50,
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                          );
                                        },
                                      )
                                      : Container(), // For other media types
                            ),
                          ],

                          // Timestamp (only time, not day)
                          if (message['timestamp'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Align(
                                alignment: Alignment.bottomRight,
                                child: Text(
                                  timeText,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ),
                            ),

                          // Failed message indicator
                          if (message['status'] == 'failed')
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Failed to send',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  GestureDetector(
                                    onTap: () => _retryFailedMessage(message),
                                    child: Text(
                                      'Retry',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Day indicator outside the bubble, on the right
                  if (dayText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6.0),
                      child: Text(
                        dayText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Helper method to get user photo for optimistic messages
  Future<void> _getUserPhotoForMessage(Map<String, dynamic> message) async {
    try {
      // Skip if the message already has a photo
      if (message.containsKey('senderPhoto') &&
          message['senderPhoto'] != null &&
          message['senderPhoto'].toString().isNotEmpty) {
        return;
      }

      // Get current user data to fill in photo
      final userData = await widget.apiService.getUserById(widget.userId);

      // Check for both photoUrl and photo fields
      final photoUrl = userData['photoUrl'] ?? userData['photo'];
      if (photoUrl != null && photoUrl.toString().isNotEmpty) {
        // Update the message with the photo URL
        setState(() {
          message['senderPhoto'] = photoUrl;
        });

        debugPrint('📸 Added user photo to optimistic message: $photoUrl');
      }
    } catch (e) {
      debugPrint('⚠️ Error getting user photo for message: $e');
      // Continue without photo
    }
  }

  // Helper method to build a consistent video placeholder
  Widget _buildDefaultVideoPlaceholder() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.7,
      height: 200,
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Video icon background
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(16),
            child: const Icon(Icons.videocam, color: Colors.white, size: 40),
          ),
        ],
      ),
    );
  }

  // Check thumbnail URLs for all video messages and correct them if needed
  Future<void> _checkAllVideoThumbnails(
    List<Map<String, dynamic>> messages,
  ) async {
    debugPrint('🔍 Checking thumbnails for all video messages...');

    // Find all video messages with thumbnails
    final videoMessages =
        messages
            .where(
              (message) =>
                  message['mediaType'] == 'video' &&
                  message['thumbnailUrl'] != null &&
                  message['thumbnailUrl'].toString().isNotEmpty,
            )
            .toList();

    debugPrint('Found ${videoMessages.length} video messages with thumbnails');

    // Test each thumbnail URL in parallel
    final futures = <Future>[];

    for (var message in videoMessages) {
      futures.add(_checkAndFixThumbnailUrl(message));
    }

    // Wait for all checks to complete
    await Future.wait(futures);

    debugPrint('✅ Finished checking all video thumbnails');
  }

  // Check and fix a single thumbnail URL
  Future<void> _checkAndFixThumbnailUrl(Map<String, dynamic> message) async {
    // First, check for both snake_case and camelCase versions
    if (!message.containsKey('thumbnailUrl') &&
        message.containsKey('thumbnail_url')) {
      // If only snake_case exists, copy it to camelCase
      debugPrint(
        '📝 Converting snake_case thumbnail_url to camelCase thumbnailUrl',
      );
      message['thumbnailUrl'] = message['thumbnail_url'];
    } else if (!message.containsKey('thumbnail_url') &&
        message.containsKey('thumbnailUrl')) {
      // If only camelCase exists, copy it to snake_case
      debugPrint(
        '📝 Converting camelCase thumbnailUrl to snake_case thumbnail_url',
      );
      message['thumbnail_url'] = message['thumbnailUrl'];
    }

    // Now proceed with checking if the URL works
    final String thumbnailUrl =
        message['thumbnailUrl']?.toString() ??
        message['thumbnail_url']?.toString() ??
        '';

    if (thumbnailUrl.isEmpty) {
      debugPrint('❌ No thumbnail URL found for message ${message['id']}');
      return;
    }

    debugPrint(
      '🔍 Checking thumbnail for message ${message['id']}: $thumbnailUrl',
    );

    // Test if the current URL works
    final bool works = await widget.apiService.testThumbnailAccess(
      thumbnailUrl,
    );

    if (works) {
      debugPrint('✅ Thumbnail URL already works: $thumbnailUrl');
      return;
    }

    // Find a working URL
    final String? workingUrl = await widget.apiService.findWorkingThumbnailUrl(
      thumbnailUrl,
    );

    if (workingUrl != null && mounted) {
      debugPrint('🔄 Found working thumbnail URL: $workingUrl');
      setState(() {
        // Update both versions for consistency
        message['thumbnailUrl'] = workingUrl;
        message['thumbnail_url'] = workingUrl;
      });
    } else {
      debugPrint('❌ Could not find working thumbnail URL for: $thumbnailUrl');
    }
  }
}
