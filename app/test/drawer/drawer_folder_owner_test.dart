// Real drawer folder actions and persisted per-Host views. UNRUN fixture.
import 'dart:convert';

import 'package:dsh_app/ui/shell/drawer/drawer_filter_bar.dart';
import 'package:dsh_app/runtime/runtime_state.dart';
import 'package:dsh_app/state/connection_state.dart';
import 'package:dsh_app/state/drawer_view_state.dart';
import 'package:dsh_app/state/hosts_state.dart';
import 'package:dsh_app/state/sessions_state.dart';
import 'package:dsh_app/state/settings_state.dart';
import 'package:dsh_app/state/workspaces_state.dart';
import 'package:dsh_app/ui/shell/drawer/folder_header.dart';
import 'package:dsh_app/ui/shell/home_shell.dart';
import 'package:dsh_app/ui/chat/composer_toast.dart';
import 'package:dsh_app/ui/common/brief_notice.dart';
import 'package:dsh_app/ui/shell/drawer/drawer_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../shell/golden_harness.dart';
import '../state/read_list_refresh_test.dart' show SwitchConnection, switchConnectionProvider;
import '../workspace/support.dart';
import 'support.dart';

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  await tester.pump(const Duration(milliseconds: 450));
}

void _seed(DrawerHost host, String label) {
  host.seedSession('s1', '$label first', DateTime(2026, 10, 28, 10));
  host.seedSession('s2', '$label second', DateTime(2026, 10, 28, 9));
  host.seedWorkspace('/root/$label', sessionIds: ['s1', 's2']);
}

const _aView = DrawerView(
  loaded: true,
  folders: [
    DrawerFolder(id: 'f1', name: 'A folder', sessionIds: ['s1']),
  ],
);

Future<(ProviderContainer, DrawerView)> _start(WidgetTester tester, {required bool sameFolderId}) async {
  final bView = DrawerView(
    loaded: true,
    folders: [
      DrawerFolder(id: sameFolderId ? 'f1' : 'fb', name: 'B folder', sessionIds: ['s2']),
    ],
  );
  SharedPreferences.setMockInitialValues({
    DrawerViewController.keyFor(HostRef.local): jsonEncode(_aView.toJson()),
    DrawerViewController.keyFor(const HostRef.ssh('pc')): jsonEncode(bView.toJson()),
  });
  final hostA = DrawerHost();
  _seed(hostA, 'A');
  final connectionA = workspaceHost(hostA);
  addTearDown(connectionA.client.close);
  usePhoneSurface(tester);
  await tester.pumpWidget(
    goldenApp(
      brightness: Brightness.light,
      home: HomeShell(chatBuilder: (_) => const SizedBox.expand(), initiallyOpen: true),
      overrides: [
        localRuntimeProvider.overrideWith(
          () => FakeRuntime(const LocalRuntimeState(loaded: true, status: runningStatus)),
        ),
        settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true, phoneStorage: true))),
        workspacePrefsProvider.overrideWith(() => FixedWorkspacePrefs(const WorkspacePrefs(loaded: true))),
        currentSessionProvider.overrideWith(() => FakeCurrentSession(null)),
        switchConnectionProvider.overrideWith(() => SwitchConnection(connectionA)),
        activeConnectionProvider.overrideWith((ref) => ref.watch(switchConnectionProvider)),
      ],
    ),
  );
  await _settle(tester);
  final container = ProviderScope.containerOf(tester.element(find.byType(HomeShell)));
  expect(container.read(drawerViewProvider).toJson(), _aView.toJson());
  expect(find.widgetWithText(DrawerFolderHeader, 'A folder'), findsOneWidget);
  return (container, bView);
}

Future<void> _openFolderActions(WidgetTester tester) async {
  await tester.longPress(find.widgetWithText(DrawerFolderHeader, 'A folder'));
  await _settle(tester);
  expect(find.text('删除文件夹'), findsOneWidget);
}

