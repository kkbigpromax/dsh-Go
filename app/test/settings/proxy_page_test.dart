// 设置 › 代理: the hand-typed VLESS + REALITY server, saved through the
// native channel only when it is complete; testing never saves.

import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/state/proxy_state.dart';
import 'package:dsh_app/ui/settings/proxy_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../engine_settings/support.dart' as engine;

class _FakeChannel implements ProxyChannel {
  _FakeChannel(this.state);
  ProxyState state;
  final saved = <ProxyConfig>[];
  final tested = <ProxyConfig>[];
  ProxyTestResult answer = const ProxyTestResult(ms: 321);

  @override
  Future<ProxyState> load() async => state;

  @override
  Future<String?> save(ProxyConfig config) async {
    saved.add(config);
    state = ProxyState(config: config, available: state.available);
    return null;
  }

  @override
  Future<ProxyTestResult> test(ProxyConfig config) async {
    tested.add(config);
    return answer;
  }
}

const _complete = ProxyConfig(
  address: 'proxy.example.com',
  id: 'b831381d-6324-4d53-ad4f-8cda48b30811',
  sni: 'www.example.com',
  publicKey: 'Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw',
  shortId: '6ba85179e30d4fc2',
);

Future<_FakeChannel> _pump(WidgetTester tester, ProxyState state, {bool fonts = false}) async {
  final channel = _FakeChannel(state);
  final client = DshClient.withCarrier(engine.FakeSettingsHost());
  addTearDown(client.close);
  await engine.pumpPage(
    tester,
    const ProxyPage(),
    overrides: [...engine.engineOverrides(client), proxyChannelProvider.overrideWithValue(channel)],
    height: 1600,
    fonts: fonts,
  );
  return channel;
}

/// Scrolls [finder] into view, then taps it.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String row, String text) async {
  await _tap(tester, find.byKey(ValueKey('proxy-$row')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, text);
  await tester.tap(find.text(appL10n.commonSave).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an incomplete server is not saved; filling it in saves exactly what was typed', (tester) async {
    final channel = await _pump(tester, const ProxyState(config: ProxyConfig(), available: true));
    expect(find.text(appL10n.proxySwitch), findsOneWidget);
    expect(find.text(appL10n.proxyStatusOff), findsOneWidget);

    await _tap(tester, find.byKey(const ValueKey('proxy-switch')));
    await _tap(tester, find.byKey(const ValueKey('proxy-save')));
    expect(channel.saved, isEmpty);
    expect(find.text(appL10n.proxyMissing(appL10n.proxyAddress)), findsOneWidget);

    await _type(tester, 'address', ' proxy.example.com ');
    await _type(tester, 'id', _complete.id);
    await _type(tester, 'public-key', _complete.publicKey);
    await _type(tester, 'sni', _complete.sni);
    await _type(tester, 'short-id', _complete.shortId);
    await _tap(tester, find.byKey(const ValueKey('proxy-save')));

    expect(channel.saved, hasLength(1));
    final saved = channel.saved.single;
    expect(saved.enabled, isTrue);
    expect(saved.address, 'proxy.example.com');
    expect(saved.network, ProxyConfig.raw);
    expect(saved.flow, ProxyConfig.visionFlow);
    expect(saved.toJson(), {..._complete.copyWith(enabled: true).toJson()});
    expect(tester.takeException(), isNull);
  });

  testWidgets('XHTTP shows its own fields and drops the flow row', (tester) async {
    await _pump(tester, const ProxyState(config: _complete, available: true));
    expect(find.byKey(const ValueKey('proxy-flow')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy-xhttp-path'), skipOffstage: false), findsNothing);

    await _tap(tester, find.text('XHTTP'));
    expect(find.byKey(const ValueKey('proxy-flow')), findsNothing);
    expect(find.byKey(const ValueKey('proxy-xhttp-path')), findsOneWidget);
    expect(find.byKey(const ValueKey('proxy-xhttp-mode')), findsOneWidget);
    expect(find.text(appL10n.proxyFlowXhttpNote), findsOneWidget);
    await tester.scrollUntilVisible(find.text(appL10n.proxyUnsaved), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text(appL10n.proxyUnsaved), findsOneWidget);
  });

  testWidgets('testing reports the time and saves nothing', (tester) async {
    final channel = await _pump(tester, const ProxyState(config: _complete, available: true));
    await _tap(tester, find.byKey(const ValueKey('proxy-test')));
    expect(channel.tested.single, _complete);
    expect(find.text(appL10n.proxyTestOk(321)), findsOneWidget);
    expect(channel.saved, isEmpty);

    channel.answer = const ProxyTestResult(error: 'REALITY: processed invalid connection');
    await _tap(tester, find.byKey(const ValueKey('proxy-test')));
    expect(find.text(appL10n.proxyTestFailed('REALITY: processed invalid connection')), findsOneWidget);
  });

  testWidgets('a build without the core says so and edits nothing', (tester) async {
    await _pump(tester, const ProxyState(config: ProxyConfig(), available: false));
    expect(find.text(appL10n.proxyUnavailable), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('proxy-save')), 200, scrollable: find.byType(Scrollable).first);
    final save = tester.widget<FilledButton>(find.byKey(const ValueKey('proxy-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('golden: a saved Vision server, running', (tester) async {
    await _pump(tester, ProxyState(config: _complete.copyWith(enabled: true), available: true, running: true), fonts: true);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/proxy_page_light.png'));
  });

  test('the stored JSON round-trips', () {
    final config = _complete.copyWith(enabled: true, network: ProxyConfig.xhttp, xhttpMode: 'packet-up');
    expect(ProxyConfig.fromJson(config.toJson()), config);
    expect(ProxyConfig.fromJson(const {}), const ProxyConfig());
  });
}
