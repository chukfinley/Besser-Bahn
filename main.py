import requests
import json
import argparse
from urllib.parse import parse_qs, urlparse
import time

# --- HILFSFUNKTION ---

def create_traveller_payload(age, bahncard_option):
    """
    Erstellt das 'reisende' JSON-Objekt basierend auf der ausgewählten BahnCard.
    """
    ermaessigung = {
        "art": "KEINE_ERMAESSIGUNG",
        "klasse": "KLASSENLOS"
    }

    # Wenn eine BahnCard-Option gewählt wurde, wird diese verarbeitet
    if bahncard_option:
        # Beispiel: 'BC25_2' wird zu Typ '25' und Klasse '2'
        bc_typ_str, klasse_str = bahncard_option.split('_')
        
        # Erstellt die korrekten API-Strings
        bc_art = f"BAHNCARD{bc_typ_str[2:]}" # Extrahiert '25' oder '50'
        k_art = f"KLASSE_{klasse_str}"      # Erstellt 'KLASSE_1' oder 'KLASSE_2'
        
        ermaessigung = {"art": bc_art, "klasse": k_art}
    
    # Das Alter wird aktuell für die Logik nicht benötigt, aber für die API bereitgestellt.
    return [{
        "typ": "ERWACHSENER",
        "ermaessigungen": [ermaessigung], # Ein Reisender hat nur eine Ermäßigungskarte
        "anzahl": 1,
        "alter": [] 
    }]

# --- API-FUNKTIONEN ---

