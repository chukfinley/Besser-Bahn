import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants.dart';
import '../models/reisende.dart';
import '../models/split_ticket.dart';

/// Service for Deutsche Bahn internal web API (bahn.de)
/// Used for price queries and split-ticketing.
class DbApiService {
  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
    'User-Agent': ApiConstants.userAgent,
    'Accept': 'application/json',
    'Accept-Language': 'de-DE,de;q=0.9',
    'Content-Type': 'application/json',
  };

  /// Search stations via bahn.de API
  Future<List<Map<String, dynamic>>> searchStations(String query) async {
    final uri = Uri.parse('${ApiConstants.dbWebApiBaseUrl}/reiseloesung/orte')
        .replace(
          queryParameters: {'suchbegriff': query, 'typ': 'ALL', 'limit': '10'},
        );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode != 200) return [];

    final result = json.decode(response.body);
    if (result is List) {
      return result.whereType<Map<String, dynamic>>().toList();
    }
    return [];
  }

  /// Get connection details with prices (for split-ticketing)
  Future<Map<String, dynamic>> getConnectionDetails({
    required String fromId,
    required String toId,
    required String dateTime,
    required List<Map<String, dynamic>> travellers,
    bool deutschlandTicket = false,
  }) async {
    final uri = Uri.parse('${ApiConstants.dbWebApiBaseUrl}/angebote/fahrplan');

    final body = {
      'abfahrtsHalt': fromId,
      'ankunftsHalt': toId,
      'anfrageZeitpunkt': dateTime,
      'ankunftSuche': 'ABFAHRT',
      'klasse': 'KLASSE_2',
      'produktgattungen': [
        'ICE',
        'EC_IC',
        'IR',
        'REGIONAL',
        'SBAHN',
        'BUS',
        'SCHIFF',
        'UBAHN',
        'TRAM',
        'ANRUFPFLICHTIG',
      ],
      'reisende': travellers,
      'schnelleVerbindungen': true,
      'deutschlandTicketVorhanden': deutschlandTicket,
    };

    final response = await _client.post(
      uri,
      headers: _headers,
      body: json.encode(body),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to get connections: ${response.statusCode}');
    }
    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Get price for a single segment
  Future<SegmentPrice> getSegmentPrice({
    required String fromId,
    required String toId,
    required String dateTime,
    required List<Map<String, dynamic>> travellers,
    bool deutschlandTicket = false,
    required int delayMs,
  }) async {
    await Future.delayed(Duration(milliseconds: delayMs));

    try {
      final result = await getConnectionDetails(
        fromId: fromId,
        toId: toId,
        dateTime: dateTime,
        travellers: travellers,
        deutschlandTicket: deutschlandTicket,
      );

      final connections = result['verbindungen'] as List<dynamic>? ?? [];
      if (connections.isEmpty) {
        return const SegmentPrice(
          price: double.infinity,
          isDTicketCovered: false,
        );
      }

      final first = connections[0] as Map<String, dynamic>;

      // NOTE: no D-Ticket coverage inference here either. This used to set the
      // whole segment to 0,00 € as soon as ANY section carried the 9G
      // attribute — so a Regional+ICE connection came out free because of its
      // regional first leg (#13). Coverage is now decided by the caller from
      // the selected connection's trains (isSegmentDTicketCovered), which is
      // both exact and free. `deutschlandTicket` still shapes the request.
      // This is the blind `connections[0]` the issue called out: no matching
      // against the selected connection happens here at all, so the fare may
      // well belong to another train. The vendo path can at least try to match
      // and flags itself when it can't — this one can never vouch for a price,
      // so it always flags. Claiming otherwise would make the fallback look
      // MORE trustworthy than the primary (#13).
      final priceObj = first['angebotsPreis'] as Map<String, dynamic>?;
      final price =
          (priceObj?['betrag'] as num?)?.toDouble() ?? double.infinity;
      return SegmentPrice(
        price: price,
        isDTicketCovered: false,
        priceMayBeTrainBound: true,
      );
    } catch (_) {
      return const SegmentPrice(
        price: double.infinity,
        isDTicketCovered: false,
      );
    }
  }

  /// Create traveller payload for the bahn.de web API (DB fallback path).
  ///
  /// Accepts [bahnCard] (BahnCard reduction), [weitere] (foreign
  /// railcards like Halbtax / Vorteilscard / NL-40), and [sba]
  /// (Schwerbehindertenausweis) so the fallback matches the Vendo primary path.
  static List<Map<String, dynamic>> createTravellerPayload({
    Reduction bahnCard = Reduction.none,
    Reduction weitere = Reduction.none, // e.g. Halbtax, Vorteilscard, NL-40
    SbaOption sba = SbaOption.none, // Schwerbehindertenausweis
  }) {
    // Every reduction is stored as the Vendo key "ART KLASSE"
    // ("BAHNCARD25 KLASSE_2", "HALBTAXABO KLASSENLOS") — the web API wants the
    // two halves as separate fields.
    Map<String, dynamic> entry(String vendoKey) {
      final parts = vendoKey.split(' ');
      return {
        'art': parts.first,
        'klasse': parts.length > 1 ? parts[1] : 'KLASSENLOS',
      };
    }

    return [
      {
        'typ': 'ERWACHSENER',
        'ermaessigungen': [
          // Always exactly one BahnCard entry, "none" included: the web API
          // treats an empty list as a malformed traveller, not as "no card".
          entry(
            bahnCard == Reduction.none
                ? 'KEINE_ERMAESSIGUNG KLASSENLOS'
                : bahnCard.vendoKey,
          ),
          if (weitere != Reduction.none) entry(weitere.vendoKey),
          if (sba != SbaOption.none) entry(sba.vendoKey),
        ],
        'alter': [],
        'anzahl': 1,
      },
    ];
  }

  /// Open/book a WHOLE connection on bahn.de: the standard fahrplan-suche deep
  /// link, pre-filled with origin/destination, date and the user's BahnCard /
  /// Deutschland-Ticket so the shown price matches the app.
  static String generateJourneyLink({
    required String fromName,
    required String toName,
    required String fromId,
    required String toId,
    required String departureIso,
    BahnCardType bahnCard = BahnCardType.none,
    bool deutschlandTicket = false,
  }) {
    final from = Uri.encodeComponent(fromName);
    final to = Uri.encodeComponent(toName);
    final hd = Uri.encodeComponent(departureIso.split('.').first);
    final dtFlag = deutschlandTicket ? 'true' : 'false';
    final bcCode = bahnCard.bookingCode;
    final bcParam = bcCode.isNotEmpty ? '&rk=$bcCode' : '';

    return 'https://www.bahn.de/buchung/fahrplan/suche#'
        'sts=true&so=$from&zo=$to'
        '&soid=$fromId&zoid=$toId'
        '&hd=$hd'
        '&dt=$dtFlag$bcParam';
  }

  /// Generate a booking link for a split ticket
  static String generateBookingLink(
    SplitTicket ticket, {
    BahnCardType bahnCard = BahnCardType.none,
    bool deutschlandTicket = false,
  }) {
    final from = Uri.encodeComponent(ticket.from);
    final to = Uri.encodeComponent(ticket.to);
    final dtFlag = deutschlandTicket ? 'true' : 'false';
    final bcCode = bahnCard.bookingCode;
    final bcParam = bcCode.isNotEmpty ? '&rk=$bcCode' : '';

    return 'https://www.bahn.de/buchung/fahrplan/suche#'
        'sts=true&so=$from&zo=$to'
        '&soid=${ticket.fromId}&zoid=${ticket.toId}'
        '&hd=${ticket.departureIso}'
        '&dt=$dtFlag$bcParam';
  }

  // ── Pasted share-link → connection (revived split-ticket entry) ──────────
  //
  // A DB "Reise teilen" link comes in three shapes the user might paste:
  //   • a short link  https://www.bahn.de/buchung/start?vbid=<uuid>
  //   • a bare vbid
  //   • a long fahrplan link with #…&soid=…&zoid=…&hd=…
  // We resolve all of them to the same `verbindungen[]` structure the rest of
  // the split-ticket code already speaks (verbindungsAbschnitte → halte +
  // angebotsPreis). Verified live against www.bahn.de/web/api/angebote/{verbindung,recon}.

  static final RegExp _urlRe = RegExp(r'https?://\S+');
  static final RegExp _vbidRe = RegExp(r'vbid=([\w-]+)');

  String? _extractVbid(String s) {
    final q = Uri.tryParse(s)?.queryParameters['vbid'];
    if (q != null && q.isNotEmpty) return q;
    return _vbidRe.firstMatch(s)?.group(1);
  }

  Map<String, String> _fragmentParams(String url) {
    final uri = Uri.tryParse(url);
    final out = <String, String>{};
    if (uri == null) return out;
    for (final part in uri.fragment.split('&')) {
      final kv = part.split('=');
      if (kv.length == 2) out[kv[0]] = Uri.decodeComponent(kv[1]);
    }
    out.addAll(uri.queryParameters);
    return out;
  }

  /// vbid → full connection: look up the recon ctx for the share id, then post
  /// it to /recon (same flow the bahn.de website runs behind a shared link).
  Future<Map<String, dynamic>?> _resolveVbid(
    String vbid,
    List<Map<String, dynamic>> travellers,
    bool deutschlandTicket,
  ) async {
    final lookup = await _client.get(
      Uri.parse('${ApiConstants.dbWebApiBaseUrl}/angebote/verbindung/$vbid'),
      headers: _headers,
    );
    if (lookup.statusCode != 200) return null;
    final recon =
        (json.decode(lookup.body) as Map<String, dynamic>?)?['hinfahrtRecon'];
    if (recon == null) return null;

    final recked = await _client.post(
      Uri.parse('${ApiConstants.dbWebApiBaseUrl}/angebote/recon'),
      headers: _headers,
      body: json.encode({
        'klasse': 'KLASSE_2',
        'reisende': travellers,
        'ctxRecon': recon,
        'deutschlandTicketVorhanden': deutschlandTicket,
      }),
    );
    if (recked.statusCode != 200 && recked.statusCode != 201) return null;
    if (recked.body.isEmpty) return null;
    return json.decode(recked.body) as Map<String, dynamic>;
  }

  /// Resolve a pasted DB share link into a concrete connection ready for
  /// [SplitTicketNotifier.analyze]: whole-trip price + ordered unique stops.
  /// Returns null if the input carries no usable link or the price is missing.
  Future<ResolvedShareConnection?> resolveShareLink(
    String input, {
    BahnCardType bahnCard = BahnCardType.none,
    bool deutschlandTicket = false,
  }) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final url = _urlRe.firstMatch(trimmed)?.group(0) ?? trimmed;
    final travellers = createTravellerPayload(
      bahnCard: Reduction.byKey(bahnCard.vendoErmaessigung),
    );

    Map<String, dynamic>? data;
    final vbid = _extractVbid(url) ?? _extractVbid(trimmed);
    if (vbid != null) {
      data = await _resolveVbid(vbid, travellers, deutschlandTicket);
    } else {
      final p = _fragmentParams(url);
      final soid = p['soid'], zoid = p['zoid'], hd = p['hd'];
      if (soid != null && zoid != null && hd != null) {
        data = await getConnectionDetails(
          fromId: soid,
          toId: zoid,
          dateTime: hd,
          travellers: travellers,
          deutschlandTicket: deutschlandTicket,
        );
      }
    }
    if (data == null) return null;

    final verbindungen = data['verbindungen'] as List<dynamic>?;
    if (verbindungen == null || verbindungen.isEmpty) return null;
    final first = verbindungen.first as Map<String, dynamic>;
    final directPrice =
        ((first['angebotsPreis'] as Map<String, dynamic>?)?['betrag'] as num?)
            ?.toDouble();
    if (directPrice == null) return null;

    final stops = <Map<String, dynamic>>[];
    for (final section
        in (first['verbindungsAbschnitte'] as List<dynamic>? ?? const [])) {
      if (section is! Map<String, dynamic>) continue;
      if ((section['verkehrsmittel'] as Map<String, dynamic>?)?['typ'] ==
          'WALK') {
        continue;
      }
      for (final halt in (section['halte'] as List<dynamic>? ?? const [])) {
        if (halt is! Map<String, dynamic>) continue;
        final id = halt['id'];
        if (id == null || stops.any((s) => s['id'] == id)) continue;
        stops.add({
          'name': halt['name'],
          'id': id,
          'departure_iso': halt['abfahrtsZeitpunkt'] ?? '',
        });
      }
    }
    if (stops.length < 2) return null;

    final date = (stops.first['departure_iso'] as String).split('T').first;
    return ResolvedShareConnection(
      routeLabel: '${stops.first['name']} → ${stops.last['name']}',
      date: date,
      directPrice: directPrice,
      stops: stops,
    );
  }

  void dispose() => _client.close();
}

class SegmentPrice {
  final double price;
  final bool isDTicketCovered;

  /// The quoted fare could not be tied to the trains the rider actually
  /// selected — it's the cheapest offer between these two stops, which may be
  /// a Sparpreis bound to a different train. Surfaced as a hint on the ticket
  /// rather than dropping the price, so the analysis keeps its results while
  /// staying honest about what it knows (#13).
  final bool priceMayBeTrainBound;

  const SegmentPrice({
    required this.price,
    required this.isDTicketCovered,
    this.priceMayBeTrainBound = false,
  });
}

/// A connection resolved from a pasted DB share link, shaped for
/// [SplitTicketNotifier.analyze]. `stops` are ordered, de-duplicated halts,
/// each a `{name, id, departure_iso}` map.
class ResolvedShareConnection {
  final String routeLabel;
  final String date; // yyyy-MM-dd
  final double directPrice;
  final List<Map<String, dynamic>> stops;
  const ResolvedShareConnection({
    required this.routeLabel,
    required this.date,
    required this.directPrice,
    required this.stops,
  });
}
