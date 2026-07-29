import 'package:live_update/live_update.dart';

import '../core/app_log.dart';
import '../core/extensions.dart';
import '../models/journey.dart';
import '../utils/live_trip_summary.dart';

/// The running trip as an Android 16 Live Update.
///
/// One notification, kept current while the trip runs: the bar is the journey
/// (a segment per leg, a marker at every change), the chip in the status bar is
/// the delay, and the system counts down to arrival by itself. On Android 17 the
/// same call also carries three metrics (delay / next stop / arrival), which the
/// platform renders in its own template — even on the always-on display.
///
/// Everything is best-effort. Where the device will not promote it — anything
/// below Android 16 QPR1, promotion switched off, an OEM that declines — [show]
/// returns false and the caller keeps to the ordinary notifications it already
/// posts. Nothing here ever throws into app code.
class LiveUpdateService {
  LiveUpdateService._();

  /// Cached so every poll does not cross the platform channel to ask again.
  static bool? _supported;

  /// The rider swiped it away — a dismissed Live Update must not come back, or
  /// the app is arguing with them once a minute.
  static bool _dismissed = false;

  static bool _listening = false;

  /// Which template Android 17 gets: [LiveUpdateStyle.auto] means the three
  /// metrics (and the always-on display, which no other template reaches),
  /// [LiveUpdateStyle.progress] keeps the journey bar there as well. Below
  /// Android 17 there is only the bar and this changes nothing.
  static LiveUpdateStyle preferredStyle = LiveUpdateStyle.auto;

  static Future<bool> isSupported() async {
    if (_supported != null) return _supported!;
    final s = await LiveUpdate.isSupported();
    _supported = s;
    AppLog.log(
        'live update: isSupported=$s '
        '(Android 16 QPR1+/17 nötig UND „Livemeldungen" für die App an)',
        tag: 'notify');
    return s;
  }

  /// Force the next [isSupported] to re-ask the platform — the rider may have
  /// just flipped the "Livemeldungen" toggle, and the cached answer is stale.
  static void invalidateSupport() => _supported = null;

  /// Called when a new trip starts being tracked: a fresh trip may be shown
  /// again even if the previous one was dismissed.
  static void reset() => _dismissed = false;

  /// Post/refresh the Live Update for [journey] as of [now].
  ///
  /// Returns whether the system is really promoting it — false means "show the
  /// ordinary notification instead", not "something broke".
  static Future<bool> show(Journey journey, {DateTime? now}) async {
    if (_dismissed) {
      AppLog.log('live update: übersprungen — vom Nutzer weggewischt (reset() '
          'setzt das bei neuer Reise zurück)', tag: 'notify');
      return false;
    }
    if (!await isSupported()) {
      AppLog.log('live update: NICHT gepostet — Gerät promotet es nicht '
          '(isSupported=false)', tag: 'notify');
      return false;
    }
    _listenForDismissal();

    final at = now ?? DateTime.now();
    final trip = summariseTrip(journey, at);
    if (trip.isEmpty) {
      AppLog.log('live update: NICHT gepostet — Reise ohne verwertbare '
          'Etappen/Zeiten (summariseTrip leer)', tag: 'notify');
      return false;
    }
    // Over and done: the Live Update's whole promise is that it is current.
    if (trip.finishedAt(at)) {
      AppLog.log('live update: NICHT gepostet — Reise laut Zeiten schon '
          'beendet, blende aus', tag: 'notify');
      await hide();
      return false;
    }

    final line = trip.currentLeg?.line?.name ?? 'Reise';
    final delay = trip.delayMinutes;
    final title = trip.cancelled
        ? '$line · fällt aus'
        : delay > 0
            ? '$line · +$delay min'
            : '$line · pünktlich';
    final semantic = trip.cancelled
        ? LiveUpdateSemantic.danger
        : delay > 0
            ? LiveUpdateSemantic.caution
            : LiveUpdateSemantic.safe;

    try {
      final result = await LiveUpdate.post(
        title: title,
        text: _nextStopLine(trip, at),
        // Short and critical, in that order: the chip has room for about seven
        // characters, and the delay is the one number worth that space.
        chipText: trip.cancelled ? 'X' : (delay > 0 ? '+$delay' : null),
        segments: [
          for (final s in trip.segments)
            LiveUpdateSegment(minutes: s.minutes, color: s.color),
        ],
        transferPoints: trip.transferPoints,
        progressMinutes: trip.progressMinutes,
        eta: trip.arrival,
        transferColor: LiveTripColors.transfer,
        titleSemantic: semantic,
        metrics: _metrics(trip, semantic),
        // The delay is what the rider is actually anxious about; when the system
        // has room for only one figure, that is the one.
        criticalMetric: 0,
        style: preferredStyle,
      );
      // post.promoted is the flag the system set at post time; isPromoted asks
      // the live notification back — they should agree, and a mismatch is worth
      // seeing in the log.
      final live = await LiveUpdate.isPromoted();
      AppLog.log(
          'live update [${result.style}]: "$title" · ${trip.segments.length} '
          'Etappen, ${trip.transferPoints.length} Umstiege · '
          'post.promoted=${result.promoted}, system.promoted=$live',
          tag: 'notify');
      return result.promoted;
    } catch (e) {
      AppLog.log('live update: POST fehlgeschlagen — $e', tag: 'notify');
      return false;
    }
  }

  /// The three figures the Android 17 template shows. Ignored below it, so the
  /// order matters only there: delay first, because it is the reason to look.
  static List<LiveUpdateMetric> _metrics(LiveTripSummary trip, int semantic) {
    final metrics = <LiveUpdateMetric>[
      LiveUpdateMetric.count(
        label: 'Verspätung',
        value: trip.delayMinutes,
        unit: 'min',
        semantic: semantic,
      ),
    ];
    final next = trip.currentLeg?.destination.name;
    if (next != null && next.isNotEmpty) {
      metrics.add(LiveUpdateMetric.text(label: 'Nächster', value: next));
    }
    final arrival = trip.arrival;
    if (arrival != null) {
      metrics.add(LiveUpdateMetric.clock(label: 'Ankunft', value: arrival));
    }
    return metrics;
  }

  /// "Nächster Halt: Kiel Hbf · an 09:34" — what the expanded card says under
  /// the bar.
  static String _nextStopLine(LiveTripSummary trip, DateTime now) {
    final leg = trip.currentLeg;
    if (leg == null) return '';
    final departure = leg.departure ?? leg.plannedDeparture;
    // Still on the platform: the departure is the thing that matters.
    if (departure != null && now.isBefore(departure)) {
      return 'Ab ${departure.hhmm} · ${leg.origin.name}';
    }
    final arrival = leg.arrival ?? leg.plannedArrival;
    final where = leg.destination.name;
    return arrival != null
        ? 'Nächster Halt: $where · an ${arrival.hhmm}'
        : 'Nächster Halt: $where';
  }

  static Future<void> hide() async {
    await LiveUpdate.cancel();
  }

  /// Stop showing it for this trip because the rider swiped it away.
  static void markDismissed() => _dismissed = true;

  /// The swipe arrives as a broadcast on the native side; without picking it up
  /// here the next poll posts the Live Update straight back.
  static void _listenForDismissal() {
    if (_listening) return;
    _listening = true;
    LiveUpdate.onDismissed = markDismissed;
  }
}
