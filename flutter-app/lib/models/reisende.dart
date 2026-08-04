import 'dart:convert';

import 'split_ticket.dart';

/// Traveller / discount models for the DB Vendo journey search
/// (`/mob/angebote/fahrplan`).
///
/// Every value here is taken verbatim from the DB Navigator app's bundled
/// master data (`assets/stammdaten/stammdaten_v6.json`,
/// `reisendenTypen` + `ermaessigungen`) plus a handful of SBA combinations
/// that were confirmed against the live endpoint. A compact extract lives in
/// `api-tests/db_stammdaten_enums.json` for reference. The healthcheck
/// (`check_vendo_journey_party`) posts a search exercising bike, dog, an SBA
/// reduction and an explicit child age to keep these keys honest.

/// `reisendenTypen` from the DB master data. `defaultAge` is `standardAlter`
/// (null = not age-dependent, i.e. bike/dog); `discountable` is
/// `istRabattierbar`.
enum TravelerType {
  erwachsener('ERWACHSENER', 'Person', '27–64 Jahre', 45, true),
  senior('SENIOR', 'Person', 'ab 65 Jahre', 65, true),
  jugendlicher('JUGENDLICHER', 'Person', '15–26 Jahre', 20, true),
  familienkind('FAMILIENKIND', 'Kind', '6–14 Jahre', 7, true),
  kleinkind('KLEINKIND', 'Kind', '0–5 Jahre', 3, false),
  fahrrad('FAHRRAD', 'Fahrrad', '', null, false),
  hund('HUND', 'Hund', '', null, false);

  final String vendoKey;
  final String label;
  final String ageBand;
  final int? defaultAge;
  final bool discountable;
  const TravelerType(
      this.vendoKey, this.label, this.ageBand, this.defaultAge, this.discountable);

  /// A real person (has an age band) vs. a bike/dog slot.
  bool get isPerson => defaultAge != null;

  /// Age-dependent types accept an explicit `alter` in the request.
  bool get ageDependent => defaultAge != null;

  bool get isBike => this == TravelerType.fahrrad;
  bool get isDog => this == TravelerType.hund;

  /// "Person · 27–64 Jahre" / "Fahrrad".
  String get fullLabel => ageBand.isEmpty ? label : '$label · $ageBand';

  static TravelerType byKey(String key) =>
      values.firstWhere((t) => t.vendoKey == key, orElse: () => erwachsener);
}

/// `ermaessigungen` (BahnCards + foreign railcards) from the master data.
/// Each carries the DB `<ART> <KLASSE>` token sent in `ermaessigungen`.
///
/// The DB app exposes these in two separate per-person selectors:
/// **BahnCard** ([isBahnCard] true) and **Weitere Ermäßigungen** (the foreign
/// railcards) — see [bahnCardOptions] / [weitereOptions].
enum Reduction {
  none('KEINE_ERMAESSIGUNG KLASSENLOS', 'Keine', false),
  bc25_2('BAHNCARD25 KLASSE_2', 'BahnCard 25 · 2. Kl.', true),
  bc25_1('BAHNCARD25 KLASSE_1', 'BahnCard 25 · 1. Kl.', true),
  bc50_2('BAHNCARD50 KLASSE_2', 'BahnCard 50 · 2. Kl.', true),
  bc50_1('BAHNCARD50 KLASSE_1', 'BahnCard 50 · 1. Kl.', true),
  bc100_2('BAHNCARD100 KLASSE_2', 'BahnCard 100 · 2. Kl.', true),
  bc100_1('BAHNCARD100 KLASSE_1', 'BahnCard 100 · 1. Kl.', true),
  bcBiz25_2('BAHNCARDBUSINESS25 KLASSE_2', 'BahnCard Business 25 · 2. Kl.', true),
  bcBiz25_1('BAHNCARDBUSINESS25 KLASSE_1', 'BahnCard Business 25 · 1. Kl.', true),
  bcBiz50_2('BAHNCARDBUSINESS50 KLASSE_2', 'BahnCard Business 50 · 2. Kl.', true),
  bcBiz50_1('BAHNCARDBUSINESS50 KLASSE_1', 'BahnCard Business 50 · 1. Kl.', true),
  chGa2('CH-GENERAL-ABONNEMENT KLASSE_2', 'CH-General-Abo · 2. Kl.', false),
  chGa1('CH-GENERAL-ABONNEMENT KLASSE_1', 'CH-General-Abo · 1. Kl.', false),
  chHalbtax('CH-HALBTAXABO_OHNE_RAILPLUS KLASSENLOS', 'HalbtaxAbo (CH)', false),
  atVorteil('A-VORTEILSCARD KLASSENLOS', 'Vorteilscard (AT)', false),
  nl40('NL-40_OHNE_RAILPLUS KLASSENLOS', 'NL-40 %', false),
  // Live in the master data and demonstrably real money: on Köln→Amsterdam it
  // takes 73,99 € to 51,60 € and 68 € to 43 €, while a made-up key on the same
  // search changes nothing (#21).
  nl100('NL-100 KLASSENLOS', 'NL-100 %', false),
  klimaAt('KLIMATICKET_OE KLASSE_2', 'KlimaTicket (AT)', false);

