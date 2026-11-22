import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/theme/app_colors.dart';
import 'package:qvgestion_mobile/features/account/presentation/screens/account_screen.dart';
import 'package:qvgestion_mobile/features/admin/presentation/screens/admin_screen.dart';
import 'package:qvgestion_mobile/features/auth/presentation/providers/auth_notifier.dart';
import 'package:qvgestion_mobile/features/map/presentation/screens/home_map_screen.dart';
import 'package:qvgestion_mobile/features/navigation/presentation/providers/navigation_providers.dart';
import 'package:qvgestion_mobile/features/navigation/presentation/widgets/faso_nav_bottom_bar.dart';
import 'package:qvgestion_mobile/features/offline/presentation/screens/saved_places_screen.dart';

/// Écran conteneur principal gérant la barre de navigation officielle Faso Nav
/// L'onglet Administration est réservé aux comptes avec le rôle Administrateur/Modérateur.
/// Sur grand écran (>= 900px, Web Desktop), affiche un rail latéral élégant façon Google Maps.
class MainTabScaffold extends ConsumerWidget {
  const MainTabScaffold({super.key});

  static const double _desktopBreakpoint = 900.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final isAdmin = authState.user?.isAdmin ?? false;
    final currentTab = ref.watch(currentTabProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

    // Si un non-admin se retrouve sur l'onglet admin, le rediriger vers la carte Explorer
    final effectiveTab = (!isAdmin && currentTab == FasoNavTab.admin)
        ? FasoNavTab.explorer
        : currentTab;

    final pages = [
      const HomeMapScreen(),
      _DesktopReadableWrapper(
        enabled: isDesktop,
        child: const SavedPlacesScreen(),
      ),
      _DesktopReadableWrapper(
        enabled: isDesktop,
        child: const AccountScreen(),
      ),
      if (isAdmin)
        _DesktopReadableWrapper(
          enabled: isDesktop,
          child: const AdminScreen(),
        )
      else
        const SizedBox.shrink(),
    ];

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            _DesktopNavRail(
              currentTab: effectiveTab,
              showAdminTab: isAdmin,
              onTabSelected: (tab) {
                ref.read(currentTabProvider.notifier).selectTab(tab);
              },
            ),
            Expanded(
              child: IndexedStack(
                index: effectiveTab.index,
                children: pages,
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: effectiveTab.index,
        children: pages,
      ),
      bottomNavigationBar: FasoNavBottomBar(
        currentTab: effectiveTab,
        showAdminTab: isAdmin,
        onTabSelected: (tab) {
          ref.read(currentTabProvider.notifier).selectTab(tab);
        },
      ),
    );
  }
}

class _DesktopReadableWrapper extends StatelessWidget {
  final bool enabled;
  final Widget child;

  const _DesktopReadableWrapper({
    required this.enabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ColoredBox(
      color: const Color(0xFFF1F5F9),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: child,
        ),
      ),
    );
  }
}

class _DesktopNavRail extends StatelessWidget {
  final FasoNavTab currentTab;
  final bool showAdminTab;
  final ValueChanged<FasoNavTab> onTabSelected;

  const _DesktopNavRail({
    required this.currentTab,
    required this.showAdminTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.explore_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'FASO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 22),
            _buildRailItem(
              tab: FasoNavTab.explorer,
              label: 'Explorer',
              icon: Icons.explore_outlined,
              activeIcon: Icons.explore_rounded,
            ),
            const SizedBox(height: 8),
            _buildRailItem(
              tab: FasoNavTab.sauvegardes,
              label: 'Favoris',
              icon: Icons.cloud_download_outlined,
              activeIcon: Icons.cloud_download_rounded,
            ),
            const SizedBox(height: 8),
            _buildRailItem(
              tab: FasoNavTab.compte,
              label: 'Compte',
              icon: Icons.person_outline_rounded,
              activeIcon: Icons.person_rounded,
            ),
            if (showAdminTab) ...[
              const SizedBox(height: 8),
              _buildRailItem(
                tab: FasoNavTab.admin,
                label: 'Admin',
                icon: Icons.admin_panel_settings_outlined,
                activeIcon: Icons.admin_panel_settings_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRailItem({
    required FasoNavTab tab,
    required String label,
    required IconData icon,
    required IconData activeIcon,
  }) {
    final isSelected = tab == currentTab;
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onTabSelected(tab),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: 66,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected
                    ? AppColors.primary
                    : const Color(0xFF475569),
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected
                      ? AppColors.primary
                      : const Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
