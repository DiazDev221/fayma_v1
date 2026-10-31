# Fayma

Gestion du crédit pour les boutiques de quartier, pensée pour fonctionner hors
connexion (montants en FCFA, interface en français).

## Développement

```bash
flutter pub get
flutter run
flutter test
```

L'application cible Android (API 24 minimum) et iOS (15 minimum). La base
SQLite est stockée dans le dossier privé de l'application (`fayma.db`).

## Version iOS

La compilation iOS se fait obligatoirement sur macOS avec Xcode. Le projet
utilise Swift Package Manager : aucun `pod install` n'est nécessaire.

1. Ouvrir le projet dans Xcode et choisir l'équipe de signature :

   ```bash
   open ios/Runner.xcworkspace
   ```

   Dans la cible **Runner** → **Signing & Capabilities**, sélectionner une
   équipe. Le bundle identifier est déjà `com.fayma.app` ; s'il est changé, il
   doit l'être partout dans le projet avant toute publication.

2. Lancer l'application sur un iPhone simulé ou réel :

   ```bash
   flutter run -d iphone
   ```

3. Construire l'IPA signé pour TestFlight ou l'App Store :

   ```bash
   tool/build_ipa.sh
   ```

   Le fichier est écrit dans `build/ios/ipa/`. Pour un simple contrôle de
   compilation sans signature : `flutter build ios --release --no-codesign`.

Spécificités iOS :

- l'import d'un contact demande l'autorisation **Contacts** (la description
  est dans `ios/Runner/Info.plist`) ;
- l'envoi d'un SMS ouvre l'application Messages avec le message pré-rempli ;
  le commerçant appuie ensuite sur « Envoyer » ;
- les factures et rapports passent par la feuille de partage iOS (Fichiers,
  Mail, WhatsApp, impression, etc.) ; les sauvegardes peuvent être
  enregistrées directement dans Fichiers ou partagées ;
- l'icône est générée depuis `assets/icon/fayma_icon_ios.png`, sans canal
  alpha, comme l'exige l'App Store.

Lors du premier envoi à App Store Connect, Apple pose une question sur le
chiffrement : Fayma chiffre uniquement ses sauvegardes locales (Argon2id +
AES-GCM) et n'utilise aucun serveur. Vérifiez la déclaration d'exportation
applicable avant de valider l'envoi.

## Créer un APK release léger

L'APK par défaut embarque les trois architectures (arm64-v8a, armeabi-v7a,
x86_64) et pèse environ 64 Mo. Pour obtenir un fichier par architecture
(~22 Mo pour les téléphones récents) :

```bash
tool/build_apk.sh
```

Le script produit des APK obfusqués dans `build/app/outputs/flutter-apk/` :

- `app-arm64-v8a-release.apk` : téléphones récents, à distribuer en priorité ;
- `app-armeabi-v7a-release.apk` : téléphones plus anciens ;
- `app-x86_64-release.apk` : émulateurs uniquement.

Les symboles de crash sont écrits dans `build/symbols/` : les conserver pour
pouvoir décoder les stack traces. Pour le Play Store, préférer
`flutter build appbundle --release`, qui ne livre à chaque appareil que
l'architecture nécessaire.

### Signature de release Android

Les APK release sont signés avec le keystore
`android/app/upload-keystore.jks`. L'alias et les mots de passe sont dans
`android/key.properties`. Ces deux fichiers sont ignorés par Git et doivent
être **sauvegardés ensemble, hors du dépôt** : sans eux, il devient impossible
de signer une mise à jour avec la même clé.

L'application utilise l'identifiant `com.fayma.app` sur Android et iOS. Il peut
encore être changé avant la première publication, mais il doit alors être
modifié partout dans le projet (Android et iOS) avant de générer les APK.

L'ancienne version de développement utilisait `com.example.fayma` : Android la
considère comme une application différente. Pour récupérer ses données,
exportez une sauvegarde `.fayma` depuis l'ancienne version, puis restaurez-la
dans la nouvelle. Si le fichier a été créé avec l'ancien code de récupération,
Fayma le demande une seule fois lors de la restauration. Les deux versions
peuvent coexister pendant la migration.

Pour distribuer sur le Play Store, conservez aussi le keystore chez un
prestataire sûr ou dans un gestionnaire de secrets. Ne le versionnez jamais.

## Factures et rapport PDF

Les documents sont générés hors connexion, directement dans l'application.

- Sur la fiche d'un client, l'icône PDF de chaque opération crée une **facture
  d'achat à crédit** ou un **reçu de dépôt / remboursement**, puis ouvre la
  feuille de partage du téléphone (WhatsApp, e-mail, impression, etc.).
