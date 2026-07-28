import 'package:besser_bahn/utils/plain_language.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('simplifyNote (#74)', () {
    test('swaps jargon for plainer words, case-insensitive', () {
      expect(simplifyNote('Aufgrund Bauarbeiten entfällt der Halt'),
          'wegen Baustelle fällt aus der Halt');
      expect(simplifyNote('Verkehrt unregelmäßig'), 'fährt nicht nach Plan');
    });

    test('longest match wins (Schienenersatzverkehr, not Ersatzverkehr)', () {
      expect(simplifyNote('Es gibt Schienenersatzverkehr.'),
          'Es gibt Ersatz-Bus statt Zug.');
    });

    test('leaves text without jargon untouched', () {
      expect(simplifyNote('Zug fährt pünktlich'), 'Zug fährt pünktlich');
    });

    test('plainNote respects the enabled flag', () {
      const raw = 'Aufgrund Bauarbeiten';
      expect(plainNote(raw, enabled: false), raw);
      expect(plainNote(raw, enabled: true), 'wegen Baustelle');
    });
  });
}
