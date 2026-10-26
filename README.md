# Mon Stock – application Android

Application de gestion de stock **hors ligne** (produits, mouvements, ventes, clients, fournisseurs, lots, entrepôts, commandes, rapports).
L'application Android est une enveloppe Flutter autour du fichier HTML `Mon_Stock_025.html` : tous les écrans et toutes les fonctions du HTML sont conservés à l'identique.

## Fichiers du dépôt

```
.github/workflows/build-apk.yml   construit l'APK automatiquement
lib/main.dart                     code Flutter (enveloppe de l'application)
pubspec.yaml                      dépendances
assets/index.html                 votre fichier Mon_Stock_025.html (renommé)
README.md                         ce fichier
```

## Construire l'APK

1. Ajoutez votre fichier `Mon_Stock_025.html` dans le dépôt, sous le nom **`assets/index.html`**.
   (Si vous le mettez à la racine du dépôt, le workflow le copie tout seul.)
2. Envoyez les fichiers sur GitHub (branche `main`) : la construction démarre.
   Vous pouvez aussi lancer **Actions → Construire l'APK Mon Stock → Run workflow**.
3. Quand la construction est terminée (✅ vert), ouvrez-la et téléchargez **Mon-Stock-APK** dans la zone *Artifacts*.
4. Décompressez le fichier, puis installez `app-release.apk` sur le téléphone (autoriser l'installation depuis cette source).

## Mettre à jour l'application

Remplacez `assets/index.html` par la nouvelle version du HTML : GitHub reconstruit l'APK.
Les données de l'appareil sont conservées si l'application est simplement mise à jour par-dessus l'ancienne.

## Ce qui fonctionne dans l'APK

- Données et comptes enregistrés sur l'appareil (stockage local), sans internet.
- Sauvegarde et exports CSV : le téléphone ouvre le menu **Partager** (Drive, WhatsApp, Fichiers…).
- Restauration d'une sauvegarde et choix de la photo de profil : sélecteur de fichiers du téléphone.
- Impression et PDF : factures, bons de commande, étiquettes et rapports passent par l'impression Android (« Enregistrer au format PDF » possible).
- Fenêtres de confirmation (suppressions, restauration…) affichées normalement.
- Bouton retour Android : retour arrière, puis demande de confirmation pour quitter.

## Limites connues

- Le scanner de codes-barres utilise la détection du navigateur. Si le téléphone ne la prend pas en charge, l'application demande de saisir le code à la main.
- Le mode « serveur de l'entreprise » (`/api`) ne fonctionne pas dans l'APK : il faudrait y indiquer l'adresse du serveur.
- Pensez à faire une sauvegarde régulière : si l'application est désinstallée, les données locales sont perdues.
- 
