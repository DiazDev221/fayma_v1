import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/operation.dart';
import '../providers.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';

/// Écran 06 - Nouveau dépôt : le client verse une avance, utilisée
/// en déduction de ses prochains achats à crédit.
class DepositScreen extends ConsumerStatefulWidget {
  const DepositScreen({super.key, required this.clientId});

  final String clientId;

  @override
  ConsumerState<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends ConsumerState<DepositScreen> {
  final _amountController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Met à jour le « Nouveau solde en dépôt » à chaque frappe.
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  int get _amount => parseAmount(_amountController.text) ?? 0;

  Future<void> _save(ClientSummary summary) async {
    if (_saving) return;
    setState(() => _saving = true);

    final repo = ref.read(creditRepositoryProvider);
    try {
      await repo.addOperation(
        Operation(
          id: repo.newId(),
          clientId: summary.client.id,
          type: OperationType.deposit,
          amount: _amount,
          date: DateTime.now(),
        ),
      );
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
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(
            child: Text('Impossible de charger le client.'),
          ),
          data: (summary) {
            if (summary == null) {
              return const Center(child: Text('Client introuvable.'));
            }
            return _buildContent(context, summary);
          },
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, ClientSummary summary) {
    final textTheme = Theme.of(context).textTheme;
    final current = summary.balance.deposit;
    final amount = _amount;
    final valid = amount > 0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.pagePadding,
              8,
              AppTheme.pagePadding,
              16,
            ),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
            children: [
              Text(
                summary.client.fullName,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppColors.mintDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              _BalanceCard(
                label: 'Solde en dépôt',
                amount: current,
                background: AppColors.mintSoft,
                color: AppColors.mintDark,
              ),
              const SizedBox(height: 24),
              Text(
                'Montant déposé',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  hintText: '0',
                  suffixText: 'FCFA',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 18,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Nouveau solde en dépôt', style: textTheme.bodySmall),
                  Text(
                    formatFcfa(current + amount),
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.mintDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (summary.hasDebt) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.coralSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Ce client doit encore ${formatFcfa(summary.balance.debt)}. '
                    'Un dépôt n\'est pas déduit de sa dette : il sert pour ses '
                    'prochains achats. Pour payer sa dette, utilisez '
                    '« Remboursement ».',
                    style:
                        textTheme.bodySmall?.copyWith(color: AppColors.coral),
                  ),
                ),
              ],
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
          child: FilledButton(
            onPressed: (valid && !_saving) ? () => _save(summary) : null,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Text('Valider'),
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.amount,
    required this.background,
    required this.color,
  });

  final String label;
  final int amount;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: color)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatFcfa(amount),
              style: textTheme.headlineMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
