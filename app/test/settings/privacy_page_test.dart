import 'package:dsh_app/l10n/l10n.dart';
import 'package:dsh_app/ui/settings/privacy_page.dart';
import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../engine_settings/support.dart' as engine;
import '../support/english_preview.dart';

void main() {
  for (final english in [false, true]) {
    testWidgets('privacy settings have no anonymous reporting (${english ? 'en' : 'zh'})', (tester) async {
      SharedPreferences.setMockInitialValues({
        'usage_stats_enabled': true,
        'usage_stats_noticed': true,
        'usage_stats_iid': 'old-install-id',
      });
      if (english) useEnglish();
      final host = engine.FakeSettingsHost();
      host.namespaces['session-log-deepseek']!.user = {'enabled': true};
      final client = DshClient.withCarrier(host);
      addTearDown(client.close);
      await engine.pumpPage(
        tester,
        english ? inEnglish(const PrivacyPage()) : const PrivacyPage(),
        overrides: engine.engineOverrides(client, local: !english),
      );

      expect(find.text(appL10n.hubPrivacySharing), findsOneWidget);
      expect(find.text(appL10n.hubSettingsShareConfig), findsOneWidget);
      expect(find.text(appL10n.phoneLocalOcrTitle), findsWidgets);
      expect(find.text('发送匿名使用统计'), findsNothing);
      expect(find.text('Send anonymous usage stats'), findsNothing);
      expect(find.text('改进 DSH Go'), findsNothing);
      expect(find.text('Improve DSH Go'), findsNothing);
      expect(find.text('向 DeepSeek 上传对话日志'), findsNothing);
      expect(find.text('Upload chat logs to DeepSeek'), findsNothing);
      expect(find.byKey(const ValueKey('usage-notice-switch')), findsNothing);
      expect(host.mutates(), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
}
