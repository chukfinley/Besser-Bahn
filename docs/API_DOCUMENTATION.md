# Better-Bahn API Documentation

## Overview

This document details the unofficial Deutsche Bahn API endpoints that Better-Bahn uses to gather pricing and connection information. These endpoints are reverse-engineered from browser interactions with bahn.de.

⚠️ **Important**: These are unofficial APIs that could change without notice. The endpoints are not officially supported by Deutsche Bahn.

## Base Configuration

### API Base URL
```
https://www.bahn.de/web/api
```

### Common Headers
```http
User-Agent: Mozilla/5.0 (compatible browser string)
Accept: application/json
Content-Type: application/json; charset=UTF-8
Accept-Language: de
```

### Rate Limiting
- **Current Implementation**: 0.5 second delay between requests
- **Recommendation**: Respect server resources, avoid aggressive querying
- **Risk**: Too many requests may result in IP blocking

## API Endpoints

### 1. vbid Resolution

**Purpose**: Convert short vbid links to full connection details

#### Endpoint
```http
GET /angebote/verbindung/{vbid}
```

#### Parameters
- `{vbid}`: The vbid identifier from short links

#### Example Request
```http
GET https://www.bahn.de/web/api/angebote/verbindung/9dd9db26-4ffc-411c-b79c-e82bf5338989
Accept: application/json
User-Agent: Mozilla/5.0
```

#### Response Structure
```json
{
  "hinfahrtRecon": "¶HKI¶T$A=1@O=Berlin...",
  "startOrt": "Berlin Hbf",
  "zielOrt": "München Hbf",
  "hinfahrtDatum": "2024-03-15T08:30:00.000Z",
  "klasse": "KLASSE_2",
  "reisende": [...],
  "verbindungsId": "..."
}
```

#### Key Fields
- `hinfahrtRecon`: Encoded connection string for subsequent API calls
- `startOrt`: Origin station name
- `zielOrt`: Destination station name
- `hinfahrtDatum`: Departure date/time

### 2. Recon Processing

**Purpose**: Get detailed connection information using recon string

#### Endpoint
```http
POST /angebote/recon
```

#### Request Payload
```json
{
  "klasse": "KLASSE_2",
  "reisende": [
    {
      "typ": "ERWACHSENER",
      "ermaessigungen": [
        {
          "art": "BAHNCARD25",
          "klasse": "KLASSE_2"
        }
      ],
      "anzahl": 1,
      "alter": []
    }
  ],
  "ctxRecon": "¶HKI¶T$A=1@O=Berlin...",
  "deutschlandTicketVorhanden": false
}
```

#### Passenger Types
- `ERWACHSENER`: Adult passenger
- `KIND`: Child passenger
- `JUGENDLICHER`: Youth passenger

#### Discount Types
```json
{
  "art": "BAHNCARD25|BAHNCARD50|KEINE_ERMAESSIGUNG",
  "klasse": "KLASSE_1|KLASSE_2|KLASSENLOS"
}
```

#### Response Structure
```json
{
  "verbindungen": [
    {
      "angebotsPreis": {
        "betrag": 49.90,
        "waehrung": "EUR"
      },
      "verbindungsAbschnitte": [
        {
          "verkehrsmittel": {
            "typ": "ICE",
            "nummer": "123",
            "zugattribute": [
              {"key": "9G", "value": "Deutschland-Ticket eligible"}
            ]
          },
          "halte": [
            {
              "id": "8011160",
              "name": "Berlin Hbf",
              "abfahrtsZeitpunkt": "2024-03-15T08:30:00.000Z",
              "ankunftsZeitpunkt": null
            }
          ]
        }
      ]
    }
  ]
}
```

### 3. Timetable Search

**Purpose**: Direct search for connections between stations

#### Endpoint
```http
POST /angebote/fahrplan
```

