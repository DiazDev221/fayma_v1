import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/operation.dart';
import '../providers.dart';
import '../services/operation_sms.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';

/// Écran 04 - Nouvel achat à crédit : lignes produit/prix, total, validation.
class PurchaseScreen extends ConsumerStatefulWidget {
  const PurchaseScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends ConsumerState<PurchaseScreen> {
  final _productController = TextEditingController();
  final _priceController = TextEditingController();
  final _productFocus = FocusNode();

  final List<PurchaseItem> _items = [];
  String? _inputError;
  bool _saving = false;

  @override
  void dispose() {
    _productController.dispose();
    _priceController.dispose();
    _productFocus.dispose();
    super.dispose();
  }

  int get _total => _items.fold<int>(0, (sum, item) => sum + item.price);

  void _addItem() {
    final name = _productController.text.trim();
    final price = parseAmount(_priceController.text);
    if (name.isEmpty) {
      setState(() => _inputError = 'Saisissez le nom du produit.');
      return;
    }
    if (price == null || price <= 0) {
      setState(() => _inputError = 'Saisissez un prix supérieur à 0.');
      return;
    }
    setState(() {
      _items.add(PurchaseItem(name: name, price: price));
      _productController.clear();
      _priceController.clear();
      _inputError = null;
    });
    _productFocus.requestFocus();
  }

  Future<void> _save(ClientSummary summary) async {
    if (_saving || _items.isEmpty) return;
    setState(() => _saving = true);

    final repo = ref.read(creditRepositoryProvider);
    final operation = Operation.purchase(
      id: repo.newId(),
      clientId: summary.client.id,
      items: List.of(_items),
      date: DateTime.now(),
    );
    final sms = await prepareOperationSms(
      ref: ref,
      context: context,
      summary: summary,
      operation: operation,
    );

    try {
      await repo.addOperation(operation);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'enregistrer l\'achat.')),
      );
      return;
    }

    if (!mounted) return;
    context.pop();
    sms.send();
  }

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(clientSummaryProvider(widget.clientId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Nouvel achat',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const AppLoading(label: 'Chargement du client…'),
          error: (_, __) => const Center(
            child: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Client indisponible',
              message: 'Impossible de charger les informations du client.',
              color: AppColors.coral,
              background: AppColors.coralSoft,
            ),
          ),
          data: (summary) {
            if (summary == null) {
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
            return _buildContent(context, summary);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ClientSummary summary) {
    final textTheme = Theme.of(context).textTheme;
    final balance = summary.balance;

    // Le dépôt du client est utilisé avant de créer une dette.
    final depositUsed = math.min(balance.deposit, _total);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              4,
              AppTheme.pagePadding,
              16,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            children: [
              FaymaCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    ClientAvatar(name: summary.client.fullName, size: 38),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            summary.client.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Dette actuelle : ${formatFcfa(balance.debt)}',
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const AppStatusPill(
                      label: 'À crédit',
                      color: AppColors.indigo,
                      background: AppColors.indigoSoft,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FaymaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Ajouter un produit',
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _productController,
                      focusNode: _productFocus,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        hintText: 'Ex : Sac de riz 25 kg',
                        labelText: 'Produit',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _priceController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: const InputDecoration(
                              hintText: '0',
                              labelText: 'Prix',
                              suffixText: 'FCFA',
                            ),
                            onSubmitted: (_) => _addItem(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: IconButton.filled(
                            onPressed: _addItem,
                            tooltip: 'Ajouter le produit',
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.indigo,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.add_rounded, size: 24),
                          ),
                        ),
                      ],
                    ),
                    if (_inputError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _inputError!,
                        style: textTheme.bodySmall?.copyWith(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              AppSectionHeader(
                title: 'Produits ajoutés',
                subtitle: _items.isEmpty
                    ? 'Aucun produit pour le moment'
                    : '${_items.length} produit'
                        '${_items.length > 1 ? 's' : ''} dans cet achat',
                trailing: _items.isEmpty
                    ? null
                    : TextButton(
                        onPressed: () => setState(_items.clear),
                        child: const Text('Vider'),
                      ),
              ),
              const SizedBox(height: 12),
              if (_items.isEmpty)
                const FaymaCard(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: AppEmptyState(
                    icon: Icons.shopping_basket_outlined,
                    title: 'Le panier est vide',
                    message: 'Ajoutez les produits pris à crédit pour '
                        'calculer le total.',
                    color: AppColors.indigo,
                    background: AppColors.indigoSoft,
                  ),
                )
              else
                for (var i = 0; i < _items.length; i++) ...[
                  _ItemRow(
                    item: _items[i],
                    onRemove: () => setState(() => _items.removeAt(i)),
                  ),
                  const SizedBox(height: 9),
                ],
            ],
          ),
        ),
        _SummaryPanel(
          total: _total,
          depositUsed: depositUsed,
          saving: _saving,
          canSave: _items.isNotEmpty && !_saving,
          onSave: () => _save(summary),
        ),
      ],
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.total,
    required this.depositUsed,
    required this.saving,
    required this.canSave,
    required this.onSave,
  });

  final int total;
  final int depositUsed;
  final bool saving;
  final bool canSave;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.pagePadding,
        16,
        AppTheme.pagePadding,
        20,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 24,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (depositUsed > 0) ...[
            Row(
              children: [
                const Icon(
                  Icons.savings_outlined,
                  size: 15,
                  color: AppColors.mintDark,
                ),
                const SizedBox(width: 5),
                Text(
                  'Dépôt utilisé : ${formatFcfa(depositUsed)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.mintDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Text('Total', style: textTheme.titleMedium),
              ),
              Text(
                formatFcfa(total),
                style: textTheme.headlineSmall?.copyWith(
                  color: AppColors.indigo,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.indigo,
            ),
            onPressed: canSave ? onSave : null,
            icon: saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(saving ? 'Enregistrement…' : 'Enregistrer l’achat'),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, required this.onRemove});

  final PurchaseItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FaymaCard(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.indigoSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.shopping_bag_outlined,
              size: 18,
              color: AppColors.indigo,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatFcfa(item.price),
            style: textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
          IconButton(
            tooltip: 'Retirer',
            icon: const Icon(Icons.close_rounded, size: 18),
            color: AppColors.textSecondary,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
