import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/todo_item.dart';
import '../services/todo_storage_service.dart';
import '../widgets/custom_modal.dart';

class TodoEditorScreen extends StatefulWidget {
  final TodoItem? existingTodo;

  const TodoEditorScreen({super.key, this.existingTodo});

  @override
  State<TodoEditorScreen> createState() => _TodoEditorScreenState();
}

class _TodoEditorScreenState extends State<TodoEditorScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _todoStorage = TodoStorageService();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _isEditing = false;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.existingTodo != null;

    if (_isEditing) {
      final todo = widget.existingTodo!;
      _titleController.text = todo.title;
      _descriptionController.text = todo.description ?? '';
      _selectedDate = todo.dueDate;
      _selectedTime = todo.dueTime != null
          ? TimeOfDay(hour: todo.dueTime!.hour, minute: todo.dueTime!.minute)
          : null;
    }

    _titleController.addListener(_onChanged);
    _descriptionController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Color _getTextColor() {
    return Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87;
  }

  Color _getHintColor() {
    return Theme.of(context).brightness == Brightness.dark ? Colors.white60 : Colors.black45;
  }

  Future<void> _saveTodo() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter a title')));
      return;
    }

    DateTime? dueTime;
    if (_selectedTime != null && _selectedDate != null) {
      dueTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
    }

    final todo = TodoItem(
      id: widget.existingTodo?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      createdAt: widget.existingTodo?.createdAt ?? DateTime.now(),
      dueDate: _selectedDate,
      dueTime: dueTime,
      isCompleted: widget.existingTodo?.isCompleted ?? false,
      backgroundColor: null,
      priority: TodoPriority.normal,
      hasReminder: false,
      subtasks: [],
      subtaskCompleted: [],
    );

    final success = await _todoStorage.saveTodo(todo);

    if (mounted) {
      if (success) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to save todo. Please try again.'),
          ),
        );
      }
    }
  }

  Future<void> _deleteTodo() async {
    if (widget.existingTodo == null) return;

    final confirmed = await GhostModal.show(
      context: context,
      title: 'Delete Todo',
      message:
          'Are you sure you want to delete this todo? This action cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );

    if (confirmed == true) {
      await _todoStorage.deleteTodo(widget.existingTodo!.id);
      if (mounted) {
        HapticFeedback.mediumImpact();
        Navigator.pop(context, true);
      }
    }
  }

  void _showDatePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _CustomCalendarPicker(
        selectedDate: _selectedDate,
        onDateSelected: (date) {
          setState(() {
            _selectedDate = date;
            _hasChanges = true;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showTimePicker() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (time != null) {
      // Validate time is not in the past for today
      if (_selectedDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final selectedDay = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day);
        
        if (selectedDay == today) {
          final selectedDateTime = DateTime(
            _selectedDate!.year,
            _selectedDate!.month,
            _selectedDate!.day,
            time.hour,
            time.minute,
          );
          if (selectedDateTime.isBefore(now)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cannot set a time in the past')),
              );
            }
            return;
          }
        }
      }
      
      setState(() {
        _selectedTime = time;
        _hasChanges = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = _getTextColor();
    final hintColor = _getHintColor();

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: textColor),
              onPressed: _deleteTodo,
            ),
          TextButton(
            onPressed: _saveTodo,
            child: Text(
              'Save',
              style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title field
            TextField(
              controller: _titleController,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Title',
                hintStyle: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: hintColor,
                ),
                border: InputBorder.none,
              ),
              maxLines: null,
            ),
            const SizedBox(height: 8),

            // Description field
            TextField(
              controller: _descriptionController,
              style: TextStyle(fontSize: 16, color: textColor),
              decoration: InputDecoration(
                hintText: 'Add notes...',
                hintStyle: TextStyle(color: hintColor),
                border: InputBorder.none,
              ),
              maxLines: null,
            ),
            const SizedBox(height: 24),

            // Date & Time section
            _buildSectionTitle('Schedule', textColor),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildOptionChip(
                    icon: Icons.calendar_today,
                    label: _selectedDate != null
                        ? _formatDate(_selectedDate!)
                        : 'Add date',
                    isSelected: _selectedDate != null,
                    onTap: _showDatePicker,
                    onClear: _selectedDate != null
                        ? () => setState(() {
                            _selectedDate = null;
                            _selectedTime = null;
                            _hasChanges = true;
                          })
                        : null,
                    textColor: textColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildOptionChip(
                    icon: Icons.access_time,
                    label: _selectedTime != null
                        ? _formatTime(_selectedTime!)
                        : 'Add time',
                    isSelected: _selectedTime != null,
                    onTap: _selectedDate != null ? _showTimePicker : null,
                    onClear: _selectedTime != null
                        ? () => setState(() {
                            _selectedTime = null;
                            _hasChanges = true;
                          })
                        : null,
                    textColor: textColor,
                    enabled: _selectedDate != null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: textColor.withOpacity(0.7),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildOptionChip({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback? onTap,
    VoidCallback? onClear,
    required Color textColor,
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? textColor.withOpacity(0.1) : Colors.transparent,
          border: Border.all(
            color: enabled
                ? textColor.withOpacity(0.3)
                : textColor.withOpacity(0.1),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled ? textColor : textColor.withOpacity(0.3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: enabled ? textColor : textColor.withOpacity(0.3),
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: textColor),
              ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateDay = DateTime(date.year, date.month, date.day);

    if (dateDay == today) return 'Today';
    if (dateDay == today.add(const Duration(days: 1))) return 'Tomorrow';
    if (dateDay == today.subtract(const Duration(days: 1))) return 'Yesterday';

    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}

/// Custom Calendar Picker Widget
class _CustomCalendarPicker extends StatefulWidget {
  final DateTime? selectedDate;
  final Function(DateTime) onDateSelected;

  const _CustomCalendarPicker({
    this.selectedDate,
    required this.onDateSelected,
  });

  @override
  State<_CustomCalendarPicker> createState() => _CustomCalendarPickerState();
}

class _CustomCalendarPickerState extends State<_CustomCalendarPicker> {
  late DateTime _currentMonth;
  late DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.selectedDate;
    _currentMonth = _selectedDate ?? DateTime.now();
  }

  /// Check if we can navigate to the previous month (must have at least today or future dates)
  bool _canNavigateToPreviousMonth() {
    final now = DateTime.now();
    final previousMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    // Allow if the previous month is the current month or later
    return previousMonth.year > now.year ||
        (previousMonth.year == now.year && previousMonth.month >= now.month);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white54 : Colors.black45;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Quick options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildQuickOption('Today', DateTime.now(), textColor),
              _buildQuickOption(
                'Tomorrow',
                DateTime.now().add(const Duration(days: 1)),
                textColor,
              ),
              _buildQuickOption(
                'Next Week',
                DateTime.now().add(const Duration(days: 7)),
                textColor,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: hintColor.withOpacity(0.2)),
          const SizedBox(height: 16),

          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.chevron_left, color: _canNavigateToPreviousMonth() ? textColor : hintColor.withOpacity(0.3)),
                onPressed: _canNavigateToPreviousMonth() ? () {
                  setState(() {
                    _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month - 1,
                    );
                  });
                } : null,
              ),
              Text(
                _getMonthName(_currentMonth.month) + ' ${_currentMonth.year}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              IconButton(
                icon: Icon(Icons.chevron_right, color: textColor),
                onPressed: () {
                  setState(() {
                    _currentMonth = DateTime(
                      _currentMonth.year,
                      _currentMonth.month + 1,
                    );
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekday headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (day) => SizedBox(
                    width: 40,
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          color: hintColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),

          // Calendar grid
          _buildCalendarGrid(textColor, hintColor, isDark),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildQuickOption(String label, DateTime date, Color textColor) {
    final isSelected =
        _selectedDate != null &&
        _selectedDate!.year == date.year &&
        _selectedDate!.month == date.month &&
        _selectedDate!.day == date.day;

    return GestureDetector(
      onTap: () {
        widget.onDateSelected(date);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.transparent,
          border: Border.all(
            color: isSelected ? Colors.blue : textColor.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.blue : textColor,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(Color textColor, Color hintColor, bool isDark) {
    final firstDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month,
      1,
    );
    final lastDayOfMonth = DateTime(
      _currentMonth.year,
      _currentMonth.month + 1,
      0,
    );
    final firstWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = lastDayOfMonth.day;

    final today = DateTime.now();
    final todayDay = DateTime(today.year, today.month, today.day);

    List<Widget> dayWidgets = [];

    // Empty cells for days before the first day of month
    for (int i = 0; i < firstWeekday; i++) {
      dayWidgets.add(const SizedBox(width: 40, height: 40));
    }

    // Day cells
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_currentMonth.year, _currentMonth.month, day);
      final dateDay = DateTime(date.year, date.month, date.day);
      final isSelected =
          _selectedDate != null &&
          _selectedDate!.year == date.year &&
          _selectedDate!.month == date.month &&
          _selectedDate!.day == date.day;
      final isToday = dateDay == todayDay;
      final isPast = dateDay.isBefore(todayDay);

      dayWidgets.add(
        GestureDetector(
          onTap: isPast ? null : () {
            widget.onDateSelected(date);
          },
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.blue
                  : isToday
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: Colors.blue)
                  : null,
            ),
            child: Center(
              child: Text(
                day.toString(),
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isPast
                      ? hintColor.withOpacity(0.4)
                      : textColor,
                  fontWeight: isSelected || isToday
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: (MediaQuery.of(context).size.width - 40 - 280) / 6,
      runSpacing: 8,
      children: dayWidgets,
    );
  }

  String _getMonthName(int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months[month - 1];
  }
}
