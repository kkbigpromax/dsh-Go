// 隐私与分享: shared links, configuration sharing and local text recognition.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../phone/phone_control_screen.dart';
import '../share_code/profile_share_sheet.dart';
import '../share_hosted/hosted_links_tile.dart';
import '../shell/page_frame.dart';
import 'settings_widgets.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppPage.list(
      title: l10n.hubPrivacy,
      children: [
        SettingsSection(
          title: l10n.hubPrivacySharing,
          children: [
            const HostedLinksSettingsTile(icon: false),
            SettingsTile(spot: Spots.shareConfig, onTap: () => unawaited(showShareProfileSheet(context))),
          ],
        ),
        SettingsSection(
          title: l10n.phoneLocalOcrTitle,
          footer: Text('${l10n.phoneLocalOcrDisclosure}\n\n${l10n.phoneLocalOcrDetails}'),
          children: [
            ListTile(
              title: Text(l10n.phoneLocalOcrTitle),
              onTap: () => unawaited(
                Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => const PhoneControlScreen())),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
