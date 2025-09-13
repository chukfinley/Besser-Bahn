# Better-Bahn Technical Documentation

## Architecture Overview

Better-Bahn is a dual-platform application designed to find cheaper split-ticket combinations for Deutsche Bahn (German Railway) journeys. The project consists of two main components:

1. **Python CLI Tool** (`main.py`) - Core logic and API interactions
2. **Flutter Mobile App** (`flutter-app/`) - User-friendly mobile interface

## Core Functionality

### Split-Ticket Analysis Algorithm

The application implements a dynamic programming approach to find the optimal combination of tickets:

1. **Route Extraction**: Parses DB URLs (both short vbid links and long URLs) to extract journey details
2. **Station Discovery**: Identifies all intermediate stations along the route
3. **Price Matrix**: Queries prices for all possible sub-routes between stations
4. **Optimization**: Uses dynamic programming to find the cheapest combination of tickets

### API Integration Strategy

**Important**: Better-Bahn does not use official Deutsche Bahn APIs. Instead, it simulates browser requests to `bahn.de` to gather pricing data.

#### Request Flow:
1. **URL Resolution**: 
   - Short links (vbid) → `/web/api/angebote/verbindung/{vbid}`
   - Long links → Direct parsing of route parameters

2. **Connection Details**: 
   - Endpoint: `/web/api/angebote/fahrplan`
   - Payload includes traveler data, BahnCard discounts, Deutschland-Ticket status

3. **Price Discovery**:
   - Queries all possible sub-routes between stations
   - Rate limiting: 0.5 second delay between requests
   - Deutschland-Ticket compatibility checking

## Technical Components

### Python Backend (`main.py`)

#### Key Functions:

- `resolve_vbid_to_connection()`: Converts short links to full connection data
- `get_connection_details()`: Fetches route and pricing information
- `get_segment_data()`: Analyzes individual route segments
- `find_cheapest_split()`: Dynamic programming optimization algorithm
- `generate_booking_link()`: Creates deep links for ticket purchasing

#### Supported Features:
- BahnCard discounts (25/50, 1st/2nd class)
- Deutschland-Ticket integration
- Age-based pricing
- Direct booking link generation

### Flutter Frontend

#### Architecture:
- Material Design 3 with DB corporate colors
- Responsive design for mobile devices
- HTTP client for API communication
- URL launcher for external booking links

#### Key Features:
- Link input and validation
- Settings for BahnCard and Deutschland-Ticket
- Results display with savings calculation
- Direct booking link integration

## Data Flow

```
User Input (DB URL) 
    ↓
URL Parsing & Validation
    ↓
API Request to bahn.de
    ↓
Route & Station Extraction
    ↓
Price Matrix Generation (N² API calls)
    ↓
Dynamic Programming Optimization
    ↓
Results & Booking Links
```

## Rate Limiting & Performance

### Current Limitations:
- 0.5 second delay between API requests
- No proxy rotation or advanced rate limiting evasion
- Sequential processing of price queries

### Performance Characteristics:
- For N stations: O(N²) API calls required
- Processing time: ~(N² × 0.5) seconds
- Memory usage: O(N²) for price matrix storage

## Security Considerations

### Web Scraping Ethics:
- Simulates legitimate browser requests
- Respects rate limits to avoid server overload
- No attempt to bypass anti-bot measures
- Distributes load across individual user devices

### Data Privacy:
- No data stored on external servers
- All processing occurs locally
- No user tracking or analytics
- No authentication or user accounts required

## Error Handling

### Robust Failure Management:
- Network request timeouts and retries
- Invalid URL detection and user feedback
- Missing price data graceful degradation
- Connection failure recovery

### Logging & Debugging:
- Detailed console output for troubleshooting
- Step-by-step analysis progress reporting
- Clear error messages for common issues

## Deployment Architecture

### Advantages of Local Processing:
1. **No Server Costs**: Eliminates hosting and maintenance expenses
2. **Scalability**: Load distributed across user devices
3. **Privacy**: No central data collection point
4. **Reliability**: Not dependent on server uptime
5. **Rate Limit Avoidance**: Individual user requests less likely to be blocked

### Distribution Channels:
- GitHub Releases for Android APK
- Python package for CLI usage
- Source code for custom builds

## Code Quality Assessment

### Strengths:
- Clear separation of concerns
- Comprehensive error handling
- Well-documented API interactions
- User-friendly command-line interface

### Areas for Improvement:
- Limited unit test coverage
- Hard-coded API endpoints
- Minimal configuration options
- No caching mechanism for repeated queries

## Future Enhancement Opportunities

### Technical Improvements:
1. **Caching System**: Store pricing data to reduce API calls
2. **Parallel Processing**: Concurrent price queries where possible
3. **Proxy Support**: Advanced rate limiting evasion
4. **Configuration System**: User-customizable settings
5. **Test Coverage**: Comprehensive unit and integration tests

### Feature Additions:
1. **Historical Price Tracking**: Monitor price trends over time
2. **Schedule Integration**: Consider departure times in optimization
3. **Multi-passenger Support**: Group booking optimization
4. **Alternative Route Suggestions**: Compare different journey paths
5. **Notification System**: Alert users to price changes