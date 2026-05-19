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
              fontSize: 13,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w800
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF111827)
                  : const Color(0xFF8A8D94),
              letterSpacing: 0,
              height: 1.2,
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
                WatchGroupTabs(
                  selectedIndex: _selectedTab,
                  onSelected: (index) => setState(() => _selectedTab = index),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      SummaryView(snapshot: data),
                      PositionsView(snapshot: data),
                      OrdersView(snapshot: data),
                      MarketView(snapshot: data),
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
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: '요약',
              ),
              NavigationDestination(
                icon: Icon(Icons.account_tree_outlined),
                selectedIcon: Icon(Icons.account_tree),
                label: '포지션',
              ),
              NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: '주문',
              ),
              NavigationDestination(
                icon: Icon(Icons.timeline),
                selectedIcon: Icon(Icons.timeline),
                label: '시장',
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
                            fontSize: 17,
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
                  label: regimeLabel(snapshot.regime),
                  color: regimeColor(snapshot.regime)),
              const SizedBox(width: 8),
              StatusPill(
                  label: modeLabel(snapshot.mode),
                  color: modeColor(snapshot.mode)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sourceLabel(snapshot.source)} · ${snapshot.lastUpdated}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Color(0xFF7A7F89),
                    fontSize: 14,
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
  const WatchGroupTabs({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const tabs = ['요약', '포지션', '주문', '시장', '로그'];
    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: EdgeInsets.symmetric(
                  horizontal: selected ? 22 : 4,
                  vertical: selected ? 12 : 0,
                ),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFFEDEEF1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tabs[index],
                  style: TextStyle(
                    color: selected ? Colors.black : const Color(0xFF8A8D94),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.1,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class SummaryView extends StatelessWidget {
  const SummaryView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {},
      child: WatchListScaffold(
        title: '운영 요약',
        subtitle: '${sourceLabel(snapshot.source)} · ${snapshot.lastUpdated}',
        metric: compactUsdt(snapshot.equity),
        accent: regimeColor(snapshot.regime),
        items: summaryItems(snapshot),
      ),
    );
  }
}

class PositionsView extends StatelessWidget {
  const PositionsView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(
      title: '현 포지션',
      subtitle: '현재 노출 ${compactUsdt(snapshot.currentExposure)}',
      metric: '${snapshot.positions.length}개',
      accent: snapshot.positions.isEmpty
          ? const Color(0xFF787B86)
          : const Color(0xFF2563EB),
      items: positionItems(snapshot),
    );
  }
}

class OrdersView extends StatelessWidget {
  const OrdersView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(
      title: '주문 대기열',
      subtitle: '목표 노출 ${compactUsdt(snapshot.targetExposure)}',
      metric: '${snapshot.orders.length}개',
      accent: snapshot.orders.isEmpty
          ? const Color(0xFF787B86)
          : const Color(0xFFC08A17),
      items: orderItems(snapshot),
    );
  }
}

class MarketView extends StatelessWidget {
  const MarketView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(
      title: '시장 콘솔',
      subtitle: 'Stable.D · Top10.D · Breadth',
      metric: snapshot.marketBias,
      accent: regimeColor(snapshot.regime),
      items: marketItems(snapshot),
    );
  }
}

class LogView extends StatelessWidget {
  const LogView({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return WatchListScaffold(
      title: '이벤트 로그',
      subtitle: snapshot.lastUpdated,
      metric: '${snapshot.events.length}개',
      accent: const Color(0xFF2563EB),
      items: consoleItems(snapshot),
      onItemTap: (item) {
        if (item.symbol == eventKindLabel('ALERT')) {
          showEngineResultSheet(context, snapshot);
        }
      },
    );
  }
}

class WatchListScaffold extends StatelessWidget {
  const WatchListScaffold({
    super.key,
    required this.items,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.accent,
    this.onItemTap,
  });

  final List<WatchItem> items;
  final String title;
  final String subtitle;
  final String metric;
  final Color accent;
  final ValueChanged<WatchItem>? onItemTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: items.length + 1,
      separatorBuilder: (context, index) {
        if (index == 0) {
          return const SizedBox(height: 6);
        }
        return const Divider(
          height: 1,
          indent: 68,
          endIndent: 18,
          color: Color(0xFFEDEEF1),
        );
      },
      itemBuilder: (context, index) {
        if (index == 0) {
          return ConsoleHeader(
            title: title,
            subtitle: subtitle,
            metric: metric,
            accent: accent,
          );
        }
        final item = items[index - 1];
        return WatchRow(
          item: item,
          onTap: onItemTap == null ? null : () => onItemTap!(item),
        );
      },
    );
  }
}

