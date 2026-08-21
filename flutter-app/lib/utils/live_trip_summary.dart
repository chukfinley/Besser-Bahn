/// Turning a journey into the shape a Live Update draws: one segment per leg,
/// a point at every change, and a position along the bar.
///
/// The progress bar IS the journey — a rider glancing at the lock screen sees
/// which leg they are on and how far the change still is, not an abstract
/// percentage. Kept out of the service so the arithmetic is testable without an
/// Android channel.
library;

import '../models/journey.dart';

/// Colours the bar uses. ARGB, as Android wants them.
class LiveTripColors {
  LiveTripColors._();

  /// Legs already travelled.
  static const done = 0xFF1B8754;

  /// The leg being travelled right now.
  static const current = 0xFF0A6ED1;

  /// Still ahead.
  static const pending = 0xFF9AA0A6;

  /// A leg running late — the one thing worth colouring loudly.
  static const delayed = 0xFFC5221F;

  /// The markers at the changes.
  static const transfer = 0xFFF29D38;
}

/// One leg as the bar shows it.
class LiveTripSegment {
  final int minutes;
  final int color;

  const LiveTripSegment(this.minutes, this.color);

  @override
  bool operator ==(Object other) =>
      other is LiveTripSegment &&
      other.minutes == minutes &&
      other.color == color;

  @override
  int get hashCode => Object.hash(minutes, color);

  @override
  String toString() =>
      'LiveTripSegment($minutes, 0x${color.toRadixString(16)})';
}

/// Everything the Live Update needs about a trip at one moment.
class LiveTripSummary {
  final List<LiveTripSegment> segments;

  /// Positions of the changes along the bar, in the same minutes scale.
  final List<int> transferPoints;

  /// How far along the bar we are.
  final int progressMinutes;

  /// Total length of the bar — the sum of the segments.
  final int totalMinutes;

  /// The train being ridden, or the next one before departure.
  final JourneyLeg? currentLeg;

  /// Delay of [currentLeg] in minutes, 0 when on time.
  final int delayMinutes;

  /// [currentLeg] is cancelled — worse than any delay, and the one state that
  /// earns the loudest treatment the platform has.
  final bool cancelled;

  /// Where the trip ends, live where known.
  final DateTime? arrival;

  const LiveTripSummary({
    required this.segments,
    required this.transferPoints,
    required this.progressMinutes,
    required this.totalMinutes,
    required this.currentLeg,
    required this.delayMinutes,
    required this.arrival,
    this.cancelled = false,
  });

  bool get isEmpty => segments.isEmpty;

  /// Whether the trip's final arrival is behind us.
  bool finishedAt(DateTime now) => arrival != null && now.isAfter(arrival!);
}

/// Read [journey] as of [now].
///
/// Walks are folded into the leg that follows them rather than given a segment
/// of their own: a five-minute walk would be a sliver nobody can see, and the
/// time still has to be somewhere or the bar stops matching the clock.
LiveTripSummary summariseTrip(Journey journey, DateTime now) {
  final legs = journey.legs;
  if (legs.isEmpty) {
    return const LiveTripSummary(
      segments: [],
      transferPoints: [],
      progressMinutes: 0,
      totalMinutes: 0,
      currentLeg: null,
      delayMinutes: 0,
      arrival: null,
    );
  }

  final start = legs.first.departure ?? legs.first.plannedDeparture;
  final end = legs.last.arrival ?? legs.last.plannedArrival;
  if (start == null || end == null) {
    final leg = legs.firstWhere((l) => !l.isWalking, orElse: () => legs.first);
    return LiveTripSummary(
      segments: const [],
      transferPoints: const [],
      progressMinutes: 0,
      totalMinutes: 0,
      currentLeg: leg,
      delayMinutes: 0,
      cancelled: leg.cancelled,
      arrival: end,
    );
  }

  final segments = <LiveTripSegment>[];
  final points = <int>[];
  JourneyLeg? current;
  var delay = 0;
  var offset = 0; // minutes from the journey's start, at each segment's edge
  var carriedWalk = 0; // walk minutes waiting to be folded into the next leg

  for (final leg in legs) {
    final from = leg.departure ?? leg.plannedDeparture;
    final to = leg.arrival ?? leg.plannedArrival;
    final minutes = (from != null && to != null)
        ? to.difference(from).inMinutes
        : 0;

    if (leg.isWalking) {
      carriedWalk += minutes.clamp(0, 24 * 60);
      continue;
    }

    // A change happens where this leg begins — except at the very start.
    if (segments.isNotEmpty) points.add(offset);

    final length = (minutes + carriedWalk).clamp(1, 24 * 60);
    carriedWalk = 0;

    final legDelay = leg.departureDelayMinutes > leg.arrivalDelayMinutes
        ? leg.departureDelayMinutes
        : leg.arrivalDelayMinutes;
    final isDone = to != null && now.isAfter(to);
    final isCurrent =
        !isDone &&
        from != null &&
        (now.isAfter(from) || now.isAtSameMomentAs(from));

    if (isCurrent) {
      current = leg;
      delay = legDelay;
    }

    final aheadColor = legDelay > 0
        ? LiveTripColors.delayed
        : LiveTripColors.current;

    if (isDone) {
      segments.add(LiveTripSegment(length, LiveTripColors.done));
    } else if (isCurrent) {
      // Split the leg being ridden at the live position: the part behind us is
      // filled (done-green), the part ahead keeps the leg's colour. That is
      // what makes the bar visibly fill and the train sit at the fill edge,
      // instead of a whole leg glowing one colour as if it were over.
      final travelled = now.difference(from).inMinutes.clamp(0, length);
      final ahead = length - travelled;
      if (travelled > 0) {
        segments.add(LiveTripSegment(travelled, LiveTripColors.done));
      }
      if (ahead > 0 || travelled == 0) {
        segments.add(LiveTripSegment(ahead.clamp(1, length), aheadColor));
      }
    } else {
      segments.add(LiveTripSegment(length, LiveTripColors.pending));
    }
    offset += length;
  }

  // Before departure the "current" leg is the one about to be boarded — that is
  // what the rider is standing on a platform waiting for.
  current ??= legs.firstWhere((l) => !l.isWalking, orElse: () => legs.first);
  if (delay == 0) {
    delay = current.departureDelayMinutes;
  }

  final total = offset;
  final elapsed = now.difference(start).inMinutes;
  return LiveTripSummary(
    segments: segments,
    transferPoints: points,
    progressMinutes: elapsed.clamp(0, total),
    totalMinutes: total,
    currentLeg: current,
    delayMinutes: delay,
    cancelled: current.cancelled,
    arrival: end,
  );
}