  final String vendoKey;
  final String label;
  final bool isBahnCard;
  const Reduction(this.vendoKey, this.label, this.isBahnCard);

  static Reduction byKey(String key) =>
      values.firstWhere((r) => r.vendoKey == key, orElse: () => none);

  /// "Keine" + the BahnCards, for the BahnCard selector.
  static List<Reduction> get bahnCardOptions =>
      [none, ...values.where((r) => r.isBahnCard)];

  /// "Keine" + the foreign railcards, for the "Weitere Ermäßigungen" selector.
  static List<Reduction> get weitereOptions =>
      [none, ...values.where((r) => r != none && !r.isBahnCard)];
}

/// Schwerbehindertenausweis options — the 2×2 matrix DB exposes
/// (Schwerbehinderung vs. Begleitperson × mit/ohne Rollstuhlplatz).
///
/// [beeintrOhneRolli] is no longer listed in the live master data, and is kept
/// anyway. "Returns 200" says nothing here: the endpoint accepts an invented
/// key like `TOTALLY_MADE_UP KLASSENLOS` with a 200 and the unchanged price,
/// so it clearly ignores what it doesn't know rather than rejecting it. By
/// every test available the de-listed key behaves exactly like its still-listed
/// sibling, so dropping it would take a real option away from real riders on
/// no evidence at all. The healthcheck reports the drift instead of failing on
/// it — see check_vendo_stammdaten_drift.
enum SbaOption {
  none('', 'Keiner'),
  beeintrOhneRolli(
      'SBA_BEEINTRAECHTIGUNGEN_KEIN_ROLLSTUHL KLASSENLOS',
      'Schwerbehinderung, ohne Rollstuhlplatz'),
  beeintrMitRolli(
      'SBA_BEEINTRAECHTIGUNGEN_MIT_ROLLSTUHL KLASSENLOS',
      'Schwerbehinderung, mit Rollstuhlplatz'),
  begleiterOhneRolli(
      'SBA_BEGLEITPERSON_KEIN_ROLLSTUHL KLASSENLOS',
      'Begleitperson, ohne Rollstuhlplatz'),
  begleiterMitRolli(
      'SBA_BEGLEITPERSON_MIT_ROLLSTUHL KLASSENLOS',
      'Begleitperson, mit Rollstuhlplatz');

  final String vendoKey;
  final String label;
  const SbaOption(this.vendoKey, this.label);

  static SbaOption byKey(String key) =>
      values.firstWhere((s) => s.vendoKey == key, orElse: () => none);
}

/// One entry in `reisendenProfil.reisende`.
class Traveler {
  final TravelerType typ;

  /// Explicit age for age-dependent persons (the DB "Alter angeben"). Sent as
  /// a scalar `alter`; null = use the type's standard band.
  final int? alter;

  /// The three independent reduction slots the DB app exposes per person.
  final Reduction bahnCard; // "BahnCard" selector
  final Reduction weitere; // "Weitere Ermäßigungen" selector (foreign cards)
  final SbaOption sba; // "Schwerbehindertenausweis" selector

  const Traveler({
    required this.typ,
    this.alter,
    this.bahnCard = Reduction.none,
    this.weitere = Reduction.none,
    this.sba = SbaOption.none,
  });

  Traveler copyWith({
    TravelerType? typ,
    int? alter,
    bool clearAlter = false,
    Reduction? bahnCard,
    Reduction? weitere,
    SbaOption? sba,
  }) {
    return Traveler(
      typ: typ ?? this.typ,
      alter: clearAlter ? null : (alter ?? this.alter),
      bahnCard: bahnCard ?? this.bahnCard,
      weitere: weitere ?? this.weitere,
      sba: sba ?? this.sba,
    );
  }

  /// JSON for the DB Vendo request. Bike/dog carry an empty `ermaessigungen`
  /// and no age; persons carry their reductions (BahnCard + SBA + foreign card)
  /// or the explicit "no discount" token, plus an explicit `alter` when set.
  Map<String, dynamic> toVendoJson() {
    final erm = <String>[];
    if (typ.discountable) {
      if (bahnCard != Reduction.none) erm.add(bahnCard.vendoKey);
      if (sba != SbaOption.none) erm.add(sba.vendoKey);
      if (weitere != Reduction.none) erm.add(weitere.vendoKey);
    }
    if (typ.isPerson && erm.isEmpty) erm.add(Reduction.none.vendoKey);
    return {
      'reisendenTyp': typ.vendoKey,
      'ermaessigungen': erm,
      if (typ.ageDependent && alter != null) 'alter': alter,
    };
  }

