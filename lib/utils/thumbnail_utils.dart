class ThumbnailUtils {
  /// Check if a thumbnail URL is valid and should be loaded
  static bool isValidThumbnailUrl(String? thumbnailUrl) {
    if (thumbnailUrl == null || thumbnailUrl.isEmpty) {
      return false;
    }

    // Don't load default thumbnails that don't exist
    if (thumbnailUrl.contains('default_thumbnail')) {
      return false;
    }

    // Don't load obviously broken URLs
    if (thumbnailUrl.contains('undefined') ||
        thumbnailUrl.contains('null') ||
        thumbnailUrl.length < 5) {
      return false;
    }

    return true;
  }
}
