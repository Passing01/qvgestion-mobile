import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/di/core_providers.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';
import 'package:qvgestion_mobile/features/weather/data/models/weather_model.dart';
import 'package:qvgestion_mobile/features/weather/data/repositories/weather_repository.dart';

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return WeatherRepository(apiClient: apiClient);
});

/// Grille météo ~1,1 km (arrondi à 2 décimales) pour éviter de recharger la météo
/// à chaque tick GPS pendant la navigation active (prévient les erreurs HTTP 429).
final weatherGridLocationProvider =
    Provider<({int latE2, int lonE2})>((ref) {
  final location = ref.watch(currentLocationProvider);
  return (
    latE2: (location.lat * 100).round(),
    lonE2: (location.lon * 100).round(),
  );
});

final currentWeatherProvider = FutureProvider<WeatherModel>((ref) async {
  final repository = ref.watch(weatherRepositoryProvider);
  final grid = ref.watch(weatherGridLocationProvider);
  return repository.getCurrentWeather(
    lat: grid.latE2 / 100.0,
    lon: grid.lonE2 / 100.0,
  );
});
