import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// Enregistre un fichier à l'emplacement choisi par l'utilisateur dans le
/// gestionnaire de fichiers du téléphone ou de l'ordinateur.
///
/// Sur Android et iOS, l'utilisateur choisit le dossier (par exemple
/// « Fichiers » ou « Téléchargements ») dans le sélecteur natif. Sur
/// ordinateur, la boîte de dialogue d'enregistrement système s'ouvre.
class BackupFileSaver {
  const BackupFileSaver();

  /// Retourne `true` si le fichier a été enregistré, `false` si l'utilisateur
  /// a annulé.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final uri = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: mimeType,
      dialogTitle: 'Enregistrer la sauvegarde Fayma',
    );

    // Sur le Web, l'enregistrement déclenche un téléchargement et l'API ne
    // renvoie pas d'emplacement. Considérer le fichier comme enregistré.
    if (kIsWeb) return true;
    return uri != null;
  }
}
