import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qvgestion_mobile/core/di/core_providers.dart';
import 'package:qvgestion_mobile/core/utils/app_logger.dart';
import 'package:qvgestion_mobile/features/offline/data/models/offline_pack_model.dart';
import 'package:qvgestion_mobile/features/offline/data/models/offline_pois_export_model.dart';
import 'package:qvgestion_mobile/features/offline/data/repositories/offline_repository.dart';
import 'package:qvgestion_mobile/features/places/data/models/place_model.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';

/// Provider d'accès au repository offline
final offlineRepositoryProvider = Provider<OfflineRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return OfflineRepository(apiClient: apiClient);
});

/// Provider de la liste des packs disponibles sur le serveur
final availableOfflinePacksProvider =
    FutureProvider<List<OfflinePackModel>>((ref) async {
  final repository = ref.watch(offlineRepositoryProvider);
  return repository.getAvailablePacks();
});

/// État global des packs installés sur le smartphone
class InstalledPacksState {
  final Map<String, OfflinePackModel> installedPacks;
  final Map<String, double> downloadingProgress;

  const InstalledPacksState({
    this.installedPacks = const {},
    this.downloadingProgress = const {},
  });

  InstalledPacksState copyWith({
    Map<String, OfflinePackModel>? installedPacks,
    Map<String, double>? downloadingProgress,
  }) {
    return InstalledPacksState(
      installedPacks: installedPacks ?? this.installedPacks,
      downloadingProgress: downloadingProgress ?? this.downloadingProgress,
    );
  }

  /// Espace disque total consommé par les tuiles vectorielles (en Mo)
  double get totalStorageUsedMo {
    return installedPacks.values
        .fold(0.0, (acc, pack) => acc + pack.tailleMo);
  }

  /// Total de lieux d'intérêts disponibles sans connexion
  int get totalOfflinePoisCount {
    return installedPacks.values
        .fold(0, (acc, pack) => acc + pack.poiCount);
  }

  bool isInstalled(String regionId) => installedPacks.containsKey(regionId);
  bool isDownloading(String regionId) => downloadingProgress.containsKey(regionId);
  double? getProgress(String regionId) => downloadingProgress[regionId];
}

class InstalledPacksNotifier extends Notifier<InstalledPacksState> {
  static const String _installedPacksKey = 'fasonav_installed_packs_v1';

  @override
  InstalledPacksState build() {
    _restoreFromPrefs();
    return const InstalledPacksState();
  }

  Future<void> _restoreFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_installedPacksKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final restored = <String, OfflinePackModel>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final pack = OfflinePackModel.fromJson(
            Map<String, dynamic>.from(value),
            isDownloaded: true,
          );
          restored[key.toString()] = pack;
        }
      });
      if (restored.isNotEmpty) {
        state = state.copyWith(installedPacks: restored);
      }
    } catch (e) {
      AppLogger.w('Restauration packs hors-ligne: $e');
    }
  }

  Future<void> _persistToPrefs(Map<String, OfflinePackModel> packs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{};
      packs.forEach((k, v) => payload[k] = v.toJson());
      await prefs.setString(_installedPacksKey, jsonEncode(payload));
    } catch (e) {
      AppLogger.w('Sauvegarde packs hors-ligne: $e');
    }
  }

  /// Télécharge réellement les POIs du pack régional et les persiste en local hors-ligne.
  Future<void> downloadPack(OfflinePackModel pack) async {
    final regionId = pack.regionId;
    if (state.isInstalled(regionId) || state.isDownloading(regionId)) return;

    final newProgress = Map<String, double>.from(state.downloadingProgress);
    newProgress[regionId] = 0.2;
    state = state.copyWith(downloadingProgress: newProgress);

    try {
      final offlineRepo = ref.read(offlineRepositoryProvider);
      final placesRepo = ref.read(placesRepositoryProvider);

      // 1. Téléchargement et stockage local des POIs de la région
      final export = await offlineRepo.getRegionPois(regionId);
      newProgress[regionId] = 0.65;
      state = state.copyWith(downloadingProgress: Map.from(newProgress));

      // 2. Fusion dans le cache local de recherche & carte hors-ligne
      if (export.pois.isNotEmpty) {
        final models = export.pois
            .map(
              (p) => PlaceModel(
                id: p.id,
                nom: p.nom,
                categorieId: 0,
                latitude: p.latitude,
                longitude: p.longitude,
                ville: pack.nomRegion,
                quartier: p.quartier,
                telephone: p.telephone,
              ),
            )
            .toList();
        await placesRepo.cachePlacesList(models);
      } else {
        await placesRepo.downloadPlacesForOffline(const [
          'pharmacie',
          'hopital-sante',
          'station-service',
          'maquis-restaurant',
        ]);
      }

      newProgress[regionId] = 0.9;
      state = state.copyWith(downloadingProgress: Map.from(newProgress));

      final updatedPacks = Map<String, OfflinePackModel>.from(state.installedPacks);
      updatedPacks[regionId] = pack.copyWith(
        isDownloaded: true,
        poiCount: export.pois.isNotEmpty ? export.pois.length : pack.poiCount,
      );

      await _persistToPrefs(updatedPacks);
      newProgress.remove(regionId);
      state = state.copyWith(
        installedPacks: updatedPacks,
        downloadingProgress: newProgress,
      );

      AppLogger.i(
        'Pack $regionId téléchargé (${export.pois.length} POIs persistés en local).',
      );
    } catch (e, stack) {
      AppLogger.e('Erreur lors du téléchargement du pack $regionId', e, stack);
      newProgress.remove(regionId);
      state = state.copyWith(downloadingProgress: newProgress);
    }
  }

  /// Supprime un pack installé pour libérer de l'espace de stockage
  Future<void> removePack(String regionId) async {
    if (!state.isInstalled(regionId)) return;

    final updatedPacks = Map<String, OfflinePackModel>.from(state.installedPacks);
    updatedPacks.remove(regionId);
    state = state.copyWith(installedPacks: updatedPacks);
    await _persistToPrefs(updatedPacks);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('fasonav_region_pois_$regionId');
    } catch (_) {}
    AppLogger.i('Pack $regionId supprimé du stockage local.');
  }
}

final installedPacksProvider =
    NotifierProvider<InstalledPacksNotifier, InstalledPacksState>(
  InstalledPacksNotifier.new,
);

/// Provider de l'export des POIs d'une région sélectionnée
final regionPoisProvider =
    FutureProvider.family<OfflinePoisExportModel, String>((ref, regionId) async {
  final repository = ref.watch(offlineRepositoryProvider);
  return repository.getRegionPois(regionId);
});
