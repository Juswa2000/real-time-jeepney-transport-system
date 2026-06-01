import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../app_state.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MapController _mapController = MapController();
  final ScrollController _scrollController = ScrollController();

  final GlobalKey _dashboardKey = GlobalKey();
  final GlobalKey _mapKey = GlobalKey();
  final GlobalKey _driversKey = GlobalKey();
  final GlobalKey _commutersKey = GlobalKey();
  final GlobalKey _notificationsKey = GlobalKey();
  final GlobalKey _reportsKey = GlobalKey();

  String _activeSection = 'Dashboard';

  static const List<LatLng> _routePolylinePoints = [
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

  static const double _mapPanelHeight = 360.0;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _driversStream =>
      _firestore.collection('drivers').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _commutersStream =>
      _firestore.collection('commuters').snapshots();

  Stream<QuerySnapshot<Map<String, dynamic>>> get _notificationsStream =>
      _firestore
          .collection('notifications')
          .orderBy('createdAt', descending: true)
          .limit(8)
          .snapshots();

  Stream<DocumentSnapshot<Map<String, dynamic>>> get _reportsStream =>
      _firestore.collection('reports').doc('daily_summary').snapshots();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _logout(BuildContext context) async {
    final appState = AppStateProvider.of(context);
    await appState.logout();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
  }

  Future<void> _scrollToSection(GlobalKey key) async {
    final context = key.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.1,
    );
  }

  Future<void> _setActiveSection(String section, GlobalKey key) async {
    setState(() => _activeSection = section);
    await _scrollToSection(key);
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 13, color: Colors.black45),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallMetricCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    double? width,
    double valueFontSize = 28,
  }) {
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationRow(NotificationAlert alert) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.redAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  alert.message,
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          Text(
            alert.time,
            style: const TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildDemandChart() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(16),
      child: CustomPaint(
        painter: _DemandChartPainter(),
        child: const Center(child: Text('')),
      ),
    );
  }

  Marker _buildDriverMarker(DocumentSnapshot<Map<String, dynamic>> driverDoc) {
    final data = driverDoc.data() ?? {};
    final fullName = (data['fullName'] as String?) ?? 'Unknown';
    final statusLabel = (data['statusLabel'] as String?) ?? 'Offline';
    final gpsEnabled = (data['gpsEnabled'] as bool?) ?? false;
    final lat = (data['latitude'] as num?)?.toDouble();
    final lon = (data['longitude'] as num?)?.toDouble();

    if (lat == null || lon == null) {
      return Marker(
        point: LatLng(0, 0),
        width: 0,
        height: 0,
        child: const SizedBox.shrink(),
      );
    }

    final color = gpsEnabled
        ? (statusLabel.toLowerCase() == 'vacant'
              ? Colors.green
              : statusLabel.toLowerCase() == 'limited'
              ? Colors.orange
              : Colors.red)
        : Colors.grey;

    return Marker(
      point: LatLng(lat, lon),
      width: 90,
      height: 90,
      child: GestureDetector(
        onTap: () => _showDriverPopup(driverDoc),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on, color: color, size: 34),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha((0.08 * 255).round()),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: Text(
                fullName.split(' ').first,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDriverPopup(DocumentSnapshot<Map<String, dynamic>> driverDoc) {
    final data = driverDoc.data() ?? {};
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text((data['fullName'] as String?) ?? 'Driver details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('Plate', data['plateNumber'] as String? ?? 'N/A'),
              _buildInfoRow('Route', data['route'] as String? ?? 'N/A'),
              _buildInfoRow(
                'Status',
                data['statusLabel'] as String? ?? 'Offline',
              ),
              _buildInfoRow(
                'GPS',
                ((data['gpsEnabled'] as bool?) ?? false)
                    ? 'Enabled'
                    : 'Disabled',
              ),
              _buildInfoRow(
                'Last Updated',
                _formatTimestamp(data['lastGpsAt'] as Timestamp?),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';
    final dateTime = timestamp.toDate();
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  List<Marker> _buildMapMarkers(
    List<DocumentSnapshot<Map<String, dynamic>>> drivers,
  ) {
    return drivers
        .map(_buildDriverMarker)
        .where((m) => m.point.latitude != 0 || m.point.longitude != 0)
        .toList();
  }

  Widget _buildMapPanel(
    List<DocumentSnapshot<Map<String, dynamic>>> drivers,
    {bool expand = false}
  ) {
    final mapWidget = ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(16),
        bottomRight: Radius.circular(16),
      ),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: _routePolylinePoints[_routePolylinePoints.length ~/ 2],
          initialZoom: 12.2,
          interactionOptions: const InteractionOptions(),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.jeepjeep',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePolylinePoints,
                color: Colors.blueAccent,
                strokeWidth: 5,
              ),
            ],
          ),
          MarkerLayer(markers: _buildMapMarkers(drivers)),
        ],
      ),
    );

    return Card(
      elevation: 6,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Live Jeepney Map',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
              ],
            ),
          ),
          if (expand)
            Expanded(child: mapWidget)
          else
            SizedBox(height: _mapPanelHeight, child: mapWidget),
        ],
      ),
    );
  }

  Widget _buildDriverTable(
    BuildContext context,
    List<DocumentSnapshot<Map<String, dynamic>>> drivers,
  ) {
    final visibleDrivers = drivers.take(3).toList();

    return Card(
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
                  'Driver Monitoring',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (visibleDrivers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No drivers available.'),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Driver Name')),
                    DataColumn(label: Text('Plate Number')),
                    DataColumn(label: Text('Route')),
                    DataColumn(label: Text('Status')),
                    DataColumn(label: Text('GPS Status')),
                    DataColumn(label: Text('Last Updated')),
                  ],
                  rows: visibleDrivers.map((doc) {
                    final data = doc.data() ?? {};
                    final gpsEnabled = (data['gpsEnabled'] as bool?) ?? false;
                    final statusText = (data['statusLabel'] as String?) ?? 'Offline';
                    final statusLower = statusText.toLowerCase();
                    final statusColor = statusLower == 'vacant'
                        ? Colors.green
                        : statusLower == 'limited'
                            ? Colors.orange
                            : statusLower == 'full'
                                ? Colors.red
                                : Colors.grey;

                    return DataRow(
                      cells: [
                        DataCell(Text(data['fullName'] as String? ?? 'Unknown')),
                        DataCell(Text(data['plateNumber'] as String? ?? 'N/A')),
                        DataCell(Text(data['route'] as String? ?? 'N/A')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: statusColor, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: gpsEnabled
                                  ? Colors.green.withOpacity(0.12)
                                  : Colors.redAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: gpsEnabled ? Colors.green : Colors.redAccent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: gpsEnabled ? Colors.green : Colors.redAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  gpsEnabled ? 'Enabled' : 'Disabled',
                                  style: TextStyle(
                                    color: gpsEnabled ? Colors.green : Colors.redAccent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(Text(_formatTimestamp(data['lastGpsAt'] as Timestamp?))),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommuterSection(
    List<DocumentSnapshot<Map<String, dynamic>>> commuters,
  ) {
    final activeCommuters = commuters.where((doc) {
      final data = doc.data() ?? {};
      return (data['gpsEnabled'] as bool?) == true ||
          (data['shareOnDriverMap'] as bool?) == true;
    }).length;

    final demandCount = commuters.where((doc) {
      final data = doc.data() ?? {};
      return (data['demand'] as String?) == 'HIGH';
    }).length;
    final demandLevel = demandCount > 5
        ? 'HIGH'
        : (demandCount > 0 ? 'MEDIUM' : 'LOW');
    final demandSubtitle = demandCount == 1
        ? '1 commuter waiting'
        : '$demandCount commuters waiting';

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Passenger Demand',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(onPressed: () {}, child: const Text('View Details')),
              ],
            ),
            const SizedBox(height: 18),
            _buildStatCard(
              'Current Demand Level',
              demandLevel,
              demandSubtitle,
              Icons.signal_cellular_alt,
              Colors.deepPurple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsPanel(
    List<String> generatedAlerts,
    QuerySnapshot<Map<String, dynamic>>? notificationsSnapshot,
    {bool expand = false}
  ) {
    final firestoreAlerts = notificationsSnapshot?.docs.map((doc) {
      final data = doc.data();
      return NotificationAlert(
        title: data['title'] as String? ?? 'Alert',
        message: data['message'] as String? ?? '',
        time: data['time'] as String? ?? 'Now',
      );
    }).toList() ?? [];

    final combinedAlerts = [
      ...generatedAlerts.map((message) => NotificationAlert(
            title: 'System Alert',
            message: message,
            time: 'Now',
          )),
      ...firestoreAlerts,
    ];

    final visibleAlerts = combinedAlerts.take(3).toList();
    final isLoadingNotifications =
        notificationsSnapshot == null && generatedAlerts.isEmpty;

    final content = isLoadingNotifications
        ? const Center(child: Text('Loading stored notifications...'))
        : visibleAlerts.isEmpty
            ? const Center(
                child: Text(
                  'No active alerts at the moment.',
                  style: TextStyle(color: Colors.green),
                ),
              )
            : ListView.separated(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: visibleAlerts.length,
                itemBuilder: (context, index) =>
                    _buildNotificationRow(visibleAlerts[index]),
                separatorBuilder: (_, __) => const SizedBox(height: 6),
              );

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Notifications',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(onPressed: () {}, child: const Text('View All')),
              ],
            ),
            const SizedBox(height: 8),
            if (expand)
              Expanded(child: content)
            else
              SizedBox(height: 200, child: content),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAlertWidgets(List<String> alerts) {
    if (alerts.isEmpty) {
      return [
        const Text(
          'No active alerts at the moment.',
          style: TextStyle(color: Colors.green),
        ),
      ];
    }
    return alerts.map((alert) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.red,
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(alert, style: const TextStyle(color: Colors.black87)),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildReportsPanel(
    List<DocumentSnapshot<Map<String, dynamic>>> drivers,
    List<DocumentSnapshot<Map<String, dynamic>>> commuters,
    DocumentSnapshot<Map<String, dynamic>>? reportDoc,
  ) {
    final activeDrivers = drivers
        .where((d) => (d.data()?['gpsEnabled'] as bool?) == true)
        .length;
    final activeCommuters = commuters
        .where((c) => (c.data()?['shareOnDriverMap'] as bool?) == true)
        .length;
    final peakHours =
        reportDoc?.data()?['peakHours'] as String? ?? '7:00 AM - 9:00 AM';
    final dailyDriverCount =
        reportDoc?.data()?['dailyActiveDrivers']?.toString() ??
        activeDrivers.toString();
    final dailyCommuterCount =
        reportDoc?.data()?['dailyActiveCommuters']?.toString() ??
        activeCommuters.toString();

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Daily Report Summary',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View Full Report'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final totalSpacing = 14 * 2;
                final cardWidth = constraints.maxWidth > totalSpacing
                    ? (constraints.maxWidth - totalSpacing) / 3
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _buildSmallMetricCard(
                      'Daily Active Drivers',
                      dailyDriverCount,
                      Icons.directions_bus,
                      Colors.teal,
                      width: cardWidth,
                    ),
                    _buildSmallMetricCard(
                      'Daily Active Commuters',
                      dailyCommuterCount,
                      Icons.people,
                      Colors.indigo,
                      width: cardWidth,
                    ),
                    _buildSmallMetricCard(
                      'Peak Demand Hours',
                      peakHours,
                      Icons.access_time,
                      Colors.deepOrange,
                      width: cardWidth,
                      valueFontSize: 22,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            const Text(
              'Passenger Demand Overview',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SizedBox(height: 160, child: _buildDemandChart()),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = AppStateProvider.of(context);
    if (appState.authLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (appState.userRole.toLowerCase() != 'admin') {
      return Scaffold(
        appBar: AppBar(title: const Text('Unauthorized')),
        body: Center(
          child: ElevatedButton(
            onPressed: () => _logout(context),
            child: const Text('Return to Login'),
          ),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _driversStream,
      builder: (context, driversSnapshot) {
        if (driversSnapshot.hasError)
          return Center(
            child: Text('Driver stream error: ${driversSnapshot.error}'),
          );
        if (driversSnapshot.connectionState == ConnectionState.waiting)
          return const Center(child: CircularProgressIndicator());

        final driverDocs = driversSnapshot.data?.docs ?? [];
        final totalDrivers = driverDocs.length;
        final activeDrivers = driverDocs
            .where((doc) => (doc.data()['gpsEnabled'] as bool?) == true)
            .length;
        final offlineDrivers = totalDrivers - activeDrivers;
        final generatedAlerts = <String>[];

        for (final driverDoc in driverDocs) {
          final data = driverDoc.data();
          final fullName = (data['fullName'] as String?) ?? 'Unknown';
          final gpsEnabled = (data['gpsEnabled'] as bool?) ?? false;
          final statusLabel =
              (data['statusLabel'] as String?)?.toLowerCase() ?? '';

          if (!gpsEnabled) generatedAlerts.add('$fullName GPS disabled.');
          if (statusLabel == 'offline' || statusLabel == 'off duty')
            generatedAlerts.add('$fullName is offline.');
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _commutersStream,
          builder: (context, commutersSnapshot) {
            if (commutersSnapshot.hasError)
              return Center(
                child: Text(
                  'Commuter stream error: ${commutersSnapshot.error}',
                ),
              );
            if (commutersSnapshot.connectionState == ConnectionState.waiting)
              return const Center(child: CircularProgressIndicator());

            final commuterDocs = commutersSnapshot.data?.docs ?? [];
            final activeCommuters = commuterDocs.where((doc) {
              final data = doc.data();
              return (data['gpsEnabled'] as bool?) == true ||
                  (data['shareOnDriverMap'] as bool?) == true;
            }).length;

            final demandHigh = commuterDocs
                .where((doc) => (doc.data()['demand'] as String?) == 'HIGH')
                .length;
            if (demandHigh > 5)
              generatedAlerts.add(
                'Passenger demand is high: $demandHigh commuters waiting.',
              );

            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _notificationsStream,
              builder: (context, notificationsSnapshot) {
                if (notificationsSnapshot.hasError)
                  return Center(
                    child: Text(
                      'Notification stream error: ${notificationsSnapshot.error}',
                    ),
                  );

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _reportsStream,
                  builder: (context, reportsSnapshot) {
                    if (reportsSnapshot.hasError)
                      return Center(
                        child: Text(
                          'Reports stream error: ${reportsSnapshot.error}',
                        ),
                      );

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 1100;
                        final sidebarWidth = isWide ? 260.0 : 0.0;
                        final panelTotalHeight = _mapPanelHeight + 64.0;

                        return Scaffold(
                          appBar: isWide
                              ? null
                              : AppBar(
                                  title: const Text('Admin Dashboard'),
                                  elevation: 0,
                                  backgroundColor: Colors.white,
                                  foregroundColor: Colors.black87,
                                  iconTheme: const IconThemeData(
                                    color: Colors.black87,
                                  ),
                                ),
                          drawer: isWide
                              ? null
                              : Drawer(child: _buildSidebar(context)),
                          body: SafeArea(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isWide)
                                  SizedBox(
                                    width: sidebarWidth,
                                    child: _buildSidebar(context),
                                  ),
                                Expanded(
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Container(
                                          key: _dashboardKey,
                                          child: _buildTopHeader(appState),
                                        ),
                                        const SizedBox(height: 16),
                                        if (isWide)
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        right: 8.0,
                                                      ),
                                                  child: _buildStatCard(
                                                    'Total Registered Drivers',
                                                    totalDrivers.toString(),
                                                    'All registered jeepney drivers',
                                                    Icons.directions_bus,
                                                    Colors.indigo,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8.0,
                                                      ),
                                                  child: _buildStatCard(
                                                    'Active Jeepneys',
                                                    activeDrivers.toString(),
                                                    'Currently transmitting GPS data',
                                                    Icons.location_on,
                                                    Colors.green,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8.0,
                                                      ),
                                                  child: _buildStatCard(
                                                    'Offline Jeepneys',
                                                    offlineDrivers.toString(),
                                                    'Jeepneys with no GPS signal',
                                                    Icons.offline_bolt,
                                                    Colors.orange,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        left: 8.0,
                                                      ),
                                                  child: _buildStatCard(
                                                    'Active Commuters',
                                                    activeCommuters.toString(),
                                                    'Commuters currently on route',
                                                    Icons.people,
                                                    Colors.blue,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Wrap(
                                            spacing: 16,
                                            runSpacing: 16,
                                            children: [
                                              SizedBox(
                                                width: double.infinity,
                                                child: _buildStatCard(
                                                  'Total Registered Drivers',
                                                  totalDrivers.toString(),
                                                  'All registered jeepney drivers',
                                                  Icons.directions_bus,
                                                  Colors.indigo,
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: _buildStatCard(
                                                  'Active Jeepneys',
                                                  activeDrivers.toString(),
                                                  'Currently transmitting GPS data',
                                                  Icons.location_on,
                                                  Colors.green,
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: _buildStatCard(
                                                  'Offline Jeepneys',
                                                  offlineDrivers.toString(),
                                                  'Jeepneys with no GPS signal',
                                                  Icons.offline_bolt,
                                                  Colors.orange,
                                                ),
                                              ),
                                              SizedBox(
                                                width: double.infinity,
                                                child: _buildStatCard(
                                                  'Active Commuters',
                                                  activeCommuters.toString(),
                                                  'Commuters currently on route',
                                                  Icons.people,
                                                  Colors.blue,
                                                ),
                                              ),
                                            ],
                                          ),
                                        const SizedBox(height: 20),
                                        if (isWide)
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              SizedBox(
                                                width:
                                                    (constraints.maxWidth -
                                                        sidebarWidth -
                                                        40) *
                                                    0.625,
                                                child: SizedBox(
                                                  height: panelTotalHeight,
                                                  child: Container(
                                                    key: _mapKey,
                                                    child: _buildMapPanel(
                                                      driverDocs,
                                                      expand: true,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              Expanded(
                                                child: SizedBox(
                                                  height: panelTotalHeight,
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .stretch,
                                                    children: [
                                                      Container(
                                                        key: _commutersKey,
                                                        child:
                                                            _buildCommuterSection(
                                                          commuterDocs,
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child: Container(
                                                          key: _notificationsKey,
                                                          child:
                                                              _buildNotificationsPanel(
                                                            generatedAlerts,
                                                            notificationsSnapshot
                                                                .data,
                                                            expand: true,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          )
                                        else
                                          Center(
                                            child: SizedBox(
                                              width: double.infinity,
                                              child: Container(
                                                key: _mapKey,
                                                child: _buildMapPanel(
                                                  driverDocs,
                                                ),
                                              ),
                                            ),
                                          ),
                                        const SizedBox(height: 20),
                                        isWide
                                            ? Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    flex: 1,
                                                    child: Container(
                                                      key: _driversKey,
                                                      child: _buildDriverTable(
                                                        context,
                                                        driverDocs,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 20),
                                                  Expanded(
                                                    child: Container(
                                                      key: _reportsKey,
                                                      child: _buildReportsPanel(
                                                        driverDocs,
                                                        commuterDocs,
                                                        reportsSnapshot.data,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  Container(
                                                    key: _driversKey,
                                                    child: _buildDriverTable(
                                                      context,
                                                      driverDocs,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Container(
                                                    key: _commutersKey,
                                                    child:
                                                        _buildCommuterSection(
                                                          commuterDocs,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Container(
                                                    key: _notificationsKey,
                                                    child:
                                                        _buildNotificationsPanel(
                                                          generatedAlerts,
                                                          notificationsSnapshot
                                                              .data,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 20),
                                                  Container(
                                                    key: _reportsKey,
                                                    child: _buildReportsPanel(
                                                      driverDocs,
                                                      commuterDocs,
                                                      reportsSnapshot.data,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B3D91), Color(0xFF003C8F)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('img/jeep_icon_logo.png', height: 64)),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'SmartSakay',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _sidebarItem(
                context,
                Icons.dashboard,
                'Dashboard',
                selected: _activeSection == 'Dashboard',
                onTap: () => _setActiveSection('Dashboard', _dashboardKey),
              ),
              _sidebarItem(
                context,
                Icons.map,
                'Live Map',
                selected: _activeSection == 'Live Map',
                onTap: () => _setActiveSection('Live Map', _mapKey),
              ),
              _sidebarItem(
                context,
                Icons.drive_eta,
                'Drivers',
                selected: _activeSection == 'Drivers',
                onTap: () => _setActiveSection('Drivers', _driversKey),
              ),
              _sidebarItem(
                context,
                Icons.person,
                'Commuters',
                selected: _activeSection == 'Commuters',
                onTap: () => _setActiveSection('Commuters', _commutersKey),
              ),
              _sidebarItem(
                context,
                Icons.notifications,
                'Notifications',
                selected: _activeSection == 'Notifications',
                onTap: () => _setActiveSection('Notifications', _notificationsKey),
              ),
              _sidebarItem(
                context,
                Icons.assessment,
                'Reports',
                selected: _activeSection == 'Reports',
                onTap: () => _setActiveSection('Reports', _reportsKey),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: ElevatedButton.icon(
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sidebarItem(BuildContext context, IconData icon, String label,
      {bool selected = false, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white70, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopHeader(AppState appState) {
    final user = appState.displayName;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Dashboard',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Welcome back, $user', style: const TextStyle(color: Colors.black54)),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search),
              color: Colors.black54,
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey.shade200,
              child: const Icon(Icons.person, color: Colors.black54),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => _logout(context),
              child: const Text('Logout'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
  }

}

class NotificationAlert {
  final String title;
  final String message;
  final String time;

  NotificationAlert({required this.title, required this.message, required this.time});
}

class _DemandChartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(size.width, 0),
        [Colors.deepPurple.shade200, Colors.deepPurple.shade400],
      )
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final ui.Path path = ui.Path();
    path.moveTo(0, size.height * 0.75);
    path.quadraticBezierTo(size.width * 0.25, size.height * 0.5, size.width * 0.5, size.height * 0.6);
    path.quadraticBezierTo(size.width * 0.75, size.height * 0.7, size.width, size.height * 0.45);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
