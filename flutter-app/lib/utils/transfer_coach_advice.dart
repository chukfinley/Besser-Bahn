/// Where in the arriving train to stand so the change at a transfer stop is a
/// step across the platform instead of a sprint down it (#27).
///
/// WHAT THIS RESTS ON
/// ------------------
/// German platform sections (Abschnitt A–G) are letters painted on the platform
/// itself, not on the track: both tracks of one island platform share the SAME
/// markers at the SAME place. The Wagenreihung proves it — Berlin Hbf, one
/// island, the two tracks come back with the same letter→metre table:
///
///   Gleis 3: G 0–97.5  F 97.5–149.8  E 149.8–194.6  …  A 358.8–430.2
///   Gleis 4: G 0–97.5  F 97.5–149.8  E 149.8–195.7  …  A 358.8–430.2
///
/// So when the arriving and the departing train stand at one platform, their
/// `platformPosition` metres live in a shared frame and can be compared
/// directly: the part of the arriving train that overlaps the departing train's
/// span is the part you want to be in.
///
/// Note the letter order is per-platform, not universal — Hamburg Dammtor Gl. 4
/// runs A(0)→G(420), Dortmund Gl. 16 runs G(0)→A(415). That's why everything
/// here works in METRES and only uses the letters as labels.
///
/// WHEN IT DELIBERATELY SAYS NOTHING (returns null)
/// -----------------------------------------------
/// A wrong section costs exactly the minutes it means to save, so every one of
/// these is a silence, not a guess:
///  * either Wagenreihung is missing — the vehicle-sequence endpoint does not
///    serve every train at every stop (a regional train's terminus 404s).
///  * the two trains are NOT on one platform. DB's own
///    `weiterfahrtAmGleichenBahnsteig` is the only trustworthy source for that
///    (Gleis 4→5 can be one island while 8→9 is two). Across two platforms the
///    sector letters are unrelated frames, and working out which END of platform
///    16 is nearest platform 11 needs station geometry we don't have here.
///  * the two sector tables disagree on where a shared letter sits (> 15 m).
///    Then the frames are not the one platform we were told they are, and the
///    comparison would be nonsense.
///  * the arriving train stands entirely alongside the departing train. Every
///    door already faces it, so there is nothing to optimise and the hint would
///    be noise.
///  * the answer would name every section the arriving train occupies. Two
///    400 m ICEs at one platform produce exactly that ("be in A–G"), which is
///    the train restated as a tip. Real case: Erfurt Hbf ICE 698 → ICE 604.
///
/// This function is pure: hand it the two sequences AT THE TRANSFER STOP.
library;

import '../models/coach_sequence.dart';

/// Why these sections are the ones being pointed at.
enum TransferAdviceReason {
  /// Part of the arriving train stands directly alongside the departing train —
  /// get off here and the next train is right there.
  alongside('Dein Anschluss hält direkt gegenüber'),

  /// The trains don't overlap at all; this is the end of the arriving train
  /// closest to the departing one — the shortest walk we can honestly promise.
  nearest('Von hier ist der Weg am kürzesten');

  const TransferAdviceReason(this.label);

  /// Short German reason, ready for the UI.
  final String label;
}

/// The recommendation: be in [sectors] of the arriving train.
class TransferCoachAdvice {
  /// Platform sections of the ARRIVING train to be in, e.g. ["C"] or
  /// ["C", "D"]. Never empty.
  final List<String> sectors;

  /// Wagon numbers standing in [sectors]. Empty when the train reports no
  /// numbers (regional stock often doesn't) — the section alone is still valid.
  final List<int> coaches;

  /// Sections the DEPARTING train occupies, for the reason line.
  final List<String> departingSectors;

  final TransferAdviceReason reason;

  const TransferCoachAdvice({
    required this.sectors,
    required this.coaches,
    required this.departingSectors,
    required this.reason,
  });

  /// "C" or "C–E".
  String get sectorLabel => _range(sectors);

  /// "A–D" — where the next train stands.
  String get departingSectorLabel => _range(departingSectors);

  static String _range(List<String> s) =>
      s.length == 1 ? s.first : '${s.first}–${s.last}';

  /// "Wagen 24" / "Wagen 24–26" / null when the train reports no numbers.
  String? get coachLabel {
    if (coaches.isEmpty) return null;
    return coaches.length == 1
        ? 'Wagen ${coaches.first}'
        : 'Wagen ${coaches.first}–${coaches.last}';
  }
}

/// Two sector tables must agree this closely on a shared letter before we treat
/// them as one platform. Real island platforms differ by ~2 m (Berlin Gl. 3/4);
/// two genuinely different platforms are far off (Dortmund Gl. 16 vs 11 put
/// sector G's end 51 m apart).
const double _frameToleranceM = 15.0;

/// Slack for "the arriving train is entirely alongside the departing one".
/// Absorbs the couple of metres the two tracks' tables differ by.
const double _containmentToleranceM = 10.0;

/// Leading track number of a Gleis label — "7A-D" and "7" are both Gleis 7.
String _normGleis(String s) {
  final m = RegExp(r'\d+').firstMatch(s);
  return m?.group(0) ?? s.trim().toUpperCase();
}

/// Coaches that actually carry a metre position on the platform.
List<Coach> _positioned(CoachSequence s) => s.allCoaches
    .where((c) => c.platformPosition != null && c.platformPosition!.length > 0)
    .toList();

