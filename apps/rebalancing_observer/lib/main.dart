import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://engine.medicalnewshub.info',
);

void main() {
  runApp(const RebalancingObserverApp());
}

class RebalancingObserverApp extends StatelessWidget {
  const RebalancingObserverApp({
    super.key,
    this.initialSnapshot,
    this.apiClient,
  });

  final EngineSnapshot? initialSnapshot;
  final EngineApiClient? apiClient;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF111827),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Mino Engine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        useMaterial3: true,
        textTheme: Typography.blackCupertino.apply(
          bodyColor: const Color(0xFF202433),
          displayColor: const Color(0xFF202433),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w700,
              color: const Color(0xFF111827),
              letterSpacing: 0,
            ),
          ),
        ),
      ),
      home: ObserverHomePage(
        initialSnapshot: initialSnapshot,
        apiClient: apiClient ??
            (initialSnapshot == null
                ? EngineApiClient(apiBaseUrl)
                : EngineApiClient.disabled()),
      ),
    );
  }
}

class ObserverHomePage extends StatefulWidget {
  const ObserverHomePage({
    super.key,
    this.initialSnapshot,
    required this.apiClient,
  });

  final EngineSnapshot? initialSnapshot;
  final EngineApiClient apiClient;

  @override
  State<ObserverHomePage> createState() => _ObserverHomePageState();
}

class _ObserverHomePageState extends State<ObserverHomePage> {
  late Future<EngineSnapshot> _snapshotFuture;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = widget.initialSnapshot != null
        ? Future.value(widget.initialSnapshot)
        : widget.apiClient.fetchSnapshot();
  }

  void _refresh() {
    setState(() {
      _snapshotFuture = widget.apiClient.fetchSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EngineSnapshot>(
      future: _snapshotFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? EngineSnapshot.sample();
        final loading = snapshot.connectionState == ConnectionState.waiting;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                AppChrome(
                    snapshot: data, loading: loading, onRefresh: _refresh),
                const WatchGroupTabs(),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      WatchlistView(snapshot: data),
                      RegimeView(snapshot: data),
                      PortfolioView(snapshot: data),
                      RiskView(snapshot: data),
                      LogView(snapshot: data),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            height: 72,
            selectedIndex: _selectedTab,
            onDestinationSelected: (index) =>
                setState(() => _selectedTab = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.bookmark_border),
                selectedIcon: Icon(Icons.bookmark),
                label: '왓치리스트',
              ),
              NavigationDestination(
                icon: Icon(Icons.candlestick_chart_outlined),
                selectedIcon: Icon(Icons.candlestick_chart),
                label: '레짐',
              ),
              NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: '포지션',
              ),
              NavigationDestination(
                icon: Icon(Icons.groups_2_outlined),
                selectedIcon: Icon(Icons.groups_2),
                label: '리스크',
              ),
              NavigationDestination(
                icon: Icon(Icons.menu),
                selectedIcon: Icon(Icons.menu),
                label: '로그',
              ),
            ],
          ),
        );
      },
    );
  }
}

class AppChrome extends StatelessWidget {
  const AppChrome({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.onRefresh,
  });

  final EngineSnapshot snapshot;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '상태',
                onPressed: () {},
                icon: const Icon(Icons.more_horiz, size: 30),
              ),
              const Spacer(),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'M',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mino Engine',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '새로고침',
                onPressed: onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync, size: 28),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              StatusPill(
                  label: snapshot.regime, color: regimeColor(snapshot.regime)),
              const SizedBox(width: 8),
              StatusPill(label: snapshot.mode, color: modeColor(snapshot.mode)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${snapshot.source} · ${snapshot.lastUpdated}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Color(0xFF7A7F89),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class WatchGroupTabs extends StatelessWidget {
  const WatchGroupTabs({super.key});

  @override
  Widget build(BuildContext context) {
    const tabs = ['FUTURE', 'my', 'Regime', 'usdt'];
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 26),
        itemBuilder: (context, index) {
          final selected = tabs[index] == 'my';
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 24 : 0,
                vertical: selected ? 12 : 0,
              ),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFF0F0F0) : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                tabs[index],
                style: TextStyle(
                  color: selected ? Colors.black : const Color(0xFF777A80),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class WatchlistView extends StatelessWidget {
  const WatchlistView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: WatchListScaffold(
        items: snapshot.watchItems.isNotEmpty
            ? snapshot.watchItems
            : defaultWatchItems(snapshot),
      ),
    );
  }
}

