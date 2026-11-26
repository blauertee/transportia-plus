import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/services/server_capabilities_service.dart';

/// `/map/initial` from the capture, as a server with [motisVersion] would
/// answer it.
String _initial(String motisVersion) {
  final json =
      jsonDecode(
            File(
              'test/fixtures/transitous/map_initial.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  (json['serverConfig'] as Map<String, dynamic>)['motisVersion'] = motisVersion;
  return jsonEncode(json);
}

/// Holds every request until the test answers it, in whatever order.
class _Server {
  _Server() {
    TransitousClient.instance = TransitousClient(
      httpClient: MockClient((request) {
        final answer = Completer<http.Response>();
        _pending.add(answer);
        return answer.future;
      }),
    );
  }

  final List<Completer<http.Response>> _pending = [];

  int get requests => _pending.length;

  void answer(int request, String motisVersion) => _pending[request].complete(
    http.Response(
      _initial(motisVersion),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Server server;

  setUp(() {
    ServerCapabilitiesService.invalidate();
    server = _Server();
  });
  tearDown(() => TransitousClient.instance = TransitousClient());

  test('answers with what the server says', () async {
    final loading = ServerCapabilitiesService.ensureLoaded();
    await _settle();
    server.answer(0, 'v-only');

    expect((await loading).motisVersion, 'v-only');
    expect(ServerCapabilitiesService.isLoaded, isTrue);
  });

  group('a load the cache was dropped under', () {
    test('finishing after the new one, does not overwrite it', () async {
      final old = ServerCapabilitiesService.ensureLoaded();
      await _settle();
      final fresh = ServerCapabilitiesService.refresh();
      await _settle();
      expect(server.requests, 2);

      server.answer(1, 'v-new');
      await fresh;
      server.answer(0, 'v-old');
      await old;

      expect(
        ServerCapabilitiesService.capabilities.value.motisVersion,
        'v-new',
      );
      expect(ServerCapabilitiesService.isLoaded, isTrue);
    });

    test(
      'finishing first, is discarded and leaves the new one in flight',
      () async {
        final old = ServerCapabilitiesService.ensureLoaded();
        await _settle();
        final fresh = ServerCapabilitiesService.refresh();
        await _settle();

        server.answer(0, 'v-old');
        await old;

        // The old server's limits never show, and nothing counts as loaded.
        expect(
          ServerCapabilitiesService.capabilities.value.motisVersion,
          isNot('v-old'),
        );
        expect(ServerCapabilitiesService.isLoaded, isFalse);

        // Another caller joins the load still running rather than starting a
        // third.
        final joined = ServerCapabilitiesService.ensureLoaded();
        await _settle();
        expect(server.requests, 2);

        server.answer(1, 'v-new');
        expect((await fresh).motisVersion, 'v-new');
        expect((await joined).motisVersion, 'v-new');
      },
    );

    test('by invalidate, leaves the fallback in place', () async {
      final old = ServerCapabilitiesService.ensureLoaded();
      await _settle();
      ServerCapabilitiesService.invalidate();

      server.answer(0, 'v-old');
      await old;

      expect(
        ServerCapabilitiesService.capabilities.value.motisVersion,
        isNot('v-old'),
      );
      expect(ServerCapabilitiesService.isLoaded, isFalse);
    });
  });
}
