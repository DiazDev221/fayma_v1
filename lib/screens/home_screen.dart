import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';
import '../router/app_router.dart';
import '../services/operation_sms.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/share_origin.dart';
import '../widgets/app_widgets.dart';

enum _ClientFilter { all, debt, deposit, clear }

/// Écran 01 - Accueil : total à recevoir et liste des clients.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _ClientFilter _filter = _ClientFilter.all;
  bool _reportBusy = false;
  String? _reminderClientId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportReport() async {
    if (_reportBusy) return;

    final clients = ref.read(clientsProvider).valueOrNull;
    final operations = ref.read(allOperationsProvider).valueOrNull;
    if (clients == null || operations == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les données sont encore en chargement.')),
      );
      return;
    }

    setState(() => _reportBusy = true);
    try {
      await ref.read(pdfExportServiceProvider).shareGeneralReport(
            clients: clients,
            operations: operations,
            sharePositionOrigin: sharePositionOriginFor(context),
          );
    } catch (error) {
      debugPrint('Génération du rapport PDF : $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Impossible de générer le rapport PDF.'),
          ),
        );
    } finally {
      if (mounted) setState(() => _reportBusy = false);
    }
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _filter = _ClientFilter.all;
    });
  }

  Future<void> _sendReminder(ClientSummary summary) async {
    if (_reminderClientId != null) return;
    setState(() => _reminderClientId = summary.client.id);

    try {
      final sms = await prepareReminderSms(
        ref: ref,
        context: context,
        summary: summary,
      );
      await sms.send();
    } finally {
      if (mounted) setState(() => _reminderClientId = null);
    }
  }

  void _reload() {
    ref.invalidate(clientsProvider);
    ref.invalidate(allOperationsProvider);
  }

  List<ClientSummary> _filtered(List<ClientSummary> clients) {
    final query = _query.trim().toLowerCase();
    final queryDigits = query.replaceAll(RegExp(r'\D'), '');
    return [
      for (final summary in clients)
        if (_matchesFilter(summary) &&
            (query.isEmpty ||
                summary.client.fullName.toLowerCase().contains(query) ||
                (queryDigits.isNotEmpty &&
                    summary.client.telephone
                        .replaceAll(RegExp(r'\D'), '')
                        .contains(queryDigits))))
          summary,
    ];
  }

  bool _matchesFilter(ClientSummary summary) {
    return switch (_filter) {
      _ClientFilter.all => true,
      _ClientFilter.debt => summary.hasDebt,
      _ClientFilter.deposit => summary.balance.deposit > 0,
      _ClientFilter.clear => !summary.hasDebt && summary.balance.deposit == 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    final summariesAsync = ref.watch(clientSummariesProvider);
    final totals = ref.watch(shopTotalsProvider).value;
    final shopName = ref.watch(shopNameProvider).valueOrNull ?? '';
    final allClients = summariesAsync.valueOrNull ?? const <ClientSummary>[];
    final clients = _filtered(allClients);
    final hasClients = allClients.isNotEmpty;

    return Scaffold(
      floatingActionButton: hasClients
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.newClient),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Nouveau client'),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Seul l'en-tête reste fixe ; tout le reste de l'accueil défile.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                14,
                AppTheme.pagePadding,
                0,
              ),
              child: _Header(shopName: shopName),
            ),
            Expanded(
              child: ListView(
                key: const Key('home-scroll'),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  22,
                  AppTheme.pagePadding,
                  104,
                ),
                children: [
                  _HeroCard(
                    totalDue: totals?.totalDue ?? 0,
                    totalDeposits: totals?.totalDeposits ?? 0,
                    clientsWithDebt: totals?.clientsWithDebt ?? 0,
                    dueShare: totals?.dueShare ?? 0,
                    clientCount: allClients.length,
                  ),
                  const SizedBox(height: 14),
                  _ReportCard(
                    busy: _reportBusy,
                    onTap: _exportReport,
                  ),
                  const SizedBox(height: 26),
                  summariesAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 44),
                      child: AppLoading(label: 'Chargement des clients…'),
                    ),
                    error: (error, _) => FaymaCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                      child: AppEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Impossible de charger les clients',
                        message: 'Vérifiez que les données sont accessibles, '
                            'puis réessayez.',
                        primaryLabel: 'Réessayer',
                        primaryIcon: Icons.refresh_rounded,
                        onPrimary: _reload,
                        color: AppColors.coral,
                        background: AppColors.coralSoft,
                      ),
                    ),
                    data: (_) {
                      if (!hasClients) {
                        return const _EmptyClients();
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppSectionHeader(
                            title: 'Clients',
                            subtitle: '${allClients.length} '
                                'client${allClients.length > 1 ? 's' : ''} au total',
                            trailing: AppStatusPill(
                              label: '${clients.length} affiché'
                                  '${clients.length > 1 ? 's' : ''}',
                              color: AppColors.textSecondary,
                              background: AppColors.surface,
                              icon: Icons.people_alt_outlined,
                              compact: true,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _searchController,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Rechercher un client ou un numéro',
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _query.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: 'Effacer la recherche',
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _query = '');
                                      },
                                      icon: const Icon(Icons.close_rounded,
                                          size: 20),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 38,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              children: [
                                _FilterChip(
                                  label: 'Tous',
                                  selected: _filter == _ClientFilter.all,
                                  onSelected: () => setState(
                                    () => _filter = _ClientFilter.all,
                                  ),
                                ),
                                _FilterChip(
                                  label: 'À crédit',
                                  selected: _filter == _ClientFilter.debt,
                                  onSelected: () => setState(
                                    () => _filter = _ClientFilter.debt,
                                  ),
                                ),
                                _FilterChip(
                                  label: 'Dépôt',
                                  selected: _filter == _ClientFilter.deposit,
                                  onSelected: () => setState(
                                    () => _filter = _ClientFilter.deposit,
                                  ),
                                ),
                                _FilterChip(
                                  label: 'À jour',
                                  selected: _filter == _ClientFilter.clear,
                                  onSelected: () => setState(
                                    () => _filter = _ClientFilter.clear,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (clients.isEmpty)
                            _NoResults(onClear: _clearFilters)
                          else
                            for (final summary in clients) ...[
                              _ClientCard(
                                summary: summary,
                                onTap: () => context.push(
                                  AppRoutes.client(summary.client.id),
                                ),
                                onRemind: summary.hasDebt
                                    ? () => _sendReminder(summary)
                                    : null,
                                reminderBusy:
                                    _reminderClientId == summary.client.id,
                              ),
                              const SizedBox(height: 12),
                            ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FaymaCard(
      onTap: busy ? null : onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.indigoSoft,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              color: AppColors.indigo,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rapport général PDF',
                  style: textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  'Toutes les dettes, dépôts et opérations de la boutique.',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            )
          else
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.shopName});

  final String shopName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = shopName.trim().isEmpty ? 'Fayma' : shopName.trim();
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: AppGradients.hero,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: AppColors.mint.withValues(alpha: 0.18),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'F',
              style: TextStyle(
                color: AppColors.mintBright,
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineSmall,
              ),
              const SizedBox(height: 1),
              Text(
                shopName.trim().isEmpty
                    ? 'Ajoutez le nom de votre boutique'
                    : 'Votre boutique, en un coup d’œil',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => context.push(AppRoutes.settings),
          tooltip: 'Paramètres',
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(42, 42),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totalDue,
    required this.totalDeposits,
    required this.clientsWithDebt,
    required this.dueShare,
    required this.clientCount,
  });

  final int totalDue;
  final int totalDeposits;
  final int clientsWithDebt;
  final double dueShare;
  final int clientCount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final hasDebt = totalDue > 0;
    final recovered = hasDebt ? (1 - dueShare).clamp(0.0, 1.0) : 1.0;
    final progressLabel =
        hasDebt ? '${(recovered * 100).round()} % encaissé' : 'Tout est à jour';

    return FaymaCard(
      gradient: AppGradients.hero,
      padding: const EdgeInsets.all(22),
      elevated: true,
      child: Stack(
        children: [
          Positioned(
            right: -38,
            top: -54,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.mintBright.withValues(alpha: 0.28),
                    AppColors.mintBright.withValues(alpha: 0),
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
                      'Total à recevoir',
                      style: textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_outlined,
                      color: AppColors.mintBright,
                      size: 19,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  formatFcfa(totalDue),
                  style: textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 36,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _HeroDepositLine(totalDeposits: totalDeposits),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          progressLabel,
                          style: textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AppProgressBar(
                          value: recovered,
                          color: AppColors.mintBright,
                          background: Colors.white.withValues(alpha: 0.14),
                          height: 7,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 18),
                  Container(
                    width: 1,
                    height: 42,
                    color: Colors.white.withValues(alpha: 0.16),
                  ),
                  const SizedBox(width: 18),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$clientsWithDebt',
                        style: textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontSize: 22,
                        ),
                      ),
                      Text(
                        'à crédit',
                        style: textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _HeroPill(
                    icon: Icons.people_alt_outlined,
                    label: '$clientCount client${clientCount > 1 ? 's' : ''}',
                  ),
                  const SizedBox(width: 8),
                  _HeroPill(
                    icon: clientsWithDebt == 0
                        ? Icons.check_circle_outline_rounded
                        : Icons.schedule_rounded,
                    label: clientsWithDebt == 0
                        ? 'Aucune dette'
                        : '$clientsWithDebt à relancer',
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroDepositLine extends StatelessWidget {
  const _HeroDepositLine({required this.totalDeposits});

  final int totalDeposits;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.savings_outlined,
            size: 16,
            color: AppColors.mintBright,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Dépôts disponibles',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                formatFcfa(totalDeposits),
                key: const Key('home-total-deposits'),
                style: textTheme.titleSmall?.copyWith(
                  color: AppColors.mintBright,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.mintBright),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.82),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: selected ? AppColors.mintDark : AppColors.textSecondary,
            ),
      ),
    );
  }
}

class _ClientCard extends StatelessWidget {
  const _ClientCard({
    required this.summary,
    required this.onTap,
    this.onRemind,
    this.reminderBusy = false,
  });

  final ClientSummary summary;
  final VoidCallback onTap;
  final VoidCallback? onRemind;
  final bool reminderBusy;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final balance = summary.balance;

    final String amountText;
    final Color amountColor;
    final String statusLabel;
    final Color statusColor;
    final Color statusBackground;

    if (summary.hasDebt) {
      amountText = formatFcfa(balance.debt);
      amountColor = AppColors.coral;
      statusLabel = 'À crédit';
      statusColor = AppColors.coral;
      statusBackground = AppColors.coralSoft;
    } else if (balance.deposit > 0) {
      amountText = formatFcfa(balance.deposit);
      amountColor = AppColors.mintDark;
      statusLabel = 'Dépôt';
      statusColor = AppColors.mintDark;
      statusBackground = AppColors.mintSoft;
    } else {
      amountText = formatFcfa(0);
      amountColor = AppColors.textSecondary;
      statusLabel = 'À jour';
      statusColor = AppColors.textSecondary;
      statusBackground = AppColors.surfaceMuted;
    }

    return FaymaCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      child: Column(
        children: [
          Row(
            children: [
              ClientAvatar(name: summary.client.fullName, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.client.fullName,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.phone_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            summary.client.telephone,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountText,
                    style: textTheme.titleSmall?.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: amountColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  AppStatusPill(
                    label: statusLabel,
                    color: statusColor,
                    background: statusBackground,
                    compact: true,
                  ),
                ],
              ),
            ],
          ),
          if (summary.hasDebt) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AppProgressBar(
                    value: balance.repaidShare,
                    color: AppColors.mint,
                    background: AppColors.coralSoft,
                    height: 6,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(balance.repaidShare * 100).round()} % remboursé',
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 2),
                _ReminderIconButton(
                  busy: reminderBusy,
                  onPressed: onRemind,
                ),
              ],
            ),
          ] else if (balance.deposit > 0) ...[
            const SizedBox(height: 11),
            Row(
              children: [
                const Icon(
                  Icons.savings_outlined,
                  size: 14,
                  color: AppColors.mintDark,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Avance pour les prochains achats',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.mintDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ReminderIconButton extends StatelessWidget {
  const _ReminderIconButton({required this.busy, this.onPressed});

  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: busy ? null : onPressed,
      tooltip: 'Envoyer un rappel',
      style: IconButton.styleFrom(
        foregroundColor: AppColors.coral,
        minimumSize: const Size(34, 34),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
        ),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.notifications_active_outlined, size: 18),
    );
  }
}

class _EmptyClients extends StatelessWidget {
  const _EmptyClients();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.storefront_outlined,
      title: 'Votre boutique est prête',
      message: 'Ajoutez votre premier client pour suivre les crédits, '
          'les remboursements et les dépôts.',
      primaryLabel: 'Ajouter un client',
      primaryIcon: Icons.person_add_alt_1_rounded,
      onPrimary: () => context.push(AppRoutes.newClient),
      secondaryLabel: 'Restaurer une sauvegarde',
      onSecondary: () => context.push(AppRoutes.backup),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.search_off_rounded,
      title: 'Aucun résultat',
      message: 'Aucun client ne correspond à votre recherche ou au filtre '
          'sélectionné.',
      primaryLabel: 'Effacer les filtres',
      primaryIcon: Icons.restart_alt_rounded,
      onPrimary: onClear,
      color: AppColors.indigo,
      background: AppColors.indigoSoft,
    );
  }
}
