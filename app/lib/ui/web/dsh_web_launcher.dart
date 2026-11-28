import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/hosts_state.dart';
import 'local_web_screen.dart';
import 'web_target.dart';

/// Where the active host's DSH Web can be opened from.
sealed class DshWebAccess {
  const DshWebAccess();
}

/// 本机: the on-device engine's `dsh web` ([LocalWebScreen] handles a
/// stopped engine itself).
final class LocalDshWeb extends DshWebAccess {
  const LocalDshWeb();
}

/// An SSH host: the remote `dsh web` through the app's local forward.
///
/// DSH's browser fence accepts any loopback Host, so the WebView can talk to
/// `127.0.0.1:<forward port>` directly; the launch token logs it in.
final class SshDshWeb extends DshWebAccess {
  const SshDshWeb(this.url, this.hostName);
  final Uri url;
  final String hostName;
}

/// No web page for this host right now; [reason] says why.
final class NoDshWeb extends DshWebAccess {
  const NoDshWeb(this.reason);
  final String reason;
}

/// The active host's DSH Web, if it has one the app can reach.
final dshWebAccessProvider = Provider.autoDispose<DshWebAccess>((ref) {
  final host = ref.watch(activeHostProvider);
  switch (host.kind) {
    case HostKind.local:
      return const LocalDshWeb();
    case HostKind.ssh || HostKind.relay:
      return NoDshWeb(appL10n.webRelayUnavailable);
  }
});

/// A page that decides how it is left for DSH Web: [openDshWeb] from inside
/// it (its rows that say 「在网页版编辑此项」) hands the target to [onOpen]
/// instead, which lands it and goes there when the page can be left — a page
/// whose own edits DSH Web would otherwise race (plugin_config_page.dart).
class DshWebOpenScope extends InheritedWidget {
  const DshWebOpenScope({super.key, required this.onOpen, required super.child});

  final void Function(DshWebTarget target) onOpen;

  static DshWebOpenScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<DshWebOpenScope>();

  @override
  bool updateShouldNotify(DshWebOpenScope oldWidget) => false;
}

/// Opens the active host's official DSH Web, landing on [target]. In
/// 网页模式 the home page itself goes there (no second page on top). Inside
/// a [DshWebOpenScope] the page around decides.
void openDshWeb(BuildContext context, WidgetRef ref, {DshWebTarget target = const DshWebTarget()}) {}
