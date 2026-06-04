import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Regional Realtime Database URL — must match the one in the .ino file
// ─────────────────────────────────────────────────────────────────────────────
const String _kDatabaseUrl =
    'https://jeepneyauth-default-rtdb.asia-southeast1.firebasedatabase.app';

// The device ID the driver claims — must match DEFAULT_DEVICE_ID in the .ino
const String _kDeviceId = 'esp01';

class DriverPage extends StatefulWidget {
  const DriverPage({super.key});

  @override
  State<DriverPage> createState() => _DriverPageState();
}

class _DriverPageState extends State<DriverPage> with WidgetsBindingObserver {
  final FirebaseAuth      _auth      = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _seatController = TextEditingController();

  // Location publishing
  StreamSubscription<Position>? _positionSubscription;
  bool _publishing = false;

  String? _driverId;
  bool    _isProcessing = false;

  final List<String>  _notifications       = [];
  final MapController _mapController       = MapController();
  final Set<String>   _sharedCommuterIds   = {};

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _commuterLocationSubscription;

  int _selectedTabIndex = 0;

  // ── ESP32 RTDB listener & device claim ────────────────────────────────────
  StreamSubscription<DatabaseEvent>? _esp32StatusSubscription;
  bool   _esp32Connected  = false;
  bool   _deviceClaimed   = false;   // true once we wrote our UID to RTDB
  String? _lastEsp32Status;

  static const _esp32StatusMap = {
    'AVAILABLE': (color: 'green',  label: 'Vacant',  seats: 8),
    'LIMITED':   (color: 'orange', label: 'Limited', seats: 2),
    'FULL':      (color: 'red',    label: 'Full',    seats: 0),
  };

  // Writes the driver's UID into RTDB so the ESP32 knows whose Firestore
  // document to update when a button is pressed.
  Future<void> _claimDevice() async {
    if (_driverId == null) return;
    try {
      final db  = FirebaseDatabase.instanceFor(
          app: _auth.app, databaseURL: _kDatabaseUrl);
      final ref = db.ref('devices/$_kDeviceId/driverUid');
      await ref.set(_driverId);
      setState(() => _deviceClaimed = true);
      _addNotification('ESP32 device claimed by this driver account.');
    } catch (e) {
      _addNotification('Failed to claim ESP32 device: $e');
    }
  }

  // Clears the UID from RTDB on logout so the ESP32 stops updating this driver.
  Future<void> _releaseDevice() async {
    try {
      final db  = FirebaseDatabase.instanceFor(
          app: _auth.app, databaseURL: _kDatabaseUrl);
      final ref = db.ref('devices/$_kDeviceId/driverUid');
      await ref.remove();
      setState(() {
        _deviceClaimed  = false;
        _esp32Connected = false;
      });
    } catch (_) {}
  }

  // Listens to the ESP32's status node so the app UI reflects button presses
  // made on the physical device.
  void _startEsp32Listener() {
    final db  = FirebaseDatabase.instanceFor(
        app: _auth.app, databaseURL: _kDatabaseUrl);
    final ref = db.ref('devices/$_kDeviceId/status');

    _esp32StatusSubscription = ref.onValue.listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw == null) return;

        final status = raw.toString().toUpperCase();
        if (status == _lastEsp32Status) return;
        _lastEsp32Status = status;

        if (!_esp32Connected) setState(() => _esp32Connected = true);

        final mapping = _esp32StatusMap[status];
        if (mapping == null) {
          _addNotification('ESP32 sent unknown status: $status');
          return;
        }

