import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';
import '../router/app_router.dart';
import '../services/backup/backup_exception.dart';
import '../services/backup/backup_format.dart';
import '../services/backup/backup_service.dart';
import '../services/backup/legacy_recovery_code.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/share_origin.dart';
import '../widgets/app_widgets.dart';

/// Export et restauration manuels d'une sauvegarde chiffrée.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  DateTime? _lastBackup;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    DateTime? last;
    try {
      last = await ref.read(backupServiceProvider).lastBackupAt();
    } catch (error) {
      // La date n'est qu'une information : les actions restent disponibles
      // même si les préférences sont illisibles.
      debugPrint('Date de dernière sauvegarde : $error');
    }
    if (!mounted) return;
    setState(() => _lastBackup = last);
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(backupServiceProvider);
      final shareOrigin = sharePositionOriginFor(context);
      final export = await service.export();

      final result = await SharePlus.instance.share(
        ShareParams(
          title: 'Sauvegarde Fayma',
          subject: 'Sauvegarde Fayma',
          files: [
            XFile(export.file.path, mimeType: backupMimeType),
          ],
          sharePositionOrigin: shareOrigin,
        ),
      );

      if (result.status != ShareResultStatus.dismissed) {
        final now = DateTime.now();
        await service.markBackupDone(now);
        if (!mounted) return;
        setState(() => _lastBackup = now);
        _showMessage('Sauvegarde exportée.');
      }
    } on BackupException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Export de sauvegarde : $error');
      _showMessage('Impossible de créer la sauvegarde. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<BackupPreview> _inspectPicked(
    PlatformFile picked, {
    String? legacyRecoveryCode,
  }) async {
    final service = ref.read(backupServiceProvider);
    if (picked.path != null) {
      return service.inspectFile(
        File(picked.path!),
        legacyRecoveryCode: legacyRecoveryCode,
      );
    }
    final size = await picked.length();
    if (size != null && size > BackupService.maxBackupBytes) {
      throw const BackupException(
        'Ce fichier est trop volumineux pour être une sauvegarde Fayma.',
      );
    }
    return service.inspectBytes(
      await picked.readAsBytes(),
      sourceName: picked.name,
      legacyRecoveryCode: legacyRecoveryCode,
    );
  }

  Future<void> _import() async {
    if (_busy) return;

    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(type: FileType.any);
    } catch (error) {
      debugPrint('Sélection du fichier de sauvegarde : $error');
      _showMessage('Impossible d\'ouvrir le sélecteur de fichiers.');
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    BackupPreview? preview;
    String? legacyCode;
    try {
      // Les sauvegardes récentes s'ouvrent directement. Les anciens fichiers
      // peuvent demander une seule fois le code qui les accompagnait.
      while (preview == null) {
        try {
          preview = await _inspectPicked(
            picked,
            legacyRecoveryCode: legacyCode,
          );
        } on BackupException catch (error) {
          if (!error.legacyCodeRequired || !mounted) rethrow;
          setState(() => _busy = false);
          final code = await _askLegacyCode(
            error: error.wrongLegacyCode ? error.message : null,
          );
          if (code == null || !mounted) return;
          legacyCode = code;
          setState(() => _busy = true);
        }
      }
    } on BackupException catch (error) {
      _showMessage(error.message);
      return;
    } catch (error) {
      debugPrint('Lecture de la sauvegarde : $error');
      _showMessage('Impossible de lire cette sauvegarde.');
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    final ready = preview;
    if (!mounted) return;
    final confirmed = await _confirmRestore(ready);
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(backupServiceProvider).restore(ready);
      ref.invalidate(shopNameProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sauvegarde restaurée.')),
      );
      context.go(AppRoutes.home);
    } on BackupException catch (error) {
      _showMessage(error.message);
    } catch (error) {
      debugPrint('Restauration de la sauvegarde : $error');
      _showMessage(
        'La restauration a échoué. Vos données actuelles sont intactes.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _askLegacyCode({String? error}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _LegacyRecoveryCodeDialog(error: error),
    );
  }

  Future<bool?> _confirmRestore(BackupPreview preview) {
    final payload = preview.payload;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restaurer cette sauvegarde ?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FaymaCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Column(
                  children: [
                    AppKeyValueRow(
                      label: 'Fichier',
                      value: preview.sourceName,
                    ),
                    const Divider(),
                    AppKeyValueRow(
                      label: 'Date',
                      value: formatDate(payload.createdAt),
                    ),
                    if (payload.shopName.trim().isNotEmpty) ...[
                      const Divider(),
                      AppKeyValueRow(
                        label: 'Boutique',
                        value: payload.shopName.trim(),
                      ),
                    ],
                    const Divider(),
                    AppKeyValueRow(
                      label: 'Version',
                      value: payload.appVersion,
                    ),
                    const Divider(),
                    AppKeyValueRow(
                      label: 'Clients',
                      value: '${payload.clientCount}',
                    ),
                    const Divider(),
                    AppKeyValueRow(
                      label: 'Opérations',
                      value: '${payload.operationCount}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const AppInfoBanner(
                icon: Icons.warning_amber_rounded,
                message: 'Toutes les données actuelles de l’application '
                    'seront remplacées par celles de cette sauvegarde.',
                color: AppColors.coral,
                background: AppColors.coralSoft,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Restaurer',
              style: TextStyle(color: AppColors.coral),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final canAct = !_busy;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sauvegarde', style: textTheme.headlineSmall),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: ListView(
                key: const Key('backup-list'),
                padding: const EdgeInsets.fromLTRB(
                  AppTheme.pagePadding,
                  4,
                  AppTheme.pagePadding,
                  32,
                ),
                children: [
                  const AppInfoBanner(
                    icon: Icons.lock_outline_rounded,
                    title: 'Vos données restent privées',
                    message: 'La sauvegarde est chiffrée sur votre téléphone '
                        'avant d’être enregistrée. Les fichiers récents se '
                        'restaurent directement, sans code à saisir.',
                    color: AppColors.mintDark,
                    background: AppColors.mintSoft,
                  ),
                  const SizedBox(height: 26),
                  const AppSectionHeader(
                    title: 'Sauvegarder ou restaurer',
                    subtitle: 'Créez un fichier chiffré, puis partagez-le par '
                        'e-mail ou enregistrez-le sur un autre téléphone.',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: canAct ? _export : null,
                    icon: const Icon(Icons.ios_share_outlined, size: 20),
                    label: const Text('Exporter une sauvegarde'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: canAct ? _import : null,
                    icon: const Icon(Icons.restore_outlined, size: 20),
                    label: const Text('Restaurer une sauvegarde'),
                  ),
                  if (_lastBackup != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        'Dernière sauvegarde : ${formatDate(_lastBackup!)}',
                        style: textTheme.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_busy) const _BusyOverlay(),
          ],
        ),
      ),
    );
  }
}

/// Saisie du code des sauvegardes créées avant sa suppression.
///
/// Le dialogue n'apparaît que lorsqu'un fichier `.fayma` utilise l'ancien
/// chiffrement. Les nouvelles sauvegardes ne passent jamais par ici.
class _LegacyRecoveryCodeDialog extends StatefulWidget {
  const _LegacyRecoveryCodeDialog({this.error});

  /// Message affiché lorsque le code précédent ne correspondait pas.
  final String? error;

  @override
  State<_LegacyRecoveryCodeDialog> createState() =>
      _LegacyRecoveryCodeDialogState();
}

class _LegacyRecoveryCodeDialogState extends State<_LegacyRecoveryCodeDialog> {
  final _controller = TextEditingController();
  String? _message;
  String? _error;

  @override
  void initState() {
    super.initState();
    _message = widget.error;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = normalizeLegacyRecoveryCode(_controller.text);
    if (normalized.isEmpty) {
      setState(() => _error = 'Saisissez le code de récupération.');
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ancienne sauvegarde'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cette sauvegarde a été créée avant la suppression du code de '
              'récupération. Saisissez le code qui l’accompagnait.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_message != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.coral.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 17,
                      color: AppColors.coral,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        _message!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_message != null || _error != null) {
                  setState(() {
                    _message = null;
                    _error = null;
                  });
                }
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'ABCD-EFGH-JKMN-...',
                errorText: _error,
                prefixIcon: const Icon(Icons.key_outlined),
              ),
              style: const TextStyle(
                fontFamily: 'monospace',
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  const _BusyOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.28),
        child: const Center(
          child: FaymaCard(
            padding: EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Traitement en cours…'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
