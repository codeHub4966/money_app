import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/app_category.dart';
import '../../../domain/models/transaction.dart' as tx;
import '../../providers/app_providers.dart';
import 'prediction_shared.dart';

const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String _dowLabel(DateTime d) => _dow[d.weekday - 1];
const _good = Color(0xFF0E8C74);
const _bad = AppTheme.error;

// Real-data implementation of the "Insight Page v4" Claude Design import
// (claude.ai/design/p/410665a5-4a2f-4c3a-bd8e-613fb8aefaea). Ported the
// design's forecast/pace/spike-detection logic to run over actual
// transactions instead of its fixture data; a couple of purely-visual
// details (the forecast chip's exact curve-following position, the
// diagonal-hatch "projected" bar texture) are simplified to flat
// approximations rather than pixel-ported.
class InsightsTab extends ConsumerStatefulWidget {
  final DateTime month; // day fixed to 1
  const InsightsTab({super.key, required this.month});

  @override
  ConsumerState<InsightsTab> createState() => _InsightsTabState();
}

class _InsightsTabState extends ConsumerState<InsightsTab> {
  String _trendView = 'daily'; // 'daily' | 'weekly'
  int? _selectedIndex;

  @override
  void didUpdateWidget(covariant InsightsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) _selectedIndex = null;
  }

  void _setTrendView(String v) {
    if (v == _trendView) return;
    setState(() { _trendView = v; _selectedIndex = null; });
  }

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? <tx.Transaction>[];
    final allCats = ref.watch(categoriesProvider);

    final data = _MonthData.compute(transactions, widget.month);
    if (data.spent <= 0) return _buildEmptyState();

    final bars = _trendView == 'daily' ? data.dailyBars() : data.weeklyBars();
    final selIdx = (_selectedIndex != null && _selectedIndex! < bars.length)
        ? _selectedIndex!
        : bars.lastIndexWhere((b) => !b.future).clamp(0, bars.length - 1);
    final sel = bars[selIdx];
    final maxV = bars.map((b) => b.value).fold(0.0, max);
    final avgForView = _trendView == 'daily'
        ? data.avgDay
        : (() {
            final recorded = bars.where((b) => !b.future).toList();
            return recorded.isEmpty ? 0.0 : recorded.map((b) => b.value).reduce((a, b) => a + b) / recorded.length;
          })();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
        if (data.isCurrentMonth) ...[
          _buildForecastCard(data),
          const SizedBox(height: 12),
        ],
        _buildTrendCard(data, bars, sel, selIdx, maxV, avgForView),
        const SizedBox(height: 12),
        _buildStatGrid(data, allCats),
        if (data.momMonths.length >= 2) ...[
          const SizedBox(height: 12),
          _buildMomCard(data),
        ],
        if (data.spikes.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSpikesCard(data, allCats),
        ],
        if (data.smartInsights.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildInsightsCard(data),
        ],
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          'No expenses recorded in ${kMonthNames[widget.month.month - 1]} ${widget.month.year}.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _card({required Widget child, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF00113A).withOpacity(0.05), blurRadius: 14, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  // ─────────────────────────── Forecast hero card ───────────────────────────

  Widget _buildForecastCard(_MonthData data) {
    final fc = data.forecast!;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.6, -1), end: Alignment(0.8, 1),
          colors: [Color(0xFF0C2A6B), Color(0xFF0A1E4F), Color(0xFF0E3A63)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: const Color(0xFF0A1E4F).withOpacity(0.3), blurRadius: 32, offset: const Offset(0, 14))],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.trending_up_rounded, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          const Text('Predicted Month-End Spending',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
        ]),
        const SizedBox(height: 12),
        Text(rm(fc.projected), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, height: 1)),
        const SizedBox(height: 4),
        Text('Projected spending', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: Colors.white.withOpacity(0.82))),
        const SizedBox(height: 6),
        Text('Based on your spending trend so far this month.', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.55))),
        if (fc.momPct != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: fc.flat ? Colors.white.withOpacity(0.16) : (fc.momPct! > 0 ? const Color(0xFFFFE1E4) : const Color(0xFFD6F3EA)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              fc.flat ? 'Flat vs ${rm(fc.prevMonthTotal!)} last month'
                  : '${fc.momPct!.abs().toStringAsFixed(0)}% ${fc.momPct! > 0 ? 'higher' : 'lower'} than last month',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                  color: fc.flat ? Colors.white : (fc.momPct! > 0 ? _bad : _good)),
            ),
          ),
        ],
        const SizedBox(height: 6),
        SizedBox(
          height: 92,
          child: Stack(children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ForecastPainter(cumulative: fc.cumulative, daysInMonth: data.daysInMonth.toDouble(), projTotal: fc.projected),
              ),
            ),
            Positioned(
              left: (fc.chipLeftFrac * (MediaQuery.of(context).size.width - 76)).clamp(0, 160).toDouble(),
              top: 4,
              child: _chip('Spent so far', rm(data.spent), light: true),
            ),
            Positioned(right: 0, top: 0, child: _chip('Projected', rm(fc.projected), light: false)),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String label, String value, {required bool light}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: light ? Colors.white.withOpacity(0.14) : Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: light ? Border.all(color: Colors.white.withOpacity(0.22)) : null,
        boxShadow: light ? null : [BoxShadow(color: Colors.black.withOpacity(0.22), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: light ? const Color(0xFFA9C7F5) : const Color(0xFF6B7280))),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: light ? Colors.white : const Color(0xFF0A1E4F))),
      ]),
    );
  }

  // ─────────────────────────── Spending trend card ───────────────────────────

  Widget _buildTrendCard(_MonthData data, List<_Bar> bars, _Bar sel, int selIdx, double maxV, double avgForView) {
    final tag = sel.value >= maxV - 0.001
        ? (_trendView == 'daily' ? 'HIGHEST DAY' : 'HIGHEST WEEK')
        : (sel.value > avgForView ? 'ABOVE AVERAGE' : 'BELOW AVERAGE');
    final tagInk = sel.value > avgForView ? _bad : _good;
    final barMax = max(maxV * 1.15, 1.0);

    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Spending trend', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            _segPill('Daily', 'daily'),
            _segPill('Weekly', 'weekly'),
          ]),
        ),
      ]),
      const SizedBox(height: 16),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(rm(sel.value), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1A1C2E))),
        const SizedBox(width: 8),
        Expanded(child: Text(sel.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant))),
        Text(tag, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: tagInk)),
      ]),
      const SizedBox(height: 14),
      SizedBox(
        height: 118,
        child: Stack(children: [
          Positioned(
            left: 0, right: 0,
            top: 118 - 8 - (avgForView / barMax * 100).clamp(0, 100),
            child: CustomPaint(size: const Size(double.infinity, 1), painter: _DashedHLine()),
          ),
          Positioned.fill(
            bottom: 8,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < bars.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: bars[i].future ? null : () => setState(() => _selectedIndex = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: (bars[i].value / barMax).clamp(0.018, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: bars[i].future
                                  ? const Color(0xFFDFE2EC)
                                  : (bars[i].value >= avgForView * 2 ? _bad : (i == selIdx ? AppTheme.secondary : AppTheme.secondary.withOpacity(0.45))),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (var i = 0; i < bars.length; i++)
          Expanded(
            child: Text(bars[i].axisLabel, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: i == selIdx ? AppTheme.primary : const Color(0xFF9EA3B8))),
          ),
      ]),
    ]));
  }

  Widget _segPill(String label, String value) {
    final active = _trendView == value;
    return GestureDetector(
      onTap: () => _setTrendView(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 4)] : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
            color: active ? AppTheme.primary : AppTheme.onSurfaceVariant)),
      ),
    );
  }

  // ─────────────────────────── Stat grid ───────────────────────────

  Widget _buildStatGrid(_MonthData data, Map<String, List<AppCategory>> allCats) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        _statCard('AVERAGE / DAY', rm(data.avgDay),
            data.prevAvgDaySub ?? 'No data from last month yet.'),
        _paceCard(data),
        _statCard('HIGHEST DAY', rm(data.highestDay),
            '${_dowLabel(DateTime(data.month.year, data.month.month, data.highestDayNum))}, ${data.highestDayNum} ${kMonthNames[data.month.month - 1]} · ${data.avgDay > 0 ? (data.highestDay / data.avgDay).toStringAsFixed(1) : '—'}× your average'),
        _topCategoryCard(data, allCats),
      ],
    );
  }

  Widget _statCard(String label, String value, String sub) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppTheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1A1C2E), height: 1)),
      const SizedBox(height: 6),
      Expanded(child: Text(sub, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant, height: 1.35),
          maxLines: 3, overflow: TextOverflow.ellipsis)),
    ]));
  }

  Widget _paceCard(_MonthData data) {
    if (data.pacePct == null) {
      return _statCard('SPENDING PACE', '—', 'Need 8+ days of data this month.');
    }
    final up = data.pacePct! >= 0;
    final ink = up ? _bad : _good;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('SPENDING PACE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppTheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Row(children: [
        Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: ink),
        const SizedBox(width: 5),
        Text('${up ? '+' : '−'}${data.pacePct!.abs().toStringAsFixed(0)}%', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: ink, height: 1)),
      ]),
      const SizedBox(height: 6),
      Expanded(child: Text('${rm(data.paceNow!)}/day now vs ${rm(data.paceBefore!)}/day before',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant, height: 1.35),
          maxLines: 3, overflow: TextOverflow.ellipsis)),
    ]));
  }

  Widget _topCategoryCard(_MonthData data, Map<String, List<AppCategory>> allCats) {
    final top = data.topCategory!;
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('TOP CATEGORY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: AppTheme.onSurfaceVariant)),
      const SizedBox(height: 6),
      Row(children: [
        Text(categoryEmoji(allCats, top.label), style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 7),
        Expanded(child: Text(top.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1A1C2E)),
            maxLines: 1, overflow: TextOverflow.ellipsis)),
      ]),
      const SizedBox(height: 9),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(value: top.pct / 100, minHeight: 5, backgroundColor: const Color(0xFFEDEFF6),
            valueColor: AlwaysStoppedAnimation(top.color)),
      ),
      const SizedBox(height: 6),
      Expanded(child: Text('${rm(top.value)} · ${top.pct.round()}% of total spend',
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant, height: 1.35),
          maxLines: 2, overflow: TextOverflow.ellipsis)),
    ]));
  }

  // ─────────────────────────── vs last month card ───────────────────────────

  Widget _buildMomCard(_MonthData data) {
    final maxTotal = data.momMonths.map((m) => m.displayTotal).fold(1.0, max);
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        const Text('vs last month', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        const Spacer(),
        Text('${data.momPct! >= 0 ? '+' : '−'}${data.momPct!.abs().toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: data.momPct! >= 0 ? _bad : _good)),
      ]),
      const SizedBox(height: 6),
      Text('${rm(data.spent)} by day ${data.daysElapsed} against ${rm(data.prevAtSamePoint!)} at the same point in ${kMonthNames[data.momMonths[1].month.month - 1]}.',
          style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant, height: 1.5)),
      const SizedBox(height: 16),
      const Text('LAST MONTHS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppTheme.onSurfaceVariant)),
      const SizedBox(height: 11),
      for (final m in data.momMonths) Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Row(children: [
          SizedBox(width: 30, child: Text(kMonthNames[m.month.month - 1].toUpperCase(),
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: m.isCurrent ? AppTheme.primary : const Color(0xFF9EA3B8)))),
          Expanded(
            child: SizedBox(height: 14, child: Row(children: [
              Expanded(flex: max((m.recorded / maxTotal * 1000).round(), 1),
                  child: Container(decoration: BoxDecoration(color: m.isCurrent ? AppTheme.secondary : const Color(0xFFB9C6E8), borderRadius: BorderRadius.circular(4)))),
              if (m.projectedExtra > 0)
                Expanded(flex: max((m.projectedExtra / maxTotal * 1000).round(), 1),
                    child: Container(margin: const EdgeInsets.only(left: 2), decoration: BoxDecoration(color: const Color(0xFF93C5FD), borderRadius: BorderRadius.circular(4)))),
              if (m.recorded + m.projectedExtra < maxTotal) Expanded(flex: max(((maxTotal - m.recorded - m.projectedExtra) / maxTotal * 1000).round(), 0), child: const SizedBox()),
            ])),
          ),
          SizedBox(width: 58, child: Text(rm(m.displayTotal), textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: m.isCurrent ? AppTheme.primary : AppTheme.onSurfaceVariant))),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        _legendDot(AppTheme.secondary, 'Recorded'),
        const SizedBox(width: 14),
        _legendDot(const Color(0xFF93C5FD), 'Projected'),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Container(
          padding: const EdgeInsets.only(top: 12),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEDEFF6)))),
          child: Text(
            '${kMonthNames[data.momMonths[1].month.month - 1]} finished at ${rm(data.momMonths[1].displayTotal)}. '
            "You're ${rm((data.spent - data.prevAtSamePoint!).abs())} ${data.spent >= data.prevAtSamePoint! ? 'ahead of' : 'behind'} that run rate.",
            style: const TextStyle(fontSize: 10, color: AppTheme.onSurfaceVariant, height: 1.5),
          ),
        ),
      ),
    ]));
  }

  Widget _legendDot(Color c, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 8, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppTheme.onSurfaceVariant)),
      ]);

  // ─────────────────────────── Unusual spending days ───────────────────────────

  Widget _buildSpikesCard(_MonthData data, Map<String, List<AppCategory>> allCats) {
    final spikeSum = data.spikes.fold(0.0, (s, r) => s + r.amount);
    return _card(
      color: const Color(0xFF00113A),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 34, height: 34,
              decoration: BoxDecoration(color: _bad, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.priority_high_rounded, color: Colors.white, size: 20)),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${data.spikes.length} unusual spending day${data.spikes.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            Text('${rm(spikeSum)} of ${rm(data.spent)} came from ${data.spikes.length == 1 ? 'this day' : 'these days'}',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF93C5FD))),
          ])),
        ]),
        for (final s in data.spikes) Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.white12))),
          child: Row(children: [
            Container(width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(11)),
                alignment: Alignment.center,
                child: Text(categoryEmoji(allCats, s.topCategory), style: const TextStyle(fontSize: 16))),
            const SizedBox(width: 11),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${_dowLabel(s.date)}, ${s.date.day} ${kMonthNames[s.date.month - 1]}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              Text('Mostly ${s.topCategory.toLowerCase()} · ${rm(s.amount - data.avgDay)} above a usual day',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white60)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(rm(s.amount), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('${(s.amount / data.avgDay).toStringAsFixed(1)}× AVG',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: Color(0xFFFF9C93))),
            ]),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('A day is flagged when it passes twice your ${data.daysElapsed}-day average (${rm(data.avgDay * 2)}). Detected locally, no data leaves the phone.',
              style: const TextStyle(fontSize: 10, color: Colors.white54, height: 1.5)),
        ),
      ]),
    );
  }

  // ─────────────────────────── Smart insights ───────────────────────────

  Widget _buildInsightsCard(_MonthData data) {
    return _card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Smart insights', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        const Spacer(),
        const Text('ON THIS DEVICE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppTheme.onSurfaceVariant)),
      ]),
      for (var i = 0; i < data.smartInsights.length; i++) Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: i == data.smartInsights.length - 1 ? Colors.transparent : const Color(0xFFEDEFF6)))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 5),
              child: Container(width: 8, height: 8, decoration: BoxDecoration(color: data.smartInsights[i].dot, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data.smartInsights[i].text, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1A1C2E), height: 1.45)),
            const SizedBox(height: 4),
            Text(data.smartInsights[i].rule, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF9EA3B8))),
          ])),
        ]),
      ),
    ]));
  }
}

