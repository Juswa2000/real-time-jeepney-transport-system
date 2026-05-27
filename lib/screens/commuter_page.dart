import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
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

  @override
  void initState() {
    super.initState();
    _addNotification('Welcome to Commuter Portal! Tracking jeepneys for you.');
  }

  void _addNotification(String msg) {
    if (mounted) {
      setState(() {
        _notifications.insert(0, '[${DateTime.now().toString().split('.')[0]}] $msg');
        if (_notifications.length > 10) _notifications.removeLast();
      });
    }
  }

  // Calculate estimated waiting time based on number of active drivers
  int _calculateWaitingTime(int activeDrivers) {
    if (activeDrivers == 0) return 20;
    if (activeDrivers <= 2) return 12;
    if (activeDrivers <= 4) return 8;
    if (activeDrivers <= 6) return 5;
    return 3;
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

  // Build route polyline (Angeles to San Fernando - simplified)
  List<LatLng> _buildRouteLine() {
    return [
      const LatLng(15.08, 120.64), // Starting point (Angeles area)
      const LatLng(15.10, 120.63),
      const LatLng(15.12, 120.62),
      const LatLng(15.14, 120.61), // Ending point (San Fernando area)
    ];
  }

  void _refreshData() {
    setState(() {});
    _addNotification('Data refreshed!');
  }

  void _logout() {
    _auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 850;

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
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _logout,
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

          return isMobile
              ? _buildMobileLayout(
                  screenWidth,
                  drivers,
                  activeDrivers,
                  routeStatus,
                  currentDemand)
              : _buildDesktopLayout(
                  drivers, activeDrivers, routeStatus, currentDemand);
        },
      ),
    );
  }

  // Mobile layout (single column with map prominent)
  Widget _buildMobileLayout(
    double screenWidth,
    List<DocumentSnapshot<Map<String, dynamic>>> allDrivers,
    List<DocumentSnapshot<Map<String, dynamic>>> activeDrivers,
    String routeStatus,
    String demand,
  ) {
    final mapHeight = (screenWidth * 0.65).clamp(260.0, 360.0);
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: screenWidth < 360 ? 8 : 12,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. ROUTE HEADER CARD
          _buildRouteCard(routeStatus),
          const SizedBox(height: 12),

          // 2. LIVE JEEPNEY STATUS CARD
          _buildJeepneyStatusCard(activeDrivers.length),
          const SizedBox(height: 12),

          // 4. DRIVER STATUS GUIDE CARD
          _buildDriverStatusGuideCard(),
          const SizedBox(height: 12),

          // 3. LIVE MAP SECTION (smaller on mobile)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: mapHeight,
              child: _buildMapWidget(activeDrivers),
            ),
          ),
          const SizedBox(height: 12),

          // 5. JEEPNEY LIST (AVAILABLE DRIVERS)
          _buildAvailableDriversList(activeDrivers),
          const SizedBox(height: 12),

          // 6. NOTIFICATIONS SECTION
          _buildNotificationsCard(),
        ],
      ),
    );
  }

  // Desktop layout (side-by-side)
  Widget _buildDesktopLayout(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left column: Info cards
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    _buildRouteCard(routeStatus),
                    const SizedBox(height: 12),
                    _buildJeepneyStatusCard(activeDrivers.length),
                    const SizedBox(height: 12),
                    _buildDriverStatusGuideCard(),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Right column: Map
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 400,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildMapWidget(activeDrivers),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 1,
                child: _buildAvailableDriversList(activeDrivers),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: _buildNotificationsCard(),
              ),
            ],
          ),
        ],
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
                const Text(
                  'Angeles → San Fernando',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: LatLng(15.12, 120.625), // Center of route
        initialZoom: 13,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.jeepjeep',
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: _buildRouteLine(),
              color: Colors.blue,
              strokeWidth: 4,
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
