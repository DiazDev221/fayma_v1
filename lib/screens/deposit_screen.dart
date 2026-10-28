import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/operation.dart';
import '../models/payment_method.dart';
import '../providers.dart';
import '../services/operation_sms.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_widgets.dart';
import '../widgets/payment_method_selector.dart';

/// Écran 06 - Nouveau dépôt : le client verse une somme, imputée d'abord
/// sur sa dette, puis conservée en avance pour ses prochains achats à crédit.
class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Met à jour la répartition dette / dépôt à chaque frappe.
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int get _amount => parseAmount(_amountController.text) ?? 0;

  void _setAmount(int value) {
    _amountController.text = value.toString();
    _amountController.selection = TextSelection.collapsed(
      offset: _amountController.text.length,
    );
  }

  Future<void> _save(ClientSummary summary) async {
    if (_saving) return;
    setState(() => _saving = true);

    final repo = ref.read(creditRepositoryProvider);
    final operation = Operation(
      id: repo.newId(),
      clientId: summary.client.id,
      type: OperationType.deposit,
      amount: _amount,
      date: DateTime.now(),
      paymentMethod: _method,
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
        const SnackBar(content: Text('Impossible d\'enregistrer le dépôt.')),
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
          'Nouveau dépôt',
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
    final debt = summary.balance.debt;
    final currentDeposit = summary.balance.deposit;
    final amount = _amount;
    final valid = amount > 0;

    // Le versement règle d'abord la dette, le surplus reste en dépôt.
    final paidOnDebt = math.min(amount, debt);
    final remainingDebt = debt - paidOnDebt;
    final newDeposit = currentDeposit + amount - paidOnDebt;

    final String allocationText;
    if (debt == 0) {
      allocationText = 'Le montant s’ajoute au dépôt du client.';
    } else if (amount == 0) {
      allocationText = 'Ce versement sera d’abord déduit de la dette du '
          'client. Le surplus, s’il y en a, restera en dépôt.';
    } else if (newDeposit > 0) {
      allocationText = 'Sur ${formatFcfa(amount)} : '
          '${formatFcfa(paidOnDebt)} déduits de la dette et '
          '${formatFcfa(newDeposit)} conservés en dépôt.';
    } else {
      allocationText = '${formatFcfa(paidOnDebt)} seront déduits de la dette '
          'du client.';
    }

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
                            summary.client.telephone,
                            style: textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    AppStatusPill(
                      label: debt > 0 ? 'À crédit' : 'Dépôt',
                      color: debt > 0 ? AppColors.coral : AppColors.mintDark,
                      background:
                          debt > 0 ? AppColors.coralSoft : AppColors.mintSoft,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _BalanceCard(
                debt: debt,
                deposit: currentDeposit,
              ),
              const SizedBox(height: 18),
              FaymaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Montant versé', style: textTheme.titleSmall),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(9),
                      ],
                      style: textTheme.headlineSmall?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        hintText: '0',
                        suffixText: 'FCFA',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _AmountShortcut(
                            label: '1 000',
                            onTap: () => _setAmount(1000),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AmountShortcut(
                            label: '5 000',
                            onTap: () => _setAmount(5000),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AmountShortcut(
                            label: '10 000',
                            onTap: () => _setAmount(10000),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              PaymentMethodSelector(
                value: _method,
                onChanged: (method) => setState(() => _method = method),
              ),
              const SizedBox(height: 16),
              FaymaCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    if (debt > 0) ...[
                      AppKeyValueRow(
                        label: 'Nouvelle dette',
                        value: formatFcfa(remainingDebt),
                        valueColor: remainingDebt > 0
                            ? AppColors.coral
                            : AppColors.mintDark,
                      ),
                      if (newDeposit > 0) ...[
                        const Divider(),
                        AppKeyValueRow(
                          label: 'Nouveau solde en dépôt',
                          value: formatFcfa(newDeposit),
                          valueColor: AppColors.mintDark,
                        ),
                      ],
                    ] else
                      AppKeyValueRow(
                        label: 'Nouveau solde en dépôt',
                        value: formatFcfa(newDeposit),
                        valueColor: AppColors.mintDark,
                      ),
                    if (amount > 0) ...[
                      const SizedBox(height: 12),
                      _AllocationBar(
                        paidOnDebt: paidOnDebt,
                        newDeposit: amount - paidOnDebt,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AppInfoBanner(
                icon:
                    debt > 0 ? Icons.alt_route_rounded : Icons.savings_outlined,
                message: allocationText,
                color: debt > 0 ? AppColors.indigo : AppColors.mintDark,
                background:
                    debt > 0 ? AppColors.indigoSoft : AppColors.mintSoft,
              ),
            ],
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
            onPressed: (valid && !_saving) ? () => _save(summary) : null,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.savings_outlined, size: 20),
            label: Text(_saving ? 'Enregistrement…' : 'Enregistrer le dépôt'),
          ),
        ),
      ],
    );
  }
}

class _AmountShortcut extends StatelessWidget {
  const _AmountShortcut({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(38),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.mintDark,
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium,
      ),
      child: Text(label),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.debt, required this.deposit});

  final int debt;
  final int deposit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasDebt = debt > 0;
    final color = hasDebt ? AppColors.coral : AppColors.mintDark;
    final background = hasDebt ? AppColors.coralSoft : AppColors.mintSoft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                hasDebt
                    ? Icons.account_balance_wallet_outlined
                    : Icons.savings_outlined,
                size: 17,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                hasDebt ? 'Dette actuelle' : 'Solde en dépôt',
                style: textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatFcfa(hasDebt ? debt : deposit),
              style: textTheme.headlineMedium?.copyWith(
                color: color,
                fontSize: 30,
              ),
            ),
          ),
          if (hasDebt && deposit > 0) ...[
            const SizedBox(height: 5),
            Text(
              'Dépôt disponible : ${formatFcfa(deposit)}',
              style: textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

class _AllocationBar extends StatelessWidget {
  const _AllocationBar({
    required this.paidOnDebt,
    required this.newDeposit,
  });

  final int paidOnDebt;
  final int newDeposit;

  @override
  Widget build(BuildContext context) {
    final total = paidOnDebt + newDeposit;
    if (total == 0) return const SizedBox.shrink();
    final debtShare = paidOnDebt / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                if (paidOnDebt > 0)
                  Expanded(
                    flex: math.max(1, (debtShare * 1000).round()),
                    child: const ColoredBox(color: AppColors.coral),
                  ),
                if (newDeposit > 0)
                  Expanded(
                    flex: math.max(1, ((1 - debtShare) * 1000).round()),
                    child: const ColoredBox(color: AppColors.mint),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            if (paidOnDebt > 0)
              _Legend(
                color: AppColors.coral,
                label: 'Dette ${formatAmount(paidOnDebt)}',
              ),
            if (paidOnDebt > 0 && newDeposit > 0) const SizedBox(width: 12),
            if (newDeposit > 0)
              _Legend(
                color: AppColors.mint,
                label: 'Dépôt ${formatAmount(newDeposit)}',
              ),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ],
    );
  }
}
