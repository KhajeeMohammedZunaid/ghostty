import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:home_widget/home_widget.dart';
import '../models/todo_item.dart';

class TodoStorageService {
  static const String _boxName = 'todos_box';
  static const String _todosKey = 'todos_list';

  static final TodoStorageService _instance = TodoStorageService._internal();
  factory TodoStorageService() => _instance;
  TodoStorageService._internal();

  Box? _box;

  /// Initialize the storage - must be called before any operation
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) return;
    try {
      _box = await Hive.openBox(_boxName);
      debugPrint('TodoStorageService: Box initialized successfully');
    } catch (e) {
      debugPrint('TodoStorageService: Error initializing box: $e');
      // Try to delete and recreate if corrupted
      try {
        await Hive.deleteBoxFromDisk(_boxName);
        _box = await Hive.openBox(_boxName);
        debugPrint('TodoStorageService: Box recreated after error');
      } catch (e2) {
        debugPrint('TodoStorageService: Failed to recreate box: $e2');
        rethrow;
      }
    }
  }

  /// Ensure box is ready
  Future<Box> _getBox() async {
    if (_box == null || !_box!.isOpen) {
      await initialize();
    }
    return _box!;
  }

  /// Get all todos from storage
  Future<List<TodoItem>> getAllTodos() async {
    try {
      final box = await _getBox();
      final dynamic rawData = box.get(_todosKey);
      
      if (rawData == null) {
        debugPrint('TodoStorageService: No todos found in storage');
        return [];
      }

      final List<dynamic> todosList = rawData as List<dynamic>;
      final todos = <TodoItem>[];
      
      for (final item in todosList) {
        try {
          if (item is String) {
            todos.add(TodoItem.fromEncodedJson(item));
          }
        } catch (e) {
          debugPrint('TodoStorageService: Error parsing todo item: $e');
          // Skip corrupted items
        }
      }
      
      debugPrint('TodoStorageService: Loaded ${todos.length} todos');
      return todos;
    } catch (e) {
      debugPrint('TodoStorageService: Error loading todos: $e');
      return [];
    }
  }

  /// Get incomplete todos only
  Future<List<TodoItem>> getIncompleteTodos() async {
    final todos = await getAllTodos();
    return todos.where((todo) => !todo.isCompleted).toList();
  }

  /// Get completed todos only
  Future<List<TodoItem>> getCompletedTodos() async {
    final todos = await getAllTodos();
    return todos.where((todo) => todo.isCompleted).toList();
  }

  /// Get todos for a specific date
  Future<List<TodoItem>> getTodosForDate(DateTime date) async {
    final todos = await getAllTodos();
    return todos.where((todo) {
      if (todo.dueDate == null) return false;
      return todo.dueDate!.year == date.year &&
          todo.dueDate!.month == date.month &&
          todo.dueDate!.day == date.day;
    }).toList();
  }

  /// Get today's todos
  Future<List<TodoItem>> getTodaysTodos() async {
    return getTodosForDate(DateTime.now());
  }

  /// Get overdue todos
  Future<List<TodoItem>> getOverdueTodos() async {
    final todos = await getAllTodos();
    return todos.where((todo) => todo.isOverdue).toList();
  }

  /// Save a todo (create or update)
  Future<bool> saveTodo(TodoItem todo) async {
    try {
      final box = await _getBox();
      final todos = await getAllTodos();

      // Find existing index
      final existingIndex = todos.indexWhere((t) => t.id == todo.id);

      if (existingIndex >= 0) {
        todos[existingIndex] = todo;
        debugPrint('TodoStorageService: Updated todo: ${todo.title}');
      } else {
        todos.add(todo);
        debugPrint('TodoStorageService: Added new todo: ${todo.title}');
      }

      // Save to storage
      final success = await _saveTodosToBox(box, todos);
      
      if (success) {
        // Update widget
        await _updateHomeWidget();
      }
      
      return success;
    } catch (e) {
      debugPrint('TodoStorageService: Error saving todo: $e');
      return false;
    }
  }

  /// Delete a todo by ID
  Future<bool> deleteTodo(String todoId) async {
    try {
      final box = await _getBox();
      final todos = await getAllTodos();

      final initialLength = todos.length;
      todos.removeWhere((t) => t.id == todoId);
      
      if (todos.length < initialLength) {
        final success = await _saveTodosToBox(box, todos);
        if (success) {
          debugPrint('TodoStorageService: Deleted todo: $todoId');
          await _updateHomeWidget();
        }
        return success;
      } else {
        debugPrint('TodoStorageService: Todo not found for deletion: $todoId');
        return false;
      }
    } catch (e) {
      debugPrint('TodoStorageService: Error deleting todo: $e');
      return false;
    }
  }

  /// Toggle todo completion status
  Future<bool> toggleTodoCompletion(String todoId) async {
    try {
      final box = await _getBox();
      final todos = await getAllTodos();
      final index = todos.indexWhere((t) => t.id == todoId);

      if (index < 0) {
        debugPrint('TodoStorageService: Todo not found for toggle: $todoId');
        return false;
      }

      final todo = todos[index];
      final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);

      todos[index] = updatedTodo;
      final success = await _saveTodosToBox(box, todos);
      
      if (success) {
        debugPrint('TodoStorageService: Toggled todo: ${todo.title} -> ${updatedTodo.isCompleted}');
        await _updateHomeWidget();
      }
      
      return success;
    } catch (e) {
      debugPrint('TodoStorageService: Error toggling todo: $e');
      return false;
    }
  }

  /// Toggle subtask completion
  Future<bool> toggleSubtaskCompletion(String todoId, int subtaskIndex) async {
    try {
      final box = await _getBox();
      final todos = await getAllTodos();
      final index = todos.indexWhere((t) => t.id == todoId);

      if (index < 0) return false;

      final todo = todos[index];
      if (subtaskIndex >= todo.subtaskCompleted.length) return false;

      final newCompleted = List<bool>.from(todo.subtaskCompleted);
      newCompleted[subtaskIndex] = !newCompleted[subtaskIndex];
      todos[index] = todo.copyWith(subtaskCompleted: newCompleted);
      
      return await _saveTodosToBox(box, todos);
    } catch (e) {
      debugPrint('TodoStorageService: Error toggling subtask: $e');
      return false;
    }
  }

  /// Clear all completed todos
  Future<bool> clearCompletedTodos() async {
    try {
      final box = await _getBox();
      final todos = await getAllTodos();

      final initialLength = todos.length;
      todos.removeWhere((t) => t.isCompleted);
      
      if (todos.length < initialLength) {
        final success = await _saveTodosToBox(box, todos);
        if (success) {
          debugPrint('TodoStorageService: Cleared ${initialLength - todos.length} completed todos');
          await _updateHomeWidget();
        }
        return success;
      }
      return true;
    } catch (e) {
      debugPrint('TodoStorageService: Error clearing completed todos: $e');
      return false;
    }
  }

  /// Clear all todos
  Future<bool> clearAllTodos() async {
    try {
      final box = await _getBox();
      await box.delete(_todosKey);
      await _updateHomeWidget();
      debugPrint('TodoStorageService: Cleared all todos');
      return true;
    } catch (e) {
      debugPrint('TodoStorageService: Error clearing all todos: $e');
      return false;
    }
  }

  /// Save todos list to storage box
  Future<bool> _saveTodosToBox(Box box, List<TodoItem> todos) async {
    try {
      final todosJson = todos.map((t) => t.toEncodedJson()).toList();
      await box.put(_todosKey, todosJson);
      debugPrint('TodoStorageService: Saved ${todos.length} todos');
      return true;
    } catch (e) {
      debugPrint('TodoStorageService: Error saving todos to box: $e');
      return false;
    }
  }
  
  /// Update home widget with current todos
  Future<void> _updateHomeWidget() async {
    try {
      // Get all todos sorted (incomplete first, then completed)
      final allTodos = await getTodosSorted(showCompleted: true);
      
      // Sort: incomplete first, then completed
      allTodos.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return 0;
      });
      
      final todosToShow = allTodos.take(5).toList();
      final incompleteCount = allTodos.where((t) => !t.isCompleted).length;
      
      final todoTitles = todosToShow.map((t) => t.title).toList();
      final todoIds = todosToShow.map((t) => t.id).toList();
      final todoCompleted = todosToShow.map((t) => t.isCompleted ? '1' : '0').toList();
      
      await HomeWidget.saveWidgetData('todo_titles', todoTitles.join('|||'));
      await HomeWidget.saveWidgetData('todo_ids', todoIds.join('|||'));
      await HomeWidget.saveWidgetData('todo_completed', todoCompleted.join('|||'));
      await HomeWidget.saveWidgetData('todo_count', incompleteCount.toString());
      
      await HomeWidget.updateWidget(
        name: 'GhosttyTodoWidgetProvider',
        androidName: 'GhosttyTodoWidgetProvider',
        iOSName: 'GhosttyTodoWidget',
      );
      debugPrint('TodoStorageService: Widget updated with ${todosToShow.length} todos ($incompleteCount incomplete)');
    } catch (e) {
      debugPrint('TodoStorageService: Failed to update widget: $e');
    }
  }

  /// Get todos sorted by due date
  Future<List<TodoItem>> getTodosSorted({
    bool showCompleted = true,
    bool ascending = true,
  }) async {
    var todos = await getAllTodos();

    if (!showCompleted) {
      todos = todos.where((t) => !t.isCompleted).toList();
    }

    todos.sort((a, b) {
      // Completed items go to bottom
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }

      // Sort by due date
      if (a.dueDate == null && b.dueDate == null) {
        return b.createdAt.compareTo(a.createdAt);
      }
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;

      final comparison = a.dueDate!.compareTo(b.dueDate!);
      return ascending ? comparison : -comparison;
    });

    return todos;
  }

  /// Get todos grouped by date
  Future<Map<String, List<TodoItem>>> getTodosGroupedByDate() async {
    final todos = await getTodosSorted(showCompleted: false);
    final grouped = <String, List<TodoItem>>{};
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final todo in todos) {
      String key;
      if (todo.isOverdue) {
        key = 'Overdue';
      } else if (todo.dueDate == null) {
        key = 'No Date';
      } else {
        final dueDay = DateTime(todo.dueDate!.year, todo.dueDate!.month, todo.dueDate!.day);
        if (dueDay == today) {
          key = 'Today';
        } else if (dueDay == today.add(const Duration(days: 1))) {
          key = 'Tomorrow';
        } else {
          key = '${todo.dueDate!.day}/${todo.dueDate!.month}/${todo.dueDate!.year}';
        }
      }

      grouped.putIfAbsent(key, () => []).add(todo);
    }

    return grouped;
  }

  /// Force refresh widget
  Future<void> refreshWidget() async {
    await _updateHomeWidget();
  }
}
