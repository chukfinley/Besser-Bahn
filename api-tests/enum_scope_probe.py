#!/usr/bin/env python3
"""Raw request/response enum-flip differ for the DB vendo/gsd backend.

The #89 class of bug: a request enum silently scopes the response, the app sends
ONE value, and data for the other values reads as empty/occupied. A human only
caught it by seeing it live. This catches it mechanically: send the SAME logical
request twice, changing exactly ONE enum, dump BOTH raw responses to disk, and
diff the concrete values (prices, seat status, occupancy) — so a field that
flips with the param jumps out.

Every raw response is written to api-tests/_raw/<name>.json for eyeballing.
Run from api-tests/ :  python3 enum_scope_probe.py [scenario]
"""
import json
import os
import sys
import urllib.parse
from datetime import datetime, timedelta

sys.path.insert(0, ".")
import healthcheck as hc  # noqa: E402

RAW = os.path.join(os.path.dirname(__file__), "_raw")
os.makedirs(RAW, exist_ok=True)
KIEL = hc.KIEL_LOC
BERLIN = hc.BERLIN_LOC
FAHRPLAN_MEDIA = "application/x.db.vendo.mob.verbindungssuche.v9+json"


def _save(name, obj):
    p = os.path.join(RAW, f"{name}.json")
    with open(p, "w") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)
    return p


def _post(url, media, body, name):
    r = hc._post(url, headers=hc._vendo_headers(media),
                 data=json.dumps(body), timeout=hc.TIMEOUT)
    try:
        obj = r.json()
    except Exception:
        obj = {"_status": r.status_code, "_text": r.text[:500]}
    _save(name, {"_request": body, "_status": r.status_code, "response": obj})
    return r.status_code, obj


# ---------- helpers to make responses comparable across two calls ----------

def _fahrplan_body(klasse="KLASSE_2", reisende=None, dticket=False,
                   verkehrsmittel=None, fixed_time=None):
    when = fixed_time or datetime.now().astimezone().replace(microsecond=0)
    return {
        "autonomeReservierung": False,
        "einstiegsTypList": ["STANDARD"],
        "fahrverguenstigungen": {
            "deutschlandTicketVorhanden": dticket,
            "nurDeutschlandTicketVerbindungen": False,
        },
        "klasse": klasse,
        "reiseHin": {"wunsch": {
            "abgangsLocationId": KIEL,
            "alternativeHalteBerechnung": True,
            "verkehrsmittel": verkehrsmittel or ["ALL"],
            "zeitWunsch": {"reiseDatum": when.isoformat(),
                           "zeitPunktArt": "ABFAHRT"},
            "zielLocationId": BERLIN,
        }},
        "reisendenProfil": {"reisende": reisende or [{
            "ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"],
            "reisendenTyp": "ERWACHSENER",
        }]},
        "reservierungsKontingenteVorhanden": False,
    }


def _conn_key(c):
    """Identify a connection by its train numbers, so the SAME connection can be
    matched between two responses even when order/paging shifts."""
    legs = c["verbindung"]["verbindungsAbschnitte"]
    trains = tuple((l.get("produktGattung"), str(l.get("zugNummer") or ""))
                   for l in legs if l.get("produktGattung"))
    dep = c["verbindung"]["verbindungsAbschnitte"][0].get("abgangsDatum", "")[:16]
    return (trains, dep)


def _price(c):
    return (((c.get("angebote") or {}).get("preise") or {})
            .get("gesamt", {}).get("ab", {}).get("betrag"))


def _price_klasse(c):
    return (((c.get("angebote") or {}).get("preise") or {})
            .get("gesamt", {}).get("klasse"))


def _auslastung(c):
    out = {}
    for l in c["verbindung"]["verbindungsAbschnitte"]:
        for a in (l.get("auslastungsInfos") or []):
            out.setdefault(a.get("klasse"), a.get("stufe"))
    return out


# ---------- scenario 1: journey search, flip KLASSE ----------

def scen_fahrplan_klasse():
    print("\n" + "=" * 70)
    print("SCENARIO 1  journey search — flip klasse (K2 -> K1), same time window")
    print("=" * 70)
    t = datetime.now().astimezone().replace(microsecond=0)
    _, a = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                 FAHRPLAN_MEDIA, _fahrplan_body("KLASSE_2", fixed_time=t),
                 "fahrplan_k2")
    _, b = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                 FAHRPLAN_MEDIA, _fahrplan_body("KLASSE_1", fixed_time=t),
                 "fahrplan_k1")
    ka = {_conn_key(c): c for c in a.get("verbindungen", [])}
    kb = {_conn_key(c): c for c in b.get("verbindungen", [])}
    common = [k for k in ka if k in kb]
    print(f"K2 conns={len(ka)}  K1 conns={len(kb)}  matched={len(common)}")
    print(f"{'trains':38} {'K2 price':>9} {'K1 price':>9}  {'K2 klass':8} {'K1 klass':8}")
    for k in common[:8]:
        ta = ",".join(f"{g}{n}" for g, n in k[0]) or "(regional)"
        print(f"{ta[:38]:38} {str(_price(ka[k])):>9} {str(_price(kb[k])):>9}"
              f"  {str(_price_klasse(ka[k])):8} {str(_price_klasse(kb[k])):8}")
    print("raw -> api-tests/_raw/fahrplan_k2.json , fahrplan_k1.json")


