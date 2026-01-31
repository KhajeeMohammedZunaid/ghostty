import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
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
  late final TextEditingController _tagController;
  late QuillController _quillController;
  late List<String> _tags;
  late List<NoteAttachment> _attachments;
  String? _selectedMood;
  String? _backgroundImageId;
  int? _backgroundColor;
  bool _isSaving = false;
  bool _hasChanges = false;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _editorFocusNode = FocusNode();
  final FocusNode _tagFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  bool _isPinned = false;

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

    // Initialize Quill controller
    _initQuillController();

    _titleController.addListener(_onTextChanged);

    // Haptic feedback while typing (throttled)
    _titleController.addListener(_onTypingHaptic);

    // Load background image once
    _loadAndCacheBackground();

    // Preload attachment images
    _preloadAttachmentImages();
  }

  void _initQuillController() {
    Document doc;
    if (widget.entry?.content != null && widget.entry!.content.isNotEmpty) {
      try {
        // Try to parse as Delta JSON
        final jsonContent = jsonDecode(widget.entry!.content);
        if (jsonContent is List) {
          doc = Document.fromJson(jsonContent);
        } else {
          // Plain text
          doc = Document()..insert(0, widget.entry!.content);
        }
      } catch (e) {
        // Plain text fallback
        doc = Document()..insert(0, widget.entry!.content);
      }
    } else {
      doc = Document();
    }

    _quillController = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );

    _quillController.addListener(_onQuillChanged);
  }

  void _onQuillChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    _onTypingHaptic();
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
      if (attachment.isImage &&
          !_cachedAttachmentImages.containsKey(attachment.id)) {
        final imageData = await _loadAttachmentImage(attachment.id);
        if (imageData != null && mounted) {
          _cachedAttachmentImages[attachment.id] = imageData;
        }
      }
    }
    if (mounted) setState(() {});
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
  bool _isEffectivelyDark(bool systemIsDark) {
    if (_backgroundColor != null) {
      final color = Color(_backgroundColor!);
      return color.computeLuminance() < 0.5;
    }
    return systemIsDark;
  }

  Color _getTextColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white : Colors.black87;
  }

  Color _getHintColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white60 : Colors.black45;
  }

  Color _getIconColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white70 : Colors.black54;
  }

  Color _getDisabledIconColor(bool systemIsDark) {
    final effectivelyDark = _isEffectivelyDark(systemIsDark);
    return effectivelyDark ? Colors.white24 : Colors.black26;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _titleController.dispose();
    _quillController.dispose();
    _tagController.dispose();
    _titleFocusNode.dispose();
    _editorFocusNode.dispose();
    _tagFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
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
      // Keep focus on tag field for continuous input
      _tagFocusNode.requestFocus();
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
    final isBold = _quillController.getSelectionStyle().attributes.containsKey(
      'bold',
    );
    _quillController.formatSelection(
      isBold ? Attribute.clone(Attribute.bold, null) : Attribute.bold,
    );
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _toggleItalic() {
    final isItalic = _quillController
        .getSelectionStyle()
        .attributes
        .containsKey('italic');
    _quillController.formatSelection(
      isItalic ? Attribute.clone(Attribute.italic, null) : Attribute.italic,
    );
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _insertBullet() {
    final isActive =
        _quillController.getSelectionStyle().attributes.containsKey('list') &&
        _quillController.getSelectionStyle().attributes['list']?.value ==
            'bullet';
    _quillController.formatSelection(
      isActive ? Attribute.clone(Attribute.ul, null) : Attribute.ul,
    );
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _insertNumberedList() {
    final isActive =
        _quillController.getSelectionStyle().attributes.containsKey('list') &&
        _quillController.getSelectionStyle().attributes['list']?.value ==
            'ordered';
    _quillController.formatSelection(
      isActive ? Attribute.clone(Attribute.ol, null) : Attribute.ol,
    );
    HapticFeedback.selectionClick();
    setState(() {});
  }

  bool get _isBoldActive =>
      _quillController.getSelectionStyle().attributes.containsKey('bold');
  bool get _isItalicActive =>
      _quillController.getSelectionStyle().attributes.containsKey('italic');
  bool get _isBulletActive =>
      _quillController.getSelectionStyle().attributes.containsKey('list') &&
      _quillController.getSelectionStyle().attributes['list']?.value ==
          'bullet';
  bool get _isNumberedActive =>
      _quillController.getSelectionStyle().attributes.containsKey('list') &&
      _quillController.getSelectionStyle().attributes['list']?.value ==
          'ordered';

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
    } on PlatformException catch (e) {
      // Handle permission denied or other platform errors silently
      debugPrint('Camera error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not access camera'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      // Silently handle other errors
      debugPrint('Camera pick error: $e');
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
    } on PlatformException catch (e) {
      // Handle permission denied or other platform errors silently
      debugPrint('Gallery picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Could not access gallery'),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      // Silently handle other errors
      debugPrint('Image pick error: $e');
    }
  }

  Future<void> _saveImageAttachment(
    Uint8List bytes,
    String originalName,
  ) async {
    final uuid = const Uuid();
    final id = uuid.v4();
    final encryption = EncryptionService.instance;

    final compressedBytes = _compressImage(bytes);

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
      _cachedAttachmentImages[id] = compressedBytes;
      _hasChanges = true;
    });

    HapticFeedback.mediumImpact();
  }

  Uint8List _compressImage(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return bytes;

      img.Image resized = decoded;
      if (decoded.width > 1200 || decoded.height > 1200) {
        if (decoded.width > decoded.height) {
          resized = img.copyResize(decoded, width: 1200);
        } else {
          resized = img.copyResize(decoded, height: 1200);
        }
      }

      return Uint8List.fromList(img.encodeJpg(resized, quality: 75));
    } catch (e) {
      return bytes;
    }
  }

  // ==================== Background Image ====================

  static const List<Color> _backgroundColors = [
    Color(0xFFFFCDD2),
    Color(0xFFF8BBD9),
    Color(0xFFE1BEE7),
    Color(0xFFBBDEFB),
    Color(0xFFB2EBF2),
    Color(0xFFC8E6C9),
    Color(0xFFFFF9C4),
    Color(0xFFFFE0B2),
    Color(0xFFD7CCC8),
    Color(0xFFCFD8DC),
    Color(0xFF37474F),
    Color(0xFF263238),
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

    final compressedBytes = _compressImage(bytes);

    final encrypted = encryption.encryptBytes(compressedBytes);
    final dir = await getApplicationDocumentsDirectory();
    final bgDir = Directory('${dir.path}/note_backgrounds');
    if (!await bgDir.exists()) {
      await bgDir.create(recursive: true);
    }

    final file = File('${bgDir.path}/$id.ghost');
    await file.writeAsBytes(encrypted);

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
    final deltaJson = jsonEncode(_quillController.document.toDelta().toJson());
    final plainText = _quillController.document.toPlainText().trim();

    if (_titleController.text.trim().isEmpty && plainText.isEmpty) {
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
        content: deltaJson,
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

  // ==================== Build Methods ====================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && mounted) Navigator.of(context).pop();
        }
      },
      child: GestureDetector(
        // Tap anywhere to focus editor, keeping keyboard open
        onTap: () {
          _editorFocusNode.requestFocus();
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
                // Background image
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
                          // Don't dismiss keyboard on scroll
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.manual,
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
                                _buildQuillEditor(isDark),
                                const SizedBox(height: 20),
                                if (_attachments.isNotEmpty) ...[
                                  _buildAttachmentsSection(isDark),
                                  const SizedBox(height: 24),
                                ],
                                _buildTagsSection(isDark),
                                // Extra space for toolbar + keyboard
                                SizedBox(
                                  height: isKeyboardVisible
                                      ? keyboardHeight + 80
                                      : bottomPadding + 140,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Floating formatting toolbar - sticks above keyboard with smooth animation
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  bottom: isKeyboardVisible ? keyboardHeight : bottomPadding,
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildFormattingToolbar(isDark),
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          sizeCurve: Curves.easeOutCubic,
                          crossFadeState: isKeyboardVisible
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: _buildBottomBar(isDark, bottomPadding),
                          secondChild: const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    final iconColor = _getIconColor(isDark);
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        isDense: true,
      ),
      maxLines: null,
      textCapitalization: TextCapitalization.sentences,
      cursorColor: GhostTheme.primary,
      cursorWidth: 2,
    );
  }

  Widget _buildQuillEditor(bool isDark) {
    final textColor = _getTextColor(isDark);
    final hintColor = _getHintColor(isDark);

    return QuillEditor.basic(
      controller: _quillController,
      focusNode: _editorFocusNode,
      config: QuillEditorConfig(
        placeholder: 'Start writing...',
        padding: const EdgeInsets.all(16),
        autoFocus: false,
        expands: false,
        scrollable: false,
        customStyles: DefaultStyles(
          paragraph: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 16,
              color: textColor.withOpacity(0.9),
              height: 1.6,
            ),
            HorizontalSpacing.zero,
            const VerticalSpacing(0, 8),
            const VerticalSpacing(0, 0),
            null,
          ),
          placeHolder: DefaultTextBlockStyle(
            TextStyle(
              fontSize: 16,
              color: hintColor.withOpacity(0.5),
              height: 1.6,
            ),
            HorizontalSpacing.zero,
            const VerticalSpacing(0, 0),
            const VerticalSpacing(0, 0),
            null,
          ),
          bold: const TextStyle(fontWeight: FontWeight.bold),
          italic: const TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
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
                      ? Colors.white.withOpacity(0.08)
                      : Colors.white.withOpacity(0.5))
                : (isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.white.withOpacity(0.85)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.black.withOpacity(0.06),
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
                  isActive: _isBoldActive,
                  onTap: _toggleBold,
                  isDark: isDark,
                  tooltip: 'Bold',
                ),
                // Italic
                _buildFormatButton(
                  icon: Icons.format_italic_rounded,
                  isActive: _isItalicActive,
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
                  isActive: _isBulletActive,
                  onTap: _insertBullet,
                  isDark: isDark,
                  tooltip: 'Bullet list',
                ),
                // Numbered list
                _buildFormatButton(
                  icon: Icons.format_list_numbered_rounded,
                  isActive: _isNumberedActive,
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
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 8),
                Text(
                  'Attachments',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white70 : Colors.black54,
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
                  .map((a) => _buildImageAttachment(a, isDark))
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
          if (cachedImage != null) {
            showDialog(
              context: context,
              builder: (context) => Dialog(
                backgroundColor: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(cachedImage, fit: BoxFit.contain),
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

  Widget _buildTagsSection(bool isDark) {
    final hintColor = _getHintColor(isDark);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tag_rounded, size: 18, color: hintColor),
              const SizedBox(width: 8),
              Text(
                'Tags',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: hintColor,
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
              _buildAddTagButton(isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String tag, bool isDark) {
    final effectivelyDark = _isEffectivelyDark(isDark);

    return GestureDetector(
      onTap: () => _removeTag(tag),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: effectivelyDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#$tag',
              style: TextStyle(
                fontSize: 13,
                color: effectivelyDark ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.close_rounded,
              size: 14,
              color: effectivelyDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddTagButton(bool isDark) {
    final effectivelyDark = _isEffectivelyDark(isDark);
    final textColor = _getTextColor(isDark);
    final hintColor = _getHintColor(isDark);

    return SizedBox(
      width: 120,
      height: 36,
      child: TextField(
        controller: _tagController,
        focusNode: _tagFocusNode,
        style: TextStyle(fontSize: 13, color: textColor),
        decoration: InputDecoration(
          hintText: '+ Add tag',
          hintStyle: TextStyle(
            fontSize: 13,
            color: hintColor.withValues(alpha: 0.6),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          isDense: true,
          filled: false,
        ),
        onSubmitted: (_) => _addTag(),
        textInputAction: TextInputAction.done,
        cursorColor: effectivelyDark ? Colors.white70 : Colors.black54,
      ),
    );
  }

  Widget _buildBottomBar(bool isDark, double bottomPadding) {
    final wordCount = _countWords(_quillController.document.toPlainText());
    final charCount = _quillController.document.toPlainText().length;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding + 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA),
        border: Border(
          top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      child: Row(
        children: [
          Text(
            '$wordCount words · $charCount chars',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const Spacer(),
          if (widget.entry != null)
            Text(
              'Edited ${_formatDate(widget.entry!.updatedAt)}',
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
