import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> with WidgetsBindingObserver {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _seatController = TextEditingController();

  // Continuous location publishing
  StreamSubscription<Position>? _positionSubscription;
  bool _publishing = false;

  String? _driverId;
  bool _isProcessing = false;
  final List<String> _notifications = [];
  final MapController _mapController = MapController();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _commuterLocationSubscription;
  final Set<String> _sharedCommuterIds = <String>{};
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _driverId = _auth.currentUser?.uid;
    _listenForSharedCommuterLocations();
    _ensureDriverDocExists();
    _addSampleNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _commuterLocationSubscription?.cancel();
    _seatController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // App is going to background/closed
      _setDriverOffline();
    }
    if (state == AppLifecycleState.detached || state == AppLifecycleState.inactive) {
      // ensure we stop publishing when app is terminated
      _stopPublishing();
    }
  }

  Future<void> _setDriverOffline() async {
    if (_driverId == null) return;
    try {
      await _firestore.collection('drivers').doc(_driverId).set({
        'gpsEnabled': false,
        'lastOfflineAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // Notify silently without setState as the widget might be unmounted
    } catch (e) {
      // Silently ignore errors when app is closing
    }
  }

  Future<void> _ensureDriverDocExists() async {
    if (_driverId == null) return;

    try {
      final docRef = _firestore.collection('drivers').doc(_driverId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        await docRef.set({
          'fullName': _auth.currentUser?.displayName ?? 'Jeepney Driver',
          'plateNumber': 'N/A',
          'route': 'Angeles → San Fernando',
          'availableSeats': 10,
          'statusColor': 'green',
          'statusLabel': 'Vacant',
          'latitude': 15.13,
          'longitude': 120.65,
          'gpsEnabled': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        _addNotification('Driver profile created in Firestore.');
      }
    } catch (e) {
      _addNotification('Error initializing driver data: $e');
    }
  }

  void _addSampleNotifications() {
    if (_notifications.isEmpty) {
      _notifications.addAll([
        'Jeepney is nearly full',
        'High passenger demand detected',
        'Seats available for boarding',
      ]);
    }
  }

  void _listenForSharedCommuterLocations() {
    _commuterLocationSubscription?.cancel();
    _commuterLocationSubscription = _firestore.collection('commuters').snapshots().listen((snapshot) {
      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) {
          continue;
        }

        final isVisible = (data['shareOnDriverMap'] as bool?) ?? false;
        final lat = data['latitude'];
        final lon = data['longitude'];
        final hasCoordinates = lat != null && lon != null;

        if (change.type == DocumentChangeType.removed) {
          _sharedCommuterIds.remove(doc.id);
          continue;
        }

        if (isVisible && hasCoordinates) {
          final wasAlreadyTracked = _sharedCommuterIds.contains(doc.id);
          if (!wasAlreadyTracked) {
            _sharedCommuterIds.add(doc.id);
            final fullName = data['fullName'];
            final name = (fullName is String ? fullName.trim() : null)?.isNotEmpty == true
                ? fullName
                : 'Commuter';
            _addNotification('$name shared a pickup location on the live map.');
          }
        } else {
          _sharedCommuterIds.remove(doc.id);
        }
      }
    }, onError: (error) {
      _addNotification('Unable to monitor commuter locations: $error');
    });
  }

  void _addNotification(String message) {
    if (!mounted) return;
    setState(() {
      final timestamp = DateTime.now().toLocal().toString().split('.').first;
      _notifications.insert(0, '[$timestamp] $message');
      if (_notifications.length > 12) {
        _notifications.removeRange(12, _notifications.length);
      }
    });
  }

  Color _getColorFromString(String colorString) {
    switch (colorString.toLowerCase()) {
      case 'green':
        return Colors.green;
      case 'orange':
        return Colors.orange;
      case 'red':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }


  Future<void> _refreshLocation() async {
    if (_driverId == null) return;

    try {
      setState(() => _isProcessing = true);
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _addNotification('Location services are disabled.');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        _addNotification('Location permission denied.');
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        _addNotification('Location permission permanently denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      await _firestore.collection('drivers').doc(_driverId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'gpsEnabled': true,
        'lastGpsAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _addNotification(
        'GPS refreshed: ${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}.',
      );
    } catch (e) {
      _addNotification('GPS update failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _startPublishing() async {
    if (_driverId == null) return;
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _addNotification('Location services disabled.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _addNotification('Location permission denied.');
      return;
    }

    // Listen to position updates and write to Firestore
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5, // meters
      ),
    ).listen((position) async {
      try {
        await _firestore.collection('drivers').doc(_driverId).set({
          'latitude': position.latitude,
          'longitude': position.longitude,
          'gpsEnabled': true,
          'heading': position.heading,
          'speed': position.speed,
          'lastGpsAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        _addNotification('Failed to publish location: $e');
      }
    }, onError: (e) {
      _addNotification('Location stream error: $e');
    });

    setState(() => _publishing = true);
    _addNotification('Started publishing location updates.');
  }

  Future<void> _stopPublishing() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    if (_driverId != null) {
      await _firestore.collection('drivers').doc(_driverId).set({
        'gpsEnabled': false,
        'lastOfflineAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    setState(() => _publishing = false);
    _addNotification('Stopped publishing location updates.');
  }

  Future<void> _logout() async {
    try {
      await _stopPublishing();
      await _auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    } catch (e) {
      _addNotification('Logout failed: $e');
    }
  }

  Future<void> _setQuickStatus(
    String statusColor,
    String statusLabel,
    int seats,
  ) async {
    if (_driverId == null) return;
    try {
      setState(() => _isProcessing = true);
      await _firestore.collection('drivers').doc(_driverId).set({
        'statusColor': statusColor,
        'statusLabel': statusLabel,
        'availableSeats': seats,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _addNotification('Status set to $statusLabel');
    } catch (e) {
      _addNotification('Failed to set status: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _buildDriverInfoCard(
    String fullName,
    String plateNumber,
    String route,
    String statusColor,
    String statusLabel,
  ) {
    final color = _getColorFromString(statusColor);
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Plate Number: $plateNumber',
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Route: $route',
                        style: const TextStyle(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        statusColor == 'green'
                            ? Icons.check_circle
                            : statusColor == 'orange'
                            ? Icons.warning
                            : Icons.cancel,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsCard(double latitude, double longitude, bool gpsEnabled) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Live GPS Location',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latitude: ${latitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Longitude: ${longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: gpsEnabled ? Colors.green : Colors.grey,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      gpsEnabled ? '✓ GPS Enabled' : '✗ GPS Disabled',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _refreshLocation,
              icon: const Icon(Icons.my_location),
              label: const Text('Enable GPS / Refresh Location'),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _publishing ? _stopPublishing : _startPublishing,
              icon: Icon(_publishing ? Icons.pause_circle : Icons.play_circle),
              label: Text(_publishing ? 'Stop Live Publish' : 'Start Live Publish'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _publishing ? Colors.red : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.clear_all),
                  tooltip: 'Clear notifications',
                  onPressed: _notifications.isEmpty
                      ? null
                      : () => setState(() => _notifications.clear()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_notifications.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'No notifications yet.',
                  style: TextStyle(color: Colors.black54),
                ),
              )
            else
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.notifications,
                            color: Colors.blue,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _notifications[index],
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusQuickSelectCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Quick Status Set',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Quickly set jeepney status:',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _setQuickStatus('green', 'Vacant', 8),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('🟢 Vacant'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _setQuickStatus('orange', 'Limited', 2),
                    icon: const Icon(Icons.warning),
                    label: const Text('🟠 Limited'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _isProcessing
                  ? null
                  : () => _setQuickStatus('red', 'Full', 0),
              icon: const Icon(Icons.cancel),
              label: const Text('🔴 Full'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Green: Many seats (8) | Orange: Few seats (2) | Red: Full (0)',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(
    String fullName,
    String plateNumber,
    String route,
    String statusColor,
    String statusLabel,
    double latitude,
    double longitude,
    bool gpsEnabled,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDriverInfoCard(
            fullName,
            plateNumber,
            route,
            statusColor,
            statusLabel,
          ),
          const SizedBox(height: 16),
          _buildStatusQuickSelectCard(),
          const SizedBox(height: 16),
          _buildGpsCard(latitude, longitude, gpsEnabled),
        ],
      ),
    );
  }

  Widget _buildLiveMapTab({
    required double latitude,
    required double longitude,
    required bool gpsEnabled,
  }) {
    final mapCenter = latitude == 0 && longitude == 0
        ? const LatLng(15.13, 120.65)
        : LatLng(latitude, longitude);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('commuters').snapshots(),
      builder: (context, snapshot) {
        final commuterDocs = snapshot.data?.docs ?? [];
        final visibleCommuters = commuterDocs.where((doc) {
          final data = doc.data();
          final shareOnMap = (data['shareOnDriverMap'] as bool?) ?? false;
          final commuterGpsEnabled = (data['gpsEnabled'] as bool?) ?? false;
          final commuterLatitude = data['latitude'];
          final commuterLongitude = data['longitude'];
          return shareOnMap &&
              commuterGpsEnabled &&
              commuterLatitude != null &&
              commuterLongitude != null;
        }).toList();

        final markers = visibleCommuters.map((doc) {
          final data = doc.data();
          final commuterName = (data['fullName'] as String?)?.trim().isNotEmpty == true
              ? data['fullName'] as String
              : 'Commuter';
          final commuterLat = (data['latitude'] as num).toDouble();
          final commuterLon = (data['longitude'] as num).toDouble();

          return Marker(
            point: LatLng(commuterLat, commuterLon),
            width: 100,
            height: 100,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.person_pin_circle, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    commuterName.split(' ').first,
                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          );
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Live commuter map',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: visibleCommuters.isEmpty ? Colors.grey : Colors.green,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${visibleCommuters.length} commuters visible',
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        visibleCommuters.isEmpty
                            ? 'No commuters are currently sharing their location on the map.'
                            : 'Visible commuter pickup points are shown in real time on the route map below.',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _publishing ? _stopPublishing : _startPublishing,
                        icon: Icon(_publishing ? Icons.pause_circle : Icons.play_circle),
                        label: Text(_publishing ? 'Stop Broadcast' : 'Start Broadcast'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _publishing ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: mapCenter,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.jeepjeep',
                      ),
                      MarkerLayer(markers: markers),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildNotificationsCard(),
    );
  }

  Widget _buildProfileTab(
    String fullName,
    String plateNumber,
    String route,
    String statusColor,
    String statusLabel,
    int availableSeats,
  ) {
    final color = _getColorFromString(statusColor);
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
                    fullName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Driver',
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
                    'Jeepney Information',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Plate Number:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        plateNumber,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Route:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Expanded(
                        child: Text(
                          route,
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
                        'Available Seats:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Text(
                        '$availableSeats',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Status:',
                        style: TextStyle(color: Colors.black54),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusLabel,
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
    if (_driverId == null) {
      return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: const SizedBox.shrink(),
          title: const Text('Driver Dashboard'),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Please log in to access the driver dashboard.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/login',
                    (route) => false,
                  ),
                  child: const Text('Go to Login'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final docRef = _firestore.collection('drivers').doc(_driverId);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: const SizedBox.shrink(),
        title: const Text('Driver Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Error loading driver data: ${snapshot.error}'),
            );
          }

          final data = snapshot.data?.data();
          if (data == null || !snapshot.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Driver record is not available yet.'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _ensureDriverDocExists,
                      child: const Text('Initialize Data'),
                    ),
                  ],
                ),
              ),
            );
          }

          final fullName = data['fullName'] as String? ?? 'Jeepney Driver';
          final plateNumber = data['plateNumber'] as String? ?? 'N/A';
          final route = data['route'] as String? ?? 'Angeles → San Fernando';
          final availableSeats = (data['availableSeats'] as num?)?.toInt() ?? 0;
          final statusColor = data['statusColor'] as String? ?? 'green';
          final statusLabel = data['statusLabel'] as String? ?? 'Vacant';
          final latitude = (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final longitude = (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final gpsEnabled = data['gpsEnabled'] as bool? ?? false;

          return Scaffold(
            body: IndexedStack(
              index: _selectedTabIndex,
              children: [
                _buildDashboardTab(
                  fullName,
                  plateNumber,
                  route,
                  statusColor,
                  statusLabel,
                  latitude,
                  longitude,
                  gpsEnabled,
                ),
                _buildLiveMapTab(
                  latitude: latitude,
                  longitude: longitude,
                  gpsEnabled: gpsEnabled,
                ),
                _buildNotificationTab(),
                _buildProfileTab(
                  fullName,
                  plateNumber,
                  route,
                  statusColor,
                  statusLabel,
                  availableSeats,
                ),
              ],
            ),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedTabIndex,
              onTap: (index) => setState(() => _selectedTabIndex = index),
              type: BottomNavigationBarType.fixed,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard),
                  label: 'Dashboard',
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
}
