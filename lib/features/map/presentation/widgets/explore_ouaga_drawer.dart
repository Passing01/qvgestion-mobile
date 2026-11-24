import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/utils/burkina_geo_helper.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';

enum ExploreDiscoveryFilter { all, tourism, restaurants, hotels }

class IconicPlaceItem {
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final String? distance;
  final double rating;
  final double latitude;
  final double longitude;
  final String gradientStart;
  final String gradientEnd;
  final IconData icon;
  final String? imageUrl;
  final ExploreDiscoveryFilter kind;

  const IconicPlaceItem({
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    this.distance,
    required this.rating,
    required this.latitude,
    required this.longitude,
    required this.gradientStart,
    required this.gradientEnd,
    required this.icon,
    this.imageUrl,
    this.kind = ExploreDiscoveryFilter.tourism,
  });
}

/// Tiroir inférieur "Explorer le Burkina & Environs" sensible à la zone GPS
/// (quartier, ville, région) et filtrable par Sites touristiques, Restaurants et Hôtels.
class ExploreOuagaDrawer extends ConsumerStatefulWidget {
  final ValueChanged<IconicPlaceItem> onPlaceTap;
  final VoidCallback? onCollapse;

  const ExploreOuagaDrawer({
    super.key,
    required this.onPlaceTap,
    this.onCollapse,
  });

  static const List<IconicPlaceItem> iconicPlaces = [
    IconicPlaceItem(
      title: 'Héros Nationaux',
      subtitle: 'Ouagadougou • Ouaga 2000',
      badgeText: 'Site touristique',
      badgeColor: Color(0xFF2563EB),
      rating: 4.8,
      latitude: 12.312187,
      longitude: -1.502617,
      gradientStart: '#1E3A8A',
      gradientEnd: '#3B82F6',
      icon: Icons.account_balance_rounded,
      kind: ExploreDiscoveryFilter.tourism,
    ),
    IconicPlaceItem(
      title: 'Grande Mosquée de Dioulassoba',
      subtitle: 'Bobo-Dioulasso • Hauts-Bassins',
      badgeText: 'Site touristique',
      badgeColor: Color(0xFF047857),
      rating: 4.9,
      latitude: 11.1772,
      longitude: -4.2979,
      gradientStart: '#065F46',
      gradientEnd: '#10B981',
      icon: Icons.mosque_rounded,
      kind: ExploreDiscoveryFilter.tourism,
    ),
    IconicPlaceItem(
      title: 'Cascades de Karfiguéla',
      subtitle: 'Banfora • Cascades',
      badgeText: 'Site touristique',
      badgeColor: Color(0xFF0284C7),
      rating: 4.9,
      latitude: 10.7222,
      longitude: -4.8256,
      gradientStart: '#0369A1',
      gradientEnd: '#38BDF8',
      icon: Icons.water_rounded,
      kind: ExploreDiscoveryFilter.tourism,
    ),
    IconicPlaceItem(
      title: 'Place de la Révolution',
      subtitle: 'Ouagadougou • Centre-Ville',
      badgeText: 'Historique',
      badgeColor: Color(0xFFC2410C),
      rating: 4.7,
      latitude: 12.369752,
      longitude: -1.529488,
      gradientStart: '#7C2D12',
      gradientEnd: '#EA580C',
      icon: Icons.flag_rounded,
      kind: ExploreDiscoveryFilter.tourism,
    ),
    IconicPlaceItem(
      title: 'Grand Marché Rood-Woko',
      subtitle: 'Ouagadougou • Centre',
      badgeText: 'Populaire',
      badgeColor: Color(0xFF0D9488),
      rating: 4.6,
      latitude: 12.3685,
      longitude: -1.5222,
      gradientStart: '#134E4A',
      gradientEnd: '#14B8A6',
      icon: Icons.storefront_rounded,
      kind: ExploreDiscoveryFilter.tourism,
    ),
  ];

  @override
  ConsumerState<ExploreOuagaDrawer> createState() => _ExploreOuagaDrawerState();
}

class _ExploreOuagaDrawerState extends ConsumerState<ExploreOuagaDrawer> {
  ExploreDiscoveryFilter _filter = ExploreDiscoveryFilter.all;

