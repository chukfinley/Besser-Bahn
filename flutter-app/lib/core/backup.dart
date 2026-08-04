import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Encrypted local backup of everything the app keeps on device (#72).
///
/// The point is a device change without a server: the library, the statistics
/// and the search preferences are the only copy there is, so losing a phone
/// today loses them. This turns them into one file the rider owns, unreadable
/// without their password.
///
/// Deliberately NOT in the backup: the DB account tokens and the Träwelling
/// token. They live in secure storage, they are re-obtainable with a login, and
/// a stolen backup password should not hand anyone a live session.
///
/// File layout, so a future version can still read today's file:
///
///   magic "BBBK1\n" | iterations (4 B, big-endian) | salt (16 B)
///                   | nonce (12 B) | ciphertext+MAC
///
/// AES-GCM with a PBKDF2-HMAC-SHA256 key. The iteration count travels IN the
/// file rather than being a constant in the code: raising the cost later must
/// not turn every backup already written into an unreadable one. GCM
/// authenticates, so a wrong password and a tampered file fail the same way —
/// as a [BackupError], never as garbage that gets restored.
class Backup {
  Backup._();

  static const _magic = 'BBBK1\n';
  static const _saltBytes = 16;
  static const _nonceBytes = 12;

  /// Cost of turning the password into a key. High enough to make a guessing
  /// attack on a stolen file expensive, low enough that an old phone still
  /// unlocks it in about a second.
  static const defaultIterations = 200000;

  /// Sanity bound on the number read from a file — a hostile 2-billion-round
  /// header would otherwise hang the app on open.
  static const _maxIterations = 5000000;

  static final _cipher = AesGcm.with256bits();
  static final _random = Random.secure();

  /// A fresh salt. Not taken from `newNonce()`: that is 12 bytes long, so
  /// asking it for 16 silently yields 12 and every file written that way
  /// decrypts against the wrong slice.
  static List<int> _newSalt() =>
      List<int>.generate(_saltBytes, (_) => _random.nextInt(256));

  static Future<SecretKey> _deriveKey(
      String password, List<int> salt, int iterations) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// Encrypt [data] (the plain backup map) into the bytes of a `.bbbk` file.
  static Future<Uint8List> encrypt(
    Map<String, dynamic> data,
    String password, {
    List<int>? salt,
    List<int>? nonce,
    int iterations = defaultIterations,
  }) async {
    if (password.isEmpty) {
      throw const BackupError('Ohne Passwort geht es nicht.');
    }
    final theSalt = salt ?? _newSalt();
    final key = await _deriveKey(password, theSalt, iterations);
    final box = await _cipher.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
      nonce: nonce ?? _cipher.newNonce(),
    );
    return Uint8List.fromList([
      ...utf8.encode(_magic),
      ..._uint32(iterations),
      ...theSalt,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// Decrypt a `.bbbk` file back into the backup map.
  ///
  /// Throws [BackupError] for anything that isn't a readable backup: the wrong
  /// file, a truncated one, a tampered one, or the wrong password. The rider
  /// gets one honest sentence instead of a stack trace.
  static Future<Map<String, dynamic>> decrypt(
      List<int> bytes, String password) async {
    final magic = utf8.encode(_magic);
    final macBytes = 16; // AES-GCM tag
    if (bytes.length < magic.length + 4 + _saltBytes + _nonceBytes + macBytes) {
      throw const BackupError('Die Datei ist keine Besser-Bahn-Sicherung.');
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) {
        throw const BackupError('Die Datei ist keine Besser-Bahn-Sicherung.');
      }
    }
    var at = magic.length;
    final iterations = (bytes[at] << 24) |
        (bytes[at + 1] << 16) |
        (bytes[at + 2] << 8) |
        bytes[at + 3];
    at += 4;
    if (iterations <= 0 || iterations > _maxIterations) {
      throw const BackupError('Die Sicherung ist beschädigt.');
    }
    final salt = bytes.sublist(at, at += _saltBytes);
    final nonce = bytes.sublist(at, at += _nonceBytes);
    final cipherText = bytes.sublist(at, bytes.length - macBytes);
    final mac = Mac(bytes.sublist(bytes.length - macBytes));

    try {
      final key = await _deriveKey(password, salt, iterations);
      final clear = await _cipher.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: key,
      );
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const BackupError('Die Sicherung ist beschädigt.');
      }
      return decoded;
    } on BackupError {
      rethrow;
    } catch (_) {
      // SecretBoxAuthenticationError and a wrong-password decode failure are
      // the same event from outside: this file will not open with this word.
      throw const BackupError(
          'Falsches Passwort — oder die Datei ist beschädigt.');
    }
  }

  static List<int> _uint32(int v) =>
      [(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  /// Suggested file name, e.g. `besser-bahn-2026-08-05.bbbk`.
  static String fileNameFor(DateTime now) {
    final d = now.toIso8601String().split('T').first;
    return 'besser-bahn-$d.bbbk';
  }
}

/// A backup that cannot be written or read, with a sentence fit to show.
class BackupError implements Exception {
  final String message;
  const BackupError(this.message);
  @override
  String toString() => message;
}
