import 'package:flutter/material.dart';
import '../../../domain/models/app_category.dart';

// Shared between prediction_dashboard_screen.dart (Expenses/Income donut)
// and insights_tab.dart (Insights) — both color categories by index from
// this same palette since AppCategory itself carries no color.
const kCategoryPalette = [
  Color(0xFF2552CA), Color(0xFF00C4A7), Color(0xFF4F79E0), Color(0xFFF2A93B),
  Color(0xFF7BA3F0), Color(0xFFA5B4CE), Color(0xFFE0736B), Color(0xFF8E6FD1),
];

const kMonthNames = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

String rm(num value, [int decimals = 0]) => 'RM${value.toStringAsFixed(decimals)}';

/// Looks up the emoji for a category label, matching by exact label first
/// then case-insensitively, falling back to a generic coin emoji.
String categoryEmoji(Map<String, List<AppCategory>> allCategories, String label) {
  for (final cats in allCategories.values) {
    for (final c in cats) {
      if (c.label == label) return c.emoji;
    }
  }
  for (final cats in allCategories.values) {
    for (final c in cats) {
      if (c.label.toLowerCase() == label.toLowerCase()) return c.emoji;
    }
  }
  return '💰';
}
