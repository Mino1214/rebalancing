import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://engine.medicalnewshub.info',
);

const String _appLogoAsset = 'icons/logos.png';

const Map<String, String> _iconAssets = {
  'APP_LOGO': _appLogoAsset,
  'BINANCE': 'icons/binance.svg',
  'BNB': 'icons/BNB.svg',
  'BTC': 'icons/BTC.svg',
  'DOGE': 'icons/DOGE.svg',
  'EDEN': 'icons/EDEN.svg',
  'ETH': 'icons/ETH.svg',
  'HYPE': 'icons/HYPE.svg',
  'MARKET': 'icons/crypto-total-market-cap.svg',
  'SOL': 'icons/SOL.svg',
  'TOTAL': 'icons/crypto-total-market-cap.svg',
  'TRADINGVIEW': 'icons/tradingview.svg',
  'TRX': 'icons/TRX.svg',
  'XRP': 'icons/XRP.svg',
  'ZEC': 'icons/ZEC.svg',
};

const List<String> _fallbackCryptoIcons = [
  'icons/BTC.svg',
  'icons/ETH.svg',
  'icons/BNB.svg',
  'icons/SOL.svg',
  'icons/XRP.svg',
  'icons/DOGE.svg',
  'icons/TRX.svg',
  'icons/HYPE.svg',
  'icons/ZEC.svg',
  'icons/EDEN.svg',
];

class AppTextStyles {
  const AppTextStyles._();

  static const detailTitle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w900,
    color: Color(0xFF15171E),
    letterSpacing: 0,
    height: 1.1,
  );

  static const detailSubtitle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Color(0xFF7A7F89),
    letterSpacing: 0,
    height: 1.25,
  );

  static const sectionTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w900,
    color: Color(0xFF15171E),
    letterSpacing: 0,
    height: 1.2,
  );

  static const rowLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    color: Color(0xFF7A7F89),
    letterSpacing: 0,
    height: 1.2,
  );

  static const rowValue = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w900,
    color: Color(0xFF15171E),
    letterSpacing: 0,
    height: 1.2,
  );

  static const rowMeta = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: Color(0xFF8A8D94),
    letterSpacing: 0,
    height: 1.2,
  );
}

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
      title: '리밸런싱 관전',
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
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: states.contains(WidgetState.selected)
                  ? const Color(0xFF15171E)
                  : const Color(0xFFAEB2BA),
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
                AppChrome(loading: loading, onRefresh: _refresh),
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
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(color: Color(0xFFF1F2F4), width: 1),
              ),
            ),
            child: NavigationBar(
              height: 60,
              backgroundColor: Colors.white,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              selectedIndex: _selectedTab,
              onDestinationSelected: (index) =>
                  setState(() => _selectedTab = index),
              destinations: [
                NavigationDestination(
                  icon: Icon(PhosphorIconsRegular.squaresFour, size: 23),
                  selectedIcon: Icon(PhosphorIconsFill.squaresFour, size: 23),
                  label: '현황',
                ),
                NavigationDestination(
                  icon: Icon(PhosphorIconsRegular.chartPieSlice, size: 23),
                  selectedIcon: Icon(PhosphorIconsFill.chartPieSlice, size: 23),
                  label: '포지션',
                ),
                NavigationDestination(
                  icon: Icon(PhosphorIconsRegular.receipt, size: 23),
                  selectedIcon: Icon(PhosphorIconsFill.receipt, size: 23),
                  label: '주문',
                ),
                NavigationDestination(
                  icon: Icon(PhosphorIconsRegular.chartLineUp, size: 23),
                  selectedIcon: Icon(PhosphorIconsFill.chartLineUp, size: 23),
                  label: '시장',
                ),
                NavigationDestination(
                  icon: Icon(PhosphorIconsRegular.listBullets, size: 23),
                  selectedIcon: Icon(PhosphorIconsFill.listBullets, size: 23),
                  label: '로그',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AppChrome extends StatelessWidget {
  const AppChrome({
    super.key,
    required this.loading,
    required this.onRefresh,
  });

  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 10, 2),
      child: Row(
        children: [
          const Spacer(),
          IconButton(
            tooltip: '새로고침',
            onPressed: onRefresh,
            splashRadius: 22,
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.2, color: Color(0xFF8A8D94)),
                  )
                : Icon(PhosphorIconsRegular.arrowsClockwise,
                    size: 22, color: const Color(0xFF6B7079)),
          ),
        ],
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
        title: '운영 현황',
        subtitle: '${sourceLabel(snapshot.source)} · ${snapshot.lastUpdated}',
        metric: compactUsdt(snapshot.equity),
        accent: regimeColor(snapshot.regime),
        chart: Column(
          children: [
            LiveFlowCard(snapshot: snapshot),
            CurrentStatusCard(snapshot: snapshot),
            PnlChartCard(
              daily: snapshot.dailyPnlPct,
              weekly: snapshot.weeklyPnlPct,
              monthly: snapshot.monthlyPnlPct,
            ),
          ],
        ),
        items: summaryItems(snapshot),
      ),
    );
  }
}

class LiveFlowCard extends StatefulWidget {
  const LiveFlowCard({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  State<LiveFlowCard> createState() => _LiveFlowCardState();
}

class _LiveFlowCardState extends State<LiveFlowCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final accent = regimeColor(snapshot.regime);
    final latestLog = snapshot.events.isEmpty ? null : snapshot.events.first;
    final stages = [
      FlowStageData(
        label: 'SIGNAL',
        value: signalActionLabel(snapshot.tradingViewSignal),
        icon: PhosphorIconsRegular.broadcast,
        color: accent,
      ),
      FlowStageData(
        label: 'ENGINE',
        value: decisionLabel(snapshot),
        icon: PhosphorIconsRegular.cpu,
        color: accent,
      ),
      FlowStageData(
        label: 'ORDER',
        value: '${snapshot.orders.length}개',
        icon: PhosphorIconsRegular.receipt,
        color: snapshot.orders.isEmpty
            ? const Color(0xFF787B86)
            : const Color(0xFFC08A17),
      ),
      FlowStageData(
        label: 'POSITION',
        value: '${snapshot.positions.length}개',
        icon: PhosphorIconsRegular.chartPieSlice,
        color: snapshot.positions.isEmpty
            ? const Color(0xFF787B86)
            : const Color(0xFF2563EB),
      ),
      FlowStageData(
        label: 'LOG',
        value: latestLog == null ? '-' : eventMinuteLabel(latestLog.time),
        icon: PhosphorIconsRegular.listBullets,
        color: latestLog == null
            ? const Color(0xFF787B86)
            : eventColor(latestLog.kind),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFF11151D),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsRegular.arrowsLeftRight,
                  size: 17,
                  color: accent,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Live Flow',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${signalSourceLabel(snapshot.tradingViewSignal)} · ${statusFreshnessLabel(snapshot)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF9AA1AF),
                        letterSpacing: 0,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: modeLabel(snapshot.mode), color: accent),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 116,
            child: LayoutBuilder(
              builder: (context, _) {
                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: FlowTrackPainter(
                        progress: _controller.value,
                        accent: accent,
                        stageColors: stages
                            .map((stage) => stage.color)
                            .toList(growable: false),
                      ),
                      child: child,
                    );
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var index = 0; index < stages.length; index++) ...[
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: FlowStageNode(
                              stage: stages[index],
                              active: flowActiveIndex(snapshot) == index,
                            ),
                          ),
                        ),
                        if (index != stages.length - 1)
                          const SizedBox(width: 7),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class FlowStageData {
  const FlowStageData({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class FlowStageNode extends StatelessWidget {
  const FlowStageNode({
    super.key,
    required this.stage,
    required this.active,
  });

  final FlowStageData stage;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.fromLTRB(7, 8, 7, 8),
      decoration: BoxDecoration(
        color: active
            ? stage.color.withValues(alpha: 0.22)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? stage.color.withValues(alpha: 0.70)
              : Colors.white.withValues(alpha: 0.10),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: stage.color.withValues(alpha: 0.20),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ]
            : const [],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: stage.color.withValues(alpha: active ? 0.28 : 0.16),
              shape: BoxShape.circle,
            ),
            child: Icon(stage.icon, size: 16, color: stage.color),
          ),
          const SizedBox(height: 6),
          Text(
            stage.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: Color(0xFF9AA1AF),
              letterSpacing: 0,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stage.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class FlowTrackPainter extends CustomPainter {
  const FlowTrackPainter({
    required this.progress,
    required this.accent,
    required this.stageColors,
  });

  final double progress;
  final Color accent;
  final List<Color> stageColors;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0 || stageColors.length < 2) return;

    final y = size.height * 0.18;
    final left = 18.0;
    final right = size.width - 18.0;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(left, y), Offset(right, y), track);

    final glow = Paint()
      ..color = accent.withValues(alpha: 0.18)
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawLine(Offset(left, y), Offset(right, y), glow);

    final segment = (right - left) / (stageColors.length - 1);
    for (var index = 0; index < stageColors.length; index++) {
      final x = left + segment * index;
      final nodePaint = Paint()
        ..color = stageColors[index].withValues(alpha: 0.86);
      canvas.drawCircle(Offset(x, y), 4.8, nodePaint);
      canvas.drawCircle(
        Offset(x, y),
        9.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = stageColors[index].withValues(alpha: 0.34),
      );
    }

    for (var index = 0; index < 3; index++) {
      final particleProgress = (progress + index / 3) % 1.0;
      final eased = Curves.easeInOut.transform(particleProgress);
      final x = left + (right - left) * eased;
      final pulse = 0.65 + 0.35 * (1 - (particleProgress * 2 - 1).abs());
      final color = Color.lerp(accent, Colors.white, 0.24)!;
      canvas.drawCircle(
        Offset(x, y),
        13 * pulse,
        Paint()..color = color.withValues(alpha: 0.10),
      );
      canvas.drawCircle(
        Offset(x, y),
        5.5 * pulse,
        Paint()..color = color.withValues(alpha: 0.92),
      );
    }
  }

  @override
  bool shouldRepaint(covariant FlowTrackPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.accent != accent ||
        oldDelegate.stageColors != stageColors;
  }
}

class CurrentStatusCard extends StatelessWidget {
  const CurrentStatusCard({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final paper = snapshot.paperAccount;
    final signal = snapshot.tradingViewSignal;
    final latestLog = snapshot.events.isEmpty ? null : snapshot.events.first;
    final metrics = [
      StatusMetricData(
        label: '판정',
        value: decisionLabel(snapshot),
        meta: '${regimeLabel(snapshot.regime)} · ${modeLabel(snapshot.mode)}',
        accent: regimeColor(snapshot.regime),
      ),
      StatusMetricData(
        label: '노출',
        value: '${snapshot.leverage.toStringAsFixed(2)}x',
        meta:
            '${compactUsdt(snapshot.currentExposure)} / ${compactUsdt(snapshot.targetExposure)}',
        accent: snapshot.leverage <= 2
            ? const Color(0xFF2F8F75)
            : const Color(0xFFC8404A),
      ),
      StatusMetricData(
        label: '손익',
        value: paper == null
            ? pct(snapshot.dailyPnlPct)
            : fmtNullableSignedUsdt(paper.totalPnl),
        meta: paper == null
            ? '일간 기준'
            : '${pct(paper.totalPnlPct)} · 비용 ${compactUsdt(paper.tradingCosts)}',
        accent: paper == null
            ? pnlColor(snapshot.dailyPnlPct)
            : pnlColor(paper.totalPnlPct),
      ),
      StatusMetricData(
        label: '포지션',
        value: '${snapshot.positions.length}개',
        meta: '주문 ${snapshot.orders.length}개',
        accent: snapshot.positions.isEmpty
            ? const Color(0xFF787B86)
            : const Color(0xFF2563EB),
      ),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: regimeColor(snapshot.regime).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsFill.chartLineUp,
                  size: 17,
                  color: regimeColor(snapshot.regime),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '현재 현황',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      statusFreshnessLabel(snapshot),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A8D94),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: signalActionLabel(signal),
                color: regimeColor(snapshot.regime),
              ),
            ],
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 4 : 2;
              const gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: width,
                      child: StatusMetricTile(metric: metric),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          StatusInlineRow(
            icon: PhosphorIconsRegular.broadcast,
            label: '신호',
            value: signalSourceLabel(signal),
            meta: signalReasonSummary(signal),
            accent: regimeColor(snapshot.regime),
          ),
          const SizedBox(height: 8),
          StatusInlineRow(
            icon: PhosphorIconsRegular.brain,
            label: '학습',
            value:
                '${learningStageLabel(snapshot.learning.stage)} · ${learningStatusLabel(snapshot.learning.latestRunStatus)}',
            meta: learningActiveVersionLabel(snapshot.learning),
            accent: learningColor(snapshot.learning),
          ),
          const SizedBox(height: 8),
          StatusInlineRow(
            icon: PhosphorIconsRegular.listBullets,
            label: '최근 로그',
            value: latestLog == null ? '이벤트 없음' : eventLogSummary(latestLog),
            meta: latestLog == null ? '-' : eventMinuteLabel(latestLog.time),
            accent: latestLog == null
                ? const Color(0xFF787B86)
                : eventColor(latestLog.kind),
          ),
        ],
      ),
    );
  }
}