void main() {
  for (final composer in [false, true]) {
    testWidgets('${composer ? 'composer' : 'brief'} replacement lets queued folder deletion finish', (tester) async {
      final (container, _) = await _start(tester, sameFolderId: false);
      final element = tester.element(find.byType(HomeShell));
      final messenger = ScaffoldMessenger.of(element);
      messenger.showSnackBar(const SnackBar(content: Text('earlier notice')));
      await tester.pumpAndSettle();
      var completed = false;
      final operation = folderActionsFlow(element, element as WidgetRef, _aView.folders.single).then((_) {
        completed = true;
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件夹'));
      await tester.idle();
      expect(container.read(drawerViewProvider).folders, isEmpty);
      expect(completed, isFalse);
      if (composer) {
        showComposerToast(element, 'replacement', composerHeight: 60);
      } else {
        messenger.showBriefNotice('replacement');
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      await operation;
    });
  }

  testWidgets('same Host folder creation still saves its name and returns to drawer', (tester) async {
    final (container, bView) = await _start(tester, sameFolderId: false);
    await tester.tap(find.byType(DrawerViewButton));
    await _settle(tester);
    await tester.tap(find.text('新建文件夹'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField), 'new folder');
    await tester.pump();
    await tester.tap(find.text('创建'));
    await _settle(tester);
    final prefs = await SharedPreferences.getInstance();
    final saved = DrawerView.fromJson(jsonDecode(prefs.getString(DrawerViewController.keyFor(HostRef.local))!));
    expect(saved.folders.map((f) => f.name), ['new folder', 'A folder']);
    expect(container.read(drawerViewProvider).toJson(), saved.toJson());
    expect(jsonDecode(prefs.getString(DrawerViewController.keyFor(const HostRef.ssh('pc')))!), bView.toJson());
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed container retires retained folder Undo callback', (tester) async {
    await _start(tester, sameFolderId: false);
    await _openFolderActions(tester);
    await tester.tap(find.text('删除文件夹'));
    await _settle(tester);
    final undo = tester.widget<SnackBarAction>(find.byType(SnackBarAction)).onPressed;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    undo();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('same Host undo preserves newly assigned members', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    await _openFolderActions(tester);
    await tester.tap(find.text('删除文件夹'));
    await _settle(tester);
    final view = container.read(drawerViewProvider.notifier);
    final newId = await view.createFolder('new owner', sessionIds: ['s1']);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(container.read(drawerViewProvider).byId('f1')!.sessionIds, isEmpty);
    expect(container.read(drawerViewProvider).folderOf['s1'], newId);
  });

  testWidgets('same Host undo does not overwrite a replacement with same id', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    await _openFolderActions(tester);
    await tester.tap(find.text('删除文件夹'));
    await _settle(tester);
    const replacement = DrawerFolder(id: 'f1', name: 'replacement', sessionIds: ['s2']);
    await container.read(drawerViewProvider.notifier).restoreFolder(replacement, 0);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(container.read(drawerViewProvider).byId('f1')!.toJson(), replacement.toJson());
  });

  testWidgets('offline same Host folder undo needs no live connection', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    await _openFolderActions(tester);
    await tester.tap(find.text('删除文件夹'));
    await _settle(tester);
    container.read(switchConnectionProvider.notifier).set(null);
    await tester.pump();
    expect(container.read(activeConnectionProvider).value, isNull);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(container.read(drawerViewProvider).toJson(), _aView.toJson());
  });

  testWidgets('delete rechecks owner after its loading await', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    var owned = true;
    final operation = container.read(drawerViewProvider.notifier).deleteFolder('f1', isCurrent: () => owned);
    owned = false;
    expect(await operation, isNull);
    expect(container.read(drawerViewProvider).toJson(), _aView.toJson());
  });

  testWidgets('restore rechecks owner after its update await', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    final view = container.read(drawerViewProvider.notifier);
    final removed = (await view.deleteFolder('f1'))!;
    var owned = true;
    final operation = view.restoreFolder(removed.$1, removed.$2, isCurrent: () => owned);
    owned = false;
    await operation;
    expect(container.read(drawerViewProvider).folders, isEmpty);
  });

  testWidgets('same Host folder delete and undo restores the original persisted view', (tester) async {
    final (container, _) = await _start(tester, sameFolderId: false);
    await _openFolderActions(tester);
    await tester.tap(find.text('删除文件夹'));
    await _settle(tester);
    expect(container.read(drawerViewProvider).folders, isEmpty);
    expect(find.text('撤销').hitTestable(), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await _settle(tester);
    expect(container.read(drawerViewProvider).toJson(), _aView.toJson());
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString(DrawerViewController.keyFor(HostRef.local))!), _aView.toJson());
    expect(tester.takeException(), isNull);
  });
}
