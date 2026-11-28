import 'dart:async';

import 'package:dsh_app/ui/common/undo_notice_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final same in [true, false]) {
    testWidgets('stale outer claim respects current identity: same=$same', (tester) async {
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(MaterialApp(scaffoldMessengerKey: key, home: const Scaffold()));
      final root = key.currentState!;
      final bIntent = reserveUndoNotice(root);
      final identity = Object();
      final bEnd = Completer<void>();
      final cEnd = same ? bEnd : Completer<void>();
      var bCancelled = 0;
      final cLease = reserveUndoNotice(root).claim(
        identity: same ? identity : Object(),
        canUndo: () => !cEnd.isCompleted,
        cancel: () {
          if (cEnd.isCompleted) return false;
          cEnd.complete();
          return true;
        },
        commit: () {
          if (cEnd.isCompleted) return false;
          cEnd.complete();
          return true;
        },
        windowClosed: cEnd.future,
      )!;
      addTearDown(() {
        if (!bEnd.isCompleted) bEnd.complete();
        if (!cEnd.isCompleted) cEnd.complete();
      });
      final result = bIntent.claim(
        identity: identity,
        canUndo: () => !bEnd.isCompleted,
        cancel: () {
          bCancelled++;
          bEnd.complete();
          return true;
        },
        commit: () {
          bCancelled++;
          bEnd.complete();
          return true;
        },
        windowClosed: bEnd.future,
      );
      if (same) {
        expect(identical(result, cLease), isTrue);
        expect(bCancelled, 0);
        expect(cEnd.isCompleted, isFalse);
      } else {
        expect(result, isNull);
        expect(bCancelled, 1);
        expect(cEnd.isCompleted, isFalse);
      }
      await tester.pump();
      expect(cLease.isCurrent, isTrue);
    });
  }
}
