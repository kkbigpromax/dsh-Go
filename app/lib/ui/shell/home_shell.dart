// SPDX-FileCopyrightText: 2026 CikeSeven
// SPDX-License-Identifier: MIT
// See THIRD_PARTY_NOTICES.md.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../links/app_links.dart';
import '../../state/adaptive_layout_state.dart';
import '../../state/drawer_view_state.dart' show drawerSelectionProvider;
import '../../state/sessions_state.dart' show currentSessionProvider;
import '../../state/live_activity_state.dart' show liveActivityBridgeProvider;
import '../bots/bot_alerts.dart';
import '../chat/chat_screen.dart';
import '../chat/composer_toast.dart' show composerToastGap;
import '../engine/engine_screen.dart';
import '../features/all_features_page.dart';
import '../notify/background_net_host.dart';
import '../notify/chat_alert_host.dart';
import '../notify/voice_model_host.dart';
import '../plugins/plugins_screen.dart';
import '../phone/phone_stop_watcher.dart';
import '../remote/host_switcher.dart' show showHostSheet;
import '../remote/remote_screen.dart';
import '../safe_mode/safe_mode_notice_listener.dart';
import '../session/session_detail_page.dart';
import '../settings/search/settings_search_page.dart';
import '../settings/settings_screen.dart';
import '../share_code/share_code_host.dart';
import '../theme/theme.dart';
import '../wallpaper/wallpaper_backdrop.dart';
import 'adaptive/adaptive_layout.dart';
import 'adaptive/adaptive_rail.dart';
import 'adaptive/adaptive_scaffold.dart';
import 'drawer_drag.dart';
import 'session_search_page.dart' show showSessionSearch;
import 'sessions_drawer.dart';
import 'system_entry_host.dart';

