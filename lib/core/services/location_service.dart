import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qvgestion_mobile/core/debug/debug_info.dart';
import 'package:qvgestion_mobile/core/utils/app_logger.dart';

/// Statuts de permission et disponibilité du service de localisation (Étape 6)
enum LocationStatus { ok, denied, deniedForever, serviceOff }

/// Service unique de position et de suivi GPS pour toute l'application.
///
/// Responsabilités :
/// - Vérifier et demander la permission GPS selon les 4 cas standard.
/// - Diffuser le flux continu haute précision (`stream`).
/// - Filtrer les mauvais points pour la navigation (`isUsable`).
/// - Détecter la perte de signal (> 10s sans point) via un watchdog.
/// - Journaliser chaque point GPS conforme au format : `[GPS] lat, lon ±acc m, vit m/s`.
/// - Mettre à jour l'écran de télémétrie de debug (`DebugInfo`).
class LocationService {
  final _ctrl = StreamController<Position>.broadcast();
  Stream<Position> get stream => _ctrl.stream;

  StreamSubscription<Position>? _sub;
  Position? last;
  Timer? _watchdog;
  bool _navigationMode = false;

  /// Indique si le service GPS est en mode navigation active (service de premier plan + WakeLock)
  bool get isNavigationMode => _navigationMode;

  /// Notifie l'état de perte de signal GPS (> 10 secondes sans point valide)
  final ValueNotifier<bool> gpsLost = ValueNotifier<bool>(false);

  /// Dernier statut de permission obtenu
  final ValueNotifier<LocationStatus?> statusNotifier =
      ValueNotifier<LocationStatus?>(null);

