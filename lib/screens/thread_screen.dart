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
import '../utils/auth_utils.dart';
import 'dart:io';
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../utils/video_thumbnail_util.dart';
import '../widgets/gradient_background.dart';
import '../theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../config/app_config.dart';
import '../dialogs/large_video_dialog.dart';
import '../services/share_service.dart';

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

class _ThreadScreenState extends State<ThreadScreen> {
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

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() {
      _isSendButtonEnabled.value = _messageController.text.trim().isNotEmpty;
    });
    _loadComments();
  }

  Future<void> _loadComments() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

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
        await _handleVeryLargeCloudFile(type);
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

  Future<void> _postComment(ApiService apiService) async {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Thread'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
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
                                  setState(() {
                                    _currentlyPlayingVideoId = message.id;
                                  });
                                }
                              },
                              currentlyPlayingVideoId: _currentlyPlayingVideoId,
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
                          child: Image.file(
                            _selectedMediaFile!,
                            width: MediaQuery.of(context).size.width * 0.7,
                            height: 200,
                            fit: BoxFit.cover,
                          ),
                        )
                        : _selectedMediaType == 'video'
                        ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.7,
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
                                          child: CircularProgressIndicator(),
                                        ),
                              ),
                            ),
                          ),
                        )
                        : const SizedBox.shrink(),
              ),
            _buildMessageComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageComposer() {
    // Implementation of _buildMessageComposer method
    // This method should return a Widget representing the message composer
    // For now, we'll use a placeholder
    return Container(
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
                    isEnabled
                        ? () => _postComment(
                          Provider.of<ApiService>(context, listen: false),
                        )
                        : null,
                tooltip: 'Send Message',
                color: isEnabled ? Theme.of(context).primaryColor : Colors.grey,
              );
            },
          ),
        ],
      ),
    );
  }
}
