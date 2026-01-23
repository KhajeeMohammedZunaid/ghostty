import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/storage_service.dart';
import '../../services/biometric_service.dart';
import '../../theme/ghost_theme.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/custom_modal.dart';
import '../auth/auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;
  bool _biometricAvailable = false;
  String _biometricType = 'Biometric';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkBiometric();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _checkBiometric() async {
    if (!kIsWeb) {
      final available = await BiometricService.isAvailable();
      final type = await BiometricService.getTypeName();
      setState(() {
        _biometricAvailable = available;
        _biometricType = type;
      });
    }
  }

  Future<void> _launchThreadDev() async {
    final uri = Uri.parse('https://threaddev.in');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showAboutScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AboutScreen()),
    );
  }

  void _showUpcomingUpdatesScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const UpcomingUpdatesScreen()),
    );
  }

  Future<void> _clearAllData() async {
    // Step 1: First warning
    final confirm1 = await GhostModal.show(
      context: context,
      title: 'Clear All Data?',
      message: 'This will permanently delete all your journal entries and media files.',
      confirmText: 'Continue',
      cancelText: 'Cancel',
      icon: Icons.warning_rounded,
      isDangerous: true,
    );
    
    if (confirm1 != true) return;
    
    // Step 2: Second warning - more serious
    final confirm2 = await GhostModal.show(
      context: context,
      title: 'Are You Sure?',
      message: 'All your encrypted entries, photos, and settings will be permanently deleted. This cannot be undone.',
      confirmText: 'Yes, Continue',
      cancelText: 'Go Back',
      icon: Icons.delete_forever_rounded,
      isDangerous: true,
    );
    
    if (confirm2 != true) return;
    
    // Step 3: Final confirmation
    final confirm3 = await GhostModal.show(
      context: context,
      title: 'Final Confirmation',
      message: 'After this, there is no going back. Your journal will be completely erased from this device.',
      confirmText: 'Delete Everything',
      cancelText: 'Keep My Data',
      icon: Icons.dangerous_rounded,
      isDangerous: true,
    );
    
    if (confirm3 != true) return;
    
    // Step 4: Require biometric authentication
    final authenticated = await BiometricService.instance.authenticateWithFallback(
      reason: 'Authenticate to confirm data deletion',
    );
    
    if (!authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.shield_rounded, color: GhostTheme.error, size: 20),
                SizedBox(width: 8),
                Text('Authentication failed. Data not deleted.'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            backgroundColor: GhostTheme.error,
          ),
        );
      }
      return;
    }
    
    // All confirmations passed - delete data
    await StorageService.instance.clearAllData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: GhostTheme.success, size: 20),
              SizedBox(width: 8),
              Text('All data cleared successfully'),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      
      // Navigate to auth screen
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _exportData() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_rounded, color: GhostTheme.primary, size: 20),
            SizedBox(width: 8),
            Text('Export feature coming soon'),
          ],
        ),
      ),
    );
  }

  void _logout() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();
    
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Appearance Section
          _buildSectionHeader('Appearance'),
          _buildSettingsCard([
            _buildListTile(
              icon: Icons.palette_rounded,
              title: 'Theme',
              subtitle: _getThemeName(themeProvider.themeMode),
              trailing: PopupMenuButton<ThemeMode>(
                initialValue: themeProvider.themeMode,
                onSelected: (mode) => themeProvider.setThemeMode(mode),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: ThemeMode.system,
                    child: Row(
                      children: [
                        Icon(Icons.brightness_auto_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('System'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: ThemeMode.light,
                    child: Row(
                      children: [
                        Icon(Icons.light_mode_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Light'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: ThemeMode.dark,
                    child: Row(
                      children: [
                        Icon(Icons.dark_mode_rounded, size: 20),
                        SizedBox(width: 12),
                        Text('Dark'),
                      ],
                    ),
                  ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getThemeName(themeProvider.themeMode),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: GhostTheme.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.arrow_drop_down_rounded, color: GhostTheme.primary),
                  ],
                ),
              ),
            ),
          ]),
          
          const SizedBox(height: 24),
          
          // Security Section
          _buildSectionHeader('Security'),
          _buildSettingsCard([
            if (_biometricAvailable || kIsWeb)
              _buildListTile(
                icon: Icons.fingerprint_rounded,
                title: _biometricType,
                subtitle: 'Authentication method',
                trailing: const Icon(Icons.check_circle_rounded, color: GhostTheme.success, size: 20),
              ),
            if (_biometricAvailable || kIsWeb) _buildDivider(),
            _buildListTile(
              icon: Icons.logout_rounded,
              title: 'Lock App',
              subtitle: 'Require authentication on next open',
              titleColor: GhostTheme.error,
              onTap: _logout,
            ),
          ]),
          
          const SizedBox(height: 24),
          
          // Data Section
          _buildSectionHeader('Data'),
          _buildSettingsCard([
            _buildListTile(
              icon: Icons.download_rounded,
              title: 'Export Data',
              subtitle: 'Download your journal entries',
              onTap: _exportData,
            ),
            _buildDivider(),
            _buildListTile(
              icon: Icons.delete_forever_rounded,
              title: 'Clear All Data',
              subtitle: 'Delete all entries and media',
              titleColor: GhostTheme.error,
              onTap: _clearAllData,
            ),
          ]),
          
          const SizedBox(height: 24),
          
          // About Section
          _buildSectionHeader('About'),
          _buildSettingsCard([
            _buildListTile(
              icon: Icons.info_rounded,
              title: 'Ghostty',
              subtitle: 'Version 1.0.0',
              onTap: _showAboutScreen,
            ),
            _buildListTile(
              icon: Icons.upcoming_rounded,
              title: 'Upcoming Updates',
              subtitle: 'What\'s next for Ghostty',
              onTap: _showUpcomingUpdatesScreen,
            ),
          ]),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: GhostTheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? GhostTheme.darkCard : GhostTheme.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? GhostTheme.darkBorder : GhostTheme.lightBorder,
        ),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildListTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    final theme = Theme.of(context);
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (titleColor ?? GhostTheme.primary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: titleColor ?? GhostTheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            )
          : null,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
      onTap: onTap,
    );
  }

  Widget _buildDivider() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Divider(
      height: 1,
      indent: 60,
      color: isDark ? GhostTheme.darkBorder : GhostTheme.lightBorder,
    );
  }

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.system:
        return 'System';
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
    }
  }
}

