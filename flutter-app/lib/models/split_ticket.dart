/// Models for the split-ticketing feature (migrated from v1)
class SplitTicket {
  final String from;
  final String to;
  final double price;
  final String fromId;
  final String toId;
  final String departureIso;
  final bool coveredByDeutschlandTicket;

  /// This fare couldn't be matched to the trains of the selected connection —
  /// it's the cheapest offer between these stops and may be a Sparpreis tied
  /// to a different train. Shown as a hint rather than suppressing the
  /// result (#13).
  final bool priceMayBeTrainBound;

  const SplitTicket({
    required this.from,
    required this.to,
    required this.price,
    required this.fromId,
    required this.toId,
    required this.departureIso,
    this.coveredByDeutschlandTicket = false,
    this.priceMayBeTrainBound = false,
  });

  String get priceFormatted => '${price.toStringAsFixed(2)} €';
}

class TicketAnalysisResult {
  final double directPrice;
  final double splitPrice;
  final List<SplitTicket> tickets;
  final int combinationsChecked;
  final Duration elapsed;

  const TicketAnalysisResult({
    required this.directPrice,
    required this.splitPrice,
    required this.tickets,
    this.combinationsChecked = 0,
    this.elapsed = Duration.zero,
  });

  double get savings => directPrice - splitPrice;
  double get savingsPercent =>
      directPrice > 0 ? (savings / directPrice) * 100 : 0;
  bool get hasSavings => savings > 0.01;
}

class SplitTicketProgress {
  final int totalCombinations;
  final int processedCombinations;
  final String currentSegment;

  const SplitTicketProgress({
    required this.totalCombinations,
    required this.processedCombinations,
    this.currentSegment = '',
  });

  double get progress =>
      totalCombinations > 0 ? processedCombinations / totalCombinations : 0;
}

enum BahnCardType {
  none('Keine', 'KEINE_ERMAESSIGUNG', 'KLASSENLOS'),
  bc25_2('BahnCard 25 (2. Kl)', 'BAHNCARD25', 'KLASSE_2'),
  bc25_1('BahnCard 25 (1. Kl)', 'BAHNCARD25', 'KLASSE_1'),
  bc50_2('BahnCard 50 (2. Kl)', 'BAHNCARD50', 'KLASSE_2'),
  bc50_1('BahnCard 50 (1. Kl)', 'BAHNCARD50', 'KLASSE_1');

  final String label;
  final String apiValue;
  final String classValue;
  const BahnCardType(this.label, this.apiValue, this.classValue);

  /// DB Vendo reduction token `ART KLASSE` for the `reisende` payload.
  String get vendoErmaessigung => this == BahnCardType.none
      ? 'KEINE_ERMAESSIGUNG KLASSENLOS'
      : '$apiValue $classValue';

  /// Whether this card implies 1st class (drives the journey-search class).
  bool get isFirstClass => classValue == 'KLASSE_1';

  String get bookingCode {
    switch (this) {
      case BahnCardType.none:
        return '';
      case BahnCardType.bc25_2:
        return '13:25:KLASSE_2:1';
      case BahnCardType.bc25_1:
        return '13:25:KLASSE_1:1';
      case BahnCardType.bc50_2:
        return '13:50:KLASSE_2:1';
      case BahnCardType.bc50_1:
        return '13:50:KLASSE_1:1';
    }
  }
}
