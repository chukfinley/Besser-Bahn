import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async'; // For Future.delayed

class BahnApiService {
  final Function(String) _addLog;
  final bool _hasDeutschlandTicket;
  final String _delayMs;
  // New: Getter for cancellation status
  final bool Function() _isCancelled;

  BahnApiService(this._addLog, this._hasDeutschlandTicket, this._delayMs, this._isCancelled);

  static const _userAgent =
      "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36";

  Future<Map<String, dynamic>> resolveVbidToConnection(
    String vbid,
    List<Map<String, dynamic>> travellerPayload,
  ) async {
    if (_isCancelled()) return {}; // Check cancellation
    _addLog("Löse VBID '$vbid' auf...");
    try {
      final vbidUrl = "https://www.bahn.de/web/api/angebote/verbindung/$vbid";
      final headers = {
        "User-Agent": _userAgent,
        "Accept": "application/json",
      };

      final response = await http.get(
        Uri.parse(vbidUrl),
        headers: headers,
      );

      if (_isCancelled()) return {}; // Check cancellation

      if (response.statusCode != 200) {
        _addLog(
          "Fehler beim Abrufen der VBID-Daten: ${response.statusCode}",
        );
        return {};
      }

      final vbidData = json.decode(
        response.body,
      );
      final reconString = vbidData['hinfahrtRecon'];

      if (reconString == null) {
        _addLog(
          "Konnte keinen 'hinfahrtRecon' aus der VBID-Antwort extrahieren",
        );
        return {};
      }

      final reconUrl = "https://www.bahn.de/web/api/angebote/recon";
      final payload = {
        "klasse": "KLASSE_2",
        "reisende": travellerPayload,
        "ctxRecon": reconString,
        "deutschlandTicketVorhanden": _hasDeutschlandTicket,
      };

      final fullHeaders = {
        ...headers,
        "Content-Type": "application/json; charset=UTF-8",
      };

      _addLog(
        "Rufe vollständige Verbindungsdetails mit dem Recon-String ab...",
      );
      final reconResponse = await http.post(
        Uri.parse(reconUrl),
        headers: fullHeaders,
        body: json.encode(payload),
      );

      if (_isCancelled()) return {}; // Check cancellation

      if (reconResponse.statusCode == 201 || reconResponse.statusCode == 200) {
        _addLog(
          "Verbindungsdaten erfolgreich abgerufen (Status: ${reconResponse.statusCode})",
        );

        if (reconResponse.body.isNotEmpty) {
          try {
            return json.decode(
              reconResponse.body,
            );
          } catch (e) {
            _addLog(
              "Fehler beim Dekodieren der JSON-Antwort: $e",
            );
            if (reconResponse.statusCode == 201) {
              _addLog(
                "Status 201 erhalten, versuche erneuten Abruf der Verbindungsdaten...",
              );
              await Future.delayed(
                const Duration(
                  milliseconds: 1000,
                ),
              );
              if (_isCancelled()) return {}; // Check cancellation before retry
              final retryResponse = await http.post(
                Uri.parse(reconUrl),
                headers: fullHeaders,
                body: json.encode(
                  payload,
                ),
              );
              if (retryResponse.statusCode == 200) {
                return json.decode(
                  retryResponse.body,
                );
              } else {
                _addLog(
                  "Erneuter Abruf fehlgeschlagen: ${retryResponse.statusCode}",
                );
              }
            }
          }
        }
      } else {
        _addLog(
          "Fehler beim Abrufen der Recon-Daten: ${reconResponse.statusCode}",
        );
      }

      return {};
    } catch (e) {
      if (_isCancelled()) { // If cancelled, just return empty, don't log as error
        _addLog("VBID Auflösung abgebrochen.");
        return {};
      }
      _addLog(
        "Fehler beim Auflösen der VBID: $e",
      );
      return {};
    }
  }

