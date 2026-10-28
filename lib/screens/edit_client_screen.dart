import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/client.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Écran 03b - Modifier le nom, le prénom et le numéro d'un client.
class EditClientScreen extends ConsumerStatefulWidget {
  const EditClientScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<EditClientScreen> createState() => _EditClientScreenState();
}

class _EditClientScreenState extends ConsumerState<EditClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _phoneController = TextEditingController();

  Client? _client;
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _loadFailed = false;
      });
    }

    try {
      final client =
          await ref.read(creditRepositoryProvider).getClient(widget.clientId);
      if (!mounted) return;

      if (client != null) {
        _nomController.text = client.nom;
        _prenomController.text = client.prenom;
        _phoneController.text = client.telephone;
      }
      setState(() {
        _client = client;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Lecture du client : $error');
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
        _loading = false;
      });
    }
  }

  String? _validateName(String? value, String label) {
    if (value == null || value.trim().isEmpty) {
      return '$label obligatoire';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final phone = normalizePhone(value ?? '');
    if (phone == null) {
      return 'Numéro à 9 chiffres (ex : 77 123 45 67)';
    }

    final clients = ref.read(clientsProvider).asData?.value ?? const <Client>[];
    for (final client in clients) {
      // Le numéro actuel du client reste autorisé.
      if (client.id == widget.clientId) continue;
      if (normalizePhone(client.telephone) == phone) {
        return 'Ce numéro existe déjà (${client.fullName})';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    final client = _client;
    if (client == null) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final updated = client.copyWith(
      nom: _nomController.text.trim(),
      prenom: _prenomController.text.trim(),
      telephone: formatPhone(_phoneController.text),
    );

    try {
      await ref.read(creditRepositoryProvider).updateClient(updated);
    } catch (error) {
      debugPrint('Modification du client : $error');
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Impossible de modifier le client.')),
        );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    context.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Client modifié.')));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Modifier le client', style: textTheme.headlineSmall),
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const AppLoading(label: 'Chargement du client…');
    }

    if (_loadFailed) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          child: AppEmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Client indisponible',
            message: 'Impossible de charger les informations de ce client.',
            primaryLabel: 'Réessayer',
            primaryIcon: Icons.refresh_rounded,
            onPrimary: _load,
            color: AppColors.coral,
            background: AppColors.coralSoft,
          ),
        ),
      );
    }

    if (_client == null) {
      return const Center(
        child: AppEmptyState(
          icon: Icons.person_off_outlined,
          title: 'Client introuvable',
          message: 'Ce client n’existe plus dans votre boutique.',
          color: AppColors.indigo,
          background: AppColors.indigoSoft,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              4,
              AppTheme.pagePadding,
              16,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppInfoBanner(
                    icon: Icons.edit_outlined,
                    title: 'Coordonnées du client',
                    message: 'L’historique des achats, remboursements et '
                        'dépôts reste inchangé.',
                    color: AppColors.indigo,
                    background: AppColors.indigoSoft,
                  ),
                  const SizedBox(height: 16),
                  FaymaCard(
                    padding: const EdgeInsets.all(17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledField(
                          label: 'Nom',
                          child: TextFormField(
                            controller: _nomController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.familyName],
                            decoration: const InputDecoration(
                              hintText: 'Ex : Diop',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            validator: (v) => _validateName(v, 'Nom'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LabeledField(
                          label: 'Prénom',
                          child: TextFormField(
                            controller: _prenomController,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.givenName],
                            decoration: const InputDecoration(
                              hintText: 'Ex : Moussa',
                              prefixIcon: Icon(Icons.badge_outlined),
                            ),
                            validator: (v) => _validateName(v, 'Prénom'),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LabeledField(
                          label: 'Numéro de téléphone',
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9 +]'),
                              ),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'Ex : 77 123 45 67',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: _validatePhone,
                            onFieldSubmitted: (_) => _save(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.pagePadding,
            8,
            AppTheme.pagePadding,
            20,
          ),
          child: FilledButton.icon(
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
                : const Icon(Icons.save_outlined, size: 20),
            label: Text(
              _saving ? 'Enregistrement…' : 'Enregistrer les modifications',
            ),
          ),
        ),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontSize: 13,
              ),
        ),
        const SizedBox(height: 7),
        child,
      ],
    );
  }
}
