class JourneySearch {
  final String from;
  final String to;
  final DateTime date;

  const JourneySearch({
    required this.from,
    required this.to,
    required this.date,
  });

  Map<String, dynamic> toJson() {
    return {'from': from, 'to': to, 'date': date.toIso8601String()};
  }

  factory JourneySearch.fromJson(Map<String, dynamic> json) {
    return JourneySearch(
      from: json['from'] as String,
      to: json['to'] as String,
      date: DateTime.parse(json['date'] as String),
    );
  }
}
