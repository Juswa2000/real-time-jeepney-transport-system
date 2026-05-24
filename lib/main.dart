import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';

import 'app_state.dart';
import 'screens/admin_page.dart';
import 'screens/auth_gate.dart';
import 'screens/commuter_page.dart';
import 'screens/commuter_register_page.dart';
import 'screens/driver_page.dart';
import 'screens/driver_register_page.dart';
import 'screens/login_page.dart';
import 'screens/register_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const JeepJeepApp());
}

class JeepJeepApp extends StatelessWidget {
  const JeepJeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      notifier: AppState(),
      child: MaterialApp(
        title: 'JeepJeep Transport Strike',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          scaffoldBackgroundColor: Colors.grey[50],
          cardTheme: const CardThemeData(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
          ),
        ),
        home: const AuthGate(),
        routes: {
          '/login': (context) => const LoginPage(),
          '/register': (context) => const RegisterPage(),
          '/register-driver': (context) => const DriverRegisterPage(),
          '/register-commuter': (context) => const CommuterRegisterPage(),
          '/commuter': (context) => const CommuterPage(),
          '/driver': (context) => const DriverPage(),
          '/admin': (context) => const AdminPage(),
        },
      ),
    );
  }
}