class ConsoleHeader extends StatelessWidget {
  const ConsoleHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.metric,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String metric;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 78),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F7F9),
          border: Border.all(color: const Color(0xFFE8EAEE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 44,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF15171E),
                      letterSpacing: 0,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7A7F89),
                      letterSpacing: 0,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              metric,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 0,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WatchRow extends StatelessWidget {
  const WatchRow({super.key, required this.item, this.onTap});

  final WatchItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final negative = item.change.trimLeft().startsWith('-');
    final changeColor = negative ? const Color(0xFFC8404A) : item.accent;
    final rightColumnWidth =
        (MediaQuery.sizeOf(context).width * 0.30).clamp(132.0, 260.0);
    final changeText = item.changePct.isEmpty
        ? item.change
        : '${item.change} · ${item.changePct}';

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 88,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 23,
                backgroundColor: item.accent.withValues(alpha: 0.14),
                child: Text(
                  item.marker.toUpperCase(),
                  style: TextStyle(
                    color: item.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 14),
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
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF80848C),
                        letterSpacing: 0,
                        height: 1.25,
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
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      changeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: changeColor,
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                    ),
                    if (item.meta.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        item.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF8A8D94),
                          letterSpacing: 0,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void showEngineResultSheet(BuildContext context, EngineSnapshot snapshot) {
  final signal = snapshot.tradingViewSignal;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      return SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.42,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4D7DD),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 23,
                      backgroundColor:
                          regimeColor(snapshot.regime).withValues(alpha: 0.12),
                      child: Icon(Icons.analytics_outlined,
                          color: regimeColor(snapshot.regime)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '엔진 결과',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF15171E),
                              letterSpacing: 0,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            signal?.signalId ?? snapshot.lastUpdated,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7A7F89),
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                DetailSection(
                  title: 'TradingView',
                  rows: [
                    DetailRowData('레짐', signal?.regime ?? '-',
                        regimeLabel(signal?.regime ?? '-')),
                    DetailRowData(
                        '타임프레임', signal?.timeframe ?? '-', 'confirmed'),
                    DetailRowData(
                        '목표 레버리지',
                        '${(signal?.targetLeverage ?? 0).toStringAsFixed(2)}x',
                        'TV'),
                    DetailRowData(
                        '신호 시간',
                        signal?.barTimeMs?.toString() ??
                            signal?.timeMs.toString() ??
                            '-',
                        'ms'),
                  ],
                ),
                DetailSection(
                  title: 'Engine',
                  rows: [
                    DetailRowData(
                        '판정',
                        '${regimeLabel(snapshot.regime)} / ${modeLabel(snapshot.mode)}',
                        snapshot.marketBias),
                    DetailRowData('점수', snapshot.regimeScore.toStringAsFixed(1),
                        sourceLabel(snapshot.source)),
                    DetailRowData(
                        '노출',
                        '${compactUsdt(snapshot.currentExposure)} → ${compactUsdt(snapshot.targetExposure)}',
                        '${snapshot.leverage.toStringAsFixed(2)}x'),
                    DetailRowData('주문', '${snapshot.orders.length}개',
                        riskLabel(snapshot.riskState)),
                  ],
                ),
                DetailSection(
                  title: 'Market',
                  rows: [
                    DetailRowData(
                        'Internals',
                        snapshot.marketInternals.riskLabel,
                        snapshot.marketInternals.source),
                    DetailRowData(
                        'Stable.D',
                        fmtNullablePct(
                            snapshot.marketInternals.stableDominancePct),
                        'defensive'),
                    DetailRowData(
                        'Top10.D',
                        fmtNullablePct(
                            snapshot.marketInternals.top10DominanceTotalPct),
                        'cap'),
                    DetailRowData(
                        'Breadth',
                        fmtNullablePct(
                            snapshot.marketInternals.volumeBreadthPct),
                        snapshot.marketInternals.advanceDeclineLabel),
                  ],
                ),
                DetailSection(
                  title: 'Signal Flags',
                  rows: [
                    DetailRowData(
                        'BTC',
                        boolDirection(signal?.btcUp, signal?.btcDown),
                        'direction'),
                    DetailRowData(
                        'TOTAL',
                        boolDirection(signal?.totalUp, signal?.totalDown),
                        'market'),
                    DetailRowData(
                        'TOTAL2',
                        boolDirection(signal?.total2Up, signal?.total2Down),
                        'alts'),
                    DetailRowData(
                        'TOTAL3',
                        signal?.total3Weak == true ? 'WEAK' : 'OK',
                        'pure alts'),
                    DetailRowData(
                        'BTC.D',
                        boolDirection(signal?.btcdUp, signal?.btcdDown),
                        'flow'),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}

class DetailSection extends StatelessWidget {
  const DetailSection({super.key, required this.title, required this.rows});

  final String title;
  final List<DetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F7F9),
        border: Border.all(color: const Color(0xFFE8EAEE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF15171E),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          ...rows.map((row) => DetailLine(row: row)),
        ],
      ),
    );
  }
}