// About Screen - Clean minimal style
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openThreadDev(BuildContext context) async {
    final uri = Uri.parse('https://threaddev.in');
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Icon - Centered
            Center(
              child: Column(
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'logos/playstore.png',
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ghostty',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // What is Ghostty
            Text(
              'What is Ghostty?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'A private journal that stays private. Your thoughts are encrypted with AES-256 and stored only on your device.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 24),

            // Why Ghostty
            Text(
              'Why Ghostty?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Unlike cloud apps, your data never leaves this device. No accounts, no syncing, no tracking.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 24),

            // Features
            Text(
              'Security',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _buildFeatureRow(context, 'AES-256 encryption'),
            _buildFeatureRow(context, 'Biometric authentication'),
            _buildFeatureRow(context, 'Offline-only storage'),
            _buildFeatureRow(context, 'Screenshot & screen recording prevention'),
            _buildFeatureRow(context, 'No analytics or tracking'),

            const SizedBox(height: 24),

            // Updates info
            Text(
              'Updates',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'App updates are released periodically with new features and improvements. A small amount of mobile data may be required to download updates.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 32),

            // Developer - ThreadDev first
            Center(
              child: Column(
                children: [
                  Text(
                    'Made by',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openThreadDev(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ThreadDev',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: GhostTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: GhostTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Privacy message - plain text at bottom
                  Text(
                    'Made for your privacy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureRow(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// Upcoming Updates Screen - Clean minimal style like About
class UpcomingUpdatesScreen extends StatelessWidget {
  const UpcomingUpdatesScreen({super.key});

  Future<void> _openThreadDev(BuildContext context) async {
    final uri = Uri.parse('https://threaddev.in');
    try {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upcoming'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header - Centered
            Center(
              child: Column(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'logos/playstore.png',
                        width: 70,
                        height: 70,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ghostty',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v1.0.0',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Export Data
            Text(
              'Export Data',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Export your journals and todos to keep a backup or transfer to another device. Your data, your control.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 24),

            // Enhanced Security
            Text(
              'Enhanced Security',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Additional security layers including app lock timeout customization and auto-lock settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 24),

            // Todo Reminders
            Text(
              'Todo Reminders',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set reminders for your todos so you never miss an important task. Smart notifications that respect your privacy.',
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),

            const SizedBox(height: 32),

            // Developer - ThreadDev first
            Center(
              child: Column(
                children: [
                  Text(
                    'Made by',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _openThreadDev(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ThreadDev',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: GhostTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_outward_rounded,
                              size: 14,
                              color: GhostTheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Made for your privacy',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
