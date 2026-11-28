import 'dart:async';

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/runtime/runtime_bridge.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/ui/safe_mode/engine_failure_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shell/golden_harness.dart';
import 'support.dart';

const execError = '/bin/sh: 1: exec: /usr/local/bin/dsh: Bad address';

class _TawcBridge extends FakeBridge {
  final setTawc = Completer<void>();

  @override
  Future<void> setTawcEngine(bool enabled) {
    calls.add('setTawcEngine:$enabled');
    return setTawc.future;
  }
}

RuntimeFailure launchFailure({bool safe = false}) => RuntimeFailure.fromMap({
  'kind': 'launchFailed',
  'at': 123,
  'exitCode': 126,
  'safeMode': safe,
  'summary': execError,
  // Recent plugin changes are not evidence of this shell execution failure.
  'recent': ['unrelated-plugin'],
  'requiredRows': ['unrelated-row'],
})!;

void main() {
  setUp(() {
    AppLocale.use(AppLocale.zhCN);
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => AppLocale.use(AppLocale.zhCN));

  testWidgets('the PRoot recovery action saves the tawcroot choice before starting', (tester) async {
    usePhoneSurface(tester);
    final bridge = _TawcBridge();
    final status = RuntimeStatus.fromMap({
      'phase': 'error',
      'failure': {'kind': 'launchFailed', 'exitCode': 126, 'summary': execError},
      'tawcRecoveryAvailable': true,
    });
    final runtime = RecordingRuntime(LocalRuntimeState(loaded: true, status: status));
    await tester.pumpWidget(
      goldenApp(
        brightness: Brightness.light,
        overrides: [runtimeBridgeProvider.overrideWithValue(bridge), localRuntimeProvider.overrideWith(() => runtime)],
        home: const Scaffold(body: EngineFailureCard()),
      ),
    );
    await tester.pump();
    expect(find.widgetWithText(OutlinedButton, appL10n.commonRetry), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, appL10n.phoneFailureRetryWithTawcroot));
    expect(bridge.calls, ['setTawcEngine:true']);
    expect(runtime.starts, isEmpty);
    bridge.setTawc.complete();
    await tester.pump();
    expect(runtime.starts, ['start']);
    expect(runtime.stops, 0);
  });
}
