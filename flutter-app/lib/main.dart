import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/app_log.dart';
import 'core/tile_cache.dart';
import 'services/background_trip_tracking.dart';
import 'services/notification_service.dart';
import 'services/update_check_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // German date symbols for locale-aware formatting (e.g. "Mai 2026" in the
  // Reisestatistik). Number symbols are bundled and need no init.
  await initializeDateFormatting('de');
  // Collapse the endless identical map-tile error dumps into one counted line
  // so the console/debug-log stays readable (must run before the first map).
  AppLog.installErrorCollapsing();
  // Best-effort: persistent on-disk tile cache. Failure is non-fatal.
  await TileCache.init();
  // Warm the vector basemap style in the background so the first map opens with
  // it ready (the style fetch was the main "takes a bit to open"). Fire-and-forget.
  TileCache.warmStyle();
  // Best-effort: local notifications (Split-Ticket-Ergebnis). Non-fatal.
  await NotificationService.init();
  // Persist the Android headless callback before a journey starts. Once the
  // GPS companion is enabled, native updates can reach Dart without the UI.
  await BackgroundTripTracking.registerHeadlessCallback();
  // Ask GitHub once a day whether a newer release is out. Fire-and-forget, off
  // for store installs (their client updates the app), and never blocking.
  UpdateCheckService.check();
  runApp(const ProviderScope(child: BessereBahnApp()));
}