- Depuis l'accueil, **Rapport général PDF** produit un document complet :
  synthèse de la boutique, situation de chaque client et journal des
  opérations. Les opérations annulées restent visibles pour l'historique.

## Rappel de crédit par SMS

Sur la fiche d'un client endetté, le bouton **Envoyer un rappel** (ou la
cloche sur sa carte à l'accueil) ouvre l'application SMS avec un message
prérempli indiquant le reste à payer et la date de la dette la plus ancienne.
Le commerçant garde la main sur l'envoi : rien ne part sans son accord, et le
rappel n'apparaît pas dans l'historique des opérations.

## Nom de la boutique et SMS

- Le nom saisi dans **Paramètres** apparaît en signature des SMS envoyés après
  chaque achat, remboursement ou dépôt.
- Les achats à crédit ne sont pas plafonnés : le commerçant peut enregistrer
  autant d'opérations que nécessaire.

## Moyens de paiement

Chaque **dépôt** et chaque **remboursement** indique le moyen utilisé par le
client :

- **Espèces** — billets et pièces remis à la boutique ;
- **Orange Money** — paiement reçu sur le compte Orange Money de la boutique ;
- **Wave** — paiement reçu sur le compte Wave de la boutique.

Le sélecteur apparaît dans les écrans **Nouveau dépôt** et **Remboursement**,
avec les logos Orange Money et Wave embarqués dans l'application (aucune
connexion nécessaire). **Espèces** est sélectionné par défaut ; touchez une
tuile pour changer de moyen avant d'enregistrer.

Le moyen choisi est ensuite visible :

- dans l'historique de la fiche client, à côté de la date, avec le logo
  correspondant ;
- sur les reçus PDF de dépôt et de remboursement ;
- dans le journal du **Rapport général PDF**.

Un achat à crédit n'a pas de moyen de paiement. Les opérations enregistrées
avant cette version restent affichées normalement, simplement sans moyen
précisé. La base SQLite passe automatiquement en version 2 au premier
lancement : aucune action n'est demandée et aucune donnée n'est perdue.

## Sauvegarde chiffrée

Depuis **Paramètres**, la tuile **Sauvegarde** ouvre l'écran dédié.

- **Enregistrer la sauvegarde** crée un fichier `.fayma` chiffré avec
  Argon2id + AES-256-GCM, puis ouvre le gestionnaire de fichiers du téléphone
  pour choisir le dossier de destination (Fichiers, Téléchargements, carte SD,
  etc.). Aucun code n'est à retenir : la clé est interne à l'application.
- **Partager la sauvegarde** crée le même fichier et ouvre la feuille de
  partage (e-mail, messagerie, etc.) pour l'envoyer directement.
- La sauvegarde contient **toutes les données de la boutique** : clients,
  opérations (lignes d'achat, notes, annulations et moyen de paiement des
  dépôts et remboursements) et **nom de la boutique**. Ce nom est restauré en
  même temps que les données ; s'il est vide dans une ancienne sauvegarde, le
  nom déjà saisi sur le téléphone est conservé.
- **Restaurer une sauvegarde** vérifie le fichier, puis remplace toutes les
  données dans une transaction SQLite. En cas d'erreur, les données existantes
  restent intactes. Les sauvegardes récentes se restaurent sans code.
- Les sauvegardes créées avant cette version utilisaient un **code de
  récupération**. Elles restent restaurables : Fayma demande alors ce code une
  seule fois. Sans ce code, ces anciens fichiers restent illisibles.
- Le chiffrement protège le fichier d'une lecture accidentelle. La clé étant
  embarquée dans l'application, cette protection ne remplace pas un mot de
  passe contre une personne qui dispose de Fayma et du fichier.
- Le format de données reste compatible avec les fichiers antérieurs : le nom
  de boutique et le moyen de paiement, absents de ces fichiers, ne sont pas
  inventés. L'ancien plafond de crédit par client, encore présent, est ignoré.
  La version du format reste la 1 pour préserver cette compatibilité.

La sauvegarde automatique Android est désactivée (`android:allowBackup="false"`)
pour éviter des copies non maîtrisées. Seuls les exports chiffrés explicites
servent à restaurer l'application après une désinstallation ou sur un nouveau
téléphone. Sur iOS, les données restent incluses dans la sauvegarde iCloud de
l'iPhone si l'utilisateur l'a activée ; l'export `.fayma` reste la seule
sauvegarde portable vers un autre appareil.
