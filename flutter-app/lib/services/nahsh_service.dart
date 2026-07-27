import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../core/app_log.dart';
import '../models/station.dart';

/// A bay that has moved: what the timetable says, where the bus really goes from
/// today, and — when the backend says so — why.
typedef PlatformCorrection = ({String planned, String live, String? note});

/// The NAH.SH HAFAS — the Schleswig-Holstein transport authority's own backend,
/// used for ONE thing: the bay a bus actually leaves from when it has been moved.
///
/// **Why a fourth data source.** Kiel Hbf bay B1 has been fully closed since
/// 6 July 2026 and lines 22/50/51/52/81/91/N22 leave from B2 instead. Measured
/// on the day:
///
///  * DB Vendo (`/mob`, the app's main source) says B1 — no `himNotizen`, no
///    `echtzeitNotizen`, nothing. Not a parsing gap on our side: a Bus 13 at the
///    same board that day carried `{prio: HOCH, text: "Halt entfällt"}`, so the
///    field is live, the closure simply is not in it.
///  * DELFI via Transitous/MOTIS says B1 too, with `realTime: true`.
///  * The nationwide DELFI realtime stream is GTFS-RT **TripUpdates** and
///    SIRI-ET only — punctuality. There is no ServiceAlerts channel to carry a
///    closed bay at all.
///  * NAH.SH HAFAS has it as an ordinary realtime platform change:
///    `dPlatfS: B1`, `dPlatfR: B2`. 12 of 61 departures that morning, and the
///    distribution matches the operator's own notice exactly (B1→B2, B2→A1).
///
/// So this is the only source that answers "which bay, really" — and it answers
/// it in the same shape the app already understands for trains (planned Gleis vs
/// live Gleis).
///
/// **Deliberately narrow.** Each region runs its own HAFAS, so this one only
/// knows Schleswig-Holstein; [servesStop] gates on that before any request goes
/// out. It is asked only about buses and trams (for trains DB's own `ezGleis` is
/// authoritative and nationwide), and every failure is silent — without an
/// answer the app shows exactly what it showed before.
class NahShService {
  NahShService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _endpoint = 'https://nahsh.hafas.cloud/gate';

  /// The HAFAS client identity the NAH.SH app uses. Same values `hafas-client`'s
  /// public `nahsh` profile carries.
  static const _client_ = {
    'id': 'NAHSH',
    'type': 'IPH',
    'name': 'NAHSHPROD',
    'v': '4000100',
  };
  static const _auth = {'type': 'AID', 'aid': 'r0Ot9FLFNAFxijLW'};

  static const _timeout = Duration(seconds: 8);

  /// Schleswig-Holstein plus a margin. A free gate: outside it this backend has
  /// nothing, and asking would only cost a request and a stall.
  static const _minLat = 53.30, _maxLat = 55.10;
  static const _minLon = 7.80, _maxLon = 11.40;

  /// Whether this backend can possibly know [stop]. Stops without coordinates
  /// are not guessed at — no answer beats a wrong region's answer.
  static bool servesStop(Station stop) {
    final lat = stop.latitude, lon = stop.longitude;
    if (lat == null || lon == null) return false;
    return lat >= _minLat && lat <= _maxLat && lon >= _minLon && lon <= _maxLon;
  }

  /// The products worth asking about. Trains are DB's own turf — it publishes
  /// `ezGleis` for them nationwide, and a regional backend disagreeing about a
  /// Gleis would be noise, not news.
  static bool coversProduct(String? product) =>
      product == 'bus' || product == 'tram' || product == 'ferry';

  /// HAFAS stop ids, keyed by the DB stop we looked them up from. Held for the
  /// process: a stop's HAFAS id does not change, and re-resolving it would be
  /// one request per Reiseplan view.
  final Map<String, String?> _locations = {};
  final Map<String, Future<String?>> _locationsInflight = {};

  /// Departure boards, keyed by HAFAS id + 15-minute bucket. One board answers
  /// every leg at that stop.
  final Map<String, List<NahShDeparture>> _boards = {};
  final Map<String, Future<List<NahShDeparture>>> _boardsInflight = {};

