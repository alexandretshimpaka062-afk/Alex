# Kivuthèque — cahier des charges de la version web

Version en ligne (Supabase + Netlify) de la bibliothèque de Kivu International School.
Ce document rassemble les décisions prises avec l'école. On avance étape par étape : chaque étape est montrée et validée avant la suivante.

## Rôles

| Rôle | Ce qu'il voit et fait | Qui l'attribue |
|---|---|---|
| **Administrateur** | Tout, y compris les comptes et les réglages | Administrateur |
| **Bibliothécaire** | Livres, membres, emprunts, retours, réservations, rappels, défis. Vue globale de la bibliothèque | Administrateur |
| **Gestionnaire des fournitures** | Articles, mouvements de stock, bons de commande | Administrateur |
| **Direction** | Tout voir (tableaux de bord, rapports, stock), sans rien modifier | Administrateur |
| **Enseignant** | Son espace de lecteur, plus le suivi de ses classes | Administrateur ou bibliothécaire |
| **Élève** | Uniquement son espace personnel | Administrateur ou bibliothécaire |
| **Borne / catalogue public** | Sans compte : catalogue et disponibilité, aucun nom d'élève | — |

La règle « la bibliothécaire n'attribue que les rôles élève et enseignant » est appliquée par la base de données elle-même, pas seulement par l'interface.

## Comptes

- Inscription avec une adresse Gmail et un mot de passe, ou avec le bouton **« Continuer avec Google »**.
- Lors de l'inscription, la personne indique son nom, son profil (élève, enseignant, personnel) et sa classe.
- Chaque nouvelle inscription arrive dans une **liste d'attente**. L'administrateur ou la bibliothécaire l'accepte en la reliant à une fiche de membre (existante ou nouvelle), ou la refuse.
- Mot de passe oublié : lien envoyé par e-mail.
- **Photo de profil** pour chacun, recadrée en cercle et réduite automatiquement. Sans photo, ce sont les initiales qui s'affichent. L'administrateur et la bibliothécaire peuvent retirer une photo inappropriée. La photo n'apparaît jamais sur la borne publique.

## Fonctionnalités

1. **Carte de membre numérique** dans l'espace personnel, avec un numéro du type **A001** (A001 → A999, puis B001…). Ce numéro sert à la recherche et aux emprunts. Pas d'impression pour l'instant.
2. **Rappels de retard** : message WhatsApp ou SMS prêt à envoyer aux parents, lettre PDF par classe, point d'accès pour un agent N8N. Le téléphone du parent est ajouté à la fiche membre.
3. **Réservations** : file d'attente quand tous les exemplaires sont sortis, alerte au retour, livre gardé 3 jours.
4. **Défis de lecture** : badges, classement des élèves dans leur classe et dans toute l'école, classement des classes, objectifs, diplôme PDF de fin de trimestre. Les noms s'affichent sous la forme « Prénom N. ». Seuls les livres rendus comptent.
5. **Recommandations** : « les élèves qui ont lu ce livre ont aussi lu… », genres préférés, notes de 1 à 5 étoiles, livres du mois, lectures conseillées par les enseignants.
6. **Bon de commande PDF** par fournisseur, pour les articles sous le seuil.
7. **État des livres** au retour (bon, abîmé, perdu), avec une amende ou le prix de remplacement. Le prix est ajouté à la fiche livre.
8. **Borne publique** : catalogue en plein écran, recherche tactile, disponibilité et rayon, retour automatique à l'accueil.
9. **Espace élève**, à la manière de Netflix : livres en cours avec compte à rebours, « Pour toi », livres du mois, réservations, badges, historique, liste « à lire plus tard », carte de membre.
10. **Espace enseignant** : classes attribuées par l'administrateur ; élèves, lectures et retards de ses classes ; objectifs ; lectures recommandées ; diplômes.

## Catalogue et couvertures (ajouté)

- **Ajouter depuis Internet** (page Livres) : recherche par titre, auteur ou ISBN dans Google Livres et Open Library. Un clic ajoute le livre avec sa couverture, la catégorie devinée et le nombre d'exemplaires. Si le livre existe déjà, on propose d'ajouter des exemplaires.
- **Couvertures du catalogue** : synchronisation de tout le catalogue. Avec un ISBN, la couverture est trouvée automatiquement ; sans ISBN, la bibliothécaire valide chaque couverture proposée. Elle peut aussi envoyer une photo.
- **Changer la couverture** sur la fiche d'un livre : choisir parmi les propositions, envoyer une photo ou retirer la couverture.
- **Copie durable** : chaque couverture est copiée, réduite (environ 6 à 15 Ko), dans le stockage Supabase « couvertures ». Elle ne dépend plus de Google ni d'Open Library.

## Sécurité

- Un élève ne lit que sa fiche, ses emprunts et ses réservations.
- Un enseignant lit aussi les élèves de ses classes.
- La borne ne voit que le catalogue et le nombre d'exemplaires disponibles.

## Étapes

1. ✅ Sécurité de la base, nouveaux rôles, inscription avec liste d'attente, bouton Google, numéros A001, carte de membre numérique, photo de profil.
2. ✅ Espace élève, réservations.
   - Espace façon Netflix : alertes (« ton livre t'attend », retards), livre du mois en grand, carte de membre, rangées (en cours avec compte à rebours, mes réservations, livres du mois, « Pour toi » selon les genres préférés, les plus lus à l'école, nouveautés, ma liste, déjà lus).
   - Choix des genres préférés à la première visite ; liste « à lire plus tard ».
   - Réservation d'un livre dont tous les exemplaires sont sortis ; 3 au maximum ; rang dans la file.
   - Au retour du livre, la bibliothécaire est alertée et le met de côté (3 jours) ; l'élève est prévenu ; « Prêter » termine la réservation ; un délai dépassé libère l'exemplaire.
   - La bibliothécaire choisit les « livres du mois » depuis la fiche d'un livre.
3. Défis, classements, recommandations.
4. Espace enseignant, borne publique.
5. Rappels de retard, état des livres, bon de commande.

Made by Alexandre et Declaire
