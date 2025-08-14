import requests
import json
import argparse
from urllib.parse import parse_qs, urlparse, quote
import time

# --- HILFSFUNKTIONEN ---

def create_traveller_payload(age, bahncard_option):
    """ Erstellt das 'reisende' JSON-Objekt basierend auf der ausgewählten BahnCard. """
    ermaessigung = {"art": "KEINE_ERMAESSIGUNG", "klasse": "KLASSENLOS"}
    if bahncard_option:
        bc_typ_str, klasse_str = bahncard_option.split('_')
        bc_art = f"BAHNCARD{bc_typ_str[2:]}"
        k_art = f"KLASSE_{klasse_str}"
        ermaessigung = {"art": bc_art, "klasse": k_art}
    return [{"typ": "ERWACHSENER", "ermaessigungen": [ermaessigung], "anzahl": 1, "alter": []}]

# --- API-FUNKTIONEN ---

def resolve_vbid_to_connection(vbid, traveller_payload, deutschland_ticket):
    """ Löst einen kurzen vbid-Link auf, um die vollständigen Verbindungsdetails zu erhalten. """
    print(f"Löse vbid '{vbid}' auf...")
    try:
        vbid_url = f"https://www.bahn.de/web/api/angebote/verbindung/{vbid}"
        headers = {"User-Agent": "Mozilla/5.0", "Accept": "application/json"}
        response = requests.get(vbid_url, headers=headers)
        response.raise_for_status()
        vbid_data = response.json()
        recon_string = vbid_data.get("hinfahrtRecon")
        if not recon_string:
            print("Fehler: Konnte keinen 'hinfahrtRecon' aus der vbid-Antwort extrahieren.")
            return None
        recon_url = "https://www.bahn.de/web/api/angebote/recon"
        payload = {"klasse": "KLASSE_2", "reisende": traveller_payload, "ctxRecon": recon_string, "deutschlandTicketVorhanden": deutschland_ticket}
        headers["Content-Type"] = "application/json; charset=UTF-8"
        print("Rufe vollständige Verbindungsdetails mit dem Recon-String ab...")
        response = requests.post(recon_url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Fehler beim Auflösen der vbid '{vbid}': {e}")
        return None

def get_connection_details(from_station_id, to_station_id, date, departure_time, traveller_payload, deutschland_ticket):
    """ Ruft Verbindungsdetails ab (für lange URLs oder Teilstrecken). """
    url = "https://www.bahn.de/web/api/angebote/fahrplan"
    payload = {
        "abfahrtsHalt": from_station_id, "anfrageZeitpunkt": f"{date}T{departure_time}",
        "ankunftsHalt": to_station_id, "ankunftSuche": "ABFAHRT", "klasse": "KLASSE_2",
        "produktgattungen": ["ICE", "EC_IC", "IR", "REGIONAL", "SBAHN", "BUS", "SCHIFF", "UBAHN", "TRAM", "ANRUFPFLICHTIG"],
        "reisende": traveller_payload, "schnelleVerbindungen": True, "deutschlandTicketVorhanden": deutschland_ticket
    }
    headers = {"User-Agent": "Mozilla/5.0", "Accept": "application/json", "Content-Type": "application/json; charset=UTF-8"}
    try:
        response = requests.post(url, json=payload, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.RequestException:
        return None

def get_segment_data(from_stop, to_stop, date, traveller_payload, deutschland_ticket):
    """ Fragt alle notwendigen Daten für ein Segment an und prüft auf Gültigkeit des Deutschland-Tickets. """
    time.sleep(0.5)
    departure_time_str = from_stop['departure_time']
    if not departure_time_str: return None
    
    connections = get_connection_details(from_stop['id'], to_stop['id'], date, departure_time_str, traveller_payload, deutschland_ticket)
    if connections and connections.get('verbindungen'):
        first_connection = connections['verbindungen'][0]
        price = first_connection.get('angebotsPreis', {}).get('betrag')
        # Dies ist die tatsächliche Abfahrtszeit des gefundenen Zuges für das Segment
        departure_iso = first_connection.get('verbindungsAbschnitte', [{}])[0].get('halte', [{}])[0].get('abfahrtsZeitpunkt')

        is_covered_by_d_ticket = False
        if deutschland_ticket:
            for section in first_connection.get('verbindungsAbschnitte', []):
                attributes = section.get('verkehrsmittel', {}).get('zugattribute', [])
                if any(attr.get('key') == '9G' for attr in attributes):
                    is_covered_by_d_ticket = True; break
        
        if is_covered_by_d_ticket:
            print(f" -> Deutschland-Ticket gültig! Preis wird auf 0.00 € gesetzt.")
            price = 0.0
        elif price is not None:
            print(f" -> Preis gefunden: {price:.2f} €")
        else:
            print(" -> Kein Preis für dieses Segment verfügbar.")
            return None

        if price is not None and departure_iso:
            return {
                "price": price,
                "start_name": from_stop['name'], "end_name": to_stop['name'],
                "start_id": from_stop['id'], "end_id": to_stop['id'],
                "departure_iso": departure_iso
            }
            
    print(" -> Keine Verbindungsdaten erhalten.")
    return None

def generate_booking_link(segment, bahncard_option, has_d_ticket):
    """ Erstellt einen stabilen, kontextreichen Buchungslink (Deep Link). """
    base_url = "https://www.bahn.de/buchung/fahrplan/suche"
    
    so = quote(segment['start_name'])
    zo = quote(segment['end_name'])
    soid = quote(segment['start_id'])
    zoid = quote(segment['end_id'])
    # Wichtig: Wir benutzen die exakte Abfahrtszeit des Segments
    hd = quote(segment['departure_iso'].split('.')[0])
    dltv = str(has_d_ticket).lower()
    r_param = ""

    if bahncard_option:
        bc_map = {
            'BC25_2': '13:25:KLASSE_2:1', 'BC25_1': '13:25:KLASSE_1:1',
            'BC50_2': '13:50:KLASSE_2:1', 'BC50_1': '13:50:KLASSE_1:1'
        }
        r_code = bc_map.get(bahncard_option)
        if r_code:
            r_param = f"&r={quote(r_code)}"

    return f"{base_url}#sts=true&so={so}&zo={zo}&soid={soid}&zoid={zoid}&hd={hd}&dltv={dltv}{r_param}"

# --- ANALYSE-FUNKTION ---

def find_cheapest_split(stops, date, direct_price, traveller_payload, args):
    """ Findet die günstigste Kombination von Tickets und generiert Links. """
    n = len(stops)
    segments_data = {}
    print("\n--- Preise und Daten für alle möglichen Teilstrecken werden abgerufen ---")
    
    for i in range(n):
        for j in range(i + 1, n):
            from_stop, to_stop = stops[i], stops[j]
            print(f"Frage Daten an für: {from_stop['name']} -> {to_stop['name']}...", end='', flush=True)
            data = get_segment_data(from_stop, to_stop, date, traveller_payload, args.deutschland_ticket)
            if data:
                segments_data[(i, j)] = data

    dp = [float('inf')] * n
    dp[0] = 0
    path_reconstruction = [-1] * n

    for i in range(1, n):
        for j in range(i):
            if (j, i) in segments_data:
                cost = dp[j] + segments_data[(j, i)]['price']
                if cost < dp[i]:
                    dp[i] = cost
                    path_reconstruction[i] = j
    
    cheapest_split_price = dp[-1]
    
    print("\n" + "="*50)
    print("--- ERGEBNIS DER ANALYSE ---")
    print("="*50)

    if cheapest_split_price < direct_price and cheapest_split_price != float('inf'):
        savings = direct_price - cheapest_split_price
        print(f"\n🎉 Günstigere Split-Ticket-Option gefunden! 🎉")
        print(f"Direktpreis: {direct_price:.2f} €")
        print(f"Bester Split-Preis: {cheapest_split_price:.2f} €")
        print(f"💰 Ersparnis: {savings:.2f} € 💰")

        path = []
        current = n - 1
        while current > 0 and path_reconstruction[current] != -1:
            prev = path_reconstruction[current]
            path.append(segments_data.get((prev, current)))
            current = prev
        path.reverse()
        
        print("\nEmpfohlene Tickets zum Buchen:")
        for idx, segment in enumerate(path, 1):
            if segment:
                print(f"  Ticket {idx}: Von {segment['start_name']} nach {segment['end_name']} für {segment['price']:.2f} €")
                if segment['price'] > 0:
                    link = generate_booking_link(segment, args.bahncard, args.deutschland_ticket)
                    print(f"      -> Buchungslink: {link}")
                else:
                    print("      -> (Fahrt durch Deutschland-Ticket abgedeckt)")

    else:
        print("\nKeine günstigere Split-Option gefunden.")
        print(f"Das Direktticket für {direct_price:.2f} € ist die beste Option.")

# --- HAUPTFUNKTION ---

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Findet günstigere Split-Tickets für eine DB-Verbindung und generiert Buchungslinks.", formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument("url", help="Der vollständige URL (lang oder kurz mit vbid) von bahn.de")
    parser.add_argument("--age", type=int, default=30, help="Alter des Reisenden (Standard: 30).")
    parser.add_argument("--bahncard", choices=['BC25_1', 'BC25_2', 'BC50_1', 'BC50_2'], help="Wählen Sie eine BahnCard-Option:\nBC25_1, BC25_2, BC50_1, BC50_2")
    parser.add_argument("--deutschland-ticket", action='store_true', help="Geben Sie an, ob ein Deutschland-Ticket vorhanden ist.")
    
    args = parser.parse_args()
    traveller_payload = create_traveller_payload(args.age, args.bahncard)
    
    connection_data, date_part = None, None
    
    url_to_parse = args.url
    if "/buchung/start" in url_to_parse:
        parsed_url = urlparse(url_to_parse)
        query_params = parse_qs(parsed_url.query)
        if 'vbid' in query_params:
            url_to_parse = f"https://www.bahn.de?vbid={query_params['vbid'][0]}"

    if "vbid=" in url_to_parse:
        print("--- Kurzer Link (vbid) erkannt ---")
        vbid = parse_qs(urlparse(url_to_parse).query)['vbid'][0]
        connection_data = resolve_vbid_to_connection(vbid, traveller_payload, args.deutschland_ticket)
        if connection_data:
            first_stop_departure = connection_data['verbindungen'][0]['verbindungsAbschnitte'][0]['halte'][0]['abfahrtsZeitpunkt']
            date_part = first_stop_departure.split('T')[0]
    else:
        print("--- Langer Link erkannt ---")
        params = parse_qs(urlparse(url_to_parse).fragment)
        if not all(k in params for k in ['soid', 'zoid', 'hd']):
            print("Fehler: Der lange URL ist unvollständig."); exit()
        from_station_id, to_station_id, datetime_str = params['soid'][0], params['zoid'][0], params['hd'][0]
        date_part, time_part = datetime_str.split('T')
        connection_data = get_connection_details(from_station_id, to_station_id, date_part, time_part, traveller_payload, args.deutschland_ticket)
    
    if not connection_data or not connection_data.get('verbindungen'):
        print("Konnte keine Verbindungsdetails für den angegebenen Link abrufen."); exit()

    print("\n--- Analysiere die Verbindung ---")
    print(f"Datum: {date_part}")
    if args.bahncard:
        bc_typ, klasse = args.bahncard.split('_'); print(f"Rabatt: BahnCard {bc_typ[2:]}, {klasse}. Klasse")
    if args.deutschland_ticket: print("Deutschland-Ticket: Vorhanden")

    first_connection = connection_data['verbindungen'][0]
    direct_price = first_connection.get('angebotsPreis', {}).get('betrag')
    
    if direct_price is None:
        print("Konnte den Direktpreis nicht ermitteln. Analyse nicht möglich."); exit()
    print(f"Direktpreis gefunden: {direct_price:.2f} €")

    all_stops = []
    print("\n--- Extrahiere alle Haltestellen der Verbindung ---")
    for section in first_connection['verbindungsAbschnitte']:
        if section['verkehrsmittel']['typ'] != 'WALK':
            for halt in section['halte']:
                if not any(stop['id'] == halt['id'] for stop in all_stops):
                    all_stops.append({
                        'name': halt['name'], 'id': halt['id'],
                        'departure_time': halt.get('abfahrtsZeitpunkt', '').split('T')[-1] if halt.get('abfahrtsZeitpunkt') else '',
                        'arrival_time': halt.get('ankunftsZeitpunkt', '').split('T')[-1] if halt.get('ankunftsZeitpunkt') else ''
                    })
    if all_stops: all_stops[-1]['departure_time'] = all_stops[-1]['arrival_time']

    print(f"{len(all_stops)} eindeutige Haltestellen gefunden:")
    for stop in all_stops: print(f"  - {stop['name']}")

    find_cheapest_split(all_stops, date_part, direct_price, traveller_payload, args)