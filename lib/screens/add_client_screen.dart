import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/client.dart';
import '../models/picked_contact.dart';
import '../providers.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Écran 02 - Ajouter un client : import depuis les contacts ou saisie manuelle.
class AddClientScreen extends ConsumerStatefulWidget {
  const AddClientScreen({super.key});

  @override
  ConsumerState<AddClientScreen> createState() => _AddClientScreenState();
}

class _AddClientScreenState extends ConsumerState<AddClientScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomController = TextEditingController();
  final _prenomController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _nomController.dispose();
    _prenomController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  /// Ouvre l'écran 07 et pré-remplit le formulaire avec le contact choisi.
  Future<void> _importFromContacts() async {
    final picked = await context.push<PickedContact>(AppRoutes.pickContact);
    if (picked == null || !mounted) return;
    setState(() {
      _nomController.text = picked.nom;
      _prenomController.text = picked.prenom;
      _phoneController.text = picked.telephone;
    });
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
    final clients = ref.read(clientsProvider).asData?.value ?? const [];
    for (final client in clients) {
      if (normalizePhone(client.telephone) == phone) {
        return 'Ce numéro existe déjà (${client.fullName})';
      }
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);
    final repo = ref.read(creditRepositoryProvider);
    final client = Client(
      id: repo.newId(),
      nom: _nomController.text.trim(),
      prenom: _prenomController.text.trim(),
      telephone: formatPhone(_phoneController.text),
      createdAt: DateTime.now(),
    );

    try {
      await repo.addClient(client);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ajouter le client.')),
      );
      return;
    }

    if (!mounted) return;
    // Remplace ce formulaire par la fiche du nouveau client.
    context.pushReplacement(AppRoutes.client(client.id));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Nouveau client', style: textTheme.headlineSmall),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  4,
                  AppTheme.pagePadding,
                  16,
                ),
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.manual,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const AppInfoBanner(
                        icon: Icons.person_add_alt_1_outlined,
                        title: 'Un nouveau client',
                        message: 'Ajoutez ses coordonnées pour suivre ses '
                            'achats à crédit et ses paiements.',
                        color: AppColors.mintDark,
                        background: AppColors.mintSoft,
                      ),
                      const SizedBox(height: 16),
                      FaymaCard(
                        onTap: _importFromContacts,
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.indigoSoft,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(
                                Icons.contacts_outlined,
                                color: AppColors.indigo,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Importer depuis mes contacts',
                                    style: textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Prénom, nom et numéro remplis '
                                    'automatiquement',
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Flexible(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'ou saisir manuellement',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: 18),
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
                    : const Icon(Icons.person_add_alt_1_rounded, size: 20),
                label: Text(_saving ? 'Enregistrement…' : 'Ajouter le client'),
              ),
            ),
          ],
        ),
      ),
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