class StatusMetricData {
  const StatusMetricData({
    required this.label,
    required this.value,
    required this.meta,
    required this.accent,
  });

  final String label;
  final String value;
  final String meta;
  final Color accent;
}

class StatusMetricTile extends StatelessWidget {
  const StatusMetricTile({super.key, required this.metric});

  final StatusMetricData metric;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8EAEE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            metric.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8A8D94),
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: metric.accent,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAEB2BA),
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusInlineRow extends StatelessWidget {
  const StatusInlineRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.meta,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final String meta;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: accent),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 54,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF8A8D94),
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4E535C),
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFAEB2BA),
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
        ),
      ],
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
      onItemTap: snapshot.positions.isEmpty
          ? null
          : (item) {
              final position = positionForWatchItem(snapshot, item);
              if (position != null) {
                showPositionDetailScreen(context, snapshot, position);
              }
            },
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
    final rebalance = snapshot.paperRebalance;
    return WatchListScaffold(
      title: '이벤트 로그',
      subtitle: logSubtitle(snapshot),
      metric: '${snapshot.events.length}개',
      accent: const Color(0xFF2563EB),
      chart: rebalance == null ? null : RebalanceFlowCard(rebalance: rebalance),
      items: consoleItems(snapshot, includeRebalance: rebalance == null),
      compactLogRows: true,
      onItemTap: (item) {
        showLogDetailScreen(context, snapshot, item);
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
    this.chart,
    this.onItemTap,
    this.compactLogRows = false,
  });

  final List<WatchItem> items;
  final String title;
  final String subtitle;
  final String metric;
  final Color accent;
  final Widget? chart;
  final ValueChanged<WatchItem>? onItemTap;
  final bool compactLogRows;

  @override
  Widget build(BuildContext context) {
    final leading = <Widget>[
      ConsoleHeader(
        title: title,
        subtitle: subtitle,
        metric: metric,
        accent: accent,
      ),
      if (chart != null) chart!,
    ];
    final leadCount = leading.length;

    return ListView.separated(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: leadCount + items.length,
      separatorBuilder: (context, index) {
        if (index < leadCount) {
          return const SizedBox(height: 6);
        }
        return const Divider(
          height: 1,
          indent: 68,
          endIndent: 18,
          color: Color(0xFFF1F2F4),
        );
      },
      itemBuilder: (context, index) {
        final delay = Duration(milliseconds: (index * 45).clamp(0, 360));
        if (index < leadCount) {
          return FadeInUp(delay: delay, child: leading[index]);
        }
        final item = items[index - leadCount];
        return FadeInUp(
          delay: delay,
          child: compactLogRows
              ? LogRow(
                  item: item,
                  onTap: onItemTap == null ? null : () => onItemTap!(item),
                )
              : WatchRow(
                  item: item,
                  onTap: onItemTap == null ? null : () => onItemTap!(item),
                ),
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
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
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
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF15171E),
                      letterSpacing: 0,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF9498A0),
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
                fontSize: 17,
                fontWeight: FontWeight.w800,
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

class PnlChartCard extends StatelessWidget {
  const PnlChartCard({
    super.key,
    required this.daily,
    required this.weekly,
    required this.monthly,
  });

  final double daily;
  final double weekly;
  final double monthly;

  @override
  Widget build(BuildContext context) {
    final entries = <(String, double)>[
      ('일간', daily),
      ('주간', weekly),
      ('월간', monthly),
    ];
    final maxAbs =
        entries.map((e) => e.$2.abs()).fold<double>(0, (a, b) => a > b ? a : b);
    final scale = maxAbs < 0.01 ? 1.0 : maxAbs;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIconsFill.chartBar,
                  size: 15, color: const Color(0xFF6B7079)),
              const SizedBox(width: 6),
              const Text(
                '손익 추이',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF15171E),
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              const Text(
                '일 · 주 · 월',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFAEB2BA),
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final e in entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: _PnlBar(label: e.$1, value: e.$2, scale: scale),
            ),
        ],
      ),
    );
  }
}

class _PnlBar extends StatelessWidget {
  const _PnlBar(
      {required this.label, required this.value, required this.scale});

