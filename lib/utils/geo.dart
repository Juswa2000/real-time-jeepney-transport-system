import 'package:geolocator/geolocator.dart';

/// Returns the great-circle distance in meters between two GPS coordinates.
double distanceBetweenMeters(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
) {
  return Geolocator.distanceBetween(
    startLatitude,
    startLongitude,
    endLatitude,
    endLongitude,
  );
}

/// Returns true when the two GPS points are within [radiusMeters].
bool isWithinRadius(
  double startLatitude,
  double startLongitude,
  double endLatitude,
  double endLongitude,
  double radiusMeters,
) {
  return distanceBetweenMeters(
        startLatitude,
        startLongitude,
        endLatitude,
        endLongitude,
      ) <=
      radiusMeters;
}
