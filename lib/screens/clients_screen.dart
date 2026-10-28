import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/client.dart';
import '../providers.dart';
import '../router/app_router.dart';
import '../theme/app_theme.dart';
import '../widgets/app_widgets.dart';

/// Écran 02 - Clients : répertoire, recherche et accès à la modification.
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Client> _filtered(List<Client> clients) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return clients;

    final queryDigits = query.replaceAll(RegExp(r'\D'), '');
    return [
      for (final client in clients)
        if (client.fullName.toLowerCase().contains(query) ||
            (queryDigits.isNotEmpty &&
                client.telephone
                    .replaceAll(RegExp(r'\D'), '')
                    .contains(queryDigits)))
          client,
    ];
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _reload() {
    ref.invalidate(clientsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final clientsAsync = ref.watch(clientsProvider);
    final hasClients = clientsAsync.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('Clients', style: textTheme.headlineSmall),
      ),
      floatingActionButton: hasClients
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.newClient),
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 22),
              label: const Text('Nouveau client'),
            )
          : null,
      body: SafeArea(
        child: clientsAsync.when(
          loading: () => const AppLoading(label: 'Chargement des clients…'),
          error: (error, _) => Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.pagePadding),
              child: FaymaCard(
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
            ),
          ),
          data: (allClients) {
            if (allClients.isEmpty) {
              return const _EmptyClients();
            }

            final clients = _filtered(allClients);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.pagePadding,
                4,
                AppTheme.pagePadding,
                104,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              children: [
                AppSectionHeader(
                  title: 'Tous les clients',
                  subtitle: '${allClients.length} '
                      'client${allClients.length > 1 ? 's' : ''} '
                      'enregistré${allClients.length > 1 ? 's' : ''}',
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
                  onChanged: (value) => setState(() => _query = value),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un client ou un numéro',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Effacer la recherche',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.close_rounded, size: 20),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                if (clients.isEmpty)
                  _NoResults(query: _query, onClear: _clearSearch)
                else ...[
                  for (final client in clients) ...[
                    _ClientRow(client: client),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 6),
                  const AppInfoBanner(
                    icon: Icons.edit_outlined,
                    message: 'Touchez une fiche pour voir l’historique, ou le '
                        'crayon pour modifier les coordonnées.',
                    color: AppColors.textSecondary,
                    background: AppColors.surfaceMuted,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FaymaCard(
      onTap: () => context.push(AppRoutes.client(client.id)),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Row(
        children: [
          ClientAvatar(name: client.fullName, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.fullName,
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
                        client.telephone,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () => context.push(AppRoutes.editClient(client.id)),
            tooltip: 'Modifier ${client.fullName}',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.indigo,
              backgroundColor: AppColors.indigoSoft,
              minimumSize: const Size(40, 40),
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class _EmptyClients extends StatelessWidget {
  const _EmptyClients();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.people_outline_rounded,
      title: 'Aucun client',
      message: 'Ajoutez votre premier client pour le retrouver ici et '
          'modifier ses coordonnées à tout moment.',
      primaryLabel: 'Ajouter un client',
      primaryIcon: Icons.person_add_alt_1_rounded,
      onPrimary: () => context.push(AppRoutes.newClient),
      secondaryLabel: 'Restaurer une sauvegarde',
      onSecondary: () => context.push(AppRoutes.backup),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return FaymaCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AppEmptyState(
        icon: Icons.search_off_rounded,
        title: 'Aucun client trouvé',
        message: 'Aucun nom ni numéro ne correspond à « ${query.trim()} ».',
        primaryLabel: 'Effacer la recherche',
        primaryIcon: Icons.restart_alt_rounded,
        onPrimary: onClear,
        color: AppColors.indigo,
        background: AppColors.indigoSoft,
      ),
    );
  }
}
