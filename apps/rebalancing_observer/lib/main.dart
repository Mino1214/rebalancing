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
      seedColor: const Color(0xFF008C7A),
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'Rebalancing Observer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF6F8FA),
        useMaterial3: true,
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE1E5EA)),
          ),
          margin: EdgeInsets.zero,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF17202A),
          elevation: 0,
          centerTitle: false,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rebalancing Observer'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<EngineSnapshot>(
        future: _snapshotFuture,
        builder: (context, snapshot) {
          final data = snapshot.data ?? EngineSnapshot.sample();
          final loading = snapshot.connectionState == ConnectionState.waiting;
          final error = snapshot.hasError ? snapshot.error.toString() : null;

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                HeaderBand(snapshot: data, loading: loading, error: error),
                const SizedBox(height: 12),
                MetricsGrid(snapshot: data),
                const SizedBox(height: 12),
                ResponsiveTwoColumn(
                  left: PositionsPanel(positions: data.positions),
                  right: OrdersPanel(orders: data.orders),
                ),
                const SizedBox(height: 12),
                ResponsiveTwoColumn(
                  left: RiskPanel(snapshot: data),
                  right: EventPanel(events: data.events),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class HeaderBand extends StatelessWidget {
  const HeaderBand({
    super.key,
    required this.snapshot,
    required this.loading,
    required this.error,
  });

  final EngineSnapshot snapshot;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(
                  label: snapshot.regime,
                  icon: Icons.insights,
                  color: regimeColor(snapshot.regime),
                ),
                StatusChip(
                  label: snapshot.marketBias,
                  icon: Icons.account_tree_outlined,
                  color: colors.tertiary,
                ),
                StatusChip(
                  label: snapshot.mode,
                  icon: Icons.swap_calls,
                  color: modeColor(snapshot.mode),
                ),
                StatusChip(
                  label: snapshot.riskState,
                  icon: Icons.shield_outlined,
                  color: riskColor(snapshot.riskState),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Score ${snapshot.regimeScore.toStringAsFixed(1)}',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF17202A),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              '${snapshot.source} · ${snapshot.lastUpdated}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF627182),
                  ),
            ),
            if (loading || error != null) ...[
              const SizedBox(height: 10),
              Text(
                loading ? 'Updating...' : 'API fallback active',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error == null ? colors.primary : colors.error,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class MetricsGrid extends StatelessWidget {
  const MetricsGrid({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      MetricItem('Equity', usdt(snapshot.equity), Icons.account_balance_wallet),
      MetricItem('Current', usdt(snapshot.currentExposure), Icons.timeline),
      MetricItem('Target', usdt(snapshot.targetExposure), Icons.flag_outlined),
      MetricItem(
          'Leverage', '${snapshot.leverage.toStringAsFixed(2)}x', Icons.speed),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 88,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) => MetricTile(item: metrics[index]),
        );
      },
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.item});

  final MetricItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(item.icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF627182),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
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

class ResponsiveTwoColumn extends StatelessWidget {
  const ResponsiveTwoColumn({
    super.key,
    required this.left,
    required this.right,
  });

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            children: [
              left,
              const SizedBox(height: 12),
              right,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class PositionsPanel extends StatelessWidget {
  const PositionsPanel({super.key, required this.positions});

  final List<PositionView> positions;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Positions',
      icon: Icons.donut_large,
      child: Column(
        children: positions
            .map(
              (position) => DenseRow(
                leading: position.symbol,
                middle: position.side,
                trailing: usdt(position.notional),
                color: position.side == 'LONG'
                    ? const Color(0xFF138A5E)
                    : const Color(0xFFB84A3D),
              ),
            )
            .toList(),
      ),
    );
  }
}

class OrdersPanel extends StatelessWidget {
  const OrdersPanel({super.key, required this.orders});

  final List<OrderView> orders;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Orders',
      icon: Icons.receipt_long,
      child: Column(
        children: orders
            .map(
              (order) => DenseRow(
                leading: order.symbol,
                middle: order.action,
                trailing: usdt(order.notional),
                color: order.reduceOnly
                    ? const Color(0xFF8A6D1E)
                    : Theme.of(context).colorScheme.primary,
              ),
            )
            .toList(),
      ),
    );
  }
}