class DetailLine extends StatelessWidget {
  const DetailLine({super.key, required this.row});

  final DetailRowData row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 94,
            child: Text(
              row.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7A7F89),
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: Color(0xFF15171E),
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              row.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF8A8D94),
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DetailRowData {
  const DetailRowData(this.label, this.value, this.meta);

  final String label;
  final String value;
  final String meta;
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          height: 1.1,
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
    required this.tradingViewSignal,
    required this.marketInternals,
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
  final TradingViewSignal? tradingViewSignal;
  final MarketInternalsView marketInternals;
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
      tradingViewSignal: TradingViewSignal.tryParse(json['tradingview_signal']),
      marketInternals: MarketInternalsView.fromJson(
          json['market_internals'] ?? json['marketInternals']),
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
      tradingViewSignal: const TradingViewSignal(
        regime: 'RANGE',
        targetLeverage: 0,
        btcUp: true,
        btcDown: false,
        totalUp: true,
        totalDown: false,
        total2Up: true,
        total2Down: false,
        total3Weak: false,
        btcdUp: true,
        btcdDown: false,
        timeframe: '5',
        confirmed: true,
        timeMs: 1779215702553,
        barTimeMs: 1779215700000,
        signalId: 'RANGE_5_1779215700000',
      ),
      marketInternals: const MarketInternalsView(
        source: 'coingecko+binance',
        riskLabel: 'BROAD_RISK_OFF',
        stableDominancePct: 11.0,
        top10DominanceTotalPct: 79.7,
        volumeBreadthPct: 34.6,
        advanceCount: 128,
        declineCount: 72,
      ),
      positions: const [],
      orders: const [],
      events: const [
        EventView(
            time: '23:43',
            kind: 'ALERT',
            message: '트레이딩뷰 웹훅이 Cloudflare Worker에 수신됨'),
        EventView(
            time: '23:43', kind: 'DECISION', message: 'RANGE 신호로 엔진이 관망 모드 유지'),
        EventView(
            time: '23:42',
            kind: 'SECRET',
            message: 'TV_WEBHOOK_PASSPHRASE 동기화 완료'),
        EventView(
            time: '23:35',
            kind: 'WORKER',
            message: 'tradingview-webhook이 workers.dev에 배포됨'),
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
      tradingViewSignal: tradingViewSignal,
      marketInternals: marketInternals,
      positions: positions,
      orders: orders,
      events: events,
      watchItems: watchItems ?? this.watchItems,
    );
  }
}

class TradingViewSignal {
  const TradingViewSignal({
    required this.regime,
    required this.targetLeverage,
    required this.btcUp,
    required this.btcDown,
    required this.totalUp,
    required this.totalDown,
    required this.total2Up,
    required this.total2Down,
    required this.total3Weak,
    required this.btcdUp,
    required this.btcdDown,
    required this.timeframe,
    required this.confirmed,
    required this.timeMs,
    required this.barTimeMs,
    required this.signalId,
  });

  final String regime;
  final double targetLeverage;
  final bool btcUp;
  final bool btcDown;
  final bool totalUp;
  final bool totalDown;
  final bool total2Up;
  final bool total2Down;
  final bool total3Weak;
  final bool btcdUp;
  final bool btcdDown;
  final String timeframe;
  final bool confirmed;
  final int? timeMs;
  final int? barTimeMs;
  final String signalId;