  final String label;
  final double value;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final gain = value >= 0;
    final color = value == 0
        ? const Color(0xFFC4C8CE)
        : (gain ? const Color(0xFF2F8F75) : const Color(0xFFC8404A));
    final frac = (value.abs() / scale).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7A7F89),
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: gain ? 0.0 : frac,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                              left: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                    width: 1.5, height: 10, color: const Color(0xFFE2E5EA)),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: gain ? frac : 0.0,
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                              right: Radius.circular(4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 64,
          child: Text(
            pct(value),
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
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
        (MediaQuery.sizeOf(context).width * 0.36).clamp(140.0, 280.0);
    final changeText = item.changePct.isEmpty
        ? item.change
        : '${item.change} · ${item.changePct}';

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(
            children: [
              WatchIconBadge(item: item),
              const SizedBox(width: 12),
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
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9498A0),
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
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      changeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: changeColor,
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                    ),
                    if (item.meta.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFFAEB2BA),
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

class LogRow extends StatelessWidget {
  const LogRow({super.key, required this.item, this.onTap});

  final WatchItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final timeLabel = eventMinuteLabel(item.value);
    final dayLabel = eventDayLabel(item.value);
    final hintLabel = item.changePct.isNotEmpty ? item.changePct : dayLabel;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 14, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              WatchIconBadge(item: item, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.accent.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.change,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: item.accent,
                              letterSpacing: 0,
                              height: 1.1,
                            ),
                          ),
                        ),
                        if (hintLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hintLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFAEB2BA),
                                letterSpacing: 0,
                                height: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4E535C),
                        letterSpacing: 0,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 48,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.05,
                      ),
                    ),
                    if (dayLabel.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        dayLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFAEB2BA),
                          letterSpacing: 0,
                          height: 1.05,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  PhosphorIconsRegular.caretRight,
                  size: 15,
                  color: const Color(0xFFC2C6CE),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class RebalanceFlowCard extends StatelessWidget {
  const RebalanceFlowCard({super.key, required this.rebalance});

  final PaperRebalanceView rebalance;

  @override
  Widget build(BuildContext context) {
    final reduced = rebalance.reducedSymbols.isNotEmpty
        ? rebalance.reducedSymbols
        : rebalance.closedSymbols;
    final added = rebalance.openedSymbols.isNotEmpty
        ? rebalance.openedSymbols
        : rebalance.increasedSymbols;
    final hasReduced = reduced.isNotEmpty;
    final hasAdded = added.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color:
                      eventColor(rebalance.eventKind).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsFill.arrowsLeftRight,
                  size: 17,
                  color: eventColor(rebalance.eventKind),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rebalanceFlowTitle(rebalance),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF15171E),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${compactUsdt(rebalance.fromExposure)} → ${compactUsdt(rebalance.toExposure)} · ${eventMinuteLabel(rebalance.time)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A8D94),
                        letterSpacing: 0,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                compactUsdt(rebalance.grossOrderNotional),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: eventColor(rebalance.eventKind),
                  letterSpacing: 0,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: RebalanceSymbolGroup(
                  label: hasReduced ? reduceFlowLabel(rebalance) : '기존',
                  symbols: hasReduced ? reduced : rebalance.changedSymbols,
                  accent: const Color(0xFFC8404A),
                  emptyText: '변경 없음',
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  flowArrowIcon(rebalance),
                  size: 20,
                  color: const Color(0xFFAEB2BA),
                ),
              ),
              Expanded(
                child: RebalanceSymbolGroup(
                  label: hasAdded
                      ? addFlowLabel(rebalance)
                      : holdFlowLabel(rebalance),
                  symbols: hasAdded ? added : rebalance.changedSymbols,
                  accent: hasAdded
                      ? const Color(0xFF2F8F75)
                      : const Color(0xFF2563EB),
                  emptyText: '대기',
                ),
              ),
            ],
          ),
          if (rebalance.changedSymbols.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              symbolsFlowSentence(rebalance),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5F6570),
                letterSpacing: 0,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class RebalanceSymbolGroup extends StatelessWidget {
  const RebalanceSymbolGroup({
    super.key,
    required this.label,
    required this.symbols,
    required this.accent,
    required this.emptyText,
  });

  final String label;
  final List<String> symbols;
  final Color accent;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final shown = symbols.take(4).toList(growable: false);
    final overflow = symbols.length - shown.length;

    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8EAEE)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: accent,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            Text(
              emptyText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Color(0xFFAEB2BA),
                letterSpacing: 0,
                height: 1.15,
              ),
            )
          else
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final symbol in shown)
                  SymbolLogo(symbol: symbol, size: 28),
                if (overflow > 0)
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F2F4),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFE2E5EA)),
                    ),
                    child: Text(
                      '+$overflow',
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF6B7079),
                        letterSpacing: 0,
                        height: 1,
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

class SymbolLogo extends StatelessWidget {
  const SymbolLogo({super.key, required this.symbol, this.size = 32});

  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = iconAssetForSymbol(symbol);
    final fallback = fallbackIconAssetForSymbol(symbol);
    if (asset != null) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: asset.toLowerCase().endsWith('.svg')
              ? SvgPicture.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      SvgPicture.asset(fallback, fit: BoxFit.cover),
                )
              : Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      SvgPicture.asset(fallback, fit: BoxFit.cover),
                ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F4),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE2E5EA)),
      ),
      child: Text(
        baseCryptoSymbol(symbol).characters.take(2).join(),
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: Color(0xFF4E535C),
          letterSpacing: 0,
          height: 1,
        ),
      ),
    );
  }
}

class WatchIconBadge extends StatelessWidget {
  const WatchIconBadge({super.key, required this.item, this.size = 46});

  final WatchItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = iconAssetForWatchItem(item);
    final fallbackAsset = fallbackIconAssetForWatchItem(item);
    final iconSize = size * 0.46;
    if (asset != null) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: asset.toLowerCase().endsWith('.svg')
              ? SvgPicture.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      SvgPicture.asset(
                    fallbackAsset,
                    fit: BoxFit.cover,
                  ),
                  placeholderBuilder: (context) => Icon(
                    watchIcon(item.symbol),
                    size: iconSize,
                    color: item.accent,
                  ),
                )
              : Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      SvgPicture.asset(
                    fallbackAsset,
                    fit: BoxFit.cover,
                  ),
                ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: item.accent.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(
        watchIcon(item.symbol),
        size: iconSize,
        color: item.accent,
      ),
    );
  }
}

class FadeInUp extends StatefulWidget {
  const FadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<FadeInUp> createState() => _FadeInUpState();
}

class _FadeInUpState extends State<FadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        return Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, (1 - _curve.value) * widget.offset),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

void showEngineResultScreen(BuildContext context, EngineSnapshot snapshot) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => EngineResultScreen(snapshot: snapshot),
    ),
  );
}

void showLogDetailScreen(
  BuildContext context,
  EngineSnapshot snapshot,
  WatchItem item,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => LogDetailScreen(snapshot: snapshot, item: item),
    ),
  );
}

void showPositionDetailScreen(
  BuildContext context,
  EngineSnapshot snapshot,
  PositionView position,
) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => PositionDetailScreen(
        snapshot: snapshot,
        position: position,
      ),
    ),
  );
}

class LogDetailScreen extends StatelessWidget {
  const LogDetailScreen({
    super.key,
    required this.snapshot,
    required this.item,
  });

  final EngineSnapshot snapshot;
  final WatchItem item;

  @override
  Widget build(BuildContext context) {
    final timeLabel = eventMinuteLabel(item.value);
    final dayLabel = eventDayLabel(item.value);
    final detailText = item.detail.isEmpty ? item.title : item.detail;
    final sections = <Widget>[
      DetailSection(
        title: '로그',
        rows: [
          DetailRowData('종류', item.change, item.symbol),
          DetailRowData('요약', item.title, item.changePct),
          DetailRowData(
            '시간',
            timeLabel,
            dayLabel.isEmpty ? item.value : dayLabel,
          ),
        ],
      ),
      DetailTextSection(title: '원문', text: detailText),
      if (item.meta.isNotEmpty && item.meta != item.value)
        DetailSection(
          title: '참조',
          rows: [
            DetailRowData('메타', item.meta, sourceLabel(snapshot.source)),
          ],
        ),
    ];

    if (logItemOpensEngineResult(item)) {
      sections.add(
        DetailSection(
          title: '엔진 결과',
          rows: [
            DetailRowData(
              '판정',
              '${regimeLabel(snapshot.regime)} / ${modeLabel(snapshot.mode)}',
              snapshot.marketBias,
            ),
            DetailRowData(
              '노출',
              '${compactUsdt(snapshot.currentExposure)} → ${compactUsdt(snapshot.targetExposure)}',
              '${snapshot.leverage.toStringAsFixed(2)}x',
            ),
            DetailRowData(
              '스냅샷',
              snapshot.lastUpdated,
              sourceLabel(snapshot.source),
            ),
          ],
        ),
      );
      sections.addAll(engineResultSections(snapshot));
    }

    return DetailPageScaffold(
      title: '로그 상세',
      subtitle: '${item.change} · $timeLabel',
      icon: watchIcon(item.symbol),
      accent: item.accent,
      children: sections,
    );
  }
}

class EngineResultScreen extends StatelessWidget {
  const EngineResultScreen({super.key, required this.snapshot});

  final EngineSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final signal = snapshot.tradingViewSignal;
    final accent = regimeColor(snapshot.regime);

    return DetailPageScaffold(
      title: '엔진 결과',
      subtitle: signal?.signalId ?? snapshot.lastUpdated,
      icon: PhosphorIconsFill.chartLineUp,
      accent: accent,
      children: engineResultSections(snapshot),
    );
  }
}

