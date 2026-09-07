import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:besser_bahn/models/db_ticket.dart';

/// One `auftrag/kundenwunsch` payload, with the order node named by [node].
///
/// The real response is a union — `reise`, `katalog`, `streckenzeitkarte`,
/// `reisekette` or `vertrag` — and only one of them is present (see
/// `AuftragsbezogeneReiseModel` in the DB Navigator app).
Map<String, dynamic> _order(
  String node,
  String infoKey,
  Map<String, dynamic> info,
) => {
  node: {
    'standardInfos': {
      'auftragsnummer': '977758847570',
      'kundenwunschId': '6ff84ae7',
      'status': 'GUELTIG',
      'zeitlicheGueltigkeit': {
        'ersterGeltungszeitpunkt': '2026-09-07T00:00:00+02:00',
      },
    },
    infoKey: info,
  },
};

String _html(String body) => base64Encode(utf8.encode(body));

void main() {
  test('a booked journey still parses (reise)', () {
    final t = DbTicket.fromJson(
      _order('reise', 'reiseInfos', {
        'angebotsname': 'Super Sparpreis',
        'klasse': 'KLASSE_2',
        'raeumlicheGueltigkeit': {
          'abgangsOrt': {'name': 'Bützow'},
          'ankunftsOrt': {'name': 'Hamburg Hbf'},
        },
      }),
    );
    expect(t.auftragsnummer, '977758847570');
    expect(t.angebotsname, 'Super Sparpreis');
    expect(t.hasClass, isTrue);
    expect(t.firstClass, isFalse);
    expect(t.vonName, 'Bützow');
    expect(t.nachName, 'Hamburg Hbf');
  });

  test('a flat-rate ticket keeps its name and its 1. Klasse (#99)', () {
    // The reported case: a Länder-Ticket sits under `katalog`, and reading
    // only `reise` turned it into a nameless "Einzelkarte 2.Kl".
    final t = DbTicket.fromJson(
      _order('katalog', 'katalogInfos', {
        'angebotsname': 'Mecklenburg-Vorpommern-Ticket',
        'klasse': 'KLASSE_1',
        'ticketStatus': 'GUELTIG',
        'reisendenInformation': [
          {'anzahl': 1, 'typ': 'ERWACHSENER'},
        ],
        'ticket': {'ticket': _html('<html>Mecklenburg-Vorpommern-Ticket</html>')},
      }),
    );
    expect(t.angebotsname, 'Mecklenburg-Vorpommern-Ticket');
    expect(t.firstClass, isTrue);
    expect(t.ticketHtml, contains('Mecklenburg-Vorpommern'));
    expect(t.reisendeText, isNotEmpty);
  });

  test('a season ticket carries its route in flat fields', () {
    final t = DbTicket.fromJson(
      _order('streckenzeitkarte', 'streckenzeitkarteInfos', {
        'angebotsname': 'Monatskarte',
        'klasse': 'KLASSE_2',
        'abgangsort': 'Kiel Hbf',
        'ankunftsort': 'Neumünster',
      }),
    );
    expect(t.vonName, 'Kiel Hbf');
    expect(t.nachName, 'Neumünster');
  });

  test('a chain order reads the first ticket block', () {
    final t = DbTicket.fromJson(
      _order('reisekette', 'reiseketteInfos', {
        'uebergreifenderAnzeigeName': 'Hin- und Rückfahrt',
        'reisekettenTicketInfos': [
          {'angebotsname': 'Sparpreis', 'klasse': 'KLASSE_1'},
          {'angebotsname': 'Sparpreis', 'klasse': 'KLASSE_1'},
        ],
      }),
    );
    expect(t.angebotsname, 'Sparpreis');
    expect(t.firstClass, isTrue);
  });

  test('a subscription reads its nested ticket block', () {
    final t = DbTicket.fromJson(
      _order('vertrag', 'vertragInfos', {
        'vertragsnummer': '123',
        'vertragTicketInfos': [
          {'angebotsname': 'Deutschland-Ticket', 'klasse': 'KLASSE_2'},
        ],
      }),
    );
    expect(t.angebotsname, 'Deutschland-Ticket');
    expect(t.firstClass, isFalse);
  });

  test('an order with no class stays unknown instead of claiming 2. Klasse', () {
    final t = DbTicket.fromJson(
      _order('katalog', 'katalogInfos', {'angebotsname': 'Irgendwas'}),
    );
    expect(t.klasse, isNull);
    expect(t.hasClass, isFalse);
    expect(t.firstClass, isFalse);
  });

  test('an unknown payload does not throw', () {
    final t = DbTicket.fromJson(const {'unbekannt': {}});
    expect(t.auftragsnummer, '');
    expect(t.hasClass, isFalse);
  });
}
