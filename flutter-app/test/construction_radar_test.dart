import 'package:besser_bahn/utils/construction_radar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isConstructionNote (#62)', () {
    test('matches planned construction / replacement notes', () {
      const yes = [
        'Wegen Bauarbeiten Ersatzverkehr mit Bussen',
        'Streckensperrung zwischen Kiel und Neumünster',
        'Zug wird umgeleitet, geänderte Reisezeit',
        'Schienenersatzverkehr eingerichtet',
        'Gleis baubedingt gesperrt',
        'Baumaßnahme im Bahnhofsbereich',
      ];
      for (final n in yes) {
        expect(isConstructionNote(n), isTrue, reason: n);
      }
    });

    test('does not match ordinary realtime running notes', () {
      const no = [
        '5 Minuten später',
        'Reservierung nicht möglich',
        'Fahrradmitnahme begrenzt',
        'Hält nur zum Aussteigen',
      ];
      for (final n in no) {
        expect(isConstructionNote(n), isFalse, reason: n);
      }
    });
  });

  group('constructionNotes (#62)', () {
    test('keeps only construction notes, de-duplicated, order preserved', () {
      final out = constructionNotes([
        '5 Minuten später',
        'Wegen Bauarbeiten Ersatzverkehr',
        'Wegen Bauarbeiten Ersatzverkehr', // dup
        'Streckensperrung Abschnitt A',
        '   ', // empty
      ]);
      expect(out, [
        'Wegen Bauarbeiten Ersatzverkehr',
        'Streckensperrung Abschnitt A',
      ]);
    });

    test('empty in, empty out', () {
      expect(constructionNotes(const []), isEmpty);
      expect(constructionNotes(['nur eine Verspätung']), isEmpty);
    });
  });
}
