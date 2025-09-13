# Better-Bahn Developer Contribution Guide

## Welcome Contributors! 🎉

Thank you for your interest in contributing to Better-Bahn! This guide will help you get started with development, testing, and submitting improvements to the project.

## Project Structure

```
Better-Bahn/
├── main.py                 # Python CLI tool (core logic)
├── pyproject.toml         # Python dependencies
├── uv.lock               # Dependency lock file
├── flutter-app/          # Mobile app source
│   ├── lib/main.dart     # Flutter app main file
│   ├── pubspec.yaml      # Flutter dependencies
│   └── android/          # Android build configuration
├── testing/              # Test utilities
├── assets/              # App icons and screenshots
├── docs/                # Documentation (technical, user guides)
└── README.md           # Main project description
```

## Development Environment Setup

### Prerequisites

#### Python Development
- **Python 3.12+** (check `.python-version`)
- **uv package manager** (recommended) or pip
- **Git** for version control

#### Flutter Development (for mobile app)
- **Flutter SDK 3.8.1+**
- **Android Studio** (for Android development)
- **Xcode** (for iOS development, if available)
- **VS Code** or **IntelliJ** with Flutter plugins

### Setup Instructions

#### 1. Clone the Repository
```bash
git clone https://github.com/gkrost/Better-Bahn.git
cd Better-Bahn
```

#### 2. Python Environment Setup
```bash
# Using uv (recommended)
uv sync

# Or using pip
pip install -r requirements.txt  # if requirements.txt exists
pip install requests>=2.32.4
```

#### 3. Flutter Environment Setup
```bash
cd flutter-app
flutter pub get
flutter doctor  # Check for any issues
```

#### 4. Test Your Setup
```bash
# Test Python CLI
python main.py --help

# Test Flutter app (with device/emulator connected)
cd flutter-app
flutter run
```

## Development Workflow

### Branch Management
1. **Fork** the repository on GitHub
2. **Clone** your fork locally
3. **Create** a feature branch: `git checkout -b feature/your-feature-name`
4. **Develop** your changes
5. **Test** thoroughly
6. **Commit** with clear messages
7. **Push** to your fork
8. **Create** a Pull Request

### Coding Standards

#### Python Code Style
- **PEP 8** compliance
- **Type hints** for function parameters and return values
- **Docstrings** for all functions and classes
- **Error handling** for all external API calls
- **Logging** instead of print statements where appropriate

```python
def get_connection_details(
    from_station_id: str, 
    to_station_id: str, 
    date: str, 
    departure_time: str,
    traveller_payload: list,
    deutschland_ticket: bool
) -> Optional[dict]:
    """
    Fetch connection details from Deutsche Bahn API.
    
    Args:
        from_station_id: Origin station ID
        to_station_id: Destination station ID
        date: Travel date in YYYY-MM-DD format
        departure_time: Departure time in HH:MM format
        traveller_payload: Traveler configuration data
        deutschland_ticket: Whether Deutschland-Ticket is available
        
    Returns:
        Connection data dictionary or None if request fails
        
    Raises:
        requests.RequestException: If API request fails
    """
    # Implementation here
```

#### Flutter Code Style
- **Dart style guide** compliance
- **Widget separation** - break complex widgets into smaller components
- **State management** - use appropriate state management patterns
- **Error handling** - graceful handling of network errors
- **Accessibility** - proper labels and semantic widgets

```dart
class ConnectionAnalysisWidget extends StatefulWidget {
  const ConnectionAnalysisWidget({
    Key? key,
    required this.url,
    required this.settings,
  }) : super(key: key);

  final String url;
  final UserSettings settings;

  @override
  State<ConnectionAnalysisWidget> createState() => 
      _ConnectionAnalysisWidgetState();
}
```

## Testing Guidelines

### Python Testing

#### Unit Tests (to be implemented)
```python
# tests/test_main.py
import unittest
from unittest.mock import patch, MagicMock
from main import get_connection_details, create_traveller_payload

class TestConnectionDetails(unittest.TestCase):
    @patch('main.requests.post')
    def test_get_connection_details_success(self, mock_post):
        # Test implementation
        pass
    
    def test_create_traveller_payload_bc25(self):
        result = create_traveller_payload(30, 'BC25_2')
        expected = [{"typ": "ERWACHSENER", ...}]
        self.assertEqual(result, expected)
```

#### Integration Tests
```python
# Test with actual API calls (use sparingly)
def test_real_api_integration():
    # Only for critical path testing
    pass
```

### Flutter Testing

#### Widget Tests
```dart
// test/widget_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:better_bahn/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const SplitTicketApp());
    expect(find.text('Better Bahn'), findsOneWidget);
  });
}
```

### Manual Testing Checklist

#### Python CLI Testing
- [ ] Help command works: `python main.py --help`
- [ ] Invalid URL handling: `python main.py "invalid-url"`
- [ ] Network error handling: Test with airplane mode
- [ ] BahnCard options: Test all BC25_1, BC25_2, BC50_1, BC50_2
- [ ] Deutschland-Ticket integration
- [ ] Age parameter variations

#### Flutter App Testing
- [ ] App builds and runs on Android
- [ ] URL input validation
- [ ] Settings persistence
- [ ] Network error handling
- [ ] Results display formatting
- [ ] Booking link functionality

## Common Development Tasks

### Adding New Features

