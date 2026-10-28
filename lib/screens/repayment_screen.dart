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

/// Écran 05 - Remboursement : le client paie tout ou partie de sa dette.
class RepaymentScreen extends ConsumerStatefulWidget {
  const RepaymentScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<RepaymentScreen> createState() => _RepaymentScreenState();
}

class _RepaymentScreenState extends ConsumerState<RepaymentScreen> {
  final _amountController = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Met à jour le « Nouveau solde » à chaque frappe.
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
      type: OperationType.repayment,
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
        const SnackBar(
          content: Text('Impossible d\'enregistrer le remboursement.'),
        ),
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
          'Remboursement',
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
    final amount = _amount;

    final tooHigh = amount > debt;
    final valid = amount > 0 && !tooHigh && debt > 0;
    final newBalance = tooHigh ? debt : debt - amount;

    String? errorText;
    if (debt == 0) {
      errorText = 'Ce client ne doit rien. Utilisez « Dépôt » pour une avance.';
    } else if (tooHigh) {
      errorText = 'Le montant dépasse la dette. '
          'Utilisez « Dépôt » pour enregistrer une avance.';
    }

    final quarter = debt == 0 ? 0 : (debt / 4).round().clamp(1, debt).toInt();
    final half = debt == 0 ? 0 : (debt / 2).round().clamp(1, debt).toInt();

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
                      label: debt > 0 ? 'À crédit' : 'À jour',
                      color: debt > 0 ? AppColors.coral : AppColors.mintDark,
                      background:
                          debt > 0 ? AppColors.coralSoft : AppColors.mintSoft,
                      compact: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _BalanceCard(debt: debt),
              const SizedBox(height: 18),
              FaymaCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Montant remboursé',
                      style: textTheme.titleSmall,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _amountController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      style: textTheme.headlineSmall?.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: InputDecoration(
                        hintText: '0',
                        suffixText: 'FCFA',
                        errorText: errorText,
                        errorMaxLines: 2,
                        contentPadding: const EdgeInsets.symmetric(
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
                            label: '25 %',
                            enabled: debt > 0,
                            onTap: () => _setAmount(quarter),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AmountShortcut(
                            label: '50 %',
                            enabled: debt > 0,
                            onTap: () => _setAmount(half),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _AmountShortcut(
                            label: 'Tout',
                            enabled: debt > 0,
                            onTap: () => _setAmount(debt),
                          ),
                        ),
                      ],
                    ),
                    if (debt == 0) ...[
                      const SizedBox(height: 14),
                      const AppInfoBanner(
                        icon: Icons.info_outline_rounded,
                        message: 'Ce client ne doit rien. Un dépôt permettra '
                            'd’enregistrer une avance.',
                        color: AppColors.indigo,
                        background: AppColors.indigoSoft,
                      ),
                    ],
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
                    AppKeyValueRow(
                      label: 'Dette actuelle',
                      value: formatFcfa(debt),
                      valueColor: AppColors.coral,
                    ),
                    const Divider(),
                    AppKeyValueRow(
                      label: 'Nouveau solde',
                      value: formatFcfa(newBalance),
                      valueColor: newBalance == 0
                          ? AppColors.mintDark
                          : AppColors.coral,
                    ),
                  ],
                ),
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
                : const Icon(Icons.check_rounded, size: 20),
            label: Text(_saving ? 'Enregistrement…' : 'Encaisser'),
          ),
        ),
      ],
    );
  }
}

class _AmountShortcut extends StatelessWidget {
  const _AmountShortcut({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
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
  const _BalanceCard({required this.debt});

  final int debt;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: debt > 0 ? AppColors.coralSoft : AppColors.mintSoft,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                debt > 0
                    ? Icons.account_balance_wallet_outlined
                    : Icons.check_circle_outline_rounded,
                size: 17,
                color: debt > 0 ? AppColors.coral : AppColors.mintDark,
              ),
              const SizedBox(width: 6),
              Text(
                debt > 0 ? 'Solde actuel dû' : 'Compte à jour',
                style: textTheme.bodySmall?.copyWith(
                  color: debt > 0 ? AppColors.coral : AppColors.mintDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatFcfa(debt),
              style: textTheme.headlineMedium?.copyWith(
                color: debt > 0 ? AppColors.coral : AppColors.mintDark,
                fontSize: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
