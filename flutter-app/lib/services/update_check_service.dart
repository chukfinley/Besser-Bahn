import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../core/app_log.dart';

/// A newer release than the one running, as GitHub reports it.
class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String releasePageUrl;

  /// Direct .apk for this device's ABI, when the release carries one.
  final String? apkUrl;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releasePageUrl,
    this.apkUrl,
  });
}

/// Tells the rider when a newer version is on GitHub. It does not install
/// anything and it does not nag: the app shows a dot in the menu and a card in
/// the settings, and the rider decides.
///
/// Deliberately NOT a tracker. It asks GitHub for the latest release tag, the
/// same request any browser makes on the releases page. Nothing about the
/// device, the rider or their trips is sent, and nothing is stored server-side
/// that we could read.
///
/// It stays quiet for store installs: an F-Droid-style client (IzzyOnDroid,
/// Neo Store, Droid-ify, Obtainium…) updates the app itself, so a second
/// "update available" hint there would be noise pointing at the wrong place.
class UpdateCheckService {
  const UpdateCheckService._();

  static const _apiUrl =
      'https://api.github.com/repos/chuk-development/Besser-Bahn/releases/latest';
  static const _releasesPage =
      'https://github.com/chuk-development/Besser-Bahn/releases';
  static const _timeout = Duration(seconds: 6);

  /// One check a day is plenty for a repo that releases every few weeks.
  static const _interval = Duration(hours: 24);

  static const _kLastCheck = 'updateLastCheckMs';
  static const _kSkipped = 'updateSkippedVersion';

  /// Installer package names of the app stores that update Besser-Bahn on
  /// their own. Everything else (browser download, adb, unknown) gets the hint.
  static const _storeInstallers = {
    'org.fdroid.fdroid', // F-Droid + IzzyOnDroid client
    'org.fdroid.basic',
    'com.machiav3lli.fdroid', // Neo Store
    'com.looker.droidify', // Droid-ify
    'nya.kitsunyan.foxydroid', // Foxy Droid
    'dev.imranr.obtainium', // Obtainium
    'com.aurora.store',
    'com.android.vending', // Play Store
  };

  /// What the UI listens to. Null means "nothing to show".
  static final ValueNotifier<UpdateInfo?> available =
      ValueNotifier<UpdateInfo?>(null);

  static bool _running = false;

  /// True when this install came from a store that does its own updates.
  static Future<bool> installedFromStore() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final installer = info.installerStore;
      if (installer == null || installer.isEmpty) return false;
      return _storeInstallers.contains(installer);
    } catch (_) {
      // Unknown installer → treat as a direct install, the hint is harmless.
      return false;
    }
  }

  /// Ask GitHub for the newest release. [force] skips both the 24 h interval
  /// and the "skip this version" the rider may have set, for the manual
  /// "Jetzt prüfen" button.
  static Future<void> check({bool force = false}) async {
    if (_running) return;
    _running = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!force) {
        // The rider can turn the check off entirely (settings → Über).
        if (!(prefs.getBool('updateCheckEnabled') ?? true)) return;
        final last = prefs.getInt(_kLastCheck);
        if (last != null) {
          final age = DateTime.now().difference(
            DateTime.fromMillisecondsSinceEpoch(last),
          );
          if (age < _interval) return;
        }
        if (await installedFromStore()) {
          AppLog.log(
            'Store-Installation → kein eigener Update-Hinweis',
            tag: 'update',
          );
          return;
        }
      }

      final res = await http
          .get(
            Uri.parse(_apiUrl),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': AppConstants.userAgent,
            },
          )
          .timeout(_timeout);
      prefs.setInt(_kLastCheck, DateTime.now().millisecondsSinceEpoch);

      if (res.statusCode != 200) {
        AppLog.log('GitHub antwortete ${res.statusCode}', tag: 'update');
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim();
      if (tag == null || tag.isEmpty) return;
      final latest = tag.startsWith('v') ? tag.substring(1) : tag;

      if (!isNewer(latest, AppConstants.appVersion)) {
        available.value = null;
        AppLog.log('aktuell (${AppConstants.appVersion})', tag: 'update');
        return;
      }
      if (!force && prefs.getString(_kSkipped) == latest) {
        AppLog.log('$latest übersprungen (Wunsch des Nutzers)', tag: 'update');
        return;
      }

      available.value = UpdateInfo(
        currentVersion: AppConstants.appVersion,
        latestVersion: latest,
        releasePageUrl: '$_releasesPage/tag/$tag',
        apkUrl: _apkFor(data['assets']),
      );
      AppLog.log(
        'neue Version $latest (läuft: ${AppConstants.appVersion})',
        tag: 'update',
      );
    } on TimeoutException {
      AppLog.log('Zeitüberschreitung beim Update-Check', tag: 'update');
    } catch (e) {
      AppLog.log('Update-Check fehlgeschlagen: $e', tag: 'update');
    } finally {
      _running = false;
    }
  }

  /// Don't show this version again.
  static Future<void> skip(String version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkipped, version);
    available.value = null;
  }

  /// Semver compare, tolerant of a missing part ("2.5" vs "2.4.1") and of a
  /// pre-release suffix ("2.5.0-rc.1" counts as 2.5.0, and /releases/latest
  /// never returns one anyway).
  static bool isNewer(String remote, String local) {
    List<int> parts(String v) => v
        .split('-')
        .first
        .split('.')
        .map((p) => int.tryParse(p.trim()) ?? 0)
        .toList();
    final r = parts(remote);
    final l = parts(local);
    for (var i = 0; i < (r.length > l.length ? r.length : l.length); i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < l.length ? l[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  /// The .apk matching this phone's ABI, so the rider lands on a file and not
  /// on a list of three. Falls back to null → the release page.
  static String? _apkFor(dynamic assets) {
    if (assets is! List) return null;
    final names = <String, String>{};
    for (final a in assets) {
      if (a is Map<String, dynamic>) {
        final n = (a['name'] as String?)?.toLowerCase();
        final u = a['browser_download_url'] as String?;
        if (n != null && u != null && n.endsWith('.apk')) names[n] = u;
      }
    }
    if (names.isEmpty) return null;
    for (final abi in _abis()) {
      for (final e in names.entries) {
        if (e.key.contains(abi)) return e.value;
      }
    }
    return null;
  }

  /// Phone ABIs, most specific first. arm64 covers every current device;
  /// the 32-bit and x86_64 builds are there for old hardware and emulators.
  static List<String> _abis() => const ['arm64-v8a', 'armeabi-v7a', 'x86_64'];
}
