import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_state.dart';
import '../../state/account_state.dart';
import '../../state/onboarding_state.dart';
import '../providers/provider_form_page.dart';
import '../theme/app_icons.dart';
import 'onboarding_scaffold.dart';
import 'setup_progress.dart';

/// First-run "connect a model" step. This build has no DeepSeek account or
/// remote host (docs/fork-maintenance.md): a custom provider (own Base URL and
/// key) or skip for now. Subscription sign-in lives in 设置 › 模型.
///
/// The engine is started as soon as this page shows: the provider form saves
/// into it.
class ConnectPage extends ConsumerStatefulWidget {
  const ConnectPage({super.key, required this.onDone});

  /// Called after a saved custom provider, or "稍后设置".
  final VoidCallback onDone;

  @override
  ConsumerState<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends ConsumerState<ConnectPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // A runtime still unpacking (or whose unpack failed) has no engine to start.
      final runtime = ref.exists(localRuntimeProvider) ? ref.read(setupRuntimeProvider) : null;
      if (runtime == SetupRuntime.unpacking || runtime == SetupRuntime.failed) return;
      unawaited(ref.read(accountEngineStarterProvider)().catchError((_) {}));
    });
  }

  Future<void> _skip() async {
    await ref.read(onboardingPrefsProvider.notifier).setKeySkipped(true);
    widget.onDone();
  }

  Future<void> _addProvider() async {
    final id = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ProviderFormPage()));
    if (id == null || !mounted) return;
    await ref.read(onboardingPrefsProvider.notifier).setKeySkipped(true);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return OnboardingScaffold(
      children: [
        const Spacer(),
        OnboardingHeader(icon: AppIcons.account, title: l10n.shellConnectModel, message: l10n.shellConnectModelMessage),
        const Spacer(flex: 2),
        const SizedBox(height: 24),
        FilledButton(onPressed: _addProvider, child: Text(l10n.engineProviderAdd)),
        const SizedBox(height: 6),
        TextButton(
          onPressed: _skip,
          style: TextButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
          child: Text(l10n.shellSetUpLater),
        ),
      ],
    );
  }
}
