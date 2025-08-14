import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const SplitTicketApp());
}

class SplitTicketApp
    extends StatelessWidget {
  const SplitTicketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Better Bahn',
      debugShowCheckedModeBanner:
          false, // Remove debug banner
      theme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(
                0xFFEC0016,
              ), // DB Red
              brightness:
                  Brightness.light,
            ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(
                0xFFEC0016,
              ), // DB Red
              brightness:
                  Brightness.dark,
            ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() =>
      _HomePageState();
}

class _HomePageState
    extends State<HomePage> {
  final TextEditingController
  _urlController =
      TextEditingController();
  bool _isLoading = false;
  String _resultText = '';
  List<String> _logMessages = [];
  List<SplitTicket> _splitTickets = [];
  double _directPrice = 0;
  double _splitPrice = 0;
  bool _hasResult = false;
  bool _showLogs = false;

  // Progress tracking
  int _totalStations = 0;
  int _processedStations = 0;
  double _progress = 0.0;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add(message);
      if (_logMessages.length > 100) {
        _logMessages.removeAt(0);
      }
    });
    debugPrint(message);
  }

  void _updateProgress(
    int processed,
    int total,
  ) {
    setState(() {
      _processedStations = processed;
      _totalStations = total;
      _progress = total > 0
          ? processed / total
          : 0.0;
    });
  }

  Future<void> _analyzeUrl(
    String url,
  ) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitte gib einen DB-Link ein',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _resultText =
          'Analysiere Verbindung...';
      _hasResult = false;
      _splitTickets = [];
      _logMessages = [];
      _progress = 0.0;
      _totalStations = 0;
      _processedStations = 0;
    });

    try {
      _addLog(
        "Starte Analyse für URL: $url",
      );

      // Parse URL to extract vbid or station IDs
      final Uri uri = Uri.parse(url);
      Map<String, dynamic>
      connectionData;
      String dateStr;

      if (url.contains('vbid=')) {
        // Handle short URL with vbid
        final String vbid =
            uri.queryParameters['vbid'] ??
            '';
        _addLog("VBID erkannt: $vbid");
        connectionData =
            await _resolveVbidToConnection(
              vbid,
            );

        if (connectionData.isEmpty) {
          throw Exception(
            "Konnte keine Verbindungsdaten für VBID abrufen",
          );
        }

        final firstStop =
            connectionData['verbindungen'][0]['verbindungsAbschnitte'][0]['halte'][0]['abfahrtsZeitpunkt'];
        dateStr = firstStop.split(
          'T',
        )[0];
      } else {
        // Handle long URL with fragment parameters
        _addLog(
          "Langer URL erkannt, extrahiere Parameter",
        );
        final Map<String, String>
        params = {};
        if (uri.fragment.isNotEmpty) {
          uri.fragment
              .split('&')
              .forEach((element) {
                final parts = element
                    .split('=');
                if (parts.length == 2) {
                  params[parts[0]] =
                      parts[1];
                }
              });
        }

        if (!params.containsKey(
              'soid',
            ) ||
            !params.containsKey(
              'zoid',
            ) ||
            !params.containsKey('hd')) {
          throw Exception(
            "URL enthält nicht alle benötigten Parameter",
          );
        }

        final fromStationId =
            params['soid']!;
        final toStationId =
            params['zoid']!;
        final dateTimeStr =
            params['hd']!;
        final dateParts = dateTimeStr
            .split('T');
        dateStr = dateParts[0];
        final timeStr = dateParts[1];

        _addLog(
          "Von: $fromStationId, Nach: $toStationId, Datum: $dateStr, Zeit: $timeStr",
        );
        connectionData =
            await _getConnectionDetails(
              fromStationId,
              toStationId,
              dateStr,
              timeStr,
            );
      }

      if (connectionData.isEmpty ||
          !connectionData.containsKey(
            'verbindungen',
          ) ||
          connectionData['verbindungen']
              .isEmpty) {
        throw Exception(
          "Keine Verbindungsdaten gefunden",
        );
      }

      _addLog(
        "Verbindungsdaten erfolgreich abgerufen",
      );

      // Extract direct price
      final firstConnection =
          connectionData['verbindungen'][0];
      final directPrice =
          firstConnection['angebotsPreis']?['betrag'];

      if (directPrice == null) {
        throw Exception(
          "Konnte den Direktpreis nicht ermitteln",
        );
      }

      // Convert to double explicitly
      final double directPriceDouble =
          directPrice is int
          ? directPrice.toDouble()
          : directPrice;

      _addLog(
        "Direktpreis gefunden: $directPriceDouble €",
      );

      // Extract all stops
      List<Map<String, dynamic>>
      allStops = [];
      _addLog(
        "Extrahiere alle Haltestellen der Verbindung",
      );

      for (var section
          in firstConnection['verbindungsAbschnitte']) {
        if (section['verkehrsmittel']['typ'] !=
            'WALK') {
          for (var halt
              in section['halte']) {
            if (!allStops.any(
              (stop) =>
                  stop['id'] ==
                  halt['id'],
            )) {
              allStops.add({
                'name': halt['name'],
                'id': halt['id'],
                'departure_time':
                    halt['abfahrtsZeitpunkt']
                        ?.split(
                          'T',
                        )[1] ??
                    '',
                'arrival_time':
                    halt['ankunftsZeitpunkt']
                        ?.split(
                          'T',
                        )[1] ??
                    '',
              });
            }
          }
        }
      }

      if (allStops.isNotEmpty) {
        allStops.last['departure_time'] =
            allStops
                .last['arrival_time'];
      }

      _addLog(
        "${allStops.length} eindeutige Haltestellen gefunden:",
      );
      for (var stop in allStops) {
        _addLog("  - ${stop['name']}");
      }

      // Find cheapest split
      final result =
          await _findCheapestSplit(
            allStops,
            dateStr,
            directPriceDouble,
          );

      setState(() {
        _isLoading = false;
        _hasResult = true;
        _directPrice =
            directPriceDouble;
        _splitPrice = result.splitPrice;
        _splitTickets = result.tickets;

        if (_splitPrice <
            _directPrice) {
          _resultText =
              'Günstigere Split-Ticket-Option gefunden!';
        } else {
          _resultText =
              'Keine günstigere Split-Option gefunden.';
        }
      });
    } catch (e) {
      _addLog("Fehler: $e");
      setState(() {
        _isLoading = false;
        _resultText = 'Fehler: $e';
      });
    }
  }

  Future<Map<String, dynamic>>
  _resolveVbidToConnection(
    String vbid,
  ) async {
    _addLog("Löse VBID '$vbid' auf...");
    try {
      // Step 1: Get the 'recon' string from the vbid endpoint
      final vbidUrl =
          "https://www.bahn.de/web/api/angebote/verbindung/$vbid";
      final headers = {
        "User-Agent":
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
        "Accept": "application/json",
      };

      final response = await http.get(
        Uri.parse(vbidUrl),
        headers: headers,
      );

      if (response.statusCode != 200) {
        _addLog(
          "Fehler beim Abrufen der VBID-Daten: ${response.statusCode}",
        );
        return {};
      }

      final vbidData = json.decode(
        response.body,
      );
      final reconString =
          vbidData['hinfahrtRecon'];

      if (reconString == null) {
        _addLog(
          "Konnte keinen 'hinfahrtRecon' aus der VBID-Antwort extrahieren",
        );
        return {};
      }

      // Step 2: Use the 'recon' string to get the full connection data
      final reconUrl =
          "https://www.bahn.de/web/api/angebote/recon";
      final payload = {
        "klasse": "KLASSE_2",
        "reisende": [
          {
            "typ": "ERWACHSENER",
            "ermaessigungen": [
              {
                "art":
                    "KEINE_ERMAESSIGUNG",
                "klasse": "KLASSENLOS",
              },
            ],
            "anzahl": 1,
            "alter": [],
          },
        ],
        "ctxRecon": reconString,
      };

      final fullHeaders = {
        ...headers,
        "Content-Type":
            "application/json; charset=UTF-8",
      };

      _addLog(
        "Rufe vollständige Verbindungsdetails mit dem Recon-String ab...",
      );
      final reconResponse = await http
          .post(
            Uri.parse(reconUrl),
            headers: fullHeaders,
            body: json.encode(payload),
          );

      // Accept 201 status code as success (Created)
      if (reconResponse.statusCode ==
              201 ||
          reconResponse.statusCode ==
              200) {
        _addLog(
          "Verbindungsdaten erfolgreich abgerufen (Status: ${reconResponse.statusCode})",
        );

        // Check if the response body is not empty
        if (reconResponse
            .body
            .isNotEmpty) {
          try {
            return json.decode(
              reconResponse.body,
            );
          } catch (e) {
            _addLog(
              "Fehler beim Dekodieren der JSON-Antwort: $e",
            );

            // For 201 responses, we might need to make a follow-up request
            if (reconResponse
                    .statusCode ==
                201) {
              _addLog(
                "Status 201 erhalten, versuche erneuten Abruf der Verbindungsdaten...",
              );

              // Wait a moment before retrying
              await Future.delayed(
                const Duration(
                  milliseconds: 500,
                ),
              );

              // Make a new request to get the connection data
              final retryResponse =
                  await http.post(
                    Uri.parse(reconUrl),
                    headers:
                        fullHeaders,
                    body: json.encode(
                      payload,
                    ),
                  );

              if (retryResponse
                      .statusCode ==
                  200) {
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
      _addLog(
        "Fehler beim Auflösen der VBID: $e",
      );
      return {};
    }
  }

  Future<Map<String, dynamic>>
  _getConnectionDetails(
    String fromStationId,
    String toStationId,
    String date,
    String departureTime,
  ) async {
    _addLog(
      "Rufe Verbindungsdetails ab für $fromStationId -> $toStationId am $date um $departureTime",
    );

    final url =
        "https://www.bahn.de/web/api/angebote/fahrplan";
    final payload = {
      "abfahrtsHalt": fromStationId,
      "anfrageZeitpunkt":
          "${date}T$departureTime",
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
      "reisende": [
        {
          "typ": "ERWACHSENER",
          "ermaessigungen": [
            {
              "art":
                  "KEINE_ERMAESSIGUNG",
              "klasse": "KLASSENLOS",
            },
          ],
          "anzahl": 1,
          "alter": [],
        },
      ],
      "schnelleVerbindungen": true,
    };

    final headers = {
      "User-Agent":
          "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Accept": "application/json",
      "Content-Type":
          "application/json; charset=UTF-8",
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: headers,
        body: json.encode(payload),
      );

      // Accept both 200 and 201 status codes
      if (response.statusCode == 200 ||
          response.statusCode == 201) {
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

            // For 201 responses, we might need to make a follow-up request
            if (response.statusCode ==
                201) {
              _addLog(
                "Status 201 erhalten, versuche erneuten Abruf...",
              );

              // Wait a moment before retrying
              await Future.delayed(
                const Duration(
                  milliseconds: 500,
                ),
              );

              // Make a new request
              final retryResponse =
                  await http.post(
                    Uri.parse(url),
                    headers: headers,
                    body: json.encode(
                      payload,
                    ),
                  );

              if (retryResponse
                      .statusCode ==
                  200) {
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
      _addLog(
        "Fehler beim Abrufen der Verbindungsdetails: $e",
      );
      return {};
    }
  }

  Future<double?> _getPriceForSegment(
    String fromId,
    String toId,
    String date,
    String departureTime,
  ) async {
    _addLog(
      "Frage Preis an für: $fromId -> $toId am $date um $departureTime",
    );

    await Future.delayed(
      const Duration(milliseconds: 500),
    ); // Rate limiting

    final connections =
        await _getConnectionDetails(
          fromId,
          toId,
          date,
          departureTime,
        );

    if (connections.isNotEmpty &&
        connections.containsKey(
          'verbindungen',
        ) &&
        connections['verbindungen']
            .isNotEmpty) {
      final firstConnection =
          connections['verbindungen'][0];
      if (firstConnection.containsKey(
        'angebotsPreis',
      )) {
        final price =
            firstConnection['angebotsPreis']['betrag'];
        _addLog(
          "Preis gefunden: $price €",
        );

        // Convert to double explicitly, handling both int and double cases
        return price is int
            ? price.toDouble()
            : price;
      }
    }

    _addLog(
      "Kein Preis für dieses Segment verfügbar",
    );
    return null;
  }

  Future<TicketAnalysisResult>
  _findCheapestSplit(
    List<Map<String, dynamic>> stops,
    String date,
    double directPrice,
  ) async {
    final int n = stops.length;
    final Map<String, double> prices =
        {};

    _addLog(
      "\n--- Preise für alle möglichen Teilstrecken werden abgerufen ---",
    );

    // Calculate total number of combinations to check
    int totalCombinations = 0;
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        if (stops[i]['departure_time']
            .isNotEmpty) {
          totalCombinations++;
        }
      }
    }

    _updateProgress(
      0,
      totalCombinations,
    );
    int processedCombinations = 0;

    // Get prices for all possible segments
    for (int i = 0; i < n; i++) {
      for (int j = i + 1; j < n; j++) {
        final fromStop = stops[i];
        final toStop = stops[j];
        final departureTimeStr =
            fromStop['departure_time'];

        if (departureTimeStr.isEmpty) {
          continue;
        }

        _addLog(
          "Frage Preis an für: ${fromStop['name']} -> ${toStop['name']}...",
        );
        final price =
            await _getPriceForSegment(
              fromStop['id'],
              toStop['id'],
              date,
              departureTimeStr,
            );

        // Update progress
        processedCombinations++;
        _updateProgress(
          processedCombinations,
          totalCombinations,
        );

        if (price != null) {
          final key = "${i}_$j";
          prices[key] =
              price; // This should now be a double from _getPriceForSegment
          _addLog(
            "Preis gefunden: $price €",
          );
        } else {
          _addLog(
            "Kein Preis für dieses Segment verfügbar",
          );
        }
      }
    }

    // Dynamic programming to find cheapest path
    List<double> dp = List.filled(
      n,
      double.infinity,
    );
    dp[0] = 0;
    List<int> pathReconstruction =
        List.filled(n, -1);

    for (int i = 1; i < n; i++) {
      for (int j = 0; j < i; j++) {
        final key = "${j}_$i";
        if (prices.containsKey(key)) {
          final cost =
              dp[j] + prices[key]!;
          if (cost < dp[i]) {
            dp[i] = cost;
            pathReconstruction[i] = j;
          }
        }
      }
    }

    final cheapestSplitPrice =
        dp[n - 1];

    _addLog(
      "\n=== ERGEBNIS DER ANALYSE ===",
    );

    List<SplitTicket> splitTickets = [];

    if (cheapestSplitPrice <
            directPrice &&
        cheapestSplitPrice !=
            double.infinity) {
      final savings =
          directPrice -
          cheapestSplitPrice;
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

      List<Map<String, dynamic>> path =
          [];
      int current = n - 1;

      while (current > 0 &&
          pathReconstruction[current] !=
              -1) {
        final prev =
            pathReconstruction[current];
        final key = "${prev}_$current";

        path.add({
          "from": stops[prev]['name'],
          "to": stops[current]['name'],
          "price": prices[key] ?? 0,
          "fromId": stops[prev]['id'],
          "toId": stops[current]['id'],
        });

        current = prev;
      }

      path = path.reversed.toList();

      _addLog(
        "\nEmpfohlene Tickets zum Buchen:",
      );
      for (
        int i = 0;
        i < path.length;
        i++
      ) {
        final segment = path[i];
        _addLog(
          "Ticket ${i + 1}: Von ${segment['from']} nach ${segment['to']} für ${segment['price']} €",
        );

        // Ensure price is a double when creating SplitTicket
        final double ticketPrice =
            segment['price'] is int
            ? segment['price']
                  .toDouble()
            : segment['price'];

        splitTickets.add(
          SplitTicket(
            from: segment['from'],
            to: segment['to'],
            price: ticketPrice,
            fromId: segment['fromId'],
            toId: segment['toId'],
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Better Bahn',
        ),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary,
        foregroundColor: Theme.of(
          context,
        ).colorScheme.onPrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(
          16.0,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment
                  .stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller:
                        _urlController,
                    decoration: InputDecoration(
                      labelText:
                          'DB-Link einfügen',
                      hintText:
                          'https://www.bahn.de/buchung/start?vbid=...',
                      border:
                          const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.clear,
                        ),
                        onPressed: () {
                          _urlController
                              .clear();
                        },
                      ),
                    ),
                    keyboardType:
                        TextInputType
                            .url,
                  ),
                ),
                const SizedBox(
                  width: 8,
                ),
                IconButton(
                  onPressed: () async {
                    final data =
                        await Clipboard.getData(
                          'text/plain',
                        );
                    if (data != null &&
                        data.text !=
                            null) {
                      final text =
                          data.text!;
                      if (text.contains(
                        'bahn.de',
                      )) {
                        setState(() {
                          _urlController
                                  .text =
                              text;
                        });
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Link aus Zwischenablage eingefügt',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.paste,
                  ),
                  tooltip:
                      'Aus Zwischenablage einfügen',
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _analyzeUrl(
                      _urlController
                          .text,
                    ),
              icon: const Icon(
                Icons.search,
              ),
              label: const Text(
                'Verbindung analysieren',
              ),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(
                      vertical: 12,
                    ),
              ),
            ),
            const SizedBox(height: 16),

            // Progress indicator during loading
            if (_isLoading) ...[
              Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(
                          value:
                              _progress >
                                  0
                              ? _progress
                              : null,
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Text(
                        '$_processedStations/$_totalStations (${(_progress * 100).toInt()}%)',
                        style:
                            const TextStyle(
                              fontSize:
                                  12,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Suche nach günstigeren Split-Tickets...',
                    style:
                        const TextStyle(
                          fontSize: 14,
                        ),
                  ),
                ],
              ),
              const SizedBox(
                height: 16,
              ),
            ],

            // Results or welcome message
            Expanded(
              child: _isLoading
                  ? _buildLogsSection()
                  : _hasResult
                  ? _buildResultsSection()
                  : _logMessages
                        .isNotEmpty
                  ? _buildLogsSection()
                  : const Center(
                      child: Text(
                        'Füge einen DB-Link ein, um günstigere Split-Ticket-Optionen zu finden.\n\n'
                        'Unterstützte Links:\n'
                        '• Kurze Links: https://www.bahn.de/buchung/start?vbid=...\n'
                        '• Lange Links: https://www.bahn.de/...',
                        textAlign:
                            TextAlign
                                .center,
                        style: TextStyle(
                          color: Colors
                              .grey,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsSection() {
    return Column(
      children: [
        // Collapsible logs section
        InkWell(
          onTap: () {
            setState(() {
              _showLogs = !_showLogs;
            });
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant,
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
            ),
            child: Row(
              children: [
                Icon(
                  _showLogs
                      ? Icons
                            .keyboard_arrow_up
                      : Icons
                            .keyboard_arrow_down,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'Logs anzeigen/ausblenden',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Logs content (collapsible)
        if (_showLogs)
          Expanded(
            child: LogConsole(
              messages: _logMessages,
            ),
          ),

        // If we have results and logs are shown, show a compact result
        if (_hasResult && _showLogs)
          Card(
            margin:
                const EdgeInsets.only(
                  top: 8,
                ),
            child: Padding(
              padding:
                  const EdgeInsets.all(
                    12,
                  ),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment
                        .start,
                children: [
                  Text(
                    _resultText,
                    style:
                        const TextStyle(
                          fontWeight:
                              FontWeight
                                  .bold,
                          fontSize: 16,
                        ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Direktpreis: ${_directPrice.toStringAsFixed(2)} €',
                  ),
                  if (_splitPrice <
                      _directPrice)
                    Text(
                      'Split-Preis: ${_splitPrice.toStringAsFixed(2)} € (Ersparnis: ${(_directPrice - _splitPrice).toStringAsFixed(2)} €)',
                      style: const TextStyle(
                        color: Colors
                            .green,
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildResultsSection() {
    return Column(
      children: [
        // Result summary card
        Card(
          elevation: 4,
          child: Padding(
            padding:
                const EdgeInsets.all(
                  16.0,
                ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Row(
                  children: [
                    Icon(
                      _splitPrice <
                              _directPrice
                          ? Icons
                                .check_circle
                          : Icons.info,
                      color:
                          _splitPrice <
                              _directPrice
                          ? Colors.green
                          : Colors
                                .orange,
                      size: 28,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: Text(
                        _resultText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(
                  height: 24,
                ),
                PriceComparison(
                  directPrice:
                      _directPrice,
                  splitPrice:
                      _splitPrice,
                  savings:
                      _directPrice -
                      _splitPrice,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Logs toggle
        InkWell(
          onTap: () {
            setState(() {
              _showLogs = !_showLogs;
            });
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant,
              borderRadius:
                  BorderRadius.circular(
                    8,
                  ),
            ),
            child: Row(
              children: [
                Icon(
                  _showLogs
                      ? Icons
                            .keyboard_arrow_up
                      : Icons
                            .keyboard_arrow_down,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'Logs anzeigen/ausblenden',
                  style: TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Either show logs or tickets
        Expanded(
          child: _showLogs
              ? LogConsole(
                  messages:
                      _logMessages,
                )
              : _splitPrice <
                    _directPrice
              ? Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Text(
                      'Empfohlene Tickets:',
                      style: TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount:
                            _splitTickets
                                .length,
                        itemBuilder: (context, index) {
                          final ticket =
                              _splitTickets[index];
                          return TicketCard(
                            ticket:
                                ticket,
                            index:
                                index +
                                1,
                          );
                        },
                      ),
                    ),
                  ],
                )
              : const Center(
                  child: Text(
                    'Das Direktticket ist die günstigste Option.',
                    style: TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class LogConsole
    extends StatelessWidget {
  final List<String> messages;

  const LogConsole({
    super.key,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          8.0,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Log:',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount:
                    messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(
                          vertical: 2,
                        ),
                    child: Text(
                      messages[index],
                      style: const TextStyle(
                        fontFamily:
                            'monospace',
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PriceComparison
    extends StatelessWidget {
  final double directPrice;
  final double splitPrice;
  final double savings;

  const PriceComparison({
    super.key,
    required this.directPrice,
    required this.splitPrice,
    required this.savings,
  });

  @override
  Widget build(BuildContext context) {
    final bool hasBetterOption =
        savings > 0;

    return Column(
      children: [
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            const Text('Direktpreis:'),
            Text(
              '${directPrice.toStringAsFixed(2)} €',
              style: const TextStyle(
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment:
              MainAxisAlignment
                  .spaceBetween,
          children: [
            const Text(
              'Split-Ticket-Preis:',
            ),
            Text(
              splitPrice ==
                      double.infinity
                  ? 'N/A'
                  : '${splitPrice.toStringAsFixed(2)} €',
              style: TextStyle(
                fontWeight:
                    FontWeight.bold,
                color: hasBetterOption
                    ? Colors.green
                    : Colors.grey,
              ),
            ),
          ],
        ),
        if (hasBetterOption) ...[
          const Divider(height: 16),
          Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              const Text(
                'Deine Ersparnis:',
                style: TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              Text(
                '${savings.toStringAsFixed(2)} €',
                style: const TextStyle(
                  fontWeight:
                      FontWeight.bold,
                  color: Colors.green,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class TicketCard
    extends StatelessWidget {
  final SplitTicket ticket;
  final int index;

  const TicketCard({
    super.key,
    required this.ticket,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin:
          const EdgeInsets.symmetric(
            vertical: 8,
          ),
      child: Padding(
        padding: const EdgeInsets.all(
          12.0,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      Theme.of(context)
                          .colorScheme
                          .primary,
                  foregroundColor:
                      Theme.of(context)
                          .colorScheme
                          .onPrimary,
                  child: Text('$index'),
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  'Ticket $index',
                  style:
                      const TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                ),
                const Spacer(),
                Text(
                  '${ticket.price.toStringAsFixed(2)} €',
                  style:
                      const TextStyle(
                        fontWeight:
                            FontWeight
                                .bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.train,
                  size: 16,
                ),
                const SizedBox(
                  width: 8,
                ),
                Expanded(
                  child: Text(
                    '${ticket.from} → ${ticket.to}',
                    style:
                        const TextStyle(
                          fontSize: 16,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SplitTicket {
  final String from;
  final String to;
  final double price;
  final String fromId;
  final String toId;

  SplitTicket({
    required this.from,
    required this.to,
    required this.price,
    required this.fromId,
    required this.toId,
  });
}

class TicketAnalysisResult {
  final double directPrice;
  final double splitPrice;
  final List<SplitTicket> tickets;

  TicketAnalysisResult({
    required this.directPrice,
    required this.splitPrice,
    required this.tickets,
  });
}