        _addNotification('ESP32 button → ${mapping.label}');
        _setQuickStatus(mapping.color, mapping.label, mapping.seats);
      },
      onError: (e) {
        if (_esp32Connected) setState(() => _esp32Connected = false);
        _addNotification('ESP32 listener error: $e');
      },
    );
  }

  void _stopEsp32Listener() {
    _esp32StatusSubscription?.cancel();
    _esp32StatusSubscription = null;
  }
  // ── END ESP32 ─────────────────────────────────────────────────────────────

  final List<LatLng> _routePolylinePoints = const [
    LatLng(15.121953, 120.600196),
    LatLng(15.120363, 120.601451),
    LatLng(15.120073, 120.601730),
    LatLng(15.119763, 120.602100),
    LatLng(15.119229, 120.602766),
    LatLng(15.118030, 120.604635),
    LatLng(15.117145, 120.606030),
    LatLng(15.116870, 120.606440),
    LatLng(15.116712, 120.606650),
    LatLng(15.116498, 120.606886),
    LatLng(15.116218, 120.607143),
    LatLng(15.115133, 120.608095),
    LatLng(15.113750, 120.609281),
    LatLng(15.112453, 120.610423),
    LatLng(15.110689, 120.611974),
    LatLng(15.110060, 120.612502),
    LatLng(15.109861, 120.612682),
    LatLng(15.101825, 120.619704),
    LatLng(15.089305, 120.630610),
    LatLng(15.084959, 120.634410),
    LatLng(15.080877, 120.637972),
    LatLng(15.078319, 120.640209),
    LatLng(15.077334, 120.641062),
    LatLng(15.077334, 120.641062),
    LatLng(15.074975, 120.643125),
    LatLng(15.074589, 120.643433),
    LatLng(15.073222, 120.644648),
    LatLng(15.070642, 120.646888),
    LatLng(15.067244, 120.649881),
    LatLng(15.065309, 120.651566),
    LatLng(15.063509, 120.653148),
    LatLng(15.061199, 120.655165),
    LatLng(15.059365, 120.656764),
    LatLng(15.058272, 120.657687),
    LatLng(15.055957, 120.659698),
    LatLng(15.054231, 120.661238),
    LatLng(15.053879, 120.661517),
    LatLng(15.051815, 120.663499),
    LatLng(15.050136, 120.665208),
    LatLng(15.049709, 120.665642),
    LatLng(15.049279, 120.666111),
    LatLng(15.048673, 120.666884),
    LatLng(15.047989, 120.667868),
    LatLng(15.047243, 120.668922),
    LatLng(15.046790, 120.669590),
    LatLng(15.046028, 120.670719),
    LatLng(15.042109, 120.676500),
    LatLng(15.041239, 120.677776),
    LatLng(15.040586, 120.678763),
    LatLng(15.038957, 120.680880),
    LatLng(15.036514, 120.683742),
    LatLng(15.034825, 120.685823),
    LatLng(15.033955, 120.686869),
    LatLng(15.033556, 120.687625),
    LatLng(15.033408, 120.688258),
    LatLng(15.032916, 120.693392),
    LatLng(15.032608, 120.693400),
    LatLng(15.031825, 120.693363),
    LatLng(15.031085, 120.693325),
    LatLng(15.030403, 120.693475),
    LatLng(15.030388, 120.694511),
    LatLng(15.031393, 120.694275),
    LatLng(15.031973, 120.694138),
    LatLng(15.032325, 120.694114),
    LatLng(15.032841, 120.694122),
    LatLng(15.032916, 120.693392),
    LatLng(15.033408, 120.688258),
    LatLng(15.033556, 120.687625),
    LatLng(15.033955, 120.686869),
    LatLng(15.034825, 120.685823),
    LatLng(15.036514, 120.683742),
    LatLng(15.038957, 120.680880),
    LatLng(15.040389, 120.682422),
    LatLng(15.041311, 120.683613),
    LatLng(15.042151, 120.684825),
    LatLng(15.042586, 120.685533),
    LatLng(15.044813, 120.689127),
    LatLng(15.044360, 120.688401),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _driverId = _auth.currentUser?.uid;
    _listenForSharedCommuterLocations();
    _ensureDriverDocExists();
    _addSampleNotifications();
    // Claim device then start listening
    _claimDevice().then((_) => _startEsp32Listener());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _commuterLocationSubscription?.cancel();
    _seatController.dispose();
    _stopEsp32Listener();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      _setDriverOffline();
    }
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      _stopPublishing();
    }
  }

  Future<void> _setDriverOffline() async {
    if (_driverId == null) return;
    try {
      await _firestore.collection('drivers').doc(_driverId).set(
        {'gpsEnabled': false, 'lastOfflineAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  Future<void> _ensureDriverDocExists() async {
    if (_driverId == null) return;
    try {
      final docRef = _firestore.collection('drivers').doc(_driverId);
      final snapshot = await docRef.get();
      if (!snapshot.exists) {
        await docRef.set({
          'fullName':       _auth.currentUser?.displayName ?? 'Jeepney Driver',
          'plateNumber':    'N/A',
          'route':          'Angeles → San Fernando',
          'availableSeats': 10,
          'statusColor':    'green',
          'statusLabel':    'Vacant',
          'latitude':       15.13,
          'longitude':      120.65,
          'gpsEnabled':     false,
          'createdAt':      FieldValue.serverTimestamp(),
        });
        _addNotification('Driver profile created.');
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
    _commuterLocationSubscription = _firestore
        .collection('commuters')
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        final doc  = change.doc;
        final data = doc.data();
        if (data == null) continue;

        final isVisible     = (data['shareOnDriverMap'] as bool?) ?? false;
        final hasCoords     = data['latitude'] != null && data['longitude'] != null;

        if (change.type == DocumentChangeType.removed) {
          _sharedCommuterIds.remove(doc.id);
          continue;
        }
        if (isVisible && hasCoords) {
          if (!_sharedCommuterIds.contains(doc.id)) {
            _sharedCommuterIds.add(doc.id);
            final name = (data['fullName'] as String?)?.trim().isNotEmpty == true
                ? data['fullName'] as String
                : 'Commuter';
            _addNotification('$name shared a pickup location on the live map.');
          }
        } else {
          _sharedCommuterIds.remove(doc.id);
        }
      }
    }, onError: (e) => _addNotification('Unable to monitor commuters: $e'));
  }

  void _addNotification(String message) {
    if (!mounted) return;
    setState(() {
      final ts = DateTime.now().toLocal().toString().split('.').first;
      _notifications.insert(0, '[$ts] $message');
      if (_notifications.length > 12) _notifications.removeRange(12, _notifications.length);
    });
  }

  Color _getColorFromString(String c) {
    switch (c.toLowerCase()) {
      case 'green':  return Colors.green;
      case 'orange': return Colors.orange;
      case 'red':    return Colors.red;
      default:       return Colors.grey;
    }
  }

  String _reverseRoute(String route) {
    final separator = RegExp(r'\s*(?:→|[-–—])\s*');
    if (!separator.hasMatch(route)) return route;
    final parts = route.split(separator).map((part) => part.trim()).toList();
    if (parts.length != 2) return route;
    return '${parts[1]} → ${parts[0]}';
  }

  bool _routeShouldUseReversedPolyline(String route) {
    final separator = RegExp(r'\s*(?:→|[-–—])\s*');
    final parts = route.split(separator).map((part) => part.trim().toLowerCase()).toList();
    if (parts.length != 2) return false;
    return parts.first.contains('san fernando');
  }

  Future<void> _switchRoute(String currentRoute) async {
    if (_driverId == null) return;
    final newRoute = _reverseRoute(currentRoute);
    try {
      await _firestore.collection('drivers').doc(_driverId).set(
        {'route': newRoute, 'lastUpdated': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      _addNotification('Route switched to $newRoute.');
    } catch (e) {
      _addNotification('Failed to switch route: $e');
    }
  }

  Future<void> _refreshLocation() async {
    if (_driverId == null) return;
    try {
      setState(() => _isProcessing = true);
      if (!await Geolocator.isLocationServiceEnabled()) {
        _addNotification('Location services are disabled.'); return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _addNotification('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      await _firestore.collection('drivers').doc(_driverId).set({
        'latitude':  pos.latitude,
        'longitude': pos.longitude,
        'gpsEnabled': true,
        'lastGpsAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _addNotification('GPS refreshed: '
          '${pos.latitude.toStringAsFixed(5)}, '
          '${pos.longitude.toStringAsFixed(5)}.');
    } catch (e) {
      _addNotification('GPS update failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _startPublishing() async {
    if (_driverId == null) return;
    if (!await Geolocator.isLocationServiceEnabled()) {
      _addNotification('Location services disabled.'); return;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      _addNotification('Location permission denied.');
      return;
    }
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best, distanceFilter: 5),
    ).listen((pos) async {
      try {
        await _firestore.collection('drivers').doc(_driverId).set({
          'latitude':  pos.latitude,
          'longitude': pos.longitude,
          'gpsEnabled': true,
          'heading':   pos.heading,
          'speed':     pos.speed,
          'lastGpsAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        _addNotification('Failed to publish location: $e');
      }
    }, onError: (e) => _addNotification('Location stream error: $e'));
    setState(() => _publishing = true);
    _addNotification('Started publishing location updates.');
  }

  Future<void> _stopPublishing() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    if (_driverId != null) {
      await _firestore.collection('drivers').doc(_driverId).set(
        {'gpsEnabled': false, 'lastOfflineAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    setState(() => _publishing = false);
    _addNotification('Stopped publishing location updates.');
  }

  Future<void> _logout() async {
    try {
      await _stopPublishing();
      await _releaseDevice();   // ← clears driverUid from RTDB
      _stopEsp32Listener();
      await _auth.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (r) => false);
      }
    } catch (e) {
      _addNotification('Logout failed: $e');
    }
  }

  Future<void> _setQuickStatus(
      String statusColor, String statusLabel, int seats) async {
    if (_driverId == null) return;
    try {
      setState(() => _isProcessing = true);
      await _firestore.collection('drivers').doc(_driverId).set({
        'statusColor':    statusColor,
        'statusLabel':    statusLabel,
        'availableSeats': seats,
        'lastUpdated':    FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _addNotification('Status set to $statusLabel');
    } catch (e) {
      _addNotification('Failed to set status: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildDriverInfoCard(String fullName, String plateNumber,
      String route, String statusColor, String statusLabel) {
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
                      Text(fullName,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Plate Number: $plateNumber',
                          style: const TextStyle(color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text('Route: $route',
                          style: const TextStyle(color: Colors.black87)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12)),
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
                      Text(statusLabel,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ESP32 connection status indicator
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.indigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.indigo.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      // Green = claimed + receiving events; amber = claimed but
                      // no event yet; grey = not claimed
                      color: _esp32Connected
                          ? Colors.green
                          : _deviceClaimed
                              ? Colors.amber
                              : Colors.grey,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _esp32Connected
                        ? 'ESP32 active — physical buttons enabled'
                        : _deviceClaimed
                            ? 'ESP32 claimed — waiting for device…'
                            : 'ESP32 not claimed',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.indigo),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsCard(
      double latitude, double longitude, bool gpsEnabled) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Live GPS Location',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Latitude: ${latitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Text('Longitude: ${longitude.toStringAsFixed(5)}',
                      style: const TextStyle(fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: gpsEnabled ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(4)),
                    child: Text(
                      gpsEnabled ? '✓ GPS Enabled' : '✗ GPS Disabled',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
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
              onPressed:
                  _publishing ? _stopPublishing : _startPublishing,
              icon: Icon(_publishing
                  ? Icons.pause_circle
                  : Icons.play_circle),
              label: Text(_publishing
                  ? 'Stop Live Publish'
                  : 'Start Live Publish'),
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _publishing ? Colors.red : Colors.green),
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
                const Text('Notifications',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
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
                child: Text('No notifications yet.',
                    style: TextStyle(color: Colors.black54)),
              )
            else
              SizedBox(
                height: 180,
                child: ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (ctx, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.notifications,
                            color: Colors.blue, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_notifications[i],
                                style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusQuickSelectCard(int totalCapacity) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Quick Status Set',
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Quickly set jeepney status:',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () => _setQuickStatus('green', 'Vacant', totalCapacity),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('🟢 Vacant'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing
                        ? null
                        : () =>
                            _setQuickStatus('orange', 'Limited', 2),
                    icon: const Icon(Icons.warning),
                    label: const Text('🟠 Limited'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Green: Many seats ($totalCapacity) | Orange: Few seats (2) | Red: Full (0)\n'
                'Physical ESP32 buttons also update this automatically.',
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardTab(
      String fullName, String plateNumber, String route,
      String statusColor, String statusLabel,
      double latitude, double longitude, bool gpsEnabled,
      int totalCapacity) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDriverInfoCard(
              fullName, plateNumber, route, statusColor, statusLabel),
          const SizedBox(height: 16),
          _buildStatusQuickSelectCard(totalCapacity),
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
    required String route,
  }) {
    final mapCenter = (latitude == 0 && longitude == 0)
        ? const LatLng(15.13, 120.65)
        : LatLng(latitude, longitude);
    final reversedRoute = _reverseRoute(route);
    final routePoints = _routeShouldUseReversedPolyline(route)
        ? _routePolylinePoints.reversed.toList()
        : _routePolylinePoints;

    // Responsive sizes based on available screen real estate
    final media = MediaQuery.of(context).size;
    final isCompact = media.height < 700 || media.width < 420;
    final cardHeight = isCompact ? 150.0 : 180.0;
    final mapPadding = isCompact ? 8.0 : 16.0;
    final initialZoomLevel = isCompact ? 14.0 : 13.0;
    final polylineWidth = isCompact ? 4.0 : 5.0;
    final markerOuterSize = isCompact ? 30.0 : 34.0;
    final markerIconSize = isCompact ? 18.0 : 20.0;
    final markerLabelFont = isCompact ? 8.0 : 9.0;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('commuters').snapshots(),
      builder: (ctx, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final visible = docs.where((d) {
          final data = d.data();
          return (data['shareOnDriverMap'] as bool? ?? false) &&
              (data['gpsEnabled'] as bool? ?? false) &&
              data['latitude'] != null &&
              data['longitude'] != null;
        }).toList();

        final markers = visible.map((d) {
          final data = d.data();
          final name =
              (data['fullName'] as String?)?.trim().isNotEmpty == true
                  ? data['fullName'] as String
                  : 'Commuter';
          final lat = (data['latitude'] as num).toDouble();
          final lon = (data['longitude'] as num).toDouble();
          return Marker(
            point: LatLng(lat, lon),
            width: markerOuterSize + 20,
            height: markerOuterSize + 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: markerOuterSize,
                  height: markerOuterSize,
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Icon(
                    Icons.person_pin_circle,
                    color: Colors.white,
                    size: markerIconSize,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name.split(' ').first,
                    style: TextStyle(
                      fontSize: markerLabelFont,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList();

        return Padding(
          padding: EdgeInsets.all(mapPadding),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: cardHeight,
                child: Card(
                  elevation: 6,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: EdgeInsets.all(mapPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Live commuter map',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                  color: visible.isEmpty
                                      ? Colors.grey
                                      : Colors.green,
                                  borderRadius:
                                      BorderRadius.circular(999)),
                              child: Text(
                                '${visible.length} commuters visible',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          visible.isEmpty
                              ? 'No commuters are currently sharing their location.'
                              : 'Visible commuter pickup points shown in real time.',
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ElevatedButton.icon(
                            onPressed: () => _switchRoute(route),
                            icon: const Icon(Icons.swap_horiz, size: 18),
                            label: Text(
                              'To $reversedRoute',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.indigo,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(40, 36),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ],
                    ),
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
                      initialZoom: initialZoomLevel,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.example.jeepjeep',
                      ),
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: routePoints,
                            color: Colors.blue.withAlpha(217),
                            strokeWidth: polylineWidth,
                            borderStrokeWidth: (polylineWidth / 2).clamp(
                              1.0,
                              2.0,
                            ),
                            borderColor: Colors.white,
                          ),
                        ],
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
      String fullName, String plateNumber, String route,
      String statusColor, String statusLabel, int availableSeats) {
    final color = _getColorFromString(statusColor);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 6,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
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
                        color: Colors.blue[300]),
                    child: const Icon(Icons.person,
                        size: 48, color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  Text(fullName,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('Driver',
                      style: TextStyle(
                          fontSize: 14, color: Colors.black54)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Jeepney Information',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _infoRow('Plate Number:', plateNumber),
                  const SizedBox(height: 12),
                  _infoRow('Route:', route, rightFlex: true),
                  const SizedBox(height: 12),
                  _infoRow('Available Seats:', '$availableSeats'),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Status:',
                          style: TextStyle(color: Colors.black54)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(statusLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
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
                padding:
                    const EdgeInsets.symmetric(vertical: 12)),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {bool rightFlex = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        rightFlex
            ? Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.bold)))
            : Text(value,
                style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
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
                const Text(
                    'Please log in to access the driver dashboard.'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context, '/login', (_) => false),
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
          IconButton(
              icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: docRef.snapshots(),
        builder: (ctx, snapshot) {
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
                        child: const Text('Initialize Data')),
                  ],
                ),
              ),
            );
          }

          final fullName =
              data['fullName'] as String? ?? 'Jeepney Driver';
          final plateNumber =
              data['plateNumber'] as String? ?? 'N/A';
          final route =
              data['route'] as String? ?? 'Angeles → San Fernando';
          final availableSeats =
              (data['availableSeats'] as num?)?.toInt() ?? 0;
          final totalCapacity =
              (data['totalCapacity'] as num?)?.toInt() ?? availableSeats;
          final statusColor =
              data['statusColor'] as String? ?? 'green';
          final statusLabel =
              data['statusLabel'] as String? ?? 'Vacant';
          final latitude =
              (data['latitude'] as num?)?.toDouble() ?? 0.0;
          final longitude =
              (data['longitude'] as num?)?.toDouble() ?? 0.0;
          final gpsEnabled =
              data['gpsEnabled'] as bool? ?? false;

          return IndexedStack(
            index: _selectedTabIndex,
            children: [
              _buildDashboardTab(fullName, plateNumber, route,
                  statusColor, statusLabel, latitude, longitude,
                  gpsEnabled, totalCapacity),
              _buildLiveMapTab(
                  latitude: latitude,
                  longitude: longitude,
                  gpsEnabled: gpsEnabled,
                  route: route),
              _buildNotificationTab(),
              _buildProfileTab(fullName, plateNumber, route,
                  statusColor, statusLabel, availableSeats),
            ],
          );
        },
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedTabIndex,
        onTap: (i) => setState(() => _selectedTabIndex = i),
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(
              icon: Icon(Icons.map), label: 'Live Map'),
          BottomNavigationBarItem(
              icon: Icon(Icons.notifications), label: 'Notification'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}