  static TradingViewSignal? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return TradingViewSignal.fromJson(Map<String, dynamic>.from(raw));
  }

  factory TradingViewSignal.fromJson(Map<String, dynamic> json) {
    return TradingViewSignal(
      regime: (json['regime'] ?? '-').toString(),
      targetLeverage:
          toDouble(json['target_leverage'] ?? json['targetLeverage']),
      btcUp: json['btc_up'] == true || json['btcUp'] == true,
      btcDown: json['btc_down'] == true || json['btcDown'] == true,
      totalUp: json['total_up'] == true || json['totalUp'] == true,
      totalDown: json['total_down'] == true || json['totalDown'] == true,
      total2Up: json['total2_up'] == true || json['total2Up'] == true,
      total2Down: json['total2_down'] == true || json['total2Down'] == true,
      total3Weak: json['total3_weak'] == true || json['total3Weak'] == true,
      btcdUp: json['btcd_up'] == true || json['btcdUp'] == true,
      btcdDown: json['btcd_down'] == true || json['btcdDown'] == true,
      timeframe: (json['tf'] ?? json['timeframe'] ?? '-').toString(),
      confirmed: json['confirmed'] != false,
      timeMs: toNullableInt(json['time_ms'] ?? json['timeMs']),
      barTimeMs: toNullableInt(json['bar_time_ms'] ?? json['barTimeMs']),
      signalId: (json['signal_id'] ?? json['signalId'] ?? '-').toString(),
    );
  }
}

class MarketInternalsView {
  const MarketInternalsView({
    required this.source,
    required this.riskLabel,
    required this.stableDominancePct,
    required this.top10DominanceTotalPct,
    required this.volumeBreadthPct,
    required this.advanceCount,
    required this.declineCount,
  });

  final String source;
  final String riskLabel;
  final double? stableDominancePct;
  final double? top10DominanceTotalPct;
  final double? volumeBreadthPct;
  final int advanceCount;
  final int declineCount;

  String get advanceDeclineLabel {
    if (advanceCount == 0 && declineCount == 0) return '-';
    return '$advanceCount/$declineCount';
  }

  factory MarketInternalsView.fromJson(Object? raw) {
    final json =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    return MarketInternalsView(
      source: (json['source'] ?? '-').toString(),
      riskLabel: (json['risk_label'] ?? json['riskLabel'] ?? '-').toString(),
      stableDominancePct: toNullableDouble(
          json['stable_dominance_pct'] ?? json['stableDominancePct']),
      top10DominanceTotalPct: toNullableDouble(
          json['top10_dominance_total_pct'] ?? json['top10DominanceTotalPct']),
      volumeBreadthPct: toNullableDouble(
          json['volume_breadth_pct'] ?? json['volumeBreadthPct']),
      advanceCount: toInt(json['advance_count'] ?? json['advanceCount']),
      declineCount: toInt(json['decline_count'] ?? json['declineCount']),
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
    this.positionSide = '',
    this.orderType = '',
    this.reason = '',
  });

  final String symbol;
  final String action;
  final double notional;
  final bool reduceOnly;
  final String positionSide;
  final String orderType;
  final String reason;