  Future<Map<String, dynamic>> getConnectionDetails(
    String fromStationId,
    String toStationId,
    String date,
    String departureTime,
    List<Map<String, dynamic>> travellerPayload,
  ) async {
    if (_isCancelled()) return {}; // Check cancellation
    _addLog(
      "Rufe Verbindungsdetails ab für $fromStationId -> $toStationId am $date um $departureTime",
    );

    final url = "https://www.bahn.de/web/api/angebote/fahrplan";
    final payload = {
      "abfahrtsHalt": fromStationId,
      "anfrageZeitpunkt": "${date}T$departureTime",
      "ankunftsHalt": toStationId,
      "ankunftSuche": "ABFAHRT",
      "klasse": "KLASSE_2",
      "produktgattungen": [
        "ICE",
        "EC_IC",
        "IR",
        "REGIONAL",
        "SBAHN",
        "BUS",
        "SCHIFF",
        "UBAHN",
        "TRAM",
        "ANRUFPFLICHTIG",
      ],
      "reisende": travellerPayload,
      "schnelleVerbindungen": true,
      "deutschlandTicketVorhanden": _hasDeutschlandTicket,
    };

    final headers = {
      "User-Agent": _userAgent,
      "Accept": "application/json",
      "Content-Type": "application/json; charset=UTF-8",
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(payload),
      );

      if (_isCancelled()) return {}; // Check cancellation

      if (response.statusCode == 200 || response.statusCode == 201) {
        _addLog(
          "Verbindungsdetails erfolgreich abgerufen (Status: ${response.statusCode})",
        );

        if (response.body.isNotEmpty) {
          try {
            return json.decode(
              response.body,
            );
          } catch (e) {
            _addLog(
              "Fehler beim Dekodieren der JSON-Antwort: $e",
            );
            if (response.statusCode == 201) {
              _addLog(
                "Status 201 erhalten, versuche erneuten Abruf...",
              );
              await Future.delayed(
                const Duration(
                  milliseconds: 1000,
                ),
              );
              if (_isCancelled()) return {}; // Check cancellation before retry
              final retryResponse = await http.post(
                Uri.parse(url),
                headers: headers,
                body: json.encode(
                  payload,
                ),
              );
              if (retryResponse.statusCode == 200) {
                return json.decode(
                  retryResponse.body,
                );
              } else {
                _addLog(
                  "Erneuter Abruf fehlgeschlagen: ${retryResponse.statusCode}",
                );
              }
            }
          }
        }
      } else {
        _addLog(
          "Fehler beim Abrufen der Verbindungsdetails: ${response.statusCode}",
        );
      }

      return {};
    } catch (e) {
      if (_isCancelled()) { // If cancelled, just return empty, don't log as error
        _addLog("Verbindungsdetails abgebrochen.");
        return {};
      }
      _addLog(
        "Fehler beim Abrufen der Verbindungsdetails: $e",
      );
      return {};
    }
  }

  Future<Map<String, dynamic>?> getSegmentData(
    Map<String, dynamic> fromStop,
    Map<String, dynamic> toStop,
    String date,
    List<Map<String, dynamic>> travellerPayload,
  ) async {
    if (_isCancelled()) return null; // Check cancellation
    _addLog(
      "Frage Daten an für: ${fromStop['name']} -> ${toStop['name']}...",
    );

    final delayMs =
        int.tryParse(
          _delayMs,
        ) ??
        500;
    await Future.delayed(
      Duration(milliseconds: delayMs),
    ); // Rate limiting
    if (_isCancelled()) return null; // Check cancellation after delay

    final departureTimeStr = fromStop['departure_time'];
    if (departureTimeStr.isEmpty) {
      return null;
    }

    final connections = await getConnectionDetails(
      fromStop['id'],
      toStop['id'],
      date,
      departureTimeStr,
      travellerPayload,
    );

    if (_isCancelled()) return null; // Check cancellation

    if (connections.isNotEmpty &&
        connections.containsKey(
          'verbindungen',
        ) &&
        connections['verbindungen'].isNotEmpty) {
      final firstConnection = connections['verbindungen'][0];
      final price = firstConnection['angebotsPreis']?['betrag'];

      final departureIso =
          firstConnection['verbindungsAbschnitte']?[0]?['halte']?[0]?['abfahrtsZeitpunkt'];

      bool isCoveredByDTicket = false;
      if (_hasDeutschlandTicket) {
        for (var section
            in firstConnection['verbindungsAbschnitte'] ?? []) {
          if (_isCancelled()) return null; // Check cancellation during loop
          final attributes = section['verkehrsmittel']?['zugattribute'] ?? [];
          for (var attr in attributes) {
            if (_isCancelled()) return null; // Check cancellation during loop
            if (attr['key'] == '9G') {
              isCoveredByDTicket = true;
              break;
            }
          }
          if (isCoveredByDTicket) break;
        }
      }

      double finalPrice;
      if (isCoveredByDTicket) {
        _addLog(
          " -> Deutschland-Ticket gültig! Preis wird auf 0.00 € gesetzt.",
        );
        finalPrice = 0.0;
      } else if (price != null) {
        finalPrice = price is int
            ? price.toDouble()
            : price;
        _addLog(
          " -> Preis gefunden: $finalPrice €",
        );
      } else {
        _addLog(
          " -> Kein Preis für dieses Segment verfügbar.",
        );
        return null;
      }

      if (departureIso != null) {
        return {
          "price": finalPrice,
          "start_name": fromStop['name'],
          "end_name": toStop['name'],
          "start_id": fromStop['id'],
          "end_id": toStop['id'],
          "departure_iso": departureIso,
        };
      }
    }

    _addLog(
      " -> Keine Verbindungsdaten erhalten.",
    );
    return null;
  }
}