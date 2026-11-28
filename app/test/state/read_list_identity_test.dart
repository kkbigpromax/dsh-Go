import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/account_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/read_list_identity.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Host extends ActiveHostController {
  _Host(this.initial);
  final HostRef initial;
  @override
  HostRef build() => initial;
}

class _Runtime extends LocalRuntimeController {
  _Runtime(this.initial);
  final RuntimeStatus initial;
  @override
  LocalRuntimeState build() => LocalRuntimeState(loaded: true, status: initial);
  void set(RuntimeStatus value) => state = LocalRuntimeState(loaded: true, status: value);
}

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

class _Account extends AccountController {
  @override
  AccountState build() => const AccountState(phase: AccountPhase.signedOut);
  @override
  bool get readListIdentityKnown => true;
  void set(AccountState value) => state = value;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer container(List<Override> overrides) {
    final c = ProviderContainer(
      overrides: [activeConnectionProvider.overrideWithValue(const AsyncData(null)), ...overrides],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('local source survives start/stop/token changes, not mode/version/reset', () {
    const running = RuntimeStatus(phase: RuntimePhase.running, installedVersion: 'v1', token: 'one');
    final runtime = _Runtime(running);
    final c = container([
      activeHostProvider.overrideWith(() => _Host(HostRef.local)),
      localRuntimeProvider.overrideWith(() => runtime),
      localReadListRootProvider.overrideWithValue(const AsyncData('/canonical/rootfs')),
      settingsProvider.overrideWith(_Settings.new),
      accountProvider.overrideWith(_Account.new),
    ]);
    final first = c.read(readListIdentityProvider)!;
    for (final phase in [RuntimePhase.stopping, RuntimePhase.installed, RuntimePhase.starting, RuntimePhase.running]) {
      runtime.set(RuntimeStatus(phase: phase, installedVersion: 'v1', token: 'new-token'));
      expect(c.read(readListIdentityProvider), first);
    }
    runtime.set(const RuntimeStatus(phase: RuntimePhase.running, installedVersion: 'v1', mode: EngineMode.safe));
    expect(c.read(readListIdentityProvider), isNot(first));
    runtime.set(const RuntimeStatus(phase: RuntimePhase.running, installedVersion: 'v2'));
    expect(c.read(readListIdentityProvider), isNot(first));
    runtime.set(const RuntimeStatus(phase: RuntimePhase.installing, installedVersion: 'v1'));
    expect(c.read(readListIdentityProvider), isNull);
    runtime.set(running);
    expect(c.read(readListIdentityProvider), isNot(first), reason: 'same-version reinstall is a new root generation');
  });

  test('unresolved root/account is not assumed to be a local signed-out identity', () {
    final account = _Account();
    final c = container([
      activeHostProvider.overrideWith(() => _Host(HostRef.local)),
      localRuntimeProvider.overrideWith(
        () => _Runtime(const RuntimeStatus(phase: RuntimePhase.running, installedVersion: 'v')),
      ),
      localReadListRootProvider.overrideWithValue(const AsyncData('/rootfs')),
      settingsProvider.overrideWith(_Settings.new),
      accountProvider.overrideWith(() => account),
    ]);
    expect(c.read(readListIdentityProvider), isNotNull);
    account.set(const AccountState(phase: AccountPhase.unknown));
    expect(c.read(readListIdentityProvider), isNull);
    account.set(const AccountState(phase: AccountPhase.signingIn));
    expect(c.read(readListIdentityProvider), isNull);
  });
}
