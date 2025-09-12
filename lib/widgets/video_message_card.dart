import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/api_service.dart';
import '../utils/thumbnail_utils.dart';
import 'simple_video_player.dart';

class VideoMessageCard extends StatefulWidget {
  final String videoUrl;
  final String? localMediaPath;
  final String? thumbnailUrl;
  final ApiService apiService;
  final bool isCurrentlyPlaying;
  final VoidCallback? onTap;

  const VideoMessageCard({
    Key? key,
    required this.videoUrl,
    this.localMediaPath,
    this.thumbnailUrl,
    required this.apiService,
    this.isCurrentlyPlaying = false,
    this.onTap,
  }) : super(key: key);

  @override
  VideoMessageCardState createState() => VideoMessageCardState();
}

class VideoMessageCardState extends State<VideoMessageCard> {
  @override
  void initState() {
    super.initState();
  }

  // Called when video enters/exits viewport
  void _onVisibilityChanged(VisibilityInfo info) {
    // The SimpleVideoPlayer handles its own lifecycle
    // This can be used for additional optimizations if needed
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check what localMediaPath we receive
    // Build thumbnail URL for the simple video player
    String? thumbnailUrl;
    if (ThumbnailUtils.isValidThumbnailUrl(widget.thumbnailUrl)) {
      thumbnailUrl =
          widget.thumbnailUrl!.startsWith('http')
              ? widget.thumbnailUrl!
              : widget.apiService.mediaBaseUrl + widget.thumbnailUrl!;
    }

    // Build video URL
    final videoUrl =
        widget.videoUrl.startsWith('http')
            ? widget.videoUrl
            : widget.apiService.mediaBaseUrl + widget.videoUrl;

    return VisibilityDetector(
      key: Key('video_${widget.videoUrl}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: SimpleVideoPlayer(
        videoUrl: videoUrl,
        localMediaPath: widget.localMediaPath,
        thumbnailUrl: thumbnailUrl,
        height: 320,
        autoPlay: false,
      ),
    );
  }
}
