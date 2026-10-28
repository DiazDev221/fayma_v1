import 'package:flutter/foundation.dart';

/// Client d'une boutique. Les montants sont en FCFA, sans décimales.
///
/// Le solde (dette, dépôt) n'est pas stocké ici : il se calcule à partir
/// des opérations du client, pour ne jamais perdre l'historique.
@immutable
class Client {
  const Client({
    required this.id,
    required this.nom,
    required this.prenom,
    required this.telephone,
    required this.createdAt,
  });

  final String id;
  final String nom;
  final String prenom;
  final String telephone;
  final DateTime createdAt;

  /// Ex : "Moussa Diop".
  String get fullName => '$prenom $nom'.trim();

  /// Ex : "MD", pour l'avatar.
  String get initials {
    final p = prenom.trim();
    final n = nom.trim();
    final first = p.isNotEmpty ? p[0] : '';
    final second = n.isNotEmpty ? n[0] : '';
    return (first + second).toUpperCase();
  }

  Client copyWith({
    String? nom,
    String? prenom,
    String? telephone,
  }) {
    return Client(
      id: id,
      nom: nom ?? this.nom,
      prenom: prenom ?? this.prenom,
      telephone: telephone ?? this.telephone,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Client &&
      other.id == id &&
      other.nom == nom &&
      other.prenom == prenom &&
      other.telephone == telephone &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, nom, prenom, telephone, createdAt);
}
