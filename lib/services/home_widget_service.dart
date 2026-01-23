import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/todo_item.dart';
import 'todo_storage_service.dart';

/// Background callback for handling widget interactions
@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null) return;

  debugPrint('HomeWidget: Background callback received: $uri');

  if (uri.host == 'toggle_todo') {
    final todoId = uri.queryParameters['id'];
    if (todoId != null && todoId.isNotEmpty) {
      debugPrint('HomeWidget: Toggling todo: $todoId');

      try {
        // Initialize Hive for background isolate
        try {
          await Hive.initFlutter();
        } catch (_) {}

        // Open the todos box directly
        Box box;
        try {
          box = await Hive.openBox('todos_box');
        } catch (_) {
          box = Hive.box('todos_box');
        }

        // Read todos directly (no encryption in background for simplicity)
        final dynamic rawData = box.get('todos_list');
        if (rawData == null) {
          debugPrint('HomeWidget: No todos found');
          return;
        }

        final List<dynamic> todosList = rawData as List<dynamic>;
        final todos = <TodoItem>[];
        
        for (final item in todosList) {
          try {
            if (item is String) {
              todos.add(TodoItem.fromEncodedJson(item));
            }
          } catch (e) {
            debugPrint('HomeWidget: Error parsing todo: $e');
          }
        }

        // Find and toggle the todo
        final index = todos.indexWhere((t) => t.id == todoId);
        if (index >= 0) {
          final todo = todos[index];
          final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);
          todos[index] = updatedTodo;

          // Save back
          final todosJson = todos.map((t) => t.toEncodedJson()).toList();
          await box.put('todos_list', todosJson);
          
          debugPrint('HomeWidget: Toggled ${todo.title} -> ${updatedTodo.isCompleted}');

          // Update widget data
          // Sort: incomplete first, then completed
          todos.sort((a, b) {
            if (a.isCompleted != b.isCompleted) {
              return a.isCompleted ? 1 : -1;
            }
            return 0;
          });
          
          final todosToShow = todos.take(5).toList();
          final incompleteCount = todos.where((t) => !t.isCompleted).length;
          
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
          
          debugPrint('HomeWidget: Widget updated with ${todosToShow.length} todos');
        } else {
          debugPrint('HomeWidget: Todo not found: $todoId');
        }
      } catch (e) {
        debugPrint('HomeWidget: Background toggle error: $e');
      }
    }
  }
}

class HomeWidgetService {
  static const String appGroupId = 'group.com.ghostty.todos';
  static const String androidWidgetName = 'GhosttyTodoWidgetProvider';
  static const String iOSWidgetName = 'GhosttyTodoWidget';

  static final HomeWidgetService _instance = HomeWidgetService._internal();
  factory HomeWidgetService() => _instance;
  HomeWidgetService._internal();

  bool _isInitialized = false;

  /// Initialize the home widget service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      HomeWidget.setAppGroupId(appGroupId);

      // Register background callback for widget interactions
      HomeWidget.registerInteractivityCallback(backgroundCallback);

      // Listen to widget clicks when app is in foreground
      HomeWidget.widgetClicked.listen(_handleWidgetClicked);

      // Initial update
      await updateWidget();
      _isInitialized = true;
      debugPrint('HomeWidget: Initialized');
    } catch (e) {
      debugPrint('HomeWidget: Init failed: $e');
    }
  }

  /// Handle widget click events when app is in foreground
  void _handleWidgetClicked(Uri? uri) {
    if (uri == null) return;

    debugPrint('HomeWidget: Clicked: $uri');

    if (uri.host == 'toggle_todo') {
      final todoId = uri.queryParameters['id'];
      if (todoId != null) {
        _toggleTodo(todoId);
      }
    }
  }

  Future<void> _toggleTodo(String todoId) async {
    try {
      final todoStorage = TodoStorageService();
      await todoStorage.initialize();
      await todoStorage.toggleTodoCompletion(todoId);
      await updateWidget();
      debugPrint('HomeWidget: Toggled $todoId');
    } catch (e) {
      debugPrint('HomeWidget: Toggle error: $e');
    }
  }

  /// Update the home widget with latest todos
  Future<void> updateWidget() async {
    try {
      final todoStorage = TodoStorageService();
      await todoStorage.initialize();

      // Get all todos (both complete and incomplete) sorted
      final allTodos = await todoStorage.getTodosSorted(showCompleted: true);
      
      // Sort: incomplete first, then completed
      allTodos.sort((a, b) {
        if (a.isCompleted != b.isCompleted) {
          return a.isCompleted ? 1 : -1;
        }
        return 0;
      });
      
      final todosToShow = allTodos.take(5).toList();
      final incompleteCount = allTodos.where((t) => !t.isCompleted).length;

      // Prepare data for widget (titles, IDs, and completion status)
      final todoTitles = todosToShow.map((t) => t.title).toList();
      final todoIds = todosToShow.map((t) => t.id).toList();
      final todoCompleted = todosToShow.map((t) => t.isCompleted ? '1' : '0').toList();

      // Save data for widget
      await HomeWidget.saveWidgetData('todo_titles', todoTitles.join('|||'));
      await HomeWidget.saveWidgetData('todo_ids', todoIds.join('|||'));
      await HomeWidget.saveWidgetData('todo_completed', todoCompleted.join('|||'));
      await HomeWidget.saveWidgetData('todo_count', incompleteCount.toString());

      // Update the widget
      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );

      debugPrint('HomeWidget: Updated with ${todosToShow.length} todos ($incompleteCount incomplete)');
    } catch (e) {
      debugPrint('HomeWidget: Update failed: $e');
    }
  }

  /// Update widget when a todo changes
  Future<void> onTodoChanged() async {
    await updateWidget();
  }
}
