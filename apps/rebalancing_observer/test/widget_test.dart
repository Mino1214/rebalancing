import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rebalancing_observer/main.dart';

void main() {
  testWidgets('observer dashboard renders read-only state', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RebalancingObserverApp(initialSnapshot: EngineSnapshot.sample()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rebalancing Observer'), findsOneWidget);
    expect(find.text('RANGE'), findsWidgets);
    expect(find.text('Positions'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Risk'), findsOneWidget);
    expect(find.text('Events'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.textContaining('Approve'), findsNothing);
  });
}