  ExploreDiscoveryFilter? _classifyPlace(PlaceModel p) {
    final slug = (p.categorie?.slug ?? '').toLowerCase();
    final catNom = (p.categorie?.nom ?? '').toLowerCase();
    final name = p.nom.toLowerCase();
    final hay = '$slug $catNom $name';

    if (hay.contains('hotel') ||
        hay.contains('hôtel') ||
        hay.contains('auberge') ||
        hay.contains('heberg') ||
        hay.contains('héberg') ||
        hay.contains('villa') ||
        hay.contains('résidence') ||
        hay.contains('residence')) {
      return ExploreDiscoveryFilter.hotels;
    }
    if (hay.contains('maquis') ||
        hay.contains('restaurant') ||
        hay.contains('resto') ||
        hay.contains('cafe') ||
        hay.contains('café') ||
        hay.contains('boulangerie') ||
        hay.contains('grill') ||
        hay.contains('manger')) {
      return ExploreDiscoveryFilter.restaurants;
    }
    if (hay.contains('touris') ||
        hay.contains('monument') ||
        hay.contains('musee') ||
        hay.contains('musée') ||
        hay.contains('cultur') ||
        hay.contains('parc') ||
        hay.contains('mosquee') ||
        hay.contains('mosquée') ||
        hay.contains('cathedrale') ||
        hay.contains('cascade') ||
        hay.contains('artisan') ||
        hay.contains('place ') ||
        p.isAnchor) {
      return ExploreDiscoveryFilter.tourism;
    }
    return null;
  }

  ({String city, String? quartier, String region}) _detectUserZone(
    double lat,
    double lon,
    List<PlaceModel> nearbyPlaces,
  ) {
    final geo = BurkinaGeoHelper.detectCityAndRegion(lat, lon);
    String city = geo.city;
    String? quartier;
    var bestDist = double.infinity;
    for (final p in nearbyPlaces) {
      final d = BurkinaGeoHelper.distanceMeters(lat, lon, p.latitude, p.longitude);
      if (d < bestDist) {
        bestDist = d;
        if (p.ville.trim().isNotEmpty && d < 25000) {
          city = p.ville.trim();
        }
        if ((p.quartier ?? '').trim().isNotEmpty && d < 4000) {
          quartier = p.quartier!.trim();
        }
      }
    }
    return (city: city, quartier: quartier, region: geo.region);
  }

