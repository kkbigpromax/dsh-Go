import 'dart:async';

import 'package:dsh_app/diagnostics/diagnostics_bundle.dart';
import 'package:dsh_app/diagnostics/app_error_log.dart';
import 'package:dsh_app/diagnostics/diagnostics_channel.dart';
import 'package:dsh_app/remote/link_status.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _privateError = HostLinkError(
  HostLinkErrorKind.dshTimeout,
  'secret-host.example',
  detail: 'token=private-token SHA256:private-fingerprint',
);

class _Runtime extends LocalRuntimeController {
  @override
  LocalRuntimeState build() => const LocalRuntimeState(loaded: true);
}

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

class _Bridge extends RuntimeBridge {
  @override
  Stream<RuntimeEvent> get events => const Stream.empty();
  @override
  Future<List<String>> logs({int lines = 500}) async => const [];
}

class _Channel extends DiagnosticsChannel {
  @override
  Future<NativeDiagnostics> info() async => const NativeDiagnostics();
  @override
  Future<List<String>> engineLog({int maxBytes = 512 * 1024}) async => const [];
}

class _Active extends ActiveHostController {
  _Active(this.host);
  final HostRef host;
  @override
  HostRef build() => host;
  void change(HostRef next) => state = next;
}

class _Link implements HostLink {
  _Link();
  final HostLinkStep step = HostLinkStep.startDsh;
  final HostLinkErrorKind errorKind = HostLinkErrorKind.dshTimeout;
  final changes = StreamController<HostLinkStatus>.broadcast(sync: true);
  HostLinkStatus? next;
  int opens = 0;

  @override
  HostLinkStatus get status =>
      next ??
      HostLinkStatus(
        HostLinkPhase.reconnecting,
        step: step,
        attempt: 2,
        error: HostLinkError(errorKind, 'secret-host.example', detail: 'SHA256:private-fingerprint', retryable: true),
        detail: 'secret-host.example token=private-token',
      );
  void emit(HostLinkStatus status) {
    next = status;
    changes.add(status);
  }

  @override
  DshClient? get currentClient => null;
  @override
  Stream<DshClient> get clients => const Stream.empty();
  @override
  Stream<HostLinkStatus> get statuses => changes.stream;
  @override
  Future<DshClient> open() async {
    opens++;
    throw _privateError;
  }

  @override
  void kick() {}
  @override
  void retry() {}
  @override
  Future<void> close() async => changes.close();
}

Future<DiagnosticsSnapshot> collect(ProviderContainer c) =>
    c.read(FutureProvider((ref) => collectDiagnostics(ref, DateTime.utc(2026))).future);

void main() {
  for (final host in [HostRef.local]) {
    test('exporting diagnostics does not initialize an unobserved ${host.kind.name} connection or link', () async {
      var connectionReads = 0;
      var linkBuilds = 0;
      final c = ProviderContainer(
        overrides: [
          activeHostProvider.overrideWith(() => _Active(host)),
          activeConnectionProvider.overrideWith((ref) {
            connectionReads++;
            return const AsyncData<HostConnection?>(null);
          }),
          hostLinkProvider.overrideWith((ref, host) {
            linkBuilds++;
            return _Link();
          }),
          localRuntimeProvider.overrideWith(_Runtime.new),
          settingsProvider.overrideWith(_Settings.new),
          runtimeBridgeProvider.overrideWithValue(_Bridge()),
          diagnosticsChannelProvider.overrideWithValue(_Channel()),
        ],
      );
      addTearDown(c.dispose);
      c.read(activeHostProvider);
      final snapshot = await collect(c);
      expect(connectionReads, 0);
      expect(linkBuilds, 0);
      expect(snapshot.connection, {'host': 'not_observed', 'state': 'not_observed'});
    });
  }

  test('collect includes app errors without opening a connection', () async {
    var connectionReads = 0;
    final c = ProviderContainer(
      overrides: [
        activeConnectionProvider.overrideWith((ref) {
          connectionReads++;
          return const AsyncData<HostConnection?>(null);
        }),
        localRuntimeProvider.overrideWith(_Runtime.new),
        settingsProvider.overrideWith(_Settings.new),
        runtimeBridgeProvider.overrideWithValue(_Bridge()),
        diagnosticsChannelProvider.overrideWithValue(_Channel()),
      ],
    );
    addTearDown(c.dispose);
    appErrorLog.record(AppErrorSource.platform, 'SYNTHETIC collect marker password=fixture-password', StackTrace.empty);
    final snapshot = await collect(c);
    expect(snapshot.appErrors.any((error) => error.message.contains('SYNTHETIC collect marker')), isTrue);
    expect(snapshot.appErrors.any((error) => error.message.contains('fixture-password')), isFalse);
    expect(connectionReads, 0);
  });
}