List<Widget> engineResultSections(EngineSnapshot snapshot) {
  final signal = snapshot.tradingViewSignal;
  final rebalance = snapshot.paperRebalance;
  final learning = snapshot.learning;

  return [
    if (rebalance != null)
      DetailSection(
        title: '최근 리밸런싱',
        rows: [
          DetailRowData(
            '결과',
            rebalanceEventLabel(rebalance.eventKind),
            '${regimeLabel(rebalance.regime)} / ${modeLabel(rebalance.mode)}',
          ),
          DetailRowData(
            '노출',
            '${compactUsdt(rebalance.fromExposure)} → ${compactUsdt(rebalance.toExposure)}',
            '목표 ${compactUsdt(rebalance.targetExposure)}',
          ),
          DetailRowData(
            '주문',
            '${rebalance.orderCount}개',
            '진입 ${rebalance.openCount} · 청산 ${rebalance.closeCount}',
          ),
          DetailRowData(
            '구성',
            '${rebalance.positionCountBefore} → ${rebalance.positionCountAfter}종목',
            '회전 ${compactUsdt(rebalance.grossOrderNotional)}',
          ),
          DetailRowData(
            '변경',
            symbolsPreview(rebalance.changedSymbols),
            rebalance.signalId,
          ),
          DetailRowData(
            '시간',
            eventMinuteLabel(rebalance.time),
            eventDayLabel(rebalance.time),
          ),
        ],
      ),
    DetailSection(
      title: 'TradingView',
      rows: [
        DetailRowData(
            '레짐', signal?.regime ?? '-', regimeLabel(signal?.regime ?? '-')),
        DetailRowData('타임프레임', signal?.timeframe ?? '-', 'confirmed'),
        DetailRowData(
          '목표 레버리지',
          '${(signal?.targetLeverage ?? 0).toStringAsFixed(2)}x',
          'TV',
        ),
        DetailRowData(
          '신호 시간',
          signal == null
              ? '-'
              : eventMinuteLabel(signal.barTimeMs ?? signal.timeMs),
          signal == null
              ? '-'
              : eventDayLabel(signal.barTimeMs ?? signal.timeMs),
        ),
      ],
    ),
    DetailSection(
      title: 'Engine',
      rows: [
        DetailRowData(
          '판정',
          '${regimeLabel(snapshot.regime)} / ${modeLabel(snapshot.mode)}',
          snapshot.marketBias,
        ),
        DetailRowData(
          '점수',
          displayRegimeScore(snapshot).toStringAsFixed(1),
          displayRegimeScoreLabel(snapshot),
        ),
        DetailRowData(
          '노출',
          '${compactUsdt(snapshot.currentExposure)} → ${compactUsdt(snapshot.targetExposure)}',
          '${snapshot.leverage.toStringAsFixed(2)}x',
        ),
        DetailRowData(
          '주문',
          '${snapshot.orders.length}개',
          riskLabel(snapshot.riskState),
        ),
      ],
    ),
    DetailSection(
      title: 'Learning',
      rows: [
        DetailRowData(
          '단계',
          learningStageLabel(learning.stage),
          learning.runCount == 0 ? '대기' : 'run ${learning.runCount}',
        ),
        DetailRowData(
          '최근 실행',
          learningStatusLabel(learning.latestRunStatus),
          learningRunMeta(learning),
        ),
        DetailRowData(
          '평가',
          '${learning.evaluationCount}회',
          compactLearningSummary(learning),
        ),
        DetailRowData(
          '활성 파라미터',
          learningActiveVersionLabel(learning),
          learningParamSummary(learning),
        ),
      ],
    ),
    DetailSection(
      title: 'Market',
      rows: [
        DetailRowData(
          'Internals',
          snapshot.marketInternals.riskLabel,
          snapshot.marketInternals.source,
        ),
        DetailRowData(
          'Stable.D',
          fmtNullablePct(snapshot.marketInternals.stableDominancePct),
          'defensive',
        ),
        DetailRowData(
          'Top10.D',
          fmtNullablePct(snapshot.marketInternals.top10DominanceTotalPct),
          'cap',
        ),
        DetailRowData(
          'Breadth',
          fmtNullablePct(snapshot.marketInternals.volumeBreadthPct),
          snapshot.marketInternals.advanceDeclineLabel,
        ),
      ],
    ),
    DetailSection(
      title: 'Signal Flags',
      rows: [
        DetailRowData(
            'BTC', boolDirection(signal?.btcUp, signal?.btcDown), 'direction'),
        DetailRowData(
          'TOTAL',
          boolDirection(signal?.totalUp, signal?.totalDown),
          'market',
        ),
        DetailRowData(
          'TOTAL2',
          boolDirection(signal?.total2Up, signal?.total2Down),
          'alts',
        ),
        DetailRowData(
          'TOTAL3',
          signal?.total3Weak == true ? 'WEAK' : 'OK',
          'pure alts',
        ),
        DetailRowData(
          'BTC.D',
          boolDirection(signal?.btcdUp, signal?.btcdDown),
          'flow',
        ),
      ],
    ),
  ];
}

class PositionDetailScreen extends StatelessWidget {
  const PositionDetailScreen({
    super.key,
    required this.snapshot,
    required this.position,
  });

  final EngineSnapshot snapshot;
  final PositionView position;

  @override
  Widget build(BuildContext context) {
    final accent = sideColor(position.side);

    return DetailPageScaffold(
      title: '포지션 상세',
      subtitle: '${position.symbol} · ${sideLabel(position.side)}',
      icon: PhosphorIconsFill.chartPieSlice,
      accent: accent,
      children: [
        DetailSection(
          title: 'Position',
          rows: [
            DetailRowData('방향', sideLabel(position.side), position.side),
            DetailRowData(
              '명목금액',
              positionNotionalUsdt(position),
              positionExposurePct(snapshot, position),
            ),
            DetailRowData(
              '수량',
              fmtNullableQuantity(position.quantity),
              'contracts',
            ),
            DetailRowData(
              '레버리지',
              fmtNullableLeverage(position.leverage),
              '계좌 ${snapshot.leverage.toStringAsFixed(2)}x',
            ),
          ],
        ),
        DetailSection(
          title: 'Price / PnL',
          rows: [
            DetailRowData(
                '진입가', fmtNullablePrice(position.entryPrice), 'entry'),
            DetailRowData('마크가', fmtNullablePrice(position.markPrice), 'mark'),
            DetailRowData(
              '청산가',
              fmtNullablePrice(position.liquidationPrice),
              'liq',
            ),
            DetailRowData(
              '미실현 손익',
              fmtNullableSignedUsdt(position.unrealizedPnl),
              positionPnlPct(position),
            ),
          ],
        ),
        DetailSection(
          title: 'Context',
          rows: [
            DetailRowData(
              '마진',
              position.marginType.isEmpty ? '-' : position.marginType,
              sourceLabel(snapshot.source),
            ),
            DetailRowData(
              '현재 노출',
              compactUsdt(snapshot.currentExposure),
              '목표 ${compactUsdt(snapshot.targetExposure)}',
            ),
            DetailRowData('업데이트', snapshot.lastUpdated, 'snapshot'),
          ],
        ),
      ],
    );
  }
}

class DetailPageScaffold extends StatelessWidget {
  const DetailPageScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: '닫기',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            PhosphorIconsRegular.x,
            size: 22,
            color: const Color(0xFF15171E),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 28),
          children: [
            DetailHeroHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              accent: accent,
            ),
            const SizedBox(height: 18),
            ...children,
          ],
        ),
      ),
    );
  }
}

class DetailHeroHeader extends StatelessWidget {
  const DetailHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, size: 24, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.detailTitle,
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.detailSubtitle,
              ),
            ],
          ),
        ),
      ],
    );
  }
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
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 8),
          ...rows.map((row) => DetailLine(row: row)),
        ],
      ),
    );
  }
}

class DetailTextSection extends StatelessWidget {
  const DetailTextSection({super.key, required this.title, required this.text});

  final String title;
  final String text;

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
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: AppTextStyles.rowValue.copyWith(height: 1.35),
          ),
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
              style: AppTextStyles.rowLabel,
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.rowValue,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              row.meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTextStyles.rowMeta,
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
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
    required this.paperRebalance,
    required this.paperAccount,
    required this.marketInternals,
    required this.learning,
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
  final PaperRebalanceView? paperRebalance;
  final PaperAccountView? paperAccount;
  final MarketInternalsView marketInternals;
  final LearningView learning;
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
      paperRebalance: PaperRebalanceView.tryParse(
        json['last_rebalance'] ??
            json['lastRebalance'] ??
            (json['paper'] is Map
                ? (json['paper'] as Map)['last_rebalance']
                : null),
      ),
      paperAccount: PaperAccountView.tryParse(json['paper']),
      marketInternals: MarketInternalsView.fromJson(
          json['market_internals'] ?? json['marketInternals']),
      learning: LearningView.fromJson(json['learning']),
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
        score: 80,
        timeMs: 1779215702553,
        barTimeMs: 1779215700000,
        signalId: 'RANGE_5_1779215700000',
      ),
      paperRebalance: const PaperRebalanceView(
        time: '2026-05-19T23:43:00+09:00',
        eventKind: 'PAPER_ENTRY',
        regime: 'BTC_ETH_LONG',
        mode: 'LONG',
        fromExposure: 0,
        toExposure: 3300,
        targetExposure: 3300,
        deltaExposure: 3300,
        orderCount: 2,
        openCount: 2,
        closeCount: 0,
        positionCountBefore: 0,
        positionCountAfter: 2,
        grossOrderNotional: 3300,
        changedSymbols: ['BTCUSDT', 'ETHUSDT'],
        openedSymbols: ['BTCUSDT', 'ETHUSDT'],
        increasedSymbols: [],
        reducedSymbols: [],
        closedSymbols: [],
        signalId: 'RANGE_5_1779215700000',
      ),
      paperAccount: const PaperAccountView(
        enabled: true,
        source: 'Paper trading',
        lastUpdated: '2026-05-19T23:43:00+09:00',
        initialEquity: 1000,
        totalPnl: 5.5,
        totalPnlPct: 0.55,
        realizedPnl: 1.2,
        unrealizedPnl: 4.3,
        tradingCosts: 0.4,
        turnover: 3300,
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
      learning: const LearningView(
        stage: 'BABY',
        runCount: 1,
        evaluationCount: 1,
        paramVersionCount: 1,
        tradeResultCount: 0,
        latestRunStatus: 'ok',
        latestRunTrigger: 'manual',
        latestRunTime: '2026-05-23T01:20:00+09:00',
        latestEvaluationSummary: '페이퍼 기록 기준으로 횡보장 진입 민감도를 낮춤',
        latestEvaluationTime: '2026-05-23T01:20:00+09:00',
        activeParamVersion: 1,
        rangeTargetLeverage: 0.5,
        confirmationCandles: 2,
        minNeutralHours: 6,
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
      paperRebalance: paperRebalance,
      paperAccount: paperAccount,
      marketInternals: marketInternals,
      learning: learning,
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
    this.score,
    this.source = '',
    this.decisionAction,
    this.decisionReason,
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
  final double? score;
  final String source;
  final String? decisionAction;
  final String? decisionReason;

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
      score: toNullableDouble(json['score']),
      timeMs: toNullableInt(json['time_ms'] ?? json['timeMs']),
      barTimeMs: toNullableInt(json['bar_time_ms'] ?? json['barTimeMs']),
      signalId: (json['signal_id'] ?? json['signalId'] ?? '-').toString(),
      source: (json['source'] ?? '').toString(),
      decisionAction:
          (json['decision_action'] ?? json['decisionAction'])?.toString(),
      decisionReason:
          (json['decision_reason'] ?? json['decisionReason'])?.toString(),
    );
  }
}

class PaperRebalanceView {
  const PaperRebalanceView({
    required this.time,
    required this.eventKind,
    required this.regime,
    required this.mode,
    required this.fromExposure,
    required this.toExposure,
    required this.targetExposure,
    required this.deltaExposure,
    required this.orderCount,
    required this.openCount,
    required this.closeCount,
    required this.positionCountBefore,
    required this.positionCountAfter,
    required this.grossOrderNotional,
    required this.changedSymbols,
    required this.openedSymbols,
    required this.increasedSymbols,
    required this.reducedSymbols,
    required this.closedSymbols,
    required this.signalId,
  });

