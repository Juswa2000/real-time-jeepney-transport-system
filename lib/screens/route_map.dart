import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key, required this.route});

  final JeepneyRoute route;

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  var _gpsDialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_gpsDialogShown) {
        _showGpsDialog();
        _gpsDialogShown = true;
      }
    });
  }

  void _showGpsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Location Services'),
        content: const Text(
            'To use live location features, please enable GPS/location services on your device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    // Approximate coordinates for the Angeles to San Fernando route in Pampanga.
    final LatLng angeles = LatLng(15.145, 120.588);
    final LatLng sanFernando = LatLng(15.034, 120.684);
    final points = [
      angeles,
      LatLng(15.153, 120.601),
      LatLng(15.151, 120.619),
      LatLng(15.131, 120.638),
      LatLng(15.102, 120.656),
      LatLng(15.073, 120.672),
      sanFernando,
    ];

    return Scaffold(
      appBar: AppBar(title: Text('${route.name} — Map')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: LatLng(15.095, 120.635),
          initialZoom: 11.4,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'com.example.jeepjeep',
          ),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                strokeWidth: 5.0,
                color: Colors.blue,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                width: 80,
                height: 80,
                point: angeles,
                child: const Icon(Icons.location_on, color: Colors.green, size: 36),
              ),
              Marker(
                width: 80,
                height: 80,
                point: sanFernando,
                child: const Icon(Icons.location_on, color: Colors.red, size: 36),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
