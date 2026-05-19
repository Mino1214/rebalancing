import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rebalancing_observer/main.dart';

void main() {
  testWidgets('observer app renders watchlist tabs in read-only mode',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RebalancingObserverApp(initialSnapshot: EngineSnapshot.sample()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mino Engine'), findsOneWidget);
    expect(find.text('요약'), findsWidgets);
    expect(find.text('포지션'), findsWidgets);
    expect(find.text('주문'), findsWidgets);
    expect(find.text('시장'), findsWidgets);
    expect(find.text('로그'), findsWidgets);
    expect(find.text('레짐'), findsOneWidget);
    expect(find.text('자산'), findsOneWidget);
    expect(find.text('횡보'), findsWidgets);
    expect(find.text('관망'), findsWidgets);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.textContaining('매수'), findsNothing);
    expect(find.textContaining('매도'), findsNothing);
  });
}
