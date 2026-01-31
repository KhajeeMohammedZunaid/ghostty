import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/animation_prefs.dart';
import '../../theme/ghost_theme.dart';
import '../journal/journal_list_screen.dart';
import '../journal/journal_editor_screen.dart';
import '../settings/settings_screen.dart';
import '../todo_list_screen.dart';
import '../todo_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;
  bool _shouldAnimate = true;
  bool _isFabExpanded = false;
  final _journalListKey = GlobalKey<JournalListScreenState>();

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _shouldAnimate = AnimationPrefs.shouldAnimateHome();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onTabSelected(int index) {
    final wasOnSettings = _currentIndex == 1;
    setState(() {
      _currentIndex = index;
      _isFabExpanded = false;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    // Refresh journal list when switching back from settings
    if (index == 0 && wasOnSettings) {
      _journalListKey.currentState?.refreshEntries();
    }
  }

  void _toggleFab() {
    HapticFeedback.lightImpact();
    setState(() => _isFabExpanded = !_isFabExpanded);
  }

  void _openJournalEditor() {
    setState(() => _isFabExpanded = false);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const JournalEditorScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    ).then((_) {
      // Refresh the journal list if we're on that screen
      if (_currentIndex == 0) {
        _journalListKey.currentState?.refreshEntries();
      }
    });
  }

  void _openTodoEditor() {
    setState(() => _isFabExpanded = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TodoEditorScreen()),
    );
  }

  void _openTodoList() {
    setState(() => _isFabExpanded = false);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TodoListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              JournalListScreen(key: _journalListKey, showFab: false),
              const SettingsScreen(),
            ],
          ),
          // Overlay when FAB is expanded
          if (_isFabExpanded)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isFabExpanded = false),
                child: Container(color: Colors.black.withOpacity(0.5)),
              ),
            ),
        ],
      ),
      // Only show FAB on Journal tab (index 0), not on Settings
      floatingActionButton: _currentIndex == 0
          ? _buildExpandableFab(isDark)
          : null,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? GhostTheme.darkSurface : GhostTheme.lightSurface,
          border: Border(
            top: BorderSide(
              color: isDark ? GhostTheme.darkBorder : GhostTheme.lightBorder,
            ),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.book_outlined,
                  selectedIcon: Icons.book_rounded,
                  label: 'Journal',
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final item = GestureDetector(
      onTap: () => _onTabSelected(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : theme.textTheme.bodySmall?.color,
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (!_shouldAnimate) return item;

    return item
        .animate(target: isSelected ? 1 : 0)
        .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }

  Widget _buildExpandableFab(bool isDark) {
    final primaryColor = isDark ? Colors.white : Colors.black;
    final onPrimaryColor = isDark ? Colors.black : Colors.white;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Expanded options
        if (_isFabExpanded) ...[
          // View Todos option
          _buildFabOption(
            label: 'View Todos',
            icon: Icons.checklist_rounded,
            onTap: _openTodoList,
            primaryColor: primaryColor,
            onPrimaryColor: onPrimaryColor,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          // New Todo option
          _buildFabOption(
            label: 'New Todo',
            icon: Icons.check_circle_outline_rounded,
            onTap: _openTodoEditor,
            primaryColor: primaryColor,
            onPrimaryColor: onPrimaryColor,
            isDark: isDark,
          ),
          const SizedBox(height: 12),
          // New Journal option
          _buildFabOption(
            label: 'New Journal',
            icon: Icons.edit_note_rounded,
            onTap: _openJournalEditor,
            primaryColor: primaryColor,
            onPrimaryColor: onPrimaryColor,
            isDark: isDark,
          ),
          const SizedBox(height: 16),
        ],
        // Main FAB
        FloatingActionButton(
          onPressed: _toggleFab,
          backgroundColor: primaryColor,
          child: AnimatedRotation(
            turns: _isFabExpanded ? 0.125 : 0,
            duration: const Duration(milliseconds: 200),
            child: Icon(
              Icons.add_rounded,
              color: const Color(0xFF4CAF50), // Green color for add icon
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFabOption({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required Color primaryColor,
    required Color onPrimaryColor,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: onPrimaryColor),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 150.ms).slideX(begin: 0.2, end: 0);
  }
}
