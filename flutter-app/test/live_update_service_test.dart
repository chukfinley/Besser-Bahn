import 'package:besser_bahn/models/departure.dart' show TransitLine;
import 'package:besser_bahn/models/journey.dart';
import 'package:besser_bahn/models/station.dart';
import 'package:besser_bahn/services/live_update_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// What crosses the platform channel — the half of the Live Update that the
/// Kotlin tests cannot see. The native side only renders what arrives here, so
/// the delay, the semantics and the three metrics are pinned on this side.

const _selent =
    Station(id: '8005292', name: 'Selent', locationId: 'A=1@L=8005292@');
const _kiel =
    Station(id: '8000199', name: 'Kiel Hbf', locationId: 'A=1@L=8000199@');

DateTime _at(int h, int m) => DateTime(2026, 7, 27, h, m);

Journey _journey({int delay = 0, bool cancelled = false}) => Journey(legs: [
      JourneyLeg(
        origin: _selent,
        destination: _kiel,
        departure: _at(9, 1),
        plannedDeparture: _at(9, 1),
        arrival: _at(9, 34),
        plannedArrival: _at(9, 34),
        departureDelay: delay * 60,
        arrivalDelay: delay * 60,
        cancelled: cancelled,
        line: TransitLine(
            name: 'RE 7', fahrtNr: '1', productName: 'RE', product: 'regional'),
      ),
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dev.chuk.betterbahn/live_update');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    LiveUpdateService.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'isSupported' => true,
        'post' => {'promoted': true, 'style': 'metric'},
        _ => null,
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Map<Object?, Object?> lastPost() =>
      calls.lastWhere((c) => c.method == 'post').arguments
          as Map<Object?, Object?>;

  test('a delayed train is a caution, and the chip is the delay', () async {
    expect(await LiveUpdateService.show(_journey(delay: 12), now: _at(9, 10)),
        isTrue);
    final args = lastPost();
    // The title names where this train takes the rider, plus the delay.
    expect(args['title'], 'RE 7 → Kiel Hbf · +12 min');
    expect(args['chipText'], '+12');
    expect(args['titleSemantic'], 3, reason: 'SEMANTIC_STYLE_CAUTION');
  });

  test('a cancelled train is a danger, not a delay', () async {
    await LiveUpdateService.show(_journey(cancelled: true), now: _at(9, 10));
    final args = lastPost();
    expect(args['title'], 'RE 7 → Kiel Hbf · fällt aus');
    expect(args['titleSemantic'], 4, reason: 'SEMANTIC_STYLE_DANGER');
  });

  test('on time: title is just the destination, chip counts down to the stop',
      () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    final args = lastPost();
    expect(args['title'], 'RE 7 → Kiel Hbf');
    // No intermediate stops in this journey → the chip counts to the rider's
    // own stop (Kiel 09:34, 24 min out).
    expect(args['chipText'], "24'");
    expect(args['titleSemantic'], 2, reason: 'SEMANTIC_STYLE_SAFE');
  });

  test('a direct trip: delay + arrival, no intermediate-stop metric', () async {
    await LiveUpdateService.show(_journey(delay: 12), now: _at(9, 10));
    final metrics = (lastPost()['metrics']! as List).cast<Map<Object?, Object?>>();
    // Just the rider's milestones: how late, and when they arrive. No
    // "next stop" tile — the passing stations don't interest the rider.
    expect(metrics.length, 2);
    expect(metrics[0]['label'], 'Verspätung');
    expect(metrics[0]['kind'], 'count');
    expect(metrics[0]['number'], 12);
    expect(metrics[0]['semantic'], 3);
    expect(metrics[1]['kind'], 'clock');
    expect(metrics[1]['label'], 'Ankunft');
    expect(metrics[1]['number'], 9 * 60 + 34); // 09:34
    expect(lastPost()['criticalMetric'], 0);
  });

  test('the current leg is split at the live position so the bar fills', () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    final args = lastPost();
    // 9 min travelled (done) + 24 min ahead (current) = the fill split.
    expect((args['segments']! as List).length, 2);
    expect(args['progress'], 9);
    // The countdown runs to the rider's own stop (here the single leg's end).
    expect(args['etaEpochMillis'], _at(9, 34).millisecondsSinceEpoch);
  });

  test('the countdown and text lead with the rider\'s OWN stop, not the trip end',
      () async {
    // ERX 83 Kiel 10:43 → Lüneburg 13:17 (the rider's transfer), passing
    // Lübeck ~12:14, then a second train on to Hamburg 14:00.
    final luebeck =
        const Station(id: '8000237', name: 'Lübeck Hbf', locationId: 'A=1@');
    final lueneburg =
        const Station(id: '8000237b', name: 'Lüneburg', locationId: 'A=1@');
    final hamburg =
        const Station(id: '8002549', name: 'Hamburg Hbf', locationId: 'A=1@');
    final journey = Journey(legs: [
      JourneyLeg(
        origin: _kiel,
        destination: lueneburg,
        departure: _at(10, 43),
        plannedDeparture: _at(10, 43),
        arrival: _at(13, 17),
        plannedArrival: _at(13, 17),
        arrivalPlatform: '5',
        line: TransitLine(
            name: 'ERX 83', fahrtNr: '21017', productName: 'RE', product: 'regional'),
        stopovers: [
          LegStopover(stop: luebeck, arrival: _at(12, 14), departure: _at(12, 16)),
        ],
      ),
      JourneyLeg(
        origin: lueneburg,
        destination: hamburg,
        departure: _at(13, 35),
        plannedDeparture: _at(13, 35),
        arrival: _at(14, 0),
        plannedArrival: _at(14, 0),
        line: TransitLine(
            name: 'RE 8', fahrtNr: '1', productName: 'RE', product: 'regional'),
      ),
    ]);

    await LiveUpdateService.show(journey, now: _at(11, 53));
    final args = lastPost();

    // The big countdown runs to Lüneburg (13:17), the rider's exit from THIS
    // train — not Hamburg (14:00), the far end of the whole journey.
    expect(args['etaEpochMillis'], _at(13, 17).millisecondsSinceEpoch);

    // The text (under the bar) is the live pulse: the next stop with a
    // countdown — "how far is the next stop", which the rider watches.
    final text = args['text'] as String;
    expect(text, contains('Lübeck'));
    expect(text, contains('in 21 Min'));

    // The subtext carries the rider's own milestones: the transfer (with Gleis)
    // and where the whole journey ends.
    final sub = args['subText'] as String;
    expect(sub, contains('Umstieg Lüneburg 13:17'));
    expect(sub, contains('Gl 5'));
    expect(sub, contains('Ziel Hamburg Hbf 14:00'));

    // Metrics, in order: delay, next stop, the rider's exit.
    final metrics = (args['metrics']! as List).cast<Map<Object?, Object?>>();
    expect(metrics[0]['label'], 'Verspätung');
    expect(metrics[1]['label'], 'Nächster Halt');
    expect(metrics[1]['text'], 'Lübeck Hbf');
    expect(metrics[2]['label'], 'Umstieg');
    expect(metrics[2]['number'], 13 * 60 + 17);

    // Samsung Now Bar gets its own short lines (#76): the exit as primary, the
    // next stop as secondary — no dense multi-fact string to overload the pill.
    expect(args['nowbarPrimary'], '→ Lüneburg 13:17');
    expect(args['nowbarSecondary'], 'Lübeck Hbf in 21 Min');
  });

  test('a finished trip is taken down instead of refreshed', () async {
    expect(await LiveUpdateService.show(_journey(), now: _at(10, 0)), isFalse);
    expect(calls.map((c) => c.method), contains('cancel'));
    expect(calls.map((c) => c.method), isNot(contains('post')));
  });

  test('chip can show stops-to-exit instead of minutes (#76)', () async {
    LiveUpdateService.chipShowsStops = true;
    addTearDown(() => LiveUpdateService.chipShowsStops = false);
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    // No stopover list on this leg → falls back to "1 to go" while en route.
    expect(lastPost()['chipText'], '1 Hlt');
  });

  test('the icon carries the state: train, or train-alert when late (#76)',
      () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    expect(lastPost()['smallIcon'], 'ic_stat_train');
    await LiveUpdateService.show(_journey(delay: 12), now: _at(9, 10));
    expect(lastPost()['smallIcon'], 'ic_stat_train_alert');
  });

  test('a dismissed Live Update does not come back', () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    LiveUpdateService.markDismissed();
    calls.clear();
    expect(await LiveUpdateService.show(_journey(), now: _at(9, 11)), isFalse);
    expect(calls, isEmpty);
    // A new trip may show one again.
    LiveUpdateService.reset();
    expect(await LiveUpdateService.show(_journey(), now: _at(9, 12)), isTrue);
  });
}