// ─────────────────────────── Data model & computation ───────────────────────────

class _Bar {
  final String label;
  final String axisLabel;
  final double value;
  final bool future;
  const _Bar({required this.label, required this.axisLabel, required this.value, required this.future});
}

class _Forecast {
  final double projected;
  final List<double> cumulative;
  final double? prevMonthTotal;
  final double? momPct;
  final bool flat;
  final double chipLeftFrac;
  const _Forecast({required this.projected, required this.cumulative, this.prevMonthTotal, this.momPct, required this.flat, required this.chipLeftFrac});
}

class _Spike {
  final DateTime date;
  final double amount;
  final String topCategory;
  const _Spike({required this.date, required this.amount, required this.topCategory});
}

class _MomMonth {
  final DateTime month;
  final double recorded;
  final double projectedExtra;
  final bool isCurrent;
  double get displayTotal => recorded + projectedExtra;
  const _MomMonth({required this.month, required this.recorded, required this.projectedExtra, required this.isCurrent});
}

class _TopCategory {
  final String label;
  final double value;
  final double pct;
  final Color color;
  const _TopCategory({required this.label, required this.value, required this.pct, required this.color});
}

class _Insight {
  final Color dot;
  final String text;
  final String rule;
  const _Insight({required this.dot, required this.text, required this.rule});
}

