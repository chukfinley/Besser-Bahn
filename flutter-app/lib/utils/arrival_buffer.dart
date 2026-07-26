/// "Ich muss um 09:48 beim Zahnarzt sein."
///
/// DB answers an arrival search with the *tightest* connection that still makes
/// it — 09:39 for a 09:48 appointment. That is the right answer to "wann komme
/// ich spätestens an" and the wrong one to "wann sollte ich losfahren": nine
/// minutes is no margin, and for most riders more waiting is not a cost. So the
/// deadline is kept as its own thing and every connection is judged by the slack
/// it leaves in front of it.
///
/// All of this is pure arithmetic on the connections the arrival search already
/// returned — no extra request, and nothing here decides *what* to fetch.
library;

import '../models/journey.dart';

/// Below this many minutes a connection counts as tight even when the rider set
/// no minimum: DB's own answer to an arrival search regularly lands here.
const int kTightBufferMinutes = 10;

/// Above this it is not "a bit of air" any more but time to do something with,
/// which is exactly what the feature is for.
const int kGenerousBufferMinutes = 45;

/// The minimums the filter offers, in minutes. `null` (= "egal") is the UI's
/// job, not this list's.
const List<int> kBufferChoices = [15, 30, 60];

enum BufferTone {
  /// Arrives *after* the deadline — misses the appointment.
  missed,

  /// Makes it, but with less air than [kTightBufferMinutes] (or than the
  /// minimum the rider asked for).
  tight,

  comfortable,

  /// Enough slack to actually do something with — a coffee, an errand.
  generous,
}

/// Slack between when this connection gets in and when the rider has to be
/// there. Negative when it arrives too late. Null when the connection has no
/// arrival time at all — unjudgeable, never silently treated as "fine".
///
/// Live arrival wins over the scheduled one: a delay eats the buffer, and that
/// is the whole point of showing it.
Duration? journeyBuffer(Journey journey, DateTime deadline) {
  final arrival = journey.arrival ?? journey.plannedArrival;
  if (arrival == null) return null;
  return deadline.difference(arrival);
}

/// How to colour a buffer. [minMinutes] is the rider's own minimum — anything
/// under it is tight *for them*, whatever the default threshold says.
BufferTone bufferTone(Duration buffer, {int? minMinutes}) {
  if (buffer.isNegative) return BufferTone.missed;
  final tight = minMinutes ?? kTightBufferMinutes;
  if (buffer.inMinutes < tight) return BufferTone.tight;
  if (buffer.inMinutes < kGenerousBufferMinutes) return BufferTone.comfortable;
  return BufferTone.generous;
}

/// "9 min", "1 h 09", "−4 min". Hours never render as "69 min": past an hour
/// the number stops being something you weigh against a walk from the platform.
String formatBuffer(Duration buffer) {
  final minutes = buffer.abs().inMinutes;
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  final text = hours > 0
      ? '$hours h ${rest.toString().padLeft(2, '0')}'
      : '$rest min';
  // A real minus sign (U+2212), not a hyphen — this is arithmetic, not a range.
  return buffer.isNegative ? '−$text' : text;
}

/// The badge's text: slack in front of the appointment, or how late it is.
String bufferLabel(Duration buffer) => buffer.isNegative
    ? '${formatBuffer(buffer)} zu spät'
    : '${formatBuffer(buffer)} Puffer';

/// Connections leaving at least [minMinutes] of slack before [deadline].
///
/// A connection with no arrival time is kept, not dropped: we cannot judge it,
/// and hiding it would silently shrink the list on missing data rather than on
/// the rider's filter.
List<Journey> withMinBuffer(
  List<Journey> journeys,
  DateTime deadline,
  int? minMinutes,
) {
  if (minMinutes == null) return journeys;
  return [
    for (final j in journeys)
      if (switch (journeyBuffer(j, deadline)) {
        null => true,
        final b => !b.isNegative && b.inMinutes >= minMinutes,
      })
        j,
  ];
}

/// Most slack first. Connections without an arrival time keep their incoming
/// order at the end — they are unjudged, not "no buffer".
List<Journey> sortedByBuffer(List<Journey> journeys, DateTime deadline) {
  final indexed = [
    for (final (i, j) in journeys.indexed)
      (journey: j, buffer: journeyBuffer(j, deadline), order: i),
  ];
  indexed.sort((a, b) {
    if (a.buffer == null && b.buffer == null) return a.order.compareTo(b.order);
    if (a.buffer == null) return 1;
    if (b.buffer == null) return -1;
    final byBuffer = b.buffer!.compareTo(a.buffer!);
    // Stable: equal buffers hold the order they came in with (departure), so
    // the list doesn't shuffle on every rebuild.
    return byBuffer != 0 ? byBuffer : a.order.compareTo(b.order);
  });
  return [for (final e in indexed) e.journey];
}
