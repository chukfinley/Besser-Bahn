import requests

url = "https://www.bahn.de/web/api/angebote/verbindung/teilen"

payload = {
    "startOrt": "Elsterwerda",
    "zielOrt": "Dresden Hbf",
    "hinfahrtDatum": "2025-08-23T09:37:00.000Z",
    "hinfahrtRecon": "¶HKI¶T$A=1@O=Elsterwerda@X=13516432@Y=51459675@L=8010099@a=128@$A=1@O=Coswig(b Dresden)@X=13579411@Y=51122814@L=8010072@a=128@$202508231146$202508231224$RB          18019$$1$$$$$$§T$A=1@O=Coswig(b Dresden)@X=13579411@Y=51122814@L=8010072@a=128@$A=1@O=Dresden Hbf@X=13732039@Y=51040562@L=8010085@a=128@$202508231230$202508231257$S               1$$1$$$$$$¶KC¶#VE#2#CF#100#CA#0#CM#0#SICT#0#AM#81#AM2#0#RT#7#¶KCC¶I1ZFIzEjRVJHIzIjSElOIzAjRUNLIzM2NTAyNnwzNjUwMjZ8MzY1MDk3fDM2NTA5N3wwfDB8MzI1fDM2NTAxOHwyfDB8MjZ8MHwwfC0yMTQ3NDgzNjQ4I0dBTSMyMzA4MjUxMTQ2IwpaI1ZOIzEjU1QjMTc1NDk0NjQ0NSNQSSMwI1pJIzI0NjM4NCNUQSMxI0RBIzIzMDgyNSMxUyM4MDEwMTAwIzFUIzExMzcjTFMjODAxMDA4OSNMVCMxMjQ3I1BVIzgwI1JUIzEjQ0EjUkIjWkUjMTgwMTkjWkIjUkIgICAgICAgICAgMTgwMTkjUEMjMyNGUiM4MDEwMDk5I0ZUIzExNDYjVE8jODAxMDA3MiNUVCMxMjI0IwpaI1ZOIzEjU1QjMTc1NDk0NjQ0NSNQSSMwI1pJIzI3NTA4MiNUQSMxI0RBIzIzMDgyNSMxUyM4MDEyMzI3IzFUIzEyMTcjTFMjODAxMDAyMiNMVCMxMzQzI1BVIzgwI1JUIzEjQ0EjcyNaRSMxI1pCI1MgICAgICAgICAgICAgICAxI1BDIzQjRlIjODAxMDA3MiNGVCMxMjMwI1RPIzgwMTAwODUjVFQjMTI1NyM=¶KRCC¶#VE#1#¶SC¶1_H4sIAAAAAAACA22P0U6DMBiFX8X0Gpe/QBmQkCDDRc3iyLIZjfGijm5iCsy2TAnhOXwgX8xSYjKjN03P6fnP97dDRyZQiPDEd5GF2IfSIk0md+kE29oQ7A2FHaqaco5CYg2XBIVgobpRKVVMp22wCfi2g4y5LsrBxNiZAmhrZxrOsYVeq3bOlVig8LFDqj0MsWy1THWorPNBXd/OtDhS3pgK0J39k1lq9rIfizU5Z4dFvR1reJHr5EWE42V0yaVi4p2JnMb3EXYI9lzHjh8igl0SeFMSbyIf4oU+MEAQxEW0+foE8AFcx/VjjZZq/NLccKkQ/4JSwWTOqrOr550BTR0bnMCAwAXi2b9APjkBeUDgL2jPVLpao1CJhhmV1bzlRaUTO8rl6N3UjahYm9RNlcvTh4xKyQupfubZts6ooKUOdX3ffwOQvpJj4gEAAA=="
}
headers = {
    "host": "www.bahn.de",
    "connection": "keep-alive",
    "sec-ch-ua-platform": "\"Linux\"",
    "x-correlation-id": "bb5026a5-74b8-43b4-a6b7-ed6ea2aa1735_6151ba0e-50ef-4ed1-9776-9c63a6da3312",
    "accept-language": "de",
    "sec-ch-ua": "\"Not;A=Brand\";v=\"99\", \"Google Chrome\";v=\"139\", \"Chromium\";v=\"139\"",
    "sec-ch-ua-mobile": "?0",
    "user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36",
    "accept": "application/json",
    "content-type": "application/json",
    "origin": "https://www.bahn.de",
    "sec-fetch-site": "same-origin",
    "sec-fetch-mode": "cors",
    "sec-fetch-dest": "empty",
    "referer": "https://www.bahn.de/buchung/fahrplan/suche",
    "accept-encoding": "gzip, deflate, br, zstd",
}

response = requests.post(url, json=payload, headers=headers)

print(response.text)