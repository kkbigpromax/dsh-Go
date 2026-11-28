import 'dart:async';

import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/share_code/guest_fs.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/session_search.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../remote/support/ready_mux.dart';

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => _running('first');

  LocalRuntimeState _running(String token) => LocalRuntimeState(
    loaded: true,
    status: RuntimeStatus.fromMap({'phase': 'running', 'baseUrl': 'http://127.0.0.1:9', 'token': token}),
  );

  void reconnect() => state = _running('second');
}

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

class _Host extends ActiveHostController {
  @override
  HostRef build() => HostRef.local;
}

class _Mux extends ReadyMux {
  _Mux(this.gate);
  final Completer<MuxGeneration>? gate;
  @override
  Future<MuxGeneration> ready({Duration? timeout}) => gate?.future ?? super.ready(timeout: timeout);
}

class _Client extends DshClient {
  _Client({Completer<MuxGeneration>? readyGate})
    : _ready = _Mux(readyGate),
      super(DshConnection(Uri.parse('http://127.0.0.1:9')));
  final _Mux _ready;
  @override
  DshMux get mux => _ready;
  final queries = <String>[];
  final response = Completer<({List<ContentHit> items, bool hasMore})>();
  bool closed = false;

  @override
  Future<({List<ContentHit> items, bool hasMore})> searchSessionsPage(String query) {
    queries.add(query);
    if (closed) return Future.error(const DshTransportException('closed client'));
    return response.future;
  }

  @override
  Future<void> close() async {
    closed = true;
    await super.close();
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final transition in ['token', 'refresh', 'error']) {
    for (final inFlight in [false, true]) {
      testWidgets('$transition retires ${inFlight ? 'in-flight' : 'debounced'} search', (tester) async {
        final old = _Client();
        final next = _Client();
        final connector = Completer<DshClient>();
        var attempts = 0;
        final c = ProviderContainer(
          retry: (_, _) => null,
          overrides: [
            activeHostProvider.overrideWith(_Host.new),
            settingsProvider.overrideWith(_Settings.new),
            localRuntimeProvider.overrideWith(_Runtime.new),
            networkKicksProvider.overrideWithValue(const Stream.empty()),
            guestFsProvider.overrideWith((ref) async => null),
            localClientConnectorProvider.overrideWithValue(
              ({required baseUri, required token}) async => ++attempts == 1 ? old : await connector.future,
            ),
          ],
        );
        addTearDown(() async {
          if (!connector.isCompleted) connector.complete(next);
          for (final client in [old, next]) {
            if (!client.response.isCompleted) client.response.complete((items: <ContentHit>[], hasMore: false));
          }
          c.dispose();
          await old.close();
          await next.close();
        });
        c.listen(sessionSearchProvider, (_, _) {});
        await tester.pump(Duration.zero);
        expect(c.read(activeConnectionProvider).value?.client, same(old));
        c.read(sessionSearchProvider.notifier).setInput(const TextEditingValue(text: 'first query'));
        if (inFlight) await tester.pump(SessionSearchController.debounce);
        expect(old.queries, inFlight ? ['first query'] : isEmpty);

        if (transition == 'refresh') {
          c.invalidate(localConnectionProvider);
        } else {
          (c.read(localRuntimeProvider.notifier) as _Runtime).reconnect();
        }
        await tester.pump(Duration.zero);
        expect(attempts, 2);
        expect(old.closed, isTrue);
        expect(c.read(localConnectionProvider).isLoading, isTrue);
        // Riverpod retains this value; consumers must not treat it as a current client.
        expect(c.read(localConnectionProvider).value?.client, same(old));
        expect(c.read(sessionContentSearchProvider), isNull);
        expect(c.read(activeConnectionProvider), same(c.read(localConnectionProvider)));
        expect(c.read(sessionSearchProvider).content, ContentSearchStatus.idle);

        old.response.complete((items: [(sessionId: 'old', snippet: 'late')], hasMore: true));
        await tester.pump(Duration.zero);
        expect(c.read(sessionSearchProvider).hits, isEmpty);
        c.read(sessionSearchProvider.notifier).setInput(const TextEditingValue(text: 'current query'));
        await tester.pump(SessionSearchController.debounce);
        expect(old.queries, inFlight ? ['first query'] : isEmpty);
        expect(next.queries, isEmpty);

        if (transition == 'error') {
          connector.completeError(const DshTransportException('reconnect failed'));
          await tester.pump(Duration.zero);
          expect(c.read(localConnectionProvider).hasError, isTrue);
          expect(c.read(localConnectionProvider).value?.client, same(old));
          expect(c.read(activeConnectionProvider).hasError, isTrue);
          expect(c.read(activeConnectionProvider), same(c.read(localConnectionProvider)));
          expect(c.read(sessionContentSearchProvider), isNull);
          expect(c.read(sessionSearchProvider).hits, isEmpty);
          return;
        }
        connector.complete(next);
        await tester.pump(Duration.zero);
        await tester.pump(SessionSearchController.debounce);
        expect(next.queries, ['current query']);
        next.response.complete((items: [(sessionId: 'current', snippet: 'current query')], hasMore: false));
        await tester.pump(Duration.zero);
        expect(c.read(sessionSearchProvider).hits.single.sessionId, 'current');
        expect(c.read(sessionSearchProvider).content, ContentSearchStatus.ready);
      });
    }
  }

  testWidgets('HTTP search remains available before this client mux is ready', (tester) async {
    final ready = Completer<MuxGeneration>();
    final client = _Client(readyGate: ready);
    final c = ProviderContainer(
      overrides: [
        activeHostProvider.overrideWith(_Host.new),
        settingsProvider.overrideWith(_Settings.new),
        localRuntimeProvider.overrideWith(_Runtime.new),
        networkKicksProvider.overrideWithValue(const Stream.empty()),
        guestFsProvider.overrideWith((ref) async => null),
        localClientConnectorProvider.overrideWithValue(({required baseUri, required token}) async => client),
      ],
    );
    addTearDown(() async {
      if (!ready.isCompleted) ready.complete(const MuxGeneration(1, 'fixture', '/tmp'));
      if (!client.response.isCompleted) client.response.complete((items: <ContentHit>[], hasMore: false));
      c.dispose();
      await client.close();
    });
    c.listen(sessionSearchProvider, (_, _) {});
    await tester.pump(Duration.zero);
    expect(ready.isCompleted, isFalse);
    expect(c.read(activeConnectionProvider).value?.client, same(client));
    c.read(sessionSearchProvider.notifier).setInput(const TextEditingValue(text: 'http ready'));
    await tester.pump(SessionSearchController.debounce);
    expect(client.queries, ['http ready']);
    client.response.complete((items: [(sessionId: 'http', snippet: 'http ready')], hasMore: false));
    await tester.pump(Duration.zero);
    expect(c.read(sessionSearchProvider).hits.single.sessionId, 'http');
    ready.complete(const MuxGeneration(1, 'fixture', '/tmp'));
    await tester.pump(Duration.zero);
    expect(client.queries, ['http ready']);
  });
}
