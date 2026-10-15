Logiciel de gestion de la bibliothèque et des fournitures de **Kivu International School**. Il fonctionne **sans internet** : les données restent sur l'ordinateur.

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

## Vos données

Elles sont dans **Documents › Kivuthèque** :
- `donnees.json` contient toute la bibliothèque ;
- `Sauvegardes automatiques` contient une copie par jour, pour les 30 derniers jours.

Pour changer d'ordinateur, copiez ce dossier au même endroit sur le nouvel ordinateur.

Made by Alexandre et Declaire