  factory OrderView.fromJson(Map<String, dynamic> json) {
    return OrderView(
      symbol: (json['symbol'] ?? '-').toString(),
      action: (json['action'] ?? json['side'] ?? '-').toString(),
      notional: toDouble(json['notional']),
      reduceOnly: json['reduce_only'] == true || json['reduceOnly'] == true,
      positionSide:
          (json['position_side'] ?? json['positionSide'] ?? json['side'] ?? '')
              .toString(),
      orderType: (json['order_type'] ?? json['orderType'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
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

List<WatchItem> summaryItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: '레짐',
      title: snapshot.marketBias,
      value: regimeLabel(snapshot.regime),
      change: '점수 ${snapshot.regimeScore.toStringAsFixed(1)}',
      changePct: modeLabel(snapshot.mode),
      accent: regimeColor(snapshot.regime),
      marker: 'R',
      meta: '현재 판단',
    ),
    WatchItem(
      symbol: '자산',
      title: '가상 / 바이낸스 계좌 자산',
      value: compactUsdt(snapshot.equity),
      change: '현재 ${compactUsdt(snapshot.currentExposure)}',
      changePct: '목표 ${compactUsdt(snapshot.targetExposure)}',
      accent: const Color(0xFF2563EB),
      marker: 'E',
      meta: sourceLabel(snapshot.source),
    ),
    WatchItem(
      symbol: '레버리지',
      title: '총 익스포저 사용량',
      value: '${snapshot.leverage.toStringAsFixed(2)}x',
      change: snapshot.leverage <= 2 ? '범위 내' : '초과',
      changePct: '최대 2.00x',
      accent: snapshot.leverage <= 2
          ? const Color(0xFF2F8F75)
          : const Color(0xFFC8404A),
      marker: 'L',
      meta: '크로스 2x 한도',
    ),
    WatchItem(
      symbol: '리스크',
      title: riskLabel(snapshot.riskState),
      value: pct(snapshot.dailyPnlPct),
      change: '주 ${pct(snapshot.weeklyPnlPct)}',
      changePct: '월 ${pct(snapshot.monthlyPnlPct)}',
      accent: riskColor(snapshot.riskState),
      marker: '!',
      meta: snapshot.cooldownUntil ?? '쿨다운 없음',
    ),
  ];
}

List<WatchItem> positionItems(EngineSnapshot snapshot) {
  if (snapshot.positions.isEmpty) {
    return [
      WatchItem(
        symbol: '플랫',
        title: '오픈된 선물 포지션 없음',
        value: compactUsdt(snapshot.currentExposure),
        change: '중립',
        changePct: '0.00%',
        accent: const Color(0xFF787B86),
        marker: 'F',
        meta: '현재 포지션만 표시',
      ),
    ];
  }

  return snapshot.positions
      .map(
        (position) => WatchItem(
          symbol: position.symbol,
          title: sideLabel(position.side),
          value: compactUsdt(position.notional),
          change: sideLabel(position.side),
          changePct: snapshot.equity <= 0 || position.notional == 0
              ? '0.00%'
              : '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%',
          accent: sideColor(position.side),
          marker: firstMarker(position.symbol),
          meta: '바이낸스 현재 포지션',
        ),
      )
      .toList(growable: false);
}

List<WatchItem> orderItems(EngineSnapshot snapshot) {
  if (snapshot.orders.isEmpty) {
    return [
      WatchItem(
        symbol: '주문 없음',
        title: '예정된 리밸런싱 주문 없음',
        value: compactUsdt(snapshot.targetExposure),
        change: '대기',
        changePct: modeLabel(snapshot.mode),
        accent: const Color(0xFF787B86),
        marker: 'O',
        meta: '주문 목록',
      ),
    ];
  }

  return snapshot.orders
      .map(
        (order) => WatchItem(
          symbol: order.symbol,
          title: [
            order.action,
            if (order.positionSide.isNotEmpty) sideLabel(order.positionSide),
            if (order.reduceOnly) '청산 전용',
          ].join(' · '),
          value: compactUsdt(order.notional),
          change: order.orderType.isEmpty ? '예정' : order.orderType,
          changePct: order.reduceOnly ? '청산' : '진입',
          accent: order.reduceOnly
              ? const Color(0xFFC08A17)
              : const Color(0xFF2563EB),
          marker: firstMarker(order.symbol),
          meta: order.reason.isEmpty ? '예정된 주문' : order.reason,
        ),
      )
      .toList(growable: false);
}

List<WatchItem> marketItems(EngineSnapshot snapshot) {
  final pinnedSymbols = {'INTERNALS', 'STABLE.D', 'TOP10.D'};
  final hiddenSymbols = {'REGIME', 'EQUITY', 'RISK', 'LEVERAGE'};
  final pinned = snapshot.watchItems
      .where((item) => pinnedSymbols.contains(item.symbol))
      .toList(growable: false);
  final topCoins = snapshot.watchItems
      .where((item) =>
          !pinnedSymbols.contains(item.symbol) &&
          !hiddenSymbols.contains(item.symbol))
      .toList(growable: false);

  if (pinned.isEmpty && topCoins.isEmpty) {
    return [
      WatchItem(
        symbol: '시장',
        title: '시장 내부 데이터 대기 중',
        value: snapshot.marketBias,
        change: regimeLabel(snapshot.regime),
        changePct: modeLabel(snapshot.mode),
        accent: regimeColor(snapshot.regime),
        marker: 'M',
        meta: snapshot.lastUpdated,
      ),
    ];
  }

  return [...pinned, ...topCoins];
}

List<WatchItem> projectProgressItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: '웹훅',
      title: 'TradingView → Cloudflare Worker',
      value: '수신됨',
      change: '202 수락',
      changePct: '운영중',
      accent: const Color(0xFF2F8F75),
      marker: 'W',
      meta: 'URL 활성',
    ),
    WatchItem(
      symbol: '신호',
      title: '최근 알림 기준 판단',
      value: decisionLabel(snapshot),
      change: regimeLabel(snapshot.regime),
      changePct: modeLabel(snapshot.mode),
      accent: regimeColor(snapshot.regime),
      marker: 'S',
      meta: snapshot.marketBias,
    ),
    WatchItem(
      symbol: '앱',
      title: 'Flutter 관전 앱 정리',
      value: '진행중',
      change: '읽기 전용',
      changePct: '콘솔',
      accent: const Color(0xFF2563EB),
      marker: 'A',
      meta: '거래 컨트롤 없음',
    ),
    WatchItem(
      symbol: '엔진',
      title: '비공개 실행 엔진 연결',
      value: '대기',
      change: '큐/터널',
      changePct: '다음 단계',
      accent: const Color(0xFFC08A17),
      marker: 'E',
      meta: '바이낸스 키는 서버에만 보관',
    ),
    WatchItem(
      symbol: '실거래',
      title: '자동 실거래 전 단계',
      value: '미시작',
      change: '페이퍼 우선',
      changePct: '안전',
      accent: const Color(0xFF787B86),
      marker: 'L',
      meta: '30일 목표',
    ),
  ];
}

