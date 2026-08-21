import 'dart:async';
import 'dart:convert';

import 'package:besser_bahn/core/constants.dart';
import 'package:besser_bahn/core/user_agent_client.dart';
import 'package:besser_bahn/services/traewelling_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Träwelling gates its whole surface on an identifiable `User-Agent` and
/// answers 403 "No identifiable User-Agent provided" without one — which is
/// exactly how the login broke in #34: the token exchange sent no UA, so Dart
/// filled in its default `Dart/x (dart:io)`, which Träwelling also rejects.
///
/// The 403 body Träwelling really sends (captured live from traewelling.de).
const _uaRejection =
    'No identifiable User-Agent provided. Please read the API guidelines: '
    'https://traewelling.de/settings/applications';

/// Fails the request the way Träwelling does when the UA is missing or generic,
/// so these tests reproduce the bug rather than merely asserting a header.
/// Mirrors the live behaviour measured against the real API.
bool _isRejectedUa(String? ua) =>
    ua == null ||
    ua.isEmpty ||
    ua.startsWith('Dart/') ||
    ua.startsWith('curl/') ||
    ua.startsWith('python-requests/');

http.Response _gate(http.BaseRequest req, http.Response ok) =>
    _isRejectedUa(req.headers['user-agent'])
    ? http.Response(_uaRejection, 403)
    : ok;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('UserAgentClient', () {
    test('sets the User-Agent on requests that lack one', () async {
      String? seen;
      final client = UserAgentClient(
        MockClient((req) async {
          seen = req.headers['user-agent'];
          return http.Response('{}', 200);
        }),
        'TestAgent/1.0',
      );

      await client.get(Uri.parse('https://example.org/'));

      expect(seen, 'TestAgent/1.0');
    });

    test('does not override an explicit User-Agent, in any casing', () async {
      String? seen;
      final client = UserAgentClient(
        MockClient((req) async {
          seen = req.headers['user-agent'];
          return http.Response('{}', 200);
        }),
        'TestAgent/1.0',
      );

      await client.get(
        Uri.parse('https://example.org/'),
        headers: {'User-Agent': 'Explicit/9.9'},
      );

      expect(seen, 'Explicit/9.9');
    });

    test('applies to every verb, not just GET', () async {
      final seen = <String, String?>{};
      final client = UserAgentClient(
        MockClient((req) async {
          seen[req.method] = req.headers['user-agent'];
          return http.Response('{}', 200);
        }),
        'TestAgent/1.0',
      );

      final uri = Uri.parse('https://example.org/');
      await client.get(uri);
      await client.post(uri, body: 'x');
      await client.put(uri, body: 'x');
      await client.delete(uri);

      expect(seen, {
        'GET': 'TestAgent/1.0',
        'POST': 'TestAgent/1.0',
        'PUT': 'TestAgent/1.0',
        'DELETE': 'TestAgent/1.0',
      });
    });
  });

  group('AppConstants.userAgent identifies the app (#34)', () {
    test('names the app, its version and a contact URL', () {
      expect(AppConstants.userAgent, startsWith('BesserBahn/'));
      expect(AppConstants.userAgent, contains(AppConstants.appVersion));
      expect(
        AppConstants.userAgent,
        contains('https://github.com/chuk-development/Besser-Bahn'),
      );
    });

    test('is not a generic UA Träwelling would reject', () {
      expect(_isRejectedUa(AppConstants.userAgent), isFalse);
    });

    test('does not masquerade as a browser', () {
      // Träwelling lets a browser UA through, but their guidelines ask who is
      // using their resources — sneaking past the filter would defeat the point.
      expect(AppConstants.userAgent, isNot(contains('Mozilla')));
      expect(AppConstants.userAgent, isNot(contains('AppleWebKit')));
      expect(AppConstants.userAgent, isNot(ApiConstants.userAgent));
    });
  });

  group('TraewellingService sends the UA on every route (#34)', () {
    setUp(
      () => FlutterSecureStorage.setMockInitialValues({
        'trwl_access_token': 'access-token',
        'trwl_refresh_token': 'refresh-token',
      }),
    );

    test('API requests carry the identifying UA', () async {
      String? seen;
      final svc = TraewellingService(
        client: MockClient((req) async {
          seen = req.headers['user-agent'];
          return _gate(
            req,
            http.Response(
              json.encode({
                'data': {'id': 1},
              }),
              200,
            ),
          );
        }),
      );

      await svc.currentUser();

      expect(seen, AppConstants.userAgent);
    });

    test(
      'the token endpoint carries the UA — the request that broke',
      () async {
        // Drive the refresh grant: it posts to the same /oauth/token endpoint,
        // through the same client, as the authorization-code exchange that #34
        // reported failing (that one needs a real browser code to reach).
        final tokenUas = <String?>[];
        var calls = 0;
        final svc = TraewellingService(
          client: MockClient((req) async {
            calls++;
            if (req.url.path.contains('/oauth/token')) {
              tokenUas.add(req.headers['user-agent']);
              return _gate(
                req,
                http.Response(
                  json.encode({
                    'access_token': 'fresh',
                    'refresh_token': 'fresh-refresh',
                    'expires_in': 3600,
                  }),
                  200,
                ),
              );
            }
            // First API call 401s, forcing the refresh; the retry succeeds.
            if (calls == 1) return http.Response('', 401);
            return _gate(
              req,
              http.Response(
                json.encode({
                  'data': {'id': 1},
                }),
                200,
              ),
            );
          }),
        );

        final user = await svc.currentUser();

        expect(tokenUas, [
          AppConstants.userAgent,
        ], reason: 'the token exchange must identify itself');
        expect(user, isNotNull, reason: 'refresh + retry should succeed');
      },
    );

    test(
      'reproduces #34: without the UA Träwelling 403s the token exchange',
      () async {
        // Guards the gate itself: strip the UA and the very failure the issue
        // reported comes back, proving these tests would catch a regression.
        final bare = MockClient(
          (req) async => _gate(
            req,
            http.Response(
              json.encode({
                'data': {'id': 1},
              }),
              200,
            ),
          ),
        );

        final res = await bare.post(
          Uri.parse(TraewellingConstants.tokenUrl),
          headers: {'Accept': 'application/json'},
        );

        expect(res.statusCode, 403);
        expect(res.body, contains('No identifiable User-Agent'));
      },
    );
  });

  // A valid session must survive a transient /auth/user failure on startup —
  // a flaky network must never silently log the user out (#39).
  group('session survives transient failures (#39)', () {
    setUp(
      () => FlutterSecureStorage.setMockInitialValues({
        'trwl_access_token': 'access-token',
        'trwl_refresh_token': 'refresh-token',
      }),
    );

    test('currentUser caches the profile for offline restore', () async {
      final svc = TraewellingService(
        client: MockClient((req) async {
          return http.Response(
            json.encode({
              'data': {'id': 7, 'username': 'stefan', 'displayName': 'Stefan'},
            }),
            200,
          );
        }),
      );

      final live = await svc.currentUser();
      expect(live!.username, 'stefan');

      // The next process can read the profile straight from storage.
      final cached = await svc.cachedUser();
      expect(cached, isNotNull);
      expect(cached!.username, 'stefan');
      expect(cached.id, 7);
    });

    test('a timing-out /auth/user does NOT clear the session', () async {
      final svc = TraewellingService(
        client: MockClient((req) async {
          throw TimeoutException('slow network');
        }),
      );

      // The call surfaces an error…
      await expectLater(svc.currentUser(), throwsA(isA<Object>()));
      // …but the token is untouched, so we're still logged in.
      expect(await svc.hasSession(), isTrue);
    });

    test(
      'a genuine 401 with no refreshable token clears the session',
      () async {
        // No refresh token available → the 401 is terminal and must log out.
        FlutterSecureStorage.setMockInitialValues({
          'trwl_access_token': 'stale-token',
        });
        final svc = TraewellingService(
          client: MockClient((req) async => http.Response('', 401)),
        );

        await expectLater(
          svc.currentUser(),
          throwsA(
            isA<TraewellingException>().having((e) => e.status, 'status', 401),
          ),
        );
        expect(await svc.hasSession(), isFalse);
      },
    );
  });
}
