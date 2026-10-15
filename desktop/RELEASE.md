Logiciel de gestion de la bibliothèque et des fournitures de **Kivu International School**. Chaque personne a son compte et son mot de passe. Le logiciel fonctionne **sans internet** : les données restent sur l'ordinateur. Internet sert seulement à rechercher les fiches de livres.

Chaque fichier ci-dessous a été installé et lancé automatiquement sur un vrai Mac et un vrai PC Windows avant d'être publié.

## Quel fichier télécharger ?

| Ordinateur | Fichier |
|---|---|
| **Mac** (puce Apple M1/M2/M3/M4 ou Intel, macOS 11 ou plus récent) | `Kivutheque-…-mac-universal.dmg` |
| **Windows 10 / 11** (installation) | `Kivutheque-…-win-x64.exe` |
| **Windows**, sans installation (clé USB) | `Kivutheque-…-windows-portable.exe` |

## Installer sur Mac

1. Ouvrez le fichier `.dmg` et glissez **Kivuthèque** sur le dossier **Applications**.
2. Ouvrez **Kivuthèque** depuis le dossier Applications. macOS affiche « Apple n'a pas pu vérifier… » : cliquez sur **OK**.
3. Ouvrez **Réglages Système › Confidentialité et sécurité**, descendez en bas de la page, puis cliquez sur **Ouvrir quand même** et confirmez.
   Cette étape n'est demandée qu'une seule fois.

Si macOS indique que l'application est « endommagée », ouvrez l'application **Terminal**, collez la ligne ci-dessous, appuyez sur Entrée, puis relancez Kivuthèque :

```
xattr -cr /Applications/Kivutheque.app
```

## Installer sur Windows

1. Lancez `Kivutheque-…-win-x64.exe`.
2. Si Windows affiche « Windows a protégé votre ordinateur », cliquez sur **Informations complémentaires**, puis sur **Exécuter quand même**.
3. Suivez l'assistant. Une icône Kivuthèque est créée sur le bureau.

## Premier lancement : comptes et mots de passe

1. Au premier lancement, créez le compte **administrateur** : votre nom, un identifiant et un mot de passe.
2. Kivuthèque affiche un **code de secours** (par exemple `AB12-CD34-EF56`). **Notez-le sur papier** et rangez-le en lieu sûr : il permet de choisir un nouveau mot de passe administrateur en cas d'oubli.
3. Dans **Comptes**, créez un compte pour chaque personne :

| Rôle | Peut faire |
|---|---|
| **Administrateur** | Tout, y compris les comptes et les réglages |
| **Bibliothécaire** | Livres, membres, emprunts et retours |
| **Gestion des fournitures** | Articles et mouvements de stock |
| **Consultation** | Tout voir, sans rien modifier |

- Les mots de passe sont chiffrés et ne sont jamais visibles, même par l'administrateur. En cas d'oubli, l'administrateur en attribue un nouveau dans **Comptes**.
- Le logiciel vérifie le rôle de la personne connectée à chaque enregistrement.
- Kivuthèque se **verrouille** automatiquement après 15 minutes sans activité. L'administrateur peut changer ce délai dans **Réglages**. Le cadenas, en bas à gauche, verrouille immédiatement.
- Après 5 mots de passe faux, la connexion est bloquée 30 secondes.

## Ajouter un livre en quelques secondes

- **Scanner le code-barres** : dans **Livres**, cliquez sur **Scanner** et présentez le code-barres ISBN (au dos du livre) à la caméra.
  - Si le livre est déjà au catalogue, sa fiche s'ouvre.
  - Sinon, le formulaire d'ajout se remplit tout seul avec le titre, l'auteur, l'éditeur, l'année, la catégorie et la couverture.
  - Sur Mac, autorisez la caméra la première fois.
- **Douchette USB** (lecteur de code-barres, environ 20 $) : branchez-la et scannez, sans rien cliquer. Elle fonctionne aussi dans le formulaire d'emprunt, pour ajouter le livre prêté.
- **Recherche sur Internet** : dans le formulaire **Nouveau livre**, tapez un titre, un auteur ou un ISBN, puis cliquez sur **Utiliser**. Les fiches viennent de Google Livres et d'Open Library.
  - La couverture est enregistrée sur l'ordinateur et reste visible sans internet.
  - Seule la recherche a besoin d'internet : tout le reste fonctionne hors connexion.

## Vos données

Elles sont dans **Documents › Kivuthèque** :
- `donnees.json` contient toute la bibliothèque ;
- `comptes.json` contient les comptes. Les mots de passe y sont chiffrés ;
- `Sauvegardes automatiques` contient une copie par jour, pour les 30 derniers jours.

Pour changer d'ordinateur, copiez ce dossier au même endroit sur le nouvel ordinateur.

Made by Alexandre et Declaire
