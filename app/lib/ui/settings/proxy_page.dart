// 设置 › 代理 (Android): one VLESS + REALITY server, every value typed in by
// hand like v2rayNG's edit page; no import, no QR codes. Saving keeps it on
// the phone (proxy/XrayProxy.kt); the engine picks it up when it starts, so a
// running engine restarts after a save.
//
//   ┌ 使用代理                           (●) ┐  状态 · 运行中
//   ├ 服务器: 地址 / 端口 / 用户 ID / 加密 / 流控
//   ├ 传输: 传输协议 [TCP|XHTTP] (+ host / path / mode)
//   ├ REALITY: SNI / 指纹 / 公钥 / ShortId / SpiderX / Mldsa65Verify
//   └ [测试连接]  [保存]

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_bridge.dart' show RuntimePhase;
import '../../runtime/runtime_state.dart';
import '../../state/proxy_state.dart';
import '../common/app_dialog.dart';
import '../common/status_chip.dart';
import '../../state/engine_control.dart';
import '../features/schedule_editor/schedule_pickers.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../workspace/text_prompt.dart';
import 'settings_widgets.dart';

/// The row in 设置 · AI that opens [ProxyPage].
class ProxyTile extends ConsumerWidget {
  const ProxyTile({super.key, this.tint = 0});
  final int tint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(proxyStateProvider).value;
    final on = state?.config.enabled ?? false;
    return SettingsTile(
      key: const ValueKey('settings-proxy'),
      icon: AppIcons.proxy,
      tint: tint,
      spot: SettingsIndex.entry(SettingsPageId.proxy),
      value: Text(on ? l10n.proxyStatusOn : l10n.proxyStatusOff),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProxyPage()));
        ref.invalidate(proxyStateProvider);
      },
    );
  }
}

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  ProxyConfig? _saved;
  ProxyConfig? _draft;
  bool _testing = false;
  bool _saving = false;
  String? _testLine;
  bool _testOk = false;

  ProxyChannel get _channel => ref.read(proxyChannelProvider);

  bool get _dirty => _draft != null && _draft != _saved;

  void _set(ProxyConfig next) => setState(() {
    _draft = next;
    _testLine = null;
  });

  String _fieldName(L10n l10n, String field) => switch (field) {
    'address' => l10n.proxyAddress,
    'port' => l10n.proxyPort,
    'id' => l10n.proxyId,
    'publicKey' => l10n.proxyPublicKey,
    'flow' => l10n.proxyFlow,
    'network' => l10n.proxyNetwork,
    'xhttpMode' => l10n.proxyXhttpMode,
    _ => field,
  };

  Future<void> _editText(
    String title,
    String value,
    ProxyConfig Function(String) apply, {
    String? hint,
    bool optional = false,
  }) async {
    final text = await showTextPrompt(
      context,
      title: title,
      initial: value,
      hint: hint ?? (optional ? context.l10n.proxyOptional : null),
      mono: true,
      keyboardType: TextInputType.url,
    );
    if (text == null || !mounted) return;
    _set(apply(text.trim()));
  }

  Future<void> _editPort(ProxyConfig draft) async {
    final l10n = context.l10n;
    final text = await showTextPrompt(
      context,
      title: l10n.proxyPort,
      initial: '${draft.port}',
      mono: true,
      keyboardType: TextInputType.number,
      validate: (text) {
        final port = int.tryParse(text.trim());
        return port == null || port < 1 || port > 65535 ? l10n.proxyPortInvalid : null;
      },
    );
    if (text == null || !mounted) return;
    _set(draft.copyWith(port: int.parse(text.trim())));
  }

  Future<void> _pick(String title, List<String> values, String selected, ProxyConfig Function(String) apply) async {
    final picked = await showChoiceSheet<String>(
      context,
      title: title,
      choices: [for (final v in values) Choice(v, v)],
      selected: selected,
    );
    if (picked == null || !mounted) return;
    _set(apply(picked));
  }

  Future<void> _test(ProxyConfig draft) async {
    final l10n = context.l10n;
    final missing = draft.problem;
    if (missing != null) {
      setState(() {
        _testOk = false;
        _testLine = l10n.proxyMissing(_fieldName(l10n, missing));
      });
      return;
    }
    setState(() {
      _testing = true;
      _testLine = null;
    });
    ProxyTestResult result;
    try {
      result = await _channel.test(draft);
    } catch (e) {
      result = ProxyTestResult(error: '$e');
    }
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ms != null;
      _testLine = result.ms != null ? l10n.proxyTestOk(result.ms!) : l10n.proxyTestFailed(result.error ?? '?');
    });
  }

  Future<void> _save(ProxyConfig draft) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final missing = draft.enabled ? draft.problem : null;
    if (missing != null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.proxyMissing(_fieldName(l10n, missing)))));
      return;
    }
    setState(() => _saving = true);
    final refused = await _channel.save(draft);
    if (!mounted) return;
    setState(() => _saving = false);
    if (refused != null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.proxyMissing(_fieldName(l10n, refused)))));
      return;
    }
    setState(() => _saved = draft);
    ref.invalidate(proxyStateProvider);
    // The engine reads the proxy when it starts.
    final running = ref.read(localRuntimeProvider).status.phase == RuntimePhase.running;
    messenger.showSnackBar(SnackBar(content: Text(running ? l10n.proxySavedRestarting : l10n.proxySaved)));
    if (running) unawaited(EngineControl.restart(ProviderScope.containerOf(context, listen: false)));
  }

  Future<bool> _confirmDiscard() async {
    final l10n = context.l10n;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.proxyDiscardTitle),
        content: Text(l10n.proxyDiscardBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.commonCancel)),
          FilledButton(onPressed: () => Navigator.pop(dialog, true), child: Text(l10n.proxyDiscard)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final async = ref.watch(proxyStateProvider);
    final state = async.value;
    if (state != null && _saved == null) {
      _saved = state.config;
      _draft = state.config;
    }
    final draft = _draft;
    if (state == null || draft == null) {
      return AppPage.list(
        title: l10n.proxyTitle,
        children: const [
          Center(
            child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
          ),
        ],
      );
    }
    final usable = state.available;
    final xhttp = draft.network == ProxyConfig.xhttp;
    final valueWidth = MediaQuery.sizeOf(context).width * 0.4;

    Widget field(String key, String title, String value, VoidCallback onTap, {bool optional = false}) => SettingsTile(
      key: ValueKey('proxy-$key'),
      title: title,
      // Keys and IDs run long: cut them so the label keeps its room.
      value: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: valueWidth),
        child: Text(
          value.isEmpty ? (optional ? l10n.proxyOptional : l10n.proxyUnset) : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: value.isEmpty ? TextStyle(color: theme.colorScheme.onSurfaceVariant) : null,
        ),
      ),
      onTap: usable ? onTap : null,
    );

    final (tone, status) = !draft.enabled
        ? (StatusTone.idle, l10n.proxyStatusOff)
        : _dirty || !state.running
        ? (StatusTone.warn, l10n.proxyStatusWaiting)
        : (StatusTone.ok, l10n.proxyStatusOn);
    final footer = !usable
        ? l10n.proxyUnavailable
        : state.error != null && draft.enabled && !_dirty
        ? l10n.proxyLastError(state.error!)
        : l10n.proxySwitchHint;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard() && mounted) {
          setState(() => _draft = _saved);
          navigator.pop();
        }
      },
      child: AppPage.list(
        title: l10n.proxyTitle,
        subtitle: Text(l10n.proxySubtitle),
        children: [
          SettingsSection(
            footer: Text(
              footer,
              style: !usable || (state.error != null && draft.enabled && !_dirty)
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
            children: [
              SettingsSwitchTile(
                key: const ValueKey('proxy-switch'),
                title: l10n.proxySwitch,
                value: draft.enabled,
                onChanged: usable ? (on) => _set(draft.copyWith(enabled: on)) : null,
              ),
              SettingsTile(
                title: l10n.linuxStatus,
                value: StatusChip(tone: tone, label: status),
                chevron: false,
              ),
            ],
          ),
          SettingsSection(
            title: l10n.proxyServer,
            children: [
              field(
                'address',
                l10n.proxyAddress,
                draft.address,
                () =>
                    _editText(l10n.proxyAddress, draft.address, (v) => draft.copyWith(address: v), hint: 'example.com'),
              ),
              field('port', l10n.proxyPort, '${draft.port}', () => _editPort(draft)),
              field(
                'id',
                l10n.proxyId,
                draft.id,
                () => _editText(l10n.proxyId, draft.id, (v) => draft.copyWith(id: v)),
              ),
              field(
                'encryption',
                l10n.proxyEncryption,
                draft.encryption,
                () => _editText(
                  l10n.proxyEncryption,
                  draft.encryption,
                  (v) => draft.copyWith(encryption: v.isEmpty ? 'none' : v),
                  hint: 'none',
                ),
              ),
              if (!xhttp)
                field(
                  'flow',
                  l10n.proxyFlow,
                  draft.flow.isEmpty ? l10n.proxyFlowNone : draft.flow,
                  () => _pick(l10n.proxyFlow, ['', ProxyConfig.visionFlow], draft.flow, (v) => draft.copyWith(flow: v)),
                ),
            ],
          ),
          SettingsSection(
            title: l10n.proxyTransport,
            footer: xhttp ? Text(l10n.proxyFlowXhttpNote) : null,
            children: [
              SettingsSegmentTile<String>(
                key: const ValueKey('proxy-network'),
                title: l10n.proxyNetwork,
                segments: const [PillSegment(ProxyConfig.raw, 'TCP'), PillSegment(ProxyConfig.xhttp, 'XHTTP')],
                selected: draft.network,
                onChanged: usable ? (v) => _set(draft.copyWith(network: v)) : null,
              ),
              if (xhttp) ...[
                field(
                  'xhttp-host',
                  l10n.proxyXhttpHost,
                  draft.xhttpHost,
                  () => _editText(
                    l10n.proxyXhttpHost,
                    draft.xhttpHost,
                    (v) => draft.copyWith(xhttpHost: v),
                    optional: true,
                  ),
                  optional: true,
                ),
                field(
                  'xhttp-path',
                  l10n.proxyXhttpPath,
                  draft.xhttpPath,
                  () => _editText(
                    l10n.proxyXhttpPath,
                    draft.xhttpPath,
                    (v) => draft.copyWith(xhttpPath: v.isEmpty ? '/' : v),
                    hint: '/',
                  ),
                ),
                field(
                  'xhttp-mode',
                  l10n.proxyXhttpMode,
                  draft.xhttpMode,
                  () => _pick(
                    l10n.proxyXhttpMode,
                    ProxyConfig.xhttpModes,
                    draft.xhttpMode,
                    (v) => draft.copyWith(xhttpMode: v),
                  ),
                ),
              ],
            ],
          ),
          SettingsSection(
            title: l10n.proxyReality,
            footer: Text(l10n.proxyFooter),
            children: [
              field(
                'sni',
                l10n.proxySni,
                draft.sni,
                () => _editText(l10n.proxySni, draft.sni, (v) => draft.copyWith(sni: v), hint: 'www.example.com'),
              ),
              field(
                'fingerprint',
                l10n.proxyFingerprint,
                draft.fingerprint,
                () => _pick(
                  l10n.proxyFingerprint,
                  ProxyConfig.fingerprints,
                  draft.fingerprint,
                  (v) => draft.copyWith(fingerprint: v),
                ),
              ),
              field(
                'public-key',
                l10n.proxyPublicKey,
                draft.publicKey,
                () => _editText(l10n.proxyPublicKey, draft.publicKey, (v) => draft.copyWith(publicKey: v)),
              ),
              field(
                'short-id',
                l10n.proxyShortId,
                draft.shortId,
                () => _editText(l10n.proxyShortId, draft.shortId, (v) => draft.copyWith(shortId: v), optional: true),
                optional: true,
              ),
              field(
                'spider-x',
                l10n.proxySpiderX,
                draft.spiderX,
                () => _editText(l10n.proxySpiderX, draft.spiderX, (v) => draft.copyWith(spiderX: v), optional: true),
                optional: true,
              ),
              field(
                'mldsa65',
                l10n.proxyMldsa65,
                draft.mldsa65Verify,
                () => _editText(
                  l10n.proxyMldsa65,
                  draft.mldsa65Verify,
                  (v) => draft.copyWith(mldsa65Verify: v),
                  optional: true,
                ),
                optional: true,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_testLine != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _testLine!,
                      key: const ValueKey('proxy-test-result'),
                      style: TextStyle(color: _testOk ? null : theme.colorScheme.error),
                    ),
                  ),
                if (_dirty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(l10n.proxyUnsaved, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('proxy-test'),
                        onPressed: usable && !_testing ? () => unawaited(_test(draft)) : null,
                        child: Text(_testing ? l10n.proxyTesting : l10n.proxyTest),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('proxy-save'),
                        onPressed: usable && _dirty && !_saving ? () => unawaited(_save(draft)) : null,
                        child: Text(l10n.proxySave),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
