import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/todo_item.dart';
import '../services/todo_storage_service.dart';
import '../widgets/custom_modal.dart';
import 'todo_editor_screen.dart';

class TodoListScreen extends StatefulWidget {
  const TodoListScreen({super.key});

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen>
    with SingleTickerProviderStateMixin {
  final TodoStorageService _todoStorage = TodoStorageService();
  List<TodoItem> _todos = [];
  bool _showCompleted = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTodos();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);
    final todos = await _todoStorage.getTodosSorted(
      showCompleted: _showCompleted,
    );
    setState(() {
      _todos = todos;
      _isLoading = false;
    });
  }

  Future<void> _toggleComplete(TodoItem todo) async {
    HapticFeedback.lightImpact();
    final success = await _todoStorage.toggleTodoCompletion(todo.id);
    if (success) {
      await _loadTodos();
      if (mounted) {
        final message = todo.isCompleted
            ? 'Todo marked incomplete'
            : 'Todo completed!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to update todo')));
    }
  }

  Future<void> _deleteTodo(TodoItem todo) async {
    final confirmed = await GhostModal.show(
      context: context,
      title: 'Delete Todo',
      message:
          'Are you sure you want to delete "${todo.title}"? This action cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );

    if (confirmed == true) {
      final success = await _todoStorage.deleteTodo(todo.id);
      if (success) {
        HapticFeedback.mediumImpact();
        await _loadTodos();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${todo.title}" deleted'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to delete todo')));
      }
    }
  }

  Future<void> _openEditor([TodoItem? todo]) async {
    final isEditing = todo != null;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TodoEditorScreen(existingTodo: todo),
      ),
    );

    if (result == true) {
      await _loadTodos();
      if (mounted) {
        final message = isEditing ? 'Todo updated!' : 'Todo created!';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white60 : Colors.black45;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Todos',
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showCompleted ? Icons.visibility : Icons.visibility_off,
              color: textColor,
            ),
            tooltip: _showCompleted ? 'Hide completed' : 'Show completed',
            onPressed: () {
              setState(() => _showCompleted = !_showCompleted);
              _loadTodos();
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: textColor),
            onSelected: (value) async {
              if (value == 'clear_completed') {
                final confirmed = await GhostModal.show(
                  context: context,
                  title: 'Clear Completed',
                  message: 'Remove all completed todos? This cannot be undone.',
                  confirmText: 'Clear',
                  cancelText: 'Cancel',
                  icon: Icons.delete_sweep_rounded,
                  isDangerous: true,
                );
                if (confirmed == true) {
                  final success = await _todoStorage.clearCompletedTodos();
                  if (success) {
                    HapticFeedback.mediumImpact();
                    await _loadTodos();
                  } else if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Failed to clear completed todos'),
                      ),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_completed',
                child: Text('Clear completed'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _todos.isEmpty
          ? _buildEmptyState(textColor, hintColor)
          : _buildTodoList(textColor, hintColor, isDark),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: isDark ? Colors.white : Colors.black,
        child: Icon(Icons.add, color: isDark ? Colors.black : Colors.white),
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color hintColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _showCompleted ? Icons.inbox_outlined : Icons.celebration_outlined,
            size: 80,
            color: hintColor.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            _showCompleted ? 'Your list is empty' : "You're all caught up!",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _showCompleted
                ? 'Create your first todo by tapping +'
                : 'No pending tasks. Time to relax!',
            style: TextStyle(color: hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoList(Color textColor, Color hintColor, bool isDark) {
    // Group todos
    final overdue = <TodoItem>[];
    final today = <TodoItem>[];
    final upcoming = <TodoItem>[];
    final noDate = <TodoItem>[];
    final completed = <TodoItem>[];

    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    for (final todo in _todos) {
      if (todo.isCompleted) {
        completed.add(todo);
      } else if (todo.isOverdue) {
        overdue.add(todo);
      } else if (todo.dueDate == null) {
        noDate.add(todo);
      } else {
        final dueDay = DateTime(
          todo.dueDate!.year,
          todo.dueDate!.month,
          todo.dueDate!.day,
        );
        if (dueDay == todayDate) {
          today.add(todo);
        } else {
          upcoming.add(todo);
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        if (overdue.isNotEmpty)
          _buildSection(
            'Overdue',
            overdue,
            Colors.red,
            textColor,
            hintColor,
            isDark,
          ),
        if (today.isNotEmpty)
          _buildSection(
            'Today',
            today,
            Colors.blue,
            textColor,
            hintColor,
            isDark,
          ),
        if (upcoming.isNotEmpty)
          _buildSection(
            'Upcoming',
            upcoming,
            Colors.green,
            textColor,
            hintColor,
            isDark,
          ),
        if (noDate.isNotEmpty)
          _buildSection(
            'No date',
            noDate,
            hintColor,
            textColor,
            hintColor,
            isDark,
          ),
        if (completed.isNotEmpty && _showCompleted)
          _buildSection(
            'Completed',
            completed,
            hintColor,
            textColor,
            hintColor,
            isDark,
          ),
        const SizedBox(height: 80), // Space for FAB
      ],
    );
  }

  Widget _buildSection(
    String title,
    List<TodoItem> todos,
    Color accentColor,
    Color textColor,
    Color hintColor,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${todos.length}',
                style: TextStyle(fontSize: 14, color: hintColor),
              ),
            ],
          ),
        ),
        ...todos.map(
          (todo) => _buildTodoItem(todo, textColor, hintColor, isDark),
        ),
      ],
    );
  }

  Widget _buildTodoItem(
    TodoItem todo,
    Color textColor,
    Color hintColor,
    bool isDark,
  ) {
    final bgColor = todo.backgroundColor != null
        ? Color(todo.backgroundColor!)
        : (isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5));
    final isItemDark = todo.backgroundColor != null
        ? Color(todo.backgroundColor!).computeLuminance() < 0.5
        : isDark;
    final itemTextColor = isItemDark ? Colors.white : Colors.black87;
    final itemHintColor = isItemDark ? Colors.white60 : Colors.black45;

    return Dismissible(
      key: Key(todo.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final confirmed = await GhostModal.show(
          context: context,
          title: 'Delete Todo',
          message:
              'Are you sure you want to delete "${todo.title}"? This action cannot be undone.',
          confirmText: 'Delete',
          cancelText: 'Cancel',
          icon: Icons.delete_forever_rounded,
          isDangerous: true,
        );
        return confirmed == true;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (direction) async {
        await _todoStorage.deleteTodo(todo.id);
        HapticFeedback.mediumImpact();
        await _loadTodos();
      },
      child: GestureDetector(
        onTap: () => _openEditor(todo),
        onLongPress: () => _deleteTodo(todo),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            border: todo.isOverdue
                ? Border.all(color: Colors.red.withOpacity(0.5), width: 1)
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox
              GestureDetector(
                onTap: () => _toggleComplete(todo),
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: todo.isCompleted ? Colors.green : itemHintColor,
                      width: 2,
                    ),
                    color: todo.isCompleted ? Colors.green : Colors.transparent,
                  ),
                  child: todo.isCompleted
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: itemTextColor,
                        decoration: todo.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (todo.description != null &&
                        todo.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        todo.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: itemHintColor,
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (todo.dueDate != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 14,
                            color: todo.isOverdue ? Colors.red : itemHintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            todo.formattedDueDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: todo.isOverdue
                                  ? Colors.red
                                  : itemHintColor,
                            ),
                          ),
                          if (todo.hasReminder) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.notifications_active,
                              size: 14,
                              color: itemHintColor,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