  final String time;
  final String eventKind;
  final String regime;
  final String mode;
  final double fromExposure;
  final double toExposure;
  final double targetExposure;
  final double deltaExposure;
  final int orderCount;
  final int openCount;
  final int closeCount;
  final int positionCountBefore;
  final int positionCountAfter;
  final double grossOrderNotional;
  final List<String> changedSymbols;
  final List<String> openedSymbols;
  final List<String> increasedSymbols;
  final List<String> reducedSymbols;
  final List<String> closedSymbols;
  final String signalId;

  static PaperRebalanceView? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return PaperRebalanceView.fromJson(Map<String, dynamic>.from(raw));
  }

  factory PaperRebalanceView.fromJson(Map<String, dynamic> json) {
    return PaperRebalanceView(
      time: (json['time'] ?? '-').toString(),
      eventKind:
          (json['event_kind'] ?? json['eventKind'] ?? 'PAPER').toString(),
      regime: (json['regime'] ?? 'RANGE').toString(),
      mode: (json['mode'] ?? 'NEUTRAL').toString(),
      fromExposure: toDouble(json['from_exposure'] ?? json['fromExposure']),
      toExposure: toDouble(json['to_exposure'] ?? json['toExposure']),
      targetExposure:
          toDouble(json['target_exposure'] ?? json['targetExposure']),
      deltaExposure: toDouble(json['delta_exposure'] ?? json['deltaExposure']),
      orderCount: toInt(json['order_count'] ?? json['orderCount']),
      openCount: toInt(json['open_count'] ?? json['openCount']),
      closeCount: toInt(json['close_count'] ?? json['closeCount']),
      positionCountBefore:
          toInt(json['position_count_before'] ?? json['positionCountBefore']),
      positionCountAfter:
          toInt(json['position_count_after'] ?? json['positionCountAfter']),
      grossOrderNotional:
          toDouble(json['gross_order_notional'] ?? json['grossOrderNotional']),
      changedSymbols:
          stringListOf(json['changed_symbols'] ?? json['changedSymbols']),
      openedSymbols:
          stringListOf(json['opened_symbols'] ?? json['openedSymbols']),
      increasedSymbols:
          stringListOf(json['increased_symbols'] ?? json['increasedSymbols']),
      reducedSymbols:
          stringListOf(json['reduced_symbols'] ?? json['reducedSymbols']),
      closedSymbols:
          stringListOf(json['closed_symbols'] ?? json['closedSymbols']),
      signalId: (json['signal_id'] ?? json['signalId'] ?? '-').toString(),
    );
  }
}

class PaperAccountView {
  const PaperAccountView({
    required this.enabled,
    required this.source,
    required this.lastUpdated,
    required this.initialEquity,
    required this.totalPnl,
    required this.totalPnlPct,
    required this.realizedPnl,
    required this.unrealizedPnl,
    required this.tradingCosts,
    required this.turnover,
  });

  final bool enabled;
  final String source;
  final String lastUpdated;
  final double initialEquity;
  final double totalPnl;
  final double totalPnlPct;
  final double realizedPnl;
  final double unrealizedPnl;
  final double tradingCosts;
  final double turnover;

  static PaperAccountView? tryParse(Object? raw) {
    if (raw is! Map) return null;
    return PaperAccountView.fromJson(Map<String, dynamic>.from(raw));
  }

  factory PaperAccountView.fromJson(Map<String, dynamic> json) {
    return PaperAccountView(
      enabled: json['enabled'] != false,
      source: (json['source'] ?? 'Paper trading').toString(),
      lastUpdated:
          (json['last_updated'] ?? json['lastUpdated'] ?? '').toString(),
      initialEquity: toDouble(json['initial_equity'] ?? json['initialEquity']),
      totalPnl: toDouble(json['total_pnl'] ?? json['totalPnl']),
      totalPnlPct: toDouble(json['total_pnl_pct'] ?? json['totalPnlPct']),
      realizedPnl: toDouble(json['realized_pnl'] ?? json['realizedPnl']),
      unrealizedPnl: toDouble(json['unrealized_pnl'] ?? json['unrealizedPnl']),
      tradingCosts: toDouble(json['trading_costs'] ?? json['tradingCosts']),
      turnover: toDouble(json['turnover']),
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

class LearningView {
  const LearningView({
    required this.stage,
    required this.runCount,
    required this.evaluationCount,
    required this.paramVersionCount,
    required this.tradeResultCount,
    required this.latestRunStatus,
    required this.latestRunTrigger,
    required this.latestRunTime,
    required this.latestEvaluationSummary,
    required this.latestEvaluationTime,
    this.activeParamVersion,
    this.rangeTargetLeverage,
    this.confirmationCandles,
    this.minNeutralHours,
  });

  final String stage;
  final int runCount;
  final int evaluationCount;
  final int paramVersionCount;
  final int tradeResultCount;
  final String latestRunStatus;
  final String latestRunTrigger;
  final String latestRunTime;
  final String latestEvaluationSummary;
  final String latestEvaluationTime;
  final int? activeParamVersion;
  final double? rangeTargetLeverage;
  final int? confirmationCandles;
  final double? minNeutralHours;

  factory LearningView.fromJson(Object? raw) {
    final json =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final latestRunRaw = json['latest_run'] ?? json['latestRun'];
    final latestRun = latestRunRaw is Map
        ? Map<String, dynamic>.from(latestRunRaw)
        : <String, dynamic>{};
    final latestEvaluationRaw =
        json['latest_evaluation'] ?? json['latestEvaluation'];
    final latestEvaluation = latestEvaluationRaw is Map
        ? Map<String, dynamic>.from(latestEvaluationRaw)
        : <String, dynamic>{};
    final activeParamsRaw = json['active_params'] ?? json['activeParams'];
    final activeParams = activeParamsRaw is Map
        ? Map<String, dynamic>.from(activeParamsRaw)
        : <String, dynamic>{};

    return LearningView(
      stage: (json['stage'] ?? 'BABY').toString(),
      runCount: toInt(json['run_count'] ?? json['runCount']),
      evaluationCount:
          toInt(json['evaluation_count'] ?? json['evaluationCount']),
      paramVersionCount:
          toInt(json['param_version_count'] ?? json['paramVersionCount']),
      tradeResultCount:
          toInt(json['trade_result_count'] ?? json['tradeResultCount']),
      latestRunStatus: (latestRun['status'] ?? '').toString(),
      latestRunTrigger: (latestRun['trigger'] ?? '').toString(),
      latestRunTime: (latestRun['ts'] ?? latestRun['time'] ?? '').toString(),
      latestEvaluationSummary: (latestEvaluation['summary'] ?? '').toString(),
      latestEvaluationTime:
          (latestEvaluation['ts'] ?? latestEvaluation['time'] ?? '').toString(),
      activeParamVersion: toNullableInt(activeParams['version']),
      rangeTargetLeverage: toNullableDouble(
          activeParams['range_target_leverage'] ??
              activeParams['rangeTargetLeverage']),
      confirmationCandles: toNullableInt(activeParams['confirmation_candles'] ??
          activeParams['confirmationCandles']),
      minNeutralHours: toNullableDouble(
          activeParams['min_neutral_hours'] ?? activeParams['minNeutralHours']),
    );
  }
}

class PositionView {
  const PositionView({
    required this.symbol,
    required this.side,
    required this.notional,
    this.entryPrice,
    this.markPrice,
    this.unrealizedPnl,
    this.quantity,
    this.leverage,
    this.liquidationPrice,
    this.marginType = '',
  });

  final String symbol;
  final String side;
  final double notional;
  final double? entryPrice;
  final double? markPrice;
  final double? unrealizedPnl;
  final double? quantity;
  final double? leverage;
  final double? liquidationPrice;
  final String marginType;

  factory PositionView.fromJson(Map<String, dynamic> json) {
    return PositionView(
      symbol: (json['symbol'] ?? '-').toString(),
      side: (json['side'] ?? '-').toString(),
      notional: toDouble(json['notional']),
      entryPrice: toNullableDouble(json['entry_price'] ?? json['entryPrice']),
      markPrice: toNullableDouble(
          json['mark_price'] ?? json['markPrice'] ?? json['last_price']),
      unrealizedPnl: toNullableDouble(json['unrealized_pnl'] ??
          json['unrealizedPnl'] ??
          json['unRealizedProfit']),
      quantity: toNullableDouble(
          json['quantity'] ?? json['position_amt'] ?? json['positionAmt']),
      leverage: toNullableDouble(json['leverage']),
      liquidationPrice: toNullableDouble(
          json['liquidation_price'] ?? json['liquidationPrice']),
      marginType: (json['margin_type'] ?? json['marginType'] ?? '').toString(),
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
    this.iconAsset,
    this.detail = '',
  });

  final String symbol;
  final String title;
  final String value;
  final String change;
  final String changePct;
  final Color accent;
  final String marker;
  final String meta;
  final String? iconAsset;
  final String detail;

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
      iconAsset: (json['icon_asset'] ?? json['iconAsset'])?.toString(),
      detail: (json['detail'] ?? json['details'] ?? '').toString(),
    );
  }

  WatchItem copyWith({String? iconAsset, String? detail}) {
    return WatchItem(
      symbol: symbol,
      title: title,
      value: value,
      change: change,
      changePct: changePct,
      accent: accent,
      marker: marker,
      meta: meta,
      iconAsset: iconAsset ?? this.iconAsset,
      detail: detail ?? this.detail,
    );
  }
}

List<WatchItem> summaryItems(EngineSnapshot snapshot) {
  final learning = snapshot.learning;
  return [
    WatchItem(
      symbol: '레짐',
      title: snapshot.marketBias,
      value: regimeLabel(snapshot.regime),
      change:
          '${displayRegimeScoreLabel(snapshot)} ${displayRegimeScore(snapshot).toStringAsFixed(1)}',
      changePct: modeLabel(snapshot.mode),
      accent: regimeColor(snapshot.regime),
      marker: 'R',
      meta: '현재 판단',
    ),
    WatchItem(
      symbol: '학습',
      title: learningStageLabel(learning.stage),
      value: learningStatusLabel(learning.latestRunStatus),
      change: 'Eval ${learning.evaluationCount}',
      changePct: learningActiveVersionLabel(learning),
      accent: learningColor(learning),
      marker: 'L',
      meta: compactLearningSummary(learning),
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
          value: positionNotionalUsdt(position),
          change: sideLabel(position.side),
          changePct: positionExposurePct(snapshot, position),
          accent: sideColor(position.side),
          marker: firstMarker(position.symbol),
          meta: positionMeta(position),
        ),
      )
      .toList(growable: false);
}

PositionView? positionForWatchItem(EngineSnapshot snapshot, WatchItem item) {
  for (final position in snapshot.positions) {
    if (position.symbol == item.symbol &&
        sideLabel(position.side) == item.title) {
      return position;
    }
  }
  for (final position in snapshot.positions) {
    if (position.symbol == item.symbol) {
      return position;
    }
  }
  return null;
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
  final hiddenSymbols = {'REGIME', 'EQUITY', 'RISK', 'LEVERAGE', 'LEARNING'};
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
  final learning = snapshot.learning;
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
      symbol: '학습',
      title: 'Claude 평가와 파라미터 조정',
      value: learningStatusLabel(learning.latestRunStatus),
      change: 'Eval ${learning.evaluationCount}',
      changePct: learningActiveVersionLabel(learning),
      accent: learningColor(learning),
      marker: 'L',
      meta: compactLearningSummary(learning),
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
          value: positionNotionalUsdt(position),
          change: sideLabel(position.side),
          changePct: positionExposurePct(snapshot, position),
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

List<WatchItem> consoleItems(
  EngineSnapshot snapshot, {
  bool includeRebalance = true,
}) {
  final items = <WatchItem>[];
  final rebalance = snapshot.paperRebalance;
  if (rebalance != null && includeRebalance) {
    items.add(rebalanceLogItem(rebalance));
  }

  items.addAll(
    snapshot.events
        .where((event) =>
            rebalance == null || !isSameRebalanceEvent(event, rebalance))
        .map(
          (event) => WatchItem(
            symbol: eventKindLabel(event.kind),
            title: eventLogSummary(event),
            value: event.time,
            change: eventKindLabel(event.kind),
            changePct: eventLogHint(event),
            accent: eventColor(event.kind),
            marker: eventMarker(event.kind),
            meta: event.kind,
            detail: event.message,
          ),
        ),
  );

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
        detail: '아직 수신된 이벤트가 없습니다.',
      ),
    );
  }

  return items;
}

