import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// Real-Time Commuter Dashboard for "Real-Time Jeepney Transport Support Platform"
// - Real-time jeepney markers on map
// - Estimated waiting time based on active drivers
// - Live driver list with status updates
// - Notifications for demand changes
// - Refresh functionality for manual updates

class CommuterPage extends StatefulWidget {
  const CommuterPage({super.key});

  @override
  State<CommuterPage> createState() => _CommuterPageState();
}

class _CommuterPageState extends State<CommuterPage> with WidgetsBindingObserver {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final MapController _mapController = MapController();
  // Track last-known driver positions for smooth animation
  final Map<String, LatLng> _driverPositions = {};
  // Store lightweight metadata for markers (name, plate, status)
  final Map<String, Map<String, dynamic>> _driverMeta = {};
  // Track active animation timers per driver
  final Map<String, Timer> _animationTimers = {};
  // Prevent overlapping animations
  final Set<String> _animating = {};
  
  final List<String> _notifications = [];
  StreamSubscription<Position>? _sharingSubscription;
  bool _sharingLocationToDrivers = false;
  bool _sharingLocationInProgress = false;
  String _prevDemand = 'LOW';
  int _selectedTabIndex = 0;
  String? _registeredName;

  static const _openRouteServiceApiKey = 'YOUR_OPENROUTESERVICE_API_KEY';
  static const _routeStart = LatLng(15.1455, 120.5979);
  static const _routeEnd = LatLng(15.0578, 120.6715);
  final List<LatLng> _routePoints = [];
  bool _routeLoading = true;
  bool _usingFallbackRoute = false;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _addNotification('Welcome to Commuter Portal! Tracking jeepneys for you.');
    _loadRegisteredName();
    _restoreSharingState();
    _fetchRouteGeometry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sharingSubscription?.cancel();
    for (final t in _animationTimers.values) t.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // When app is backgrounded/closed, stop sharing so driver map no longer shows stale commuter markers.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      _stopSharingToDrivers();
    }
  }

  Future<void> _loadRegisteredName() async {
    final user = _auth.currentUser;
    if (user == null) return;

    String name = 'Commuter';
    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      if (userData != null) {
        name = (userData['name'] as String?)?.trim() ?? name;
      }
      if (name == 'Commuter' || name.isEmpty) {
        final commuterDoc = await _firestore.collection('commuters').doc(user.uid).get();
        final commuterData = commuterDoc.data();
        name = (commuterData?['fullName'] as String?)?.trim() ?? name;
      }
    } catch (_) {
      // ignore errors and keep fallback name
    }

    if (mounted) {
      setState(() {
        _registeredName = name;
      });
    }
  }

  Future<void> _restoreSharingState() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final commuterDoc = await _firestore.collection('commuters').doc(user.uid).get();
      final commuterData = commuterDoc.data();
      final sharing = (commuterData?['shareOnDriverMap'] as bool?) ?? false;
      if (sharing) {
        if (mounted) {
          setState(() => _sharingLocationToDrivers = true);
        }
        await _startSharingToDrivers();
      }
    } catch (_) {
      // ignore restore errors
    }
  }

  Future<bool> _requestLocationAccess() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _addNotification('Location services are disabled. Turn them on to share your location.');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _addNotification('Location permission denied. Enable it so drivers can see your pickup point.');
      return false;
    }

    return true;
  }

  Future<void> _startSharingToDrivers() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (_sharingLocationInProgress) return;

    final allowed = await _requestLocationAccess();
    if (!allowed) return;

    setState(() {
      _sharingLocationInProgress = true;
    });

    try {
      final commuterDoc = _firestore.collection('commuters').doc(user.uid);
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      await commuterDoc.set({
        'shareOnDriverMap': true,
        'gpsEnabled': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'lastSharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _sharingSubscription?.cancel();
      _sharingSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          distanceFilter: 10,
        ),
      ).listen((position) async {
        try {
          await commuterDoc.set({
            'shareOnDriverMap': true,
            'gpsEnabled': true,
            'latitude': position.latitude,
            'longitude': position.longitude,
            'lastSharedAt': FieldValue.serverTimestamp(),
            'heading': position.heading,
            'speed': position.speed,
          }, SetOptions(merge: true));
        } catch (_) {
          // Ignore transient location write errors while live sharing.
        }
      }, onError: (_) {
        _addNotification('Location sharing stopped due to a tracking error.');
      });

      if (mounted) {
        setState(() {
          _sharingLocationToDrivers = true;
          _sharingLocationInProgress = false;
        });
      }
      _addNotification('Your location is now visible to drivers on their live map.');
    } catch (e) {
      if (mounted) {
        setState(() => _sharingLocationInProgress = false);
      }
      _addNotification('Failed to start location sharing: $e');
    }
  }

  Future<void> _stopSharingToDrivers() async {
    final user = _auth.currentUser;
    if (user == null) return;

    _sharingSubscription?.cancel();
    _sharingSubscription = null;

    try {
      await _firestore.collection('commuters').doc(user.uid).set({
        'shareOnDriverMap': false,
        'gpsEnabled': false,
        'lastSharedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Ignore write errors on stop.
    }

    if (mounted) {
      setState(() {
        _sharingLocationToDrivers = false;
        _sharingLocationInProgress = false;
      });
    }

    _addNotification('You stopped sharing your location with drivers.');
  }

  void _addNotification(String msg) {
    if (mounted) {
      setState(() {
        _notifications.insert(0, '[${DateTime.now().toString().split('.')[0]}] $msg');
        if (_notifications.length > 10) _notifications.removeLast();
      });
    }
  }

  // Determine route status based on active drivers and passenger demand
  String _determineRouteStatus(int activeDrivers, String demand) {
    if (activeDrivers == 0) return 'No Trips';
    if (activeDrivers < 2 || demand == 'HIGH') return 'Limited';
    return 'Available';
  }

  // Build map markers for each active driver
  // Build markers based on the last-known animated positions
  List<Marker> _buildDriverMarkersFromState() {
    return _driverPositions.entries.map((entry) {
      final id = entry.key;
      final pos = entry.value;
      final meta = _driverMeta[id] ?? {};
      final gpsEnabled = (meta['gpsEnabled'] as bool?) ?? true;
      if (!gpsEnabled || pos.latitude == 0 && pos.longitude == 0) return null;

      final plateNumber = meta['plateNumber'] as String? ?? 'Unknown';
      final fullName = meta['fullName'] as String? ?? 'Driver';
      final statusColor = (meta['statusColor'] as String?)?.toLowerCase() ?? 'blue';

      final markerColor = statusColor == 'green'
          ? Colors.green
          : statusColor == 'orange'
              ? Colors.orange
              : statusColor == 'red'
                  ? Colors.red
                  : Colors.blue;

      return Marker(
        point: pos,
        width: 80,
        height: 80,
        child: GestureDetector(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$fullName ($plateNumber)')),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: markerColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.directions_car, color: Colors.white, size: 20),
              ),
              Text(plateNumber, style: const TextStyle(fontSize: 10, backgroundColor: Colors.white))
            ],
          ),
        ),
      );
    }).whereType<Marker>().toList();
  }

  LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
    return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
  }

  void _startMarkerAnimation(String id, LatLng from, LatLng to, {int durationMs = 600}) {
    if (_animating.contains(id)) return;
    _animating.add(id);

    _animationTimers[id]?.cancel();
    final int steps = 12;
    int step = 0;
    final interval = Duration(milliseconds: (durationMs / steps).round());

    _animationTimers[id] = Timer.periodic(interval, (timer) {
      step++;
      final t = (step / steps).clamp(0.0, 1.0);
      final next = _lerpLatLng(from, to, t);
      _driverPositions[id] = next;
      if (mounted) setState(() {});

      if (t >= 1.0) {
        timer.cancel();
        _animationTimers.remove(id);
        _animating.remove(id);
      }
    });
  }

  List<LatLng> _buildFallbackRoutePoints() {
    return [
      const LatLng(15.121953, 120.600196),
      const LatLng(15.120363, 120.601451),
      const LatLng(15.120073, 120.601730),
      const LatLng(15.119763, 120.602100),
      const LatLng(15.119229, 120.602766),
      const LatLng(15.118030, 120.604635),
      const LatLng(15.117145, 120.606030),
      const LatLng(15.116870, 120.606440),
      const LatLng(15.116712, 120.606650),
      const LatLng(15.116498, 120.606886),
      const LatLng(15.116218, 120.607143),
      const LatLng(15.115133, 120.608095),
      const LatLng(15.113750, 120.609281),
      const LatLng(15.112453, 120.610423),
      const LatLng(15.110689, 120.611974),
      const LatLng(15.110060, 120.612502),
      const LatLng(15.109861, 120.612682),
      const LatLng(15.101825, 120.619704),
      const LatLng(15.089305, 120.630610),
      const LatLng(15.084959, 120.634410),
      const LatLng(15.080877, 120.637972),
      const LatLng(15.078319, 120.640209),
      const LatLng(15.077334, 120.641062),
      const LatLng(15.077334, 120.641062),
      const LatLng(15.074975, 120.643125),
      const LatLng(15.074589, 120.643433),
      const LatLng(15.073222, 120.644648),
      const LatLng(15.070642, 120.646888),
      const LatLng(15.067244, 120.649881),
      const LatLng(15.065309, 120.651566),
      const LatLng(15.063509, 120.653148),
      const LatLng(15.061199, 120.655165),
      const LatLng(15.059365, 120.656764),
      const LatLng(15.058272, 120.657687),
      const LatLng(15.055957, 120.659698),
      const LatLng(15.054231, 120.661238),
      const LatLng(15.053879, 120.661517),
      const LatLng(15.051815, 120.663499),
      const LatLng(15.050136, 120.665208),
      const LatLng(15.049709, 120.665642),
      const LatLng(15.049279, 120.666111),
      const LatLng(15.048673, 120.666884),
      const LatLng(15.047989, 120.667868),
      const LatLng(15.047243, 120.668922),
      const LatLng(15.046790, 120.669590),
      const LatLng(15.046028, 120.670719),
      const LatLng(15.042109, 120.676500),
      const LatLng(15.041239, 120.677776),
      const LatLng(15.040586, 120.678763),
      const LatLng(15.038957, 120.680880),
      const LatLng(15.036514, 120.683742),
      const LatLng(15.034825, 120.685823),
      const LatLng(15.033955, 120.686869),
      const LatLng(15.033556, 120.687625),
      const LatLng(15.033408, 120.688258),
      const LatLng(15.032916, 120.693392),
      const LatLng(15.032608, 120.693400),
      const LatLng(15.031825, 120.693363),
      const LatLng(15.031085, 120.693325),
      const LatLng(15.030403, 120.693475),
      const LatLng(15.030388, 120.694511),
      const LatLng(15.031393, 120.694275),
      const LatLng(15.031973, 120.694138),
      const LatLng(15.032325, 120.694114),
      const LatLng(15.032841, 120.694122),
      const LatLng(15.032916, 120.693392),
      const LatLng(15.033408, 120.688258),
      const LatLng(15.033556, 120.687625),
      const LatLng(15.033955, 120.686869),
      const LatLng(15.034825, 120.685823),
      const LatLng(15.036514, 120.683742),
      const LatLng(15.038957, 120.680880),
      const LatLng(15.040389, 120.682422),
      const LatLng(15.041311, 120.683613),
      const LatLng(15.042151, 120.684825),
      const LatLng(15.042586, 120.685533),
      const LatLng(15.044813, 120.689127),
      const LatLng(15.044360, 120.688401),
    ];
  }

  void _loadFallbackRoute() {
    if (!mounted) return;

    setState(() {
      _routePoints
        ..clear()
        ..addAll(_buildFallbackRoutePoints());
      _routeLoading = false;
      _routeError = null;
      _usingFallbackRoute = true;
    });
  }

  Future<void> _fetchRouteGeometry() async {
    if (_openRouteServiceApiKey.contains('YOUR_')) {
      _loadFallbackRoute();
      return;
    }

    _usingFallbackRoute = false;

    try {
      final url = Uri.parse('https://api.openrouteservice.org/v2/directions/driving-car/geojson');
      final response = await http.post(
        url,
        headers: {
          'Authorization': _openRouteServiceApiKey,
          'Content-Type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({
          'coordinates': [
            [_routeStart.longitude, _routeStart.latitude],
            [_routeEnd.longitude, _routeEnd.latitude],
          ],
          'instructions': false,
          'elevation': false,
          'geometry_simplify': false,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('OpenRouteService request failed with status ${response.statusCode}');
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final features = body['features'] as List<dynamic>?;
      if (features == null || features.isEmpty) {
        throw Exception('No route returned by OpenRouteService.');
      }

      final geometry = (features.first as Map<String, dynamic>)['geometry'];
      final routePoints = <LatLng>[];

      if (geometry is Map<String, dynamic>) {
        final coords = geometry['coordinates'];
        if (coords is List) {
          for (final entry in coords) {
            if (entry is List && entry.length >= 2) {
              final lon = (entry[0] as num).toDouble();
              final lat = (entry[1] as num).toDouble();
              routePoints.add(LatLng(lat, lon));
            }
          }
        } else if (coords is String && coords.isNotEmpty) {
          routePoints.addAll(_decodePolyline(coords));
        }
      } else if (geometry is String && geometry.isNotEmpty) {
        routePoints.addAll(_decodePolyline(geometry));
      }

      if (routePoints.isEmpty) {
        throw Exception('Unable to decode route geometry from OpenRouteService response.');
      }

      if (mounted) {
        setState(() {
          _routePoints
            ..clear()
            ..addAll(routePoints);
          _routeLoading = false;
          _routeError = null;
          _usingFallbackRoute = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _routeError = error.toString();
          _routeLoading = false;
          _usingFallbackRoute = false;
        });
      }
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    final decoded = PolylinePoints.decodePolyline(encoded);
    return decoded.map((point) => LatLng(point.latitude, point.longitude)).toList();
  }

  void _refreshData() {
    _fetchRouteGeometry();
    setState(() {});
    _addNotification('Data refreshed!');
  }

  Future<void> _logout() async {
    // Ensure we stop sharing before signing out so drivers stop seeing the commuter marker.
    await _stopSharingToDrivers();
    await _auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  Widget _buildMapTab(List<DocumentSnapshot<Map<String, dynamic>>> activeDrivers) {
    return SizedBox(
      height: double.infinity,
      child: _buildMapWidget(activeDrivers),
    );
  }

  Widget _buildPassengerShareCard() {
    final statusColor = _sharingLocationToDrivers ? Colors.green : Colors.grey;
    final actionLabel = _sharingLocationToDrivers ? 'Stop Sharing' : 'Share My Location';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Location Access for Drivers',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _sharingLocationToDrivers ? 'Visible' : 'Hidden',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _sharingLocationToDrivers
                  ? 'Your current pickup point is shared with drivers, and they can see it in real time.'
                  : 'Tap the button below to share your location so drivers can see where commuters are waiting.',
              style: const TextStyle(color: Colors.black87, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _sharingLocationInProgress
                    ? null
                    : (_sharingLocationToDrivers ? _stopSharingToDrivers : _startSharingToDrivers),
                icon: Icon(_sharingLocationToDrivers ? Icons.location_off : Icons.location_on),
                label: Text(actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _sharingLocationToDrivers ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJeepneysTab(
    List<DocumentSnapshot<Map<String, dynamic>>> allDrivers,
    List<DocumentSnapshot<Map<String, dynamic>>> activeDrivers,
    String routeStatus,
    String demand,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildPassengerShareCard(),
          const SizedBox(height: 16),
          _buildRouteCard(routeStatus),
          const SizedBox(height: 16),
          _buildJeepneyStatusCard(activeDrivers.length),
          const SizedBox(height: 16),
          _buildDriverStatusGuideCard(),
          const SizedBox(height: 16),
          _buildAvailableDriversList(activeDrivers),
        ],
      ),
    );
  }

  Widget _buildNotificationsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildNotificationsCard(),
    );
  }

  Widget _buildProfileTab() {
    final user = _auth.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue[300],
                    ),
                    child: const Icon(
                      Icons.person,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _registeredName ?? user?.displayName ?? 'Commuter',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    user?.email ?? 'No email',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'User Type:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        'Commuter',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Email:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Expanded(
                        child: Text(
                          user?.email ?? 'N/A',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Account Status:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Commuter Dashboard'),
        elevation: 4,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _refreshData,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('drivers').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 48),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final drivers = snapshot.data?.docs ?? [];
          
          // Filter only drivers with valid GPS data
          final activeDrivers = drivers
              .where((doc) {
                final data = doc.data();
                final gpsEnabled = (data['gpsEnabled'] as bool?) ?? false;
                return gpsEnabled &&
                    data['latitude'] != null &&
                    data['longitude'] != null;
              })
              .toList();

          // Calculate demand from notifications (simple approach)
          final highDemandCount = drivers
              .where((doc) => (doc.data()['demand'] as String?) == 'HIGH')
              .length;
          final currentDemand =
              highDemandCount > (drivers.length ~/ 2) ? 'HIGH' : 'LOW';

          // Notify on demand change
          if (currentDemand != _prevDemand) {
            _addNotification('Passenger demand: $currentDemand');
            _prevDemand = currentDemand;
          }

          final routeStatus =
              _determineRouteStatus(activeDrivers.length, currentDemand);

          // Update driver position state and start animations for changed positions
          final activeIds = <String>{};
          for (final doc in activeDrivers) {
            final id = doc.id;
            activeIds.add(id);
            final data = doc.data() as Map<String, dynamic>? ?? {};
            final lat = (data['latitude'] as num?)?.toDouble();
            final lon = (data['longitude'] as num?)?.toDouble();
            final gpsEnabled = (data['gpsEnabled'] as bool?) ?? false;

            // update meta for marker rendering
            _driverMeta[id] = {
              'plateNumber': data['plateNumber'] as String? ?? 'Unknown',
              'fullName': data['fullName'] as String? ?? 'Driver',
              'statusColor': data['statusColor'] as String? ?? 'blue',
              'gpsEnabled': gpsEnabled,
            };

            if (!gpsEnabled || lat == null || lon == null) continue;

            final newPos = LatLng(lat, lon);
            final prevPos = _driverPositions[id];
            if (prevPos == null) {
              _driverPositions[id] = newPos;
            } else {
              final latDiff = (prevPos.latitude - newPos.latitude).abs();
              final lonDiff = (prevPos.longitude - newPos.longitude).abs();
              if (latDiff > 0.00001 || lonDiff > 0.00001) {
                _startMarkerAnimation(id, prevPos, newPos);
              }
            }
          }

          // Remove positions for drivers that went offline or left
          final toRemove = _driverPositions.keys.where((k) => !activeIds.contains(k)).toList();
          for (final k in toRemove) {
            _driverPositions.remove(k);
            _driverMeta.remove(k);
            _animationTimers[k]?.cancel();
            _animationTimers.remove(k);
            _animating.remove(k);
          }

          return Scaffold(
            body: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildJeepneysTab(drivers, activeDrivers, routeStatus, currentDemand),
                _buildMapTab(activeDrivers),
                _buildNotificationsTab(),
                _buildProfileTab(),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedTabIndex,
              onTap: (index) => setState(() => _selectedTabIndex = index),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.list),
                  label: 'Jeepneys',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.map),
                  label: 'Live Map',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.notifications),
                  label: 'Notification',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // 1. ROUTE HEADER CARD
  Widget _buildRouteCard(String status) {
    final statusColor = status == 'Available'
        ? Colors.green
        : (status == 'Limited' ? Colors.orange : Colors.red);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: statusColor.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Route Status',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Angeles → San Fernando',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_routeLoading)
              const Text(
                'Loading exact road route from OpenRouteService...',
                style: TextStyle(color: Colors.black54),
              )
            else if (_routeError != null)
              Text(
                'Route error: $_routeError',
                style: const TextStyle(color: Colors.redAccent),
              )
            else if (_usingFallbackRoute)
              const Text(
                'Using fallback route preview until an OpenRouteService API key is configured.',
                style: TextStyle(color: Colors.black54),
              )
            else
              const Text(
                'Road-snapped route loaded along MacArthur Highway.',
                style: TextStyle(color: Colors.black54),
              ),
          ],
        ),
      ),
    );
  }

  // 2. LIVE JEEPNEY STATUS CARD
  Widget _buildJeepneyStatusCard(int active) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live Jeepney Status',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Active Jeepneys', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text(
                  '$active',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Status: ${active > 0 ? "AVAILABLE" : "NO TRIPS"}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active > 0 ? Colors.blue : Colors.red,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 4. ESTIMATED WAITING TIME CARD
  Widget _buildDriverStatusGuideCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driver Status Guide',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            _buildStatusGuideRow(
              Colors.green,
              '🟢 GREEN = VACANT',
              'Many seats are available.',
            ),
            const SizedBox(height: 12),
            _buildStatusGuideRow(
              Colors.orange,
              '🟠 ORANGE = LIMITED',
              'Only 1–2 seats remaining.',
            ),
            const SizedBox(height: 12),
            _buildStatusGuideRow(
              Colors.red,
              '🔴 RED = FULL',
              'Jeepney is already full.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusGuideRow(Color color, String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // 3. LIVE MAP SECTION
  Widget _buildMapWidget(List<DocumentSnapshot<Map<String, dynamic>>> activeDrivers) {
    final initialCenter = _routePoints.isNotEmpty
        ? _routePoints[_routePoints.length ~/ 2]
        : const LatLng(15.12, 120.625);

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: 12,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.jeepjeep',
        ),
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                color: Colors.blue,
                strokeWidth: 6,
                borderStrokeWidth: 3,
                borderColor: Colors.white,
              ),
            ],
          ),
        MarkerLayer(
          markers: _buildDriverMarkersFromState(),
        ),
      ],
    );
  }

  // 5. JEEPNEY LIST (AVAILABLE DRIVERS)
  Widget _buildAvailableDriversList(List<DocumentSnapshot<Map<String, dynamic>>> activeDrivers) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Available Jeepneys',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (activeDrivers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No jeepneys currently operating.', style: TextStyle(color: Colors.grey)),
              )
            else
              ...activeDrivers.map((doc) {
                final data = doc.data() ?? {};
                final fullName = data['fullName'] as String? ?? 'Unknown Driver';
                final plateNumber = data['plateNumber'] as String? ?? 'N/A';
                final status = (data['status'] as String?)?.toLowerCase() ?? 'offline';
                final demand = (data['demand'] as String?) ?? 'LOW';

                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_car, color: Colors.white, size: 20),
                  ),
                  title: Text(fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Plate: $plateNumber'),
                      Text(
                        'Demand: $demand',
                        style: TextStyle(
                          color: demand == 'HIGH' ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  trailing: Chip(
                    label: Text(status),
                    backgroundColor: status == 'operating' ? Colors.green : Colors.grey,
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  // 6. NOTIFICATIONS SECTION
  Widget _buildNotificationsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                if (_notifications.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear_all, size: 18),
                    onPressed: () {
                      setState(() => _notifications.clear());
                    },
                    tooltip: 'Clear all',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('No notifications yet.', style: TextStyle(color: Colors.grey)),
              )
            else
              ...List.generate(
                _notifications.length,
                (index) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _notifications[index],
                          style: const TextStyle(fontSize: 12),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
