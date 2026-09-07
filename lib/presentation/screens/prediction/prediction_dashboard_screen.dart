import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/transaction.dart' as tx;
import '../../../domain/models/wallet.dart' as wl;
import '../../providers/app_providers.dart';
import '../../widgets/settings_icon_button.dart';
import 'insights_tab.dart';
import 'prediction_shared.dart';

// "Charts" screen imported from the Claude Design project
// (claude.ai/design/p/410665a5-4a2f-4c3a-bd8e-613fb8aefaea, "Prediction
// Dashboard.dc.html" -> "Insights Screen.dc.html", screen=charts).
// Filters real Expense/Income transactions, grouped by Category or Account,
// into a donut + list. The date-range picker is fully interactive but (per
// the design's own note) doesn't yet re-filter the totals — it always shows
// the current calendar month, same as the rest of the app's "this month"
// figures — wire that up when a proper query layer exists.
//
// The Insights segment (from "Insight Page v4.dc.html" in the same design
// project) is a separate widget — see insights_tab.dart — dropped in below
// the shared header when that segment is selected.
class PredictionDashboardScreen extends ConsumerStatefulWidget {
  const PredictionDashboardScreen({super.key});

  @override
  ConsumerState<PredictionDashboardScreen> createState() => _PredictionDashboardScreenState();
}

class _Series {
  final String id;
  final String label;
  final String emoji;
  final double value;
  final Color color;
  const _Series({required this.id, required this.label, required this.emoji, required this.value, required this.color});
}

class _PredictionDashboardScreenState extends ConsumerState<PredictionDashboardScreen> {
  static const _donutSize = 280.0;
  static const _ringRadius = 88.0;
  static const _ringStroke = 56.16; // 46.8 * 1.2 (another 20% wider slices)

  String _cType = 'expense'; // 'expense' | 'income'
  String _cGroup = 'category'; // 'category' | 'account'
  final Map<String, String> _selected = {};
  final Map<String, GlobalKey> _rowKeys = {};
  final ScrollController _listScrollController = ScrollController();

  @override
  void dispose() {
    _listScrollController.dispose();
    super.dispose();
  }

  String _rangeMode = 'month'; // 'month' | 'week' | 'custom'
  late int _rangeYear = DateTime.now().year;
  late int _rangeMonth = DateTime.now().month - 1; // 0-based
  late DateTime _weekStart = _startOfWeek(DateTime.now());
  late DateTime _customFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  late DateTime _customTo = DateTime.now();

