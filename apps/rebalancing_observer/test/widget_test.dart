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
    expect(find.text('SUMMARY'), findsOneWidget);
    expect(find.text('position'), findsOneWidget);
    expect(find.text('orders'), findsOneWidget);
    expect(find.text('market'), findsOneWidget);
    expect(find.text('logs'), findsOneWidget);
    expect(find.text('요약'), findsOneWidget);
    expect(find.text('포지션'), findsOneWidget);
    expect(find.text('주문'), findsOneWidget);
    expect(find.text('시장'), findsOneWidget);
    expect(find.text('로그'), findsOneWidget);
    expect(find.text('REGIME'), findsOneWidget);
    expect(find.text('EQUITY'), findsOneWidget);
    expect(find.text('RANGE'), findsWidgets);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.textContaining('매수'), findsNothing);
    expect(find.textContaining('매도'), findsNothing);
  });
}
