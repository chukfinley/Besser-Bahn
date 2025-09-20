import 'package:besser_bahn/models/ticket_models.dart'; // Import models
import 'package:besser_bahn/services/bahn_api_service.dart'; // Import service
import 'package:besser_bahn/utils/traveller_helpers.dart'; // Import helpers

class SplitTicketLogic {
  final Function(String) _addLog;
  final Function(int, int) _updateProgress;
  final BahnApiService _apiService;
  final TravellerHelpers _travellerHelpers;
  // New: Getter for cancellation status
  final bool Function() _isCancelled;

  SplitTicketLogic(
    this._addLog,
    this._updateProgress,
    this._apiService,
    this._travellerHelpers,
    this._isCancelled,
  );

  Future<TicketAnalysisResult> findCheapestSplit(
    List<Map<String, dynamic>> stops,
    String date,
    double directPrice,
    List<Map<String, dynamic>> travellerPayload,
  ) async {
    if (_isCancelled()) { // Check cancellation at start of logic
      return TicketAnalysisResult(
        directPrice: directPrice,
        splitPrice: double.infinity,
        tickets: [],
      );
    }

    final int n = stops.length;
    final Map<
      String,
      Map<String, dynamic>
    > segmentsData = {};

    _addLog(
      "\n--- Preise und Daten für alle möglichen Teilstrecken werden abgerufen ---",
    );

    int totalCombinations = 0;
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (stops[i]['departure_time'].isNotEmpty) {
          totalCombinations++;
        }
      }
    }

    _updateProgress(
      0,
      totalCombinations,
    );
    int processedCombinations = 0;

    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (_isCancelled()) { // Check cancellation inside main loop
          _addLog("Teilstrecken-Abruf abgebrochen.");
          return TicketAnalysisResult(
            directPrice: directPrice,
            splitPrice: double.infinity,
            tickets: [],
          );
        }

        final fromStop = stops[i];
        final toStop = stops[j];

        if (fromStop['departure_time'].isEmpty) {
          continue;
        }

        final data = await _apiService.getSegmentData(
          fromStop,
          toStop,
          date,
          travellerPayload,
        );

        processedCombinations++;
        _updateProgress(
          processedCombinations,
          totalCombinations,
        );

        if (data != null) {
          segmentsData[key(j,i)] = data; // Store segment data for dp
        }
      }
    }

    // Dynamic programming to find cheapest path
    List<double> dp = List.filled(
      n,
      double.infinity,
    );
    dp[0] = 0;
    List<int> pathReconstruction = List.filled(n, -1);

    for (int i = 1; i < n; i++) {
      if (_isCancelled()) { // Check cancellation inside DP loop
        _addLog("Optimierung abgebrochen.");
        return TicketAnalysisResult(
          directPrice: directPrice,
          splitPrice: double.infinity,
          tickets: [],
        );
      }
      for (int j = 0; j < i; j++) {
        final segmentKey = key(j,i);
        if (segmentsData.containsKey(
          segmentKey,
        )) {
          final cost = dp[j] + segmentsData[segmentKey]!['price'];
          if (cost < dp[i]) {
            dp[i] = cost;
            pathReconstruction[i] = j;
          }
        }
      }
    }

    final cheapestSplitPrice = dp[n - 1];

    _addLog(
      "\n=== ERGEBNIS DER ANALYSE ===",
    );

    List<SplitTicket> splitTickets = [];

    if (cheapestSplitPrice < directPrice &&
        cheapestSplitPrice != double.infinity) {
      final savings = directPrice - cheapestSplitPrice;
      _addLog(
        "\n🎉 Günstigere Split-Ticket-Option gefunden! 🎉",
      );
      _addLog(
        "Direktpreis: $directPrice €",
      );
      _addLog(
        "Bester Split-Preis: $cheapestSplitPrice €",
      );
      _addLog(
        "💰 Ersparnis: $savings €",
      );

      List<Map<String, dynamic>> path = [];
      int current = n - 1;

      while (current > 0 && pathReconstruction[current] != -1) {
        if (_isCancelled()) { // Check cancellation during path reconstruction
          _addLog("Pfadrekonstruktion abgebrochen.");
          return TicketAnalysisResult(
            directPrice: directPrice,
            splitPrice: double.infinity,
            tickets: [],
          );
        }
        final prev = pathReconstruction[current];
        final segmentKey = key(prev,current);

        if (segmentsData.containsKey(
          segmentKey,
        )) {
          path.add(segmentsData[segmentKey]!);
        }

        current = prev;
      }

      path = path.reversed.toList();

      _addLog(
        "\nEmpfohlene Tickets zum Buchen:",
      );
      for (int i = 0; i < path.length; i++) {
        if (_isCancelled()) { // Check cancellation during ticket listing
          _addLog("Ticketauflistung abgebrochen.");
          return TicketAnalysisResult(
            directPrice: directPrice,
            splitPrice: double.infinity,
            tickets: [],
          );
        }
        final segment = path[i];
        _addLog(
          "Ticket ${i + 1}: Von ${segment['start_name']} nach ${segment['end_name']} für ${segment['price']} €",
        );

        final ticket = SplitTicket(
          from: segment['start_name'],
          to: segment['end_name'],
          price: segment['price'],
          fromId: segment['start_id'],
          toId: segment['end_id'],
          departureIso: segment['departure_iso'],
          coveredByDeutschlandTicket: segment['price'] == 0,
        );

        splitTickets.add(ticket);

        if (segment['price'] > 0) {
          final bookingLink = _travellerHelpers.generateBookingLink(
            ticket,
          );
          _addLog(
            "      -> Buchungslink: $bookingLink",
          );
        } else {
          _addLog(
            "      -> (Fahrt durch Deutschland-Ticket abgedeckt)",
          );
        }
      }

      return TicketAnalysisResult(
        directPrice: directPrice,
        splitPrice: cheapestSplitPrice,
        tickets: splitTickets,
      );
    } else {
      _addLog(
        "\nKeine günstigere Split-Option gefunden.",
      );
      _addLog(
        "Das Direktticket für $directPrice € ist die beste Option.",
      );

      return TicketAnalysisResult(
        directPrice: directPrice,
        splitPrice: double.infinity,
        tickets: [],
      );
    }
  }

  // Helper function to generate segment key
  String key(int j, int i) => "${j}_$i";
}