List<WatchItem> decisionConsoleItems(EngineSnapshot snapshot) {
  final alert = latestEvent(snapshot, 'ALERT');
  return [
    WatchItem(
      symbol: '콘솔',
      title: alert?.message ?? '트레이딩뷰 알림 대기 중',
      value: decisionLabel(snapshot),
      change: regimeLabel(snapshot.regime),
      changePct: snapshot.marketBias,
      accent: regimeColor(snapshot.regime),
      marker: '>',
      meta: alert?.time ?? snapshot.lastUpdated,
    ),
    WatchItem(
      symbol: '레짐',
      title: '웹훅 페이로드 판단 필드',
      value: regimeLabel(snapshot.regime),
      change: decisionDetail(snapshot),
      changePct: modeLabel(snapshot.mode),
      accent: regimeColor(snapshot.regime),
      marker: 'R',
      meta: '수동 오버라이드 없음',
    ),
    WatchItem(
      symbol: '목표',
      title: '엔진 스냅샷 기준 목표 익스포저',
      value: compactUsdt(snapshot.targetExposure),
      change: '레버 ${snapshot.leverage.toStringAsFixed(2)}x',
      changePct: '최대 2x',
      accent: snapshot.leverage <= 2
          ? const Color(0xFF2F8F75)
          : const Color(0xFFC8404A),
      marker: 'T',
      meta: '현재 ${compactUsdt(snapshot.currentExposure)}',
    ),
    WatchItem(
      symbol: '동작',
      title: '앱은 판단 표시만 수행',
      value: '관전',
      change: '버튼 없음',
      changePct: '읽기 전용',
      accent: const Color(0xFF2563EB),
      marker: 'A',
      meta: sourceLabel(snapshot.source),
    ),
  ];
}

List<WatchItem> portfolioItems(EngineSnapshot snapshot) {
  final items = snapshot.positions
      .map(
        (position) => WatchItem(
          symbol: position.symbol,
          title: sideLabel(position.side),
          value: compactUsdt(position.notional),
          change: sideLabel(position.side),
          changePct: snapshot.equity <= 0 || position.notional == 0
              ? '0.00%'
              : '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%',
          accent: sideColor(position.side),
          marker: firstMarker(position.symbol),
          meta: '바이낸스 현재 포지션',
        ),
      )
      .toList(growable: true);

  if (items.isEmpty) {
    items.add(
      WatchItem(
        symbol: '플랫',
        title: '오픈된 바이낸스 선물 포지션 없음',
        value: compactUsdt(snapshot.currentExposure),
        change: '중립',
        changePct: '0.00%',
        accent: const Color(0xFF787B86),
        marker: 'F',
        meta: '읽기 전용 관전',
      ),
    );
  }

  for (final order in snapshot.orders.take(6)) {
    items.add(
      WatchItem(
        symbol: order.symbol,
        title: '${order.action}${order.reduceOnly ? ' · 청산 전용' : ''}',
        value: compactUsdt(order.notional),
        change: order.action,
        changePct: order.reduceOnly ? '청산' : '진입',
        accent: order.reduceOnly
            ? const Color(0xFFC08A17)
            : const Color(0xFF2563EB),
        marker: firstMarker(order.symbol),
        meta: '예정된 주문',
      ),
    );
  }

  return items;
}

