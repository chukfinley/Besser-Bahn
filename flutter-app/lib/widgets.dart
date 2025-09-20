import 'package:flutter/material.dart';
import 'models.dart'; // Import the new models.dart

class LogConsole extends StatelessWidget {
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Log:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 2,
                    ),
                    child: Text(
                      messages[index],
                      style: const TextStyle(
                        fontFamily: 'monospace',
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

class PriceComparison extends StatelessWidget {
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
    final bool hasBetterOption = savings > 0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Direktpreis:'),
            Text(
              '${directPrice.toStringAsFixed(2)} €',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Split-Ticket-Preis:',
            ),
            Text(
              splitPrice == double.infinity
                  ? 'N/A'
                  : '${splitPrice.toStringAsFixed(2)} €',
              style: TextStyle(
                fontWeight: FontWeight.bold,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Deine Ersparnis:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${savings.toStringAsFixed(2)} €',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
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

class TicketCard extends StatelessWidget {
  final SplitTicket ticket;
  final int index;
  final VoidCallback? onBookPressed;

  const TicketCard({
    super.key,
    required this.ticket,
    required this.index,
    this.onBookPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(
        vertical: 8,
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          12.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  child: Text('$index'),
                ),
                const SizedBox(
                  width: 8,
                ),
                Text(
                  'Ticket $index',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${ticket.price.toStringAsFixed(2)} €',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
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
                    style: const TextStyle(
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            if (ticket.coveredByDeutschlandTicket) ...[
              const SizedBox(height: 8),
              const Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.green,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Mit Deutschland-Ticket abgedeckt',
                    style: TextStyle(
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(
                height: 12,
              ),
              ElevatedButton.icon(
                onPressed: onBookPressed,
                icon: const Icon(
                  Icons.shopping_cart,
                ),
                label: const Text(
                  'Ticket buchen',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}