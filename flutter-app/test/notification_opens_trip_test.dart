import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/library_models.dart';
import 'package:besser_bahn/providers/library_provider.dart';
import 'package:besser_bahn/services/notification_service.dart';
import 'package:besser_bahn/services/trip_reminder_scheduler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tapping a trip notification has to land on THAT trip's Reiseplan, not just
/// open the app.
///
/// What makes that possible is a key travelling all the way from the saved trip
/// into the notification's payload and back out again. These tests pin the two
/// ends we can test without an OS notification plugin: every planned reminder
/// carries the key of the trip it is about, and that key still finds the trip in
/// the library afterwards.

final _base = DateTime(2026, 8, 1, 10, 0);

Journey _journey({required String originId, DateTime? departure}) {
  final dep = departure ?? _base;
  return Journey.fromJson({
    'legs': [
      {
        'origin': {'id': originId, 'name': 'Kiel Hbf'},
        'destination': {'id': '8002549', 'name': 'Hamburg Hbf'},
        'plannedDeparture': dep.toIso8601String(),
        'plannedArrival': dep
            .add(const Duration(minutes: 75))
            .toIso8601String(),
        'line': {'name': 'ICE 71'},
      },
    ],
  });
}

SavedJourney _saved(Journey journey) =>
    SavedJourney(journey: journey, savedAtMs: 7, watched: true);

List<TripReminder> _plan(List<SavedJourney> trips) =>
    TripReminderScheduler.plan(
      trips,
      leadMinutes: 30,
      departureReminders: true,
      transferAlerts: true,
      arrivalAlert: true,
      arrivalAlarmSound: true,
      now: _base.subtract(const Duration(hours: 3)),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('a scheduled reminder knows which trip it is about', () {
    test('every ping carries the saved trip key', () {
      final trip = _saved(_journey(originId: '8000199'));
      final planned = _plan([trip]);

      expect(planned, isNotEmpty);
      expect(
        planned.every((r) => r.tripKey == trip.key),
        isTrue,
        reason: 'a ping without a key opens the app and nothing else',
      );
    });

    test('the loud arrival alarm carries it too — it is the one you get woken '
        'by and most need the Reiseplan from', () {
      final trip = _saved(_journey(originId: '8000199'));
      final alarms = _plan([trip]).where((r) => r.alarm);

      expect(alarms, isNotEmpty);
      expect(alarms.every((r) => r.tripKey == trip.key), isTrue);
    });

    test('two trips do not get each other\'s key', () {
      final kiel = _saved(_journey(originId: '8000199'));
      final hamburg = _saved(
        _journey(
          originId: '8002549',
          departure: _base.add(const Duration(hours: 1)),
        ),
      );

      final keys = _plan([kiel, hamburg]).map((r) => r.tripKey).toSet();

      expect(keys, {kiel.key, hamburg.key});
      expect(kiel.key, isNot(hamburg.key));
    });

    test('withTripKey changes nothing else about the ping', () {
      final original = TripReminder(
        when: _base,
        title: 'Gleich Abfahrt',
        body: 'ICE 71 ab Kiel Hbf',
        alarm: true,
      );
      final stamped = original.withTripKey('abc');

      expect(stamped.when, original.when);
      expect(stamped.title, original.title);
      expect(stamped.body, original.body);
      expect(stamped.alarm, original.alarm);
      expect(original.tripKey, isEmpty, reason: 'the original is untouched');
    });
  });

  group('the key still finds the trip when the tap comes back', () {
    test('a planned key resolves to exactly that saved trip', () async {
      final trip = _saved(_journey(originId: '8000199'));
      final other = _saved(
        _journey(
          originId: '8002549',
          departure: _base.add(const Duration(hours: 1)),
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final library = container.read(libraryProvider.notifier);
      library.toggleJourney(trip.journey);
      library.toggleJourney(other.journey);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final key = _plan([trip]).first.tripKey;
      final found = container
          .read(libraryProvider)
          .journeys
          .where((j) => j.key == key)
          .firstOrNull;

      expect(found, isNotNull);
      expect(found!.journey.origin?.id, '8000199');
    });

    test('the library says whether it has been read yet — an empty list right '
        'after launch means "not loaded", not "trip is gone"', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(libraryProvider).loaded, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(container.read(libraryProvider).loaded, isTrue);
    });
  });

  group('what a tap means', () {
    NotificationResponse tap({String? payload, String? actionId}) =>
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          payload: payload,
          actionId: actionId,
        );

    test('tapping a trip notification hands the trip on — twice over, so a '
        'cold start finds it too', () async {
      final opened = NotificationService.tripOpens.first;

      await NotificationService.handleResponseForTest(
        tap(payload: 'trip:8000199_8002549_2026-08-01T10:00'),
      );

      expect(await opened, '8000199_8002549_2026-08-01T10:00');
      // Persisted for the case where nothing was listening yet, and consumed
      // exactly once.
      expect(
        await NotificationService.takePendingTripKey(),
        '8000199_8002549_2026-08-01T10:00',
      );
      expect(await NotificationService.takePendingTripKey(), isNull);
    });

    test(
      '"Stoppen" on the arrival alarm silences it and goes nowhere',
      () async {
        await NotificationService.handleResponseForTest(
          tap(
            payload: 'trip:8000199_8002549_2026-08-01T10:00',
            actionId: 'stop_alarm',
          ),
        );

        expect(
          await NotificationService.takePendingTripKey(),
          isNull,
          reason:
              'the rider is switching it off, not asking to be taken '
              'anywhere',
        );
      },
    );

    test('a notification without a trip behaves as before', () async {
      await NotificationService.handleResponseForTest(tap());
      await NotificationService.handleResponseForTest(tap(payload: 'trip:'));
      await NotificationService.handleResponseForTest(
        tap(payload: 'split-result'),
      );

      expect(await NotificationService.takePendingTripKey(), isNull);
    });

    test(
      'the missed-connection prompt still needs its explicit action — a body '
      'tap must not be read as approval',
      () async {
        const payload = 'missed-connection:not-a-valid-rescue';

        await NotificationService.handleResponseForTest(tap(payload: payload));
        expect(await NotificationService.takePendingMissedRescue(), isNull);

        // And it is not mistaken for a trip either.
        expect(await NotificationService.takePendingTripKey(), isNull);
      },
    );
  });
}
