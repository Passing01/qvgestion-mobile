import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/utils/burkina_geo_helper.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';
import 'package:qvgestion_mobile/features/weather/presentation/providers/weather_providers.dart';

/// Bandeau météo & trafic déroulant de la maquette officielle
class WeatherTrafficTicker extends ConsumerWidget {
  const WeatherTrafficTicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(currentWeatherProvider);
    final loc = ref.watch(currentLocationProvider);
    final places = ref.watch(placesStateProvider).placesList;

    String detectedCity =
        BurkinaGeoHelper.detectCityAndRegion(loc.lat, loc.lon).city;
    for (final p in places) {
      if (p.ville.trim().isNotEmpty &&
          BurkinaGeoHelper.distanceMeters(
                loc.lat,
                loc.lon,
                p.latitude,
                p.longitude,
              ) <
              30000) {
        detectedCity = p.ville.trim();
        break;
      }
    }

    final String displayText = weatherAsync.when(
      data: (weather) {
        final temp = weather.temperatureCelsius.round();
        final cityFromWeather = BurkinaGeoHelper.detectCityAndRegion(
          weather.latitude,
          weather.longitude,
        ).city;
        final cityLabel =
            cityFromWeather != 'Burkina Faso' ? cityFromWeather : detectedCity;
        return '$cityLabel $temp°C • ${weather.drivingAdvisory}';
      },
      loading: () => '$detectedCity • Chargement météo & trafic...',
      error: (error, stack) =>
          '$detectedCity • Conditions de circulation disponibles sur carte',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB).withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icône repère / académique
            const Icon(
              Icons.school_rounded,
              size: 16,
              color: Color(0xFF4B5563),
            ),
            const SizedBox(width: 6),
            // Pastille ambre
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Icône météo
            const Text('🌤️', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 6),
            // Texte dynamique météo & trafic
            Expanded(
              child: Text(
                displayText,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F2937),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
