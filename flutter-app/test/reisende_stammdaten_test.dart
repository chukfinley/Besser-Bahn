import 'package:besser_bahn/models/reisende.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every `ermaessigungen` key the live master data lists
/// (GET /mob/stammdaten, 2026-07-16). The drift against the running API is
/// checked by api-tests/healthcheck.py — this pins the app side, so a key can't
/// be dropped or fat-fingered without a test saying so.
const _liveErmaessigungen = {
  'A-VORTEILSCARD KLASSENLOS',
  'BAHNCARD100 KLASSE_1',
  'BAHNCARD100 KLASSE_2',
  'BAHNCARD25 KLASSE_1',
  'BAHNCARD25 KLASSE_2',
  'BAHNCARD50 KLASSE_1',
  'BAHNCARD50 KLASSE_2',
  'BAHNCARDBUSINESS25 KLASSE_1',
  'BAHNCARDBUSINESS25 KLASSE_2',
  'BAHNCARDBUSINESS50 KLASSE_1',
  'BAHNCARDBUSINESS50 KLASSE_2',
  'CH-GENERAL-ABONNEMENT KLASSE_1',
  'CH-GENERAL-ABONNEMENT KLASSE_2',
  'CH-HALBTAXABO_OHNE_RAILPLUS KLASSENLOS',
  'KEINE_ERMAESSIGUNG KLASSENLOS',
  'KLIMATICKET_OE KLASSE_2',
  'NL-100 KLASSENLOS',
  'NL-40_OHNE_RAILPLUS KLASSENLOS',
  'SBA_BEEINTRAECHTIGUNGEN_MIT_ROLLSTUHL KLASSENLOS',
  'SBA_BEGLEITPERSON_KEIN_ROLLSTUHL KLASSENLOS',
  'SBA_BEGLEITPERSON_MIT_ROLLSTUHL KLASSENLOS',
};

void main() {
  group('Reduction vs the live master data (#21)', () {
    test('every live discount is offered', () {
      final ours = {
        for (final r in Reduction.values) r.vendoKey,
        for (final s in SbaOption.values)
          if (s.vendoKey.isNotEmpty) s.vendoKey,
      };
      expect(
        ours,
        containsAll(_liveErmaessigungen),
        reason:
            'a discount DB lists and we do not is money the rider '
            'silently leaves on the table',
      );
    });

    test('NL-100 is offered under "Weitere Ermäßigungen"', () {
      // Found by diffing the master data, and worth real money: on
      // Köln→Amsterdam it takes 73,99 € to 51,60 €.
      expect(Reduction.nl100.vendoKey, 'NL-100 KLASSENLOS');
      expect(Reduction.weitereOptions, contains(Reduction.nl100));
      expect(
        Reduction.bahnCardOptions,
        isNot(contains(Reduction.nl100)),
        reason: 'a Dutch railcard is not a BahnCard',
      );
    });

    test('the de-listed SBA option is kept on purpose', () {
      // The endpoint answers an invented key with 200 and an unchanged price,
      // so "not listed" is no evidence it stopped working — and dropping it
      // would take a real option from riders who hold that card.
      expect(
        SbaOption.beeintrOhneRolli.vendoKey,
        'SBA_BEEINTRAECHTIGUNGEN_KEIN_ROLLSTUHL KLASSENLOS',
      );
      expect(
        _liveErmaessigungen,
        isNot(contains(SbaOption.beeintrOhneRolli.vendoKey)),
      );
    });

    test('a chosen discount reaches the request', () {
      final json = const Traveler(
        typ: TravelerType.erwachsener,
        weitere: Reduction.nl100,
      ).toVendoJson();
      expect(json['ermaessigungen'], contains('NL-100 KLASSENLOS'));
    });

    test('keys round-trip through byKey', () {
      for (final r in Reduction.values) {
        expect(Reduction.byKey(r.vendoKey), r);
      }
      expect(
        Reduction.byKey('SOMETHING DB INVENTED'),
        Reduction.none,
        reason: 'an unknown stored key must not throw',
      );
    });
  });
}
