import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
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

class _CommuterPageState extends State<CommuterPage> {
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
  String _prevDemand = 'LOW';
  int _selectedTabIndex = 0;
  String? _registeredName;

  static const _openRouteServiceApiKey = 'YOUR_OPENROUTESERVICE_API_KEY';
  static const _routeStart = LatLng(15.1455, 120.5979);
  static const _routeEnd = LatLng(15.0578, 120.6715);
  static const List<LatLng> _angelesToSanFernandoDetailedRoute = [
    LatLng(15.145500, 120.597900),
    LatLng(15.145350, 120.598050),
    LatLng(15.145200, 120.598220),
    LatLng(15.145050, 120.598390),
    LatLng(15.144900, 120.598560),
    LatLng(15.144750, 120.598730),
    LatLng(15.144600, 120.598900),
    LatLng(15.144450, 120.599070),
    LatLng(15.144300, 120.599240),
    LatLng(15.144150, 120.599410),
    LatLng(15.144000, 120.599580),
    LatLng(15.143850, 120.599750),
    LatLng(15.143700, 120.599920),
    LatLng(15.143550, 120.600090),
    LatLng(15.143400, 120.600260),
    LatLng(15.143250, 120.600430),
    LatLng(15.143100, 120.600600),
    LatLng(15.142950, 120.600770),
    LatLng(15.142800, 120.600940),
    LatLng(15.142650, 120.601110),
    LatLng(15.142500, 120.601280),
    LatLng(15.142350, 120.601450),
    LatLng(15.142200, 120.601620),
    LatLng(15.142050, 120.601790),
    LatLng(15.141900, 120.601960),
    LatLng(15.141750, 120.602130),
    LatLng(15.141600, 120.602300),
    LatLng(15.141450, 120.602470),
    LatLng(15.141300, 120.602640),
    LatLng(15.141150, 120.602810),
    LatLng(15.141000, 120.602980),
    LatLng(15.140850, 120.603150),
    LatLng(15.140700, 120.603320),
    LatLng(15.140550, 120.603490),
    LatLng(15.140400, 120.603660),
    LatLng(15.140250, 120.603830),
    LatLng(15.140100, 120.604000),
    LatLng(15.139950, 120.604170),
    LatLng(15.139800, 120.604340),
    LatLng(15.139650, 120.604510),
    LatLng(15.139500, 120.604680),
    LatLng(15.139350, 120.604850),
    LatLng(15.139200, 120.605020),
    LatLng(15.139050, 120.605190),
    LatLng(15.138900, 120.605360),
    LatLng(15.138750, 120.605530),
    LatLng(15.138600, 120.605700),
    LatLng(15.138450, 120.605870),
    LatLng(15.138300, 120.606040),
    LatLng(15.138150, 120.606210),
    LatLng(15.138000, 120.606380),
    LatLng(15.137850, 120.606550),
    LatLng(15.137700, 120.606720),
    LatLng(15.137550, 120.606890),
    LatLng(15.137400, 120.607060),
    LatLng(15.137250, 120.607230),
    LatLng(15.137100, 120.607400),
    LatLng(15.136950, 120.607570),
    LatLng(15.136800, 120.607740),
    LatLng(15.136650, 120.607910),
    LatLng(15.136500, 120.608080),
    LatLng(15.136350, 120.608250),
    LatLng(15.136200, 120.608420),
    LatLng(15.136050, 120.608590),
    LatLng(15.135900, 120.608760),
    LatLng(15.135750, 120.608930),
    LatLng(15.135600, 120.609100),
    LatLng(15.135450, 120.609270),
    LatLng(15.135300, 120.609440),
    LatLng(15.135150, 120.609610),
    LatLng(15.135000, 120.609780),
    LatLng(15.134850, 120.609950),
    LatLng(15.134700, 120.610120),
    LatLng(15.134550, 120.610290),
    LatLng(15.134400, 120.610460),
    LatLng(15.134250, 120.610630),
    LatLng(15.134100, 120.610800),
    LatLng(15.133950, 120.610970),
    LatLng(15.133800, 120.611140),
    LatLng(15.133650, 120.611310),
    LatLng(15.133500, 120.611480),
    LatLng(15.133350, 120.611650),
    LatLng(15.133200, 120.611820),
    LatLng(15.133050, 120.611990),
    LatLng(15.132900, 120.612160),
    LatLng(15.132750, 120.612330),
    LatLng(15.132600, 120.612500),
    LatLng(15.132450, 120.612670),
    LatLng(15.132300, 120.612840),
    LatLng(15.132150, 120.613010),
    LatLng(15.132000, 120.613180),
    LatLng(15.131850, 120.613350),
    LatLng(15.131700, 120.613520),
    LatLng(15.131550, 120.613690),
    LatLng(15.131400, 120.613860),
    LatLng(15.131250, 120.614030),
    LatLng(15.131100, 120.614200),
    LatLng(15.130950, 120.614370),
    LatLng(15.130800, 120.614540),
    LatLng(15.130650, 120.614710),
    LatLng(15.130500, 120.614880),
    LatLng(15.130350, 120.615050),
    LatLng(15.130200, 120.615220),
    LatLng(15.130050, 120.615390),
    LatLng(15.129900, 120.615560),
    LatLng(15.129750, 120.615730),
    LatLng(15.129600, 120.615900),
    LatLng(15.129450, 120.616070),
    LatLng(15.129300, 120.616240),
    LatLng(15.129150, 120.616410),
    LatLng(15.129000, 120.616580),
    LatLng(15.128850, 120.616750),
    LatLng(15.128700, 120.616920),
    LatLng(15.128550, 120.617090),
    LatLng(15.128400, 120.617260),
    LatLng(15.128250, 120.617430),
    LatLng(15.128100, 120.617600),
    LatLng(15.127950, 120.617770),
    LatLng(15.127800, 120.617940),
    LatLng(15.127650, 120.618110),
    LatLng(15.127500, 120.618280),
    LatLng(15.127350, 120.618450),
    LatLng(15.127200, 120.618620),
    LatLng(15.127050, 120.618790),
    LatLng(15.126900, 120.618960),
    LatLng(15.126750, 120.619130),
    LatLng(15.126600, 120.619300),
    LatLng(15.126450, 120.619470),
    LatLng(15.126300, 120.619640),
    LatLng(15.057800, 120.671500),
  ];
  final List<LatLng> _routePoints = [];
  bool _routeLoading = true;
  bool _usingFallbackRoute = false;
  String? _routeError;

  @override
  void initState() {
    super.initState();
    _addNotification('Welcome to Commuter Portal! Tracking jeepneys for you.');
    _loadRegisteredName();
    _fetchRouteGeometry();
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
    return List<LatLng>.from(_angelesToSanFernandoDetailedRoute);
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

  void _logout() {
    _auth.signOut();
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

  @override
  void dispose() {
    for (final t in _animationTimers.values) {
      t.cancel();
    }
    _animationTimers.clear();
    _animating.clear();
    super.dispose();
  }
}
