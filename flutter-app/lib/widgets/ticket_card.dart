import 'package:flutter/material.dart';
import 'package:besser_bahn/models/ticket_models.dart'; // Import models

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