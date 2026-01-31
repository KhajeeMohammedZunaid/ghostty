import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/journal_entry.dart';
import '../../services/storage_service.dart';
import '../../services/encryption_service.dart';
import '../../services/animation_prefs.dart';
import '../../services/update_service.dart';
import '../../theme/ghost_theme.dart';
import '../../widgets/custom_modal.dart';
import 'journal_editor_screen.dart';

class JournalListScreen extends StatefulWidget {
  final bool showFab;

  const JournalListScreen({super.key, this.showFab = true});

  @override
  JournalListScreenState createState() => JournalListScreenState();
}

class JournalListScreenState extends State<JournalListScreen> {
  List<JournalEntry> _entries = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showSearch = false;
  bool _shouldAnimate = true;
  bool _isGridView = true; // Default to grid view

  @override
  void initState() {
    super.initState();
    _shouldAnimate = AnimationPrefs.shouldAnimateJournalList();
    _loadEntries(showLoading: true);
    _checkForUpdates();
  }

  /// Check for updates silently in background
  Future<void> _checkForUpdates() async {
    final updateInfo = await UpdateService.instance.checkForUpdate();
    if (updateInfo != null && mounted) {
      UpdateService.instance.showUpdateSnackBar(context, updateInfo);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadEntries({bool showLoading = false}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      final entries = await StorageService.instance.getAllJournalEntries();
      if (mounted) {
        setState(() {
          _entries = entries;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Public method to refresh entries - called by parent screens
  void refreshEntries() {
    _loadEntries();
  }

  List<JournalEntry> get _filteredEntries {
    List<JournalEntry> result;
    if (_searchQuery.isEmpty) {
      result = _entries;
    } else {
      final query = _searchQuery.toLowerCase();
      result = _entries.where((entry) {
        return entry.title.toLowerCase().contains(query) ||
            entry.plainTextContent.toLowerCase().contains(query) ||
            entry.tags.any((tag) => tag.toLowerCase().contains(query));
      }).toList();
    }
    // Sort: pinned first, then by date
    result.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return result;
  }

  Future<void> _deleteEntry(JournalEntry entry) async {
    final confirm = await GhostModal.show(
      context: context,
      title: 'Delete Entry',
      message:
          'Are you sure you want to delete this entry? This action cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );

    if (confirm == true) {
      // Optimistic UI update - remove immediately
      setState(() => _entries.removeWhere((e) => e.id == entry.id));
      await StorageService.instance.deleteJournalEntry(entry.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Entry deleted'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  void _openEditor([JournalEntry? entry]) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            JournalEditorScreen(entry: entry),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 150),
      ),
    ).then((_) {
      // Refresh in background without blocking UI
      _loadEntries();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search entries...',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (value) => setState(() => _searchQuery = value),
              )
            : Text(
                'Journal',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _showSearch ? Icons.close_rounded : Icons.search_rounded,
            ),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  _searchQuery = '';
                }
              });
            },
          ),
          if (!_showSearch)
            IconButton(
              icon: Icon(
                _isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
              ),
              onPressed: () => setState(() => _isGridView = !_isGridView),
              tooltip: _isGridView ? 'List view' : 'Grid view',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredEntries.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _loadEntries,
              color: GhostTheme.primary,
              child: _isGridView ? _buildGridView() : _buildListView(),
            ),
      floatingActionButton: widget.showFab
          ? FloatingActionButton(
              onPressed: () => _openEditor(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
    );
  }

  Widget _buildGridView() {
    // Use a custom masonry-style layout with wrap
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
          final cardWidth =
              (constraints.maxWidth - (crossAxisCount - 1) * 12) /
              crossAxisCount;

          // Split entries into columns
          final columns = List.generate(crossAxisCount, (_) => <_CardData>[]);
          final columnHeights = List.filled(crossAxisCount, 0.0);

          for (int i = 0; i < _filteredEntries.length; i++) {
            final entry = _filteredEntries[i];
            final cardHeight = _calculateCardHeight(entry, cardWidth);

            // Find shortest column
            int shortestCol = 0;
            for (int j = 1; j < crossAxisCount; j++) {
              if (columnHeights[j] < columnHeights[shortestCol]) {
                shortestCol = j;
              }
            }

            columns[shortestCol].add(_CardData(entry, i));
            columnHeights[shortestCol] += cardHeight + 12; // 12 for spacing
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(crossAxisCount, (colIndex) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: colIndex == 0 ? 0 : 6,
                    right: colIndex == crossAxisCount - 1 ? 0 : 6,
                  ),
                  child: Column(
                    children: columns[colIndex].map((data) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildGridCard(data.entry, data.index),
                      );
                    }).toList(),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  double _calculateCardHeight(JournalEntry entry, double cardWidth) {
    // Base height for mood, date, padding
    double height = 60;

    // Title height (rough estimate)
    if (entry.title.isNotEmpty) {
      final titleLines = (entry.title.length / 20).ceil().clamp(1, 2);
      height += titleLines * 24 + 6;
    }

    // Content height
    final contentLength = entry.plainTextContent.length;
    if (contentLength > 0) {
      final maxLines = contentLength > 200 ? 6 : (contentLength > 100 ? 4 : 3);
      height += maxLines * 18;
    }

    // Attachments indicator
    if (entry.hasAttachments) {
      height += 30;
    }

    // Tags height
    if (entry.tags.isNotEmpty) {
      height += 32;
    }

    return height;
  }

  Widget _buildListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredEntries.length,
      itemBuilder: (context, index) {
        final entry = _filteredEntries[index];
        return _buildEntryCard(entry, index);
      },
    );
  }

  Widget _buildGridCard(JournalEntry entry, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Determine content display based on length
    final contentLength = entry.plainTextContent.length;
    final maxLines = contentLength > 200 ? 6 : (contentLength > 100 ? 4 : 3);

    // Handle background color - adapt text colors based on background
    final hasBackgroundColor = entry.backgroundColor != null;
    final bgColor = hasBackgroundColor
        ? Color(entry.backgroundColor!)
        : (isDark ? GhostTheme.darkCard : GhostTheme.lightCard);

    // Determine if background is dark for text color adaptation
    final isBackgroundDark = hasBackgroundColor
        ? bgColor.computeLuminance() < 0.5
        : isDark;

    // Adapt text colors based on background
    final textColor = isBackgroundDark ? Colors.white : Colors.black87;
    final hintColor = isBackgroundDark ? Colors.white60 : Colors.black45;
    final attachmentColor = isBackgroundDark
        ? Colors.white70
        : const Color(0xFF555555);

    Widget card = GestureDetector(
      onTap: () => _openEditor(entry),
      onLongPress: () => _deleteEntry(entry),
      child: FutureBuilder<Uint8List?>(
        future: entry.backgroundImageId != null
            ? _loadBackgroundImage(entry.backgroundImageId!)
            : Future.value(null),
        builder: (context, snapshot) {
          // If there's a background image, use lighter text
          final hasBackgroundImage = snapshot.hasData && snapshot.data != null;
          final effectiveTextColor = hasBackgroundImage
              ? Colors.white
              : textColor;
          final effectiveHintColor = hasBackgroundImage
              ? Colors.white70
              : hintColor;
          final effectiveAttachmentColor = hasBackgroundImage
              ? Colors.white70
              : attachmentColor;

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? GhostTheme.darkBorder : GhostTheme.lightBorder,
              ),
              image: hasBackgroundImage
                  ? DecorationImage(
                      image: MemoryImage(snapshot.data!),
                      fit: BoxFit.cover,
                      opacity: isDark ? 0.25 : 0.3,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Mood, pin and date row
                Row(
                  children: [
                    if (entry.mood != null) ...[
                      Text(entry.mood!, style: const TextStyle(fontSize: 18)),
                    ],
                    if (entry.isPinned) ...[
                      if (entry.mood != null) const SizedBox(width: 4),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: isBackgroundDark
                            ? Colors.white70
                            : GhostTheme.primary.withOpacity(0.8),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _formatDateShort(entry.updatedAt),
                      style: TextStyle(fontSize: 11, color: effectiveHintColor),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Title
                if (entry.title.isNotEmpty) ...[
                  Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: effectiveTextColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                ],

                // Content preview with formatting
                if (entry.plainTextContent.isNotEmpty)
                  _buildFormattedContentPreview(
                    entry,
                    effectiveHintColor,
                    maxLines,
                  ),

                // Attachments indicator
                if (entry.hasAttachments) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (entry.imageAttachments.isNotEmpty) ...[
                        Icon(
                          Icons.image_rounded,
                          size: 14,
                          color: effectiveAttachmentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.imageAttachments.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: effectiveAttachmentColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (entry.audioAttachments.isNotEmpty) ...[
                        Icon(
                          Icons.mic_rounded,
                          size: 14,
                          color: effectiveAttachmentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.audioAttachments.length}',
                          style: TextStyle(
                            fontSize: 11,
                            color: effectiveAttachmentColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],

                // Tags
                if (entry.tags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: entry.tags
                        .take(2)
                        .map(
                          (tag) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isBackgroundDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : const Color(
                                      0xFF2D2D2D,
                                    ).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$tag',
                              style: TextStyle(
                                color: isBackgroundDark
                                    ? Colors.white70
                                    : const Color(0xFF2D2D2D),
                                fontSize: 10,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );

    if (!_shouldAnimate || index > 8) return card;

    return card
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: index * 40),
          duration: const Duration(milliseconds: 250),
        )
        .scale(
          begin: const Offset(0.95, 0.95),
          end: const Offset(1, 1),
          delay: Duration(milliseconds: index * 40),
          duration: const Duration(milliseconds: 250),
        );
  }

  /// Build formatted content preview with bold/italic styling preserved
  Widget _buildFormattedContentPreview(
    JournalEntry entry,
    Color textColor,
    int maxLines,
  ) {
    final spans = entry.formattedContentSpans;
    if (spans.isEmpty) return const SizedBox.shrink();

    // Build TextSpan list with proper formatting
    final textSpans = <TextSpan>[];
    int totalChars = 0;
    const maxChars = 200; // Limit characters for performance

    for (final span in spans) {
      if (totalChars >= maxChars) break;

      String text = span.text;
      if (totalChars + text.length > maxChars) {
        text = text.substring(0, maxChars - totalChars);
      }
      totalChars += text.length;

      textSpans.add(
        TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 12,
            color: textColor,
            height: 1.4,
            fontWeight: span.isBold ? FontWeight.w600 : FontWeight.normal,
            fontStyle: span.isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }

    return RichText(
      text: TextSpan(children: textSpans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Future<Uint8List?> _loadBackgroundImage(String id) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/note_backgrounds/$id.ghost');

      if (!await file.exists()) return null;

      final encrypted = await file.readAsBytes();
      return EncryptionService.instance.decryptBytes(encrypted);
    } catch (e) {
      return null;
    }
  }

  String _formatDateShort(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';

    return '${date.day}/${date.month}';
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.book_outlined,
                size: 64,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No entries found'
                  : 'Your journal is empty',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Start writing your first entry',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isEmpty) ...[
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Create Entry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(JournalEntry entry, int index) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Handle background color
    final hasBackgroundColor = entry.backgroundColor != null;
    final bgColor = hasBackgroundColor
        ? Color(entry.backgroundColor!)
        : (isDark ? GhostTheme.darkCard : GhostTheme.lightCard);

    // Determine if background is dark for text color adaptation
    final isBackgroundDark = hasBackgroundColor
        ? bgColor.computeLuminance() < 0.5
        : isDark;

    final card = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Dismissible(
        key: Key(entry.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) async {
          await _deleteEntry(entry);
          return false;
        },
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 24),
          decoration: BoxDecoration(
            color: GhostTheme.error.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_rounded, color: GhostTheme.error),
        ),
        child: FutureBuilder<Uint8List?>(
          future: entry.backgroundImageId != null
              ? _loadBackgroundImage(entry.backgroundImageId!)
              : Future.value(null),
          builder: (context, snapshot) {
            final hasBackgroundImage =
                snapshot.hasData && snapshot.data != null;
            final effectiveTextColor = hasBackgroundImage
                ? Colors.white
                : (isBackgroundDark ? Colors.white : Colors.black87);
            final effectiveHintColor = hasBackgroundImage
                ? Colors.white70
                : (isBackgroundDark ? Colors.white70 : Colors.black54);

            return GestureDetector(
              onTap: () => _openEditor(entry),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? GhostTheme.darkBorder
                        : GhostTheme.lightBorder,
                  ),
                  image: hasBackgroundImage
                      ? DecorationImage(
                          image: MemoryImage(snapshot.data!),
                          fit: BoxFit.cover,
                          opacity: isDark ? 0.25 : 0.3,
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (entry.mood != null) ...[
                          Text(
                            entry.mood!,
                            style: const TextStyle(fontSize: 20),
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (entry.isPinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 16,
                            color: hasBackgroundImage || isBackgroundDark
                                ? Colors.white70
                                : GhostTheme.primary.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            entry.title.isNotEmpty ? entry.title : 'Untitled',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: effectiveTextColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.plainTextContent,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: effectiveHintColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 14,
                          color: hasBackgroundImage || isBackgroundDark
                              ? Colors.white54
                              : Colors.black38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(entry.updatedAt),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: hasBackgroundImage || isBackgroundDark
                                ? Colors.white54
                                : Colors.black38,
                          ),
                        ),
                        if (entry.tags.isNotEmpty) ...[
                          const SizedBox(width: 16),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: entry.tags.take(3).map((tag) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        hasBackgroundImage || isBackgroundDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '#$tag',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color:
                                          hasBackgroundImage || isBackgroundDark
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );

    if (!_shouldAnimate || index > 8) return card;

    return card
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: index * 35),
          duration: const Duration(milliseconds: 200),
        )
        .slideY(
          begin: 0.08,
          end: 0,
          delay: Duration(milliseconds: index * 35),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.day}/${date.month}/${date.year}';
  }
}

/// Helper class for masonry layout
class _CardData {
  final JournalEntry entry;
  final int index;

  _CardData(this.entry, this.index);
}
