import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class DataSheet extends StatefulWidget {
  final bool isImport;
  final VoidCallback onClose;

  const DataSheet({super.key, required this.isImport, required this.onClose});

  @override
  State<DataSheet> createState() => _DataSheetState();
}

class _DataSheetState extends State<DataSheet> {
  String _format = 'csv';

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      GestureDetector(
        onTap: widget.onClose,
        child: Container(color: Colors.black.withOpacity(0.4)),
      ),
      Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [BoxShadow(color: Color(0x14001A3A), blurRadius: 60, offset: Offset(0, -20))],
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 48, height: 6, decoration: BoxDecoration(
              color: AppTheme.surfaceContainerLow, borderRadius: BorderRadius.circular(3))),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(widget.isImport ? 'Import Data' : 'Export Data',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
              GestureDetector(
                onTap: widget.onClose,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(color: AppTheme.surfaceContainerLow, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 20, color: AppTheme.onSurfaceVariant),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _FormatCard(
                label: 'CSV',
                title: 'CSV Format',
                description: widget.isImport ? 'Upload raw spreadsheet data.' : 'Raw data for spreadsheets.',
                selected: _format == 'csv',
                onTap: () => setState(() => _format = 'csv'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _FormatCard(
                label: 'PDF',
                title: 'PDF Report',
                description: widget.isImport ? 'Import formatted visual documents.' : 'Formatted visual report.',
                selected: _format == 'pdf',
                onTap: () => setState(() => _format = 'pdf'),
              )),
            ]),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: widget.onClose,
                icon: Icon(widget.isImport ? Icons.upload_rounded : Icons.download_rounded, size: 20),
                label: Text(widget.isImport ? 'IMPORT DATA' : 'EXPORT DATA',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 2)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class _FormatCard extends StatelessWidget {
  final String label;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _FormatCard({
    required this.label, required this.title, required this.description,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.secondary.withOpacity(0.4) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : AppTheme.surfaceContainerLow,
                shape: BoxShape.circle,
              ),
              child: Center(child: Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppTheme.onSurfaceVariant))),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: AppTheme.secondary, size: 24),
          ]),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.onSurface)),
          const SizedBox(height: 4),
          Text(description, style: const TextStyle(fontSize: 13, color: AppTheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
