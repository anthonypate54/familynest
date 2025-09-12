import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'cloud_file_service.dart';

/// Service for accessing Google Drive files
class GoogleDriveService {
  static const int maxFileSizeBytes = 25 * 1024 * 1024; // 25MB

  // TEMPORARILY DISABLED - Initialize only when needed to prevent crashes
  GoogleSignIn? _googleSignIn;

  GoogleSignIn get googleSignIn {
    _googleSignIn ??= GoogleSignIn(
      scopes: [drive.DriveApi.driveReadonlyScope],
      // iOS Client ID should be automatically picked up from GoogleService-Info.plist
    );
    return _googleSignIn!;
  }

  /// Get Google Drive files with instant size filtering (like Google Messages)
  Future<List<CloudFile>> getFiles(String type) async {
    try {
      debugPrint('🔐 Authenticating with Google Drive...');

      // Authenticate with Google
      final account = await googleSignIn.signInSilently();
      debugPrint('${account?.email ?? 'null'}');

      if (account == null) {
        debugPrint('🔐 No cached sign-in, attempting interactive sign-in...');
        final interactiveAccount = await googleSignIn.signIn();
        debugPrint(
          '${interactiveAccount?.email ?? 'null'}',
        );

        if (interactiveAccount == null) {
          throw Exception('Google Sign-in was cancelled by user');
        }
      }

      debugPrint('Getting authenticated client...');
      final authClient = await googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception('Failed to get authenticated client');
      }

      debugPrint('Google authentication successful');

      // Access Google Drive API
      final driveApi = drive.DriveApi(authClient);
      final mimePrefix = type == 'photo' ? 'image/' : 'video/';

      debugPrint('Searching Google Drive for $type files...');

      final result = await driveApi.files
          .list(
            q: "mimeType contains '$mimePrefix' and trashed = false",
            $fields: 'files(id, name, size, mimeType, webContentLink)',
            pageSize: 50,
          )
          .timeout(const Duration(seconds: 10));

      if (result.files == null) {
        debugPrint('📂 No files found in Google Drive');
        return [];
      }

      // Filter by size INSTANTLY (like Google Messages)
      final filteredFiles =
          result.files!
              .where((file) {
                final fileSize = file.size;
                if (fileSize == null) return false;
                final sizeInt = int.tryParse(fileSize.toString()) ?? 0;
                return sizeInt <= maxFileSizeBytes;
              })
              .map((file) {
                final fileSize = file.size;
                final sizeInt = int.tryParse(fileSize?.toString() ?? '0') ?? 0;
                return CloudFile(
                  id: file.id!,
                  name: file.name!,
                  size: sizeInt,
                  downloadUrl: file.webContentLink,
                  mimeType: file.mimeType ?? 'unknown',
                  provider: 'google_drive',
                );
              })
              .toList();

      debugPrint(
        'Found ${filteredFiles.length} Google Drive $type files under 25MB',
      );
      return filteredFiles;
    } catch (e) {
      debugPrint('$e');
      rethrow;
    }
  }

  /// Download Google Drive file for actual usage
  Future<String?> downloadFile(CloudFile file) async {
    if (file.provider != 'google_drive') {
      throw ArgumentError('File is not from Google Drive');
    }

    try {
      debugPrint('⬇️ Downloading Google Drive file: ${file.name}');

      // Get authenticated client
      final authClient = await googleSignIn.authenticatedClient();
      if (authClient == null) {
        throw Exception('Not authenticated with Google Drive');
      }

      // Download file to temp directory
      final driveApi = drive.DriveApi(authClient);
      final tempDir = await getTemporaryDirectory();
      final localPath = '${tempDir.path}/${file.name}';

      final media =
          await driveApi.files.get(
                file.id,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final sink = File(localPath).openWrite();
      await media.stream.pipe(sink);
      await sink.close();

      debugPrint('$localPath');
      return localPath;
    } catch (e) {
      debugPrint('$e');
      return null;
    }
  }

  /// Sign out from Google Drive
  Future<void> signOut() async {
    try {
      await googleSignIn.signOut();
      debugPrint('Signed out from Google Drive');
    } catch (e) {
      debugPrint('$e');
    }
  }

  /// Check if user is currently signed in
  bool get isSignedIn => _googleSignIn?.currentUser != null;

  /// Get current user info
  String? get currentUserEmail => _googleSignIn?.currentUser?.email;
}
