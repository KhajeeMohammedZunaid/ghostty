import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

/// Polite Update Protocol - Non-blocking, opt-in update system
/// The app functions 100% offline. Updates are a convenience, not a blocker.
class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  static UpdateService get instance => _instance;
  UpdateService._internal();

  // Current app version - update this with each release
  static const String currentVersion = '1.0.0';
  static const int currentBuildNumber = 1;

  // GitHub raw URL for version.json
  // This URL points to the version.json file in your GitHub repo
  static const String versionUrl = 
      'https://raw.githubusercontent.com/KhajeeMohammedZunaid/ghostty/main/version.json';

  /// Check for updates silently in background
  /// Returns update info if available, null otherwise
  Future<UpdateInfo?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final remoteVersion = data['version'] as String;
        final remoteBuildNumber = data['build_number'] as int;

        // Compare versions
        if (_isNewerVersion(remoteVersion, remoteBuildNumber)) {
          return UpdateInfo(
            version: remoteVersion,
            buildNumber: remoteBuildNumber,
            changelog: data['changelog'] as String? ?? 'Bug fixes and improvements',
            downloadUrl: data['download_url'] as String,
          );
        }
      }
      return null;
    } catch (e) {
      // Fail silently - offline or network error
      // User should notice nothing
      debugPrint('Update check failed silently: $e');
      return null;
    }
  }

  /// Compare versions to check if remote is newer
  bool _isNewerVersion(String remoteVersion, int remoteBuildNumber) {
    // First compare build numbers (most reliable)
    if (remoteBuildNumber > currentBuildNumber) {
      return true;
    }

    // Fallback to semantic versioning
    final currentParts = currentVersion.split('.').map(int.parse).toList();
    final remoteParts = remoteVersion.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final current = i < currentParts.length ? currentParts[i] : 0;
      final remote = i < remoteParts.length ? remoteParts[i] : 0;

      if (remote > current) return true;
      if (remote < current) return false;
    }

    return false;
  }

  /// Show polite update snackbar
  void showUpdateSnackBar(BuildContext context, UpdateInfo info) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.system_update_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Update available (v${info.version})',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    info.changelog,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Update',
          textColor: Colors.greenAccent,
          onPressed: () => _openDownloadUrl(info.downloadUrl),
        ),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// Open download URL in browser
  Future<void> _openDownloadUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Could not open download URL: $e');
    }
  }
}

/// Update information model
class UpdateInfo {
  final String version;
  final int buildNumber;
  final String changelog;
  final String downloadUrl;

  UpdateInfo({
    required this.version,
    required this.buildNumber,
    required this.changelog,
    required this.downloadUrl,
  });
}
