import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/operation.dart';
import '../providers.dart';
import '../router/app_router.dart';
import '../services/operation_sms.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/operation_order.dart';
import '../utils/share_origin.dart';
import '../widgets/app_widgets.dart';
import '../widgets/payment_method_selector.dart';

/// Écran 03 - Fiche client : solde, actions et historique des opérations.
class ClientDetailScreen extends ConsumerWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final String clientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(clientSummaryProvider(clientId));
    final operations =
        ref.watch(clientOperationsProvider(clientId)).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            onPressed: () => context.push(AppRoutes.editClient(clientId)),
            tooltip: 'Modifier le client',
            icon: const Icon(Icons.edit_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: summaryAsync.when(
          loading: () => const AppLoading(label: 'Chargement du client…'),
          error: (_, __) => const Center(
            child: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Client indisponible',
              message: 'Impossible de charger les informations de ce client.',
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
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                0,
                AppTheme.pagePadding,
                32,
              ),
              children: [
                _HeaderBlock(summary: summary),
                const SizedBox(height: 18),
                _BalanceCard(summary: summary),
                const SizedBox(height: 16),
                _Actions(summary: summary),
                const SizedBox(height: 28),
                AppSectionHeader(
                  title: 'Historique',
                  subtitle: operations.isEmpty
                      ? 'Aucune opération enregistrée'
                      : '${operations.length} opération'
                          '${operations.length > 1 ? 's' : ''} au total',
                ),
                const SizedBox(height: 12),
                _History(operations: operations, summary: summary),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderBlock extends StatelessWidget {
  const _HeaderBlock({required this.summary});

  final ClientSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final balance = summary.balance;

    final Color color;
    final Color background;
    if (summary.hasDebt) {
      color = AppColors.coral;
      background = AppColors.coralSoft;
    } else if (balance.deposit > 0) {
      color = AppColors.mintDark;
      background = AppColors.mintSoft;
    } else {
      color = AppColors.indigo;
      background = AppColors.indigoSoft;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClientAvatar(
          name: summary.client.fullName,
          size: 64,
          background: background,
          foreground: color,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                summary.client.fullName,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall?.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(
                    Icons.phone_outlined,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      summary.client.telephone,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AppStatusPill(
                label: summary.hasDebt
                    ? 'À crédit'
                    : balance.deposit > 0
                        ? 'Dépôt disponible'
                        : 'Compte à jour',
                color: color,
                background: background,
                icon: summary.hasDebt
                    ? Icons.schedule_rounded
                    : balance.deposit > 0
                        ? Icons.savings_outlined
                        : Icons.check_circle_outline_rounded,
                compact: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.summary});

  final ClientSummary summary;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final balance = summary.balance;

    final String label;
    final int amount;
    final Color accent;
    final String hint;
    if (summary.hasDebt) {
      label = 'Montant à recevoir';
      amount = balance.debt;
      accent = AppColors.coralBright;
      hint = 'Dette en cours sur ${summary.balance.openDebts.length} '
          'achat${summary.balance.openDebts.length > 1 ? 's' : ''}';
    } else if (balance.deposit > 0) {
      label = 'Dépôt disponible';
      amount = balance.deposit;
      accent = AppColors.mintBright;
      hint = 'Utilisable pour les prochains achats à crédit';
    } else {
      label = 'Situation du compte';
      amount = 0;
      accent = AppColors.indigoBright;
      hint = 'Aucune dette, aucun dépôt en attente';
    }

    return FaymaCard(
      gradient: AppGradients.ink,
      padding: const EdgeInsets.all(22),
      elevated: true,
      child: Stack(
        children: [
          Positioned(
            right: -52,
            bottom: -70,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accent.withValues(alpha: 0.2),
                    accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  AppStatusPill(
                    label: summary.hasDebt
                        ? 'À crédit'
                        : balance.deposit > 0
                            ? 'Dépôt'
                            : 'À jour',
                    color: accent,
                    background: Colors.white.withValues(alpha: 0.09),
                    compact: true,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatFcfa(amount),
                  style: textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 35,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hint,
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: 0.64),
                ),
              ),
              if (summary.hasDebt) ...[
                const SizedBox(height: 18),
                Text(
                  'Remboursé à ${(balance.repaidShare * 100).round()} %',
                  style: textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.68),
                  ),
                ),
                const SizedBox(height: 8),
                AppProgressBar(
                  value: balance.repaidShare,
                  color: AppColors.mintBright,
                  background: Colors.white.withValues(alpha: 0.13),
                  height: 7,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.summary});

  final ClientSummary summary;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _reminderBusy = false;

  ClientSummary get summary => widget.summary;

  Future<void> _sendReminder() async {
    if (_reminderBusy) return;
    setState(() => _reminderBusy = true);

    try {
      final sms = await prepareReminderSms(
        ref: ref,
        context: context,
        summary: summary,
      );
      await sms.send();
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  Future<void> _openRepayOrDeposit(BuildContext context) async {
    final id = summary.client.id;
    if (!summary.hasDebt) {
      context.push(AppRoutes.deposit(id));
      return;
    }

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final textTheme = Theme.of(sheetContext).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Encaisser', style: textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Choisissez comment enregistrer le paiement de '
                  '${summary.client.fullName}.',
                  style: textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                FaymaCard(
                  onTap: () => Navigator.of(sheetContext).pop('repayment'),
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      const _SheetIcon(
                        icon: Icons.payments_outlined,
                        color: AppColors.coral,
                        background: AppColors.coralSoft,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Remboursement',
                              style: textTheme.titleSmall,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Le client paie une partie ou la totalité de '
                              'sa dette.',
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
                const SizedBox(height: 10),
                FaymaCard(
                  onTap: () => Navigator.of(sheetContext).pop('deposit'),
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      const _SheetIcon(
                        icon: Icons.savings_outlined,
                        color: AppColors.mintDark,
                        background: AppColors.mintSoft,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Dépôt', style: textTheme.titleSmall),
                            const SizedBox(height: 2),
                            Text(
                              'Déduit d’abord la dette, le reste devient une '
                              'avance.',
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
              ],
            ),
          ),
        );
      },
    );

    if (choice == null || !context.mounted) return;
    context.push(
      choice == 'repayment' ? AppRoutes.repayment(id) : AppRoutes.deposit(id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.indigo,
            minimumSize: const Size.fromHeight(56),
            shape: buttonShape,
          ),
          onPressed: () => context.push(AppRoutes.purchase(summary.client.id)),
          icon: const Icon(Icons.shopping_bag_outlined, size: 20),
          label: const Text('Nouvel achat à crédit'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.mintDark,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(56),
            shape: buttonShape,
          ),
          onPressed: () => _openRepayOrDeposit(context),
          icon: const Icon(Icons.payments_outlined, size: 20),
          label: Text(
            summary.hasDebt ? 'Rembourser ou déposer' : 'Enregistrer un dépôt',
          ),
        ),
        if (summary.hasDebt) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.coral,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size.fromHeight(52),
              shape: buttonShape,
            ),
            onPressed: _reminderBusy ? null : _sendReminder,
            icon: _reminderBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined, size: 20),
            label: Text(
              _reminderBusy ? 'Préparation du rappel…' : 'Envoyer un rappel',
            ),
          ),
        ],
      ],
    );
  }
}

