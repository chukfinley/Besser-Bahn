class SplitTicket {
  final String from;
  final String to;
  final double price;
  final String fromId;
  final String toId;
  final String departureIso;
  final bool coveredByDeutschlandTicket;

  SplitTicket({
    required this.from,
    required this.to,
    required this.price,
    required this.fromId,
    required this.toId,
    required this.departureIso,
    this.coveredByDeutschlandTicket = false,
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