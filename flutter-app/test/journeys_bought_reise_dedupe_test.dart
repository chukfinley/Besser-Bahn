import 'package:besser_bahn/models/db_ticket.dart';
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/library_models.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/account_provider.dart';
import 'package:besser_bahn/screens/journeys/journeys_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// #80: a trip the user tracked on the DB account and then BOUGHT arrives from
/// `reisenuebersicht` twice — as an order and as a tracked Reise — and the
/// Reisen tab listed it twice: as a ticket on top, again under "Gemerkte
/// Reisen".

Station _st(String id, String name) => Station(id: id, name: name);

Journey _journey(DateTime dep) => Journey(
  legs: [
    JourneyLeg(
      origin: _st('8011160', 'Berlin Hbf'),
      destination: _st('8000152', 'Hannover Hbf'),
      plannedDeparture: dep,
      departure: dep,
      plannedArrival: dep.add(const Duration(hours: 2)),
      arrival: dep.add(const Duration(hours: 2)),
    ),
  ],
);

DbTicketTrip _ticketTrip(Journey j) => DbTicketTrip(
  index: const DbReiseIndex(auftragsnummer: 'A1', kundenwunschIds: ['K1']),
  ticketKey: 'A1/K1',
  journey: j,
);

void main() {
  final dep = DateTime(2026, 8, 20, 9, 34);
  final journey = _journey(dep);
  final key = SavedJourney(journey: journey, savedAtMs: 0).key;

  group('gekaufte Reise verschwindet aus "Gemerkte Reisen" (#80)', () {
    test('the tracked twin of a bought ticket is hidden', () {
      final ticketKeys = {_ticketTrip(journey).journeyKey!};
      final hidden = boughtSavedReiseIds(
        savedReiseIds: {key: 'rk-1'},
        ticketKeys: ticketKeys,
      );
      expect(hidden, {'rk-1'});
    });

    test('a tracked trip without a ticket stays visible', () {
      final other = SavedJourney(
        journey: _journey(dep.add(const Duration(days: 1))),
        savedAtMs: 0,
      ).key;
      final hidden = boughtSavedReiseIds(
        savedReiseIds: {key: 'rk-1', other: 'rk-2'},
        ticketKeys: {_ticketTrip(journey).journeyKey!},
      );
      expect(hidden, {'rk-1'});
    });

    test('a ticket whose Verbindung would not parse hides nothing', () {
      const unparsed = DbTicketTrip(
        index: DbReiseIndex(auftragsnummer: 'A1', kundenwunschIds: ['K1']),
        ticketKey: 'A1/K1',
      );
      expect(unparsed.journeyKey, isNull);
      expect(
        boughtSavedReiseIds(savedReiseIds: {key: 'rk-1'}, ticketKeys: const {}),
        isEmpty,
      );
    });

    test('no DB bookmarks at all — nothing to hide', () {
      expect(
        boughtSavedReiseIds(
          savedReiseIds: const {},
          ticketKeys: {_ticketTrip(journey).journeyKey!},
        ),
        isEmpty,
      );
    });
  });
}