class _MonthData {
  final DateTime month;
  final int daysInMonth;
  final int daysElapsed;
  final bool isCurrentMonth;
  final List<double> dailyFull; // length daysInMonth
  final double spent;
  final double avgDay;
  final int highestDayNum;
  final double highestDay;
  final double? pacePct, paceNow, paceBefore;
  final String? prevAvgDaySub;
  final double? prevAtSamePoint;
  final double? momPct;
  final List<_MomMonth> momMonths; // [this month, prev, prev-1, ...] up to 6, empty if <2
  final List<_Spike> spikes;
  final _TopCategory? topCategory;
  final _Forecast? forecast;
  final List<_Insight> smartInsights;

  const _MonthData({
    required this.month, required this.daysInMonth, required this.daysElapsed, required this.isCurrentMonth,
    required this.dailyFull, required this.spent, required this.avgDay, required this.highestDayNum, required this.highestDay,
    this.pacePct, this.paceNow, this.paceBefore, this.prevAvgDaySub, this.prevAtSamePoint, this.momPct,
    required this.momMonths, required this.spikes, this.topCategory, this.forecast, required this.smartInsights,
  });

  List<_Bar> dailyBars() {
    return [
      for (var d = 1; d <= daysInMonth; d++)
        _Bar(
          label: '${_dowLabel(DateTime(month.year, month.month, d))}, $d ${kMonthNames[month.month - 1]}',
          axisLabel: (d == 1 || d % 5 == 0) ? '$d' : '',
          value: dailyFull[d - 1],
          future: d > daysElapsed,
        ),
    ];
  }

