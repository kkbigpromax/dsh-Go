import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/links/page_links.dart';
import 'package:dsh_app/pets/pet_overlay_bridge.dart';
import 'package:dsh_app/state/quick_panel_state.dart';
import 'package:dsh_app/state/ui_mode_state.dart';
import 'package:dsh_app/ui/features/feature_catalog.dart';
import 'package:dsh_app/ui/pets/pet_stage.dart';
import 'package:dsh_app/ui/settings/index/spots.dart';
import 'package:dsh_app/ui/settings/interface_page.dart';
import 'package:dsh_app/ui/shell/home_shell.dart';
import 'package:dsh_app/ui/shell/quick_panel.dart';
import 'package:dsh_app/ui/shell/sessions_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine_settings/support.dart' as engine;
import '../chat/support/harness.dart';
import 'adaptive/support.dart';

void main() {
  setUpAll(loadTestFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'ui.mode': 'web',
      'app_mode.startup': 'companion',
      'pet.pack': 'deepy-whale',
    });
    freezeClocks();
  });
  tearDown(thawClocks);

  test('retired settings and their deep links cannot reopen disabled features', () {
    for (final id in [
      'pets',
      'pet-size',
      'pet-quiet',
      'pet-outside-app',
      'quick-panel',
      'ui-mode',
      'web-app',
      'open-web',
      'web-phone-layout',
      'companion',
      'tavern',
      'diagnostics',
      'about',
      'community',
      'forum',
      'usage-stats',
      'chat-log-upload',
    ]) {
      expect(SettingsIndex.spotForLink(id), isNull, reason: id);
      expect(pageForId(id, null), isNull, reason: id);
      expect(pageLinkId(Uri.parse('dshgo://open/$id')), isNull, reason: id);
    }
    expect(
      featureSections.expand((s) => s.items).map((i) => i.id),
      isNot(contains(anyOf('web', 'community', 'forum'))),
    );
    expect(
      SettingsIndex.pages.keys,
      isNot(contains(anyOf(SettingsPageId.pets, SettingsPageId.about, SettingsPageId.diagnostics))),
    );
  });

  test('interface search keywords describe only retained controls', () {
    final page = SettingsIndex.page(SettingsPageId.interface);
    for (final locale in [const Locale('zh'), const Locale('en')]) {
      final keywords = page.keywords!(lookupL10n(locale));
      expect(keywords.toLowerCase(), isNot(contains('web')));
      expect(keywords, isNot(contains('网页')));
    }
  });

  test('old web mode preferences migrate to the native chat interface', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(uiModeProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(uiModeProvider).mode, UiMode.native);
    await container.read(uiModeProvider.notifier).set(UiMode.web);
    expect(container.read(uiModeProvider).mode, UiMode.native);
  });

  testWidgets('main chat has no pet or quick panel, left swipe cannot activate their providers', (tester) async {
    useWindow(tester, const Size(390, 844));
    mockClipboard(tester);
    await tester.pumpWidget(homeApp());
    await pumpFrames(tester, 8);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
    expect(find.byType(PetStage), findsNothing);
    expect(find.byType(QuickPanel), findsNothing);
    expect(container.exists(quickPanelProvider), isFalse);
    expect(container.exists(petOverlayBridgeProvider), isFalse);
    await tester.dragFrom(const Offset(360, 420), const Offset(-290, 0));
    await pumpFrames(tester, 8);
    expect(find.byType(QuickPanel), findsNothing);
    expect(container.exists(quickPanelProvider), isFalse);
    await tester.dragFrom(const Offset(12, 420), const Offset(290, 0));
    await pumpFrames(tester, 8);
    expect(find.byType(SessionsDrawer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('interface settings only show controls used by native chat', (tester) async {
    await engine.pumpPage(tester, const InterfacePage(), overrides: engine.engineOverrides(null));
    expect(find.byKey(const ValueKey('interface-startup-mode')), findsNothing);
    expect(find.byKey(const ValueKey('quick-panel-swipe')), findsNothing);
    expect(find.byKey(const ValueKey('quick-panel-items')), findsNothing);
    for (final text in [appL10n.commonWeb, appL10n.modeSheetTitle, appL10n.hubQuickPanel]) {
      expect(find.text(text), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
