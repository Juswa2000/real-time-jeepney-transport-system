import 'package:flutter/material.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create an account')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 24),
            const Text('Register as', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _RoleTile(
              title: 'Commuter',
              description: 'Sign up to browse routes and track jeepneys.',
              icon: Icons.person,
              color: Colors.indigo,
              onTap: () => Navigator.pushNamed(context, '/register-commuter'),
            ),
            _RoleTile(
              title: 'Driver',
              description: 'Sign up to update status, share location and receive demand.',
              icon: Icons.drive_eta,
              color: Colors.teal,
              onTap: () => Navigator.pushNamed(context, '/register-driver'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  const _RoleTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(color: color.withAlpha((0.14 * 255).round()), borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.all(14),
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text(description, style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, size: 18, color: Colors.black26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
