import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rebalancing_observer/main.dart';

void main() {
  test('snapshot parses learning status payload', () {
    final snapshot = EngineSnapshot.fromJson({
      'source': 'Engine API',
      'last_updated': '2026-05-23T01:20:00+09:00',
      'regime': 'RANGE',
      'market_bias': 'PAPER',
      'mode': 'OBSERVE',
      'risk_state': 'OK',
      'market_internals': <String, Object?>{},
      'positions': [],
      'orders': [],
      'events': [],
      'watchlist': [],
      'learning': {
        'stage': 'BABY',
        'run_count': 2,
        'evaluation_count': 1,
        'param_version_count': 1,
        'trade_result_count': 3,
        'latest_run': {
          'status': 'ok',
          'trigger': 'scheduler',
          'ts': '2026-05-23T01:20:00+09:00',
        },
        'latest_evaluation': {
          'summary': 'range 민감도 조정',
          'ts': '2026-05-23T01:20:00+09:00',
        },
        'active_params': {
          'version': 3,
          'range_target_leverage': 0.5,
          'confirmation_candles': 2,
          'min_neutral_hours': 6,
        },
      },
    });

    expect(snapshot.learning.stage, 'BABY');
    expect(snapshot.learning.evaluationCount, 1);
    expect(snapshot.learning.activeParamVersion, 3);
    expect(summaryItems(snapshot).map((item) => item.symbol), contains('학습'));
  });

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

    expect(find.text('운영 요약'), findsOneWidget);
    expect(find.text('손익 추이'), findsOneWidget);
    expect(find.text('요약'), findsWidgets);
    expect(find.text('학습'), findsWidgets);
    expect(find.text('포지션'), findsWidgets);
    expect(find.text('주문'), findsWidgets);
    expect(find.text('시장'), findsWidgets);
    expect(find.text('로그'), findsWidgets);
    expect(find.text('레짐'), findsOneWidget);
    expect(find.text('자산'), findsOneWidget);
    expect(find.text('횡보'), findsWidgets);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.textContaining('Approve'), findsNothing);
    expect(find.textContaining('매수'), findsNothing);
    expect(find.textContaining('매도'), findsNothing);
  });

  testWidgets('alert log opens engine result details', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RebalancingObserverApp(initialSnapshot: EngineSnapshot.sample()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('로그').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('트레이딩뷰 웹훅').first);
    await tester.pumpAndSettle();

    expect(find.text('엔진 결과'), findsOneWidget);
    expect(find.text('TradingView'), findsOneWidget);
    expect(find.text('Engine'), findsOneWidget);
    expect(find.text('Learning'), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Signal Flags'), findsOneWidget);
    expect(find.text('주문'), findsWidgets);
    expect(find.textContaining('매수'), findsNothing);
    expect(find.textContaining('매도'), findsNothing);
  });

  testWidgets('log tab shows visual rebalance flow above compact logs',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      RebalancingObserverApp(initialSnapshot: EngineSnapshot.sample()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('로그').last);
    await tester.pumpAndSettle();

    expect(find.text('2개 포지션을 담았어요'), findsOneWidget);
    expect(find.text('매수'), findsOneWidget);
    expect(find.textContaining('BTCUSDT'), findsWidgets);
    expect(find.textContaining('트레이딩뷰 웹훅'), findsWidgets);
  });

  testWidgets('position tab opens position details', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final snapshot = EngineSnapshot.fromJson({
      'source': 'Paper trading',
      'last_updated': '2026-05-20T12:00:00Z',
      'regime': 'TOP10_LONG',
      'market_bias': 'BROAD_BULL',
      'mode': 'LONG',
      'risk_state': 'OK',
      'regime_score': 40,
      'equity': 1000,
      'current_exposure': 300,
      'target_exposure': 500,
      'leverage': 0.3,
      'daily_pnl_pct': 0,
      'weekly_pnl_pct': 0,
      'monthly_pnl_pct': 0,
      'market_internals': <String, Object?>{},
      'positions': [
        {
          'symbol': 'BTCUSDT',
          'side': 'LONG',
          'quantity': 0.003,
          'notional': 300,
          'entry_price': 100000,
          'mark_price': 101000,
          'unrealized_pnl': 3,
          'leverage': 2,
          'margin_type': 'cross',
        },
      ],
      'orders': [],
      'events': [],
      'watchlist': [],
    });

    await tester.pumpWidget(RebalancingObserverApp(initialSnapshot: snapshot));
    await tester.pumpAndSettle();

    await tester.tap(find.text('포지션').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('BTCUSDT').first);
    await tester.pumpAndSettle();

    expect(find.text('포지션 상세'), findsOneWidget);
    expect(find.text('진입가'), findsOneWidget);
    expect(find.text('마크가'), findsOneWidget);
    expect(find.text('미실현 손익'), findsOneWidget);
    expect(find.text('+3.00'), findsOneWidget);
  });
}