List<WatchItem> pipelineItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: '1 TV',
      title: '알림 JSON에 schema/passphrase/time_ms 포함',
      value: '완료',
      change: '수락됨',
      changePct: '400 수정',
      accent: const Color(0xFF2F8F75),
      marker: '1',
      meta: latestEvent(snapshot, 'ALERT')?.time ?? snapshot.lastUpdated,
    ),
    WatchItem(
      symbol: '2 워커',
      title: '검증·지연 확인·중복 제거',
      value: '운영중',
      change: 'workers.dev',
      changePct: 'KV 사용',
      accent: const Color(0xFF2F8F75),
      marker: '2',
      meta: 'tradingview-webhook',
    ),
    WatchItem(
      symbol: '3 엔진',
      title: '큐/터널 컨슈머와 상태 저장소',
      value: '남음',
      change: '연결 필요',
      changePct: '다음 단계',
      accent: const Color(0xFFC08A17),
      marker: '3',
      meta: '비공개 API /status',
    ),
    WatchItem(
      symbol: '4 앱',
      title: '읽기 전용 상태 폴링',
      value: '정리중',
      change: '탭 유지',
      changePct: '콘솔 전용',
      accent: const Color(0xFF2563EB),
      marker: '4',
      meta: sourceLabel(snapshot.source),
    ),
    WatchItem(
      symbol: '5 바이낸스',
      title: '실거래 전 페이퍼 모드',
      value: '잠금',
      change: '실거래 없음',
      changePct: '대기',
      accent: const Color(0xFF787B86),
      marker: '5',
      meta: '앱에 키 없음',
    ),
  ];
}

List<WatchItem> guardItems(EngineSnapshot snapshot) {
  return [
    WatchItem(
      symbol: '일간',
      title: '일간 손실 가드',
      value: pct(snapshot.dailyPnlPct),
      change: snapshot.dailyPnlPct <= -2 ? '차단' : '정상',
      changePct: '한도 -2.00%',
      accent: snapshot.dailyPnlPct <= -2
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'D',
      meta: '신규 진입 차단',
    ),
    WatchItem(
      symbol: '주간',
      title: '주간 축소 가드',
      value: pct(snapshot.weeklyPnlPct),
      change: snapshot.weeklyPnlPct <= -5 ? '축소' : '정상',
      changePct: '한도 -5.00%',
      accent: snapshot.weeklyPnlPct <= -5
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'W',
      meta: '50% 축소',
    ),
    WatchItem(
      symbol: '월간',
      title: '월간 정지 가드',
      value: pct(snapshot.monthlyPnlPct),
      change: snapshot.monthlyPnlPct <= -10 ? '정지' : '정상',
      changePct: '한도 -10.00%',
      accent: snapshot.monthlyPnlPct <= -10
          ? const Color(0xFFC8404A)
          : const Color(0xFF2F8F75),
      marker: 'M',
      meta: '전량 청산 후 정지',
    ),
    WatchItem(
      symbol: '레버리지',
      title: '총 익스포저 한도',
      value: '${snapshot.leverage.toStringAsFixed(2)}x',
      change: snapshot.leverage <= 2 ? '범위 내' : '초과',
      changePct: '최대 2.00x',
      accent: snapshot.leverage <= 2
          ? const Color(0xFF2F8F75)
          : const Color(0xFFC8404A),
      marker: 'L',
      meta: '자산 기준',
    ),
    WatchItem(
      symbol: '쿨다운',
      title: snapshot.cooldownUntil ?? '활성 쿨다운 없음',
      value: riskLabel(snapshot.riskState),
      change: '자동',
      changePct: '읽기 전용',
      accent: riskColor(snapshot.riskState),
      marker: 'C',
      meta: '앱 측 주문 제어 없음',
    ),
  ];
}