  List<_Bar> weeklyBars() {
    final bars = <_Bar>[];
    var start = 0, idx = 0;
    while (start < daysInMonth) {
      final end = min(start + 7, daysInMonth);
      final v = dailyFull.sublist(start, end).fold(0.0, (s, x) => s + x);
      final future = start >= daysElapsed;
      final partial = start < daysElapsed && end > daysElapsed;
      bars.add(_Bar(
        label: partial ? 'Week ${idx + 1} · in progress' : 'Week ${idx + 1} · ${start + 1}–$end ${kMonthNames[month.month - 1]}',
        axisLabel: 'W${idx + 1}',
        value: v,
        future: future,
      ));
      start = end;
      idx++;
    }
    return bars;
  }

  static double _monthTotalToDay(List<tx.Transaction> all, DateTime monthStart, int upToDay) {
    return all.where((t) =>
        t.type == tx.TransactionType.expense &&
        t.date.year == monthStart.year && t.date.month == monthStart.month &&
        t.date.day <= upToDay &&
        t.category != 'Transfer' && t.category != 'Balance Adjustment')
      .fold(0.0, (s, t) => s + t.amount);
  }

  static bool _monthHasData(List<tx.Transaction> all, DateTime monthStart) {
    return all.any((t) =>
        t.type == tx.TransactionType.expense &&
        t.date.year == monthStart.year && t.date.month == monthStart.month &&
        t.category != 'Transfer' && t.category != 'Balance Adjustment');
  }

