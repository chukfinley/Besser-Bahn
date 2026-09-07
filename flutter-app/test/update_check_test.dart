import 'package:besser_bahn/core/constants.dart';
import 'package:besser_bahn/services/update_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Versionsvergleich', () {
    test('eine höhere Version ist neuer', () {
      expect(UpdateCheckService.isNewer('2.5.0', '2.4.1'), isTrue);
      expect(UpdateCheckService.isNewer('2.4.2', '2.4.1'), isTrue);
      expect(UpdateCheckService.isNewer('3.0.0', '2.9.9'), isTrue);
    });

    test('gleiche oder ältere Version löst nichts aus', () {
      expect(UpdateCheckService.isNewer('2.4.1', '2.4.1'), isFalse);
      expect(UpdateCheckService.isNewer('2.4.0', '2.4.1'), isFalse);
      expect(UpdateCheckService.isNewer('1.9.9', '2.0.0'), isFalse);
    });

    test('Zahlen werden numerisch verglichen, nicht als Text', () {
      // "10" < "9" wäre die Textreihenfolge und würde jedes Update ab 2.10
      // verschlucken.
      expect(UpdateCheckService.isNewer('2.10.0', '2.9.0'), isTrue);
      expect(UpdateCheckService.isNewer('2.9.0', '2.10.0'), isFalse);
    });

    test('fehlende Stellen zählen als 0', () {
      expect(UpdateCheckService.isNewer('2.5', '2.4.1'), isTrue);
      expect(UpdateCheckService.isNewer('2.4', '2.4.1'), isFalse);
      expect(UpdateCheckService.isNewer('2.4.0', '2.4'), isFalse);
    });

    test('rc-Suffix zählt wie die Version ohne Suffix', () {
      expect(UpdateCheckService.isNewer('2.5.0-rc.1', '2.4.1'), isTrue);
      expect(UpdateCheckService.isNewer('2.4.1-rc.1', '2.4.1'), isFalse);
    });

    test('die eigene Version gilt nie als Update', () {
      expect(
        UpdateCheckService.isNewer(
          AppConstants.appVersion,
          AppConstants.appVersion,
        ),
        isFalse,
      );
    });
  });
}
