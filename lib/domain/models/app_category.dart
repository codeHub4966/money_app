class AppCategory {
  final String id;
  final String label;
  final String emoji;
  const AppCategory({required this.id, required this.label, required this.emoji});

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'emoji': emoji};

  factory AppCategory.fromJson(Map<String, dynamic> j) =>
      AppCategory(id: j['id'] as String, label: j['label'] as String, emoji: j['emoji'] as String);
}
