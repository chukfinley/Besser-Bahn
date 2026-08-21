import 'dart:io';

import 'package:besser_bahn/models/station_map.dart';
import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StationFacility model (#73)', () {
    test('anything but ACTIVE is out of service', () {
      const active = StationFacility(
        type: 'ELEVATOR',
        description: 'x',
        stateType: 'ACTIVE',
      );
      const inactive = StationFacility(
        type: 'ELEVATOR',
        description: 'x',
        stateType: 'INACTIVE',
      );
      const unknown = StationFacility(
        type: 'ESCALATOR',
        description: 'x',
        stateType: 'UNKNOWN',
      );
      expect(active.outOfService, isFalse);
      expect(inactive.outOfService, isTrue);
      expect(unknown.outOfService, isTrue);
      expect(active.germanKind, 'Aufzug');
      expect(unknown.germanKind, 'Rolltreppe');
    });
  });

  group('bahnhof.de facility parsing (#73)', () {
    test('Kiel Hbf fixture: facilities parsed, all ACTIVE → none broken', () {
      final body = File('test/fixtures/kiel-hbf.rsc.txt').readAsStringSync();
      final map = parseStationMapBody('kiel-hbf', body);
      expect(map.facilities, isNotEmpty);
      expect(map.outOfServiceFacilities, isEmpty);
      expect(map.facilities.any((f) => f.isElevator), isTrue);
    });

    test('an INACTIVE state in the payload surfaces as out of service', () {
      // Take the real fixture and flip one lift to INACTIVE.
      final body = File('test/fixtures/hamburg-hbf.rsc.txt')
          .readAsStringSync()
          .replaceFirst(
            '"state":{"type":"ACTIVE","explanation":"available"},'
                '"associatedPlatforms":[],'
                '"description":"zu Gleis 13/14 Abschnitt E"',
            '"state":{"type":"INACTIVE","explanation":"not available"},'
                '"associatedPlatforms":[],'
                '"description":"zu Gleis 13/14 Abschnitt E"',
          );
      final map = parseStationMapBody('hamburg-hbf', body);
      final broken = map.outOfServiceFacilities;
      expect(broken, isNotEmpty);
      expect(broken.first.gleise, containsAll({'13', '14'}));
      // And it's found when filtering by the served Gleis.
      expect(map.outOfServiceForGleise({'13'}), isNotEmpty);
      expect(map.outOfServiceForGleise({'99'}), isEmpty);
    });
  });
}