  Map<String, dynamic> toStorageJson() => {
        'typ': typ.vendoKey,
        if (alter != null) 'alter': alter,
        'bahnCard': bahnCard.vendoKey,
        'weitere': weitere.vendoKey,
        'sba': sba.vendoKey,
      };

  factory Traveler.fromStorageJson(Map<String, dynamic> j) {
    // Back-compat: an earlier build stored a single 'reduction' slot — route it
    // to the right new slot by kind.
    final legacy = Reduction.byKey(j['reduction'] as String? ?? '');
    return Traveler(
      typ: TravelerType.byKey(j['typ'] as String? ?? 'ERWACHSENER'),
      alter: (j['alter'] as num?)?.toInt(),
      bahnCard: Reduction.byKey(j['bahnCard'] as String? ??
          (legacy.isBahnCard ? legacy.vendoKey : '')),
      weitere: Reduction.byKey(j['weitere'] as String? ??
          (legacy != Reduction.none && !legacy.isBahnCard
              ? legacy.vendoKey
              : '')),
      sba: SbaOption.byKey(j['sba'] as String? ?? ''),
    );
  }
}

/// The full "Reisende & Klasse" selection driving a journey search.
class SearchParty {
  final bool firstClass;
  final bool deutschlandTicket;
  final List<Traveler> travelers;

  const SearchParty({
    this.firstClass = false,
    this.deutschlandTicket = false,
    this.travelers = const [Traveler(typ: TravelerType.erwachsener)],
  });

  int get personCount => travelers.where((t) => t.typ.isPerson).length;
  bool get hasBike => travelers.any((t) => t.typ.isBike);
  bool get hasDog => travelers.any((t) => t.typ.isDog);

  List<Map<String, dynamic>> toReisendeJson() =>
      travelers.map((t) => t.toVendoJson()).toList();

  /// Just the first *person* of this party, for the "what would one ticket
  /// cost?" comparison (#67).
  ///
  /// Their own discounts ride along so the comparison is like-for-like; bike
  /// and dog stay out, since those are extras on a booking, not a per-person
  /// fare, and counting them N times would invent a saving that isn't there.
  List<Map<String, dynamic>> toSingleTravellerJson() {
    final person = travelers.where((t) => t.typ.isPerson).firstOrNull;
    if (person == null) return toReisendeJson();
    return [person.toVendoJson()];
  }

  SearchParty copyWith({
    bool? firstClass,
    bool? deutschlandTicket,
    List<Traveler>? travelers,
  }) {
    return SearchParty(
      firstClass: firstClass ?? this.firstClass,
      deutschlandTicket: deutschlandTicket ?? this.deutschlandTicket,
      travelers: travelers ?? this.travelers,
    );
  }

  /// Short German summary for the search-form chip, e.g.
  /// "1 Reisende·r · 2. Kl." or "2 Pers., 🚲, 🐶 · 1. Kl.".
  String get summary {
    final parts = <String>[];
    if (personCount > 0) {
      parts.add(personCount == 1 ? '1 Reisende·r' : '$personCount Reisende');
    }
    if (hasBike) parts.add('🚲');
    if (hasDog) parts.add('🐶');
    if (parts.isEmpty) parts.add('0 Reisende');
    final klasse = firstClass ? '1. Kl.' : '2. Kl.';
    return '${parts.join(', ')} · $klasse';
  }

  /// Seed a sensible default from the persisted single-card settings: a single
  /// adult holding the configured BahnCard, in the matching class, plus the
  /// Deutschland-Ticket flag.
  factory SearchParty.fromSettings(
      BahnCardType card, bool deutschlandTicket) {
    return SearchParty(
      firstClass: card.isFirstClass,
      deutschlandTicket: deutschlandTicket,
      travelers: [
        Traveler(
          typ: TravelerType.erwachsener,
          bahnCard: Reduction.byKey(card.vendoErmaessigung),
        ),
      ],
    );
  }

  Map<String, dynamic> toStorageJson() => {
        'firstClass': firstClass,
        'deutschlandTicket': deutschlandTicket,
        'travelers': travelers.map((t) => t.toStorageJson()).toList(),
      };

  factory SearchParty.fromStorageJson(Map<String, dynamic> j) {
    final list = (j['travelers'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(Traveler.fromStorageJson)
        .toList();
    return SearchParty(
      firstClass: j['firstClass'] as bool? ?? false,
      deutschlandTicket: j['deutschlandTicket'] as bool? ?? false,
      travelers: list.isEmpty
          ? const [Traveler(typ: TravelerType.erwachsener)]
          : list,
    );
  }

  String encode() => json.encode(toStorageJson());
  static SearchParty? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return SearchParty.fromStorageJson(
          json.decode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