  static DateTime _startOfWeek(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  // Insights is always month-granularity, independent of the Expenses/Income
  // range picker's mode (week/custom don't apply to it).
  late DateTime _insightsMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool get _canStepInsightsForward {
    final now = DateTime.now();
    return _insightsMonth.year < now.year || (_insightsMonth.year == now.year && _insightsMonth.month < now.month);
  }

  void _stepInsightsMonth(int dir) {
    if (dir > 0 && !_canStepInsightsForward) return;
    setState(() => _insightsMonth = DateTime(_insightsMonth.year, _insightsMonth.month + dir, 1));
  }

  String get _selectionKey => '$_cType-$_cGroup';

  String _fmtDay(DateTime d) => '${d.day} ${kMonthNames[d.month - 1]}';

  String get _rangeLabel {
    if (_rangeMode == 'month') return '${kMonthNames[_rangeMonth]} $_rangeYear';
    if (_rangeMode == 'week') {
      final end = _weekStart.add(const Duration(days: 6));
      if (end.month == _weekStart.month) {
        return '${_weekStart.day}–${end.day} ${kMonthNames[end.month - 1]}';
      }
      return '${_fmtDay(_weekStart)} – ${_fmtDay(end)}';
    }
    return '${_fmtDay(_customFrom)} – ${_fmtDay(_customTo)}';
  }

  void _step(int dir) {
    setState(() {
      if (_rangeMode == 'month') {
        var m = _rangeMonth + dir;
        var y = _rangeYear;
        if (m < 0) { m = 11; y -= 1; }
        if (m > 11) { m = 0; y += 1; }
        _rangeMonth = m;
        _rangeYear = y;
      } else if (_rangeMode == 'week') {
        _weekStart = _weekStart.add(Duration(days: dir * 7));
      } else {
        final span = _customTo.difference(_customFrom).inDays + 1;
        _customFrom = _customFrom.add(Duration(days: dir * span));
        _customTo = _customTo.add(Duration(days: dir * span));
      }
    });
  }

  (DateTime, DateTime) _effectiveRange() {
    if (_rangeMode == 'month') {
      final start = DateTime(_rangeYear, _rangeMonth + 1, 1);
      final end = DateTime(_rangeYear, _rangeMonth + 2, 1).subtract(const Duration(days: 1));
      return (start, end);
    }
    if (_rangeMode == 'week') {
      return (_weekStart, _weekStart.add(const Duration(days: 6)));
    }
    return (_customFrom, _customTo);
  }

  bool _inRange(DateTime d) {
    final (start, end) = _effectiveRange();
    final day = DateTime(d.year, d.month, d.day);
    final s = DateTime(start.year, start.month, start.day);
    final e = DateTime(end.year, end.month, end.day);
    return !day.isBefore(s) && !day.isAfter(e);
  }

  tx.TransactionType get _wantType => _cType == 'expense' ? tx.TransactionType.expense : tx.TransactionType.income;

  List<_Series> _buildSeries() {
    final transactions = ref.watch(transactionsProvider).valueOrNull ?? <tx.Transaction>[];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? <wl.Wallet>[];
    final allCats = ref.watch(categoriesProvider);
    final wantType = _wantType;

    final periodTx = transactions.where((t) =>
        t.type == wantType &&
        _inRange(t.date) &&
        t.category != 'Transfer' && t.category != 'Balance Adjustment');

    final totals = <String, double>{};
    for (final t in periodTx) {
      final key = _cGroup == 'category' ? t.category : t.accountId;
      totals[key] = (totals[key] ?? 0) + t.amount;
    }

    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (_cGroup == 'category') {
      return [
        for (var i = 0; i < entries.length; i++)
          _Series(
            id: entries[i].key,
            label: entries[i].key,
            emoji: categoryEmoji(allCats, entries[i].key),
            value: entries[i].value,
            color: kCategoryPalette[i % kCategoryPalette.length],
          ),
      ];
    }

    return [
      for (var i = 0; i < entries.length; i++)
        _Series(
          id: entries[i].key,
          label: wallets.where((w) => w.id == entries[i].key).firstOrNull?.name ?? 'Unknown',
          emoji: _walletEmoji(wallets.where((w) => w.id == entries[i].key).firstOrNull?.type),
          value: entries[i].value,
          color: kCategoryPalette[i % kCategoryPalette.length],
        ),
    ];
  }

  static String _walletEmoji(wl.WalletType? type) {
    switch (type) {
      case wl.WalletType.bank: return '🏦';
      case wl.WalletType.credit: return '💳';
      case wl.WalletType.cash: return '💵';
      case wl.WalletType.crypto: return '🪙';
      case wl.WalletType.savings: return '🐷';
      case wl.WalletType.other: return '📂';
      default: return '👛';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cType == 'insights') {
      return Scaffold(
        backgroundColor: AppTheme.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              _buildTypeToggle(),
              const SizedBox(height: 12),
              Expanded(child: InsightsTab(month: _insightsMonth)),
            ],
          ),
        ),
      );
    }

    final series = _buildSeries();
    final total = series.fold(0.0, (s, r) => s + r.value);
    final selectedId = _selected[_selectionKey];

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildTypeToggle(),
            const SizedBox(height: 10),
            _buildGroupToggle(),
            const SizedBox(height: 16),
            if (total > 0) Center(child: _buildDonut(series, total, selectedId)),
            const SizedBox(height: 8),
            Expanded(
              child: total == 0
                  ? _buildEmptyState()
                  : ListView(
                      controller: _listScrollController,
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        _buildListHeader(series.length),
                        ..._buildRows(series, total, selectedId),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Row(children: [
        const Text('Charts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        const Spacer(),
        _cType == 'insights' ? _buildInsightsMonthPill() : _buildRangePill(),
        const SizedBox(width: 10),
        const SettingsIconButton(),
      ]),
    );
  }

  Widget _buildInsightsMonthPill() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(17)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _pillArrow(Icons.chevron_left_rounded, () => _stepInsightsMonth(-1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('${kMonthNames[_insightsMonth.month - 1]} ${_insightsMonth.year}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        ),
        Opacity(
          opacity: _canStepInsightsForward ? 1 : 0.3,
          child: _pillArrow(Icons.chevron_right_rounded, () => _stepInsightsMonth(1)),
        ),
      ]),
    );
  }

  Widget _buildRangePill() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(17)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _pillArrow(Icons.chevron_left_rounded, () => _step(-1)),
        GestureDetector(
          onTap: _openRangeSheet,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_rangeLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.primary)),
              const SizedBox(width: 3),
              const Icon(Icons.expand_more_rounded, size: 14, color: AppTheme.primary),
            ]),
          ),
        ),
        _pillArrow(Icons.chevron_right_rounded, () => _step(1)),
      ]),
    );
  }

  Widget _pillArrow(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(width: 26, height: 28, child: Icon(icon, size: 16, color: AppTheme.primary)),
    );
  }

  Widget _buildTypeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(22)),
        child: Row(children: [
          _typePill('Expenses', 'expense'),
          _typePill('Income', 'income'),
          _typePill('Insights', 'insights'),
        ]),
      ),
    );
  }

  Widget _typePill(String label, String value) {
    final active = _cType == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _cType = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 4)] : null,
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? AppTheme.primary : AppTheme.onSurfaceVariant)),
        ),
      ),
    );
  }

  Widget _buildGroupToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _groupChip('Category', 'category'),
        const SizedBox(width: 8),
        _groupChip('Account', 'account'),
      ]),
    );
  }

  Widget _groupChip(String label, String value) {
    final active = _cGroup == value;
    return GestureDetector(
      onTap: () => setState(() => _cGroup = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.surfaceContainerLow, width: 1.5),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppTheme.onSurfaceVariant)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          _cType == 'expense' ? 'No expenses recorded in this period.' : 'No income recorded in this period.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppTheme.onSurfaceVariant),
        ),
      ),
    );
  }

  // Badges straddle the ring's outer edge (half on the colored slice, half
  // outside it). Percentage labels sit slightly inward from the slice
  // band's radial center, toward the inner edge.
  static const _badgeRadius = _ringRadius + _ringStroke / 2;
  static const _labelRadius = _ringRadius - _ringStroke * 0.10;
  // Minimum arc length (px) a "NN%" label needs along the label radius —
  // below this the slice is too thin circumferentially to show it, no
  // matter how wide the ring band is drawn.
  static const _minLabelArcLength = 34.0;
  static const _minLabelFrac = _minLabelArcLength / (2 * pi * _labelRadius);

  Widget _buildDonut(List<_Series> series, double total, String? selectedId) {
    const size = _donutSize;

    double acc = 0;
    final badges = <Widget>[];
    final labels = <Widget>[];
    for (final s in series) {
      final frac = s.value / total;
      final midAngle = -pi / 2 + (acc + frac / 2) * 2 * pi;
      final on = selectedId == s.id;
      final bSize = on ? 39.1 : 34.5; // (34/30) * 1.15 — icon circle +15%
      final bx = size / 2 + _badgeRadius * cos(midAngle) - bSize / 2;
      final by = size / 2 + _badgeRadius * sin(midAngle) - bSize / 2;
      badges.add(Positioned(
        left: bx, top: by,
        child: IgnorePointer(
          child: Container(
            width: bSize, height: bSize,
            decoration: BoxDecoration(
              color: Colors.white, shape: BoxShape.circle,
              border: Border.all(color: s.color, width: 2.5),
              boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.16), blurRadius: 8)],
            ),
            child: Center(child: Text(s.emoji, style: TextStyle(fontSize: on ? 17 : 14))),
          ),
        ),
      ));

      if (frac >= _minLabelFrac) {
        final lx = size / 2 + _labelRadius * cos(midAngle);
        final ly = size / 2 + _labelRadius * sin(midAngle);
        labels.add(Positioned(
          left: lx - 18, top: ly - 9,
          child: IgnorePointer(
            child: SizedBox(
              width: 36,
              child: Text('${(frac * 100).round()}%', textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ));
      }
      acc += frac;
    }

    final centerColor = _cType == 'expense' ? const Color(0xFFD32F2F) : const Color(0xFF0E8C74);

    return GestureDetector(
      onTapUp: (details) => _handleDonutTap(details.localPosition, series, total),
      child: SizedBox(
        width: size, height: size,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            CustomPaint(size: const Size(size, size), painter: _DonutPainter(series, total, selectedId)),
            IgnorePointer(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_cType == 'expense' ? 'Total Expenses' : 'Total Income',
                    style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                Container(width: 22, height: 3, margin: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(color: centerColor.withOpacity(0.55), borderRadius: BorderRadius.circular(2))),
                Text('RM${total.toStringAsFixed(0)}',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: centerColor)),
              ]),
            ),
            ...badges,
            ...labels,
          ],
        ),
      ),
    );
  }

  // A single hit-test covering both the ring band and the badges that
  // straddle it, so tapping either the slice or its icon selects the same
  // segment (matched purely by angle from center).
  void _handleDonutTap(Offset local, List<_Series> series, double total) {
    if (total <= 0 || series.isEmpty) return;
    const cx = _donutSize / 2, cy = _donutSize / 2;
    final dx = local.dx - cx, dy = local.dy - cy;
    final r = sqrt(dx * dx + dy * dy);
    const minR = _ringRadius - _ringStroke / 2 - 10;
    const maxR = _badgeRadius + 22;
    if (r < minR || r > maxR) return;

    var angle = atan2(dy, dx) + pi / 2;
    if (angle < 0) angle += 2 * pi;
    final frac = angle / (2 * pi);

    double acc = 0;
    for (final s in series) {
      final f = s.value / total;
      if (frac >= acc && frac < acc + f) {
        setState(() => _selected[_selectionKey] = s.id);
        _scrollRowToTop(s.id);
        return;
      }
      acc += f;
    }
    setState(() => _selected[_selectionKey] = series.last.id);
    _scrollRowToTop(series.last.id);
  }

  // Scrolls the tapped slice's row to the top of the list's own scroll area.
  // The list itself never reorders and the page around it doesn't move.
  void _scrollRowToTop(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _rowKeys[id];
      final ctx = key?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Widget _buildListHeader(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Row(children: [
        Text(_cGroup == 'category' ? 'By category' : 'By account',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary)),
        const Spacer(),
        Text('$count ${_cGroup == 'category' ? 'CATEGORIES' : 'ACCOUNTS'}',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: AppTheme.onSurfaceVariant)),
      ]),
    );
  }

  List<Widget> _buildRows(List<_Series> series, double total, String? selectedId) {
    final widgets = <Widget>[];
    for (var i = 0; i < series.length; i++) {
      final s = series[i];
      if (i > 0) {
        widgets.add(Divider(height: 1, thickness: 1, indent: 24, endIndent: 24, color: AppTheme.surfaceContainerLow));
      }
      widgets.add(KeyedSubtree(
        key: _rowKeys.putIfAbsent(s.id, () => GlobalKey()),
        child: GestureDetector(
          onTap: () {
            setState(() => _selected[_selectionKey] = s.id);
            if (_cGroup == 'category') _openCategoryDetail(s);
          },
          child: Container(
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            decoration: BoxDecoration(
              color: selectedId == s.id ? const Color(0xFFEDF1FB) : Colors.transparent,
              border: Border(left: BorderSide(color: selectedId == s.id ? s.color : Colors.transparent, width: 3)),
            ),
            child: Row(children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 10),
              Text(s.emoji, style: const TextStyle(fontSize: 17)),
              const SizedBox(width: 8),
              Expanded(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
              SizedBox(width: 36, child: Text('${(s.value / total * 100).round()}%', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.onSurfaceVariant))),
              SizedBox(width: 76, child: Text('RM${s.value.toStringAsFixed(0)}', textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.onSurface))),
            ]),
          ),
        ),
      ));
    }
    return widgets;
  }

  // ─────────────────────────── Category detail sheet ───────────────────────────

  void _openCategoryDetail(_Series s) {
    final transactions = ref.read(transactionsProvider).valueOrNull ?? <tx.Transaction>[];
    final wantType = _wantType;
    final matches = transactions.where((t) =>
        t.type == wantType && t.category == s.id && _inRange(t.date)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final grouped = <String, List<tx.Transaction>>{};
    for (final t in matches) {
      final key = DateFormat('d MMM yyyy').format(t.date).toUpperCase();
      grouped.putIfAbsent(key, () => []).add(t);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
          child: Column(children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(children: [
                Container(width: 44, height: 44,
                    decoration: BoxDecoration(color: s.color.withOpacity(0.12), shape: BoxShape.circle),
                    child: Center(child: Text(s.emoji, style: const TextStyle(fontSize: 22)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  Text('${matches.length} transaction${matches.length == 1 ? '' : 's'} · $_rangeLabel',
                      style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                ])),
                Text('RM${s.value.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: s.color)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: matches.isEmpty
                  ? const Center(child: Text('No transactions in this period.', style: TextStyle(color: AppTheme.onSurfaceVariant)))
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      children: [
                        for (final entry in grouped.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                            child: Text(entry.key, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                letterSpacing: 1.2, color: AppTheme.onSurfaceVariant.withOpacity(0.7))),
                          ),
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
                            child: Column(children: [
                              for (var i = 0; i < entry.value.length; i++) ...[
                                if (i > 0) Divider(height: 1, indent: 14, endIndent: 14, color: AppTheme.surfaceContainerLow),
                                Builder(builder: (_) {
                                  final t = entry.value[i];
                                  return GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      context.push('/transaction-details', extra: t);
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(children: [
                                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(t.note?.isNotEmpty == true ? t.note! : t.category,
                                              maxLines: 1, overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
                                          Text(DateFormat('HH:mm').format(t.date),
                                              style: const TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
                                        ])),
                                        Text(
                                          '${wantType == tx.TransactionType.expense ? '-' : '+'}RM${t.amount.toStringAsFixed(2)}',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800,
                                              color: wantType == tx.TransactionType.expense ? const Color(0xFFD32F2F) : const Color(0xFF0E8C74)),
                                        ),
                                      ]),
                                    ),
                                  );
                                }),
                              ],
                            ]),
                          ),
                        ],
                      ],
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─────────────────────────── Date range sheet ───────────────────────────

  void _openRangeSheet() {
    final fromCtrl = TextEditingController(text: _dmy(_customFrom));
    final toCtrl = TextEditingController(text: _dmy(_customTo));
    String? dateErr;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void applyCustom() {
            final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(fromCtrl.text.trim());
            final m2 = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(toCtrl.text.trim());
            if (m == null || m2 == null) {
              setSheet(() => dateErr = 'Use DD/MM/YYYY, e.g. 01/09/2026');
              return;
            }
            final from = DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
            final to = DateTime(int.parse(m2.group(3)!), int.parse(m2.group(2)!), int.parse(m2.group(1)!));
            if (from.day != int.parse(m.group(1)!) || from.month != int.parse(m.group(2)!) ||
                to.day != int.parse(m2.group(1)!) || to.month != int.parse(m2.group(2)!)) {
              setSheet(() => dateErr = 'That date does not exist');
              return;
            }
            if (from.isAfter(to)) {
              setSheet(() => dateErr = 'From must be on or before To');
              return;
            }
            setState(() { _rangeMode = 'custom'; _customFrom = from; _customTo = to; });
            setSheet(() => dateErr = null);
          }

          final spanNote = dateErr ??
              '${_customTo.difference(_customFrom).inDays + 1} days selected · type as DD/MM/YYYY';

          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(2)))),
                Row(children: [
                  const Text('Date range', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  const Spacer(),
                  Text(_rangeLabel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.secondary)),
                ]),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    for (final mode in const [['month', 'Monthly'], ['week', 'Weekly'], ['custom', 'Custom']])
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setSheet(() => setState(() => _rangeMode = mode[0])),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: _rangeMode == mode[0] ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: _rangeMode == mode[0] ? [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 4)] : null,
                            ),
                            child: Text(mode[1], textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                    color: _rangeMode == mode[0] ? AppTheme.primary : AppTheme.onSurfaceVariant)),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 18),
                if (_rangeMode == 'month') ...[
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    GestureDetector(
                      onTap: () => setSheet(() => setState(() => _rangeYear -= 1)),
                      child: _circleBtn(Icons.chevron_left_rounded),
                    ),
                    SizedBox(width: 60, child: Text('$_rangeYear', textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                    GestureDetector(
                      onTap: () => setSheet(() => setState(() => _rangeYear += 1)),
                      child: _circleBtn(Icons.chevron_right_rounded),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 12,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 1.6),
                    itemBuilder: (_, i) {
                      final active = _rangeMode == 'month' && _rangeMonth == i;
                      return GestureDetector(
                        onTap: () => setSheet(() => setState(() { _rangeMode = 'month'; _rangeMonth = i; })),
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active ? AppTheme.primary : AppTheme.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(kMonthNames[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: active ? Colors.white : AppTheme.onSurface)),
                        ),
                      );
                    },
                  ),
                ] else if (_rangeMode == 'week') ...[
                  for (var i = 0; i < 6; i++)
                    Builder(builder: (_) {
                      final s = _startOfWeek(DateTime.now()).subtract(Duration(days: 7 * i));
                      final e = s.add(const Duration(days: 6));
                      final active = _rangeMode == 'week' && _weekStart == s;
                      final label = i == 0 ? 'This week' : i == 1 ? 'Last week' : '$i weeks ago';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => setSheet(() => setState(() { _rangeMode = 'week'; _weekStart = s; })),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                                color: active ? AppTheme.primary : AppTheme.surface,
                                borderRadius: BorderRadius.circular(16)),
                            child: Row(children: [
                              Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                  color: active ? Colors.white : AppTheme.onSurface)),
                              const Spacer(),
                              Text('${_fmtDay(s)} – ${_fmtDay(e)}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: active ? Colors.white70 : AppTheme.onSurfaceVariant)),
                            ]),
                          ),
                        ),
                      );
                    }),
                ] else ...[
                  Row(children: [
                    Expanded(child: _dateField('FROM', fromCtrl, () { applyCustom(); })),
                    const SizedBox(width: 10),
                    Expanded(child: _dateField('TO', toCtrl, () { applyCustom(); })),
                  ]),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(spanNote, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: dateErr != null ? const Color(0xFFD32F2F) : AppTheme.onSurfaceVariant)),
                  ),
                ],
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    height: 52, alignment: Alignment.center,
                    decoration: BoxDecoration(color: const Color(0xFFC9ECE6), borderRadius: BorderRadius.circular(22)),
                    child: const Text('Apply', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0A4A3D))),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    ).then((_) => setState(() {}));
  }

  Widget _circleBtn(IconData icon) => Container(
        width: 30, height: 30,
        decoration: BoxDecoration(color: AppTheme.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: AppTheme.primary),
      );

  Widget _dateField(String label, TextEditingController controller, VoidCallback onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(color: AppTheme.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: AppTheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: 10,
          onChanged: (_) => onChanged(),
          decoration: const InputDecoration(border: InputBorder.none, isDense: true, counterText: '', hintText: 'DD/MM/YYYY'),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.onSurface),
        ),
      ]),
    );
  }

  String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _DonutPainter extends CustomPainter {
  final List<_Series> series;
  final double total;
  final String? selectedId;
  const _DonutPainter(this.series, this.total, this.selectedId);

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    const radius = _PredictionDashboardScreenState._ringRadius;
    const strokeWidth = _PredictionDashboardScreenState._ringStroke;
    var startAngle = -pi / 2;
    for (final s in series) {
      final sweep = (s.value / total) * 2 * pi;
      final on = selectedId == null || selectedId == s.id;
      final gap = sweep > 0.05 ? 0.03 : 0.0;
      final paint = Paint()
        ..color = s.color.withOpacity(on ? 1 : 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = selectedId == s.id ? strokeWidth + 5 : strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), startAngle, max(sweep - gap, 0.001), false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.total != total || oldDelegate.selectedId != selectedId;
}
