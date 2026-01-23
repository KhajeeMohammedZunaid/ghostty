import 'package:flutter/material.dart';
import '../theme/ghost_theme.dart';

/// A beautifully designed custom modal for confirmations
class GhostModal extends StatelessWidget {
  final String title;
  final String message;
  final String? confirmText;
  final String? cancelText;
  final IconData? icon;
  final Color? iconColor;
  final bool isDangerous;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const GhostModal({
    super.key,
    required this.title,
    required this.message,
    this.confirmText,
    this.cancelText,
    this.icon,
    this.iconColor,
    this.isDangerous = false,
    this.onConfirm,
    this.onCancel,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String? confirmText,
    String? cancelText,
    IconData? icon,
    Color? iconColor,
    bool isDangerous = false,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GhostModal(
          title: title,
          message: message,
          confirmText: confirmText,
          cancelText: cancelText,
          icon: icon,
          iconColor: iconColor,
          isDangerous: isDangerous,
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveIconColor = iconColor ?? (isDangerous ? GhostTheme.error : GhostTheme.primary);

    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isDark ? GhostTheme.darkCard : GhostTheme.lightCard,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon ?? (isDangerous ? Icons.warning_rounded : Icons.info_rounded),
                    size: 36,
                    color: effectiveIconColor,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                
                // Message
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                
                // Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                          onCancel?.call();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: BorderSide(
                            color: isDark ? GhostTheme.darkBorder : GhostTheme.lightBorder,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          cancelText ?? 'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop(true);
                          onConfirm?.call();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDangerous ? GhostTheme.error : GhostTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          confirmText ?? 'Confirm',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A progress modal for showing loading states
class GhostProgressModal extends StatelessWidget {
  final String title;
  final String? message;
  final double? progress;

  const GhostProgressModal({
    super.key,
    required this.title,
    this.message,
    this.progress,
  });

  static void show({
    required BuildContext context,
    required String title,
    String? message,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => GhostProgressModal(
        title: title,
        message: message,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: BoxDecoration(
          color: isDark ? GhostTheme.darkCard : GhostTheme.lightCard,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (progress != null)
                  CircularProgressIndicator(
                    value: progress,
                    valueColor: const AlwaysStoppedAnimation(GhostTheme.primary),
                  )
                else
                  const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(GhostTheme.primary),
                  ),
                const SizedBox(height: 20),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