class RegimeView extends StatelessWidget {
  const RegimeView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(items: decisionConsoleItems(snapshot));
  }
}

class PortfolioView extends StatelessWidget {
  const PortfolioView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(items: portfolioItems(snapshot));
  }
}

class RiskView extends StatelessWidget {
  const RiskView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(items: guardItems(snapshot));
  }
}

class LogView extends StatelessWidget {
  const LogView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(items: consoleItems(snapshot));
  }
}

class WatchListScaffold extends StatelessWidget {
  const WatchListScaffold({super.key, required this.items});

  final List<WatchItem> items;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 38, color: Color(0xFFE5E5E5)),
      itemBuilder: (context, index) => WatchRow(item: items[index]),
    );
  }
}

class WatchRow extends StatelessWidget {
  const WatchRow({super.key, required this.item});

  final WatchItem item;

  @override
  Widget build(BuildContext context) {
    final negative = item.change.trimLeft().startsWith('-');
    final changeColor = negative ? const Color(0xFFC8404A) : item.accent;
    final rightColumnWidth =
        (MediaQuery.sizeOf(context).width * 0.24).clamp(132.0, 260.0);

    return SizedBox(
      height: 96,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: item.accent.withValues(alpha: 0.12),
              child: Text(
                item.marker.toUpperCase(),
                style: TextStyle(
                  color: item.accent,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF202433),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF909399),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: rightColumnWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF202433),
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${item.change}  ${item.changePct}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: changeColor,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF7A7F89),
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class EngineApiClient {
  EngineApiClient(this.baseUrl, {http.Client? client})
      : _client = client ?? http.Client();

  EngineApiClient.disabled()
      : baseUrl = '',
        _client = null;

  final String baseUrl;
  final http.Client? _client;

  Future<EngineSnapshot> fetchSnapshot() async {
    final client = _client;
    if (client == null) {
      return EngineSnapshot.sample();
    }

    try {
      final response = await client
          .get(Uri.parse('$baseUrl/status'))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('status ${response.statusCode}');
      }

      return EngineSnapshot.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return EngineSnapshot.sample(source: 'Local project snapshot');
    }
  }
}

class EngineSnapshot {
  const EngineSnapshot({
    required this.source,
    required this.lastUpdated,
    required this.regime,
    required this.marketBias,
    required this.mode,
    required this.riskState,
    required this.regimeScore,
    required this.equity,
    required this.currentExposure,
    required this.targetExposure,
    required this.leverage,
    required this.dailyPnlPct,
    required this.weeklyPnlPct,
    required this.monthlyPnlPct,
    required this.cooldownUntil,
    required this.positions,
    required this.orders,
    required this.events,
    required this.watchItems,
  });

  final String source;
  final String lastUpdated;
  final String regime;
  final String marketBias;
  final String mode;
  final String riskState;
  final double regimeScore;
  final double equity;
  final double currentExposure;
  final double targetExposure;
  final double leverage;
  final double dailyPnlPct;
  final double weeklyPnlPct;
  final double monthlyPnlPct;
  final String? cooldownUntil;
  final List<PositionView> positions;
  final List<OrderView> orders;
  final List<EventView> events;
  final List<WatchItem> watchItems;

