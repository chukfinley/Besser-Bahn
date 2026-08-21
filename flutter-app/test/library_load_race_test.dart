import 'dart:convert';

import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/library_models.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/library_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saving something in the first moments after launch must survive the library
/// load that is still in flight.
///
/// Reading the stored library is asynchronous. The load used to assign a whole
/// fresh state when it landed, so anything saved in between — a tap on "merken"
/// right after start, or a screen opened straight from a notification — was
/// silently wiped, with the entry still sitting in storage but gone from the
/// app until the next launch.

/// A trip that is still in the future, so the load's purge of long-past trips
/// cannot be what removes it.
Journey _journey(String from, String to) {
  final soon = DateTime.now().add(const Duration(days: 1));
  return Journey(
    legs: [
      JourneyLeg(
        origin: Station(id: from, name: from),
        destination: Station(id: to, name: to),
        plannedDeparture: soon,
        departure: soon,
        plannedArrival: soon.add(const Duration(hours: 2)),
        arrival: soon.add(const Duration(hours: 2)),
      ),
    ],
  );
}

void main() {
  test('a trip saved during the load is still there afterwards', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Touch the provider (starts the async load) and save before it lands.
    container.read(libraryProvider);
    container.read(libraryProvider.notifier).toggleJourney(_journey('A', 'B'));
    expect(container.read(libraryProvider).journeys, hasLength(1));

    // Let the load finish.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(container.read(libraryProvider).loaded, isTrue);
    expect(
      container.read(libraryProvider).journeys,
      hasLength(1),
      reason: 'the load must not overwrite what was saved meanwhile',
    );
  });

  test('stored entries and entries saved meanwhile both survive', () async {
    // getInstance() caches per isolate, so without this reset the second test
    // reads the first test's (empty) store and the case under test never runs.
    SharedPreferences.resetStatic();
    final stored = SavedJourney(journey: _journey('C', 'D'), savedAtMs: 0);
    SharedPreferences.setMockInitialValues({
      'lib_journeys_v1': jsonEncode([stored.toJson()]),
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(libraryProvider);
    container.read(libraryProvider.notifier).toggleJourney(_journey('A', 'B'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final keys = container
        .read(libraryProvider)
        .journeys
        .map((j) => j.key)
        .toSet();
    expect(keys, hasLength(2));
    expect(keys, contains(stored.key));
  });
}
