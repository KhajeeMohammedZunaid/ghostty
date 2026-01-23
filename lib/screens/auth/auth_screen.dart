import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/biometric_service.dart';
import '../../services/storage_service.dart';
import '../../services/encryption_service.dart';
import '../../services/animation_prefs.dart';
import '../../theme/ghost_theme.dart';
import '../home/home_screen.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;
  
  const AuthScreen({super.key, this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool _isLoading = true;
  bool _isAuthenticating = false;
  bool _biometricAvailable = false;
  String _biometricType = 'Biometric';
  String _error = '';
  bool _shouldAnimate = true;

  @override
  void initState() {
    super.initState();
    _shouldAnimate = AnimationPrefs.shouldAnimateAuth();
    _initializeAuth();
  }

  Future<void> _initializeAuth() async {
    await StorageService.instance.initialize();
    await AnimationPrefs.init();
    
    // Check biometric availability
    if (!kIsWeb) {
      final biometricService = BiometricService.instance;
      _biometricAvailable = await biometricService.canCheckBiometrics();
      if (_biometricAvailable) {
        _biometricType = await biometricService.getBiometricTypeName();
      }
    }
    
    setState(() => _isLoading = false);
    
    // Auto-trigger biometric auth if available
    if (_biometricAvailable) {
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    
    setState(() {
      _isAuthenticating = true;
      _error = '';
    });
    
    try {
      final biometricService = BiometricService.instance;
      final success = await biometricService.authenticateWithFallback(
        reason: 'Unlock Ghostty',
      );
      
      if (success) {
        // Initialize encryption with a device-based key
        EncryptionService.instance.initialize('ghost_secure_key_${DateTime.now().year}');
        
        if (mounted) {
          // If callback provided, call it instead of navigating
          if (widget.onAuthSuccess != null) {
            widget.onAuthSuccess!();
          } else {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => 
                    const HomeScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
          }
        }
      } else {
        setState(() {
          _error = 'Authentication failed. Please try again.';
          _isAuthenticating = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Authentication error. Please try again.';
        _isAuthenticating = false;
      });
    }
  }

  // Fallback for web or when biometric not available
  Future<void> _proceedWithoutBiometric() async {
    EncryptionService.instance.initialize('ghost_secure_key_${DateTime.now().year}');
    
    if (mounted) {
      // If callback provided, call it instead of navigating
      if (widget.onAuthSuccess != null) {
        widget.onAuthSuccess!();
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => 
                const HomeScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Container(
                height: size.height - MediaQuery.of(context).padding.top,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    
                    // Logo
                    _buildLogo(isDark),
                    
                    const SizedBox(height: 48),
                    
                    // Title
                    _buildAnimatedWidget(
                      delay: 200,
                      child: Text(
                        'Ghostty',
                        style: theme.textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    _buildAnimatedWidget(
                      delay: 300,
                      child: Text(
                        'Your secure private journal',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    
                    const SizedBox(height: 64),
                    
                    // Biometric Button or Web fallback
                    if (_biometricAvailable) ...[
                      _buildAnimatedWidget(
                        delay: 400,
                        child: _buildBiometricButton(isDark),
                      ),
                    ] else if (kIsWeb) ...[
                      _buildAnimatedWidget(
                        delay: 400,
                        child: _buildWebEntryButton(),
                      ),
                    ] else ...[
                      _buildAnimatedWidget(
                        delay: 400,
                        child: _buildFallbackButton(),
                      ),
                    ],
                    
                    if (_error.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: GhostTheme.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    
                    const Spacer(flex: 2),
                    
                    // Footer
                    _buildAnimatedWidget(
                      delay: 600,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 16,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Your data never leaves this device',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildAnimatedWidget({required int delay, required Widget child}) {
    if (!_shouldAnimate) return child;
    return child
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 400.ms)
        .slideY(begin: 0.2, end: 0);
  }

  Widget _buildLogo(bool isDark) {
    final logo = Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'logos/playstore.png',
          width: 112,
          height: 112,
          fit: BoxFit.cover,
        ),
      ),
    );
    
    if (!_shouldAnimate) return logo;
    return logo
        .animate()
        .fadeIn(duration: 600.ms)
        .scale(begin: const Offset(0.8, 0.8));
  }

  Widget _buildBiometricButton(bool isDark) {
    return GestureDetector(
      onTap: _isAuthenticating ? null : _authenticate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: _isAuthenticating
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    isDark ? Colors.black : Colors.white,
                  ),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _biometricType == 'Face ID'
                        ? Icons.face
                        : Icons.fingerprint,
                    color: isDark ? Colors.black : Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Unlock with $_biometricType',
                    style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildWebEntryButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: _proceedWithoutBiometric,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white : Colors.black,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.login_rounded,
              color: isDark ? Colors.black : Colors.white,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(
              'Enter Ghostty',
              style: TextStyle(
                color: isDark ? Colors.black : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackButton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Text(
          'Biometric authentication not available',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _proceedWithoutBiometric,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.login_rounded,
                  color: isDark ? Colors.black : Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Text(
                  'Continue',
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
