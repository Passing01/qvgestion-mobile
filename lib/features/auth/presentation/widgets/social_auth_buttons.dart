import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qvgestion_mobile/core/theme/app_colors.dart';
import 'package:qvgestion_mobile/core/widgets/feedback/app_snackbar.dart';
import 'package:qvgestion_mobile/features/auth/presentation/providers/auth_notifier.dart';

/// Boutons de connexion / inscription sociale (Google, Facebook, Apple).
class SocialAuthButtons extends ConsumerWidget {
  final VoidCallback onSuccess;

  const SocialAuthButtons({super.key, required this.onSuccess});

  Future<void> _handleProviderTap(
    BuildContext context,
    WidgetRef ref,
    String provider,
    String displayName,
  ) async {
    final notifier = ref.read(authNotifierProvider.notifier);
    final configured = notifier.isOAuthConfigured(provider);
    if (!configured) {
      AppSnackbar.showInfo(
        context,
        title: 'Connexion $displayName',
        message:
            'Intégration $displayName prête. Renseignez l\'identifiant client OAuth (${provider.toUpperCase()}_CLIENT_ID) pour activer l\'authentification en production.',
      );
      return;
    }

    final ok = await notifier.startOAuthFlow(provider);
    if (ok && context.mounted) {
      AppSnackbar.showSuccess(
        context,
        title: 'Connecté via $displayName',
        message: 'Bienvenue sur FASO NAV !',
      );
      onSuccess();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoading = ref.watch(authNotifierProvider).isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'Ou continuer avec',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
            const Expanded(child: Divider(color: Color(0xFFE2E8F0))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _SocialChipButton(
                key: const Key('btn_oauth_google'),
                label: 'Google',
                icon: Icons.g_mobiledata_rounded,
                accent: const Color(0xFFDB4437),
                disabled: isLoading,
                onTap: () => _handleProviderTap(context, ref, 'google', 'Google'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SocialChipButton(
                key: const Key('btn_oauth_facebook'),
                label: 'Facebook',
                icon: Icons.facebook_rounded,
                accent: const Color(0xFF1877F2),
                disabled: isLoading,
                onTap: () => _handleProviderTap(context, ref, 'facebook', 'Facebook'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _SocialChipButton(
                key: const Key('btn_oauth_apple'),
                label: 'Apple',
                icon: Icons.apple_rounded,
                accent: const Color(0xFF111827),
                disabled: isLoading,
                onTap: () => _handleProviderTap(context, ref, 'apple', 'Apple'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SocialChipButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color accent;
  final bool disabled;
  final VoidCallback onTap;

  const _SocialChipButton({
    super.key,
    required this.label,
    required this.icon,
    required this.accent,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: disabled ? null : onTap,
      icon: Icon(icon, size: 19, color: accent),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: accent,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
