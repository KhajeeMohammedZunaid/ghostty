import 'dart:convert';

/// Represents a single todo item
class TodoItem {
  final String id;
  final String title;
  final String? description;
  final DateTime createdAt;
  final DateTime? dueDate;
  final DateTime? dueTime; // Specific time for notification
  final bool isCompleted;
  final int? backgroundColor;
  final TodoPriority priority;
  final bool hasReminder;
  final List<String> subtasks;
  final List<bool> subtaskCompleted;

  TodoItem({
    required this.id,
    required this.title,
    this.description,
    required this.createdAt,
    this.dueDate,
    this.dueTime,
    this.isCompleted = false,
    this.backgroundColor,
    this.priority = TodoPriority.normal,
    this.hasReminder = false,
    this.subtasks = const [],
    this.subtaskCompleted = const [],
  });

  TodoItem copyWith({
    String? id,
    String? title,
    String? description,
    DateTime? createdAt,
    DateTime? dueDate,
    DateTime? dueTime,
    bool? isCompleted,
    int? backgroundColor,
    bool clearBackground = false,
    TodoPriority? priority,
    bool? hasReminder,
    List<String>? subtasks,
    List<bool>? subtaskCompleted,
    bool clearDueDate = false,
    bool clearDueTime = false,
  }) {
    return TodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      dueTime: clearDueTime ? null : (dueTime ?? this.dueTime),
      isCompleted: isCompleted ?? this.isCompleted,
      backgroundColor: clearBackground ? null : (backgroundColor ?? this.backgroundColor),
      priority: priority ?? this.priority,
      hasReminder: hasReminder ?? this.hasReminder,
      subtasks: subtasks ?? this.subtasks,
      subtaskCompleted: subtaskCompleted ?? this.subtaskCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'dueTime': dueTime?.toIso8601String(),
      'isCompleted': isCompleted,
      'backgroundColor': backgroundColor,
      'priority': priority.index,
      'hasReminder': hasReminder,
      'subtasks': subtasks,
      'subtaskCompleted': subtaskCompleted,
    };
  }

  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      dueDate: json['dueDate'] != null 
          ? DateTime.parse(json['dueDate'] as String) 
          : null,
      dueTime: json['dueTime'] != null 
          ? DateTime.parse(json['dueTime'] as String) 
          : null,
      isCompleted: json['isCompleted'] as bool? ?? false,
      backgroundColor: json['backgroundColor'] as int?,
      priority: TodoPriority.values[json['priority'] as int? ?? 1],
      hasReminder: json['hasReminder'] as bool? ?? false,
      subtasks: (json['subtasks'] as List<dynamic>?)?.cast<String>() ?? [],
      subtaskCompleted: (json['subtaskCompleted'] as List<dynamic>?)?.cast<bool>() ?? [],
    );
  }

  String toEncodedJson() => jsonEncode(toJson());

  factory TodoItem.fromEncodedJson(String encoded) {
    return TodoItem.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }

  /// Check if todo is overdue
  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final now = DateTime.now();
    if (dueTime != null) {
      final dueDateTime = DateTime(
        dueDate!.year,
        dueDate!.month,
        dueDate!.day,
        dueTime!.hour,
        dueTime!.minute,
      );
      return now.isAfter(dueDateTime);
    }
    return now.isAfter(DateTime(dueDate!.year, dueDate!.month, dueDate!.day, 23, 59, 59));
  }

  /// Check if todo is due today
  bool get isDueToday {
    if (dueDate == null) return false;
    final now = DateTime.now();
    return dueDate!.year == now.year && 
           dueDate!.month == now.month && 
           dueDate!.day == now.day;
  }

  /// Get completion percentage for subtasks
  double get completionPercentage {
    if (subtasks.isEmpty) return isCompleted ? 1.0 : 0.0;
    final completed = subtaskCompleted.where((c) => c).length;
    return completed / subtasks.length;
  }

  /// Get formatted due date string
  String get formattedDueDate {
    if (dueDate == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dueDay = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);

    String dateStr;
    if (dueDay == today) {
      dateStr = 'Today';
    } else if (dueDay == tomorrow) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = '${dueDate!.day}/${dueDate!.month}/${dueDate!.year}';
    }

    if (dueTime != null) {
      final hour = dueTime!.hour;
      final minute = dueTime!.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      dateStr += ' at $displayHour:$minute $period';
    }

    return dateStr;
  }
}

enum TodoPriority {
  low,
  normal,
  high,
}

extension TodoPriorityExtension on TodoPriority {
  String get label {
    switch (this) {
      case TodoPriority.low:
        return 'Low';
      case TodoPriority.normal:
        return 'Normal';
      case TodoPriority.high:
        return 'High';
    }
  }

  int get colorValue {
    switch (this) {
      case TodoPriority.low:
        return 0xFF4CAF50; // Green
      case TodoPriority.normal:
        return 0xFF2196F3; // Blue
      case TodoPriority.high:
        return 0xFFFF5722; // Orange-Red
    }
  }
}