# ---------- scenario 2: gsd seat map, flip KLASSE (the #89 flip, raw) ----------

def _gsd_raw(fahrtNr, dep, arr, dep_t, arr_t, klasse, name):
    data = {"buchungskontext": {"quellSystem": "SIMA",
            "buchungsKontextId": hc._corr_id(),
            "buchungsKontextDaten": {"zugnummer": fahrtNr, "zugfahrtKey": "",
                "abfahrtHalt": {"locationId": dep, "abfahrtZeit": dep_t},
                "ankunftHalt": {"locationId": arr, "ankunftZeit": arr_t},
                "inventarsystem": "RIFF",
                "platzbedarfe": [{"platzprofilCode": "StandardEinzelperson",
                                  "anzahl": 1.0, "klasse": klasse}]}},
            "correlationID": hc._corr_id(), "lang": "de", "theme": "app"}
    url = ("https://app.services-bahn.de/mob/gsd/gsd_v3?data="
           + urllib.parse.quote(json.dumps(data, separators=(",", ":"))))
    r = hc._get(url, headers={"User-Agent": "DBNavigator/Android/26.9.0"}, timeout=20)
    import re
    m = re.search(r"id='ssr_data'\s*>(.*?)</script>", r.text, re.S)
    ssr = json.loads(m.group(1)) if m else {"_no_ssr": True, "_status": r.status_code}
    _save(name, {"_request": data, "response": ssr})
    return ssr


def _free_ids(ssr):
    cs = [w for zt in ssr.get("zugfahrt", {}).get("zugteile", []) for w in zt.get("wagen", [])]
    return {(w.get("nummer"), p.get("nummer")) for w in cs
            for p in w.get("plaetze", []) if p.get("status") in (1, 2)}, cs


def scen_gsd_klasse():
    print("\n" + "=" * 70)
    print("SCENARIO 2  gsd seat map — flip klasse (K2 -> K1), SAME train  [#89]")
    print("=" * 70)
    # find a working long-distance leg
    _, a = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                 FAHRPLAN_MEDIA, _fahrplan_body(), "fahrplan_for_gsd")
    seg = None
    for c in a.get("verbindungen", []):
        for l in c["verbindung"]["verbindungsAbschnitte"]:
            if (l.get("produktGattung") or "").upper() not in ("ICE", "IC", "EC", "ECE"):
                continue
            fahrtNr = str(l.get("zugNummer") or "")
            dep = str(l.get("abgangsOrt", {}).get("evaNr") or "")
            arr = str(l.get("ankunftsOrt", {}).get("evaNr") or "")
            dep_t = (l.get("abgangsDatum") or "").split("+")[0]
            arr_t = (l.get("ankunftsDatum") or "").split("+")[0]
            if not (fahrtNr and dep and arr and dep_t and arr_t):
                continue
            ssr2 = _gsd_raw(fahrtNr, dep, arr, dep_t, arr_t, "KLASSE_2", "gsd_k2")
            if ssr2.get("zugfahrt"):
                seg = (fahrtNr, dep, arr, dep_t, arr_t, l.get("mitteltext"))
                break
        if seg:
            break
    if not seg:
        print("  no working long-distance segment")
        return
    fahrtNr, dep, arr, dep_t, arr_t, name = seg
    ssr1 = _gsd_raw(fahrtNr, dep, arr, dep_t, arr_t, "KLASSE_1", "gsd_k1")
    free2, cs2 = _free_ids(_gsd_raw(fahrtNr, dep, arr, dep_t, arr_t, "KLASSE_2", "gsd_k2"))
    free1, cs1 = _free_ids(ssr1)
    print(f"  train {name} nr={fahrtNr} {dep}->{arr} {dep_t}")
    print(f"  coaches: K2={len(cs2)} K1={len(cs1)}  (same physical train)")
    print(f"  free seats: K2={len(free2)}  K1={len(free1)}")
    print(f"  free ONLY in K1 (a K2-only fetch marks these occupied): {len(free1 - free2)}")
    print(f"  free ONLY in K2: {len(free2 - free1)}")
    # show a concrete first-class seat that flips
    only1 = sorted(free1 - free2)[:5]
    print(f"  example K1-only free seats (coach,seat): {only1}")
    print("  raw -> api-tests/_raw/gsd_k1.json , gsd_k2.json")


# ---------- scenario 3: fare — flip reisende (adult / BC50 / child) ----------