  factory EngineSnapshot.fromJson(Map<String, dynamic> json) {
    final positions = listOf(json['positions'], PositionView.fromJson);
    final orders = listOf(json['orders'], OrderView.fromJson);
    final events = listOf(json['events'], EventView.fromJson);
    final parsedWatchItems =
        listOf(json['watchlist'] ?? json['watchItems'], WatchItem.fromJson);

    final snapshot = EngineSnapshot(
      source: (json['source'] ?? 'Engine API').toString(),
      lastUpdated:
          (json['last_updated'] ?? json['lastUpdated'] ?? '-').toString(),
      regime: (json['regime'] ?? 'RANGE').toString(),
      marketBias:
          (json['market_bias'] ?? json['marketBias'] ?? 'RANGE').toString(),
      mode: (json['mode'] ?? 'NEUTRAL').toString(),
      riskState: (json['risk_state'] ?? json['riskState'] ?? 'OK').toString(),
      regimeScore: toDouble(json['regime_score'] ?? json['regimeScore']),
      equity: toDouble(json['equity']),
      currentExposure:
          toDouble(json['current_exposure'] ?? json['currentExposure']),
      targetExposure:
          toDouble(json['target_exposure'] ?? json['targetExposure']),
      leverage: toDouble(json['leverage']),
      dailyPnlPct: toDouble(json['daily_pnl_pct'] ?? json['dailyPnlPct']),
      weeklyPnlPct: toDouble(json['weekly_pnl_pct'] ?? json['weeklyPnlPct']),
      monthlyPnlPct: toDouble(json['monthly_pnl_pct'] ?? json['monthlyPnlPct']),
      cooldownUntil:
          (json['cooldown_until'] ?? json['cooldownUntil'])?.toString(),
      positions: positions,
      orders: orders,
      events: events,
      watchItems: parsedWatchItems,
    );

    if (snapshot.watchItems.isNotEmpty) {
      return snapshot;
    }
    return snapshot.copyWith(watchItems: defaultWatchItems(snapshot));
  }

  static EngineSnapshot sample({String source = 'Local project snapshot'}) {
    final snapshot = EngineSnapshot(
      source: source,
      lastUpdated: '2026-05-19 23:43 KST',
      regime: 'RANGE',
      marketBias: 'WEBHOOK_ACCEPTED',
      mode: 'OBSERVE',
      riskState: 'OK',
      regimeScore: 0,
      equity: 0,
      currentExposure: 0,
      targetExposure: 0,
      leverage: 0,
      dailyPnlPct: 0,
      weeklyPnlPct: 0,
      monthlyPnlPct: 0,
      cooldownUntil: null,
      positions: const [],
      orders: const [],
      events: const [
        EventView(
            time: '23:43',
            kind: 'ALERT',
            message: 'TradingView webhook accepted by Cloudflare Worker'),
        EventView(
            time: '23:43',
            kind: 'DECISION',
            message: 'RANGE signal keeps engine in observe mode'),
        EventView(
            time: '23:42',
            kind: 'SECRET',
            message: 'TV_WEBHOOK_PASSPHRASE synced with TradingView input'),
        EventView(
            time: '23:35',
            kind: 'WORKER',
            message: 'tradingview-webhook deployed on workers.dev'),
      ],
      watchItems: const [],
    );

    return snapshot.copyWith(watchItems: defaultWatchItems(snapshot));
  }

  EngineSnapshot copyWith({List<WatchItem>? watchItems}) {
    return EngineSnapshot(
      source: source,
      lastUpdated: lastUpdated,
      regime: regime,
      marketBias: marketBias,
      mode: mode,
      riskState: riskState,
      regimeScore: regimeScore,
      equity: equity,
      currentExposure: currentExposure,
      targetExposure: targetExposure,
      leverage: leverage,
      dailyPnlPct: dailyPnlPct,
      weeklyPnlPct: weeklyPnlPct,
      monthlyPnlPct: monthlyPnlPct,
      cooldownUntil: cooldownUntil,
      positions: positions,
      orders: orders,
      events: events,
      watchItems: watchItems ?? this.watchItems,
    );
  }
}

class PositionView {
  const PositionView(
      {required this.symbol, required this.side, required this.notional});

  final String symbol;
  final String side;
  final double notional;

  factory PositionView.fromJson(Map<String, dynamic> json) {
    return PositionView(
      symbol: (json['symbol'] ?? '-').toString(),
      side: (json['side'] ?? '-').toString(),
      notional: toDouble(json['notional']),
    );
  }
}

class OrderView {
  const OrderView({
    required this.symbol,
    required this.action,
    required this.notional,
    required this.reduceOnly,
  });

  final String symbol;
  final String action;
  final double notional;
  final bool reduceOnly;

