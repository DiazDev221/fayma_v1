/// Normalise un code de récupération des anciennes sauvegardes.
///
/// Les nouvelles sauvegardes n'utilisent plus de code : ce fichier ne sert
/// qu'à ouvrir les fichiers `.fayma` créés avant cette simplification.
///
/// Les caractères souvent confondus sont corrigés (O -> 0, I/L -> 1) pour
/// pardonner une recopie manuelle approximative.
String normalizeLegacyRecoveryCode(String code) {
  return code
      .toUpperCase()
      .replaceAll(RegExp(r'[^0-9A-Z]'), '')
      .replaceAll('O', '0')
      .replaceAll('I', '1')
      .replaceAll('L', '1');
}