  List<IconicPlaceItem> _buildDiscoveryItems(
    double lat,
    double lon,
    List<PlaceModel> nearbyPlaces,
  ) {
    final sortedNearby = List<PlaceModel>.from(nearbyPlaces)
      ..sort((a, b) {
        final da = BurkinaGeoHelper.distanceMeters(lat, lon, a.latitude, a.longitude);
        final db = BurkinaGeoHelper.distanceMeters(lat, lon, b.latitude, b.longitude);
        return da.compareTo(db);
      });

    final localCards = <IconicPlaceItem>[];
    for (final p in sortedNearby) {
      final kind = _classifyPlace(p);
      if (kind == null) continue;
      final distM = BurkinaGeoHelper.distanceMeters(lat, lon, p.latitude, p.longitude);
      final distText = distM >= 1000
          ? '${(distM / 1000).toStringAsFixed(1)} km'
          : '${distM.round()} m';

      late final String badge;
      late final Color color;
      late final IconData icon;
      late final String gStart;
      late final String gEnd;
      switch (kind) {
        case ExploreDiscoveryFilter.hotels:
          badge = 'Hôtel';
          color = const Color(0xFF7C3AED);
          icon = Icons.hotel_rounded;
          gStart = '#4C1D95';
          gEnd = '#8B5CF6';
        case ExploreDiscoveryFilter.restaurants:
          badge = 'Restaurant / Maquis';
          color = const Color(0xFFEA580C);
          icon = Icons.restaurant_rounded;
          gStart = '#9A3412';
          gEnd = '#F97316';
        case ExploreDiscoveryFilter.tourism:
        case ExploreDiscoveryFilter.all:
          badge = 'Site touristique';
          color = const Color(0xFF047857);
          icon = Icons.tour_rounded;
          gStart = '#065F46';
          gEnd = '#10B981';
      }

      localCards.add(
        IconicPlaceItem(
          title: p.nom,
          subtitle: '${p.ville}${p.quartier != null ? " • ${p.quartier}" : ""}',
          badgeText: badge,
          badgeColor: color,
          distance: distText,
          rating: p.noteMoyenne ?? 4.6,
          latitude: p.latitude,
          longitude: p.longitude,
          gradientStart: gStart,
          gradientEnd: gEnd,
          icon: icon,
          imageUrl: p.photos.isNotEmpty ? p.photos.first : null,
          kind: kind,
        ),
      );
      if (localCards.length >= 12) break;
    }

    // Priorise d'abord les incontournables de la région détectée tout en gardant l'ordre curaté dans la même ville
    final userZone = _detectUserZone(lat, lon, nearbyPlaces);
    final curated = List<IconicPlaceItem>.from(ExploreOuagaDrawer.iconicPlaces)
      ..sort((a, b) {
        final aLocal = a.subtitle.toLowerCase().contains(userZone.city.toLowerCase());
        final bLocal = b.subtitle.toLowerCase().contains(userZone.city.toLowerCase());
        if (aLocal != bLocal) return aLocal ? -1 : 1;
        return 0;
      });
    final curatedWithDist = curated.map((c) {
      final d = BurkinaGeoHelper.distanceMeters(lat, lon, c.latitude, c.longitude);
      final distText =
          d >= 1000 ? '${(d / 1000).toStringAsFixed(0)} km' : '${d.round()} m';
      return IconicPlaceItem(
        title: c.title,
        subtitle: c.subtitle,
        badgeText: c.badgeText,
        badgeColor: c.badgeColor,
        distance: distText,
        rating: c.rating,
        latitude: c.latitude,
        longitude: c.longitude,
        gradientStart: c.gradientStart,
        gradientEnd: c.gradientEnd,
        icon: c.icon,
        imageUrl: c.imageUrl,
        kind: c.kind,
      );
    }).toList();

    final seenTitles = <String>{};
    final merged = <IconicPlaceItem>[];
    for (final item in [...localCards, ...curatedWithDist]) {
      if (_filter != ExploreDiscoveryFilter.all && item.kind != _filter) {
        continue;
      }
      if (seenTitles.add(item.title.toLowerCase())) {
        merged.add(item);
      }
    }
    if (merged.isEmpty) {
      return curatedWithDist;
    }
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    final nearbyPlaces = ref.watch(placesStateProvider).placesList;
    final loc = ref.watch(currentLocationProvider);
    final zone = _detectUserZone(loc.lat, loc.lon, nearbyPlaces);
    final items = _buildDiscoveryItems(loc.lat, loc.lon, nearbyPlaces);
    final subtitleZone = zone.quartier != null
        ? 'Autour de ${zone.quartier} (${zone.city}) • ${zone.region}'
        : 'Zone : ${zone.city} • Région ${zone.region}';

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: (details) {
        if (details.primaryDelta != null && details.primaryDelta! > 6) {
          widget.onCollapse?.call();
        }
      },
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 40) {
          widget.onCollapse?.call();
        }
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 20,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: widget.onCollapse,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                  color: Colors.transparent,
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Explorer le Burkina & Environs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleZone,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF4B5563),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FE),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Populaire',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6D28D9),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Tout voir',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      if (widget.onCollapse != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Color(0xFF6B7280), size: 26),
                          tooltip: 'Réduire le tiroir',
                          visualDensity: VisualDensity.compact,
                          onPressed: widget.onCollapse,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 30,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                children: [
                  _buildFilterChip(ExploreDiscoveryFilter.all, 'Tout'),
                  const SizedBox(width: 6),
                  _buildFilterChip(ExploreDiscoveryFilter.tourism, 'Sites touristiques'),
                  const SizedBox(width: 6),
                  _buildFilterChip(ExploreDiscoveryFilter.restaurants, 'Restaurants'),
                  const SizedBox(width: 6),
                  _buildFilterChip(ExploreDiscoveryFilter.hotels, 'Hôtels'),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 164,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (context, index) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final place = items[index];
                  return GestureDetector(
                    onTap: () => widget.onPlaceTap(place),
                    child: Container(
                      width: 215,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            children: [
                              Container(
                                height: 90,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(18)),
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(int.parse(place.gradientStart.replaceFirst('#', '0xFF'))),
                                      Color(int.parse(place.gradientEnd.replaceFirst('#', '0xFF'))),
                                    ],
                                  ),
                                ),
                                child: place.imageUrl != null
                                    ? ClipRRect(
                                        borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(18),
                                        ),
                                        child: Image.network(
                                          place.imageUrl!,
                                          height: 90,
                                          width: double.infinity,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => Center(
                                            child: Icon(
                                              place.icon,
                                              size: 46,
                                              color: Colors.white.withValues(alpha: 0.85),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Center(
                                        child: Icon(
                                          place.icon,
                                          size: 46,
                                          color: Colors.white.withValues(alpha: 0.85),
                                        ),
                                      ),
                              ),
                              Positioned(
                                top: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: place.badgeColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    place.badgeText,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              if (place.distance != null)
                                Positioned(
                                  bottom: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      place.distance!,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        place.title,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF111827),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            size: 14, color: Color(0xFFF59E0B)),
                                        const SizedBox(width: 2),
                                        Text(
                                          place.rating.toString(),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF374151),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  place.subtitle,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6B7280),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(ExploreDiscoveryFilter kind, String label) {
    final active = _filter == kind;
    return GestureDetector(
      onTap: () => setState(() => _filter = kind),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF047857) : const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : const Color(0xFF374151),
          ),
        ),
      ),
    );
  }
}
