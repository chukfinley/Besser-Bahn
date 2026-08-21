import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/journey_search_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every value of the DB Navigator's `VerkehrsmittelModel` enum except ALL,
/// read out of its APK. If DB adds one, [ProductCategory] must place it —
/// otherwise that mode silently drops out of every filtered search.
const _vendoEnum = {
  'HOCHGESCHWINDIGKEITSZUEGE',
  'INTERCITYUNDEUROCITYZUEGE',
  'INTERREGIOUNDSCHNELLZUEGE',
  'NAHVERKEHRSONSTIGEZUEGE',
  'SBAHNEN',
  'BUSSE',
  'SCHIFFE',
  'UBAHN',
  'STRASSENBAHN',
  'ANRUFPFLICHTIGEVERKEHRE',
};

Station _st(String name) => Station(id: name, name: name);

Journey _journey(String product) => Journey(
  legs: [
    JourneyLeg(
      tripId: 't-$product',
      origin: _st('München Hbf'),
      destination: _st('Augsburg Hbf'),
      plannedDeparture: DateTime(2026, 7, 16, 9),
      arrival: DateTime(2026, 7, 16, 9, 31),
      line: TransitLine(
        name: product,
        fahrtNr: '568',
        productName: product,
        product: product,
      ),
    ),
  ],
);

void main() {
  group('ProductCategory.codesFor', () {
    test('all categories selected asks for ALL', () {
      expect(ProductCategory.codesFor(ProductCategory.values.toSet()), ['ALL']);
    });

    test('empty selection falls back to ALL rather than an empty query', () {
      expect(ProductCategory.codesFor({}), ['ALL']);
    });

    test('regression #18: dropping Fernverkehr still asks for the rest', () {
      // The reported case: München–Augsburg with "Fernverkehr" switched off.
      // The query must name every remaining mode — asking for ALL and
      // filtering afterwards is what returned an empty list.
      final codes = ProductCategory.codesFor(
        ProductCategory.values.toSet()..remove(ProductCategory.fern),
      );

      expect(codes, isNot(contains('ALL')));
      expect(codes, contains('NAHVERKEHRSONSTIGEZUEGE'));
      expect(codes, isNot(contains('HOCHGESCHWINDIGKEITSZUEGE')));
      expect(codes, isNot(contains('INTERCITYUNDEUROCITYZUEGE')));
      expect(codes, isNot(contains('INTERREGIOUNDSCHNELLZUEGE')));
    });

    test('Fern mirrors the Navigator: ICE + IC/EC + IR', () {
      expect(ProductCategory.codesFor({ProductCategory.fern}), [
        'HOCHGESCHWINDIGKEITSZUEGE',
        'INTERCITYUNDEUROCITYZUEGE',
        'INTERREGIOUNDSCHNELLZUEGE',
      ]);
    });

    test('categories cover the enum exactly, with no mode in two places', () {
      final all = [for (final c in ProductCategory.values) ...c.vendoCodes];
      expect(
        all.toSet(),
        _vendoEnum,
        reason: 'ProductCategory must cover every VerkehrsmittelModel value',
      );
      expect(
        all.length,
        all.toSet().length,
        reason: 'a mode assigned to two categories is sent twice',
      );
    });
  });

  group('onlyDeutschlandTicket', () {
    test('defaults off and survives an unrelated copyWith', () {
      expect(JourneySearchState().onlyDeutschlandTicket, isFalse);
      expect(
        JourneySearchState(
          onlyDeutschlandTicket: true,
        ).copyWith(sortMode: JourneySortMode.duration).onlyDeutschlandTicket,
        isTrue,
        reason: 'copyWith must carry the flag, or the re-search drops it',
      );
    });
  });

  group('JourneySearchState.sortedJourneys', () {
    test('regression #18: does not re-filter what the backend returned', () {
      // The backend already searched for the selected modes only. Re-checking
      // the products here is what emptied the list, and it would also drop a
      // feeder bus the backend deliberately included on a regional trip.
      final state = JourneySearchState(
        result: JourneyResult(journeys: [_journey('nationalExpress')]),
        products: {ProductCategory.regional},
      );
      expect(state.sortedJourneys, hasLength(1));
    });
  });
}
