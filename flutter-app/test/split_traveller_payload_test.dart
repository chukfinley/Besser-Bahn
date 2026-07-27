import 'package:besser_bahn/models/reisende.dart';
import 'package:besser_bahn/models/split_ticket.dart';
import 'package:besser_bahn/providers/settings_provider.dart';
import 'package:besser_bahn/services/db_api_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a split-ticket price is computed FOR (#75).
///
/// The two halves of the analysis price the same trip through different
/// backends — Vendo with the party's `reisende`, the bahn.de web API with this
/// traveller payload — so a reduction that only reaches one of them makes the
/// segment prices disagree with each other and with what the rider pays. These
/// tests pin the payload and the settings path that feeds it.

List<Map<String, dynamic>> _reductions(Map<String, dynamic> traveller) =>
    (traveller['ermaessigungen'] as List).cast<Map<String, dynamic>>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('createTravellerPayload', () {
    test('no reduction still sends an explicit "none" entry', () {
      final payload = DbApiService.createTravellerPayload();
      expect(payload.length, 1);
      expect(payload.single['typ'], 'ERWACHSENER');
      expect(_reductions(payload.single), [
        {'art': 'KEINE_ERMAESSIGUNG', 'klasse': 'KLASSENLOS'},
      ]);
    });

    test('a BahnCard is split into art + klasse', () {
      final payload = DbApiService.createTravellerPayload(
        bahnCard: Reduction.byKey(BahnCardType.bc25_2.vendoErmaessigung),
      );
      final erm = _reductions(payload.single).single;
      expect(erm['art'], 'BAHNCARD25');
      expect(erm['klasse'], 'KLASSE_2');
    });

    test('Halbtax and SBA ride along instead of being dropped', () {
      const halbtax = Reduction.chHalbtax;
      const sba = SbaOption.beeintrMitRolli;

      final payload = DbApiService.createTravellerPayload(
        bahnCard: Reduction.byKey(BahnCardType.bc50_2.vendoErmaessigung),
        weitere: halbtax,
        sba: sba,
      );

      final arts = [for (final e in _reductions(payload.single)) e['art']];
      expect(arts.length, 3);
      expect(arts.first, 'BAHNCARD50'); // the card stays first
      expect(arts, contains('CH-HALBTAXABO_OHNE_RAILPLUS'));
      expect(arts, contains('SBA_BEEINTRAECHTIGUNGEN_MIT_ROLLSTUHL'));
      // Everything foreign is classless — the class belongs to the BahnCard.
      final erm = _reductions(payload.single);
      expect(erm[1]['klasse'], 'KLASSENLOS');
      expect(erm[2]['klasse'], 'KLASSENLOS');
    });

    test('without a BahnCard, weitere is still not mistaken for one', () {
      final erm = _reductions(
          DbApiService.createTravellerPayload(weitere: Reduction.atVorteil)
              .single);
      expect(erm.length, 2);
      expect(erm.first['art'], 'KEINE_ERMAESSIGUNG');
      expect(erm.last['art'], 'A-VORTEILSCARD');
    });
  });

  group('setBahnCard carries the card into the party', () {
    /// Every setter persists asynchronously; let that land before the container
    /// is torn down, or `_save` writes into a disposed Ref.
    Future<void> settle() => Future<void>.delayed(Duration.zero);

    /// A container whose settings have finished loading from disk.
    ///
    /// `SettingsNotifier.build()` kicks off an async `_load()` that REPLACES the
    /// whole state when it lands, so anything set in the same turn as startup is
    /// overwritten. The app never hits that (prefs resolve in milliseconds, the
    /// settings screen is taps away), but a test that acts immediately does —
    /// so wait for the load, the way a rider does.
    Future<ProviderContainer> container() async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider);
      await settle();
      return c;
    }

    test('a customised party keeps its Halbtax, SBA and extra travellers', () async {
      final c = await container();
      final notifier = c.read(settingsProvider.notifier);
      const halbtax = Reduction.chHalbtax;
      const sba = SbaOption.beeintrMitRolli;

      notifier.setSearchParty(const SearchParty(
        travelers: [
          Traveler(
            typ: TravelerType.erwachsener,
            weitere: halbtax,
            sba: sba,
          ),
          const Traveler(typ: TravelerType.familienkind, alter: 8),
        ],
      ));
      notifier.setBahnCard(BahnCardType.bc25_2);
      await settle();

      final party = c.read(settingsProvider).searchParty;
      expect(party.travelers.length, 2, reason: 'party must not be re-seeded');
      expect(party.travelers.first.bahnCard.vendoKey,
          BahnCardType.bc25_2.vendoErmaessigung);
      expect(party.travelers.first.weitere, halbtax);
      expect(party.travelers.first.sba, sba);
    });

    test('a 1st-class card implies 1st class', () async {
      final c = await container();
      c.read(settingsProvider.notifier).setBahnCard(BahnCardType.bc50_1);
      await settle();
      expect(c.read(settingsProvider).searchParty.firstClass, isTrue);
    });

    test('a 2nd-class card does NOT demote a rider who chose 1st class — '
        'switching cards says nothing about the class', () async {
      final c = await container();
      final notifier = c.read(settingsProvider.notifier);
      notifier.setSearchParty(const SearchParty(firstClass: true));

      notifier.setBahnCard(BahnCardType.bc25_2);
      await settle();

      expect(c.read(settingsProvider).searchParty.firstClass, isTrue);
    });

    test('setWeitereReduction reaches the travellers without touching the card',
        () async {
      final c = await container();
      final notifier = c.read(settingsProvider.notifier);
      const halbtax = Reduction.chHalbtax;

      notifier.setBahnCard(BahnCardType.bc50_2);
      notifier.setWeitereReduction(halbtax);
      await settle();

      final traveler = c.read(settingsProvider).searchParty.travelers.first;
      expect(traveler.weitere, halbtax);
      expect(traveler.bahnCard.vendoKey, BahnCardType.bc50_2.vendoErmaessigung);
    });
  });
}