WatchItem rebalanceLogItem(PaperRebalanceView rebalance) {
  final label = rebalanceEventLabel(rebalance.eventKind);
  final composition = rebalance.positionCountBefore > 0 ||
          rebalance.positionCountAfter > 0
      ? ' · ${rebalance.positionCountBefore}→${rebalance.positionCountAfter}종목'
      : '';
  final detail =
      '${regimeLabel(rebalance.regime)} ${compactUsdt(rebalance.fromExposure)} → ${compactUsdt(rebalance.toExposure)}$composition · ${symbolsPreview(rebalance.changedSymbols)}';
  return WatchItem(
    symbol: eventKindLabel(rebalance.eventKind),
    title: paperRebalanceLogSummary(rebalance),
    value: rebalance.time,
    change: label,
    changePct: paperRebalanceLogHint(rebalance),
    accent: eventColor(rebalance.eventKind),
    marker: eventMarker(rebalance.eventKind),
    meta: rebalance.signalId,
    detail: detail,
  );
}

String rebalanceFlowTitle(PaperRebalanceView rebalance) {
  final reduced =
      rebalance.reducedSymbols.length + rebalance.closedSymbols.length;
  final added =
      rebalance.openedSymbols.length + rebalance.increasedSymbols.length;
  if (reduced > 0 && added > 0) {
    return '$reduced개 줄이고 $added개 담았어요';
  }
  if (reduced > 0) {
    return '$reduced개 포지션을 줄였어요';
  }
  if (added > 0) {
    return '$added개 포지션을 담았어요';
  }
  return paperRebalanceLogSummary(rebalance);
}

String reduceFlowLabel(PaperRebalanceView rebalance) {
  if (rebalance.closedSymbols.isNotEmpty && rebalance.reducedSymbols.isEmpty) {
    return '청산';
  }
  return '축소';
}

String addFlowLabel(PaperRebalanceView rebalance) {
  if (rebalance.increasedSymbols.isNotEmpty &&
      rebalance.openedSymbols.isEmpty) {
    return '증액';
  }
  return '매수';
}

String holdFlowLabel(PaperRebalanceView rebalance) {
  if (rebalance.eventKind == 'PAPER_EXIT') return '현금화';
  if (rebalance.reducedSymbols.isNotEmpty ||
      rebalance.closedSymbols.isNotEmpty) {
    return '남은 포지션';
  }
  return '유지';
}

IconData flowArrowIcon(PaperRebalanceView rebalance) {
  if (rebalance.openedSymbols.isNotEmpty ||
      rebalance.increasedSymbols.isNotEmpty) {
    return PhosphorIconsRegular.arrowRight;
  }
  if (rebalance.closedSymbols.isNotEmpty) {
    return PhosphorIconsRegular.arrowCircleDownRight;
  }
  if (rebalance.reducedSymbols.isNotEmpty) {
    return PhosphorIconsRegular.arrowBendDownRight;
  }
  return PhosphorIconsRegular.equals;
}

String symbolsFlowSentence(PaperRebalanceView rebalance) {
  final reduced = rebalance.reducedSymbols.isNotEmpty
      ? rebalance.reducedSymbols
      : rebalance.closedSymbols;
  final added = rebalance.openedSymbols.isNotEmpty
      ? rebalance.openedSymbols
      : rebalance.increasedSymbols;

  if (reduced.isNotEmpty && added.isNotEmpty) {
    return '${symbolsPreview(reduced)} 줄이고 ${symbolsPreview(added)} 담음';
  }
  if (reduced.isNotEmpty) {
    return '${symbolsPreview(reduced)} ${reduceFlowLabel(rebalance)}';
  }
  if (added.isNotEmpty) {
    return '${symbolsPreview(added)} ${addFlowLabel(rebalance)}';
  }
  return symbolsPreview(rebalance.changedSymbols);
}

String paperRebalanceLogSummary(PaperRebalanceView rebalance) {
  return switch (rebalance.eventKind) {
    'PAPER_ENTRY' => '페이퍼 진입 완료',
    'PAPER_REBALANCE' => '페이퍼 리밸런싱 완료',
    'PAPER_EXIT' => '페이퍼 청산 완료',
    'PAPER_HOLD' => '페이퍼 포지션 유지',
    _ => '페이퍼 상태 갱신',
  };
}

String paperRebalanceLogHint(PaperRebalanceView rebalance) {
  final parts = <String>[
    regimeLabel(rebalance.regime),
    if (rebalance.orderCount > 0) '주문 ${rebalance.orderCount}개',
    if (rebalance.positionCountBefore > 0 || rebalance.positionCountAfter > 0)
      '${rebalance.positionCountBefore}→${rebalance.positionCountAfter}종목',
  ];
  return parts.join(' · ');
}

String eventLogSummary(EventView event) {
  final kind = event.kind.toUpperCase();
  final message = event.message.trim();
  final lower = message.toLowerCase();

  return switch (kind) {
    'ALERT' => message.contains('웹훅') ? '트레이딩뷰 웹훅 수신' : '트레이딩뷰 알림 수신',
    'DECISION' => decisionEventSummary(message),
    'PAPER_ENTRY' => lower.startsWith('increase') ? '페이퍼 포지션 증액' : '페이퍼 진입 완료',
    'PAPER_REBALANCE' =>
      lower.startsWith('reduce') || lower.startsWith('increase')
          ? '페이퍼 포지션 조정'
          : '페이퍼 리밸런싱 완료',
    'PAPER_EXIT' => '페이퍼 청산 완료',
    'PAPER_ORDER' => '페이퍼 주문 생성',
    'PAPER_HOLD' => '페이퍼 포지션 유지',
    'PAPER' => '페이퍼 상태 갱신',
    'SECRET' => '시크릿 동기화 완료',
    'WORKER' => lower.contains('deploy') || message.contains('배포')
        ? '워커 배포 완료'
        : '워커 상태 확인',
    'ERROR' => '오류 확인 필요',
    'BINANCE' => '바이낸스 연결 확인',
    'CONFIG' => '설정 확인 필요',
    'INTERNALS' => '시장 내부 지표 갱신',
    'UNIVERSE' => '거래 후보군 갱신',
    'ORDERS' => lower.contains('no order') ? '추가 주문 없음' : '예정 주문 생성',
    'LIVE' => '실거래 실행 모드',
    'DRYRUN' => '드라이런 실행 모드',
    _ => compactKoreanLogMessage(message),
  };
}

String decisionEventSummary(String message) {
  final lower = message.toLowerCase();
  if (message.contains('관망') || lower.contains('neutral')) {
    return '엔진 관망 유지';
  }
  if (lower.contains('risk stop') || message.contains('리스크')) {
    return '리스크 가드 작동';
  }
  if (lower.contains('chaotic')) {
    return '혼조장 진입 차단';
  }
  if (lower.contains('deposit')) {
    return '입금 리밸런싱 대기';
  }
  if (lower.contains('preliminary bear')) {
    return '예비 약세 신호 확인';
  }
  if (lower.contains('preliminary bull')) {
    return '예비 강세 신호 확인';
  }
  if (lower.contains('rebalance')) {
    return '리밸런싱 조건 확인';
  }
  return '엔진 판단 갱신';
}

