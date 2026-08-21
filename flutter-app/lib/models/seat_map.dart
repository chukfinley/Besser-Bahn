/// Graphical seat display (GSD) for a train run.
///
/// Source: the DB Navigator backend `app.services-bahn.de/mob/gsd` — the same
/// "Sitzplatz reservieren" screen the official app shows during booking. It is
/// NOT behind auth: the SSR endpoint returns real per-train reservation status
/// keyed on train number + boarding/alighting EVA + planned times. The booking
/// `zugfahrtKey` in the captured request turned out to be ignored, so we can
/// drive it straight from a [Trip]'s leg data. See [seat_map_service.dart].
library;

/// Reservation state of a single seat. The codes come straight from DB's own
/// `status` enum in the gsd bundle (`fD`):
///   0 = NICHT_AUSWAEHLBAR (reserved / occupied — NOT free)
///   1 = AUSWAEHLBAR       (free / reservable)
///   2 = VORGESCHLAGEN     (the seat the backend auto-suggests — also free)
/// NB: 0 is *occupied*, not free — the opposite of what the value might
/// suggest. We don't book, so the suggested seat (2) is just another free one.
enum SeatStatus {
  /// Reservable / available (status 1 or 2).
  free,

  /// Already reserved / occupied (status 0).
  occupied,

  /// Seat present in the layout but absent from the status payload.
  unknown,
}

SeatStatus seatStatusFromCode(int? code) {
  switch (code) {
    case 1: // AUSWAEHLBAR
    case 2: // VORGESCHLAGEN (system-suggested, but free)
      return SeatStatus.free;
    case 0: // NICHT_AUSWAEHLBAR
      return SeatStatus.occupied;
    default:
      return SeatStatus.unknown;
  }
}

/// One seat with its reservation state.
class Seat {
  final String number;
  final SeatStatus status;

  const Seat({required this.number, required this.status});

  factory Seat.fromJson(Map<String, dynamic> json) => Seat(
    number: (json['nummer'] ?? '').toString(),
    status: seatStatusFromCode(json['status'] as int?),
  );
}

/// A coach in the train, with its seats and (lazily loaded) physical layout.
class SeatCoach {
  final String number; // "7"
  final String wagentyp; // "I9812-412.(12-TLG.)-7" — key for the layout API
  final List<Seat> seats;

  /// Physical geometry of this coach (seat positions, tables, symbols). Fetched
  /// separately from `gsd/api/wagentypen/{wagentyp}` and attached afterwards.
  final CoachLayout? layout;

  const SeatCoach({
    required this.number,
    required this.wagentyp,
    required this.seats,
    this.layout,
  });

  int get freeCount => seats.where((s) => s.status == SeatStatus.free).length;
  int get totalCount => seats.length;
  bool get hasFree => freeCount > 0;

  /// Reservation status of a seat by its number, for painting the layout.
  SeatStatus statusOf(String seatNumber) {
    for (final s in seats) {
      if (s.number == seatNumber) return s.status;
    }
    return SeatStatus.unknown;
  }

  SeatCoach withLayout(CoachLayout? layout) => SeatCoach(
    number: number,
    wagentyp: wagentyp,
    seats: seats,
    layout: layout,
  );

  factory SeatCoach.fromJson(Map<String, dynamic> json) {
    final plaetze = json['plaetze'] as List<dynamic>? ?? const [];
    return SeatCoach(
      number: (json['nummer'] ?? '').toString(),
      wagentyp: (json['wagentyp'] ?? '').toString(),
      seats: plaetze
          .whereType<Map<String, dynamic>>()
          .map(Seat.fromJson)
          .toList(),
    );
  }
}

/// A whole train's seat map: the ordered coaches.
class SeatMap {
  final List<SeatCoach> coaches;

  const SeatMap({required this.coaches});

  int get totalFree => coaches.fold(0, (n, c) => n + c.freeCount);
  int get totalSeats => coaches.fold(0, (n, c) => n + c.totalCount);
  bool get isEmpty => coaches.isEmpty || totalSeats == 0;

  /// Coach numbers that still have a free seat — so a rider on a nearly-full
  /// train sees *where* the space is ("frei in Wagen 6") instead of a bare
  /// count or a misleading empty state (#seat).
  List<String> get freeCoachNumbers => [
    for (final c in coaches)
      if (c.hasFree) c.number,
  ];

