# Better-Bahn User Guide

## What is Better-Bahn?

Better-Bahn is a free, open-source application that helps you save money on Deutsche Bahn (German Railway) journeys by finding cheaper split-ticket combinations. Instead of buying one expensive direct ticket, the app analyzes your route and suggests buying multiple cheaper tickets that cover the same journey.

## How It Works

### The Split-Ticket Concept

When traveling from A to C via B, sometimes it's cheaper to buy:
- One ticket from A to B
- Another ticket from B to C

Rather than a single direct ticket from A to C.

Better-Bahn automatically:
1. Analyzes your planned journey
2. Checks prices for all possible ticket combinations
3. Finds the cheapest option
4. Provides direct booking links

### Example Savings

**Traditional booking**: Berlin → Munich = €89.90
**Split-ticket option**: 
- Berlin → Nuremberg = €29.90
- Nuremberg → Munich = €19.90
- **Total: €49.80 (Save €40.10!)**

## Installation

### Mobile App (Android)

1. Go to the [GitHub Releases page](https://github.com/gkrost/Better-Bahn/releases)
2. Download the latest `.apk` file
3. Install on your Android device
4. Allow installation from unknown sources if prompted

### Python CLI Tool

**Prerequisites**: Python 3.12+ installed on your system

1. Clone or download the repository
2. Navigate to the project directory
3. Run commands using: `python main.py [options] <url>`

#### Quick Start:
```bash
# Basic usage
python main.py "https://www.bahn.de/buchung/start?vbid=YOUR_LINK_HERE"

# With BahnCard 25, 2nd class
python main.py --bahncard BC25_2 "YOUR_DB_LINK"

# With Deutschland-Ticket
python main.py --deutschland-ticket "YOUR_DB_LINK"

# Custom age and full options
python main.py --age 25 --bahncard BC50_1 --deutschland-ticket "YOUR_DB_LINK"
```

## Using the App

### Step 1: Get Your Journey Link

#### From DB Navigator App:
1. Plan your journey in the DB Navigator app
2. Look for the "Share" or "Teilen" button
3. Copy the link (starts with `https://www.bahn.de/`)

#### From bahn.de Website:
1. Search for your journey on bahn.de
2. Select your preferred connection
3. Copy the URL from your browser's address bar

### Step 2: Configure Your Settings

#### BahnCard Options:
- **BC25_1**: BahnCard 25, 1st class
- **BC25_2**: BahnCard 25, 2nd class  
- **BC50_1**: BahnCard 50, 1st class
- **BC50_2**: BahnCard 50, 2nd class

#### Deutschland-Ticket:
- Check this option if you have a Deutschland-Ticket
- The app will automatically set regional transport segments to €0

#### Age Setting:
- Some discounts are age-dependent
- Default is 30 years old

### Step 3: Analyze Your Journey

1. Paste your DB link into the app
2. Select your BahnCard type (if applicable)
3. Enable Deutschland-Ticket option (if applicable)
4. Tap "Analyze Connection" / "Verbindung analysieren"

### Step 4: Review Results

The app will show:
- **Direct ticket price**: Cost of booking the journey as one ticket
- **Split-ticket price**: Cost of the optimized combination
- **Savings amount**: How much money you'll save
- **Recommended tickets**: List of individual tickets to buy

### Step 5: Book Your Tickets

For each recommended ticket:
1. Tap the provided booking link
2. You'll be redirected to bahn.de with the exact journey pre-filled
3. Complete your purchase as normal
4. Repeat for each ticket segment

## Supported Link Types

### Short Links (vbid):
```
https://www.bahn.de/buchung/start?vbid=abc123-def456-ghi789
```

### Long Links:
```
https://www.bahn.de/buchung/fahrplan/suche#sts=true&so=Berlin&zo=Munich&soid=8011160&zoid=8000261&hd=2024-03-15T08:30&dltv=false
```

## Tips for Maximum Savings

### 1. Flexible Travel Times
- Split-ticket opportunities vary by time of day
- Try different departure times to find better deals

### 2. Route Selection
- Longer routes with more intermediate stations offer more split opportunities
- Consider alternative routes through different cities

### 3. Advance Booking
- Like regular tickets, split-tickets are often cheaper when booked in advance
- Prices can change, so book promptly when you find savings

### 4. BahnCard Integration
- The app automatically applies your BahnCard discount to each segment
- Sometimes split-tickets + BahnCard offer even greater savings

## Important Considerations

### Legal Compliance
- Split-tickets are completely legal and comply with DB terms of service
- You're simply buying multiple valid tickets for your journey
- No "hacking" or terms violation involved

### Ticket Validity
- Each ticket is valid for its specific segment
- Make sure you have all tickets when traveling
- Show the appropriate ticket for each segment to conductors

### Transfer Handling
- You don't need to exit and re-enter stations at transfer points
- Stay on the same train if it continues your journey
- Only change tickets when you actually change trains

### Connection Risks
- If you miss a connection due to delays, later tickets may become invalid
- Consider travel insurance for valuable journeys
- DB's delay compensation still applies to individual tickets

## Troubleshooting

### "No cheaper option found"
- Split-tickets aren't always available
- Try different times or alternative routes
- Direct tickets are sometimes genuinely the best deal

### "Could not retrieve connection details"
- Check your internet connection
- Verify the DB link is complete and valid
- The bahn.de servers might be temporarily unavailable

### App crashes or errors
- Ensure you're using the latest version
- Try a different DB link to isolate the issue
- Report bugs on the GitHub issues page

### Rate limiting / "Too many requests"
- The app includes delays to avoid overwhelming DB servers
- If blocked, wait a few minutes before retrying
- Consider using the app during off-peak hours

## Privacy & Security

### Local Processing
- All analysis happens on your device
- No data is sent to external servers (except bahn.de for price queries)
- No user accounts or tracking

### Data Usage
- The app makes multiple requests to bahn.de to gather pricing data
- Each analysis requires 1 request per possible route segment
- For N stations, expect up to N² requests

### No Data Collection
- Better-Bahn doesn't collect personal information
- No analytics or telemetry
- No advertising or monetization

## Getting Help

### Community Support
- GitHub Issues: Report bugs or request features
- Discussions: Ask questions and share experiences
- Wiki: Community-contributed tips and guides

### Self-Help
- Check this user guide for common questions
- Review the technical documentation for advanced usage
- Examine the source code - it's open source!

## Contributing

Better-Bahn is open source and welcomes contributions:
- Report bugs through GitHub Issues
- Suggest features or improvements
- Submit code improvements via Pull Requests
- Help translate the app to other languages
- Share your savings stories to help others

## Legal Disclaimer

Better-Bahn is an unofficial tool not affiliated with Deutsche Bahn AG. Use at your own risk. Always verify ticket validity and compliance with current DB terms of service. The developers are not responsible for any issues arising from split-ticket bookings.