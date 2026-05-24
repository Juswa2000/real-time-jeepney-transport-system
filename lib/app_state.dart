import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState() {
    _routes = [
      JeepneyRoute(
        name: 'San Fernando',
        status: RouteStatus.active,
        estimatedWaitMinutes: 4,
        currentJeepneys: 3,
        latestLocation: 'Near Central Plaza',
        routeCode: 'SF-01',
      ),
      JeepneyRoute(
        name: 'Mabalacat',
        status: RouteStatus.delayed,
        estimatedWaitMinutes: 12,
        currentJeepneys: 1,
        latestLocation: 'Before Bypass',
        routeCode: 'MB-02',
      ),
      JeepneyRoute(
        name: 'Bamban',
        status: RouteStatus.noTrips,
        estimatedWaitMinutes: 0,
        currentJeepneys: 0,
        latestLocation: 'No active jeeps',
        routeCode: 'BB-03',
      ),
      JeepneyRoute(
        name: 'Porac',
        status: RouteStatus.active,
        estimatedWaitMinutes: 6,
        currentJeepneys: 2,
        latestLocation: 'Heading to Plaza',
        routeCode: 'PC-04',
      ),
    ];

    _drivers = [
      DriverInfo(
        name: 'Juan Dela Cruz',
        status: DriverStatus.offline,
        location: 'Not shared',
        available: false,
        assignedRoute: 'San Fernando',
      ),
      DriverInfo(
        name: 'Maria Santos',
        status: DriverStatus.offline,
        location: 'Not shared',
        available: false,
        assignedRoute: 'Mabalacat',
      ),
      DriverInfo(
        name: 'Pedro Reyes',
        status: DriverStatus.offline,
        location: 'Not shared',
        available: false,
        assignedRoute: 'Porac',
      ),
    ];

    _activityLog.add('System started. Monitoring routes and drivers.');
    _initializeAuth();
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? user;
  String userRole = '';
  bool adminLoggedIn = false;
  bool authLoading = true;

  String get displayName {
    if (adminLoggedIn) return 'Admin';
    return user?.displayName ?? user?.email?.split('@').first ?? 'Guest';
  }

  bool get isLoggedIn => user != null || adminLoggedIn;

  late List<JeepneyRoute> _routes;
  late List<DriverInfo> _drivers;
  final List<String> _activityLog = [];
  String _searchText = '';

  List<JeepneyRoute> get routes {
    if (_searchText.isEmpty) {
      return _routes;
    }
    final query = _searchText.toLowerCase();
    return _routes
        .where((route) => route.name.toLowerCase().contains(query))
        .toList();
  }

  List<DriverInfo> get drivers => List.unmodifiable(_drivers);

  List<String> get activityLog => List.unmodifiable(_activityLog.reversed);

  String get searchText => _searchText;

  Future<void> _initializeAuth() async {
    _auth.authStateChanges().listen((firebaseUser) async {
      authLoading = true;
      notifyListeners();

      user = firebaseUser;
      if (user != null) {
        userRole = await _loadUserRole(user!.uid);
      } else {
        userRole = '';
      }

      authLoading = false;
      notifyListeners();
    });
  }

  Future<String?> login(String email, String password) async {
    // Test accounts for development
    if (email == 'admin' && password == 'admin123') {
      adminLoggedIn = true;
      userRole = 'admin';
      notifyListeners();
      return null;
    }
    
    if (email == 'driver' && password == 'driver123') {
      userRole = 'driver';
      // Create a test driver in Firestore with fixed ID
      await _firestore.collection('drivers').doc('test_driver').set({
        'email': email,
        'status': 'offline',
        'latitude': 15.5,
        'longitude': 120.5,
        'demand': 'LOW',
      });
      notifyListeners();
      return null;
    }
    
    if (email == 'commuter' && password == 'commuter123') {
      userRole = 'commuter';
      // Create a test commuter in Firestore
      final testCommueterId = 'test_commuter_${DateTime.now().millisecondsSinceEpoch}';
      await _firestore.collection('commuters').doc(testCommueterId).set({
        'email': email,
        'status': 'active',
      });
      notifyListeners();
      return null;
    }

    try {
      authLoading = true;
      notifyListeners();

      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      user = credential.user;
      if (user != null) {
        userRole = await _loadUserRole(user!.uid);
      } else {
        userRole = '';
      }

      authLoading = false;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (exception) {
      authLoading = false;
      notifyListeners();
      return exception.message ?? 'Unable to login. Please try again.';
    }
  }

  Future<String?> register(
    String email,
    String password,
    String role,
    String name, {
    String? contactNumber,
    String? licenseNumber,
    String? plateNumber,
    String? route,
  }) async {
    try {
      print('[AppState] register: start for $email, role=$role');
      final result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      print('[AppState] register: auth created user: ${result.user?.uid}');
      final userId = result.user?.uid;
      if (userId != null) {
        final userData = <String, dynamic>{
          'email': email,
          'name': name,
          'role': role,
          'createdAt': FieldValue.serverTimestamp(),
          'lastActive': FieldValue.serverTimestamp(),
        };

        if (role == 'driver') {
          userData['contactNumber'] = contactNumber ?? '';
          userData['licenseNumber'] = licenseNumber ?? '';
          userData['plateNumber'] = plateNumber ?? '';
          userData['route'] = route ?? '';
        }

        print('[AppState] register: writing user doc for $userId');
        await _firestore.collection('users').doc(userId).set(userData);

        if (role == 'driver') {
          print('[AppState] register: writing driver doc for $userId');
          await _firestore.collection('drivers').doc(userId).set({
            'fullName': name,
            'email': email,
            'contactNumber': contactNumber ?? '',
            'licenseNumber': licenseNumber ?? '',
            'plateNumber': plateNumber ?? '',
            'route': route ?? '',
            'availableSeats': 10,
            'statusColor': 'green',
            'statusLabel': 'Vacant',
            'latitude': 15.13,
            'longitude': 120.65,
            'gpsEnabled': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('[AppState] register: driver doc write complete for $userId');
        } else if (role == 'commuter') {
          print('[AppState] register: writing commuter doc for $userId');
          await _firestore.collection('commuters').doc(userId).set({
            'fullName': name,
            'email': email,
            'status': 'active',
            'createdAt': FieldValue.serverTimestamp(),
          });
          print('[AppState] register: commuter doc write complete for $userId');
        }

        print('[AppState] register: firestore write complete for $userId');
        userRole = role;
      }
      print('[AppState] register: finished');
      return null;
    } on FirebaseAuthException catch (exception) {
      print(
        '[AppState] register: FirebaseAuthException (${exception.code}): ${exception.message}',
      );
      String friendly;
      switch (exception.code) {
        case 'email-already-in-use':
          friendly =
              'This email is already registered. Please log in or use a different email.';
          break;
        case 'weak-password':
          friendly = 'Password is too weak. Use at least 6 characters.';
          break;
        case 'invalid-email':
          friendly = 'The email address is invalid. Please correct it.';
          break;
        case 'operation-not-allowed':
          friendly = 'Email/password sign-in is not enabled in Firebase.';
          break;
        default:
          friendly =
              exception.message ?? 'Unable to register. Please try again.';
      }
      return friendly;
    } catch (e, st) {
      print('[AppState] register: unexpected error: $e');
      print(st);
      return 'Unexpected error during registration.';
    }
  }

  Future<void> logout() async {
    if (adminLoggedIn) {
      adminLoggedIn = false;
    }
    await _auth.signOut();
    user = null;
    userRole = '';
    notifyListeners();
  }

  Future<void> setUserRole(String role) async {
    if (user == null) return;
    userRole = role;
    await _firestore.collection('users').doc(user!.uid).update({
      'role': role,
      'lastActive': FieldValue.serverTimestamp(),
    });
    notifyListeners();
  }

  Future<String> _loadUserRole(String uid) async {
    try {
      final snapshot = await _firestore.collection('users').doc(uid).get();
      final data = snapshot.data();
      if (data == null) return '';

      final role = data['role'] as String?;
      if (role != null && role.isNotEmpty) {
        return role;
      }

      final hasDriverFields = (data['licenseNumber'] as String?)?.isNotEmpty == true ||
          (data['plateNumber'] as String?)?.isNotEmpty == true ||
          (data['route'] as String?)?.isNotEmpty == true;
      if (hasDriverFields) {
        return 'driver';
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  void updateSearch(String text) {
    _searchText = text;
    notifyListeners();
  }

  void toggleDriverStatus(DriverInfo driver, DriverStatus newStatus) {
    driver.status = newStatus;
    if (newStatus == DriverStatus.operating) {
      driver.available = true;
      driver.location = _randomLocationForRoute(driver.assignedRoute);
      _updateRouteStatus(driver.assignedRoute, RouteStatus.active);
      _activityLog.insert(
        0,
        '${driver.name} is now operating on ${driver.assignedRoute}.',
      );
    } else if (newStatus == DriverStatus.onBreak) {
      driver.available = false;
      driver.location = 'On break near ${_routeLandmark(driver.assignedRoute)}';
      _activityLog.insert(0, '${driver.name} is on break.');
    } else {
      driver.available = false;
      driver.location = 'Offline';
      _activityLog.insert(0, '${driver.name} is offline.');
      _updateRouteStatus(driver.assignedRoute, RouteStatus.noTrips);
    }
    notifyListeners();
  }

  void shareDriverLocation(DriverInfo driver) {
    driver.location = _randomLocationForRoute(driver.assignedRoute);
    _activityLog.insert(
      0,
      '${driver.name} shared location on ${driver.assignedRoute}.',
    );
    notifyListeners();
  }

  void setDriverAvailability(DriverInfo driver, bool available) {
    driver.available = available;
    final statusText = available ? 'available' : 'not available';
    _activityLog.insert(0, '${driver.name} toggled availability: $statusText.');
    notifyListeners();
  }

  String scanQRCode(String routeName) {
    final route = _routes.firstWhere(
      (route) => route.name == routeName,
      orElse: () => _routes.first,
    );
    final result =
        'QR:${route.routeCode}:${route.name}:${DateTime.now().millisecondsSinceEpoch}';
    _activityLog.insert(0, 'Commuter scanned QR for ${route.name}.');
    return result;
  }

  String driverDemandSummary(DriverInfo driver) {
    final demand = Random().nextInt(8) + 2;
    return '$demand passengers waiting on ${driver.assignedRoute}';
  }

  void addAdminAction(String message) {
    _activityLog.insert(0, message);
    notifyListeners();
  }

  void registerDriver(DriverInfo driver) {
    _drivers.add(driver);
    _activityLog.insert(0, 'Driver account registered: ${driver.name}.');
    notifyListeners();
  }

  void _updateRouteStatus(String routeName, RouteStatus status) {
    final route = _routes.firstWhere(
      (route) => route.name == routeName,
      orElse: () => _routes.first,
    );
    route.status = status;
    if (status == RouteStatus.noTrips) {
      route.currentJeepneys = 0;
      route.estimatedWaitMinutes = 0;
      route.latestLocation = 'No active jeeps';
    } else if (status == RouteStatus.active && route.currentJeepneys == 0) {
      route.currentJeepneys = 1;
      route.estimatedWaitMinutes = 6;
      route.latestLocation = 'Departing soon';
    }
  }

  String _randomLocationForRoute(String routeName) {
    final points = <String>[
      'Near market',
      'Before terminal',
      'After highway exit',
      'At intersection',
      'Approaching plaza',
    ];
    return '${points[Random().nextInt(points.length)]} on $routeName route';
  }

  String _routeLandmark(String routeName) {
    switch (routeName) {
      case 'San Fernando':
        return 'Plaza';
      case 'Mabalacat':
        return 'Bypass';
      case 'Porac':
        return 'Bridge';
      default:
        return 'route stop';
    }
  }
}

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({
    super.key,
    required AppState notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AppState of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<AppStateProvider>();
    assert(provider != null, 'No AppStateProvider found in context');
    return provider!.notifier!;
  }
}
