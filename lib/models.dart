enum RouteStatus { active, noTrips, delayed }

enum DriverStatus { operating, onBreak, offline }

class JeepneyRoute {
  JeepneyRoute({
    required this.name,
    required this.status,
    required this.estimatedWaitMinutes,
    required this.currentJeepneys,
    required this.latestLocation,
    required this.routeCode,
  });

  final String name;
  RouteStatus status;
  int estimatedWaitMinutes;
  int currentJeepneys;
  String latestLocation;
  final String routeCode;
}

class DriverInfo {
  DriverInfo({
    required this.name,
    required this.status,
    required this.location,
    required this.available,
    required this.assignedRoute,
  });

  final String name;
  DriverStatus status;
  String location;
  bool available;
  String assignedRoute;
}