  static _MonthData compute(List<tx.Transaction> all, DateTime month) {
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final isCurrentMonth = month.year == now.year && month.month == now.month;
    final daysElapsed = isCurrentMonth ? min(now.day, daysInMonth) : daysInMonth;

    final monthTx = all.where((t) =>
        t.type == tx.TransactionType.expense &&
        t.date.year == month.year && t.date.month == month.month &&
        t.category != 'Transfer' && t.category != 'Balance Adjustment').toList();

    final dailyFull = List<double>.filled(daysInMonth, 0);
    for (final t in monthTx) {
      if (t.date.day >= 1 && t.date.day <= daysInMonth) dailyFull[t.date.day - 1] += t.amount;
    }
    final recorded = dailyFull.sublist(0, daysElapsed);
    final spent = recorded.fold(0.0, (s, v) => s + v);

    if (spent <= 0) {
      return _MonthData(month: month, daysInMonth: daysInMonth, daysElapsed: daysElapsed, isCurrentMonth: isCurrentMonth,
          dailyFull: dailyFull, spent: 0, avgDay: 0, highestDayNum: 1, highestDay: 0,
          momMonths: const [], spikes: const [], smartInsights: const []);
    }

    final avgDay = spent / daysElapsed;

    var hiDay = 1;
    var hiV = 0.0;
    for (var i = 0; i < daysElapsed; i++) {
      if (recorded[i] > hiV) { hiV = recorded[i]; hiDay = i + 1; }
    }

    double? pacePct, paceNow, paceBefore;
    if (daysElapsed >= 8) {
      final recent7 = recorded.sublist(daysElapsed - 7);
      final earlier = recorded.sublist(0, daysElapsed - 7);
      final pn = recent7.fold(0.0, (s, v) => s + v) / 7;
      final pb = earlier.isEmpty ? 0.0 : earlier.fold(0.0, (s, v) => s + v) / earlier.length;
      if (pb > 0) {
        paceNow = pn; paceBefore = pb;
        pacePct = (pn - pb) / pb * 100;
      }
    }

    final prevMonthStart = DateTime(month.year, month.month - 1, 1);
    final prevAtSamePoint = _monthHasData(all, prevMonthStart) ? _monthTotalToDay(all, prevMonthStart, daysElapsed) : null;
    String? prevAvgDaySub;
    double? momPct;
    if (prevAtSamePoint != null && prevAtSamePoint > 0) {
      final prevAvgDay = prevAtSamePoint / daysElapsed;
      final diff = avgDay - prevAvgDay;
      prevAvgDaySub = '${diff >= 0 ? '+' : '−'}${rm(diff.abs(), 2)} vs the same point in ${kMonthNames[prevMonthStart.month - 1]}';
      momPct = (spent - prevAtSamePoint) / prevAtSamePoint * 100;
    }

    // vs-last-month bar list: walk back up to 6 consecutive data-bearing months.
    final momMonths = <_MomMonth>[];
    var cursor = month;
    var cursorFull = _monthTotalToDay(all, month, daysInMonth); // == spent when past-completed
    momMonths.add(_MomMonth(month: month, recorded: spent, projectedExtra: 0, isCurrent: true));
    for (var i = 1; i < 6; i++) {
      cursor = DateTime(cursor.year, cursor.month - 1, 1);
      if (!_monthHasData(all, cursor)) break;
      final cDaysInMonth = DateTime(cursor.year, cursor.month + 1, 0).day;
      cursorFull = _monthTotalToDay(all, cursor, cDaysInMonth);
      momMonths.add(_MomMonth(month: cursor, recorded: cursorFull, projectedExtra: 0, isCurrent: false));
    }
    final prevMonthFullTotal = momMonths.length >= 2 ? momMonths[1].recorded : null;

    // Category totals + top category.
    final catTotals = <String, double>{};
    for (final t in monthTx) {
      if (t.date.day > daysElapsed) continue;
      catTotals[t.category] = (catTotals[t.category] ?? 0) + t.amount;
    }
    final sortedCats = catTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _TopCategory? topCategory;
    if (sortedCats.isNotEmpty) {
      topCategory = _TopCategory(
        label: sortedCats.first.key, value: sortedCats.first.value,
        pct: sortedCats.first.value / spent * 100, color: kCategoryPalette[0],
      );
    }

    // Unusual spending days (>= 2x average).
    final threshold = avgDay * 2;
    final spikes = <_Spike>[];
    for (var i = 0; i < daysElapsed; i++) {
      if (recorded[i] < threshold) continue;
      final day = i + 1;
      final dayTx = monthTx.where((t) => t.date.day == day).toList();
      final byCategory = <String, double>{};
      for (final t in dayTx) { byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount; }
      final topDayCat = byCategory.entries.isEmpty
          ? 'spending'
          : (byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
      spikes.add(_Spike(date: DateTime(month.year, month.month, day), amount: recorded[i], topCategory: topDayCat));
    }
    spikes.sort((a, b) => b.date.compareTo(a.date));

    // Forecast (current month only).
    _Forecast? forecast;
    if (isCurrentMonth && daysElapsed < daysInMonth) {
      final paceWindow = daysElapsed >= 7 ? recorded.sublist(daysElapsed - 7) : recorded;
      final pace = paceWindow.fold(0.0, (s, v) => s + v) / paceWindow.length;
      final projected = spent + pace * (daysInMonth - daysElapsed);
      final cumulative = <double>[0];
      var run = 0.0;
      for (var i = 0; i < daysElapsed; i++) { run += recorded[i]; cumulative.add(run); }
      double? fcMomPct;
      var flat = false;
      if (prevMonthFullTotal != null && prevMonthFullTotal > 0) {
        fcMomPct = (projected - prevMonthFullTotal) / prevMonthFullTotal * 100;
        flat = fcMomPct.abs() < 2;
      }
      forecast = _Forecast(
        projected: projected, cumulative: cumulative, prevMonthTotal: prevMonthFullTotal,
        momPct: fcMomPct, flat: flat, chipLeftFrac: (daysElapsed / daysInMonth).clamp(0.0, 0.7),
      );
    }

    // Smart insights.
    final insights = <_Insight>[];
    if (pacePct != null) {
      final up = pacePct >= 0;
      insights.add(_Insight(
        dot: up ? _bad : _good,
        text: 'Your spending over the last 7 days is ${pacePct.abs().toStringAsFixed(0)}% ${up ? 'higher' : 'lower'} than earlier this month.',
        rule: 'LAST 7 DAYS ${rm(paceNow!)}/DAY VS ${rm(paceBefore!)}/DAY',
      ));
    }
    if (topCategory != null) {
      insights.add(_Insight(
        dot: kCategoryPalette[0],
        text: '${topCategory.label} is your highest spending category this month, at ${topCategory.pct.round()}% of total expenses.',
        rule: '${rm(topCategory.value)} OF ${rm(spent)}',
      ));
    }
    if (spikes.isNotEmpty) {
      final s = spikes.first;
      insights.add(_Insight(
        dot: _bad,
        text: '${_dowLabel(s.date)}, ${s.date.day} ${kMonthNames[s.date.month - 1]} was an unusual day at ${rm(s.amount)}, about ${(s.amount / avgDay).toStringAsFixed(1)}× your normal daily spending.',
        rule: 'ABOVE THE ${rm(threshold)} UNUSUAL-DAY THRESHOLD',
      ));
    }
    if (forecast != null) {
      if (forecast.prevMonthTotal != null) {
        final diff = forecast.projected - forecast.prevMonthTotal!;
        insights.add(_Insight(
          dot: AppTheme.secondary,
          text: forecast.flat
              ? 'At the current pace the month ends near ${rm(forecast.projected)}, about the same as ${kMonthNames[prevMonthStart.month - 1]}.'
              : 'At the current pace the month ends near ${rm(forecast.projected)}, ${rm(diff.abs())} ${diff > 0 ? 'above' : 'below'} what you spent in ${kMonthNames[prevMonthStart.month - 1]}.',
          rule: 'FORECAST FROM $daysElapsed DAYS OF TRANSACTIONS',
        ));
      } else {
        insights.add(_Insight(
          dot: AppTheme.secondary,
          text: 'At the current pace the month ends near ${rm(forecast.projected)}.',
          rule: 'FORECAST FROM $daysElapsed DAYS OF TRANSACTIONS',
        ));
      }
    } else if (!isCurrentMonth && prevMonthFullTotal != null) {
      final diff = spent - prevMonthFullTotal;
      insights.add(_Insight(
        dot: AppTheme.secondary,
        text: 'You spent ${rm(spent)} in ${kMonthNames[month.month - 1]}, ${rm(diff.abs())} ${diff > 0 ? 'more' : 'less'} than ${kMonthNames[prevMonthStart.month - 1]}.',
        rule: '${kMonthNames[month.month - 1].toUpperCase()} VS ${kMonthNames[prevMonthStart.month - 1].toUpperCase()}',
      ));
    }

    return _MonthData(
      month: month, daysInMonth: daysInMonth, daysElapsed: daysElapsed, isCurrentMonth: isCurrentMonth,
      dailyFull: dailyFull, spent: spent, avgDay: avgDay, highestDayNum: hiDay, highestDay: hiV,
      pacePct: pacePct, paceNow: paceNow, paceBefore: paceBefore, prevAvgDaySub: prevAvgDaySub,
      prevAtSamePoint: prevAtSamePoint, momPct: momPct, momMonths: momMonths, spikes: spikes,
      topCategory: topCategory, forecast: forecast, smartInsights: insights,
    );
  }
}

// ─────────────────────────── Painters ───────────────────────────

class _ForecastPainter extends CustomPainter {
  final List<double> cumulative;
  final double daysInMonth;
  final double projTotal;
  const _ForecastPainter({required this.cumulative, required this.daysInMonth, required this.projTotal});