/// The recommendation for changing from [arriving] into [departing], or null
/// when the data doesn't support one. See the library doc for every case.
///
/// Both sequences MUST be the ones fetched AT THE TRANSFER STOP — the arriving
/// train's composition at its origin says nothing about which sector it stops
/// in here.
///
/// [samePlatformPerDb] is DB's `weiterfahrtAmGleichenBahnsteig` for this
/// transfer. It is the gate: sector letters only compare within one platform.
TransferCoachAdvice? transferCoachAdvice({
  required CoachSequence? arriving,
  required CoachSequence? departing,
  required bool samePlatformPerDb,
}) {
  if (arriving == null || departing == null) return null;

  // Gate 1 — one platform, on evidence only. Same track is proof by itself;
  // otherwise we take DB's word and nothing else. Two islands would need
  // station geometry (which end of Gl. 16 faces Gl. 11) that isn't in here.
  final arrTrack = _normGleis(arriving.departurePlatform);
  final depTrack = _normGleis(departing.departurePlatform);
  final sameTrack = arrTrack.isNotEmpty && arrTrack == depTrack;
  if (!sameTrack && !samePlatformPerDb) return null;

  final arrTable = <String, PlatformSector>{
    for (final s in arriving.platform.sectors)
      if (s.name.trim().isNotEmpty && s.end > s.start)
        s.name.trim().toUpperCase(): s,
  };
  final depTable = <String, PlatformSector>{
    for (final s in departing.platform.sectors)
      if (s.name.trim().isNotEmpty && s.end > s.start)
        s.name.trim().toUpperCase(): s,
  };
  if (arrTable.isEmpty || depTable.isEmpty) return null;

  // Gate 2 — the two tables must really describe one platform. This catches a
  // wrong same-platform flag, and it catches two different platforms that DB
  // happens to link: at a big station every platform is ~430 m, so identical
  // *lengths* prove nothing — identical letter POSITIONS do.
  var shared = 0;
  for (final e in arrTable.entries) {
    final other = depTable[e.key];
    if (other == null) continue;
    shared++;
    if ((e.value.start - other.start).abs() > _frameToleranceM ||
        (e.value.end - other.end).abs() > _frameToleranceM) {
      return null;
    }
  }
  if (shared < 2) return null; // too little overlap to call it one platform

  final arrCoaches = _positioned(arriving);
  final depCoaches = _positioned(departing);
  if (arrCoaches.isEmpty || depCoaches.isEmpty) return null;

  double minStart(List<Coach> cs) =>
      cs.map((c) => c.platformPosition!.start).reduce((a, b) => a < b ? a : b);
  double maxEnd(List<Coach> cs) =>
      cs.map((c) => c.platformPosition!.end).reduce((a, b) => a > b ? a : b);

  final depStart = minStart(depCoaches);
  final depEnd = maxEnd(depCoaches);
  final arrStart = minStart(arrCoaches);
  final arrEnd = maxEnd(arrCoaches);

  // Gate 3 — nothing to optimise: wherever you sit, the next train is opposite.
  if (arrStart >= depStart - _containmentToleranceM &&
      arrEnd <= depEnd + _containmentToleranceM) {
    return null;
  }

  // The part of the arriving train that stands alongside the departing train.
  final alongside = arrCoaches
      .where(
        (c) =>
            c.platformPosition!.start < depEnd &&
            c.platformPosition!.end > depStart,
      )
      .toList();

  List<Coach> chosen;
  TransferAdviceReason reason;
  if (alongside.isNotEmpty) {
    chosen = alongside;
    reason = TransferAdviceReason.alongside;
  } else {
    // No overlap at all — the closest we can get is the arriving train's end
    // facing the departing train. Name that whole section, not one car.
    Coach nearestCoach = arrCoaches.first;
    var best = double.infinity;
    for (final c in arrCoaches) {
      final p = c.platformPosition!;
      final d = p.end <= depStart ? depStart - p.end : p.start - depEnd;
      if (d < best) {
        best = d;
        nearestCoach = c;
      }
    }
    final sector = nearestCoach.platformPosition!.sector.trim().toUpperCase();
    if (sector.isEmpty) return null;
    chosen = arrCoaches
        .where((c) => c.platformPosition!.sector.trim().toUpperCase() == sector)
        .toList();
    reason = TransferAdviceReason.nearest;
  }

  final sectors = _sectorsOf(chosen);
  if (sectors.isEmpty) return null; // no sector letters → nothing to say

  // Gate 4 — the advice has to actually narrow something down. Two 400 m ICEs
  // at one platform overlap across every section the arriving one occupies;
  // "be in A–G" is the whole train restated as a tip. Only speak when there is
  // a part of the train to avoid. (Gate 3 catches full containment by metres;
  // this catches the same thing once it's rounded to section letters.)
  final arrSectors = _sectorsOf(arrCoaches);
  if (sectors.length >= arrSectors.length) return null;

  final depSectors = _sectorsOf(depCoaches);
  if (depSectors.isEmpty) return null;

  final coaches = chosen.map((c) => c.wagonNumber).where((n) => n > 0).toList()
    ..sort();

  return TransferCoachAdvice(
    sectors: sectors,
    coaches: coaches,
    departingSectors: depSectors,
    reason: reason,
  );
}

/// Distinct section letters these coaches stand in, alphabetical — the order the
/// rest of the app labels sections in (see CoachGroup.sectors).
List<String> _sectorsOf(List<Coach> coaches) {
  final s = <String>{};
  for (final c in coaches) {
    final sec = c.platformPosition?.sector.trim().toUpperCase();
    if (sec != null && sec.isNotEmpty) s.add(sec);
  }
  return s.toList()..sort();
}