  factory OrderView.fromJson(Map<String, dynamic> json) {
    return OrderView(
      symbol: (json['symbol'] ?? '-').toString(),
      action: (json['action'] ?? json['side'] ?? '-').toString(),
      notional: toDouble(json['notional']),
      reduceOnly: json['reduce_only'] == true || json['reduceOnly'] == true,
    );
  }
}

class EventView {
  const EventView(
      {required this.time, required this.kind, required this.message});

  final String time;
  final String kind;
  final String message;

  factory EventView.fromJson(Map<String, dynamic> json) {
    return EventView(
      time: (json['time'] ?? '-').toString(),
      kind: (json['kind'] ?? '-').toString(),
      message: (json['message'] ?? '-').toString(),
    );
  }
}

class WatchItem {
  const WatchItem({
    required this.symbol,
    required this.title,
    required this.value,
    required this.change,
    required this.changePct,
    required this.accent,
    required this.marker,
    this.meta = '',
  });

  final String symbol;
  final String title;
  final String value;
  final String change;
  final String changePct;
  final Color accent;
  final String marker;
  final String meta;

  factory WatchItem.fromJson(Map<String, dynamic> json) {
    return WatchItem(
      symbol: (json['symbol'] ?? '-').toString(),
      title: (json['title'] ?? json['name'] ?? '-').toString(),
      value: (json['value'] ?? '-').toString(),
      change: (json['change'] ?? '').toString(),
      changePct: (json['change_pct'] ?? json['changePct'] ?? '').toString(),
      accent: parseColor(json['color']) ?? const Color(0xFF2F8F75),
      marker: firstMarker((json['marker'] ?? json['symbol'] ?? '?').toString()),
      meta: (json['meta'] ?? '').toString(),
    );
  }
}

List<WatchItem> projectProgressItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: 'WEBHOOK',
      title: 'TradingView -> Cloudflare Worker',
      value: '수신됨',
      change: '202 Accepted',
      changePct: 'live',
      accent: const Color(0xFF2F8F75),
      marker: 'W',
      meta: 'URL active',
    ),
    WatchItem(
      symbol: 'SIGNAL',
      title: '최근 alert 기준 판단',
      value: decisionLabel(snapshot),
      change: snapshot.regime,
      changePct: snapshot.mode,
      accent: regimeColor(snapshot.regime),
      marker: 'S',
      meta: snapshot.marketBias,
    ),
    WatchItem(
      symbol: 'APP',
      title: 'Flutter observer cleanup',
      value: '진행중',
      change: 'read only',
      changePct: 'console',
      accent: const Color(0xFF2563EB),
      marker: 'A',
      meta: 'No trade controls',
    ),
    WatchItem(
      symbol: 'ENGINE',
      title: 'Private execution engine hookup',
      value: '대기',
      change: 'Queue/Tunnel',
      changePct: 'next',
      accent: const Color(0xFFC08A17),
      marker: 'E',
      meta: 'Binance keys stay server-side',
    ),
    WatchItem(
      symbol: 'LIVE',
      title: '자동 실거래 전 단계',
      value: '미시작',
      change: 'paper first',
      changePct: 'safe',
      accent: const Color(0xFF787B86),
      marker: 'L',
      meta: '30 days target',
    ),
  ];
}

List<WatchItem> decisionConsoleItems(EngineSnapshot snapshot) {
  final alert = latestEvent(snapshot, 'ALERT');
  return [
    WatchItem(
      symbol: 'CONSOLE',
      title: alert?.message ?? 'Waiting for TradingView alert',
      value: decisionLabel(snapshot),
      change: snapshot.regime,
      changePct: snapshot.marketBias,
      accent: regimeColor(snapshot.regime),
      marker: '>',
      meta: alert?.time ?? snapshot.lastUpdated,
    ),
    WatchItem(
      symbol: 'REGIME',
      title: 'Webhook payload decision field',
      value: snapshot.regime,
      change: decisionDetail(snapshot),
      changePct: snapshot.mode,
      accent: regimeColor(snapshot.regime),
      marker: 'R',
      meta: 'No manual override',
    ),
    WatchItem(
      symbol: 'TARGET',
      title: 'Target exposure from engine snapshot',
      value: compactUsdt(snapshot.targetExposure),
      change: 'Lev ${snapshot.leverage.toStringAsFixed(2)}x',
      changePct: 'Max 2x',
      accent: snapshot.leverage <= 2
          ? const Color(0xFF2F8F75)
          : const Color(0xFFC8404A),
      marker: 'T',
      meta: 'Current ${compactUsdt(snapshot.currentExposure)}',
    ),
    WatchItem(
      symbol: 'ACTION',
      title: '앱은 판단 표시만 수행',
      value: '관전',
      change: 'no buttons',
      changePct: 'read only',
      accent: const Color(0xFF2563EB),
      marker: 'A',
      meta: snapshot.source,
    ),
  ];
}