List<WatchItem> consoleItems(EngineSnapshot snapshot) {
  final items = snapshot.events
      .map(
        (event) => WatchItem(
          symbol: eventKindLabel(event.kind),
          title: event.message,
          value: event.time,
          change: eventKindLabel(event.kind),
          changePct: sourceLabel(snapshot.source),
          accent: eventColor(event.kind),
          marker: eventMarker(event.kind),
          meta: '프로젝트 로그',
        ),
      )
      .toList(growable: true);

  if (items.isEmpty) {
    items.add(
      WatchItem(
        symbol: '대기',
        title: '엔진 로그 수신 대기 중',
        value: '-',
        change: '폴링',
        changePct: sourceLabel(snapshot.source),
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
      title: '비트코인 무기한',
      value: modeLabel(snapshot.mode),
      change: regimeLabel(snapshot.regime),
      changePct: snapshot.marketBias,
      accent: const Color(0xFFF7931A),
      marker: 'B',
      meta: '신호 소스',
    ),
    WatchItem(
      symbol: '자산',
      title: 'USDT-M 계좌 자산',
      value: compactUsdt(snapshot.equity),
      change: '레버리지 ${snapshot.leverage.toStringAsFixed(2)}x',
      changePct: '목표 ${compactUsdt(snapshot.targetExposure)}',
      accent: const Color(0xFF2563EB),
      marker: 'E',
      meta: sourceLabel(snapshot.source),
    ),
    WatchItem(
      symbol: '리스크',
      title: riskLabel(snapshot.riskState),
      value: pct(snapshot.dailyPnlPct),
      change: '주 ${pct(snapshot.weeklyPnlPct)}',
      changePct: '월 ${pct(snapshot.monthlyPnlPct)}',
      accent: riskColor(snapshot.riskState),
      marker: 'R',
      meta: snapshot.cooldownUntil ?? '쿨다운 없음',
    ),
    ...snapshot.positions.map(
      (position) => WatchItem(
        symbol: position.symbol,
        title: sideLabel(position.side),
        value: compactUsdt(position.notional),
        change: sideLabel(position.side),
        changePct: snapshot.equity <= 0 || position.notional == 0
            ? '0.00%'
            : '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%',
        accent: sideColor(position.side),
        marker: firstMarker(position.symbol),
        meta: '현재 포지션',
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
    change: pnl >= 0 ? '정상' : pct(pnl),
    changePct: '한도 $limit',
    accent: pnl < 0 ? const Color(0xFFC8404A) : const Color(0xFF2F8F75),
    marker: marker,
    meta: '자동 가드',
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

String regimeLabel(String regime) {
  return switch (regime) {
    'BULL' => '강세',
    'BEAR' => '약세',
    'RANGE' => '횡보',
    'CHAOTIC' => '혼조',
    'TOP10_LONG' => '상위10 롱',
    'BTC_ETH_LONG' => 'BTC/ETH 롱',
    'ALT_WEAK_SHORT' => '알트 약세 숏',
    'SHORT_MODE' => '숏 모드',
    _ => regime,
  };
}

String modeLabel(String mode) {
  return switch (mode) {
    'LONG' => '롱',
    'SHORT' => '숏',
    'OBSERVE' => '관망',
    'PAUSED' => '정지',
    'NEUTRAL' => '중립',
    _ => mode,
  };
}

String riskLabel(String risk) {
  return switch (risk) {
    'OK' => '정상',
    'NONE' => '없음',
    'BLOCK_NEW_ENTRIES' => '신규 진입 차단',
    'REDUCE_HALF' => '50% 축소',
    'CLOSE_ALL_AND_PAUSE' => '전량 청산 후 정지',
    _ => risk,
  };
}

String sideLabel(String side) {
  return switch (side) {
    'LONG' => '롱',
    'SHORT' => '숏',
    'FLAT' => '플랫',
    _ => side,
  };
}

String sourceLabel(String source) {
  return switch (source) {
    'Local project snapshot' => '로컬 스냅샷',
    'Engine API' => '엔진 API',
    _ => source,
  };
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

String eventKindLabel(String kind) {
  return switch (kind) {
    'ALERT' => '알림',
    'DECISION' => '판단',
    'SECRET' => '시크릿',
    'WORKER' => '워커',
    'ERROR' => '오류',
    _ => kind,
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

double? toNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

int? toNullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String fmtNullablePct(double? value) {
  if (value == null) return '-';
  return '${value.toStringAsFixed(2)}%';
}

String boolDirection(bool? up, bool? down) {
  if (up == true && down == true) return 'CONFLICT';
  if (up == true) return 'UP';
  if (down == true) return 'DOWN';
  return 'MIXED';
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
