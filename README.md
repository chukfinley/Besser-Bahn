# Besser Bahn

[![Flutter CI](https://github.com/YousefAbaas/Besser-Bahn/actions/workflows/flutter-ci.yml/badge.svg)](https://github.com/YousefAbaas/Besser-Bahn/actions/workflows/flutter-ci.yml)

**Privacy-first railway companion for Germany, built with Flutter.**

Besser Bahn is a privacy-focused mobile application for frequent railway travelers in Germany. It combines journey planning, live departure information, real-time disruption data, maps, connection reliability, split-ticket analysis, and optional DB account integration in a single Flutter application.

The application is designed to work without tracking, advertising, or a mandatory account.

<p align="center">
  <img src="assets/app_icon.png" width="100" alt="Besser Bahn app icon" />
</p>

## Engineering Snapshot

| Area             | Technology / Approach                                 |
| ---------------- | ----------------------------------------------------- |
| Mobile           | Flutter / Dart                                        |
| State management | Riverpod                                              |
| Navigation       | GoRouter                                              |
| Networking       | REST / HTTP integrations                              |
| Maps             | OpenStreetMap-based mapping                           |
| Local data       | Local persistence and offline caching                 |
| Testing          | Flutter unit and widget tests                         |
| CI               | GitHub Actions                                        |
| Architecture     | Service / provider / model-based Flutter architecture |

## Quality Status

The current codebase has been validated as a clean quality milestone.

| Check             | Result             |
| ----------------- | ------------------ |
| `flutter analyze` | ✅ No issues found  |
| `flutter test`    | ✅ 857 tests passed |
| Quality release   | `v0.1.0-quality`   |

The `v0.1.0-quality` release provides a stable baseline for continued development.

## Features

### 🔎 Journey Search

* Connection search between two stations with station autocomplete.
* Supports **coordinates and map links** as origins or destinations (`53.43, 14.53`, `geo:`, OpenStreetMap, Organic Maps, and Google Maps links) with nearby station resolution.
* Detailed multi-leg connections including transfers, platforms, stops, and real-time delays.
* **Connection and punctuality badges** for transfers, calculated using a self-hosted prediction model.
* Sorting by **reliability**, rather than only by duration.
* Highlights for **fastest, cheapest, and most reliable** connections.

### 🔔 Live Journey Monitoring

Per-journey monitoring can be enabled or disabled from the connection view.

When enabled, the application can notify the user about:

* Significant delay changes.
* Platform changes at the user's station.
* Train cancellations.
* At-risk connections.
* Arrival reminders.
* Optional GPS-based exit alerts.

#### Connection Rescue

When a transfer becomes unlikely, Besser Bahn can calculate the next reachable connection based on the live arrival of the incoming train.

The app can then suggest switching to the next viable connection and show the resulting impact on the journey.

The monitoring workflow runs locally on the device without a server that tracks the user's journey.

### 🚉 Station

A combined station area provides:

* **Train** — detailed information for an individual service, including stops, platforms, and delays.
* **Departures** — live departure board with map support.
* **Map** — interactive station map with platforms, elevators, and points of interest.

### 🧭 Maps & Live Data

* Exact track polylines based on DB-provided route geometry.
* German basemap using BKG TopPlus-Open.
* Offline map-tile caching on the device.
* **Coach sequence and available seats** with carriage and seat-map information where available.
* **Split-train detection** to identify the train section passengers should board.
* Current location and nearby stations using GPS.

### 💶 Split-Ticket Analysis

* Finds potentially cheaper ticket combinations for a selected connection.
* Supports **BahnCard 25/50**, first/second class, and **Deutschlandticket** scenarios.
* Provides direct booking links for individual ticket segments.
* Sends a local notification when analysis is complete.

### 👤 Optional DB Account

The application can optionally connect to a user's DB account.

The account integration supports:

* **My Tickets** — booked tickets including barcode presentation for inspection.
* **BahnCard** — card and inspection views with offline availability.
* **BahnBonus** — points and status information.
* **Saved journeys** — synchronization with journeys saved in the DB account.
* OAuth2 with **PKCE**, without storing the user's DB password in the application.

The DB account is completely optional; the rest of the application remains usable without an account.

## My Contributions

As a contributor to Besser Bahn, I worked on reliability, API integration, testing, Flutter tooling, and journey-search infrastructure.

### Flutter Upgrade

* Upgraded the application to **Flutter 3.44.3**.
* Stabilized affected application and test code across the Flutter upgrade.
* Verified the migration with static analysis and the automated test suite.
* Kept generated platform files and IDE artifacts out of feature changes.

## DB Vendo API Investigation

A significant part of the Besser Bahn work involved integrating and validating
the DB Navigator mobile backend (Vendo) using real production responses.

Rather than relying exclusively on mocked fixtures, the integration was
validated with dedicated live probes to verify undocumented response structures
before mapping them into the application's domain models.

### Validated Vendo capabilities

### Journey Search & Offline Caching

* Improved Riverpod-based journey-search state and provider integration.
* Added offline caching for journey search results.
* Added JSON serialization and deserialization for cached journey results.
* Improved arrival-time searches, transport filters, transfer constraints, and journey sorting.
* Added progressive loading of earlier and later connections.
* Added fallback handling for relaxed transfer constraints when the initial search produces no connections.

### Testing & CI

* Added a GitHub Actions workflow for automated Flutter analysis and tests.
* CI runs for relevant Flutter application changes on `main`, `chore/**`, and pull requests.
* Added and maintained tests covering journey search, rerouting, transfer information, walking routes, station search, address search, split-ticket data, and related services.
* Verified the current codebase with **857 automated tests passing** and clean Flutter analysis.


* **Journey search:** validated real journey responses and extracted stable
  `zuglaufId` values for individual train runs.
* **Zuglauf details:** validated the `/mob/zuglauf/{zuglaufId}` endpoint against
  real ICE and regional train runs.
* **Track polylines:** verified that Vendo returns detailed route geometry via
  `polylineGroup.polylineDesc[].coordinates`.
* **Real train example:** ICE 953 from Köln Hbf to Berlin Hbf returned **1,274
  polyline points**, from approximately Köln (50.943038, 6.959700) to Berlin
  (52.525841, 13.368874).
* **Regional train example:** S6 train 30691 from Köln Hbf to Köln Messe/Deutz
  returned **287 polyline points**.
* **Stop data:** validated real stop-level data including stations, planned
  platforms, realtime platforms, occupancy information, and arrival/departure
  timestamps.
* **Schedule metadata:** verified that `fahrplan.regulaererFahrplan` is not
  guaranteed to be a structured object; for some real trains DB returns a
  string such as `nicht täglich`. The parser therefore handles the upstream
  type defensively.
* **Occupancy data:** verified that `auslastungsInfos` can contain separate
  first- and second-class entries with DB-provided availability text.
* **Best-price endpoint:** validated daily price intervals, DB's
  `istBestpreis` flag, connection contexts, price-less intervals, and
  part-trip prices.

### Validation approach

The live investigation was performed with isolated Flutter test probes rather
than changing production behavior blindly.

The probes were used to:

1. obtain real journey responses from the Vendo backend;
2. extract real `zuglaufId` values;
3. request individual train runs through the Vendo `zuglauf` endpoint;
4. inspect the actual response structure and runtime types;
5. validate parsing against both long-distance and regional trains;
6. verify the returned polyline geometry and stop metadata;
7. convert the discovered behavior into deterministic automated tests.

This approach helped distinguish documented assumptions from behavior actually
observed in the upstream production API.

### Real-world Zuglauf validation

Live Zuglauf responses were successfully retrieved and parsed for real
connections including:

**ICE 953 — Köln Hbf → Berlin Hbf**

- 8 stops
- Real `zuglaufId`
- Platform information
- Occupancy information for both classes
- Service-day metadata
- 1,274 route-polyline points

The route geometry was parsed from Vendo's response structure:

```text
polylineGroup
└── polylineDesc
    └── coordinates
### Engineering Practices
* Used focused commits describing individual engineering changes.
* Kept generated platform files and IDE-specific files out of feature commits.
* Used `git diff --check` and staged-diff inspection before committing.
* Validated changes with static analysis and automated tests before pushing to `main`.
* Maintained a tagged quality milestone with `v0.1.0-quality`.

> This repository demonstrates practical work on an existing Flutter codebase: understanding unfamiliar services, modifying API integrations, maintaining tests, upgrading dependencies, implementing offline caching, and validating changes through CI.

## Development

### Prerequisites

* Flutter SDK
* Dart SDK
* Android Studio or another Flutter-compatible IDE

### Run locally

```bash
flutter pub get
flutter run
```

### Verify the project

```bash
flutter analyze
flutter test
```

## CI

The project uses GitHub Actions to automatically validate Flutter changes.

The CI workflow runs static analysis and the automated test suite for relevant branches and pull requests.

## Quality Release

### `v0.1.0-quality`

This release represents a verified quality milestone for the project.

Highlights:

* Clean Flutter analyzer result.
* 857 automated tests passing.
* Improved journey-search provider integration.
* Offline journey-result caching.
* Journey-result JSON serialization.
* Improved DB / Vendo API handling.
* Improved Riverpod provider integration.

## Roadmap

* Continue improving journey reliability prediction.
* Expand offline capabilities.
* Improve live disruption and connection-rescue workflows.
* Continue strengthening automated test coverage.
* Improve platform-specific UX and accessibility.

## License

See the repository license for the current licensing terms.