def scen_fahrplan_reisende():
    print("\n" + "=" * 70)
    print("SCENARIO 3  journey search — flip reisendenProfil (fare scoping)")
    print("=" * 70)
    t = datetime.now().astimezone().replace(microsecond=0)
    variants = {
        "adult": [{"ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"],
                   "reisendenTyp": "ERWACHSENER"}],
        "bc50_k2": [{"ermaessigungen": ["BAHNCARD50 KLASSE_2"],
                     "reisendenTyp": "ERWACHSENER"}],
        "child7": [{"ermaessigungen": ["KEINE_ERMAESSIGUNG KLASSENLOS"],
                    "reisendenTyp": "FAMILIENKIND", "alter": 7}],
    }
    res = {}
    for label, reis in variants.items():
        st, obj = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                        FAHRPLAN_MEDIA,
                        _fahrplan_body(reisende=reis, fixed_time=t),
                        f"fahrplan_{label}")
        res[label] = ({_conn_key(c): _price(c) for c in obj.get("verbindungen", [])}
                      if st == 200 else {})
        if st != 200:
            print(f"  {label}: HTTP {st} (skipped)")
    labels = [v for v in variants if res[v]]
    keys = [k for k in res["adult"] if all(k in res[v] for v in labels)]
    print(f"{'trains':38} {'adult':>8} {'BC50':>8} {'child7':>8}")
    for k in keys[:8]:
        ta = ",".join(f"{g}{n}" for g, n in k[0]) or "(regional)"
        print(f"{ta[:38]:38} {str(res['adult'][k]):>8} "
              f"{str(res['bc50_k2'].get(k)):>8} {str(res['child7'].get(k)):>8}")
    print("raw -> api-tests/_raw/fahrplan_adult.json , _bc50_k2.json , _child7.json")


# ---------- scenario 4: D-Ticket flag flips coverage/offers ----------

def scen_fahrplan_dticket():
    print("\n" + "=" * 70)
    print("SCENARIO 4  journey search — flip deutschlandTicketVorhanden")
    print("=" * 70)
    t = datetime.now().astimezone().replace(microsecond=0)
    _, a = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                 FAHRPLAN_MEDIA, _fahrplan_body(dticket=False, fixed_time=t),
                 "fahrplan_noDT")
    _, b = _post("https://app.services-bahn.de/mob/angebote/fahrplan",
                 FAHRPLAN_MEDIA, _fahrplan_body(dticket=True, fixed_time=t),
                 "fahrplan_DT")
    ka = {_conn_key(c): _price(c) for c in a.get("verbindungen", [])}
    kb = {_conn_key(c): _price(c) for c in b.get("verbindungen", [])}
    keys = [k for k in ka if k in kb]
    print(f"{'trains':38} {'no-DT':>8} {'with-DT':>8}")
    for k in keys[:8]:
        ta = ",".join(f"{g}{n}" for g, n in k[0]) or "(regional)"
        print(f"{ta[:38]:38} {str(ka[k]):>8} {str(kb[k]):>8}")
    print("raw -> api-tests/_raw/fahrplan_noDT.json , fahrplan_DT.json")


# ---------- scenario 5: zuglauf raw auslastung both classes ----------

def scen_zuglauf_auslastung():
    print("\n" + "=" * 70)
    print("SCENARIO 5  zuglauf — raw per-stop auslastungsInfos (both classes?)")
    print("=" * 70)
    pos = hc._vendo_board(hc.KOELN_HBF)
    zid = next((p["zuglaufId"] for p in pos
                if p.get("verkehrmittel", {}).get("produktGattung") in ("ICE", "IC")),
               pos[0]["zuglaufId"])
    r = hc._get(
        f"https://app.services-bahn.de/mob/zuglauf/{urllib.parse.quote(zid, safe='')}",
        headers=hc._vendo_headers(hc.ZUGLAUF_MEDIA), timeout=hc.TIMEOUT)
    obj = r.json()
    _save("zuglauf", obj)
    halte = obj.get("halte", [])
    print(f"  {len(halte)} halte")
    for h in halte[:6]:
        ai = {a.get("klasse"): a.get("stufe") for a in (h.get("auslastungsInfos") or [])}
        print(f"    {h.get('ort', {}).get('name', '?')[:28]:28} auslastung={ai}")
    print("  raw -> api-tests/_raw/zuglauf.json")


SCENARIOS = {
    "klasse": scen_fahrplan_klasse,
    "gsd": scen_gsd_klasse,
    "reisende": scen_fahrplan_reisende,
    "dticket": scen_fahrplan_dticket,
    "zuglauf": scen_zuglauf_auslastung,
}

if __name__ == "__main__":
    pick = sys.argv[1:] or list(SCENARIOS)
    for name in pick:
        fn = SCENARIOS.get(name)
        if fn is None:
            print(f"unknown scenario '{name}'; choose from {list(SCENARIOS)}")
            continue
        fn()
    print("\nAll raw responses saved under api-tests/_raw/ — inspect any of them.")