class _SheetIcon extends StatelessWidget {
  const _SheetIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}

/// Texte et couleur d'une ligne d'historique.
class _OperationView {
  const _OperationView({
    required this.label,
    required this.amountText,
    required this.color,
    required this.icon,
    required this.iconBackground,
  });

  final String label;
  final String amountText;
  final Color color;
  final IconData icon;
  final Color iconBackground;

  factory _OperationView.of(Operation op) {
    final String base;
    switch (op.type) {
      case OperationType.credit:
        base = 'Achat à crédit';
      case OperationType.repayment:
        base = 'Remboursement';
      case OperationType.deposit:
        base = 'Dépôt';
    }

    final int debtEffect;
    switch (op.type) {
      case OperationType.credit:
        debtEffect = op.sign;
      case OperationType.repayment:
        debtEffect = -op.sign;
      case OperationType.deposit:
        debtEffect = 0;
    }

    final String amountText;
    final Color color;
    if (op.type == OperationType.deposit) {
      amountText = formatSignedFcfa(op.sign * op.amount);
      color = op.sign > 0 ? AppColors.mintDark : AppColors.textSecondary;
    } else if (debtEffect > 0) {
      amountText = formatSignedFcfa(op.amount);
      color = AppColors.coral;
    } else {
      amountText = formatSignedFcfa(-op.amount);
      color = AppColors.mintDark;
    }

    final IconData icon;
    final Color iconBackground;
    if (op.isReversal) {
      icon = Icons.undo_rounded;
      iconBackground = AppColors.surfaceMuted;
    } else {
      switch (op.type) {
        case OperationType.credit:
          icon = Icons.shopping_bag_outlined;
          iconBackground = AppColors.indigoSoft;
        case OperationType.repayment:
          icon = Icons.check_rounded;
          iconBackground = AppColors.mintSoft;
        case OperationType.deposit:
          icon = Icons.savings_outlined;
          iconBackground = AppColors.mintSoft;
      }
    }

    return _OperationView(
      label: op.isReversal ? 'Annulation · $base' : base,
      amountText: amountText,
      color: color,
      icon: icon,
      iconBackground: iconBackground,
    );
  }
}

