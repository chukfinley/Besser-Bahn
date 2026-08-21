import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/providers/service_providers.dart';
import 'package:besser_bahn/providers/station_search_provider.dart';
import 'package:besser_bahn/services/hafas_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The suggestion list must answer the text that is in the field *now*.
///
/// It used to keep whatever came back last: a slow request for an earlier term
/// could land after a fast one for the current term and overwrite it, and while
/// a new query was still debouncing the old list stayed on screen. Either way
/// the rider read a list that said something entirely different from what they
/// had typed.
class _ScriptedHafas extends HafasService {
  /// query → (delay, result names)
  final Map<String, (Duration, List<String>)> script;
  final queries = <String>[];

  _ScriptedHafas(this.script);

  @override
  Future<List<Station>> searchStations(
    String query, {
    bool stopsOnly = false,
  }) async {
    queries.add(query);
    final entry = script[query] ?? (Duration.zero, const <String>[]);
    await Future<void>.delayed(entry.$1);
    return [
      for (final n in entry.$2)
        Station(id: n.hashCode.toString(), name: n, locationId: 'A=1@O=$n@'),
    ];
  }
}

/// Waits until [test] holds, so the assertions don't depend on exact timing.
Future<void> _until(
  bool Function() test, {
  Duration limit = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(limit);
  while (!test()) {
    if (DateTime.now().isAfter(deadline)) fail('condition never held');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  ProviderContainer containerWith(_ScriptedHafas hafas) {
    final c = ProviderContainer(
      overrides: [hafasServiceProvider.overrideWithValue(hafas)],
    );
    addTearDown(c.dispose);
    // Keep the auto-dispose provider alive for the length of the test.
    addTearDown(c.listen(stationSearchProvider, (_, _) {}).close);
    return c;
  }

  test('a slow answer to an old query never overwrites the new one', () async {
    final hafas = _ScriptedHafas({
      'Kiel': (const Duration(milliseconds: 600), ['Kiel Hbf']),
      'Preetz': (const Duration(milliseconds: 10), ['Preetz']),
    });
    final c = containerWith(hafas);
    final notifier = c.read(stationSearchProvider.notifier);

    notifier.search('Kiel');
    // Let the debounce fire so "Kiel" is genuinely in flight.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(hafas.queries, ['Kiel']);

    notifier.search('Preetz');
    await _until(
      () => c.read(stationSearchProvider).value?.stations.isNotEmpty ?? false,
    );
    expect(c.read(stationSearchProvider).value!.query, 'Preetz');

    // Now the slow "Kiel" answer lands — and must be dropped.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final result = c.read(stationSearchProvider).value!;
    expect(result.query, 'Preetz');
    expect(result.stations.single.name, 'Preetz');
  });

  test(
    'results for the old query are dropped the moment a new one is typed',
    () async {
      final hafas = _ScriptedHafas({
        'Kiel': (Duration.zero, ['Kiel Hbf']),
        'Preetz': (const Duration(milliseconds: 500), ['Preetz']),
      });
      final c = containerWith(hafas);
      final notifier = c.read(stationSearchProvider.notifier);

      notifier.search('Kiel');
      await _until(
        () => c.read(stationSearchProvider).value?.stations.isNotEmpty ?? false,
      );

      notifier.search('Preetz');
      // The field shows a spinner, not Kiel Hbf. Riverpod keeps the old value
      // attached to the loading state, so being loading is only half of it: the
      // leftover data must also be recognisable as an answer to the *old* query.
      final pending = c.read(stationSearchProvider);
      expect(pending.isLoading, isTrue);
      expect(pending.value!.matches('Preetz'), isFalse);
      expect(pending.value!.query, 'Kiel');
    },
  );

  test('a result knows which query it answers', () async {
    final hafas = _ScriptedHafas({
      'Preetz': (Duration.zero, ['Preetz']),
    });
    final c = containerWith(hafas);
    c.read(stationSearchProvider.notifier).search('Preetz');
    await _until(
      () => c.read(stationSearchProvider).value?.stations.isNotEmpty ?? false,
    );

    final result = c.read(stationSearchProvider).value!;
    expect(result.matches('Preetz'), isTrue);
    expect(result.matches('  Preetz  '), isTrue, reason: 'trimmed like input');
    expect(result.matches('Preet'), isFalse);
  });

  test(
    'a query too short to search reports itself, not the previous list',
    () async {
      final hafas = _ScriptedHafas({
        'Kiel': (Duration.zero, ['Kiel Hbf']),
      });
      final c = containerWith(hafas);
      final notifier = c.read(stationSearchProvider.notifier);

      notifier.search('Kiel');
      await _until(
        () => c.read(stationSearchProvider).value?.stations.isNotEmpty ?? false,
      );

      notifier.search('K');
      final result = c.read(stationSearchProvider).value!;
      expect(result.query, 'K');
      expect(result.stations, isEmpty);
    },
  );

  test('stopsOnly is passed through to the backend', () async {
    final hafas = _ScriptedHafas({
      'Preetz': (Duration.zero, ['Preetz']),
    });
    final c = containerWith(hafas);
    c.read(stationSearchProvider.notifier)
      ..stopsOnly = true
      ..search('Preetz');
    await _until(() => hafas.queries.isNotEmpty);
    expect(hafas.queries, ['Preetz']);
  });
}