#### Request Payload
```json
{
  "abfahrtsHalt": "8011160",
  "anfrageZeitpunkt": "2024-03-15T08:30",
  "ankunftsHalt": "8000261",
  "ankunftSuche": "ABFAHRT",
  "klasse": "KLASSE_2",
  "produktgattungen": [
    "ICE", "EC_IC", "IR", "REGIONAL", 
    "SBAHN", "BUS", "SCHIFF", "UBAHN", 
    "TRAM", "ANRUFPFLICHTIG"
  ],
  "reisende": [...],
  "schnelleVerbindungen": true,
  "deutschlandTicketVorhanden": false
}
```

#### Parameters
- `abfahrtsHalt`: Origin station ID
- `ankunftsHalt`: Destination station ID
- `anfrageZeitpunkt`: Search time in ISO format
- `ankunftSuche`: "ABFAHRT" for departure time, "ANKUNFT" for arrival time
- `produktgattungen`: Array of transport types to include

#### Transport Types
- `ICE`: High-speed trains
- `EC_IC`: EuroCity/InterCity
- `IR`: InterRegio
- `REGIONAL`: Regional trains
- `SBAHN`: S-Bahn suburban trains
- `BUS`: Bus connections
- `SCHIFF`: Ferry connections
- `UBAHN`: U-Bahn subway
- `TRAM`: Tram/streetcar
- `ANRUFPFLICHTIG`: On-demand services

## Data Structures

### Station Object
```json
{
  "id": "8011160",
  "name": "Berlin Hbf",
  "coordinates": {
    "lat": 52.525589,
    "lon": 13.369548
  }
}
```

### Connection Object
```json
{
  "verbindungsId": "unique-id",
  "angebotsPreis": {
    "betrag": 49.90,
    "waehrung": "EUR",
    "preisart": "STANDARD"
  },
  "dauer": "PT4H30M",
  "umstiege": 1,
  "verbindungsAbschnitte": [...]
}
```

### Section Object
```json
{
  "verkehrsmittel": {
    "typ": "ICE",
    "nummer": "123",
    "name": "ICE 123",
    "zugattribute": [
      {"key": "9G", "value": "Deutschland-Ticket eligible"}
    ]
  },
  "halte": [
    {
      "id": "8011160",
      "name": "Berlin Hbf",
      "abfahrtsZeitpunkt": "2024-03-15T08:30:00.000Z",
      "ankunftsZeitpunkt": "2024-03-15T08:35:00.000Z",
      "platform": "12"
    }
  ]
}
```

## Deutschland-Ticket Detection

The Deutschland-Ticket eligibility is determined by the presence of specific train attributes:

```json
{
  "zugattribute": [
    {
      "key": "9G",
      "value": "Deutschland-Ticket compatible"
    }
  ]
}
```

When `9G` attribute is present, the segment is covered by Deutschland-Ticket and price is set to €0.

## Error Handling

### Common Error Responses

#### Rate Limiting
```json
{
  "error": "Too Many Requests",
  "code": 429,
  "message": "Rate limit exceeded"
}
```

#### Invalid Station
```json
{
  "error": "Invalid Station",
  "code": 400,
  "message": "Station ID not found"
}
```

#### No Connections Found
```json
{
  "verbindungen": []
}
```

### HTTP Status Codes
- `200`: Success
- `400`: Bad Request (invalid parameters)
- `429`: Too Many Requests (rate limited)
- `500`: Internal Server Error
- `503`: Service Unavailable

## Implementation Examples

### Python Implementation

```python
import requests
import time
from typing import Optional, Dict, List

class DBAPIClient:
    BASE_URL = "https://www.bahn.de/web/api"
    
    def __init__(self, rate_limit_delay: float = 0.5):
        self.rate_limit_delay = rate_limit_delay
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0',
            'Accept': 'application/json',
            'Accept-Language': 'de'
        })
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Optional[Dict]:
        """Make API request with rate limiting and error handling"""
        time.sleep(self.rate_limit_delay)
        
        try:
            url = f"{self.BASE_URL}{endpoint}"
            response = self.session.request(method, url, **kwargs)
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            print(f"API request failed: {e}")
            return None
    
    def resolve_vbid(self, vbid: str) -> Optional[Dict]:
        """Resolve vbid to connection details"""
        return self._make_request('GET', f'/angebote/verbindung/{vbid}')
    
    def get_connections(self, 
                       from_station: str, 
                       to_station: str, 
                       departure_time: str,
                       traveller_data: List[Dict]) -> Optional[Dict]:
        """Get connections between stations"""
        payload = {
            'abfahrtsHalt': from_station,
            'ankunftsHalt': to_station,
            'anfrageZeitpunkt': departure_time,
            'ankunftSuche': 'ABFAHRT',
            'klasse': 'KLASSE_2',
            'reisende': traveller_data,
            'produktgattungen': ['ICE', 'EC_IC', 'IR', 'REGIONAL'],
            'schnelleVerbindungen': True,
            'deutschlandTicketVorhanden': False
        }
        
        return self._make_request('POST', '/angebote/fahrplan', json=payload)
```