List<WatchItem> portfolioItems(EngineSnapshot snapshot) {
  final items = snapshot.positions
      .map(
        (position) => WatchItem(
          symbol: position.symbol,
          title: position.side,
          value: compactUsdt(position.notional),
          change: position.side,
          changePct: snapshot.equity <= 0 || position.notional == 0
              ? '0.00%'
              : '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%',
          accent: sideColor(position.side),
          marker: firstMarker(position.symbol),
          meta: 'Current Binance position',
        ),
      )
      .toList(growable: true);

  if (items.isEmpty) {
    items.add(
      WatchItem(
        symbol: 'FLAT',
        title: 'No open Binance futures position',
        value: compactUsdt(snapshot.currentExposure),
        change: 'neutral',
        changePct: '0.00%',
        accent: const Color(0xFF787B86),
        marker: 'F',
        meta: 'Read-only observer',
      ),
    );
  }

  for (final order in snapshot.orders.take(6)) {
    items.add(
      WatchItem(
        symbol: order.symbol,
        title: '${order.action}${order.reduceOnly ? ' · reduce-only' : ''}',
        value: compactUsdt(order.notional),
        change: order.action,
        changePct: order.reduceOnly ? 'reduce' : 'entry',
        accent: order.reduceOnly
            ? const Color(0xFFC08A17)
            : const Color(0xFF2563EB),
        marker: firstMarker(order.symbol),
        meta: 'Planned order',
      ),
    );
  }

  return items;
}

List<WatchItem> pipelineItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: '1 TV',
      title: 'Alert JSON emits schema/passphrase/time_ms',
      value: '완료',
      change: 'accepted',
      changePct: '400 fixed',
      accent: const Color(0xFF2F8F75),
      marker: '1',
      meta: latestEvent(snapshot, 'ALERT')?.time ?? snapshot.lastUpdated,
    ),
    WatchItem(
      symbol: '2 WORKER',
      title: 'Validation, stale check, dedupe',
      value: '운영중',
      change: 'workers.dev',
      changePct: 'KV on',
      accent: const Color(0xFF2F8F75),
      marker: '2',
      meta: 'tradingview-webhook',
    ),
    WatchItem(
      symbol: '3 ENGINE',
      title: 'Queue/Tunnel consumer and state store',
      value: '남음',
      change: 'connect',
      changePct: 'next',
      accent: const Color(0xFFC08A17),
      marker: '3',
      meta: 'Private API /status',
    ),
    WatchItem(
      symbol: '4 APP',
      title: 'Read-only status polling',
      value: '정리중',
      change: 'tabs kept',
      changePct: 'console only',
      accent: const Color(0xFF2563EB),
      marker: '4',
      meta: snapshot.source,
    ),
    WatchItem(
      symbol: '5 BINANCE',
      title: 'Paper mode before live execution',
      value: '잠금',
      change: 'no live',
      changePct: 'pending',
      accent: const Color(0xFF787B86),
      marker: '5',
      meta: 'No app-side keys',
    ),
  ];
}

