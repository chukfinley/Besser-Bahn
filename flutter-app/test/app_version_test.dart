import 'dart:io';

import 'package:besser_bahn/core/constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppConstants.appVersion] is a compile-time const — no `package_info_plus`
/// plugin channel needed, so it works in tests and on desktop alike. The trade
/// is that it can drift from `pubspec.yaml`, and it had: it still read 2.0.0
/// while pubspec was at 2.1.0, which would have shipped a lying version in the
/// Träwelling User-Agent and in the Einstellungen screen (#34).
///
/// This test is what makes the const safe: pubspec stays the single source of
/// truth, and a release bump that forgets the const fails the build.
void main() {
  test('AppConstants.appVersion matches pubspec.yaml (#34)', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull, reason: 'pubspec.yaml has no version: line');

    // pubspec carries `<version>+<build>`; the UA and the UI want the version.
    final pubspecVersion = match!.group(1)!.split('+').first;

    expect(
      AppConstants.appVersion,
      pubspecVersion,
      reason:
          'Bump AppConstants.appVersion to $pubspecVersion — it is baked '
          'into the Träwelling User-Agent and shown in Einstellungen.',
    );
  });
}
