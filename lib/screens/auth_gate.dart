import 'package:flutter/material.dart';

import '../app_state.dart';
import 'admin_page.dart';
import 'commuter_page.dart';
import 'driver_page.dart';
import 'login_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);

    return AnimatedBuilder(
      animation: appState,
      builder: (context, child) {
        if (appState.authLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!appState.isLoggedIn) {
          return const LoginPage();
        }

        switch (appState.userRole.toLowerCase()) {
          case 'commuter':
            return const CommuterPage();
          case 'driver':
            return const DriverPage();
          case 'admin':
            return const AdminPage();
          default:
            return const Scaffold(
              body: Center(
                child: Text(
                  'Unable to determine your role. Please log out and log in again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
        }
      },
    );
  }
}