  /// "  ·  frei in Wagen 6, 11" when seats are scarce (≤ 5 coaches with space),
  /// empty otherwise — appended to the "N von M frei" line when no coach is
  /// selected. On a nearly-full train this is the piece that matters (#seat).
  String get freeCoachHint {
    final free = freeCoachNumbers;
    if (free.isEmpty || free.length > 5) return '';
    return '  ·  frei in Wagen ${free.join(', ')}';
  }

  /// Parse the `ssr_data` JSON embedded in the gsd_v3 HTML page.
  factory SeatMap.fromSsr(Map<String, dynamic> ssr) {
    final zugteile =
        (ssr['zugfahrt'] as Map<String, dynamic>?)?['zugteile']
            as List<dynamic>? ??
        const [];
    final coaches = <SeatCoach>[];
    for (final teil in zugteile.whereType<Map<String, dynamic>>()) {
      final wagen = teil['wagen'] as List<dynamic>? ?? const [];
      for (final w in wagen.whereType<Map<String, dynamic>>()) {
        coaches.add(SeatCoach.fromJson(w));
      }
    }
    return SeatMap(coaches: coaches);
  }
}

/// Physical layout of a coach type — the grid DB draws the seat plan on.
///
/// Coordinates live on a [width]×[height] grid (typically 120×20). Elements are
/// seats ([LayoutElementType.platz]), fixtures like tables/walls
/// ([LayoutElementType.einbau]) and pictograms ([LayoutElementType.symbol]).
class CoachLayout {
  final String id;
  final int width;
  final int height;
  final String klasse;
  final List<LayoutElement> elements;

  const CoachLayout({
    required this.id,
    required this.width,
    required this.height,
    required this.klasse,
    required this.elements,
  });

  factory CoachLayout.fromJson(Map<String, dynamic> json) {
    final teile = json['wagenteile'] as List<dynamic>? ?? const [];
    // A coach can have multiple "wagenteile" (e.g. split classes). We render
    // the widest as the body and merge all elements onto one grid.
    final elements = <LayoutElement>[];
    int width = 0, height = 0;
    String klasse = '';
    for (final t in teile.whereType<Map<String, dynamic>>()) {
      width = (t['width'] as num?)?.toInt() ?? width;
      height = (t['height'] as num?)?.toInt() ?? height;
      klasse = (t['klasse'] as String?) ?? klasse;
      final els = t['elemente'] as List<dynamic>? ?? const [];
      elements.addAll(
        els.whereType<Map<String, dynamic>>().map(LayoutElement.fromJson),
      );
    }
    return CoachLayout(
      id: (json['id'] ?? '').toString(),
      width: width,
      height: height,
      klasse: klasse,
      elements: elements,
    );
  }
}

enum LayoutElementType { platz, einbau, symbol, unknown }

LayoutElementType _elementType(String? t) {
  switch (t) {
    case 'PLATZ':
      return LayoutElementType.platz;
    case 'EINBAU':
      return LayoutElementType.einbau;
    case 'SYMBOL':
      return LayoutElementType.symbol;
    default:
      return LayoutElementType.unknown;
  }
}

/// Which way a seat faces / where a fixture sits.
enum ElementDirection { links, rechts, oben, unten, none }

ElementDirection _direction(String? d) {
  switch (d) {
    case 'LINKS':
      return ElementDirection.links;
    case 'RECHTS':
      return ElementDirection.rechts;
    case 'OBEN':
      return ElementDirection.oben;
    case 'UNTEN':
      return ElementDirection.unten;
    default:
      return ElementDirection.none;
  }
}

class LayoutElement {
  final double x;
  final double y;
  final LayoutElementType type;
  final String? subtype; // TISCH_GROSS, WC, FAHRRAD, HANDY, BEHINDERT, …
  final String? number; // seat number (only for PLATZ)
  final ElementDirection direction;
  final List<String> hinweise; // e.g. ["SICHT"] (window seat), ["GEPAECK"]

  const LayoutElement({
    required this.x,
    required this.y,
    required this.type,
    this.subtype,
    this.number,
    this.direction = ElementDirection.none,
    this.hinweise = const [],
  });

  factory LayoutElement.fromJson(Map<String, dynamic> json) => LayoutElement(
    x: (json['x'] as num?)?.toDouble() ?? 0,
    y: (json['y'] as num?)?.toDouble() ?? 0,
    type: _elementType(json['type'] as String?),
    subtype: json['subtype'] as String?,
    number: json['nummer']?.toString(),
    direction: _direction(json['direction'] as String?),
    hinweise: (json['hinweise'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
  );
}
