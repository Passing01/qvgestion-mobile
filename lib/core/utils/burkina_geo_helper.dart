import 'dart:math' as math;

/// Informations géographiques d'une zone détectée au Burkina Faso.
class BurkinaZoneInfo {
  final String city;
  final String region;

  const BurkinaZoneInfo({required this.city, required this.region});
}

/// Utilitaire partagé de détection ville / région au Burkina Faso depuis GPS.
class BurkinaGeoHelper {
  BurkinaGeoHelper._();

  static const List<({String city, String region, double lat, double lon})>
      _regionalCenters = [
    (city: 'Ouagadougou', region: 'Centre', lat: 12.3714, lon: -1.5197),
    (city: 'Bobo-Dioulasso', region: 'Hauts-Bassins', lat: 11.1771, lon: -4.2979),
    (city: 'Koudougou', region: 'Centre-Ouest', lat: 12.2526, lon: -2.3627),
    (city: 'Banfora', region: 'Cascades', lat: 10.6333, lon: -4.7667),
    (city: 'Ouahigouya', region: 'Nord', lat: 13.5828, lon: -2.4216),
    (city: 'Kaya', region: 'Centre-Nord', lat: 13.0917, lon: -1.0844),
    (city: 'Tenkodogo', region: 'Centre-Est', lat: 11.7800, lon: -0.3697),
    (city: 'Fada N\'Gourma', region: 'Est', lat: 12.0616, lon: 0.3584),
    (city: 'Dédougou', region: 'Boucle du Mouhoun', lat: 12.4634, lon: -3.4608),
    (city: 'Gaoua', region: 'Sud-Ouest', lat: 10.3333, lon: -3.1833),
    (city: 'Dori', region: 'Sahel', lat: 14.0354, lon: -0.0345),
    (city: 'Ziniaré', region: 'Plateau-Central', lat: 12.5819, lon: -1.2972),
    (city: 'Manga', region: 'Centre-Sud', lat: 11.6636, lon: -1.0731),
  ];

  static double distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLon = (lon2 - lon1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Retourne la ville et la région burkinabè correspondant aux coordonnées GPS.
  static BurkinaZoneInfo detectCityAndRegion(double lat, double lon) {
    var best = _regionalCenters.first;
    var bestDist = double.infinity;
    for (final c in _regionalCenters) {
      final d = distanceMeters(lat, lon, c.lat, c.lon);
      if (d < bestDist) {
        bestDist = d;
        best = c;
      }
    }
    if (bestDist <= 60000) {
      return BurkinaZoneInfo(city: best.city, region: best.region);
    }
    if (bestDist <= 140000) {
      return BurkinaZoneInfo(city: best.region, region: best.region);
    }
    return const BurkinaZoneInfo(city: 'Burkina Faso', region: 'Burkina Faso');
  }
}