### JavaScript/Flutter Implementation

```dart
class DBAPIClient {
  static const String baseUrl = 'https://www.bahn.de/web/api';
  final http.Client client;
  final Duration rateLimitDelay;
  
  DBAPIClient({http.Client? client, this.rateLimitDelay = const Duration(milliseconds: 500)})
      : client = client ?? http.Client();
  
  Future<Map<String, dynamic>?> _makeRequest(
      String method, String endpoint, {Map<String, dynamic>? body}) async {
    
    await Future.delayed(rateLimitDelay);
    
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      final headers = {
        'User-Agent': 'Mozilla/5.0',
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=UTF-8',
        'Accept-Language': 'de',
      };
      
      http.Response response;
      if (method == 'GET') {
        response = await client.get(uri, headers: headers);
      } else {
        response = await client.post(uri, headers: headers, body: jsonEncode(body));
      }
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Network error: $e');
      return null;
    }
  }
  
  Future<Map<String, dynamic>?> resolveVbid(String vbid) async {
    return _makeRequest('GET', '/angebote/verbindung/$vbid');
  }
}
```

## Best Practices

### 1. Rate Limiting
- Always implement delays between requests
- Use exponential backoff for retries
- Monitor for rate limiting responses

### 2. Error Handling
- Handle network failures gracefully
- Provide user-friendly error messages
- Implement retry logic for transient failures

### 3. Data Validation
- Validate station IDs before making requests
- Check response structure before processing
- Handle missing or null fields safely

### 4. Caching
- Cache station data to reduce API calls
- Store connection results temporarily
- Implement cache invalidation strategies

### 5. Monitoring
- Log API response times
- Track success/failure rates
- Monitor for API changes

## Security Considerations

### 1. No Authentication Required
- APIs are publicly accessible
- No API keys or tokens needed
- Rate limiting is the primary protection

### 2. Data Privacy
- Don't store unnecessary user data
- Process requests locally when possible
- Respect user privacy preferences

### 3. Ethical Usage
- Respect server resources
- Don't abuse rate limits
- Consider impact on DB infrastructure

## Troubleshooting

### Common Issues

#### 1. Empty Response
```json
{"verbindungen": []}
```
**Causes**: Invalid station IDs, no connections available, time too far in future
**Solutions**: Validate inputs, try different times, check station existence

#### 2. Rate Limiting
**Symptoms**: 429 status codes, blocked requests
**Solutions**: Increase delays, implement exponential backoff, use proxy rotation

#### 3. Changed API Structure
**Symptoms**: Missing fields, unexpected response format
**Solutions**: Update parsing logic, add defensive programming, monitor for changes

### Debugging Tips

1. **Log All Requests**: Keep track of what you're sending
2. **Inspect Responses**: Understand the data structure
3. **Test with Browser**: Compare with manual bahn.de usage
4. **Monitor Network**: Use tools like mitmproxy to inspect traffic

## Limitations

1. **Unofficial Status**: No guarantees of stability or availability
2. **Rate Limits**: Aggressive usage may be blocked
3. **Geographic Scope**: Limited to German railway network
4. **Language**: Responses primarily in German
5. **Real-time Data**: Limited access to live delay information

This API documentation reflects the current understanding of Deutsche Bahn's web interfaces. Always test thoroughly and implement robust error handling when using these endpoints.