// ignore_for_file: avoid_print
import 'package:besser_bahn/services/vendo_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'probe: fetch polyline using a real zuglaufId',
    () async {
      final service = VendoService();

      // 1. Get real journeys from the Vendo API.
      final result = await service.searchJourneys(
        fromLocationId: 'A=1@L=8000207@',
        toLocationId: 'A=1@L=8011160@',
        dateTime: DateTime.now(),
      );

      // 2. Find the first real train leg.
      final trainLeg = result.journeys
          .expand((journey) => journey.legs)
          .firstWhere((leg) => !leg.isWalking && leg.tripId != null);

      final zuglaufId = trainLeg.tripId!;

      print('\n========== REAL ZUGLAUF ==========');
      print('Train: ${trainLeg.line?.fahrtNr}');
      print('${trainLeg.origin.name} → ${trainLeg.destination.name}');
      print('zuglaufId: $zuglaufId');

      // 3. Fetch the real train's route geometry.
      final points = await service.fetchTripPolyline(zuglaufId);

      print('Polyline points: ${points?.length ?? 0}');

      if (points != null && points.isNotEmpty) {
        print('First point: ${points.first}');
        print('Last point:  ${points.last}');
      }

      print('==================================\n');

      expect(points, isNotNull, reason: 'Zuglauf API returned no polyline.');

      expect(
        points,
        isNotEmpty,
        reason: 'Zuglauf API returned an empty polyline.',
      );
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}