List<WatchItem> guardItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: 'DAILY',
      title: 'Daily loss guard',
      value: pct(snapshot.dailyPnlPct),
      change: snapshot.dailyPnlPct <= -2 ? '-blocked' : '+OK',
      changePct: 'Limit -2.00%',
      accent: snapshot.dailyPnlPct <= -2
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'D',
      meta: 'Block new entries',
    ),
    WatchItem(
      symbol: 'WEEKLY',
      title: 'Weekly reduction guard',
      value: pct(snapshot.weeklyPnlPct),
      change: snapshot.weeklyPnlPct <= -5 ? '-reduce' : '+OK',
      changePct: 'Limit -5.00%',
      accent: snapshot.weeklyPnlPct <= -5
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'W',
      meta: 'Reduce 50%',
    ),
    WatchItem(
      symbol: 'MONTHLY',
      title: 'Monthly stop guard',
      value: pct(snapshot.monthlyPnlPct),
      change: snapshot.monthlyPnlPct <= -10 ? '-pause' : '+OK',
      changePct: 'Limit -10.00%',
      accent: snapshot.monthlyPnlPct <= -10
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'M',
      meta: 'Close all and pause',
    ),
    WatchItem(
      symbol: 'LEVERAGE',
      title: 'Total exposure cap',
      value: '${snapshot.leverage.toStringAsFixed(2)}x',
      change: snapshot.leverage <= 2 ? '+within' : '-over',
      changePct: 'Max 2.00x',
      accent: snapshot.leverage <= 2
          ? const Color(0xFF2F8F75)
          : const Color(0xFFC8404A),
      marker: 'L',
      meta: 'Equity based',
    ),
    WatchItem(
      symbol: 'COOLDOWN',
      title: snapshot.cooldownUntil ?? 'No active cooldown',
      value: snapshot.riskState,
      change: 'auto',
      changePct: 'read only',
      accent: riskColor(snapshot.riskState),
      marker: 'C',
      meta: 'No app-side order control',
    ),
  ];
}

List<WatchItem> consoleItems(EngineSnapshot snapshot) {
  final items = snapshot.events
      .map(
        (event) => WatchItem(
          symbol: event.kind,
          title: event.message,
          value: event.time,
          change: event.kind.toLowerCase(),
          changePct: snapshot.source,
          accent: eventColor(event.kind),
          marker: eventMarker(event.kind),
          meta: 'Project log',
        ),
      )
      .toList(growable: true);

  if (items.isEmpty) {
    items.add(
      WatchItem(
        symbol: 'WAITING',
        title: 'No engine log has been received yet',
        value: '-',
        change: 'polling',
        changePct: snapshot.source,
        accent: const Color(0xFF787B86),
        marker: '?',
        meta: snapshot.lastUpdated,
      ),
    );
  }

  return items;
}

List<WatchItem> defaultWatchItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: 'BTCUSDT',
      title: 'Bitcoin perpetual',
      value: snapshot.mode,
      change: snapshot.regime,
      changePct: snapshot.marketBias,
      accent: const Color(0xFFF7931A),
      marker: 'B',
      meta: 'Signal source',
    ),
    WatchItem(
      symbol: 'EQUITY',
      title: 'USDT-M account equity',
      value: compactUsdt(snapshot.equity),
      change: 'Lev ${snapshot.leverage.toStringAsFixed(2)}x',
      changePct: 'Target ${compactUsdt(snapshot.targetExposure)}',
      accent: const Color(0xFF2563EB),
      marker: 'E',
      meta: snapshot.source,
    ),
    WatchItem(
      symbol: 'RISK',
      title: snapshot.riskState,
      value: pct(snapshot.dailyPnlPct),
      change: 'W ${pct(snapshot.weeklyPnlPct)}',
      changePct: 'M ${pct(snapshot.monthlyPnlPct)}',
      accent: riskColor(snapshot.riskState),
      marker: 'R',
      meta: snapshot.cooldownUntil ?? 'No cooldown',
    ),
    ...snapshot.positions.map(
      (position) => WatchItem(
        symbol: position.symbol,
        title: position.side,
        value: compactUsdt(position.notional),
        change: position.side,
        changePct: snapshot.equity <= 0 || position.notional == 0
            ? '0.00%'
            : '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%',
        accent: sideColor(position.side),
        marker: firstMarker(position.symbol),
        meta: 'Current position',
      ),
    ),
  ];
}