def resolve_vbid_to_connection(vbid, traveller_payload, deutschland_ticket):
    """
    Löst einen kurzen vbid-Link auf, um die vollständigen Verbindungsdetails zu erhalten.
    """
    print(f"Löse vbid '{vbid}' auf...")
    try:
        vbid_url = f"https://www.bahn.de/web/api/angebote/verbindung/{vbid}"
        headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            "Accept": "application/json",
        }
        response = requests.get(vbid_url, headers=headers)
        response.raise_for_status()
        vbid_data = response.json()
        recon_string = vbid_data.get("hinfahrtRecon")

        if not recon_string:
            print("Fehler: Konnte keinen 'hinfahrtRecon' aus der vbid-Antwort extrahieren.")
            return None

        recon_url = "https://www.bahn.de/web/api/angebote/recon"
        payload = {
            "klasse": "KLASSE_2",
            "reisende": traveller_payload,
            "ctxRecon": recon_string,
            "deutschlandTicketVorhanden": deutschland_ticket
        }
        headers["Content-Type"] = "application/json; charset=UTF-8"
        
        print("Rufe vollständige Verbindungsdetails mit dem Recon-String ab...")
        response = requests.post(recon_url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()

    except requests.RequestException as e:
        print(f"Fehler beim Auflösen der vbid '{vbid}': {e}")
        return None

def get_connection_details(from_station_id, to_station_id, date, departure_time, traveller_payload, deutschland_ticket):
    """
    Ruft Verbindungsdetails ab (für lange URLs oder Teilstrecken).
    """
    url = "https://www.bahn.de/web/api/angebote/fahrplan"
    payload = {
        "abfahrtsHalt": from_station_id,
        "anfrageZeitpunkt": f"{date}T{departure_time}",
        "ankunftsHalt": to_station_id,
        "ankunftSuche": "ABFAHRT",
        "klasse": "KLASSE_2",
        "produktgattungen": ["ICE", "EC_IC", "IR", "REGIONAL", "SBAHN", "BUS", "SCHIFF", "UBAHN", "TRAM", "ANRUFPFLICHTIG"],
        "reisende": traveller_payload,
        "schnelleVerbindungen": True,
        "deutschlandTicketVorhanden": deutschland_ticket
    }
    headers = {
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Content-Type": "application/json; charset=UTF-8",
    }
    try:
        response = requests.post(url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.RequestException:
        return None

def get_price_for_segment(from_id, to_id, date, departure_time, traveller_payload, deutschland_ticket):
    """
    Fragt den Preis für ein bestimmtes Segment an.
    """
    time.sleep(0.5) # Kurze Pause, um die API nicht zu überlasten
    connections = get_connection_details(from_id, to_id, date, departure_time, traveller_payload, deutschland_ticket)
    if connections and connections.get('verbindungen'):
        first_connection = connections['verbindungen'][0]
        if first_connection.get('angebotsPreis'):
            return first_connection['angebotsPreis']['betrag']
    return None

# --- ANALYSE-FUNKTION ---

def find_cheapest_split(stops, date, direct_price, traveller_payload, deutschland_ticket):
    """
    Findet die günstigste Kombination von Tickets.
    """
    n = len(stops)
    prices = {}
    print("\n--- Preise für alle möglichen Teilstrecken werden abgerufen ---")
    
    for i in range(n):
        for j in range(i + 1, n):
            from_stop = stops[i]
            to_stop = stops[j]
            departure_time_str = from_stop['departure_time']
            if not departure_time_str:
                continue

            print(f"Frage Preis an für: {from_stop['name']} -> {to_stop['name']}...", end='', flush=True)
            price = get_price_for_segment(from_stop['id'], to_stop['id'], date, departure_time_str, traveller_payload, deutschland_ticket)
            
            if price is not None:
                prices[(i, j)] = price
                print(f" -> Preis gefunden: {price:.2f} €")
            else:
                print(" -> Kein Preis für dieses Segment verfügbar.")

    dp = [float('inf')] * n
    dp[0] = 0
    path_reconstruction = [-1] * n

    for i in range(1, n):
        for j in range(i):
            if (j, i) in prices:
                cost = dp[j] + prices[(j, i)]
                if cost < dp[i]:
                    dp[i] = cost
                    path_reconstruction[i] = j
    
    cheapest_split_price = dp[-1]
    
    print("\n" + "="*50)
    print("--- ERGEBNIS DER ANALYSE ---")
    print("="*50)

    if cheapest_split_price < direct_price and cheapest_split_price != float('inf'):
        savings = direct_price - cheapest_split_price
        print("\n🎉 Günstigere Split-Ticket-Option gefunden! 🎉")
        print(f"Direktpreis: {direct_price:.2f} €")
        print(f"Bester Split-Preis: {cheapest_split_price:.2f} €")
        print(f"💰 Ersparnis: {savings:.2f} € 💰")

        path = []
        current = n - 1
        while current > 0 and path_reconstruction[current] != -1:
            prev = path_reconstruction[current]
            path.append({
                "from": stops[prev]['name'],
                "to": stops[current]['name'],
                "price": prices.get((prev, current), 0)
            })
            current = prev
        path.reverse()
        
        print("\nEmpfohlene Tickets zum Buchen:")
        for idx, segment in enumerate(path, 1):
            print(f"  Ticket {idx}: Von {segment['from']} nach {segment['to']} für {segment['price']:.2f} €")
    else:
        print("\nKeine günstigere Split-Option gefunden.")
        print(f"Das Direktticket für {direct_price:.2f} € ist die beste Option.")

# --- HAUPTFUNKTION ---

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Findet günstigere Split-Tickets für eine DB-Verbindung über einen URL.",
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument("url", help="Der vollständige URL (lang oder kurz mit vbid) von bahn.de")
    parser.add_argument("--age", type=int, default=30, help="Alter des Reisenden (Standard: 30).")
    parser.add_argument(
        "--bahncard", 
        choices=['BC25_1', 'BC25_2', 'BC50_1', 'BC50_2'], 
        help="Wählen Sie eine der vier BahnCard-Optionen:\n"
             "BC25_1: BahnCard 25, 1. Klasse\n"
             "BC25_2: BahnCard 25, 2. Klasse\n"
             "BC50_1: BahnCard 50, 1. Klasse\n"
             "BC50_2: BahnCard 50, 2. Klasse"
    )
    parser.add_argument("--deutschland-ticket", action='store_true', help="Geben Sie an, ob ein Deutschland-Ticket vorhanden ist.")
    
    args = parser.parse_args()

    # Erstelle die Payloads basierend auf den Argumenten
    traveller_payload = create_traveller_payload(args.age, args.bahncard)
    
    connection_data = None
    date_part = None
    
    if "vbid=" in args.url:
        print("--- Kurzer Link (vbid) erkannt ---")
        vbid = parse_qs(urlparse(args.url).query)['vbid'][0]
        connection_data = resolve_vbid_to_connection(vbid, traveller_payload, args.deutschland_ticket)
        if connection_data:
            first_stop_departure = connection_data['verbindungen'][0]['verbindungsAbschnitte'][0]['halte'][0]['abfahrtsZeitpunkt']
            date_part = first_stop_departure.split('T')[0]
    else:
        print("--- Langer Link erkannt ---")
        params = parse_qs(urlparse(args.url).fragment)
        if not all(k in params for k in ['soid', 'zoid', 'hd']):
            print("Fehler: Der lange URL ist unvollständig.")
            exit()
        from_station_id = params['soid'][0]
        to_station_id = params['zoid'][0]
        datetime_str = params['hd'][0]
        date_part, time_part = datetime_str.split('T')
        connection_data = get_connection_details(from_station_id, to_station_id, date_part, time_part, traveller_payload, args.deutschland_ticket)

    if not connection_data or not connection_data.get('verbindungen'):
        print("Konnte keine Verbindungsdetails für den angegebenen Link abrufen.")
        exit()

    print("\n--- Analysiere die Verbindung ---")
    print(f"Datum: {date_part}")
    if args.bahncard:
        bc_typ, klasse = args.bahncard.split('_')
        print(f"Rabatt: BahnCard {bc_typ[2:]}, {klasse}. Klasse")
    if args.deutschland_ticket:
        print("Deutschland-Ticket: Vorhanden")

    first_connection = connection_data['verbindungen'][0]
    direct_price = first_connection.get('angebotsPreis', {}).get('betrag')
    
    if direct_price is None:
        print("Konnte den Direktpreis nicht ermitteln. Analyse nicht möglich.")
        exit()
        
    print(f"Direktpreis gefunden: {direct_price:.2f} €")

    all_stops = []
    print("\n--- Extrahiere alle Haltestellen der Verbindung ---")
    for section in first_connection['verbindungsAbschnitte']:
        if section['verkehrsmittel']['typ'] != 'WALK':
            for halt in section['halte']:
                if not any(stop['id'] == halt['id'] for stop in all_stops):
                    all_stops.append({
                        'name': halt['name'],
                        'id': halt['id'],
                        'departure_time': halt.get('abfahrtsZeitpunkt', '').split('T')[-1] if halt.get('abfahrtsZeitpunkt') else '',
                        'arrival_time': halt.get('ankunftsZeitpunkt', '').split('T')[-1] if halt.get('ankunftsZeitpunkt') else ''
                    })
    if all_stops:
        all_stops[-1]['departure_time'] = all_stops[-1]['arrival_time']

    print(f"{len(all_stops)} eindeutige Haltestellen gefunden:")
    for stop in all_stops:
        print(f"  - {stop['name']}")

    find_cheapest_split(all_stops, date_part, direct_price, traveller_payload, args.deutschland_ticket)