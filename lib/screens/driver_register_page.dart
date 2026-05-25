import 'package:flutter/material.dart';
import '../app_state.dart';

class DriverRegisterPage extends StatefulWidget {
  const DriverRegisterPage({super.key});

  @override
  State<DriverRegisterPage> createState() => _DriverRegisterPageState();
}

class _DriverRegisterPageState extends State<DriverRegisterPage> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _licenseController = TextEditingController();
  final _plateController = TextEditingController();
  String _selectedRoute = 'ANGELES - SAN FERNANDO';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _licenseController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final appState = AppStateProvider.of(context);
    final name = _nameController.text.trim();
    final contact = _contactController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final license = _licenseController.text.trim();
    final plate = _plateController.text.trim();
    final route = _selectedRoute;

    if (name.isEmpty ||
        contact.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        license.isEmpty ||
        plate.isEmpty ||
        _selectedRoute.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All fields are required for driver registration.'),
        ),
      );
      return;
    }

    print('[DriverRegisterPage] submit pressed for $email');
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Registering driver...')));
    setState(() => _isLoading = true);
    String? error;
    try {
      error = await appState
          .register(
            email,
            password,
            'driver',
            name,
            contactNumber: contact,
            licenseNumber: license,
            plateNumber: plate,
            route: route,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print(
                '[DriverRegisterPage] register timed out after 15s for $email',
              );
              return 'Registration timed out. Check network or Firebase config.';
            },
          );
    } catch (e, st) {
      print('[DriverRegisterPage] register threw: $e');
      print(st);
      error = 'Unexpected error: $e';
    }
    print('[DriverRegisterPage] register returned error=$error');
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    print('[DriverRegisterPage] registration successful; prompting next action');
    await _showPostRegisterDialog(dashboardRoute: '/driver');
  }

  Future<void> _showPostRegisterDialog({required String dashboardRoute}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Account Created'),
          content: const Text(
              'Your account was created successfully. Where would you like to go next?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Back to Login'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Go to Dashboard'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (result == true) {
      Navigator.pushReplacementNamed(context, dashboardRoute);
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Driver Registration')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Driver Signup',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your official details to manage routes and share live updates.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                _buildField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _contactController,
                  label: 'Contact Number',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock,
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _licenseController,
                  label: 'License Number',
                  icon: Icons.card_membership,
                ),
                const SizedBox(height: 16),
                _buildField(
                  controller: _plateController,
                  label: 'Plate Number',
                  icon: Icons.directions_bus,
                ),
                const SizedBox(height: 16),
                _buildRouteDropdown(),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Create Driver Account'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () => Navigator.pushReplacementNamed(context, '/login'),
                  child: const Text('Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Widget _buildRouteDropdown() {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Route',
        prefixIcon: const Icon(Icons.map),
        border: const OutlineInputBorder(),
      ),
      child: DropdownButton<String>(
        value: _selectedRoute,
        underline: const SizedBox(),
        isExpanded: true,
        items: const [
          DropdownMenuItem(
            value: 'ANGELES - SAN FERNANDO',
            child: Text('ANGELES - SAN FERNANDO'),
          ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _selectedRoute = value);
          }
        },
      ),
    );
  }
}
