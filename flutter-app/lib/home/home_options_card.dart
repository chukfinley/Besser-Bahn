import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeOptionsCard extends StatelessWidget {
  final TextEditingController ageController;
  final TextEditingController delayController;
  final bool hasDeutschlandTicket;
  final ValueChanged<bool?> onDeutschlandTicketChanged;
  final String? selectedBahnCard;
  final ValueChanged<String?> onBahnCardChanged;
  final List<Map<String, String?>> bahnCardOptions;

  const HomeOptionsCard({
    super.key,
    required this.ageController,
    required this.delayController,
    required this.hasDeutschlandTicket,
    required this.onDeutschlandTicketChanged,
    required this.selectedBahnCard,
    required this.onBahnCardChanged,
    required this.bahnCardOptions,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(
          12.0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Reisende & Rabatte',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(
              height: 12,
            ),
            Row(
              children: [
                const Text(
                  'Alter:',
                ),
                const SizedBox(
                  width: 8,
                ),
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: ageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(
                  width: 16,
                ),
                const Text(
                  'Delay (ms):',
                ),
                const SizedBox(
                  width: 8,
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: delayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 12,
            ),
            CheckboxListTile(
              title: const Text(
                'Deutschland-Ticket',
              ),
              value: hasDeutschlandTicket,
              onChanged: onDeutschlandTicketChanged,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
            const SizedBox(
              height: 12,
            ),
            DropdownButtonFormField<
              String?
            >(
              decoration: const InputDecoration(
                labelText: 'BahnCard',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              value: selectedBahnCard,
              items: bahnCardOptions.map((
                option,
              ) {
                return DropdownMenuItem<
                  String?
                >(
                  value: option['value'],
                  child: Text(
                    option['label']!,
                  ),
                );
              }).toList(),
              onChanged: onBahnCardChanged,
            ),
          ],
        ),
      ),
    );
  }
}