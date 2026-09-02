# Recherche: Live-Flächen-Karte (alle Züge auf der Karte)

Stand: 2026-08-23. **Ergebnis: nicht implementiert.** Es gibt aktuell keinen
gratis + zuverlässigen Weg. Diese Notiz hält den kompletten Prüfstand fest,
damit das nicht nochmal von vorne recherchiert werden muss.

## Idee

Extra-Screen ("Live-Karte"), der wie bei geOps / TRAVIC alle Züge in einem
Kartenausschnitt live zeigt. Nutzen: Zug fällt weg, man weiß nicht mehr welcher
es war — Karte auf, Zug identifizieren. Standalone, an nichts gekoppelt, Polling
stoppt beim Verlassen des Screens.

## Wie geOps / TRAVIC das machen (verifiziert per Netzwerk-Mitschnitt)

- **TRAVIC** (`travic.app`): HTTP-Polling `GET /trajserv/trajectories?...bbox...`.
  Antwort = pro Fahrzeug die **ganze Trajektorie** (Polyline mit Zeit-Offsets `a`
  und Verspätung `dd`/`ad` in ms). Der Client interpoliert die Position über die
  Uhr. Kein Live-GPS pro Sekunde.
- **geOps Portal** (`mobility.portal.geops.io`): WebSocket
  `wss://api.geops.io/tracker-ws/v1/ws?key=...`. Client sendet `BBOX minx miny
  maxx maxy zoom` + `BUFFER 90 100`. Server pusht `trajectory`-Features:
  GeoJSON-LineString (Route in EPSG:3857) + `properties.time_intervals`
  (Zeitstempel pro Streckenpunkt in ms + Verspätungs-Flag). `train_number: null`
  in vielen → reiner Fahrplan, kein GPS, Position komplett gerechnet.

**Kernpunkt:** Beide streamen **keine** Sekunden-GPS-Positionen. Sie liefern
Route + Fahrplan + Verspätung, die Position wird im Client interpoliert. Genau
das, was unsere Route-Karte via `/mob/zuglauf`-Polyline schon pro Zug macht.
geOps holt die Daten vorab (Soll-Fahrplan als Datensatz, nicht pro Abfrage) und
lässt nur die Verspätung als dünnen Echtzeit-Strom nachlaufen. Kein DB-
Sonderzugang, keine IP-Farm nötig — sie nutzen die gesetzlich vorgeschriebenen
offenen Daten.

## Woher die Daten kommen

- **Soll-Fahrplan**: EU-Verordnung 2017/1926 zwingt jeden Betreiber, den Fahrplan
  am nationalen Zugangspunkt (DE: Mobilithek / DELFI e.V.) als Open Data (NeTEx)
  zu veröffentlichen. Ein Datensatz-Download, kein API-Hämmern, kein Rate-Limit.
- **gtfs.de** (Patrick Brosi, baut auch TRAVIC) rechnet diesen NeTEx-Dump täglich
  in sauberes GTFS um und aggregiert obendrauf einen GTFS-RT-Echtzeit-Feed aus
  dem, was Betreiber freiwillig offen publizieren. Lizenz CC BY-SA 4.0.

## Warum es (gratis) nicht geht — die harten Blocker

Alles real geprüft, nicht geraten:

1. **Free-RT-Feed hat keine Positionen.** `realtime.gtfs.de/realtime-free.pb`
   geparst: 81.503 Entities = 36.122 TripUpdates (nur Verspätungen) + 45.381
   Alerts, **0 VehiclePositions**. Position müsste man selbst aus static GTFS
   (Stops + Zeiten) rechnen.
2. **Free-RT-Feed ist 21,5 MB, ganz Deutschland, kein Bbox-Filter.** Alle 10s
   ziehen = ~130 MB/min mobiles Datenvolumen. Auf dem Handy unmöglich. Müsste
   serverseitig laufen.
3. **Free-static und Free-RT haben verschiedene IDs.** Overlap RT ↔ `fv_free`:
   194 / 5.589 Fahrten (3,5%). RT ↔ `rv_free`: ~5.292 / 108.688 (~5%). Der RT
   matcht die **Complete**-static (kostenpflichtig), nicht die minimierten
   Gratis-Subsets. Ohne ID-Match kein Join von Position + Verspätung. Tot.
4. **Kein `shapes.txt`** in den Free-Feeds → keine Gleisgeometrie; Position wäre
   nur Luftlinie zwischen Halten (für den Zweck okay, aber Punkt 3 killt es eh).
5. **DBs eigene Backends haben keinen Bbox-Radar.** `db-vendo-client` (nutzt das
   Vendo-`/mob`, dasselbe Backend wie unsere App): `radar()` explizit *not
   supported*, ebenso dbnav- und RIS-Profil. Radar konnte nur das **Alt-HAFAS**
   (`JourneyGeoPos`) — und das schaltet DB ab, weshalb `v6.db.transport.rest`
   unzuverlässig und zudem IPv6-only (hier nicht erreichbar) ist. Das ist genau
   die "HAFAS tot/wackelig"-Quelle, vor der unsere eigenen Notizen warnen.

Feed-Größen zum Merken: `fv_free` 0,4 MB (5.590 Fern-Fahrten), `rv_free` 12 MB
(108.688 Regio-Fahrten), `nv_free` 251 MB (Bus/Tram — für Zug-Scope irrelevant).

## Optionen mit ehrlichen Kosten

- **gtfs.de Complete Feed + matched RT** — funktioniert, laufende Kosten, Preis
  auf Anfrage.
- **geOps Realtime API** — wenig Arbeit (Client-only Websocket), zuverlässig,
  laufende Kosten. Nicht deren Portal-Public-Key missbrauchen (`5cc87b12…`):
  gegen ToS, Key wird rotiert → Screen tot.
- **db-rest `/radar` wrappen** — gratis, aber Alt-HAFAS-basiert = wackelig/tot,
  Screen zeitweise leer → Support-/Ruf-Risiko.
- **DB-HAFAS `mgate.exe` `JourneyGeoPos` direkt anpingen** — letzte ungeprüfte
  Gratis-Hoffnung. Falls DBs HAFAS-Radar noch antwortet, selbst hosten → €0,
  DB-Positionen. Noch nicht getestet.

## Entscheidung

Nicht implementiert. Kein tragfähiger Gratis-Weg; die billige Abkürzung
(db-rest) ist die instabile Quelle, die wir ohnehin meiden. Per-Zug-Live über
`/mob` (Route-Polyline + Verspätung) deckt den Hauptbedarf bereits ab. Falls das
Thema wieder aufkommt: zuerst den DB-HAFAS-`JourneyGeoPos`-Ping prüfen (einziger
verbleibender €0-Pfad), sonst nur gegen laufende Kosten (geOps / gtfs.de
Complete) machbar.

Lizenz-Merker, falls doch mal gtfs.de genutzt wird: CC BY-SA 4.0 erlaubt
kommerzielle Nutzung; Pflicht sind Attribution ("Daten: gtfs.de / DELFI, CC
BY-SA 4.0") und Share-Alike — Letzteres bindet nur die Daten, nicht den App-Code
(Anzeigen ist keine weiterverteilte Ableitung), Closed-Source-App also okay.