/// Home: the chat screen, with the sessions drawer pulled over it from the left.
///
/// The drawer is driven by one [AnimationController] that a swipe moves
/// continuously (right to open, left to push back, same finger), so the drawer
/// follows the hand instead of playing a canned animation. Only the overlay
/// rebuilds per frame; the chat underneath never does.
///
/// From 840dp wide ([AdaptiveLayout]) the list stays on screen as a rail or a
/// sidebar and 对话详情 is a column beside the chat; ≡ then folds and unfolds
/// the list, and the drawer is only pulled over when the sidebar doesn't fit.
///
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.chatBuilder, this.initiallyOpen = false});

  /// Replaces [ChatScreen] (widget tests use a stand-in).
  @visibleForTesting
  final Widget Function(VoidCallback openDrawer)? chatBuilder;

  /// Starts with the drawer fully open (goldens).
  @visibleForTesting
  final bool initiallyOpen;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with TickerProviderStateMixin {
  late final AnimationController _drawer = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
    value: widget.initiallyOpen ? 1 : 0,
  );

  /// Mirrors "drawer at all open" so PopScope rebuilds only on the 0 ↔ >0 edge.
  late bool _open = widget.initiallyOpen;

  /// The pulled-over drawer's identity bar height: its notices stand above it.
  final _identityBar = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _drawer.addListener(() {
      final open = _drawer.value > 0;
      if (open != _open) setState(() => _open = open);
    });
  }

  @override
  void dispose() {
    _drawer.dispose();
    _identityBar.dispose();
    super.dispose();
  }

  /// 320 of list, plus the cutout or navigation bar it covers on a phone on
  /// its side (the drawer's content keeps clear of it), like the sidebar.
  double _drawerWidth(BuildContext context) => math.min(
    AdaptiveMetrics.sidebarWidth + MediaQuery.paddingOf(context).left,
    MediaQuery.sizeOf(context).width - 56,
  );

  void _slideOpen(AnimationController side) {
    FocusManager.instance.primaryFocus?.unfocus();
    side.animateTo(1, curve: AppMotion.glide, duration: AppMotion.of(context, AppMotion.emphasized));
  }

  void _slideClosed(AnimationController side) {
    FocusManager.instance.primaryFocus?.unfocus();
    side.animateBack(0, curve: AppMotion.glide, duration: AppMotion.of(context, AppMotion.standard));
  }

  void _openDrawer() => _slideOpen(_drawer);

  void _closeDrawer() => _slideClosed(_drawer);

  void _revealChat(bool animate) {
    if (_drawer.value == 0) return;
    if (animate) {
      _closeDrawer();
    } else {
      _drawer.value = 0;
    }
  }

  /// The columns as last built; what ≡ does depends on them.
  AdaptiveLayout _layout = const AdaptiveLayout.compact();

  /// ≡ (the header's, or the rail's): pull the drawer over, or fold / unfold
  /// the sidebar of a wide window.
  void _onMenu() {
    final prefs = ref.read(layoutPrefsProvider.notifier);
    switch (_layout.menuAction) {
      case MenuAction.overlay:
        _openDrawer();
      case MenuAction.expand:
        prefs.setSidebarOpen(true);
      case MenuAction.collapse:
        prefs.setSidebarOpen(false);
    }
  }

  Future<void> _search() async {
    final sessionId = await showSessionSearch(context);
    if (sessionId == null || !mounted) return;
    ref.read(currentSessionProvider.notifier).select(sessionId);
  }

  void _onDragStart(AnimationController side) {
    side.stop();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// [opening]: pixels towards fully open.
  void _onDragDelta(AnimationController side, double width, double opening) {
    if (width <= 0) return;
    side.value = (side.value + opening / width).clamp(0.0, 1.0);
  }

  /// [velocity]: pixels a second towards fully open.
  void _onDragEnd(AnimationController side, double width, double velocity) {
    if (velocity.abs() >= kMinFlingVelocity && width > 0) {
      final target = velocity > 0 ? 1.0 : 0.0;
      if (AppMotion.reduced(context)) {
        side.value = target;
        return;
      }
      // Not `fling`, which refuses a spring with any bounce. The controller's
      // bounds clip it: the bounce shapes the arrival, nothing goes past the edge.
      final spring = AppMotion.settle(AppMotion.flingSpring, side.value, target, velocity / width, landing: false);
      if (velocity > 0) {
        side.animateWith(spring);
      } else {
        side.animateBackWith(spring);
      }
      return;
    }
    if (side.value >= 0.5) {
      _slideOpen(side);
    } else {
      _slideClosed(side);
    }
  }

  void _openDestination(DrawerDestination destination) {
    final page = switch (destination) {
      DrawerDestination.web => const SizedBox.shrink(),
      DrawerDestination.remote => const RemoteScreen(),
      DrawerDestination.plugins => const PluginsScreen(),
      DrawerDestination.engine => const EngineScreen(),
      DrawerDestination.settings => const SettingsScreen(),
      DrawerDestination.settingsSearch => const SettingsSearchPage(),
      DrawerDestination.features => const AllFeaturesPage(),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    // Close once the new page covers us, so "back" lands on the chat.
    Future<void>.delayed(AppMotion.slow, () {
      if (!mounted) return;
      _drawer.value = 0;
    });
  }

  /// The drawer's swipe (right to open, left to push back).
  Map<Type, GestureRecognizerFactory> get _drawerGestures => {
    DrawerDragRecognizer: GestureRecognizerFactoryWithHandlers<DrawerDragRecognizer>(
      () => DrawerDragRecognizer(
        isOpen: () => _drawer.value > 0,
        onStart: () => _onDragStart(_drawer),
        onDelta: (dx) => _onDragDelta(_drawer, _drawerWidth(context), dx),
        onEnd: (velocity) => _onDragEnd(_drawer, _drawerWidth(context), velocity),
        debugOwner: this,
      ),
      (_) {},
    ),
  };

  /// The quick panel's swipe (left to open, right to push back).

  @override
  Widget build(BuildContext context) {
    final width = _drawerWidth(context);
    final sessionId = ref.watch(currentSessionProvider);
    final prefs = ref.watch(layoutPrefsProvider);
    // Multi-select in a list on screen (the open drawer, or the sidebar):
    // back ends it before anything else.
    final selecting = ref.watch(drawerSelectionProvider.select((s) => s != null));
    final layout = _layout = AdaptiveLayout.resolve(
      window: MediaQuery.sizeOf(context),
      padding: MediaQuery.paddingOf(context),
      hasSession: sessionId != null,
      sidebarOpen: prefs.sidebarOpen,
      panelOpen: prefs.panelOpen,
    );
    final sidebar = layout.left == LeftPane.sidebar;
    final chat = widget.chatBuilder?.call(_onMenu) ?? ChatScreen(onOpenDrawer: _onMenu, backdrop: false);
    // Chat status notifications keep their shared reducer without the pet overlay.
    ref.listen<void>(liveActivityBridgeProvider, (_, _) {});
    return SafeModeNoticeListener(
      child: PhoneStopWatcher(
        child: PopScope(
          canPop: !_open && !(selecting && sidebar),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            final selection = ref.read(drawerSelectionProvider.notifier);
            if (selection.active) {
              selection.end();
            } else {
              _closeDrawer();
            }
          },
          child: AnnotatedRegion<SystemUiOverlayStyle>(
            value: dshSystemOverlay(Theme.of(context).brightness),
            // 首页 / 对话 and the drawer: the custom wallpaper when one is in use.
            child: WallpaperBackdrop(
              child: _DrawerNoticeTheme(
                drawer: _drawer,
                identityBar: _identityBar,
                width: width,
                child: Scaffold(
                  backgroundColor: Colors.transparent,
                  // The chat screen handles the keyboard itself.
                  resizeToAvoidBottomInset: false,
                  body: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Notifications: routes taps, raises the in-app banner (draws nothing here).
                      ChatAlertHost(onReveal: _revealChat),
                      // Background running cut off by the phone: one line under the header (draws nothing here).
                      const BackgroundNetHost(),
                      // The voice model chosen during setup: download, resume, ready / failed notices (draws nothing).
                      const VoiceModelHost(),
                      // App links / shared files: routes them to their feature (draws nothing).
                      const LinkHost(),
                      // Share codes (分享码): registers its links and files with the router.
                      const ShareCodeHost(),
                      // Share sheet, launcher shortcuts, the tile: into the chat (draws nothing).
                      SystemEntryHost(onReveal: _revealChat),
                      // DS Bot: keeps its feed and notifications alive with the shell.
                      const BotAlertsHost(),
                      ExcludeSemantics(
                        excluding: _open,
                        child: _SideParallax(
                          drawer: _drawer,
                          drawerWidth: width,
                          child: AdaptiveScaffold(
                            layout: layout,
                            // Stored choices arriving at launch snap into place.
                            animate: prefs.loaded,
                            body: RawGestureDetector(
                              // translucent: join the hit chain without swallowing taps
                              // meant for the chat; wraps the whole chat column so empty
                              // areas still drag. Not 对话详情 beside it: its tabs swipe.
                              // No drawer to pull while the sidebar shows.
                              behavior: HitTestBehavior.translucent,
                              gestures: {if (!sidebar) ..._drawerGestures},
                              child: chat,
                            ),
                            sidebar: SessionsDrawer(
                              key: const ValueKey('persistent-sidebar'),
                              // It stays: picking a conversation just shows it.
                              onClose: () {},
                              onOpen: _openDestination,
                            ),
                            rail: AdaptiveRail(
                              onMenu: _onMenu,
                              menuTooltip: AdaptiveChrome.menuTooltipFor(layout),
                              onSearch: _search,
                              onHost: () =>
                                  showHostSheet(context, onManage: () => _openDestination(DrawerDestination.remote)),
                              onWeb: () => _openDestination(DrawerDestination.web),
                              onSettings: () => _openDestination(DrawerDestination.settings),
                            ),
                            panel: layout.panelAvailable && sessionId != null
                                ? SessionDetailPage.panel(key: ValueKey(sessionId), sessionId: sessionId)
                                : null,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        // The open drawer and its scrim take the swipe that pushes it
                        // back; closed, nothing here is hit.
                        child: RawGestureDetector(
                          behavior: HitTestBehavior.deferToChild,
                          gestures: _drawerGestures,
                          child: _DrawerOverlay(
                            animation: _drawer,
                            width: width,
                            drawer: SessionsDrawer(
                              onClose: _closeDrawer,
                              onOpen: _openDestination,
                              identityBarHeight: _identityBar,
                              drawerMotion: _drawer,
                            ),
                            onClose: _closeDrawer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// While the drawer is pulled over, notices (floating SnackBars without a
/// margin of their own) stand inside it: [SessionsDrawer.contentEdge] in from
/// either side of its content and [composerToastGap] above its identity bar,
/// clear of every key. Closed, the theme's placement is untouched; in
/// between they follow the drawer. Only SnackBars depend on this, so the
/// chat underneath still never rebuilds while the drawer moves.
class _DrawerNoticeTheme extends StatelessWidget {
  const _DrawerNoticeTheme({required this.drawer, required this.identityBar, required this.width, required this.child});

  final Animation<double> drawer;
  final ValueListenable<double> identityBar;

  /// The drawer's width, its content starting after the left inset.
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = SnackBarTheme.of(context);
    final closed = base.insetPadding;
    final screen = MediaQuery.sizeOf(context).width;
    final padding = MediaQuery.paddingOf(context);
    return AnimatedBuilder(
      animation: Listenable.merge([drawer, identityBar]),
      child: child,
      builder: (context, child) {
        final progress = drawer.value;
        var data = base;
        if (closed != null && progress > 0 && identityBar.value > 0) {
          // A floating SnackBar's margin lies inside the side insets (its
          // SafeArea) and stands on the bottom one, as the drawer's content does.
          final open = EdgeInsets.fromLTRB(
            SessionsDrawer.contentEdge,
            closed.top,
            math.max(0.0, screen - padding.right - width + SessionsDrawer.contentEdge),
            identityBar.value + composerToastGap,
          );
          data = base.copyWith(insetPadding: EdgeInsets.lerp(closed, open, progress));
        }
        return SnackBarTheme(data: data, child: child!);
      },
    );
  }
}

/// Scrim + drawer panel; the only part that rebuilds while the drawer moves. The
/// panel keeps its state when closed, while Visibility suppresses painting,
/// semantics and tickers until the first drag frame reveals it.
/// The fluid tier: as a side panel slides over, the page below drifts a little the
/// same way. Only a translation: scaling would make its glass re-sample at a new size.
class _SideParallax extends StatelessWidget {
  const _SideParallax({required this.drawer, required this.drawerWidth, required this.child});

  final Animation<double> drawer;
  final double drawerWidth;
  final Widget child;

  static const _share = 0.14;

  @override
  Widget build(BuildContext context) {
    final fluid = AppMotion.fluid(context);
    return AnimatedBuilder(
      animation: drawer,
      child: child,
      builder: (context, child) =>
          Transform.translate(offset: Offset(fluid ? _share * drawer.value * drawerWidth : 0, 0), child: child),
    );
  }
}

class _DrawerOverlay extends StatelessWidget {
  const _DrawerOverlay({required this.animation, required this.width, required this.drawer, required this.onClose});

  final Animation<double> animation;
  final double width;
  final Widget drawer;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scrim = DshSurfaces.of(context).scrim;
    return AnimatedBuilder(
      animation: animation,
      child: RepaintBoundary(child: drawer),
      builder: (context, drawer) {
        final progress = animation.value;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: progress == 0,
                child: GestureDetector(
                  onTap: onClose,
                  child: ColoredBox(color: scrim.withValues(alpha: scrim.a * progress)),
                ),
              ),
            ),
            // 面板位置用 Transform 走(paint-only):每帧改 Positioned.left 会让
            // Stack 和整块抽屉重新布局,拖动时白白多一层成本。
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: width,
              child: Visibility(
                visible: progress > 0,
                maintainState: true,
                child: Transform.translate(offset: Offset((progress - 1) * (width + 24), 0), child: drawer!),
              ),
            ),
          ],
        );
      },
    );
  }
}
