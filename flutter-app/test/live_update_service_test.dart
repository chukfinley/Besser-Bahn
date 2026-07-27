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
    expect(args['title'], 'RE 7 · +12 min');
    expect(args['chipText'], '+12');
    expect(args['titleSemantic'], 3, reason: 'SEMANTIC_STYLE_CAUTION');
  });

  test('a cancelled train is a danger, not a delay', () async {
    await LiveUpdateService.show(_journey(cancelled: true), now: _at(9, 10));
    final args = lastPost();
    expect(args['title'], 'RE 7 · fällt aus');
    expect(args['titleSemantic'], 4, reason: 'SEMANTIC_STYLE_DANGER');
  });

  test('on time is a safe, with no chip claiming the status bar', () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    final args = lastPost();
    expect(args['title'], 'RE 7 · pünktlich');
    expect(args['chipText'], isNull);
    expect(args['titleSemantic'], 2, reason: 'SEMANTIC_STYLE_SAFE');
  });

  test('three metrics, delay first because it is the reason to look', () async {
    await LiveUpdateService.show(_journey(delay: 12), now: _at(9, 10));
    final metrics = (lastPost()['metrics']! as List).cast<Map<Object?, Object?>>();
    expect(metrics.length, 3);
    expect(metrics[0]['label'], 'Verspätung');
    expect(metrics[0]['kind'], 'count');
    expect(metrics[0]['number'], 12);
    expect(metrics[0]['unit'], 'min');
    expect(metrics[0]['semantic'], 3);
    expect(metrics[1]['kind'], 'text');
    expect(metrics[1]['text'], 'Kiel Hbf');
    // 09:34 as the minute of the day — a LocalTime on the far side.
    expect(metrics[2]['kind'], 'clock');
    expect(metrics[2]['number'], 9 * 60 + 34);
    expect(lastPost()['criticalMetric'], 0);
  });

  test('the journey is still sent as segments for the Android 16 bar', () async {
    await LiveUpdateService.show(_journey(), now: _at(9, 10));
    final args = lastPost();
    expect((args['segments']! as List).length, 1);
    expect(args['progress'], 9);
    expect(args['etaEpochMillis'], _at(9, 34).millisecondsSinceEpoch);
  });

  test('a finished trip is taken down instead of refreshed', () async {
    expect(await LiveUpdateService.show(_journey(), now: _at(10, 0)), isFalse);
    expect(calls.map((c) => c.method), contains('cancel'));
    expect(calls.map((c) => c.method), isNot(contains('post')));
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
