import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/app_category.dart';
import '../../providers/app_providers.dart';

class CategoryManagementScreen extends ConsumerStatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  bool _isExpense = true;
  String _search = '';

  String get _type => _isExpense ? 'expense' : 'income';

  List<AppCategory> _filtered(List<AppCategory> cats) => _search.isEmpty
      ? cats
      : cats
          .where((c) => c.label.toLowerCase().contains(_search.toLowerCase()))
          .toList();

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (_) => _AddCategoryDialog(type: _type),
    );
  }

  void _confirmDelete(AppCategory cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Text(cat.emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 10),
          const Text('Delete Category',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: Text('Remove "${cat.label}" from $_type categories?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(categoriesProvider.notifier).remove(_type, cat.id, ref);
                if (mounted) Navigator.pop(ctx);
              } catch (e) {
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString().replaceFirst('Exception: ', '')),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showSearch() {
    final ctrl = TextEditingController(text: _search);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Search Category'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Type to search...',
            filled: true,
            fillColor: AppTheme.surfaceContainerLow,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _search = '');
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () {
              setState(() => _search = ctrl.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Search',
                style: TextStyle(
                    color: AppTheme.secondary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allCats = ref.watch(categoriesProvider)[_type] ?? [];
    final cats = _filtered(allCats);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      body: SafeArea(
        child: Column(children: [
          // ── Header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded,
                    color: AppTheme.onSurface),
                onPressed: () => Navigator.pop(context),
              ),
              const Expanded(
                child: Text('Categories',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.onSurface)),
              ),
              IconButton(
                icon: const Icon(Icons.search_rounded, color: AppTheme.onSurface),
                onPressed: _showSearch,
              ),
            ]),
          ),

          // ── Toggle ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(50),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8)
                ],
              ),
              child: Row(children: [
                _ToggleBtn(
                    label: 'Expenses',
                    active: _isExpense,
                    onTap: () => setState(() { _isExpense = true; _search = ''; })),
                _ToggleBtn(
                    label: 'Income',
                    active: !_isExpense,
                    onTap: () => setState(() { _isExpense = false; _search = ''; })),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Hint ────────────────────────────────────────────────
          Text(
            'Tap to delete  ·  Long-press and drag to reorder',
            style: TextStyle(
                fontSize: 11,
                color: AppTheme.onSurfaceVariant.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 12),

          // ── Draggable Grid ──────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _buildDraggableGrid(cats),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildDraggableGrid(List<AppCategory> cats) {
    return GridView.builder(
      itemCount: cats.length + 1,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 20,
        childAspectRatio: 0.8,
      ),
      itemBuilder: (context, i) {
        // ADD button is always last
        if (i == cats.length) {
          return _CategoryCell(
            emoji: '', label: 'ADD',
            isAdd: true, highlighted: false,
            onTap: _showAddDialog,
          );
        }

        final cat = cats[i];

        return LongPressDraggable<int>(
          data: i,
          delay: const Duration(milliseconds: 300),
          // Ghost following the finger
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.85,
              child: SizedBox(
                width: 72,
                child: _CategoryCell(
                  emoji: cat.emoji, label: cat.label,
                  isAdd: false, highlighted: false,
                  onTap: () {},
                ),
              ),
            ),
          ),
          // Faded placeholder in original slot
          childWhenDragging: Opacity(
            opacity: 0.25,
            child: _CategoryCell(
              emoji: cat.emoji, label: cat.label,
              isAdd: false, highlighted: false,
              onTap: () {},
            ),
          ),
          child: DragTarget<int>(
            onWillAcceptWithDetails: (d) => d.data != i,
            onAcceptWithDetails: (d) {
              ref.read(categoriesProvider.notifier).reorder(_type, d.data, i);
            },
            builder: (_, candidates, __) => _CategoryCell(
              emoji: cat.emoji,
              label: cat.label,
              isAdd: false,
              highlighted: candidates.isNotEmpty,
              onTap: () => _confirmDelete(cat),
            ),
          ),
        );
      },
    );
  }
}

// ── _AddCategoryDialog ─────────────────────────────────────────────────────

class _AddCategoryDialog extends ConsumerStatefulWidget {
  final String type;
  const _AddCategoryDialog({required this.type});

  @override
  ConsumerState<_AddCategoryDialog> createState() => _AddCategoryDialogState();
}

class _AddCategoryDialogState extends ConsumerState<_AddCategoryDialog> {
  final _labelCtrl = TextEditingController();
  final _emojiCtrl = TextEditingController();
  final _emojiFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _emojiFocus.addListener(() => setState(() {})); // rebuild on focus change
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _emojiCtrl.dispose();
    _emojiFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final label = _labelCtrl.text.trim();
    final emoji = _emojiCtrl.text.trim();
    if (label.isEmpty || emoji.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter both an icon and a name.')));
      return;
    }
    final id =
        '${label.toLowerCase().replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}';
    ref.read(categoriesProvider.notifier).add(
          widget.type,
          AppCategory(id: id, label: label, emoji: emoji),
        );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Text('Add Category',
          style: TextStyle(fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        // Emoji field — hint disappears as soon as keyboard opens (focus)
        TextField(
          controller: _emojiCtrl,
          focusNode: _emojiFocus,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 36),
          maxLength: 2,
          decoration: InputDecoration(
            counterText: '',
            // hide hint the moment the field is focused (keyboard appears)
            hintText: _emojiFocus.hasFocus ? '' : '😀',
            hintStyle: const TextStyle(fontSize: 36),
            filled: true,
            fillColor: AppTheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text('Type 1 emoji or up to 2 characters',
            style: TextStyle(fontSize: 11, color: AppTheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        // Category name
        TextField(
          controller: _labelCtrl,
          textCapitalization: TextCapitalization.words,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Category name',
            filled: true,
            fillColor: AppTheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Add',
              style: TextStyle(
                  color: AppTheme.secondary, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────

class _ToggleBtn extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _ToggleBtn(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(50),
              boxShadow: active
                  ? [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8)
                    ]
                  : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: active
                        ? AppTheme.onSurface
                        : AppTheme.onSurfaceVariant)),
          ),
        ),
      );
}

class _CategoryCell extends StatelessWidget {
  final String emoji;
  final String label;
  final bool isAdd;
  final bool highlighted;
  final VoidCallback onTap;
  const _CategoryCell({
    required this.emoji,
    required this.label,
    required this.isAdd,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: highlighted
                  ? AppTheme.secondary.withValues(alpha: 0.15)
                  : const Color(0xFFEAECF2),
              shape: BoxShape.circle,
              border: highlighted
                  ? Border.all(
                      color: AppTheme.secondary, width: 2)
                  : null,
            ),
            child: isAdd
                ? const Icon(Icons.add_rounded,
                    size: 28, color: Color(0xFF9EA3B8))
                : Center(
                    child: Text(emoji,
                        style: const TextStyle(fontSize: 28))),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: AppTheme.onSurface),
          ),
        ]),
      );
}