String eventLogHint(EventView event) {
  return switch (event.kind.toUpperCase()) {
    'ALERT' => '신호',
    'DECISION' => '엔진',
    'PAPER_ENTRY' ||
    'PAPER_REBALANCE' ||
    'PAPER_EXIT' ||
    'PAPER_ORDER' ||
    'PAPER_HOLD' ||
    'PAPER' =>
      '페이퍼',
    'SECRET' => '보안',
    'WORKER' => 'Cloudflare',
    'ERROR' => '확인 필요',
    'BINANCE' => '거래소',
    'CONFIG' => '환경',
    'INTERNALS' => '마켓',
    'UNIVERSE' => '후보군',
    'ORDERS' => '주문',
    'LIVE' => '실거래',
    'DRYRUN' => '모의',
    _ => eventDayLabel(event.time),
  };
}

String compactKoreanLogMessage(String message) {
  final text = message.trim();
  if (text.isEmpty || text == '-') return '이벤트 수신';
  final translated = text
      .replaceAll('TradingView', '트레이딩뷰')
      .replaceAll('Binance', '바이낸스')
      .replaceAll('accepted', '수락')
      .replaceAll('failed', '실패')
      .replaceAll('loaded', '로드')
      .replaceAll('generated', '생성')
      .replaceAll('enabled', '활성화');
  if (translated.characters.length <= 28) return translated;
  return '${translated.characters.take(28).join()}...';
}

bool isSameRebalanceEvent(EventView event, PaperRebalanceView rebalance) {
  return event.kind == rebalance.eventKind &&
      event.time == rebalance.time &&
      event.message.contains('->');
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
        value: positionNotionalUsdt(position),
        change: sideLabel(position.side),
        changePct: positionExposurePct(snapshot, position),
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

String logSubtitle(EngineSnapshot snapshot) {
  if (snapshot.events.isEmpty) {
    return '최근 이벤트 없음';
  }
  return '최근 ${eventMinuteLabel(snapshot.events.first.time)} 수신';
}

int flowActiveIndex(EngineSnapshot snapshot) {
  if (snapshot.orders.isNotEmpty) return 2;
  if (snapshot.positions.isNotEmpty) return 3;
  if (snapshot.events.isNotEmpty) return 4;
  if (snapshot.tradingViewSignal != null) return 1;
  return 0;
}

String statusFreshnessLabel(EngineSnapshot snapshot) {
  final paperTime = snapshot.paperAccount?.lastUpdated ?? '';
  if (paperTime.isNotEmpty) {
    return '페이퍼 ${eventMinuteLabel(paperTime)} 갱신 · ${sourceLabel(snapshot.source)}';
  }
  return '${sourceLabel(snapshot.source)} · ${eventMinuteLabel(snapshot.lastUpdated)} 갱신';
}

String signalActionLabel(TradingViewSignal? signal) {
  if (signal == null) return '대기';
  final action = (signal.decisionAction ?? '').toUpperCase();
  if (action == 'ENTER') return '진입';
  if (action == 'EXIT') return '청산';
  if (action == 'HOLD') return '유지';
  return signal.targetLeverage > 0 ? '진입' : '관망';
}

String signalSourceLabel(TradingViewSignal? signal) {
  if (signal == null) return '신호 대기';
  final source = signal.source.toLowerCase();
  if (source == 'internal_engine') return '내부 엔진 신호';
  if (source == 'tradingview') return 'TradingView 신호';
  if (signal.timeframe == 'internal') return '내부 엔진 신호';
  return source.isEmpty ? 'TradingView 신호' : signal.source;
}

String signalReasonSummary(TradingViewSignal? signal) {
  if (signal == null) return '-';
  final reason = signal.decisionReason?.trim() ?? '';
  if (reason.isNotEmpty) return compactText(reason, 34);
  return '${signal.timeframe} · ${signal.signalId}';
}

String compactText(String text, int limit) {
  if (text.characters.length <= limit) return text;
  return '${text.characters.take(limit).join()}...';
}

Color pnlColor(double value) {
  if (value > 0) return const Color(0xFF2F8F75);
  if (value < 0) return const Color(0xFFC8404A);
  return const Color(0xFF787B86);
}

double displayRegimeScore(EngineSnapshot snapshot) {
  final signal = snapshot.tradingViewSignal;
  if (signal == null) return snapshot.regimeScore;
  if (signal.score != null) return signal.score!;

  var score = 0.0;
  score += boolPairScore(signal.btcUp, signal.btcDown, 40.0);
  score += boolPairScore(signal.totalUp, signal.totalDown, 25.0);
  score += boolPairScore(signal.total2Up, signal.total2Down, 25.0);
  if (signal.btcdDown) {
    score += 10.0;
  } else if (signal.btcdUp) {
    score -= 10.0;
  }
  return score;
}

String displayRegimeScoreLabel(EngineSnapshot snapshot) {
  return snapshot.tradingViewSignal == null ? '점수' : 'TV점수';
}

double boolPairScore(bool up, bool down, double weight) {
  if (up && !down) return weight;
  if (down && !up) return -weight;
  return 0.0;
}

String eventMinuteLabel(Object? raw) {
  final dateTime = parseEventDateTime(raw);
  if (dateTime != null) {
    return '${twoDigits(dateTime.hour)}:${twoDigits(dateTime.minute)}';
  }

  final text = raw?.toString() ?? '-';
  final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
  if (match != null) {
    return '${match.group(1)!.padLeft(2, '0')}:${match.group(2)}';
  }
  return text.length <= 5 ? text : text.substring(0, 5);
}

String eventDayLabel(Object? raw) {
  final dateTime = parseEventDateTime(raw);
  if (dateTime == null) return '';
  final now = DateTime.now();
  if (dateTime.year == now.year &&
      dateTime.month == now.month &&
      dateTime.day == now.day) {
    return '오늘';
  }
  return '${twoDigits(dateTime.month)}/${twoDigits(dateTime.day)}';
}

DateTime? parseEventDateTime(Object? raw) {
  if (raw == null) return null;
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
  }
  if (raw is num) {
    return DateTime.fromMillisecondsSinceEpoch(raw.toInt()).toLocal();
  }

  final text = raw.toString().trim();
  if (text.isEmpty || text == '-') return null;
  final millis = int.tryParse(text);
  if (millis != null && text.length >= 12) {
    return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  }
  return DateTime.tryParse(text)?.toLocal();
}

String twoDigits(int value) => value.toString().padLeft(2, '0');

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

String learningStageLabel(String stage) {
  return switch (stage.toUpperCase()) {
    'BABY' => 'BABY 단계',
    'JUNIOR' => 'JUNIOR 단계',
    'SENIOR' => 'SENIOR 단계',
    _ => stage.isEmpty ? 'BABY 단계' : stage,
  };
}

String learningStatusLabel(String status) {
  final normalized = status.toLowerCase();
  return switch (normalized) {
    '' => '대기',
    'ok' => '정상',
    'diagnosis_failed' => '진단 실패',
    'failed' || 'error' => '오류',
    'running' => '실행중',
    _ => status,
  };
}

String learningActiveVersionLabel(LearningView learning) {
  final version = learning.activeParamVersion;
  return version == null ? 'v-' : 'v$version';
}

String learningRunMeta(LearningView learning) {
  final parts = <String>[];
  if (learning.latestRunTime.isNotEmpty) {
    parts.add(eventMinuteLabel(learning.latestRunTime));
  }
  if (learning.latestRunTrigger.isNotEmpty) {
    parts.add(learning.latestRunTrigger);
  }
  return parts.isEmpty ? '대기' : parts.join(' · ');
}

String learningParamSummary(LearningView learning) {
  final parts = <String>[];
  final rangeTarget = learning.rangeTargetLeverage;
  if (rangeTarget != null) {
    parts.add('range ${rangeTarget.toStringAsFixed(2)}x');
  }
  final confirmation = learning.confirmationCandles;
  if (confirmation != null) {
    parts.add('confirm $confirmation');
  }
  final neutralHours = learning.minNeutralHours;
  if (neutralHours != null) {
    parts.add('neutral ${neutralHours.toStringAsFixed(0)}h');
  }
  return parts.isEmpty ? '파라미터 대기' : parts.join(' · ');
}

String compactLearningSummary(LearningView learning) {
  final text = learning.latestEvaluationSummary.trim();
  if (text.isEmpty) {
    return learning.evaluationCount == 0
        ? '평가 대기'
        : '평가 ${learning.evaluationCount}회';
  }
  if (text.characters.length <= 28) return text;
  return '${text.characters.take(28).join()}...';
}

