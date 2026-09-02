import 'package:besser_bahn/services/station_map_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// bahnhof.de slug resolution. The tricky part is DB's trailing transit-mode
/// qualifier — "Hamburg-Altona(S)" is the S-Bahn part of the same station, and
/// leaving the "(S)" in resolved to a page without map data, so the platform
/// overlay went missing at those stops. Mid-name parentheses like the "(Main)"
/// in "Frankfurt (Main) Hbf" ARE part of the slug and must stay.
void main() {
  group('StationMapService.slugify', () {
    test('drops a trailing S-Bahn/U-Bahn qualifier', () {
      expect(StationMapService.slugify('Hamburg-Altona(S)'), 'hamburg-altona');
      expect(StationMapService.slugify('Hamburg-Harburg(S)'), 'hamburg-harburg');
      expect(StationMapService.slugify('Berlin Alexanderplatz (S)'),
          'berlin-alexanderplatz');
      expect(StationMapService.slugify('Some Halt (S+U)'), 'some-halt');
    });

    test('keeps mid-name parentheses that belong to the slug', () {
      expect(StationMapService.slugify('Frankfurt (Main) Hbf'),
          'frankfurt-main-hbf');
      expect(StationMapService.slugify('Berg (b Neumarkt)'), 'berg-b-neumarkt');
    });

    test('plain names + umlauts unchanged', () {
      expect(StationMapService.slugify('Würzburg Hbf'), 'wuerzburg-hbf');
      expect(StationMapService.slugify('Kiel Hbf'), 'kiel-hbf');
      expect(StationMapService.slugify('Büchen'), 'buechen');
    });
  });
}
