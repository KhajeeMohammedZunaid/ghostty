import 'dart:convert';

/// Represents a note attachment (image or audio)
class NoteAttachment {
  final String id;
  final String type; // 'image' or 'audio'
  final String fileName;
  final int sizeBytes;
  final DateTime addedAt;
  final int? durationMs; // For audio files

  NoteAttachment({
    required this.id,
    required this.type,
    required this.fileName,
    required this.sizeBytes,
    required this.addedAt,
    this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'fileName': fileName,
    'sizeBytes': sizeBytes,
    'addedAt': addedAt.toIso8601String(),
    'durationMs': durationMs,
  };

  factory NoteAttachment.fromJson(Map<String, dynamic> json) => NoteAttachment(
    id: json['id'] as String,
    type: json['type'] as String,
    fileName: json['fileName'] as String,
    sizeBytes: json['sizeBytes'] as int,
    addedAt: DateTime.parse(json['addedAt'] as String),
    durationMs: json['durationMs'] as int?,
  );

  bool get isImage => type == 'image';
  bool get isAudio => type == 'audio';
}

class JournalEntry {
  final String id;
  final String title;
  final String content;
  final List<TextFormatting> formatting;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mood;
  final List<String> tags;
  final List<NoteAttachment> attachments; // Images and audio files
  final String? backgroundImageId; // Custom background image reference
  final int? backgroundColor; // Background color value
  final bool isPinned; // Pin note to top

  JournalEntry({
    required this.id,
    required this.title,
    required this.content,
    this.formatting = const [],
    required this.createdAt,
    required this.updatedAt,
    this.mood,
    this.tags = const [],
    this.attachments = const [],
    this.backgroundImageId,
    this.backgroundColor,
    this.isPinned = false,
  });

  JournalEntry copyWith({
    String? id,
    String? title,
    String? content,
    List<TextFormatting>? formatting,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? mood,
    List<String>? tags,
    List<NoteAttachment>? attachments,
    String? backgroundImageId,
    int? backgroundColor,
    bool clearBackground = false,
    bool? isPinned,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      formatting: formatting ?? this.formatting,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mood: mood ?? this.mood,
      tags: tags ?? this.tags,
      attachments: attachments ?? this.attachments,
      backgroundImageId: clearBackground
          ? null
          : (backgroundImageId ?? this.backgroundImageId),
      backgroundColor: clearBackground
          ? null
          : (backgroundColor ?? this.backgroundColor),
      isPinned: isPinned ?? this.isPinned,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'formatting': formatting.map((f) => f.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'mood': mood,
      'tags': tags,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'backgroundImageId': backgroundImageId,
      'backgroundColor': backgroundColor,
      'isPinned': isPinned,
    };
  }

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    // Handle legacy attachedMediaIds field
    List<NoteAttachment> attachments = [];
    if (json['attachments'] != null) {
      attachments = (json['attachments'] as List<dynamic>)
          .map((a) => NoteAttachment.fromJson(a as Map<String, dynamic>))
          .toList();
    }

    return JournalEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
      formatting:
          (json['formatting'] as List<dynamic>?)
              ?.map((f) => TextFormatting.fromJson(f as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      mood: json['mood'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      attachments: attachments,
      backgroundImageId: json['backgroundImageId'] as String?,
      backgroundColor: json['backgroundColor'] as int?,
      isPinned: json['isPinned'] as bool? ?? false,
    );
  }

  String toEncodedJson() => jsonEncode(toJson());

  factory JournalEntry.fromEncodedJson(String encoded) {
    return JournalEntry.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
  }

  /// Get plain text content for display in list view
  String get plainTextContent {
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

  /// Get image attachments only
  List<NoteAttachment> get imageAttachments =>
      attachments.where((a) => a.isImage).toList();

  /// Get audio attachments only
  List<NoteAttachment> get audioAttachments =>
      attachments.where((a) => a.isAudio).toList();

  /// Check if note has any attachments
  bool get hasAttachments => attachments.isNotEmpty;

  /// Check if note has a custom background
  bool get hasBackground =>
      backgroundImageId != null || backgroundColor != null;

  /// Get content formatted spans for thumbnail display
  /// Returns a list of (text, isBold, isItalic) tuples
  List<ContentSpan> get formattedContentSpans {
    if (content.isEmpty) return [];

    try {
      final jsonContent = jsonDecode(content);
      if (jsonContent is List) {
        final spans = <ContentSpan>[];
        for (final op in jsonContent) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String && insert.isNotEmpty) {
              final attrs = op['attributes'] as Map<String, dynamic>?;
              final isBold = attrs?['bold'] == true;
              final isItalic = attrs?['italic'] == true;
              spans.add(
                ContentSpan(text: insert, isBold: isBold, isItalic: isItalic),
              );
            }
          }
        }
        return spans;
      }
    } catch (e) {
      // Plain text fallback
    }
    return [ContentSpan(text: content.trim(), isBold: false, isItalic: false)];
  }
}

/// Represents a span of content with formatting
class ContentSpan {
  final String text;
  final bool isBold;
  final bool isItalic;

  ContentSpan({
    required this.text,
    required this.isBold,
    required this.isItalic,
  });
}

/// Text formatting types
enum FormatType {
  bold,
  italic,
  bulletDot,
  bulletNumber,
  checkbox,
  checkboxChecked,
}

class TextFormatting {
  final int start;
  final int end;
  final String type;
  final int? listIndex; // For numbered lists

  TextFormatting({
    required this.start,
    required this.end,
    required this.type,
    this.listIndex,
  });

  Map<String, dynamic> toJson() {
    return {'start': start, 'end': end, 'type': type, 'listIndex': listIndex};
  }

  factory TextFormatting.fromJson(Map<String, dynamic> json) {
    return TextFormatting(
      start: json['start'] as int,
      end: json['end'] as int,
      type: json['type'] as String,
      listIndex: json['listIndex'] as int?,
    );
  }

  bool get isBold => type == 'bold';
  bool get isItalic => type == 'italic';
  bool get isBulletDot => type == 'bulletDot';
  bool get isBulletNumber => type == 'bulletNumber';
  bool get isCheckbox => type == 'checkbox';
  bool get isCheckboxChecked => type == 'checkboxChecked';
}
