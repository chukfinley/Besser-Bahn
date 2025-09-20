import 'package:flutter/material.dart';

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