  Future<Map<String, dynamic>?> _call(String method, Map<String, dynamic> req) async {
    final body = {
      'lang': 'de',
      'svcReqL': [
        {'cfg': const <String, dynamic>{}, 'meth': method, 'req': req},
      ],
      'client': _client_,
      'ver': '1.34',
      'auth': _auth,
    };
    try {
      final res = await _client
          .post(
            Uri.parse(_endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: utf8.encode(json.encode(body)),
          )
          .timeout(_timeout);
      if (res.statusCode != 200) {
        AppLog.log('nahsh $method HTTP ${res.statusCode}', tag: 'nahsh');
        return null;
      }
      final data =
          json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final svc = (data['svcResL'] as List<dynamic>?)?.firstOrNull;
      if (svc is! Map<String, dynamic> || svc['err'] != 'OK') {
        AppLog.log('nahsh $method err ${svc is Map ? svc['err'] : '?'}',
            tag: 'nahsh');
        return null;
      }
      return svc['res'] as Map<String, dynamic>?;
    } catch (e) {
      AppLog.log('nahsh $method failed: $e', tag: 'nahsh');
      return null;
    }
  }

  /// The HAFAS id for [stop], by name and confirmed by coordinates.
  ///
  /// HAFAS ids are not DB's EVA numbers (Kiel Hbf: 9049076 vs 699275), so the
  /// join is over the name — and then checked against the coordinate, because a
  /// name alone matches "Kiel Hbf/Kaistraße" just as happily.
  Future<String?> _locationIdFor(Station stop) {
    final key = stop.id.isNotEmpty ? stop.id : stop.name;
    if (_locations.containsKey(key)) return Future.value(_locations[key]);
    return _locationsInflight[key] ??= _resolveLocation(key, stop);
  }

  Future<String?> _resolveLocation(String key, Station stop) async {
    final res = await _call('LocMatch', {
      'input': {
        'loc': {'type': 'S', 'name': '${stop.name}?'},
        'maxLoc': 8,
        'field': 'S',
      },
    });
    final locs = ((res?['match'] as Map<String, dynamic>?)?['locL']
            as List<dynamic>?) ??
        const [];
    String? best;
    double bestMetres = double.infinity;
    for (final l in locs.whereType<Map<String, dynamic>>()) {
      final extId = l['extId'] as String?;
      final crd = l['crd'] as Map<String, dynamic>?;
      if (extId == null || crd == null) continue;
      // HAFAS coordinates are integer micro-degrees.
      final lat = (crd['y'] as num?)?.toDouble();
      final lon = (crd['x'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final d = _metres(stop.latitude!, stop.longitude!, lat / 1e6, lon / 1e6);
      if (d < bestMetres) {
        bestMetres = d;
        best = extId;
      }
    }
    // 300 m: the same stop as seen by two datasets, never the next one along.
    final resolved = bestMetres <= 300 ? best : null;
    AppLog.log(
        'nahsh loc "${stop.name}" → ${resolved ?? 'kein Treffer'}'
        '${resolved != null ? ' (${bestMetres.round()} m)' : ''}',
        tag: 'nahsh');
    _locations[key] = resolved;
    _locationsInflight.remove(key);
    return resolved;
  }

  /// The departure board at [extId] around [around].
  Future<List<NahShDeparture>> _board(String extId, DateTime around) {
    final bucket = around.millisecondsSinceEpoch ~/ (15 * 60 * 1000);
    final key = '$extId@$bucket';
    final cached = _boards[key];
    if (cached != null) return Future.value(cached);
    return _boardsInflight[key] ??= _fetchBoard(key, extId, around);
  }

  Future<List<NahShDeparture>> _fetchBoard(
      String key, String extId, DateTime around) async {
    // Start the board a few minutes early so a bus running late is still on it.
    final from = around.subtract(const Duration(minutes: 5));
    final res = await _call('StationBoard', {
      'type': 'DEP',
      'date': _date(from),
      'time': _time(from),
      'stbLoc': {'extId': extId},
      'maxJny': 80,
    });
    final list = parseBoard(res);
    AppLog.log('nahsh board $extId: ${list.length} departures, '
        '${list.where((d) => d.moved).length} moved', tag: 'nahsh');
    _boards[key] = list;
    _boardsInflight.remove(key);
    return list;
  }

  /// HAFAS `StationBoard` response → departures. Exposed for tests.
  static List<NahShDeparture> parseBoard(Map<String, dynamic>? res) {
    if (res == null) return const [];
    final common = res['common'];
    final prodRaw = common is Map<String, dynamic> ? common['prodL'] : null;
    final prodL = prodRaw is List<dynamic> ? prodRaw : const [];
    final himRaw = common is Map<String, dynamic> ? common['himL'] : null;
    final himL = himRaw is List<dynamic> ? himRaw : const [];
    final jnyRaw = res['jnyL'];
    final out = <NahShDeparture>[];
    for (final j in (jnyRaw is List<dynamic> ? jnyRaw : const [])
        .whereType<Map<String, dynamic>>()) {
      final stop = j['stbStop'] as Map<String, dynamic>?;
      if (stop == null) continue;
      final prodX = j['prodX'];
      final prod = (prodX is int && prodX >= 0 && prodX < prodL.length)
          ? prodL[prodX] as Map<String, dynamic>?
          : null;
      out.add(NahShDeparture(
        line: (prod?['name'] as String? ?? '').trim(),
        direction: (j['dirTxt'] as String? ?? '').trim(),
        plannedTime: _hhmmss(stop['dTimeS'] as String?),
        plannedPlatform: _platform(stop, 'S'),
        livePlatform: _platform(stop, 'R'),
        notes: _himHeads(himL, [j['msgL'], stop['msgL']]),
      ));
    }
    return out;
  }

  /// The headlines of the disruption messages hung on a departure — this is
  /// where the operator says WHY the bay moved ("Sperrung Bussteig B1 am
  /// Hauptbahnhof"). Deduped: HAFAS links the same message from several places.
  static List<String> _himHeads(List<dynamic> himL, List<dynamic> msgLists) {
    final out = <String>[];
    for (final msgs in msgLists) {
      if (msgs is! List<dynamic>) continue;
      for (final m in msgs.whereType<Map<String, dynamic>>()) {
        final x = m['himX'];
        if (x is! int || x < 0 || x >= himL.length) continue;
        final him = himL[x];
        if (him is! Map<String, dynamic>) continue;
        final head = (him['head'] as String? ?? '').trim();
        if (head.isEmpty || out.contains(head)) continue;
        out.add(head);
      }
    }
    return out;
  }

  /// Both HAFAS spellings: the flat `dPlatfS`/`dPlatfR` and the newer
  /// `dPltfS`/`dPltfR` object with a `txt`.
  static String? _platform(Map<String, dynamic> stop, String suffix) {
    final flat = stop['dPlatf$suffix'];
    if (flat is String && flat.trim().isNotEmpty) return flat.trim();
    final obj = stop['dPltf$suffix'];
    if (obj is Map<String, dynamic>) {
      final txt = obj['txt'];
      if (txt is String && txt.trim().isNotEmpty) return txt.trim();
    }
    return null;
  }

  /// Where the bus for [line] towards [towards] really leaves from, when that
  /// differs from the timetable — otherwise null, and nothing changes.
  ///
  /// [plannedDeparture] is matched against the board's scheduled time (not the
  /// live one): that is the value both sides agree on however late the bus is.
  Future<PlatformCorrection?> platformCorrection({
    required Station stop,
    required String? line,
    required String? towards,
    required DateTime plannedDeparture,
    String? product,
  }) async {
    if (!servesStop(stop)) return null;
    if (product != null && !coversProduct(product)) return null;
    final extId = await _locationIdFor(stop);
    if (extId == null) return null;
    final board = await _board(extId, plannedDeparture);
    return matchDeparture(
      board,
      line: line,
      towards: towards,
      plannedDeparture: plannedDeparture,
    );
  }

  /// The correction for one ride out of a board. Exposed for tests, which is
  /// where the matching rules actually live.
  ///
  /// Time first (a bay is per departure, not per line), then the line, then the
  /// destination as a tiebreak — a stop can have the same line leaving in two
  /// directions from two bays within the same minute.
  static PlatformCorrection? matchDeparture(
    List<NahShDeparture> board, {
    String? line,
    String? towards,
    required DateTime plannedDeparture,
    Duration tolerance = const Duration(minutes: 2),
  }) {
    final wantedLine = _lineKey(line);
    final wantedTo = _placeKey(towards);
    final minutes = plannedDeparture.hour * 60 + plannedDeparture.minute;

    final candidates = <NahShDeparture>[];
    for (final d in board) {
      if (!d.moved) continue;
      final t = d.plannedTime;
      if (t == null) continue;
      var diff = (t - minutes).abs();
      // Around midnight the board wraps; 23:58 and 00:01 are three minutes apart.
      if (diff > 720) diff = 1440 - diff;
      if (diff > tolerance.inMinutes) continue;
      if (wantedLine != null && _lineKey(d.line) != wantedLine) continue;
      candidates.add(d);
    }
    if (candidates.isEmpty) return null;

    // The destination is a filter, not just a tiebreak. Line 22 leaves Kiel Hbf
    // for Schwentinental at 09:38 (bay unchanged) and for Suchsdorf at 09:39
    // (B1 → B2); a minute of tolerance otherwise hands the Schwentinental rider
    // the other ride's correction and sends them to the wrong bay.
    if (wantedTo != null && candidates.any((d) => d.direction.isNotEmpty)) {
      final byDirection = candidates
          .where((d) => _directionMatches(d.direction, wantedTo))
          .toList();
      // Nothing in this direction moved — which is an answer: no correction.
      if (byDirection.length != 1) return null;
      return _correctionOf(byDirection.first);
    }

    // Ambiguity is failure: sending a rider to the wrong bay is worse than
    // leaving the timetable's answer alone.
    if (candidates.length != 1) return null;
    return _correctionOf(candidates.first);
  }

  /// The message that names the bay the bus left, when there is one — at Kiel
  /// Hbf "Sperrung Bussteig B1 am Hauptbahnhof", which is the difference between
  /// "why is it B2 now" and a bare change.
  static String? _bestNote(NahShDeparture d) {
    final bay = d.plannedPlatform?.toLowerCase();
    if (bay != null) {
      for (final n in d.notes) {
        if (n.toLowerCase().contains(bay)) return n;
      }
    }
    return d.notes.isEmpty ? null : d.notes.first;
  }

  static PlatformCorrection _correctionOf(NahShDeparture d) => (
        planned: d.plannedPlatform!,
        live: d.livePlatform!,
        note: _bestNote(d),
      );

  /// Whether a board entry heads where the rider does. Prefix either way, since
  /// the two sources spell the same place differently often enough
  /// ("Suchsdorf" vs "Kiel Suchsdorf, Wendeschleife").
  static bool _directionMatches(String boardDirection, String wanted) {
    final d = _placeKey(boardDirection);
    if (d == null) return false;
    return d == wanted || d.startsWith(wanted) || wanted.startsWith(d);
  }

  /// "Bus 22" / "22" / "bus22" all mean line 22.
  static String? _lineKey(String? s) {
    if (s == null) return null;
    final t = s
        .toUpperCase()
        .replaceAll(RegExp(r'\b(BUS|TRAM|STR|FÄHRE|FAEHRE)\b'), '')
        .replaceAll(RegExp(r'[\s.\-_/]'), '');
    return t.isEmpty ? null : t;
  }

  static String? _placeKey(String? s) {
    if (s == null) return null;
    final head = s.split(',').first;
    final t = head.toLowerCase().replaceAll(RegExp(r'[^a-z0-9äöüß]'), '');
    return t.isEmpty ? null : t;
  }

  static String _date(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}';
  static String _time(DateTime t) =>
      '${_two(t.hour)}${_two(t.minute)}00';
  static String _two(int v) => v.toString().padLeft(2, '0');

  /// HAFAS "HHMMSS" → minutes since midnight. A leading day offset ("1093900",
  /// the day after) is tolerated by reading the last six digits.
  static int? _hhmmss(String? s) {
    if (s == null || s.length < 6) return null;
    final t = s.substring(s.length - 6);
    final h = int.tryParse(t.substring(0, 2));
    final m = int.tryParse(t.substring(2, 4));
    if (h == null || m == null) return null;
    return h * 60 + m;
  }

  static double _metres(double lat1, double lon1, double lat2, double lon2) {
    final dy = (lat1 - lat2) * 111320.0;
    final dx = (lon1 - lon2) * 111320.0 * math.cos(lat1 * math.pi / 180.0);
    return math.sqrt(dx * dx + dy * dy);
  }
}

/// One departure off the NAH.SH board.
class NahShDeparture {
  final String line;
  final String direction;

  /// Scheduled departure as minutes since midnight.
  final int? plannedTime;

  final String? plannedPlatform;
  final String? livePlatform;

  /// Headlines of the operator's disruption messages for this departure.
  final List<String> notes;

  const NahShDeparture({
    required this.line,
    required this.direction,
    required this.plannedTime,
    required this.plannedPlatform,
    required this.livePlatform,
    this.notes = const [],
  });

  /// This departure has been moved to a different bay.
  bool get moved =>
      plannedPlatform != null &&
      livePlatform != null &&
      plannedPlatform != livePlatform;
}
