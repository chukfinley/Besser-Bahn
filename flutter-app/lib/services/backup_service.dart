import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_log.dart';
import '../core/backup.dart';

/// Writes and restores the encrypted on-device backup (#72).
///
/// Works on the SharedPreferences keys directly rather than on each provider:
/// the providers all read the same store on start, so a restore that lands
/// before the next launch is complete by construction, and a new feature's key
/// is included the day it is added instead of the day someone remembers to
/// extend a mapper.
class BackupService {
  /// Everything that is genuinely local and genuinely worth carrying to a new
  /// phone: the library (favourites, saved routes/trains/journeys), the
  /// lifetime statistics, confirmed split savings, and the search preferences.
  ///
  /// Prefixes, so a `_v2` key of the same feature keeps working.
  static const _prefixes = <String>[
    'lib_', // stations, routes, trains, journeys
    'travel_stats', // lifetime tally + which trips are already counted
    'purchased_splits', // confirmed split-ticket savings
  ];

  /// Individual settings keys. Listed one by one on purpose: settings is the
  /// drawer where credentials would end up, and a prefix match there would
  /// eventually sweep one into the file.
  static const _settingKeys = <String>[
    'bahnCard',
    'deutschlandTicket',
    'searchParty',
    'partyCustomized',
    'transferProfile',
    'age',
    'remindersEnabled',
    'reminderLeadMinutes',
    'transferAlerts',
    'arrivalAlertEnabled',
    'arrivalAlarmSound',
    'exitAlarmEnabled',
    'plainLanguage',
    'liveChipStops',
    'trwlAutoCheckin',
    'trwlVisibility',
  ];

  bool _isBackedUp(String key) =>
      _settingKeys.contains(key) || _prefixes.any(key.startsWith);

  /// Collect the current state into the plain (unencrypted) backup map.
  Future<Map<String, dynamic>> collect() async {
    final prefs = await SharedPreferences.getInstance();
    final values = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (!_isBackedUp(key)) continue;
      final v = prefs.get(key);
      // Only the four types SharedPreferences can hand back; a List<String>
      // survives as a list of strings.
      if (v is String || v is bool || v is int || v is double) {
        values[key] = v;
      } else if (v is List<String>) {
        values[key] = {'_type': 'stringList', 'value': v};
      }
    }
    return {
      'format': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'values': values,
    };
  }

  /// Write an encrypted backup to a file and return it.
  Future<File> writeBackup(String password, {Directory? into}) async {
    final bytes = await Backup.encrypt(await collect(), password);
    final dir = into ?? await getTemporaryDirectory();
    final file = File('${dir.path}/${Backup.fileNameFor(DateTime.now())}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Restore from an encrypted backup. Returns how many values were written.
  ///
  /// Additive: keys the backup doesn't mention are left alone, so restoring an
  /// old file cannot silently reset a setting that didn't exist back then.
  /// Anything unreadable throws [BackupError] *before* the first write, so a
  /// failed restore can't leave half the app on someone else's data.
  Future<int> restore(List<int> bytes, String password) async {
    final data = await Backup.decrypt(bytes, password);
    final values = data['values'];
    if (values is! Map) {
      throw const BackupError('Die Sicherung enthält keine Daten.');
    }

    final prefs = await SharedPreferences.getInstance();
    var written = 0;
    for (final entry in values.entries) {
      final key = entry.key;
      if (key is! String || !_isBackedUp(key)) continue;
      final v = entry.value;
      try {
        if (v is String) {
          await prefs.setString(key, v);
        } else if (v is bool) {
          await prefs.setBool(key, v);
        } else if (v is int) {
          await prefs.setInt(key, v);
        } else if (v is double) {
          await prefs.setDouble(key, v);
        } else if (v is Map && v['_type'] == 'stringList') {
          await prefs.setStringList(
              key, (v['value'] as List).map((e) => '$e').toList());
        } else {
          continue;
        }
        written++;
      } catch (e) {
        AppLog.log('restore of "$key" failed: $e', tag: 'backup');
      }
    }
    return written;
  }

  /// When the backup was made, for the confirmation dialog. Null if the file
  /// doesn't say (it always does from format 1 on).
  static DateTime? createdAt(Map<String, dynamic> data) =>
      DateTime.tryParse(data['createdAt'] as String? ?? '');

  /// Human summary of what a *plain* backup map holds — used in tests and in
  /// the log, never for anything the rider must trust.
  static String describe(Map<String, dynamic> data) {
    final values = data['values'];
    final n = values is Map ? values.length : 0;
    return '$n Einträge, erstellt ${data['createdAt'] ?? 'unbekannt'}';
  }

  /// Round-trip helper for the debug log — deliberately not exposed in the UI.
  static String encodePlain(Map<String, dynamic> data) => jsonEncode(data);
}