class _History extends ConsumerStatefulWidget {
  const _History({required this.operations, required this.summary});

  final List<Operation> operations;
  final ClientSummary summary;

  @override
  ConsumerState<_History> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<_History> {
  String? _busyOperationId;

  Future<void> _shareInvoice(
    BuildContext context,
    Operation operation,
    bool isCancelled,
  ) async {
    if (_busyOperationId != null) return;
    setState(() => _busyOperationId = operation.id);

    try {
      await ref.read(pdfExportServiceProvider).shareOperationInvoice(
            client: widget.summary.client,
            operation: operation,
            currentBalance: widget.summary.balance,
            isCancelled: isCancelled,
            sharePositionOrigin: sharePositionOriginFor(context),
          );
    } catch (error) {
      debugPrint('Génération de la facture PDF : $error');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Impossible de générer la facture PDF.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _busyOperationId = null);
    }
  }

  Future<void> _confirmReverse(
    BuildContext context,
    Operation operation,
  ) async {
    final view = _OperationView.of(operation);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Annuler cette opération ?'),
        content: Text(
          '${view.label} de ${formatFcfa(operation.amount)} '
          'du ${formatDate(operation.date)}.\n\n'
          'Elle reste visible dans l’historique, barrée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Garder'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Annuler l’opération',
              style: TextStyle(color: AppColors.coral),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(creditRepositoryProvider).reverseOperation(operation.id);
    } on StateError catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final operations = widget.operations;
    if (operations.isEmpty) {
      return const FaymaCard(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: AppEmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Aucune opération',
          message: 'Les achats, remboursements et dépôts de ce client '
              'apparaîtront ici.',
          color: AppColors.indigo,
          background: AppColors.indigoSoft,
        ),
      );
    }

    final reversedIds = {
      for (final operation in operations)
        if (operation.reversalOf != null) operation.reversalOf!,
    };

    // Plus récent en haut ; à date égale, la dernière enregistrée d'abord.
    final sortedOperations = sortOperationsByMostRecent(operations);

    return Column(
      children: [
        for (final operation in sortedOperations) ...[
          _HistoryRow(
            operation: operation,
            isCancelled: reversedIds.contains(operation.id),
            pdfBusy: _busyOperationId == operation.id,
            onPdf: () => _shareInvoice(
              context,
              operation,
              reversedIds.contains(operation.id),
            ),
            onLongPress:
                operation.isReversal || reversedIds.contains(operation.id)
                    ? null
                    : () => _confirmReverse(context, operation),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 2),
        const AppInfoBanner(
          icon: Icons.touch_app_outlined,
          message: 'Icône PDF pour partager une facture. Appui long sur une '
              'opération pour l’annuler.',
          color: AppColors.textSecondary,
          background: AppColors.surfaceMuted,
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.operation,
    required this.isCancelled,
    required this.pdfBusy,
    this.onPdf,
    this.onLongPress,
  });

  final Operation operation;
  final bool isCancelled;
  final bool pdfBusy;
  final VoidCallback? onPdf;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final view = _OperationView.of(operation);

    final detail = operation.items.isNotEmpty
        ? operation.items.map((item) => item.name).join(', ')
        : operation.note;
    final method = operation.paymentMethod;
    final dateLine = method == null
        ? formatDate(operation.date)
        : '${formatDate(operation.date)} · ${method.label}';

    final struck = isCancelled ? TextDecoration.lineThrough : null;
    final dimmed = isCancelled ? 0.52 : 1.0;

    return FaymaCard(
      onLongPress: onLongPress,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      color: isCancelled ? AppColors.surfaceMuted : AppColors.surface,
      child: Opacity(
        opacity: dimmed,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: view.iconBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              child: method != null && !operation.isReversal
                  ? Center(
                      child: PaymentMethodLogo(method: method, size: 28),
                    )
                  : Icon(view.icon, size: 19, color: view.color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          view.label,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            decoration: struck,
                          ),
                        ),
                      ),
                      if (isCancelled) ...[
                        const SizedBox(width: 6),
                        const AppStatusPill(
                          label: 'Annulé',
                          color: AppColors.textSecondary,
                          background: AppColors.surface,
                          compact: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateLine,
                    style: textTheme.bodySmall,
                  ),
                  if (detail != null && detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              view.amountText,
              style: textTheme.bodyMedium?.copyWith(
                color: view.color,
                fontWeight: FontWeight.w800,
                decoration: struck,
              ),
            ),
            const SizedBox(width: 2),
            if (pdfBusy)
              const SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                onPressed: onPdf,
                tooltip: 'Partager la facture PDF',
                style: IconButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  minimumSize: const Size(34, 34),
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
              ),
          ],
        ),
      ),
    );
  }
}
