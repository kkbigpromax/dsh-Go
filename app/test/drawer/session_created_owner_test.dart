import 'dart:async';

import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/session_created_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _host = HostRef.ssh('created-owner');
final _created = DateTime.fromMillisecondsSinceEpoch(1793000000000);

Map<String, Object?> _page(DateTime? at) => {
  'hasMore': false,
  'records': [
    if (at != null)
      {
        'event': {
          'seq': 0,
          'time': at.millisecondsSinceEpoch,
          'type': 'turn/start',
          'data': {'turn': 1},
        },
      },
  ],
};

class _Read {
  _Read(this.id);
  final String id;
  final answer = Completer<RpcResult>();
}

class _Carrier extends DshCarrier {
  final reads = <_Read>[];
  bool closed = false;
  late final client = DshClient.withCarrier(this);

  @override
  String get kind => 'controlled-created-time';
  @override
  DshTracer? get tracer => null;

  @override
  Future<RpcResult> call(String endpoint, Map<String, Object?> args, {Duration? timeout}) {
    if (closed) throw const DshClosedException('carrier closed');
    expect(endpoint, 'session/page');
    final request = args['request']! as Map;
    expect(request['throughSeq'], 0);
    expect(request['maxMessages'], 1);
    final address = request['address']! as Map;
    final read = _Read(address['sessionId']! as String);
    reads.add(read);
    return read.answer.future;
  }

  @override
  Future<DshMuxLink> openLink(MuxOptions options) => throw StateError('history does not open a stream');

  // Like ordinary HTTP close(force: false), closing prevents new calls but
  // does not replace the replies of already-started unary requests.
  @override
  Future<void> close() async => closed = true;
}

_Carrier _carrier() {
  final carrier = _Carrier();
  addTearDown(() {
    for (final read in carrier.reads) {
      if (!read.answer.isCompleted) read.answer.complete(RpcOk(_page(null)));
    }
  });
  return carrier;
}

class _Harness {
  _Harness(this.container, this.clients);
  final ProviderContainer container;
  final List<DshClient> clients;

  SessionCreatedController get controller => container.read(sessionCreatedProvider.notifier);
  Map<String, DateTime> get state => container.read(sessionCreatedProvider);

  static AsyncValue<HostConnection?> connection(DshClient client) =>
      AsyncData(HostConnection(client: client, isLocal: false, kind: HostKind.ssh, hostId: _host.id));

  static Future<_Harness> start(DshClient client) async {
    final container = ProviderContainer(overrides: [activeConnectionProvider.overrideWithValue(connection(client))]);
    container.read(activeHostProvider.notifier).select(_host);
    container.listen(sessionCreatedProvider, (_, _) {});
    final h = _Harness(container, [client]);
    addTearDown(() async {
      container.dispose();
      for (final client in h.clients) {
        await client.close();
      }
    });
    await h.flush();
    return h;
  }

  Future<void> flush() async {
    await container.pump();
    for (var i = 0; i < 16; i++) {
      await Future<void>.value();
    }
  }

  Future<void> replace(DshClient client) async {
    final before = controller;
    final previous = clients.last;
    clients.add(client);
    container.updateOverrides([activeConnectionProvider.overrideWithValue(connection(client))]);
    // SshHostLink publishes the new client, then gracefully closes the old
    // one. The real fetcher rebuilds while the host/cache key stays the same.
    await previous.close();
    await flush();
    expect(controller, same(before));
    expect(container.read(activeHostProvider), _host);
    expect(container.read(activeConnectionProvider).value!.client, same(client));
  }
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // Match main()'s warmed preferences; the regression is not a cold-store race.
    await SharedPreferences.getInstance();
  });

  test('a pending read may finish after disposal without starting another read', () async {
    final first = _carrier();
    final h = await _Harness.start(first.client);
    h.controller.ensure(['one', 'two', 'queued']);
    expect(first.reads, hasLength(2));
    h.container.dispose();
    for (final read in first.reads) {
      read.answer.complete(RpcOk(_page(_created)));
    }
    for (var i = 0; i < 16; i++) {
      await Future<void>.value();
    }
    expect(first.reads, hasLength(2));
  });
}