  /// S'assure que les permissions et services sont disponibles (Étape 6)
  Future<LocationStatus> ensurePermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        statusNotifier.value = LocationStatus.serviceOff;
        return LocationStatus.serviceOff;
      }

      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
      }

      if (p == LocationPermission.deniedForever) {
        statusNotifier.value = LocationStatus.deniedForever;
        return LocationStatus.deniedForever;
      }

      final status = (p == LocationPermission.denied)
          ? LocationStatus.denied
          : LocationStatus.ok;

      statusNotifier.value = status;
      return status;
    } catch (e) {
      AppLogger.w('[GPS] Erreur lors de la vérification des permissions: $e');
      statusNotifier.value = LocationStatus.denied;
      return LocationStatus.denied;
    }
  }

  /// Ouvre les paramètres de l'application (pour deniedForever)
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e) {
      AppLogger.e('[GPS] Impossible d\'ouvrir les réglages de l\'app: $e');
      return false;
    }
  }

  /// Ouvre les paramètres système de localisation (pour serviceOff)
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      AppLogger.e(
        '[GPS] Impossible d\'ouvrir les réglages de localisation: $e',
      );
      return false;
    }
  }

  /// Bascule entre le mode exploration normal et le mode navigation (Étape 8 - Règle 7 : écran verrouillé)
  Future<void> setNavigationMode(bool active) async {
    if (_navigationMode == active && _sub != null) return;
    _navigationMode = active;
    await start();
  }

  /// Démarre le flux GPS haute précision et le watchdog de signal
  Future<void> start() async {
    final navigationMode = _navigationMode;
    await _sub?.cancel();

    // Récupération instantanée du dernier fix connu récent du système (< 30 min)
    try {
      final cached = await Geolocator.getLastKnownPosition();
      if (cached != null && isDisplayUsable(cached)) {
        final ageMin = DateTime.now().difference(cached.timestamp).inMinutes.abs();
        if (ageMin <= 30) {
          last = cached;
          final ageSec = DateTime.now().difference(cached.timestamp).inSeconds.abs();
          if (ageSec <= 15) {
            DebugInfo.instance.updateGpsFix(cached);
          }
          _ctrl.add(cached);
        }
      }
    } catch (_) {}

    final LocationSettings locationSettings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      if (navigationMode) {
        // Étape 8 · Règle 7 : Navigation active même écran verrouillé
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 1),
          foregroundNotificationConfig: const ForegroundNotificationConfig(
            notificationTitle: 'FASO NAV',
            notificationText: 'Navigation en cours',
            enableWakeLock: true,
          ),
        );
      } else {
        // En exploration, LocationAccuracy.high exploite GNSS + Wi-Fi/4G sans bloquer en intérieur
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
          intervalDuration: const Duration(seconds: 2),
        );
      }
    } else if (kIsWeb) {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: navigationMode
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.high,
        distanceFilter: navigationMode ? 3 : 0,
      );
    }

    _sub = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (p) {
        if (!_shouldAcceptPosition(p)) return;
        _emitFreshFix(p);
      },
      onError: (e) {
        AppLogger.e('⛔ [GPS] Erreur flux GPS: $e');
      },
    );

    // Force immédiatement un premier fix actif si le flux stream tarde au démarrage
    unawaited(refreshCurrentPosition());

    // Watchdog : vérifie périodiquement si le signal GPS est réellement perdu.
    // Sur Web (kIsWeb), watchPosition n'émet pas à fréquence fixe à l'arrêt :
    // on n'alerte donc qu'en navigation active après 45 s sans point.
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) {
      final fixAt = DebugInfo.instance.lastFixAt;
      final age = fixAt == null
          ? 999
          : DateTime.now().difference(fixAt).inSeconds;
      final isLost = kIsWeb
          ? (_navigationMode && fixAt != null && age > 45)
          : (age > 10);
      if (isLost != gpsLost.value) {
        gpsLost.value = isLost;
        if (isLost) {
          AppLogger.w(
            '⚠️ [GPS] Signal GPS perdu (aucun point reçu depuis ${age}s)',
          );
        }
      }
    });
  }

  void _emitFreshFix(Position p) {
    last = p;
    final logMsg =
        '[GPS] ${p.latitude.toStringAsFixed(6)}, ${p.longitude.toStringAsFixed(6)} ±${p.accuracy.toStringAsFixed(0)} m, ${p.speed.toStringAsFixed(1)} m/s';
    AppLogger.i(logMsg);
    debugPrint(logMsg);
    DebugInfo.instance.updateGpsFix(p);
    if (gpsLost.value) {
      gpsLost.value = false;
      AppLogger.i('📡 [GPS] Signal GPS retrouvé');
    }
    _ctrl.add(p);
  }

  bool _shouldAcceptPosition(Position p) {
    if (!isDisplayUsable(p)) return false;
    final prev = last;
    final fixAt = DebugInfo.instance.lastFixAt;
    if (prev != null && fixAt != null) {
      final age = DateTime.now().difference(fixAt).inSeconds.abs();
      // Évite qu'un rebond réseau très imprécis (>150 m) écrase un fix GNSS récent (<=25 m)
      if (age <= 15 && prev.accuracy <= 25.0 && p.accuracy > 150.0) {
        return false;
      }
    }
    return true;
  }

  /// Écarte les mauvais points pour la navigation :
  /// sur mobile : précision <= 50 m et âge <= 10 s ; sur Web : tolérance Wi-Fi/navigateur.
  bool isUsable(Position p) {
    final age = DateTime.now().difference(p.timestamp).inSeconds.abs();
    final maxAcc = kIsWeb ? 250.0 : 50.0;
    final maxAge = kIsWeb ? 60 : 10;
    return p.accuracy <= maxAcc && age <= maxAge;
  }

  /// Tolérance adaptée à l'affichage temps réel sur la carte (exploration, recherche, météo) :
  /// accepte les fixes GNSS / Wi-Fi / 4G valides jusqu'à 500 m pour montrer la vraie position.
  bool isDisplayUsable(Position p) {
    if (!p.latitude.isFinite || !p.longitude.isFinite) return false;
    if (p.latitude == 0.0 && p.longitude == 0.0) return false;
    final maxAcc = kIsWeb ? 5000.0 : 500.0;
    return !p.accuracy.isFinite || p.accuracy <= maxAcc;
  }

  /// Tolérance plus souple au démarrage (intérieur, ombre urbaine, navigateur Web)
  bool isStartUsable(Position p) {
    final age = DateTime.now().difference(p.timestamp).inSeconds.abs();
    return p.accuracy <= 150 && age <= 30;
  }

  /// Force une lecture GPS fraîche ponctuelle (avec repli réseau/Wi-Fi si le GNSS met du temps)
  Future<Position?> refreshCurrentPosition() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 6),
        ),
      ).timeout(const Duration(seconds: 6));
      if (_shouldAcceptPosition(p)) {
        _emitFreshFix(p);
      }
      return p;
    } catch (_) {
      if (!kIsWeb) {
        try {
          final fallback = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          ).timeout(const Duration(seconds: 5));
          if (_shouldAcceptPosition(fallback)) {
            _emitFreshFix(fallback);
          }
          return fallback;
        } catch (_) {}
      }
      return last;
    }
  }

  /// Arrête le flux et le watchdog
  void stop() {
    _sub?.cancel();
    _sub = null;
    _watchdog?.cancel();
    _watchdog = null;
  }

  /// Libère les ressources
  void dispose() {
    stop();
    _ctrl.close();
    gpsLost.dispose();
    statusNotifier.dispose();
  }
}

/// Provider du service de position (Singleton dans l'arbre Riverpod)
final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider exposant le flux de positions filtrées et exploitables
final gpsStreamProvider = StreamProvider<Position>((ref) {
  final service = ref.watch(locationServiceProvider);
  return service.stream;
});

/// Provider signalant la perte de signal GPS (> 10s)
final gpsLostProvider = NotifierProvider<GpsLostNotifier, bool>(
  GpsLostNotifier.new,
);

class GpsLostNotifier extends Notifier<bool> {
  VoidCallback? _listener;

  @override
  bool build() {
    final service = ref.watch(locationServiceProvider);
    _listener = () {
      state = service.gpsLost.value;
    };
    service.gpsLost.addListener(_listener!);
    ref.onDispose(() {
      if (_listener != null) {
        service.gpsLost.removeListener(_listener!);
      }
    });
    return service.gpsLost.value;
  }
}
