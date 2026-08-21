import '../models/split_ticket.dart';
import '../services/db_api_service.dart';
import '../services/vendo_service.dart';
import 'split_stops.dart';

/// Result of pricing the segments of one route. `null` segments stay infinite.
typedef SplitProgress = void Function(int processed, int total, String segment);

/// Pure split-ticket engine: price every `i→j` segment of an ordered stop list,
/// find the cheapest forward split via DP, and clamp it to the direct fare (you
/// can always buy the through ticket, so a split must never cost more). Shared
/// by the single-connection analysis and the bulk price comparison so both
/// price identically.
class SplitEngine {
  final VendoService vendo;
  final DbApiService dbApi;
  const SplitEngine(this.vendo, this.dbApi);

  /// Analyse [stops] (`{name, id, departure_iso}` each). Returns the comparison,
  /// or null if cancelled mid-run or there are fewer than two stops.
  ///
  /// [reisende] is the Vendo-shaped party (age/type/BahnCard); [travellers] the
  /// website-shaped fallback used only if Vendo has no price for a segment.
  Future<TicketAnalysisResult?> analyze({
    required List<Map<String, dynamic>> stops,
    required String date,
    required double directPrice,
    required List<Map<String, dynamic>> reisende,
    required List<Map<String, dynamic>> travellers,
    required bool deutschlandTicket,
    required bool firstClass,
    required int apiDelayMs,
    SplitProgress? onProgress,
    bool Function()? isCancelled,
  }) async {
    final n = stops.length;
    if (n < 2) return null;
    final total = (n * (n - 1)) ~/ 2;
    final prices = <String, SegmentPrice>{};
    var processed = 0;
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        if (isCancelled?.call() ?? false) return null;
        final dtIso = stops[i]['departure_iso'] as String? ?? date;

        // Decide D-Ticket coverage from the trains THIS connection actually
        // uses, before spending a request. Free and exact — the backends can
        // only answer "some train between these stations is regional", which
        // is a different question and the source of #13's false "0,00 €" on
        // ICE segments.
        if (deutschlandTicket && isSegmentDTicketCovered(stops, i, j)) {
          prices['$i-$j'] = const SegmentPrice(
            price: 0.0,
            isDTicketCovered: true,
          );
          processed++;
          onProgress?.call(
            processed,
            total,
            '${stops[i]['name']} → ${stops[j]['name']}',
          );
          continue;
        }

        await Future.delayed(Duration(milliseconds: apiDelayMs));
        var price = await vendo.getSegmentPrice(
          from: stops[i]['id'] as String,
          to: stops[j]['id'] as String,
          dateTime: DateTime.tryParse(dtIso),
          firstClass: firstClass,
          reisende: reisende,
          expectedTrains: segmentTrainNumbers(stops, i, j),
        );
        if (price.price == double.infinity) {
          price = await dbApi.getSegmentPrice(
            fromId: stops[i]['id'] as String,
            toId: stops[j]['id'] as String,
            dateTime: dtIso,
            travellers: travellers,
            delayMs: apiDelayMs,
          );
        }
        if (isCancelled?.call() ?? false) return null;
        prices['$i-$j'] = price;
        processed++;
        onProgress?.call(
          processed,
          total,
          '${stops[i]['name']} → ${stops[j]['name']}',
        );
      }
    }

    // Cheapest forward split (DP over stops in route order).
    final dp = List<double>.filled(n, double.infinity);
    final parent = List<int>.filled(n, -1);
    dp[0] = 0;
    for (var j = 1; j < n; j++) {
      for (var i = 0; i < j; i++) {
        final seg = prices['$i-$j']?.price ?? double.infinity;
        if (dp[i] + seg < dp[j]) {
          dp[j] = dp[i] + seg;
          parent[j] = i;
        }
      }
    }

    final tickets = <SplitTicket>[];
    var current = n - 1;
    while (current > 0) {
      final prev = parent[current];
      if (prev < 0) break;
      final seg = prices['$prev-$current'];
      tickets.insert(
        0,
        SplitTicket(
          from: stops[prev]['name'] as String,
          to: stops[current]['name'] as String,
          price: seg?.price ?? 0,
          fromId: stops[prev]['id'] as String,
          toId: stops[current]['id'] as String,
          departureIso: stops[prev]['departure_iso'] as String? ?? date,
          coveredByDeutschlandTicket: seg?.isDTicketCovered ?? false,
          priceMayBeTrainBound: seg?.priceMayBeTrainBound ?? false,
        ),
      );
      current = prev;
    }

    var splitPrice = dp[n - 1];
    var resultTickets = tickets;
    // A single ticket spanning the whole route is not a split — it's the
    // through ticket, and the DP is free to "choose" it. It looked like a
    // saving only because directPrice is the selected connection's fare while
    // the 0→n-1 candidate was priced as the cheapest train on that route, so
    // it undercut it and got presented as "1 Ticket, 44 % gespart" over
    // identical endpoints (#13).
    // …unless it's a D-Ticket-covered route: "you need no ticket at all" is a
    // real, useful answer, not a degenerate split.
    final isWholeRoute =
        resultTickets.length <= 1 &&
        !(resultTickets.length == 1 &&
            resultTickets.first.coveredByDeutschlandTicket);
    // Never present a split that costs more than — or merely ties — the direct
    // fare: fall back to a single through ticket.
    if (isWholeRoute || (directPrice > 0 && splitPrice >= directPrice - 0.01)) {
      splitPrice = directPrice;
      resultTickets = [
        SplitTicket(
          from: stops.first['name'] as String,
          to: stops.last['name'] as String,
          price: directPrice,
          fromId: stops.first['id'] as String,
          toId: stops.last['id'] as String,
          departureIso: stops.first['departure_iso'] as String? ?? date,
        ),
      ];
    }

    stopwatch.stop();
    return TicketAnalysisResult(
      directPrice: directPrice,
      splitPrice: splitPrice,
      tickets: resultTickets,
      combinationsChecked: total,
      elapsed: stopwatch.elapsed,
    );
  }
}
