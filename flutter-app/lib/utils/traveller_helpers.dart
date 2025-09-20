import 'package:besser_bahn/models/ticket_models.dart'; // Import models

class TravellerHelpers {
  final String? _selectedBahnCard;
  final bool _hasDeutschlandTicket;

  TravellerHelpers(this._selectedBahnCard, this._hasDeutschlandTicket);

  List<Map<String, dynamic>> createTravellerPayload() {
    Map<String, dynamic> ermaessigung = {
      "art": "KEINE_ERMAESSIGUNG",
      "klasse": "KLASSENLOS",
    };

    if (_selectedBahnCard != null) {
      final parts = _selectedBahnCard!.split('_');
      final bcTyp = parts[0].substring(
        2,
      ); // Extract '25' or '50'
      final klasse = parts[1];

      ermaessigung = {
        "art": "BAHNCARD$bcTyp",
        "klasse": "KLASSE_$klasse",
      };
    }

    return [
      {
        "typ": "ERWACHSENER",
        "ermaessigungen": [
          ermaessigung,
        ],
        "anzahl": 1,
        "alter": [],
      },
    ];
  }

  String generateBookingLink(
    SplitTicket ticket,
  ) {
    final baseUrl = "https://www.bahn.de/buchung/fahrplan/suche";

    final so = Uri.encodeComponent(
      ticket.from,
    );
    final zo = Uri.encodeComponent(
      ticket.to,
    );
    final soid = Uri.encodeComponent(
      ticket.fromId,
    );
    final zoid = Uri.encodeComponent(
      ticket.toId,
    );
    final hd = Uri.encodeComponent(
      ticket.departureIso.split('.')[0],
    );
    final dltv = _hasDeutschlandTicket.toString().toLowerCase();
    String rParam = "";

    if (_selectedBahnCard != null) {
      final bcMap = {
        'BC25_2': '13:25:KLASSE_2:1',
        'BC25_1': '13:25:KLASSE_1:1',
        'BC50_2': '13:50:KLASSE_2:1',
        'BC50_1': '13:50:KLASSE_1:1',
      };
      final rCode = bcMap[_selectedBahnCard];
      if (rCode != null) {
        rParam = "&r=${Uri.encodeComponent(rCode)}";
      }
    }

    return "$baseUrl#sts=true&so=$so&zo=$zo&soid=$soid&zoid=$zoid&hd=$hd&dltv=$dltv$rParam";
  }
}