WatchItem riskItem(
    String symbol, String title, double pnl, String limit, String marker) {
  return WatchItem(
    symbol: symbol,
    title: title,
    value: pct(pnl),
    change: pnl >= 0 ? '+OK' : pct(pnl),
    changePct: 'Limit $limit',
    accent: pnl < 0 ? const Color(0xFFC8404A) : const Color(0xFF2F8F75),
    marker: marker,
    meta: 'Auto guard',
  );
}

EventView? latestEvent(EngineSnapshot snapshot, String kind) {
  for (final event in snapshot.events) {
    if (event.kind == kind) {
      return event;
    }
  }
  return null;
}

String decisionLabel(EngineSnapshot snapshot) {
  return switch (snapshot.regime) {
    'TOP10_LONG' => '상위10 롱',
    'BTC_ETH_LONG' => 'BTC/ETH 롱',
    'ALT_WEAK_SHORT' => '알트 약세 숏',
    'SHORT_MODE' => '숏 모드',
    'CHAOTIC' => '정지',
    _ => '관망',
  };
}

String decisionDetail(EngineSnapshot snapshot) {
  return switch (snapshot.regime) {
    'TOP10_LONG' => 'long basket',
    'BTC_ETH_LONG' => 'major only',
    'ALT_WEAK_SHORT' => 'short weak alts',
    'SHORT_MODE' => 'short guarded',
    'CHAOTIC' => 'pause entries',
    _ => 'no entry',
  };
}

Color eventColor(String kind) {
  return switch (kind) {
    'ERROR' => const Color(0xFFC8404A),
    'SECRET' || 'ALERT' || 'WORKER' => const Color(0xFF2F8F75),
    'DECISION' => const Color(0xFF2563EB),
    _ => const Color(0xFF787B86),
  };
}

String eventMarker(String kind) {
  return firstMarker(kind);
}

String firstMarker(String value) {
  if (value.isEmpty) return '?';
  return value.characters.first;
}

List<T> listOf<T>(Object? raw, T Function(Map<String, dynamic>) parser) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => parser(Map<String, dynamic>.from(item)))
      .toList(growable: false);
}

double toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String compactUsdt(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  if (absolute >= 1000000) {
    return '$sign${(absolute / 1000000).toStringAsFixed(2)}M';
  }
  if (absolute >= 1000) {
    return '$sign${(absolute / 1000).toStringAsFixed(2)}K';
  }
  return '$sign${absolute.toStringAsFixed(absolute >= 100 ? 0 : 2)}';
}

String pct(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';

Color regimeColor(String regime) {
  return switch (regime) {
    'BULL' || 'TOP10_LONG' => const Color(0xFF2F8F75),
    'BEAR' || 'SHORT_MODE' || 'ALT_WEAK_SHORT' => const Color(0xFFC8404A),
    'CHAOTIC' => const Color(0xFF8F3FA8),
    _ => const Color(0xFF787B86),
  };
}

Color modeColor(String mode) {
  return switch (mode) {
    'LONG' => const Color(0xFF2F8F75),
    'SHORT' => const Color(0xFFC8404A),
    'OBSERVE' => const Color(0xFF2563EB),
    'PAUSED' => const Color(0xFF8F3FA8),
    _ => const Color(0xFF787B86),
  };
}

Color sideColor(String side) {
  return switch (side) {
    'LONG' => const Color(0xFF2F8F75),
    'SHORT' => const Color(0xFFC8404A),
    'FLAT' => const Color(0xFF787B86),
    _ => const Color(0xFF2563EB),
  };
}

Color riskColor(String risk) {
  return switch (risk) {
    'OK' || 'NONE' => const Color(0xFF2F8F75),
    'BLOCK_NEW_ENTRIES' => const Color(0xFFC08A17),
    'REDUCE_HALF' => const Color(0xFFC08A17),
    'CLOSE_ALL_AND_PAUSE' => const Color(0xFFC8404A),
    _ => const Color(0xFF787B86),
  };
}

Color? parseColor(Object? raw) {
  if (raw is! String) return null;
  final normalized = raw.replaceAll('#', '');
  if (normalized.length != 6) return null;
  final value = int.tryParse('FF$normalized', radix: 16);
  if (value == null) return null;
  return Color(value);
}
