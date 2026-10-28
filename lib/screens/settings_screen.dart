import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Écran - Paramètres : clients, nom de la boutique et sauvegarde.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = ref.read(shopSettingsProvider);
    var name = '';
    try {
      name = await store.readShopName();
    } catch (error) {
      debugPrint('Chargement du nom de la boutique : $error');
    }
    if (!mounted) return;
    setState(() {
      _nameController.text = name;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving || _loading) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final store = ref.read(shopSettingsProvider);
    final name = _nameController.text.trim();

    try {
      await store.saveShopName(name);
      ref.invalidate(shopNameProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Nom de la boutique enregistré.')),
        );
    } catch (error) {
      debugPrint('Enregistrement du nom de la boutique : $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'enregistrer le nom de la boutique.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final clientCount = ref.watch(clientsProvider).valueOrNull?.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Paramètres', style: textTheme.headlineSmall),
      ),
      body: SafeArea(
        child: _loading
            ? const AppLoading(label: 'Chargement des paramètres…')
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  4,
                  AppTheme.pagePadding,
                  32,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                children: [
                  const AppSectionHeader(
                    title: 'Gestion',
                    subtitle: 'Tout ce qu’il faut pour tenir votre boutique.',
                  ),
                  const SizedBox(height: 12),
                  _SettingsTile(
                    icon: Icons.people_alt_outlined,
                    color: AppColors.indigo,
                    background: AppColors.indigoSoft,
                    title: 'Clients',
                    subtitle: clientCount == null
                        ? 'Consulter, ajouter ou modifier un client.'
                        : '$clientCount client${clientCount > 1 ? 's' : ''} '
                            'enregistré${clientCount > 1 ? 's' : ''}.',
                    onTap: () => context.push(AppRoutes.clients),
                  ),
                  const SizedBox(height: 10),
                  _SettingsTile(
                    icon: Icons.cloud_upload_outlined,
                    color: AppColors.mintDark,
                    background: AppColors.mintSoft,
                    title: 'Sauvegarde',
                    subtitle:
                        'Exporter ou restaurer les données de la boutique.',
                    onTap: () => context.push(AppRoutes.backup),
                  ),
                  const SizedBox(height: 26),
                  const AppSectionHeader(
                    title: 'Boutique',
                    subtitle: 'Le nom signe les SMS envoyés à vos clients.',
                  ),
                  const SizedBox(height: 12),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FaymaCard(
                          padding: const EdgeInsets.all(17),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Nom de la boutique',
                                style: textTheme.titleSmall?.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 7),
                              TextFormField(
                                controller: _nameController,
                                textCapitalization: TextCapitalization.words,
                                textInputAction: TextInputAction.done,
                                inputFormatters: [
                                  LengthLimitingTextInputFormatter(40),
                                ],
                                decoration: const InputDecoration(
                                  hintText: 'Ex : Boutique Awa',
                                  prefixIcon: Icon(Icons.storefront_outlined),
                                ),
                                onFieldSubmitted: (_) => _save(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _nameController,
                          builder: (context, value, _) {
                            final name = value.text.trim();
                            return FaymaCard(
                              color: AppColors.surfaceMuted,
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.sms_outlined,
                                        size: 17,
                                        color: AppColors.textSecondary,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          'Aperçu de la signature',
                                          overflow: TextOverflow.ellipsis,
                                          style: textTheme.titleSmall
                                              ?.copyWith(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Merci de votre confiance.',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  Text(
                                    name.isEmpty ? 'Votre boutique' : name,
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: name.isEmpty
                                          ? AppColors.textSecondary
                                          : AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.check_rounded, size: 20),
                          label: Text(
                            _saving ? 'Enregistrement…' : 'Enregistrer le nom',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AppInfoBanner(
                    icon: Icons.phone_android_outlined,
                    message: 'Vos données restent sur ce téléphone. Pensez à '
                        'exporter une sauvegarde régulièrement.',
                    color: AppColors.textSecondary,
                    background: AppColors.surfaceMuted,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FaymaCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(subtitle, style: textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}
