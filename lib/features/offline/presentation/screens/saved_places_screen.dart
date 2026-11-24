import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/services/location_service.dart';
import 'package:qvgestion_mobile/core/theme/app_colors.dart';
import 'package:qvgestion_mobile/core/widgets/feedback/app_snackbar.dart';
import 'package:qvgestion_mobile/features/navigation/presentation/providers/navigation_providers.dart';
import 'package:qvgestion_mobile/features/navigation/presentation/widgets/faso_nav_bottom_bar.dart';
import 'package:qvgestion_mobile/features/offline/data/models/offline_pack_model.dart';
import 'package:qvgestion_mobile/features/offline/presentation/providers/offline_providers.dart';
import 'package:qvgestion_mobile/features/offline/presentation/widgets/offline_pois_modal.dart';
import 'package:qvgestion_mobile/features/places/presentation/providers/places_providers.dart';
import 'package:qvgestion_mobile/features/places/presentation/widgets/save_place_modal.dart';
import 'package:qvgestion_mobile/features/traffic/presentation/widgets/share_trip_sheet.dart';

/// Onglet 3 officiel : Lieux sauvegardés & Cartes hors-ligne (PMTiles)
/// Entièrement dynamique et connecté à l'API Railway
class SavedPlacesScreen extends ConsumerWidget {
  const SavedPlacesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availablePacksAsync = ref.watch(availableOfflinePacksProvider);
    final installedState = ref.watch(installedPacksProvider);
    final favoritesAsync = ref.watch(myFavoritesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text(
          'Mes adresses & Hors-ligne',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(availableOfflinePacksProvider);
              ref.invalidate(myFavoritesProvider);
              AppSnackbar.showInfo(
                context,
                title: 'Synchronisation',
                message: 'Actualisation des packs régionaux et favoris...',
              );
            },
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF374151)),
            tooltip: 'Rafraîchir les packs',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 0. RACCOURCIS GRAND PUBLIC EN 1 CLIC (Maison & Partager ma position)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    final lastGps = ref.read(locationServiceProvider).last;
                    final loc = ref.read(currentLocationProvider);
                    SavePlaceModal.show(
                      context,
                      latitude: lastGps?.latitude ?? loc.lat,
                      longitude: lastGps?.longitude ?? loc.lon,
                      initialName: 'Ma maison',
                      initialCategory: 'domicile',
                    );
                  },
                  icon: const Icon(Icons.home_rounded, size: 20),
                  label: const Text('Ma maison'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    final lastGps = ref.read(locationServiceProvider).last;
                    final loc = ref.read(currentLocationProvider);
                    ShareTripSheet.show(
                      context,
                      currentLat: lastGps?.latitude ?? loc.lat,
                      currentLon: lastGps?.longitude ?? loc.lon,
                    );
                  },
                  icon: const Icon(Icons.share_location_rounded, size: 20),
                  label: const Text('Ma position'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    side: const BorderSide(color: Color(0xFF0F766E)),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 1. BANNIÈRE D'ÉTAT DU STOCKAGE HORS-LIGNE
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.offline_pin_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        installedState.installedPacks.isNotEmpty
                            ? 'Lieux Hors-Ligne Sauvegardés'
                            : 'Aucun pack hors-ligne téléchargé',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        installedState.installedPacks.isNotEmpty
                            ? '${installedState.installedPacks.length} région(s) mémorisée(s) • '
                                '${installedState.totalOfflinePoisCount} lieux accessibles sans internet'
                            : 'Téléchargez votre région ci-dessous avant de voyager sans connexion.',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF047857),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 22),

          // 2. SECTION DES PACKS RÉGIONAUX (Connectée au backend)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cartes sans internet',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                'Sans crédit requis',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 12),

          availablePacksAsync.when(
            data: (packs) {
              if (packs.isEmpty) {
                return const Center(
                  child: Text('Aucun pack cartographique disponible.'),
                );
              }

              return Column(
                children: packs.map((pack) {
                  final isDownloaded =
                      installedState.isInstalled(pack.regionId);
                  final isDownloading =
                      installedState.isDownloading(pack.regionId);
                  final progress =
                      installedState.getProgress(pack.regionId) ?? 0.0;

                  return _buildPackCard(
                    context,
                    ref: ref,
                    pack: pack,
                    isDownloaded: isDownloaded,
                    isDownloading: isDownloading,
                    downloadProgress: progress,
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFDC2626)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Erreur de récupération des packs : $e',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(availableOfflinePacksProvider),
                    child: const Text('Réessayer'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 3. SECTION DES LIEUX FAVORIS (Réels + cache hors-ligne)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Mes Lieux Favoris',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              IconButton(
                onPressed: () => ref.invalidate(myFavoritesProvider),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                tooltip: 'Rafraîchir mes favoris',
              ),
            ],
          ),
          const SizedBox(height: 8),
          favoritesAsync.when(
            data: (favorites) {
              if (favorites.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Text(
                    'Aucun lieu favori enregistré pour le moment.\nTouchez un lieu sur la carte puis sur le cœur ♥ pour le retrouver ici même sans connexion.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7280)),
                  ),
                );
              }
              return Column(
                children: favorites.map((place) {
                  return _buildFavoriteItem(
                    name: place.nom,
                    subtitle:
                        '${place.ville}${place.quartier != null ? " • ${place.quartier}" : ""}',
                    icon: Icons.place_rounded,
                    onTap: () {
                      ref
                          .read(selectedPlaceProvider.notifier)
                          .select(place);
                      ref
                          .read(currentTabProvider.notifier)
                          .selectTab(FasoNavTab.explorer);
                    },
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (_, _) => const Text(
              'Connectez-vous pour synchroniser vos favoris entre vos appareils.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackCard(
    BuildContext context, {
    required WidgetRef ref,
    required OfflinePackModel pack,
    required bool isDownloaded,
    required bool isDownloading,
    required double downloadProgress,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDownloaded
              ? const Color(0xFFA7F3D0)
              : const Color(0xFFE5E7EB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDownloaded
                      ? const Color(0xFFECFDF5)
                      : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  pack.iconData,
                  color: isDownloaded
                      ? const Color(0xFF10B981)
                      : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.nomRegion,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${pack.formattedSize} • ${pack.poiCount} POI • v${pack.version}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (isDownloaded) ...[
                // Bouton Consulter les POIs du pack
                IconButton(
                  onPressed: () => OfflinePoisModal.show(context, pack),
                  icon: const Icon(Icons.visibility_outlined,
                      size: 20, color: Color(0xFF374151)),
                  tooltip: 'Voir les POIs indexés',
                ),
                // Bouton Supprimer pour libérer l'espace
                IconButton(
                  onPressed: () {
                    ref
                        .read(installedPacksProvider.notifier)
                        .removePack(pack.regionId);
                    AppSnackbar.showInfo(
                      context,
                      title: 'Espace libéré',
                      message: 'Le pack ${pack.nomRegion} a été supprimé.',
                    );
                  },
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: Color(0xFFEF4444)),
                  tooltip: 'Supprimer le pack',
                ),
              ] else if (isDownloading) ...[
                Text(
                  '${(downloadProgress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ] else ...[
                ElevatedButton.icon(
                  onPressed: () {
                    ref
                        .read(installedPacksProvider.notifier)
                        .downloadPack(pack);
                    AppSnackbar.showSuccess(
                      context,
                      title: 'Téléchargement démarré',
                      message:
                          'Téléchargement de ${pack.nomRegion} avec reprise HTTP Range (206)...',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.cloud_download_rounded, size: 14),
                  label: const Text('Télécharger', style: TextStyle(fontSize: 11)),
                ),
              ],
            ],
          ),

          // Barre de progression si téléchargement en cours
          if (isDownloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: downloadProgress,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(AppColors.primary),
                minHeight: 6,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFavoriteItem({
    required String name,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: AppColors.primaryLight,
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: Text(subtitle, style: const TextStyle(fontSize: 11)),
          trailing: const Icon(Icons.favorite_rounded, color: Color(0xFFEF4444)),
        ),
      ),
    );
  }
}
