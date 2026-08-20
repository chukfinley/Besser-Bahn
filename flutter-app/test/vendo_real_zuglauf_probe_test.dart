// ignore_for_file: avoid_print
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'probe: extract real zuglauf IDs from Vendo journey search',
    () async {
      final service = VendoService();

      final result = await service.searchJourneys(
        fromLocationId: 'A=1@L=8000207@',
        toLocationId: 'A=1@L=8011160@',
        dateTime: DateTime.now(),
      );

      print('\n========== REAL ZUGLAUF IDS ==========');

      var count = 0;

      for (final journey in result.journeys) {
        for (final leg in journey.legs) {
          if (leg.isWalking || leg.tripId == null) {
            continue;
          }

          count++;

          print(
            '[$count] '
            '${leg.origin.name} → ${leg.destination.name} | '
            'train=${leg.line?.fahrtNr ?? 'unknown'} | '
            'tripId=${leg.tripId}',
          );
        }
      }

      print('======================================\n');

      expect(
        result.journeys,
        isNotEmpty,
        reason: 'The real Vendo API returned no journeys.',
      );

      expect(
        count,
        greaterThan(0),
        reason: 'No non-walking leg with a zuglaufId was found.',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