#### 1. API Endpoint Changes
```python
# config.py (create if needed)
class APIConfig:
    BASE_URL = "https://www.bahn.de/web/api"
    ENDPOINTS = {
        'connection': '/angebote/verbindung',
        'timetable': '/angebote/fahrplan',
        'recon': '/angebote/recon'
    }
    RATE_LIMIT_DELAY = 0.5
```

#### 2. New Discount Types
```python
def create_traveller_payload(age: int, discount_option: str) -> list:
    """Extended to support new discount types"""
    # Add new discount mappings here
    pass
```

#### 3. Enhanced Error Handling
```python
import logging
from typing import Optional
from dataclasses import dataclass

@dataclass
class APIError:
    code: str
    message: str
    retryable: bool

def safe_api_call(func):
    """Decorator for robust API calls with retry logic"""
    def wrapper(*args, **kwargs):
        # Implementation with exponential backoff
        pass
    return wrapper
```

### Performance Improvements

#### 1. Caching Implementation
```python
from functools import lru_cache
import hashlib
import json

@lru_cache(maxsize=100)
def cached_connection_details(params_hash: str) -> Optional[dict]:
    """Cache connection details to avoid repeated API calls"""
    pass
```

#### 2. Parallel Processing
```python
import asyncio
import aiohttp

async def get_all_segments_parallel(segments: list) -> list:
    """Process multiple segments concurrently"""
    async with aiohttp.ClientSession() as session:
        tasks = [get_segment_data_async(session, segment) for segment in segments]
        return await asyncio.gather(*tasks, return_exceptions=True)
```

## Code Review Process

### Review Checklist

#### Functionality
- [ ] Code solves the intended problem
- [ ] Edge cases are handled
- [ ] Error conditions are managed
- [ ] Performance is acceptable

#### Code Quality
- [ ] Code is readable and well-documented
- [ ] Functions are appropriately sized
- [ ] Variable names are descriptive
- [ ] No code duplication

#### Testing
- [ ] Unit tests cover new functionality
- [ ] Integration tests pass
- [ ] Manual testing completed
- [ ] No regression in existing features

#### Security
- [ ] Input validation implemented
- [ ] No hardcoded secrets
- [ ] Network requests are safe
- [ ] Error messages don't leak sensitive info

### Review Guidelines

#### For Reviewers
1. **Be Constructive**: Provide specific, actionable feedback
2. **Ask Questions**: If something is unclear, ask for clarification
3. **Suggest Improvements**: Offer better approaches when possible
4. **Test Changes**: Actually run the code when reviewing

#### For Contributors
1. **Small PRs**: Keep changes focused and reviewable
2. **Clear Descriptions**: Explain what and why in PR description
3. **Address Feedback**: Respond to all review comments
4. **Update Documentation**: Keep docs in sync with code changes

## Debugging Tips

### Python Debugging
```python
# Add debug logging
import logging
logging.basicConfig(level=logging.DEBUG)

# Use pdb for interactive debugging
import pdb; pdb.set_trace()

# Mock API responses for testing
@patch('main.requests.post')
def test_with_mock(mock_post):
    mock_post.return_value.json.return_value = {"test": "data"}
    # Test your function
```

### Flutter Debugging
```dart
// Debug prints
debugPrint('Connection analysis started');

// Flutter inspector in VS Code
// Use hot reload for rapid iteration
// Check Flutter logs: flutter logs
```

### Network Debugging
```bash
# Monitor HTTP requests
mitmproxy  # Intercept and inspect requests

# Test API endpoints directly
curl -X POST "https://www.bahn.de/web/api/angebote/fahrplan" \
  -H "Content-Type: application/json" \
  -d '{"test": "payload"}'
```

## Contributing Guidelines

### What We're Looking For
- **Bug fixes** for existing functionality
- **Performance improvements** and optimization
- **New features** that align with project goals
- **Documentation** improvements and translations
- **Test coverage** additions
- **Code quality** improvements

### What We're Not Looking For
- **Major architecture changes** without prior discussion
- **Features** that compromise user privacy
- **Dependencies** that significantly increase app size
- **Changes** that break existing functionality

### Getting Your PR Accepted
1. **Discuss First**: For major changes, open an issue first
2. **Follow Guidelines**: Adhere to coding standards and testing requirements
3. **Document Changes**: Update relevant documentation
4. **Test Thoroughly**: Ensure changes work as expected
5. **Be Patient**: Allow time for review and iteration

## Release Process

### Version Management
- **Semantic Versioning**: MAJOR.MINOR.PATCH
- **Flutter**: Update `pubspec.yaml` version
- **Python**: Update `pyproject.toml` version
- **Git Tags**: Tag releases for easy tracking

### Release Checklist
- [ ] All tests pass
- [ ] Documentation updated
- [ ] Version numbers bumped
- [ ] Change log updated
- [ ] APK built and tested
- [ ] Release notes prepared
- [ ] Git tag created

## Getting Help

### Community Resources
- **GitHub Issues**: Report bugs and request features
- **GitHub Discussions**: Ask questions and share ideas
- **Code Review**: Get feedback on your contributions

### Mentorship
New contributors are welcome! Don't hesitate to:
- Ask questions in issues or discussions
- Request code review for learning
- Start with small, focused contributions
- Join the community and help others

## Recognition

Contributors are recognized through:
- **GitHub Contributors** list
- **Release notes** acknowledgments
- **Special thanks** in documentation
- **Community reputation** building

Thank you for contributing to Better-Bahn! Your efforts help thousands of travelers save money on their journeys. 🚄💰