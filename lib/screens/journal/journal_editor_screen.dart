import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import '../../models/journal_entry.dart';
import '../../services/storage_service.dart';
import '../../services/encryption_service.dart';
import '../../theme/ghost_theme.dart';
import '../../widgets/custom_modal.dart';

class JournalEditorScreen extends StatefulWidget {
  final JournalEntry? entry;

  const JournalEditorScreen({super.key, this.entry});

  @override
  State<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends State<JournalEditorScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagController;
  late List<String> _tags;
  late List<NoteAttachment> _attachments;
  String? _selectedMood;
  String? _backgroundImageId;
  int? _backgroundColor;
  bool _isSaving = false;
  bool _hasChanges = false;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  // Formatting state
  bool _isBold = false;
  bool _isItalic = false;
  bool _isPinned = false;

  // Undo/Redo stacks
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];
  String _lastContent = '';

  // Cached background image to prevent blinking
  Uint8List? _cachedBackgroundImage;

  // Cached attachment images to prevent blinking during typing
  final Map<String, Uint8List> _cachedAttachmentImages = {};

  // Haptic throttle
  DateTime _lastHaptic = DateTime.now();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  final List<String> _moodOptions = [
    '😊',
    '😌',
    '😐',
    '😢',
    '😤',
    '😰',
    '🥳',
    '😴',
    '💪',
    '❤️',
  ];

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    _titleController = TextEditingController(text: widget.entry?.title ?? '');
    _tagController = TextEditingController();
    _tags = List.from(widget.entry?.tags ?? []);
    _attachments = List.from(widget.entry?.attachments ?? []);
    _selectedMood = widget.entry?.mood;
    _backgroundImageId = widget.entry?.backgroundImageId;
    _backgroundColor = widget.entry?.backgroundColor;
    _isPinned = widget.entry?.isPinned ?? false;

    String initialContent = '';
    if (widget.entry?.content != null && widget.entry!.content.isNotEmpty) {
      initialContent = _parseContent(widget.entry!.content);
    }
    _contentController = TextEditingController(text: initialContent);
    _lastContent = initialContent;

    _titleController.addListener(_onTextChanged);
    _contentController.addListener(_onContentChanged);

    // Haptic feedback while typing (throttled)
    _titleController.addListener(_onTypingHaptic);
    _contentController.addListener(_onTypingHaptic);

    // Load background image once
    _loadAndCacheBackground();

    // Preload attachment images
    _preloadAttachmentImages();
  }

  void _onTypingHaptic() {
    final now = DateTime.now();
    if (now.difference(_lastHaptic).inMilliseconds > 50) {
      HapticFeedback.selectionClick();
      _lastHaptic = now;
    }
  }

  Future<void> _preloadAttachmentImages() async {
    for (final attachment in _attachments) {
      if (attachment.isImage && !_cachedAttachmentImages.containsKey(attachment.id)) {
        final imageData = await _loadAttachmentImage(attachment.id);
        if (imageData != null && mounted) {
          _cachedAttachmentImages[attachment.id] = imageData;
        }
      }
    }
    if (mounted) setState(() {});
  }

  void _onContentChanged() {
    _onTextChanged();
    // Add to undo stack
    final currentContent = _contentController.text;
    if (currentContent != _lastContent &&
        currentContent.length != _lastContent.length) {
      if (_undoStack.isEmpty || _undoStack.last != _lastContent) {
        _undoStack.add(_lastContent);
        if (_undoStack.length > 50) _undoStack.removeAt(0);
      }
      _redoStack.clear();
      _lastContent = currentContent;
    }
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(_contentController.text);
      final previous = _undoStack.removeLast();
      _contentController.removeListener(_onContentChanged);
      _contentController.text = previous;
      _contentController.selection = TextSelection.collapsed(
        offset: previous.length,
      );
      _lastContent = previous;
      _contentController.addListener(_onContentChanged);
      HapticFeedback.lightImpact();
      setState(() {});
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(_contentController.text);
      final next = _redoStack.removeLast();
      _contentController.removeListener(_onContentChanged);
      _contentController.text = next;
      _contentController.selection = TextSelection.collapsed(
        offset: next.length,
      );
      _lastContent = next;
      _contentController.addListener(_onContentChanged);
      HapticFeedback.lightImpact();
      setState(() {});
    }
  }

  void _togglePin() {
    setState(() {
      _isPinned = !_isPinned;
      _hasChanges = true;
    });
    HapticFeedback.mediumImpact();
  }

  Future<void> _loadAndCacheBackground() async {
    if (_backgroundImageId != null) {
      final data = await _loadBackgroundImage();
      if (mounted) {
        setState(() {
          _cachedBackgroundImage = data;
        });
      }
    }
  }

  /// Determines if the effective background is dark
  /// Takes into account custom background color with luminance check
  bool _isEffectivelyDark(bool systemIsDark) {
    if (_backgroundColor != null) {
      // Use luminance of the custom background color
      final color = Color(_backgroundColor!);
      return color.computeLuminance() < 0.5;
    }
    // Fall back to system theme
    return systemIsDark;
  }

  /// Get the appropriate text color based on effective background
  Color _getTextColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white : Colors.black87;
  }

  /// Get the appropriate hint/secondary text color
  Color _getHintColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white60 : Colors.black45;
  }

  /// Get the appropriate icon color
  Color _getIconColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white70 : Colors.black54;
  }

  /// Get the disabled icon color
  Color _getDisabledIconColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white24 : Colors.black26;
  }

  String _parseContent(String content) {
    if (content.isEmpty) return '';
    try {
      final jsonContent = jsonDecode(content);
      if (jsonContent is List) {
        final buffer = StringBuffer();
        for (final op in jsonContent) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) {
              buffer.write(insert);
            }
          }
        }
        return buffer.toString().trim();
      }
    } catch (e) {
      // Plain text
    }
    return content.trim();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    setState(() {});
  }

  // ==================== Tag Management ====================

  void _addTag() {
    final tag = _tagController.text.trim().toLowerCase().replaceAll(' ', '_');
    if (tag.isNotEmpty && !_tags.contains(tag) && _tags.length < 10) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
        _hasChanges = true;
      });
      HapticFeedback.lightImpact();
    }
  }

  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      _hasChanges = true;
    });
    HapticFeedback.lightImpact();
  }

  // ==================== Mood Picker ====================

  void _selectMood(String mood) {
    setState(() {
      _selectedMood = _selectedMood == mood ? null : mood;
      _hasChanges = true;
    });
    HapticFeedback.selectionClick();
    Navigator.pop(context);
  }

  void _showMoodPicker() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'How are you feeling?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: _moodOptions.map((mood) {
                final isSelected = _selectedMood == mood;
                return GestureDetector(
                  onTap: () => _selectMood(mood),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? GhostTheme.primary.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected
                            ? GhostTheme.primary
                            : (isDark ? Colors.white12 : Colors.black12),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(mood, style: const TextStyle(fontSize: 28)),
                    ),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  // ==================== Formatting ====================

  void _toggleBold() {
    setState(() {
      _isBold = !_isBold;
      _hasChanges = true;
    });
    HapticFeedback.selectionClick();
  }

  void _toggleItalic() {
    setState(() {
      _isItalic = !_isItalic;
      _hasChanges = true;
    });
    HapticFeedback.selectionClick();
  }

  void _insertBullet() {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursorPos = selection.baseOffset;

    // Find the start of the current line
    int lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    // Insert bullet at line start
    final newText =
        text.substring(0, lineStart) + '• ' + text.substring(lineStart);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: cursorPos + 2,
    );
    _hasChanges = true;
    HapticFeedback.selectionClick();
  }

  void _insertNumberedList() {
    final text = _contentController.text;
    final selection = _contentController.selection;
    final cursorPos = selection.baseOffset;

    // Count existing numbered items
    int number = 1;
    final lines = text.substring(0, cursorPos).split('\n');
    for (final line in lines.reversed) {
      final match = RegExp(r'^(\d+)\. ').firstMatch(line);
      if (match != null) {
        number = int.parse(match.group(1)!) + 1;
        break;
      }
    }

    // Find the start of the current line
    int lineStart = cursorPos;
    while (lineStart > 0 && text[lineStart - 1] != '\n') {
      lineStart--;
    }

    // Insert number at line start
    final prefix = '$number. ';
    final newText =
        text.substring(0, lineStart) + prefix + text.substring(lineStart);
    _contentController.text = newText;
    _contentController.selection = TextSelection.collapsed(
      offset: cursorPos + prefix.length,
    );
    _hasChanges = true;
    HapticFeedback.selectionClick();
  }

  // ==================== Image Handling ====================

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      await _saveImageAttachment(bytes, image.name);
    } catch (e) {
      _showError('Failed to capture image: $e');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      await _saveImageAttachment(bytes, image.name);
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _saveImageAttachment(
    Uint8List bytes,
    String originalName,
  ) async {
    final uuid = const Uuid();
    final id = uuid.v4();
    final encryption = EncryptionService.instance;

    // Compress image for storage
    final compressedBytes = _compressImage(bytes);

    // Encrypt and save
    final encrypted = encryption.encryptBytes(compressedBytes);
    final dir = await getApplicationDocumentsDirectory();
    final attachmentDir = Directory('${dir.path}/note_attachments');
    if (!await attachmentDir.exists()) {
      await attachmentDir.create(recursive: true);
    }

    final file = File('${attachmentDir.path}/$id.ghost');
    await file.writeAsBytes(encrypted);

    final attachment = NoteAttachment(
      id: id,
      type: 'image',
      fileName: originalName,
      sizeBytes: compressedBytes.length,
      addedAt: DateTime.now(),
    );

    setState(() {
      _attachments.add(attachment);
      _cachedAttachmentImages[id] = compressedBytes; // Cache immediately
      _hasChanges = true;
    });

    HapticFeedback.mediumImpact();
  }

  Uint8List _compressImage(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      // Resize if too large
      img.Image resized = decoded;
      if (decoded.width > 1200 || decoded.height > 1200) {
        if (decoded.width > decoded.height) {
          resized = img.copyResize(decoded, width: 1200);
        } else {
          resized = img.copyResize(decoded, height: 1200);
        }
      }

      // Encode as JPEG with 75% quality
      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    } catch (e) {
      return bytes;
    }
  }

  // ==================== Background Image ====================

  // Preset colors for background (limited selection)
  static const List<Color> _backgroundColors = [
    Color(0xFFFFCDD2), // Red light
    Color(0xFFF8BBD9), // Pink light
    Color(0xFFE1BEE7), // Purple light
    Color(0xFFBBDEFB), // Blue light
    Color(0xFFB2EBF2), // Cyan light
    Color(0xFFC8E6C9), // Green light
    Color(0xFFFFF9C4), // Yellow light
    Color(0xFFFFE0B2), // Orange light
    Color(0xFFD7CCC8), // Brown light
    Color(0xFFCFD8DC), // Blue Grey light
    Color(0xFF37474F), // Dark grey
    Color(0xFF263238), // Dark slate
  ];

  Future<void> _pickBackgroundImage() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Note Background',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            // Color palette
            Text(
              'Colors',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _backgroundColors.map((color) {
                final isSelected = _backgroundColor == color.value;
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _setBackgroundColor(color);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected
                          ? Border.all(color: GhostTheme.primary, width: 3)
                          : Border.all(
                              color: isDark ? Colors.white24 : Colors.black12,
                              width: 1,
                            ),
                    ),
                    child: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: color.computeLuminance() > 0.5
                                ? Colors.black87
                                : Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: 16),
            Text(
              'Image',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildBackgroundOption(
                  icon: Icons.camera_alt_rounded,
                  label: 'Camera',
                  onTap: () async {
                    Navigator.pop(context);
                    await _captureBackgroundImage();
                  },
                  isDark: isDark,
                ),
                _buildBackgroundOption(
                  icon: Icons.photo_library_rounded,
                  label: 'Gallery',
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickBackgroundFromGallery();
                  },
                  isDark: isDark,
                ),
                if (_backgroundImageId != null || _backgroundColor != null)
                  _buildBackgroundOption(
                    icon: Icons.delete_outline_rounded,
                    label: 'Remove',
                    onTap: () {
                      Navigator.pop(context);
                      _removeBackground();
                    },
                    isDark: isDark,
                    isDestructive: true,
                  ),
              ],
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _setBackgroundColor(Color color) {
    setState(() {
      _backgroundColor = color.value;
      _backgroundImageId = null;
      _cachedBackgroundImage = null;
      _hasChanges = true;
    });
    HapticFeedback.lightImpact();
  }

  Widget _buildBackgroundOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDestructive
                  ? GhostTheme.error.withOpacity(0.15)
                  : (isDark
                        ? Colors.white.withOpacity(0.1)
                        : Colors.black.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: isDestructive
                  ? GhostTheme.error
                  : (isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDestructive
                  ? GhostTheme.error
                  : (isDark ? Colors.white54 : Colors.black45),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureBackgroundImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );

      if (image == null) return;
      await _saveBackgroundImage(await image.readAsBytes());
    } catch (e) {
      _showError('Failed to capture image: $e');
    }
  }

  Future<void> _pickBackgroundFromGallery() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );

      if (image == null) return;
      await _saveBackgroundImage(await image.readAsBytes());
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _saveBackgroundImage(Uint8List bytes) async {
    final uuid = const Uuid();
    final id = uuid.v4();
    final encryption = EncryptionService.instance;

    // Compress for background
    final compressedBytes = _compressImage(bytes);

    // Encrypt and save
    final encrypted = encryption.encryptBytes(compressedBytes);
    final dir = await getApplicationDocumentsDirectory();
    final bgDir = Directory('${dir.path}/note_backgrounds');
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }

    final file = File('${bgDir.path}/$id.ghost');
    await file.writeAsBytes(encrypted);

    // Delete old background if exists
    if (_backgroundImageId != null) {
      final oldFile = File('${bgDir.path}/$_backgroundImageId.ghost');
      if (await oldFile.exists()) {
        await oldFile.delete();
      }
    }

    setState(() {
      _backgroundImageId = id;
      _backgroundColor = null;
      _cachedBackgroundImage = compressedBytes;
      _hasChanges = true;
    });

    HapticFeedback.mediumImpact();
  }

  void _removeBackground() {
    setState(() {
      _backgroundImageId = null;
      _backgroundColor = null;
      _cachedBackgroundImage = null;
      _hasChanges = true;
    });
    HapticFeedback.lightImpact();
  }

  Future<Uint8List?> _loadBackgroundImage() async {
    if (_backgroundImageId == null) return null;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/note_backgrounds/$_backgroundImageId.ghost',
      );

      if (!await file.exists()) return null;

      final encrypted = await file.readAsBytes();
      return EncryptionService.instance.decryptBytes(encrypted);
    } catch (e) {
      return null;
    }
  }

  void _deleteAttachment(NoteAttachment attachment) async {
    final confirm = await GhostModal.show(
      context: context,
      title: 'Delete Image?',
      message: 'This cannot be undone.',
      confirmText: 'Delete',
      cancelText: 'Cancel',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );

    if (confirm == true) {
      // Delete file
      try {
        final dir = await getApplicationDocumentsDirectory();
        final file = File(
          '${dir.path}/note_attachments/${attachment.id}.ghost',
        );
        if (await file.exists()) {
          await file.delete();
        }
      } catch (e) {
        // Ignore file deletion errors
      }

      setState(() {
        _attachments.removeWhere((a) => a.id == attachment.id);
        _hasChanges = true;
      });

      HapticFeedback.mediumImpact();
    }
  }

  // ==================== Save ====================

  Future<void> _save() async {
    final content = _contentController.text.trim();

    if (_titleController.text.trim().isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Add a title or some content'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    HapticFeedback.mediumImpact();

    try {
      final now = DateTime.now();

      final entry = JournalEntry(
        id: widget.entry?.id ?? EncryptionService.generateSecureId(),
        title: _titleController.text.trim(),
        content: content,
        createdAt: widget.entry?.createdAt ?? now,
        updatedAt: now,
        mood: _selectedMood,
        tags: _tags,
        attachments: _attachments,
        backgroundImageId: _backgroundImageId,
        backgroundColor: _backgroundColor,
        isPinned: _isPinned,
      );

      await StorageService.instance.saveJournalEntry(entry);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;

    final result = await GhostModal.show(
      context: context,
      title: 'Discard changes?',
      message: 'You have unsaved changes.',
      confirmText: 'Discard',
      cancelText: 'Keep Editing',
      icon: Icons.warning_amber_rounded,
      isDangerous: true,
    );

    return result ?? false;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: GhostTheme.error,
      ),
    );
  }

  // ==================== Build Methods ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: _backgroundColor != null 
            ? Color(_backgroundColor!)
            : (isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA)),
        resizeToAvoidBottomInset: false,
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Stack(
            children: [
              // Background image (cached to prevent blinking)
              if (_cachedBackgroundImage != null)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: Opacity(
                      opacity: isDark ? 0.3 : 0.4,
                      child: Image.memory(
                        _cachedBackgroundImage!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        cacheWidth: 800,
                        filterQuality: FilterQuality.low,
                        isAntiAlias: false,
                      ),
                    ),
                  ),
                ),

              // Content
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _buildTopBar(isDark),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const ClampingScrollPhysics(),
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 8),
                              _buildMoodButton(isDark),
                              const SizedBox(height: 16),
                              _buildTitleField(isDark),
                              const SizedBox(height: 12),
                              _buildContentField(isDark),
                              const SizedBox(height: 20),
                              if (_attachments.isNotEmpty) ...[
                                _buildAttachmentsSection(isDark),
                                const SizedBox(height: 24),
                              ],
                              _buildTagsSection(isDark),
                              SizedBox(height: bottomPadding + 140),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _buildFormattingToolbar(isDark),
                    _buildBottomBar(isDark, bottomPadding),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    final iconColor = _getIconColor(isDark);
    final disabledColor = _getDisabledIconColor(isDark);
    final hintColor = _getHintColor(isDark);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_rounded,
              color: iconColor,
              size: 20,
            ),
            onPressed: () async {
              if (_hasChanges) {
                final shouldPop = await _onWillPop();
                if (shouldPop && mounted) Navigator.pop(context);
              } else {
                Navigator.pop(context);
              }
            },
            visualDensity: VisualDensity.compact,
          ),
          // Undo
          IconButton(
            icon: Icon(
              Icons.undo_rounded,
              color: _undoStack.isNotEmpty ? iconColor : disabledColor,
              size: 20,
            ),
            onPressed: _undoStack.isNotEmpty ? _undo : null,
            visualDensity: VisualDensity.compact,
            tooltip: 'Undo',
          ),
          // Redo
          IconButton(
            icon: Icon(
              Icons.redo_rounded,
              color: _redoStack.isNotEmpty ? iconColor : disabledColor,
              size: 20,
            ),
            onPressed: _redoStack.isNotEmpty ? _redo : null,
            visualDensity: VisualDensity.compact,
            tooltip: 'Redo',
          ),
          const Spacer(),
          // Pin
          IconButton(
            icon: Icon(
              _isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              color: _isPinned ? GhostTheme.primary : hintColor,
              size: 20,
            ),
            onPressed: _togglePin,
            visualDensity: VisualDensity.compact,
            tooltip: _isPinned ? 'Unpin' : 'Pin to top',
          ),
          // Background
          IconButton(
            icon: Icon(
              _backgroundImageId != null
                  ? Icons.wallpaper_rounded
                  : Icons.wallpaper_outlined,
              color: _backgroundImageId != null
                  ? GhostTheme.primary
                  : hintColor,
              size: 20,
            ),
            onPressed: _pickBackgroundImage,
            visualDensity: VisualDensity.compact,
            tooltip: 'Background',
          ),
          const SizedBox(width: 4),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(GhostTheme.primary),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                backgroundColor: GhostTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Save',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildMoodButton(bool isDark) {
    return GestureDetector(
      onTap: _showMoodPicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_selectedMood ?? '😊', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 8),
            Text(
              _selectedMood != null ? 'Change' : 'Add mood',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleField(bool isDark) {
    final textColor = _getTextColor(isDark);
    final hintColor = _getHintColor(isDark).withOpacity(0.5);
    
    return TextField(
      controller: _titleController,
      focusNode: _titleFocusNode,
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: textColor,
        height: 1.3,
      ),
      decoration: InputDecoration(
        hintText: 'Title',
        hintStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: hintColor,
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        isDense: true,
      ),
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: GhostTheme.primary,
      cursorWidth: 2,
    );
  }

  Widget _buildContentField(bool isDark) {
    final textColor = _getTextColor(isDark);
    final hintColor = _getHintColor(isDark);
    
    return TextField(
      controller: _contentController,
      focusNode: _contentFocusNode,
      style: TextStyle(
        fontSize: 16,
        color: textColor.withOpacity(0.9),
        height: 1.6,
        fontWeight: _isBold ? FontWeight.bold : FontWeight.normal,
        fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      ),
      decoration: InputDecoration(
        hintText: 'Start writing...',
        hintStyle: TextStyle(
          fontSize: 16,
          color: hintColor.withOpacity(0.5),
        ),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        contentPadding: const EdgeInsets.all(16),
        isDense: true,
      ),
      maxLines: null,
      minLines: 6,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: GhostTheme.primary,
      cursorWidth: 2,
    );
  }

  Widget _buildFormattingToolbar(bool isDark) {
    final hasBackground = _cachedBackgroundImage != null;

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: hasBackground ? 25 : 8,
          sigmaY: hasBackground ? 25 : 8,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: hasBackground
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.5))
                : (isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.85)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                // Bold
                _buildFormatButton(
                  icon: Icons.format_bold_rounded,
                  isActive: _isBold,
                  onTap: _toggleBold,
                  isDark: isDark,
                  tooltip: 'Bold',
                ),
                // Italic
                _buildFormatButton(
                  icon: Icons.format_italic_rounded,
                  isActive: _isItalic,
                  onTap: _toggleItalic,
                  isDark: isDark,
                  tooltip: 'Italic',
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                // Bullet list
                _buildFormatButton(
                  icon: Icons.format_list_bulleted_rounded,
                  isActive: false,
                  onTap: _insertBullet,
                  isDark: isDark,
                  tooltip: 'Bullet list',
                ),
                // Numbered list
                _buildFormatButton(
                  icon: Icons.format_list_numbered_rounded,
                  isActive: false,
                  onTap: _insertNumberedList,
                  isDark: isDark,
                  tooltip: 'Numbered list',
                ),
                Container(
                  width: 1,
                  height: 24,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
                // Camera
                _buildFormatButton(
                  icon: Icons.camera_alt_rounded,
                  isActive: false,
                  onTap: _pickImage,
                  isDark: isDark,
                  tooltip: 'Take photo',
                ),
                // Gallery
                _buildFormatButton(
                  icon: Icons.photo_library_rounded,
                  isActive: false,
                  onTap: _pickImageFromGallery,
                  isDark: isDark,
                  tooltip: 'Add image',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatButton({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
    required String tooltip,
    Color? activeColor,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: isActive
                ? (activeColor ?? GhostTheme.primary).withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 22,
            color: isActive
                ? (activeColor ?? GhostTheme.primary)
                : (isDark ? Colors.white54 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection(bool isDark) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.attach_file_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Attachments',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _attachments
                    .where((a) => a.isImage)
                    .map(
                      (attachment) => _buildImageAttachment(attachment, isDark),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildImageAttachment(NoteAttachment attachment, bool isDark) {
    final cachedImage = _cachedAttachmentImages[attachment.id];

    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: () => _deleteAttachment(attachment),
        onTap: () {
          // Show full image in dialog
          if (cachedImage != null) {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                child: Stack(
                  children: [
                    InteractiveViewer(child: Image.memory(cachedImage)),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            image: cachedImage != null
                ? DecorationImage(
                    image: MemoryImage(cachedImage),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: cachedImage == null
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
      ),
    );
  }

  Future<Uint8List?> _loadAttachmentImage(String id) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/note_attachments/$id.ghost');

      if (!await file.exists()) return null;

      final encrypted = await file.readAsBytes();
      return EncryptionService.instance.decryptBytes(encrypted);
    } catch (e) {
      return null;
    }
  }

  Widget _buildTagsSection(bool isDark) {
    final hintColor = _getHintColor(isDark);
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tag_rounded,
                size: 16,
                color: hintColor,
              ),
              const SizedBox(width: 6),
              Text(
                'Tags',
                style: TextStyle(
                  fontSize: 13,
                  color: hintColor,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._tags.map((tag) => _buildTagChip(tag, isDark)),
              if (_tags.length < 10) _buildAddTagButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag, bool isDark) {
    // Use background-aware color for tag
    final effectivelyDark = _isEffectivelyDark(isDark);
    final tagColor = effectivelyDark ? GhostTheme.primary : const Color(0xFF2D2D2D);
    
    return GestureDetector(
      onTap: () => _removeTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tagColor.withOpacity(effectivelyDark ? 0.12 : 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$tag',
              style: TextStyle(
                fontSize: 13,
                color: tagColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.close_rounded,
              size: 14,
              color: tagColor.withOpacity(0.7),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTagButton(bool isDark) {
    final textColor = _getTextColor(isDark);
    final hintColor = _getHintColor(isDark);
    
    return SizedBox(
      width: 120,
      height: 36,
      child: TextField(
        controller: _tagController,
        style: TextStyle(
          fontSize: 13,
          color: textColor.withOpacity(0.7),
        ),
        decoration: InputDecoration(
          hintText: 'Add tag',
          hintStyle: TextStyle(
            fontSize: 13,
            color: hintColor.withOpacity(0.6),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          isDense: true,
        ),
        onSubmitted: (_) => _addTag(),
        textInputAction: TextInputAction.done,
      ),
    );
  }

  Widget _buildBottomBar(bool isDark, double bottomPadding) {
    final wordCount = _countWords(_contentController.text);
    final charCount = _contentController.text.length;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.06)
                : Colors.black.withOpacity(0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$wordCount words',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 3,
            height: 3,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              shape: BoxShape.circle,
            ),
          ),
          Text(
            '$charCount chars',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          if (_attachments.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 3,
              height: 3,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                shape: BoxShape.circle,
              ),
            ),
            Text(
              '${_attachments.length} files',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
          const Spacer(),
          if (widget.entry != null)
            Text(
              _formatDate(widget.entry!.updatedAt),
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
        ],
      ),
    );
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}
