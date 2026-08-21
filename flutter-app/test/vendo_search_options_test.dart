import 'dart:convert';

import 'package:besser_bahn/models/search_options.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/models/transfer_profile.dart';
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An empty but valid result — these tests are about what we *send*.
final _emptyResult = json.encode({'verbindungen': []});

Station _st(String name, String loc) =>
    Station(id: name, name: name, locationId: loc);

/// Captures the `reiseHin.wunsch` of a single search.
Future<Map<String, dynamic>> _wunschOf(
  Future<void> Function(VendoService) search,
) async {
  late Map<String, dynamic> wunsch;
  final svc = VendoService(
    client: MockClient((req) async {
      final body =
          json.decode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;
      wunsch =
          (body['reiseHin'] as Map<String, dynamic>)['wunsch']
              as Map<String, dynamic>;
      return http.Response.bytes(utf8.encode(_emptyResult), 200);
    }),
  );
  await search(svc);
  return wunsch;
}

void main() {
  group('searchJourneys wunsch (#19)', () {
    test('sends nothing extra when no option is set', () async {
      final wunsch = await _wunschOf(
        (svc) => svc.searchJourneys(
          fromLocationId: 'A=1@O=Köln Hbf@L=8000207@',
          toLocationId: 'A=1@O=München Hbf@L=8000261@',
        ),
      );

      // Absent, not null: DB's wunsch is a sparse object, and sending
      // `maxUmstiege: null` is not the same request as omitting it.
      expect(wunsch.containsKey('maxUmstiege'), isFalse);
      expect(wunsch.containsKey('minUmstiegsdauer'), isFalse);
      expect(wunsch.containsKey('viaLocations'), isFalse);
    });

    test(
      'max transfers, min transfer time and via travel with the request',
      () async {
        final wunsch = await _wunschOf(
          (svc) => svc.searchJourneys(
            fromLocationId: 'A=1@O=Köln Hbf@L=8000207@',
            toLocationId: 'A=1@O=München Hbf@L=8000261@',
            maxTransfers: 0,
            minTransferMinutes: 30,
            viaLocations: const [
              {
                'locationId': 'A=1@O=Frankfurt(Main)Hbf@L=8000105@',
                'minUmstiegsdauer': 60,
              },
            ],
          ),
        );

        expect(wunsch['maxUmstiege'], 0);
        expect(wunsch['minUmstiegsdauer'], 30);
        expect(wunsch['viaLocations'], [
          {
            'locationId': 'A=1@O=Frankfurt(Main)Hbf@L=8000105@',
            'minUmstiegsdauer': 60,
          },
        ]);
      },
    );

    test('maxTransfers: 0 is sent, not swallowed as falsy', () async {
      // The direct-trains-only case — the one value most likely to be lost to
      // a `if (maxTransfers != null)` written as `if (maxTransfers != 0)`.
      final wunsch = await _wunschOf(
        (svc) => svc.searchJourneys(
          fromLocationId: 'A=1@O=Köln Hbf@L=8000207@',
          toLocationId: 'A=1@O=München Hbf@L=8000261@',
          maxTransfers: 0,
        ),
      );
      expect(wunsch['maxUmstiege'], 0);
    });
  });

  group('SearchOptions', () {
    final frankfurt = _st(
      'Frankfurt(Main)Hbf',
      'A=1@O=Frankfurt(Main)Hbf@L=8000105@',
    );

    test('viaLocationsJson is null without a via, and carries the stay', () {
      expect(const SearchOptions().viaLocationsJson, isNull);
      expect(SearchOptions(via: frankfurt).viaLocationsJson, [
        {'locationId': frankfurt.vendoLocationId},
      ]);
      expect(
        SearchOptions(via: frankfurt, viaStayMinutes: 60).viaLocationsJson,
        [
          {'locationId': frankfurt.vendoLocationId, 'minUmstiegsdauer': 60},
        ],
      );
    });

    test('activeCount counts constraints, not the via stay', () {
      // The stay only exists as a property of the via — counting it too would
      // badge "2" for what the rider set once.
      expect(const SearchOptions().activeCount, 0);
      expect(SearchOptions(via: frankfurt, viaStayMinutes: 60).activeCount, 1);
      expect(
        SearchOptions(
          maxTransfers: 0,
          minTransferMinutes: 30,
          via: frankfurt,
        ).activeCount,
        3,
      );
    });

    test('clearing the via clears its stay', () {
      final opts = SearchOptions(
        via: frankfurt,
        viaStayMinutes: 60,
      ).copyWith(clearVia: true);
      expect(opts.via, isNull);
      expect(
        opts.viaStayMinutes,
        isNull,
        reason: 'a stay without a via would be sent as a bare wish',
      );
    });

    test('directOnly is maxTransfers 0, not "some cap"', () {
      expect(const SearchOptions(maxTransfers: 0).directOnly, isTrue);
      expect(const SearchOptions(maxTransfers: 1).directOnly, isFalse);
      expect(const SearchOptions().directOnly, isFalse);
    });
  });

  group('TransferProfile.minTransferMinutes', () {
    test('fast/normal ask for nothing — DB already plans for them', () {
      expect(TransferProfile.fast.minTransferMinutes, isNull);
      expect(TransferProfile.normal.minTransferMinutes, isNull);
    });

    test('slower profiles ask for more slack, monotonically', () {
      const ordered = [
        TransferProfile.luggage,
        TransferProfile.child,
        TransferProfile.accessible,
        TransferProfile.slow,
      ];
      final mins = [for (final p in ordered) p.minTransferMinutes!];
      final sorted = [...mins]..sort();
      expect(
        mins,
        sorted,
        reason: 'a slower profile must never ask for less slack',
      );
    });
  });
}
