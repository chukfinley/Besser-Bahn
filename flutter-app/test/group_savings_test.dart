import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/reisende.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/group_savings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

/// Group booking vs. N single bookings (#67). The comparison itself is one
/// subtraction; what matters is when the app is allowed to open its mouth.

Journey _journey(DateTime dep) => Journey(legs: [
      JourneyLeg(
        origin: Station(id: 'a', name: 'A'),
        destination: Station(id: 'b', name: 'B'),
        plannedDeparture: dep,
      ),
    ]);

void main() {
  final dep = DateTime(2026, 8, 5, 9, 12);

  group('groupSavingFor', () {
    test('names the saving when singles are genuinely cheaper', () {
      final saving = GroupSaving(
          departure: dep, groupTotal: 180, singlesTotal: 168);
      expect(groupSavingFor([saving], _journey(dep))?.savings, 12);
    });

    test('says nothing when the group booking wins — the normal case', () {
      final saving = GroupSaving(
          departure: dep, groupTotal: 150, singlesTotal: 168);
      expect(groupSavingFor([saving], _journey(dep)), isNull);
    });

    test('ignores rounding noise below a euro', () {
      final saving = GroupSaving(
          departure: dep, groupTotal: 168.02, singlesTotal: 168);
      expect(groupSavingFor([saving], _journey(dep)), isNull);
    });

    test('matches on departure, not on position in the list', () {
      final other = GroupSaving(
          departure: dep.add(const Duration(hours: 1)),
          groupTotal: 300,
          singlesTotal: 100);
      expect(groupSavingFor([other], _journey(dep)), isNull);
    });
  });

  group('SearchParty.toSingleTravellerJson', () {
    test('keeps one person with their discounts, drops bike and dog', () {
      const party = SearchParty(travelers: [
        Traveler(typ: TravelerType.erwachsener, alter: 40),
        Traveler(typ: TravelerType.erwachsener, alter: 38),
        Traveler(typ: TravelerType.fahrrad),
        Traveler(typ: TravelerType.hund),
      ]);
      final json = party.toSingleTravellerJson();
      expect(json, hasLength(1));
      expect(json.first['reisendenTyp'], 'ERWACHSENER');
    });

    test('a party without a person falls back to what it has', () {
      const party = SearchParty(travelers: [Traveler(typ: TravelerType.hund)]);
      expect(party.toSingleTravellerJson(), hasLength(1));
    });
  });
}
