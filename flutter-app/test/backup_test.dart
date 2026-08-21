import 'dart:convert';

import 'package:besser_bahn/core/backup.dart';
import 'package:flutter_test/flutter_test.dart';

/// The encrypted local backup (#72). Everything here is about the two ways a
/// backup can hurt: silently failing to restore, and opening for someone who
/// shouldn't have it.

void main() {
  const password = 'ein sehr gutes Passwort';
  // Cheap key derivation for the tests. The count travels in the file, so a
  // 1000-round test backup opens with exactly the same code path as a
  // 200000-round real one — without spending five seconds per assertion.
  const rounds = 1000;
  final data = {
    'format': 1,
    'createdAt': '2026-08-05T09:00:00.000',
    'values': {
      'lib_routes_v1': '[{"from":"Kiel"}]',
      'travel_stats_v1': '{"tripCount":42}',
      'remindersEnabled': true,
      'reminderLeadMinutes': 30,
    },
  };

  test('round-trips through encryption unchanged', () async {
    final bytes = await Backup.encrypt(data, password, iterations: rounds);
    expect(await Backup.decrypt(bytes, password), data);
  });

  test('the file is not readable without the password', () async {
    final bytes = await Backup.encrypt(data, password, iterations: rounds);
    // No plaintext leaks into the file — station names included.
    expect(utf8.decode(bytes, allowMalformed: true), isNot(contains('Kiel')));
    await expectLater(
      Backup.decrypt(bytes, 'falsch'),
      throwsA(isA<BackupError>()),
    );
  });

  test('a tampered byte fails authentication instead of restoring', () async {
    final bytes = await Backup.encrypt(data, password, iterations: rounds);
    bytes[bytes.length - 20] ^= 0xFF;
    await expectLater(
      Backup.decrypt(bytes, password),
      throwsA(isA<BackupError>()),
    );
  });

  test('a foreign file is rejected by its header, not by a crash', () async {
    await expectLater(
      Backup.decrypt(utf8.encode('{"just":"some json"}'), password),
      throwsA(isA<BackupError>()),
    );
  });

  test('a truncated backup is rejected', () async {
    final bytes = await Backup.encrypt(data, password, iterations: rounds);
    await expectLater(
      Backup.decrypt(bytes.sublist(0, 20), password),
      throwsA(isA<BackupError>()),
    );
  });

  test('an empty password is refused up front', () async {
    await expectLater(
      Backup.encrypt(data, '', iterations: rounds),
      throwsA(isA<BackupError>()),
    );
  });

  test('two backups of the same data differ (fresh salt and nonce)', () async {
    final a = await Backup.encrypt(data, password, iterations: rounds);
    final b = await Backup.encrypt(data, password, iterations: rounds);
    expect(a, isNot(equals(b)));
    expect(await Backup.decrypt(b, password), data);
  });

  test('file name carries the day it was made', () {
    expect(
      Backup.fileNameFor(DateTime(2026, 8, 5)),
      'besser-bahn-2026-08-05.bbbk',
    );
  });
}
