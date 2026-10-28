/// Erreur lisible par l'utilisateur pendant une sauvegarde ou une restauration.
///
/// Les détails techniques restent dans [cause] pour les journaux de débogage.
class BackupException implements Exception {
  const BackupException(
    this.message, {
    this.cause,
    this.legacyCodeRequired = false,
    this.wrongLegacyCode = false,
  });

  final String message;
  final Object? cause;

  /// Vrai lorsque le fichier a été créé avec l'ancien code de récupération.
  ///
  /// Les nouvelles sauvegardes n'ont plus de code. L'écran de restauration
  /// demande donc ce code uniquement pour les anciens fichiers `.fayma`.
  final bool legacyCodeRequired;

  /// Vrai lorsque le code fourni pour une ancienne sauvegarde ne correspond
  /// pas au fichier (ou que celui-ci est endommagé).
  final bool wrongLegacyCode;

  @override
  String toString() => message;
}
