import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:io';
import 'theme/ghost_theme.dart';
import 'providers/theme_provider.dart';
import 'screens/auth/auth_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/todo_editor_screen.dart';
import 'services/storage_service.dart';
import 'services/home_widget_service.dart';
import 'services/todo_storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await StorageService.instance.initialize();
  await TodoStorageService().initialize();
  await HomeWidgetService().initialize();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // TEMPORARILY DISABLED FOR VIDEO DEMO
  // if (Platform.isAndroid || Platform.isIOS) {
  //   await _enableSecureMode();
  // }

  runApp(const GhosttyApp());
}

Future<void> _enableSecureMode() async {
  const platform = MethodChannel('ghostty/secure');
  try {
    await platform.invokeMethod('enableSecureMode');
  } catch (_) {}
}

class GhosttyApp extends StatefulWidget {
  const GhosttyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<GhosttyApp> createState() => _GhosttyAppState();
}

class _GhosttyAppState extends State<GhosttyApp> with WidgetsBindingObserver {
  bool _requiresAuth = false;
  DateTime? _pausedTime;
  static const _navigationChannel = MethodChannel('ghostty/navigation');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupNavigationChannel();
  }

  void _setupNavigationChannel() {
    _navigationChannel.setMethodCallHandler((call) async {
      if (call.method == 'navigate') {
        final action = call.arguments as String?;
        if (action == 'open_todo_editor') {
          // Wait for the app to be ready before navigating
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToTodoEditor();
          });
        }
      }
    });
  }

  void _navigateToTodoEditor() {
    final navigator = GhosttyApp.navigatorKey.currentState;
    if (navigator != null) {
      navigator.push(
        MaterialPageRoute(builder: (context) => const TodoEditorScreen()),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _pausedTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // Require auth if paused > 2s (avoids auth on permission dialogs)
      if (_pausedTime != null) {
        final pausedDuration = DateTime.now().difference(_pausedTime!);
        if (pausedDuration.inSeconds > 2) {
          setState(() => _requiresAuth = true);
        }
        _pausedTime = null;
      }
    }
  }

  void _onAuthComplete() {
    setState(() {
      _requiresAuth = false;
      _pausedTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            navigatorKey: GhosttyApp.navigatorKey,
            title: 'Ghostty',
            debugShowCheckedModeBanner: false,
            theme: GhostTheme.lightTheme(),
            darkTheme: GhostTheme.darkTheme(),
            themeMode: themeProvider.themeMode,
            // Smooth theme animation
            themeAnimationDuration: const Duration(milliseconds: 300),
            themeAnimationCurve: Curves.easeInOut,
            home: _requiresAuth
                ? AuthScreen(onAuthSuccess: _onAuthComplete)
                : const AuthScreen(),
          );
        },
      ),
    );
  }
}