class RiskPanel extends StatelessWidget {
  const RiskPanel({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Risk',
      icon: Icons.health_and_safety_outlined,
      child: Column(
        children: [
          DenseRow(
            leading: 'Daily',
            middle: pct(snapshot.dailyPnlPct),
            trailing: 'Limit -2.0%',
            color: snapshot.dailyPnlPct < -2
                ? Colors.red
                : const Color(0xFF138A5E),
          ),
          DenseRow(
            leading: 'Weekly',
            middle: pct(snapshot.weeklyPnlPct),
            trailing: 'Limit -5.0%',
            color: snapshot.weeklyPnlPct < -5
                ? Colors.red
                : const Color(0xFF138A5E),
          ),
          DenseRow(
            leading: 'Monthly',
            middle: pct(snapshot.monthlyPnlPct),
            trailing: 'Limit -10.0%',
            color: snapshot.monthlyPnlPct < -10
                ? Colors.red
                : const Color(0xFF138A5E),
          ),
          DenseRow(
            leading: 'Cooldown',
            middle: snapshot.cooldownUntil ?? 'None',
            trailing: snapshot.riskState,
            color: riskColor(snapshot.riskState),
          ),
        ],
      ),
    );
  }
}

class EventPanel extends StatelessWidget {
  const EventPanel({super.key, required this.events});

  final List<EventView> events;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Events',
      icon: Icons.event_note,
      child: Column(
        children: events
            .map(
              (event) => DenseRow(
                leading: event.time,
                middle: event.kind,
                trailing: event.message,
                color: event.kind == 'ERROR'
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
            )
            .toList(),
      ),
    );
  }
}

class DataPanel extends StatelessWidget {
  const DataPanel({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon,
                    size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class DenseRow extends StatelessWidget {
  const DenseRow({
    super.key,
    required this.leading,
    required this.middle,
    required this.trailing,
    required this.color,
  });

  final String leading;
  final String middle;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 42),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE9EDF1)),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              leading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              middle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              trailing,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(color: Color(0xFF3B4652)),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
        ],
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
          .timeout(const Duration(seconds: 5));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('status ${response.statusCode}');
      }

      return EngineSnapshot.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } catch (_) {
      return EngineSnapshot.sample(source: 'Sample fallback');
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

  factory EngineSnapshot.fromJson(Map<String, dynamic> json) {
    return EngineSnapshot(
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
      positions: listOf(json['positions'], PositionView.fromJson),
      orders: listOf(json['orders'], OrderView.fromJson),
      events: listOf(json['events'], EventView.fromJson),
    );
  }

  static EngineSnapshot sample({String source = 'Sample'}) {
    return EngineSnapshot(
      source: source,
      lastUpdated: '2026-05-19 23:30 KST',
      regime: 'RANGE',
      marketBias: 'RANGE',
      mode: 'NEUTRAL',
      riskState: 'OK',
      regimeScore: 12.5,
      equity: 1500,
      currentExposure: 0,
      targetExposure: 0,
      leverage: 0,
      dailyPnlPct: 0.1,
      weeklyPnlPct: -0.6,
      monthlyPnlPct: 1.8,
      cooldownUntil: null,
      positions: const [
        PositionView(symbol: 'BTCUSDT', side: 'FLAT', notional: 0),
        PositionView(symbol: 'ETHUSDT', side: 'FLAT', notional: 0),
      ],
      orders: const [
        OrderView(
            symbol: 'NONE',
            action: 'NO_ACTION',
            notional: 0,
            reduceOnly: false),
      ],
      events: const [
        EventView(
            time: '23:28',
            kind: 'ALERT',
            message: 'tf=1 receive test accepted'),
        EventView(
            time: '23:24',
            kind: 'TUNNEL',
            message: 'engine.medicalnewshub.info online'),
      ],
    );
  }
}

class PositionView {
  const PositionView({
    required this.symbol,
    required this.side,
    required this.notional,
  });

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
  const EventView({
    required this.time,
    required this.kind,
    required this.message,
  });

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

class MetricItem {
  const MetricItem(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
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

String usdt(double value) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  return '$sign${absolute.toStringAsFixed(absolute >= 100 ? 0 : 2)} USDT';
}

String pct(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';

Color regimeColor(String regime) {
  return switch (regime) {
    'BULL' || 'TOP10_LONG' => const Color(0xFF138A5E),
    'BEAR' || 'SHORT_MODE' || 'ALT_WEAK_SHORT' => const Color(0xFFB84A3D),
    'CHAOTIC' => const Color(0xFF8F3FA8),
    _ => const Color(0xFF627182),
  };
}

Color modeColor(String mode) {
  return switch (mode) {
    'LONG' => const Color(0xFF138A5E),
    'SHORT' => const Color(0xFFB84A3D),
    'PAUSED' => const Color(0xFF8F3FA8),
    _ => const Color(0xFF627182),
  };
}

Color riskColor(String risk) {
  return switch (risk) {
    'OK' || 'NONE' => const Color(0xFF138A5E),
    'BLOCK_NEW_ENTRIES' => const Color(0xFF8A6D1E),
    'REDUCE_HALF' => const Color(0xFFB56B00),
    'CLOSE_ALL_AND_PAUSE' => const Color(0xFFB84A3D),
    _ => const Color(0xFF627182),
  };
}
