import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:besser_bahn/models/ticket_models.dart'; // Ensure this is correct
import 'package:besser_bahn/services/bahn_api_service.dart'; // Ensure this is correct
import 'package:besser_bahn/utils/split_ticket_logic.dart'; // Ensure this is correct
import 'package:besser_bahn/utils/traveller_helpers.dart'; // Ensure this is correct
import 'package:besser_bahn/home/home_options_card.dart'; // Ensure this is correct
import 'package:besser_bahn/home/home_sections.dart'; // Ensure this is correct

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _ageController = TextEditingController(text: "30");
  final TextEditingController _delayController = TextEditingController(
    text: "500",
  );
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  String _resultText = '';
  List<String> _logMessages = [];
  List<SplitTicket> _splitTickets = [];
  double _directPrice = 0;
  double _splitPrice = 0;
  bool _hasResult = false;
  bool _showLogs = false;
  bool _hasDeutschlandTicket = false;
  String? _selectedBahnCard;

  // New: Cancellation flag
  bool _isCancelled = false;

  // Progress tracking
  int _totalStations = 0;
  int _processedStations = 0;
  double _progress = 0.0;

  // BahnCard options (moved to state as it impacts payload)
  final List<Map<String, String?>> _bahnCardOptions = [
    {
      'value': null,
      'label': 'Keine BahnCard',
    },
    {
      'value': 'BC25_1',
      'label': 'BahnCard 25, 1. Klasse',
    },
    {
      'value': 'BC25_2',
      'label': 'BahnCard 25, 2. Klasse',
    },
    {
      'value': 'BC50_1',
      'label': 'BahnCard 50, 1. Klasse',
    },
    {
      'value': 'BC50_2',
      'label': 'BahnCard 50, 2. Klasse',
    },
  ];

  late BahnApiService _apiService;
  late TravellerHelpers _travellerHelpers;
  late SplitTicketLogic _splitTicketLogic;

  @override
  void initState() {
    super.initState();
    _initDependencies();
  }

  void _initDependencies() {
    // Pass the _isCancelled getter to services and logic
    _apiService = BahnApiService(
      _addLog,
      _hasDeutschlandTicket,
      _delayController.text, // Pass current delay value
      () => _isCancelled, // Getter for cancellation status
    );
    _travellerHelpers = TravellerHelpers(
      _selectedBahnCard,
      _hasDeutschlandTicket,
    );
    _splitTicketLogic = SplitTicketLogic(
      _addLog,
      _updateProgress,
      _apiService,
      _travellerHelpers,
      () => _isCancelled, // Getter for cancellation status
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    _ageController.dispose();
    _delayController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _addLog(String message) {
    // Ensure setState only runs if the widget is still mounted
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _processedStations = processed;
      _totalStations = total;
      _progress = total > 0
          ? processed / total
          : 0.0;
    });
  }

  // Helper to extract URL from a potentially longer text
  String _extractUrlFromString(String text) {
    final RegExp urlRegex = RegExp(
      r'https://www\.bahn\.de/[^\s]+',
    ); // Simple regex for Bahn.de URLs
    final match = urlRegex.firstMatch(text);
    return match?.group(0) ?? text; // Return matched URL or original text if no match
  }

  // Method to cancel the ongoing analysis
  void _cancelAnalysis() {
    if (!mounted) return;
    setState(() {
      _isCancelled = true;
      _isLoading = false; // Immediately stop showing loading state
      _resultText = 'Analyse abgebrochen.';
      _logMessages.add("Analyse wurde abgebrochen.");
      _progress = 0.0;
      _processedStations = 0;
      _totalStations = 0;
      _hasResult = false; // Clear previous results
      _splitTickets = []; // Clear previous tickets
      // Scroll to top to show cancel message clearly
      _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }


  Future<void> _analyzeUrl(
    String url,
  ) async {
    // Reset cancellation flag and dependencies at the start of a new analysis
    _isCancelled = false;
    _initDependencies(); // Re-initialize services with potentially updated values

    String processedUrl = _extractUrlFromString(url);

    if (processedUrl.isEmpty) {
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

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _resultText = 'Analysiere Verbindung...';
      _hasResult = false;
      _splitTickets = [];
      _logMessages = [];
      _progress = 0.0;
      _totalStations = 0;
      _processedStations = 0;
    });

    try {
      _addLog(
        "Starte Analyse für URL: $processedUrl",
      );

      // Check for cancellation before proceeding
      if (_isCancelled) return;

      final travellerPayload = _travellerHelpers.createTravellerPayload();
      final int age =
          int.tryParse(
            _ageController.text,
          ) ??
          30;

      _addLog(
        "Reisender: Alter $age" +
            (_selectedBahnCard != null
                ? ", mit $_selectedBahnCard"
                : ", ohne BahnCard") +
            (_hasDeutschlandTicket
                ? ", mit Deutschland-Ticket"
                : ", ohne Deutschland-Ticket"),
      );

      String urlToParse = processedUrl;
      if (processedUrl.contains(
        "/buchung/start",
      )) {
        final Uri uri = Uri.parse(processedUrl);
        final vbid = uri.queryParameters['vbid'];
        if (vbid != null) {
          urlToParse = "https://www.bahn.de?vbid=$vbid";
        }
      }

      final Uri uri = Uri.parse(
        urlToParse,
      );
      Map<String, dynamic> connectionData;
      // FIX: Initialize dateStr to prevent non-nullable error
      String dateStr = ''; 

      if (urlToParse.contains(
        'vbid=',
      )) {
        final String vbid = uri.queryParameters['vbid'] ?? '';
        _addLog("VBID erkannt: $vbid");
        connectionData = await _apiService.resolveVbidToConnection(
          vbid,
          travellerPayload,
        );

        if (connectionData.isEmpty) { // Also handle empty data from cancelled or failed API call
            throw Exception("Konnte keine Verbindungsdaten für VBID abrufen");
        }

        final firstStop = connectionData['verbindungen'][0]['verbindungsAbschnitte'][0]['halte'][0]['abfahrtsZeitpunkt'];
        dateStr = firstStop.split(
          'T',
        )[0];
      } else {
        _addLog(
          "Langer URL erkannt, extrahiere Parameter",
        );
        final Map<String, String> params = {};
        if (uri.fragment.isNotEmpty) {
          uri.fragment.split('&').forEach((element) {
            final parts = element.split('=');
            if (parts.length == 2) {
              params[parts[0]] = parts[1];
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

        final fromStationId = params['soid']!;
        final toStationId = params['zoid']!;
        final dateTimeStr = params['hd']!;
        final dateParts = dateTimeStr.split('T');
        dateStr = dateParts[0];
        final timeStr = dateParts[1];

        _addLog(
          "Von: $fromStationId, Nach: $toStationId, Datum: $dateStr, Zeit: $timeStr",
        );
        connectionData = await _apiService.getConnectionDetails(
          fromStationId,
          toStationId,
          dateStr,
          timeStr,
          travellerPayload,
        );
      }

      // Check for cancellation after API calls
      if (_isCancelled) return;

      if (connectionData.isEmpty ||
          !connectionData.containsKey(
            'verbindungen',
          ) ||
          connectionData['verbindungen'].isEmpty) {
        throw Exception(
          "Keine Verbindungsdaten gefunden",
        );
      }

      _addLog(
        "Verbindungsdaten erfolgreich abgerufen",
      );

      final firstConnection = connectionData['verbindungen'][0];
      final directPrice = firstConnection['angebotsPreis']?['betrag'];

      if (directPrice == null) {
        throw Exception(
          "Konnte den Direktpreis nicht ermitteln",
        );
      }

      final double directPriceDouble = directPrice is int
          ? directPrice.toDouble()
          : directPrice;

      _addLog(
        "Direktpreis gefunden: $directPriceDouble €",
      );

      List<Map<String, dynamic>> allStops = [];
      _addLog(
        "Extrahiere alle Haltestellen der Verbindung",
      );

      for (var section in firstConnection['verbindungsAbschnitte']) {
        if (_isCancelled) return; // Check cancellation during loop
        if (section['verkehrsmittel']['typ'] != 'WALK') {
          for (var halt in section['halte']) {
            if (_isCancelled) return; // Check cancellation during loop
            if (!allStops.any(
              (stop) =>
                  stop['id'] == halt['id'],
            )) {
              allStops.add({
                'name': halt['name'],
                'id': halt['id'],
                'departure_time':
                    halt['abfahrtsZeitpunkt']?.split(
                          'T',
                        )[1] ??
                    '',
                'arrival_time':
                    halt['ankunftsZeitpunkt']?.split(
                          'T',
                        )[1] ??
                    '',
                'departure_iso': halt['abfahrtsZeitpunkt'] ?? '',
              });
            }
          }
        }
      }

      if (allStops.isNotEmpty) {
        allStops.last['departure_time'] = allStops.last['arrival_time'];
      }

      _addLog(
        "${allStops.length} eindeutige Haltestellen gefunden:",
      );
      for (var stop in allStops) {
        _addLog("  - ${stop['name']}");
      }

      final result = await _splitTicketLogic.findCheapestSplit(
        allStops,
        dateStr,
        directPriceDouble,
        travellerPayload,
      );

      // Final check for cancellation before updating UI with results
      if (_isCancelled) return;

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasResult = true;
        _directPrice = directPriceDouble;
        _splitPrice = result.splitPrice;
        _splitTickets = result.tickets;

        if (_splitPrice < _directPrice) {
          _resultText = 'Günstigere Split-Ticket-Option gefunden!';
        } else {
          _resultText = 'Keine günstigere Split-Option gefunden.';
        }
      });
    } catch (e) {
      if (_isCancelled) {
        _addLog("Analyse abgebrochen (Fehler nach Abbruch ignoriert: $e)");
      } else {
        _addLog("Fehler: $e");
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _resultText = 'Fehler: $e';
        });
      }
    } finally {
      // Ensure isLoading is false if an error occurred or was cancelled
      if (!mounted) return;
      if (_isLoading && _isCancelled) {
         setState(() {
           _isLoading = false;
         });
      }
    }
  }

  Future<void> _launchUrl(
    SplitTicket ticket,
  ) async {
    final bookingLink = _travellerHelpers.generateBookingLink(ticket);
    final Uri uri = Uri.parse(bookingLink);
    if (!await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    )) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Konnte URL nicht öffnen: $bookingLink',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Besser Bahn',
        ),
        backgroundColor: Theme.of(
          context,
        ).colorScheme.primary,
        foregroundColor: Theme.of(
          context,
        ).colorScheme.onPrimary,
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        child: Padding(
          padding: const EdgeInsets.all(
            16.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: 'DB-Link einfügen',
                        hintText: 'https://www.bahn.de/buchung/start?vbid=...',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.clear,
                          ),
                          onPressed: () {
                            _urlController.clear();
                          },
                        ),
                      ),
                      keyboardType: TextInputType.url,
                      // Optional: If you want live extraction while typing, uncomment below
                      // onChanged: (value) {
                      //   final extracted = _extractUrlFromString(value);
                      //   if (extracted != value && extracted.isNotEmpty) {
                      //     _urlController.value = TextEditingValue(
                      //       text: extracted,
                      //       selection: TextSelection.collapsed(offset: extracted.length),
                      //     );
                      //   }
                      // },
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  IconButton(
                    onPressed: () async {
                      final data = await Clipboard.getData(
                        'text/plain',
                      );
                      if (data != null && data.text != null) {
                        final text = data.text!;
                        // Use extraction logic here
                        final extractedUrl = _extractUrlFromString(text);

                        if (extractedUrl.contains(
                          'bahn.de',
                        )) {
                          if (!mounted) return;
                          setState(() {
                            _urlController.text = extractedUrl;
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
                        } else {
                           if (!mounted) return;
                           ScaffoldMessenger.of(
                            context,
                           ).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Kein gültiger Bahn-Link gefunden',
                              ),
                            ),
                           );
                        }
                      }
                    },
                    icon: const Icon(
                      Icons.paste,
                    ),
                    tooltip: 'Aus Zwischenablage einfügen',
                  ),
                ],
              ),
              const SizedBox(
                height: 16,
              ),
              HomeOptionsCard(
                ageController: _ageController,
                delayController: _delayController,
                hasDeutschlandTicket: _hasDeutschlandTicket,
                onDeutschlandTicketChanged: (value) {
                  setState(() {
                    _hasDeutschlandTicket = value ?? false;
                  });
                },
                selectedBahnCard: _selectedBahnCard,
                onBahnCardChanged: (value) {
                  setState(() {
                    _selectedBahnCard = value;
                  });
                },
                bahnCardOptions: _bahnCardOptions,
              ),
              const SizedBox(
                height: 16,
              ),
              // Conditionally change button text and action
              ElevatedButton.icon(
                onPressed: _isLoading
                    ? _cancelAnalysis // If loading, allow cancellation
                    : () => _analyzeUrl(
                          _urlController.text,
                        ),
                icon: Icon(
                  _isLoading ? Icons.cancel : Icons.search,
                ),
                label: Text(
                  _isLoading
                      ? 'Abbrechen'
                      : 'Verbindung analysieren',
                ),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                  ),
                  backgroundColor: _isLoading
                      ? Theme.of(context).colorScheme.error // Red for cancel
                      : Theme.of(context).colorScheme.primary,
                  foregroundColor: _isLoading
                      ? Theme.of(context).colorScheme.onError
                      : Theme.of(context).colorScheme.onPrimary,
                ),
              ),
              const SizedBox(
                height: 16,
              ),
              AnalysisProgressIndicator(
                isLoading: _isLoading,
                progress: _progress,
                processedStations: _processedStations,
                totalStations: _totalStations,
              ),
              // Determine which section to show based on state
              if (_isLoading || _logMessages.isNotEmpty && !_hasResult)
                LogSection(
                  showLogs: _showLogs,
                  logMessages: _logMessages,
                  onToggleLogs: () {
                    setState(() {
                      _showLogs = !_showLogs;
                    });
                  },
                  hasResult: _hasResult,
                  resultText: _resultText,
                  directPrice: _directPrice,
                  splitPrice: _splitPrice,
                )
              else if (_hasResult)
                ResultsSection(
                  resultText: _resultText,
                  directPrice: _directPrice,
                  splitPrice: _splitPrice,
                  splitTickets: _splitTickets,
                  showLogs: _showLogs,
                  logMessages: _logMessages,
                  onToggleLogs: () {
                    setState(() {
                      _showLogs = !_showLogs;
                    });
                  },
                  onBookTicket: _launchUrl,
                )
              else
                const WelcomeMessage(),
            ],
          ),
        ),
      ),
    );
  }
}