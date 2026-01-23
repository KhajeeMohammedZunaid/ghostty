import 'package:home_widget/home_widget.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/todo_item.dart';
import 'todo_storage_service.dart';

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri == null) return;

  if (uri.host == 'toggle_todo') {
    final todoId = uri.queryParameters['id'];
    if (todoId != null && todoId.isNotEmpty) {
      try {
        try {
          await Hive.initFlutter();
        } catch (_) {}

        Box box;
        try {
          box = await Hive.openBox('todos_box');
        } catch (_) {
          box = Hive.box('todos_box');
        }

        final dynamic rawData = box.get('todos_list');
        if (rawData == null) return;

        final List<dynamic> todosList = rawData as List<dynamic>;
        final todos = <TodoItem>[];

        for (final item in todosList) {
          try {
            if (item is String) {
              todos.add(TodoItem.fromEncodedJson(item));
            }
          } catch (_) {}
        }

        final index = todos.indexWhere((t) => t.id == todoId);
        if (index >= 0) {
          final todo = todos[index];
          final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);
          todos[index] = updatedTodo;

          final todosJson = todos.map((t) => t.toEncodedJson()).toList();
          await box.put('todos_list', todosJson);

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
          final todoCompleted = todosToShow
              .map((t) => t.isCompleted ? '1' : '0')
              .toList();

          await HomeWidget.saveWidgetData(
            'todo_titles',
            todoTitles.join('|||'),
          );
          await HomeWidget.saveWidgetData('todo_ids', todoIds.join('|||'));
          await HomeWidget.saveWidgetData(
            'todo_completed',
            todoCompleted.join('|||'),
          );
          await HomeWidget.saveWidgetData(
            'todo_count',
            incompleteCount.toString(),
          );

          await HomeWidget.updateWidget(
            name: 'GhosttyTodoWidgetProvider',
            androidName: 'GhosttyTodoWidgetProvider',
            iOSName: 'GhosttyTodoWidget',
          );
        }
      } catch (_) {}
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

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      HomeWidget.setAppGroupId(appGroupId);
      HomeWidget.registerInteractivityCallback(backgroundCallback);
      HomeWidget.widgetClicked.listen(_handleWidgetClicked);
      await updateWidget();
      _isInitialized = true;
    } catch (_) {}
  }

  void _handleWidgetClicked(Uri? uri) {
    if (uri == null) return;

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
    } catch (_) {}
  }

  Future<void> updateWidget() async {
    try {
      final todoStorage = TodoStorageService();
      await todoStorage.initialize();

      final allTodos = await todoStorage.getTodosSorted(showCompleted: true);

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
      final todoCompleted = todosToShow
          .map((t) => t.isCompleted ? '1' : '0')
          .toList();

      await HomeWidget.saveWidgetData('todo_titles', todoTitles.join('|||'));
      await HomeWidget.saveWidgetData('todo_ids', todoIds.join('|||'));
      await HomeWidget.saveWidgetData(
        'todo_completed',
        todoCompleted.join('|||'),
      );
      await HomeWidget.saveWidgetData('todo_count', incompleteCount.toString());

      await HomeWidget.updateWidget(
        name: androidWidgetName,
        androidName: androidWidgetName,
        iOSName: iOSWidgetName,
      );
    } catch (_) {}
  }

  Future<void> onTodoChanged() async {
    await updateWidget();
  }
}