  @override
  void paint(Canvas canvas, Size size) {
    if (projTotal <= 0 || cumulative.length < 2) return;
    const topMargin = 8.0, bottomMargin = 4.0;
    double px(double day) => (day / daysInMonth * size.width).clamp(0, size.width);
    double py(double v) => size.height - bottomMargin - (v / projTotal).clamp(0, 1) * (size.height - topMargin - bottomMargin);

    final points = <Offset>[for (var i = 0; i < cumulative.length; i++) Offset(px(i.toDouble()), py(cumulative[i]))];

    final areaPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) { areaPath.lineTo(p.dx, p.dy); }
    areaPath.lineTo(points.last.dx, size.height);
    areaPath.close();
    canvas.drawPath(areaPath, Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [const Color(0xFF2E7FD4).withOpacity(0.55), const Color(0xFF2E7FD4).withOpacity(0)]).createShader(Offset.zero & size));

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) { linePath.lineTo(p.dx, p.dy); }
    canvas.drawPath(linePath, Paint()
      ..color = Colors.white.withOpacity(0.55)..style = PaintingStyle.stroke..strokeWidth = 2..strokeCap = StrokeCap.round);

    final dotB = Offset(px(daysInMonth), py(projTotal));
    _drawDashed(canvas, points.last, dotB, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.2..strokeCap = StrokeCap.round);

    canvas.drawCircle(points.last, 5, Paint()..color = Colors.white);
    canvas.drawCircle(dotB, 6.5, Paint()..color = const Color(0xFF5B93F5));
    canvas.drawCircle(dotB, 6.5, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2.5);
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dashLen = 6.0, gapLen = 5.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = Offset((b.dx - a.dx) / total, (b.dy - a.dy) / total);
    var drawn = 0.0;
    while (drawn < total) {
      final len = min(dashLen, total - drawn);
      canvas.drawLine(a + dir * drawn, a + dir * (drawn + len), paint);
      drawn += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _ForecastPainter old) =>
      old.cumulative != cumulative || old.daysInMonth != daysInMonth || old.projTotal != projTotal;
}

class _DashedHLine extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF9EA3B8)..strokeWidth = 1.2;
    const dashLen = 4.0, gapLen = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(min(x + dashLen, size.width), 0), paint);
      x += dashLen + gapLen;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedHLine oldDelegate) => false;
}
