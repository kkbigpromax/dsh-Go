import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../remote/secret_store.dart';

export '../remote/link_status.dart' show HostLinkStatus, HostLinkPhase, HostLinkStep, HostLinkError, HostLinkErrorKind;

/// The kinds of DSH host upstream knows. This build talks only to [local]
/// (docs/fork-maintenance.md); the others stay so stored references decode.
enum HostKind { local, ssh, relay }

/// Identifies a host: the on-device engine, a saved SSH host, or a relay
/// (ds-harness-remote) device. Equality is by kind + id; [name] is only a
/// cached display name for relay hosts (their list lives on the server).
class HostRef {
  const HostRef._(this.kind, this.id, [this.name]);

  static const local = HostRef._(HostKind.local, 'local');

  const HostRef.ssh(String id) : this._(HostKind.ssh, id);

  const HostRef.relay(String id, {String? name}) : this._(HostKind.relay, id, name);

  final HostKind kind;
  final String id;
  final String? name;

  bool get isLocal => kind == HostKind.local;

  String encode() => jsonEncode({'kind': kind.name, 'id': id, if (name != null) 'name': name});

  static HostRef decode(String? raw) {
    if (raw == null || raw.isEmpty) return local;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return local;
      final id = map['id'];
      final name = map['name'];
      if (id is! String || id.isEmpty) return local;
      return switch (map['kind']) {
        'ssh' => HostRef.ssh(id),
        'relay' => HostRef.relay(id, name: name is String ? name : null),
        _ => local,
      };
    } catch (_) {
      return local;
    }
  }

  @override
  bool operator ==(Object other) => other is HostRef && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'HostRef(${kind.name}:$id)';
}

/// Chat-header label for a connection: "本机", "电脑 · SSH", "家里的 Mac · 远程".
String hostLabel(HostKind kind, String? name) => switch (kind) {
  HostKind.local => appL10n.commonThisPhone,
  HostKind.ssh => '${_short(name ?? appL10n.stateSshHost)} · SSH',
  HostKind.relay => appL10n.stateHostRemoteLabel(_short(name ?? appL10n.commonRemoteHost)),
};

String _short(String name) {
  final t = name.trim();
  return t.length <= 14 ? t : '${t.substring(0, 13)}…';
}

// ── Secrets ──────────────────────────────────────────────────────────────────

/// Keystore-backed in the app; tests override with [MemorySecretStore].
final secretStoreProvider = Provider<SecretStore>((ref) => SecureSecretStore());

// ── Active host ──────────────────────────────────────────────────────────────

/// Which host the chat, session list and new chats use: always 本机 in this
/// build, which has no remote hosts (docs/fork-maintenance.md).
class ActiveHostController extends Notifier<HostRef> {
  @override
  HostRef build() => HostRef.local;

  /// The startup host choice has settled.
  Future<void> get ready => Future.value();

  /// Only 本机 can be selected; a stored remote reference is ignored.
  void select(HostRef host) {
    if (!host.isLocal) return;
  }
}

final activeHostProvider = NotifierProvider<ActiveHostController, HostRef>(ActiveHostController.new);

/// Opens the login page: a Custom Tab on Android (Google sign-in refuses
/// WebViews), the browser elsewhere.
typedef UrlOpener = Future<bool> Function(Uri url);

final urlOpenerProvider = Provider<UrlOpener>(
  (ref) => (url) async {
    // HarmonyOS's url_launcher answers the in-app mode with a developer's toast.
    if (Platform.operatingSystem == 'ohos') return launchUrl(url, mode: LaunchMode.externalApplication);
    try {
      return await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      return launchUrl(url, mode: LaunchMode.externalApplication);
    }
  },
);
