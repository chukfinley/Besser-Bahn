import 'package:flutter/material.dart';
import 'package:besser_bahn/models/ticket_models.dart';
import 'package:besser_bahn/widgets/log_console.dart';
import 'package:besser_bahn/widgets/price_comparison.dart';
import 'package:besser_bahn/widgets/ticket_card.dart';

// --- Shared UI Components/Sections ---

class AnalysisProgressIndicator extends StatelessWidget {
  final bool isLoading;
  final double progress;
  final int processedStations;
  final int totalStations;

  const AnalysisProgressIndicator({
    super.key,
    required this.isLoading,
    required this.progress,
    required this.processedStations,
    required this.totalStations,
  });

  @override
  Widget build(BuildContext context) {
    if (!isLoading) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: LinearProgressIndicator(
                value: progress > 0
                    ? progress
                    : null,
              ),
            ),
            const SizedBox(
              width: 8,
            ),
            Text(
              '$processedStations/$totalStations (${(progress * 100).toInt()}%)',
              style: const TextStyle(
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 8,
        ),
        const Text(
          'Suche nach günstigeren Split-Tickets...',
          style: TextStyle(
            fontSize: 14,
          ),
        ),
        const SizedBox(
          height: 16,
        ),
      ],
    );
  }
}

class WelcomeMessage extends StatelessWidget {
  const WelcomeMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(
          32.0,
        ),
        child: Text(
          'Füge einen DB-Link ein, um günstigere Split-Ticket-Optionen zu finden.\n\n'
          'Unterstützte Links:\n'
          '• Kurze Links: https://www.bahn.de/buchung/start?vbid=...\n'
          '• Lange Links: https://www.bahn.de/...',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}

class LogSection extends StatelessWidget {
  final bool showLogs;
  final List<String> logMessages;
  final VoidCallback onToggleLogs;
  final bool hasResult;
  final String resultText;
  final double directPrice;
  final double splitPrice;

  const LogSection({
    super.key,
    required this.showLogs,
    required this.logMessages,
    required this.onToggleLogs,
    required this.hasResult,
    required this.resultText,
    required this.directPrice,
    required this.splitPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggleLogs,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(
                8,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  showLogs
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'Logs anzeigen/ausblenden',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (showLogs)
          SizedBox(
            height: 300,
            child: LogConsole(
              messages: logMessages,
            ),
          ),
        if (hasResult && showLogs)
          Card(
            margin: const EdgeInsets.only(
              top: 8,
            ),
            child: Padding(
              padding: const EdgeInsets.all(
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resultText,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(
                    height: 8,
                  ),
                  Text(
                    'Direktpreis: ${directPrice.toStringAsFixed(2)} €',
                  ),
                  if (splitPrice < directPrice)
                    Text(
                      'Split-Preis: ${splitPrice.toStringAsFixed(2)} € (Ersparnis: ${(directPrice - splitPrice).toStringAsFixed(2)} €)',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class ResultsSection extends StatelessWidget {
  final String resultText;
  final double directPrice;
  final double splitPrice;
  final List<SplitTicket> splitTickets;
  final bool showLogs;
  final List<String> logMessages;
  final VoidCallback onToggleLogs;
  final void Function(SplitTicket) onBookTicket;

  const ResultsSection({
    super.key,
    required this.resultText,
    required this.directPrice,
    required this.splitPrice,
    required this.splitTickets,
    required this.showLogs,
    required this.logMessages,
    required this.onToggleLogs,
    required this.onBookTicket,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(
              16.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      splitPrice < directPrice
                          ? Icons.check_circle
                          : Icons.info,
                      color: splitPrice < directPrice
                          ? Colors.green
                          : Colors.orange,
                      size: 28,
                    ),
                    const SizedBox(
                      width: 8,
                    ),
                    Expanded(
                      child: Text(
                        resultText,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(
                  height: 24,
                ),
                PriceComparison(
                  directPrice: directPrice,
                  splitPrice: splitPrice,
                  savings: directPrice - splitPrice,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: onToggleLogs,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 12,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant,
              borderRadius: BorderRadius.circular(
                8,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  showLogs
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Text(
                  'Logs anzeigen/ausblenden',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        showLogs
            ? SizedBox(
                height: 300,
                child: LogConsole(
                  messages: logMessages,
                ),
              )
            : splitPrice < directPrice
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Empfohlene Tickets:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: splitTickets.length,
                        itemBuilder: (context, index) {
                          final ticket = splitTickets[index];
                          return TicketCard(
                            ticket: ticket,
                            index: index + 1,
                            onBookPressed: () => onBookTicket(ticket),
                          );
                        },
                      ),
                    ],
                  )
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(
                        32.0,
                      ),
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