# Bibliothèque KIS — logiciel de bureau

Version installable de l'application, pour Mac et Windows. Elle fonctionne **sans internet**.

## Installer

**Windows** : lancez `Bibliotheque-KIS-1.0.0-win-x64.exe` et suivez l'assistant.
Windows affiche « Windows a protégé votre ordinateur » (le logiciel n'est pas signé) :
cliquez sur **Informations complémentaires**, puis **Exécuter quand même**.
`Bibliotheque-KIS-1.0.0-portable.exe` se lance sans installation (clé USB, par exemple).

**Mac** : ouvrez le fichier `.zip` (Mac à puce Apple M1/M2/M3/M4 : `mac-arm64` ; ancien Mac Intel : `mac-x64`),
glissez **Bibliothèque KIS** dans le dossier **Applications**.
Au premier lancement, macOS indique que le développeur ne peut pas être vérifié :
ouvrez **Réglages Système › Confidentialité et sécurité**, puis cliquez sur **Ouvrir quand même**
(sur les versions plus anciennes : clic droit sur l'application › **Ouvrir**).

## Où sont les données ?

Dans **Documents › Bibliothèque KIS** :
- `donnees.json` : toutes les données de la bibliothèque ;
- `Sauvegardes automatiques` : une copie par jour, les 30 derniers jours.

Pour changer d'ordinateur, copiez ce dossier sur le nouvel ordinateur au même endroit.

## Refaire les installateurs

```bash
python3 app/build.py          # génère desktop/index.html et l'icône
cd desktop && npm install
npm run dist:win              # Windows (sous Linux, nécessite wine)
npm run dist:mac              # Mac (sur un Mac)
```
L'action GitHub « Logiciel de bureau » fabrique aussi les installateurs Mac (.dmg) et Windows (.exe) à chaque modification.

Made by Alexandre Declaire