Color learningColor(LearningView learning) {
  final status = learning.latestRunStatus.toLowerCase();
  if (status == 'ok') return const Color(0xFF2F8F75);
  if (status.contains('fail') || status.contains('error')) {
    return const Color(0xFFC8404A);
  }
  if (status.isEmpty) return const Color(0xFF787B86);
  return const Color(0xFFC08A17);
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

bool logItemOpensEngineResult(WatchItem item) {
  return {
    eventKindLabel('ALERT'),
    eventKindLabel('PAPER_ENTRY'),
    eventKindLabel('PAPER_REBALANCE'),
    eventKindLabel('PAPER_EXIT'),
  }.contains(item.symbol);
}

String rebalanceEventLabel(String kind) {
  return switch (kind) {
    'PAPER_ENTRY' => '진입',
    'PAPER_REBALANCE' => '리밸런싱',
    'PAPER_EXIT' => '청산',
    'PAPER_HOLD' => '유지',
    _ => '페이퍼',
  };
}

String eventKindLabel(String kind) {
  return switch (kind) {
    'ALERT' => '알림',
    'DECISION' => '판단',
    'PAPER_ENTRY' => '진입',
    'PAPER_REBALANCE' => '리밸런싱',
    'PAPER_EXIT' => '청산',
    'PAPER_ORDER' => '주문',
    'PAPER_HOLD' => '유지',
    'PAPER' => '페이퍼',
    'SECRET' => '시크릿',
    'WORKER' => '워커',
    'ERROR' => '오류',
    'BINANCE' => '바이낸스',
    'CONFIG' => '설정',
    'INTERNALS' => '시장',
    'UNIVERSE' => '후보군',
    'ORDERS' => '주문',
    'LIVE' => '실거래',
    'DRYRUN' => '모의',
    _ => kind,
  };
}

Color eventColor(String kind) {
  return switch (kind) {
    'ERROR' => const Color(0xFFC8404A),
    'CONFIG' => const Color(0xFFC08A17),
    'PAPER_ENTRY' => const Color(0xFF2F8F75),
    'PAPER_REBALANCE' => const Color(0xFF2563EB),
    'PAPER_EXIT' => const Color(0xFFC8404A),
    'PAPER_ORDER' => const Color(0xFFC08A17),
    'PAPER_HOLD' => const Color(0xFF787B86),
    'ORDERS' => const Color(0xFFC08A17),
    'BINANCE' => const Color(0xFFF0B90B),
    'INTERNALS' || 'UNIVERSE' => const Color(0xFF2563EB),
    'LIVE' => const Color(0xFFC8404A),
    'DRYRUN' => const Color(0xFF787B86),
    'SECRET' || 'ALERT' || 'WORKER' => const Color(0xFF2F8F75),
    'DECISION' => const Color(0xFF2563EB),
    _ => const Color(0xFF787B86),
  };
}

String eventMarker(String kind) {
  if (kind == 'PAPER_ENTRY') return '+';
  if (kind == 'PAPER_REBALANCE') return 'R';
  if (kind == 'PAPER_EXIT') return '-';
  return firstMarker(kind);
}

String? iconAssetForWatchItem(WatchItem item) {
  final direct = item.iconAsset;
  if (direct != null && direct.isNotEmpty) return direct;
  return iconAssetForSymbol(item.symbol);
}

String? iconAssetForSymbol(String symbol) {
  final raw = symbol.trim();
  final upper = raw.toUpperCase();
  final compact = upper.replaceAll(RegExp(r'[^A-Z0-9]'), '');

  if (upper == 'PAPER.PNL' ||
      compact == 'PAPERPNL' ||
      (compact.contains('PAPER') && compact.contains('PNL'))) {
    return _iconAssets['APP_LOGO'];
  }
  if (upper == 'TV.SIGNAL' ||
      compact == 'TVSIGNAL' ||
      compact == 'TRADINGVIEWSIGNAL' ||
      raw.contains('알림') ||
      upper.contains('TRADINGVIEW')) {
    return _iconAssets['TRADINGVIEW'];
  }
  if (raw.contains('바이낸스') || upper.contains('BINANCE')) {
    return _iconAssets['BINANCE'];
  }
  if (upper == 'INTERNALS') {
    return _iconAssets['BINANCE'];
  }
  if (raw.contains('시장') ||
      upper.contains('STABLE.D') ||
      upper.contains('TOP10.D') ||
      upper.contains('TOTAL')) {
    return _iconAssets['MARKET'];
  }

  final base = baseCryptoSymbol(raw);
  final exact = _iconAssets[base];
  if (exact != null) return exact;
  if (!looksLikeCryptoMarketSymbol(upper)) return null;

  return 'icons/$base.svg';
}

String fallbackIconAssetForWatchItem(WatchItem item) {
  return fallbackIconAssetForSymbol(item.symbol);
}

String fallbackIconAssetForSymbol(String symbol) {
  final base = baseCryptoSymbol(symbol);
  var hash = 0;
  for (final codeUnit in base.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return _fallbackCryptoIcons[hash % _fallbackCryptoIcons.length];
}

String baseCryptoSymbol(String value) {
  var symbol = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9.]'), '');
  for (final suffix in const ['USDT', 'USDC', 'BUSD', 'USD', 'PERP']) {
    if (symbol.endsWith(suffix) && symbol.length > suffix.length) {
      symbol = symbol.substring(0, symbol.length - suffix.length);
      break;
    }
  }
  if (symbol.startsWith('1000') && symbol.length > 4) {
    symbol = symbol.substring(4);
  }
  return symbol;
}

bool looksLikeCryptoMarketSymbol(String symbol) {
  final clean = symbol.replaceAll(RegExp(r'[^A-Z0-9.]'), '');
  return clean.endsWith('USDT') ||
      clean.endsWith('USDC') ||
      clean.endsWith('BUSD') ||
      clean.endsWith('PERP');
}

IconData watchIcon(String symbol) {
  final s = symbol;
  if (s.contains('레짐')) return PhosphorIconsRegular.compass;
  if (s.contains('자산')) return PhosphorIconsRegular.wallet;
  if (s.contains('레버리지')) return PhosphorIconsRegular.gauge;
  if (s.contains('리스크')) return PhosphorIconsRegular.shieldWarning;
  if (s.contains('플랫')) return PhosphorIconsRegular.minus;
  if (s.contains('주문')) return PhosphorIconsRegular.receipt;
  if (s.contains('목표')) return PhosphorIconsRegular.target;
  if (s.contains('학습')) return PhosphorIconsRegular.brain;
  if (s.contains('진입')) return PhosphorIconsRegular.arrowCircleUpRight;
  if (s.contains('리밸런싱')) return PhosphorIconsRegular.arrowsLeftRight;
  if (s.contains('청산')) return PhosphorIconsRegular.arrowCircleDownRight;
  if (s.contains('유지')) return PhosphorIconsRegular.pauseCircle;
  if (s.contains('페이퍼')) return PhosphorIconsRegular.notepad;
  if (s.contains('시장') || s.contains('콘솔')) {
    return PhosphorIconsRegular.chartLineUp;
  }
  if (s.contains('동작') || s.contains('앱')) {
    return PhosphorIconsRegular.deviceMobile;
  }
  if (s.contains('웹훅')) return PhosphorIconsRegular.link;
  if (s.contains('신호')) return PhosphorIconsRegular.broadcast;
  if (s.contains('엔진')) return PhosphorIconsRegular.cpu;
  if (s.contains('실거래') || s.contains('바이낸스')) {
    return PhosphorIconsRegular.currencyBtc;
  }
  if (s.contains('일간') || s.contains('주간') || s.contains('월간')) {
    return PhosphorIconsRegular.calendarBlank;
  }
  if (s.contains('쿨다운') || s.contains('대기')) {
    return PhosphorIconsRegular.timer;
  }
  if (s.contains('알림')) return PhosphorIconsRegular.bell;
  if (s.contains('판단')) return PhosphorIconsRegular.brain;
  if (s.contains('시크릿')) return PhosphorIconsRegular.key;
  if (s.contains('워커')) return PhosphorIconsRegular.cloud;
  if (s.contains('오류')) return PhosphorIconsRegular.warning;
  if (s.contains('설정')) return PhosphorIconsRegular.gearSix;
  if (s.contains('후보군')) return PhosphorIconsRegular.stack;
  if (s.contains('모의')) return PhosphorIconsRegular.flask;
  if (s.contains('USDT') || s.contains('BTC') || s.contains('ETH')) {
    return PhosphorIconsRegular.currencyBtc;
  }
  return PhosphorIconsRegular.circlesThree;
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

List<String> stringListOf(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((item) => item.toString()).toList(growable: false);
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

String fmtNullablePrice(double? value) {
  if (value == null || value == 0) return '-';
  final absolute = value.abs();
  if (absolute >= 1000) return value.toStringAsFixed(2);
  if (absolute >= 1) return value.toStringAsFixed(4);
  return value.toStringAsFixed(6);
}

String fmtNullableQuantity(double? value) {
  if (value == null || value == 0) return '-';
  final absolute = value.abs();
  if (absolute >= 100) return value.toStringAsFixed(2);
  if (absolute >= 1) return value.toStringAsFixed(4);
  return value.toStringAsFixed(6);
}

String fmtNullableLeverage(double? value) {
  if (value == null || value == 0) return '-';
  return '${value.toStringAsFixed(2)}x';
}

String fmtNullableSignedUsdt(double? value) {
  if (value == null) return '-';
  return '${value >= 0 ? '+' : '-'}${compactUsdt(value.abs())}';
}

String positionPnlPct(PositionView position) {
  final pnl = position.unrealizedPnl;
  if (pnl == null || position.notional == 0) return '-';
  return pct(pnl / position.notional * 100);
}

String positionExposurePct(EngineSnapshot snapshot, PositionView position) {
  if (snapshot.equity <= 0 || position.notional == 0) return '0.00%';
  return '${(position.notional / snapshot.equity * 100).toStringAsFixed(2)}%';
}

String positionNotionalUsdt(PositionView position) =>
    '${compactUsdt(position.notional)} USDT';

String positionMeta(PositionView position) {
  final parts = <String>[];
  if (position.entryPrice != null) {
    parts.add('진입 ${fmtNullablePrice(position.entryPrice)}');
  }
  if (position.unrealizedPnl != null) {
    parts.add('PnL ${fmtNullableSignedUsdt(position.unrealizedPnl)}');
  }
  if (parts.isEmpty) return '바이낸스 현재 포지션';
  return parts.join(' · ');
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

String symbolsPreview(List<String> symbols, {int limit = 4}) {
  if (symbols.isEmpty) return '-';
  final visible = symbols.take(limit).join(', ');
  final hidden = symbols.length - limit;
  return hidden > 0 ? '$visible 외 $hidden' : visible;
}

String pct(double value) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}%';

Color regimeColor(String regime) {
  return switch (regime) {
    'BULL' || 'TOP10_LONG' || 'BTC_ETH_LONG' => const Color(0xFF2F8F75),
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
