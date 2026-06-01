import 'package:flutter/material.dart';

import '../app_state.dart';

class AdminGuard extends StatefulWidget {
  const AdminGuard({required this.child, super.key});

  final Widget child;

  @override
  State<AdminGuard> createState() => _AdminGuardState();
}

class _AdminGuardState extends State<AdminGuard> {
  bool _redirectScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkAuthorization();
  }

  @override
  void didUpdateWidget(covariant AdminGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkAuthorization();
  }

  void _checkAuthorization() {
    final appState = AppStateProvider.of(context);
    if (appState.authLoading || _redirectScheduled) {
      return;
    }

    if (!appState.isLoggedIn || !appState.isAdmin) {
      _redirectScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        if (appState.isLoggedIn) {
          await appState.logout();
        }

        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);

    if (appState.authLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!appState.isLoggedIn) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!appState.isAdmin) {
      return const AccessDeniedPage();
    }

    return widget.child;
  }
}

class AccessDeniedPage extends StatelessWidget {
  const AccessDeniedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Access Denied')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: const [
              Icon(Icons.block, size: 80, color: Colors.redAccent),
              SizedBox(height: 24),
              Text(
                'This portal is for administrators only. Please use the mobile application.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 16),
              Text(
                'You will be redirected to the login page shortly.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WebAccessDeniedPage extends StatefulWidget {
  const WebAccessDeniedPage({super.key});

  @override
  State<WebAccessDeniedPage> createState() => _WebAccessDeniedPageState();
}

class _WebAccessDeniedPageState extends State<WebAccessDeniedPage> {
  bool _hasLoggedOut = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasLoggedOut) {
      _hasLoggedOut = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final appState = AppStateProvider.of(context);
        await appState.logout();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const AccessDeniedPage();
  }
}
