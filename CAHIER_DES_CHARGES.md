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
3. ✅ Défis, classements, recommandations.
   - Page « Défis » pour l'élève :
     - objectif du trimestre avec un anneau de progression ;
     - 8 badges (premier livre, 5, 10 et 25 livres, explorateur, toujours à l'heure, fidèle, critique) ;
     - rang dans la classe et dans l'école ; classement de sa classe, top 10 de l'école, classement des classes ;
     - diplôme PDF quand l'objectif est atteint.
   - Page « Défis » pour le personnel : classement des classes, top 10, classement complet d'une classe, diplômes PDF de la classe ou d'un élève.
   - Trimestres : septembre à décembre, janvier à mars, avril à juillet. L'objectif (3 livres par défaut) se règle dans Réglages.
   - Notes de 1 à 5 étoiles sur les livres empruntés ; rangée « Les mieux notés ».
   - « Les lecteurs de ce livre ont aussi lu » sur chaque fiche. « Pour toi » combine les lectures des élèves proches, les genres préférés, les notes et la popularité.
   - Badges visibles aussi sur la fiche d'un membre (personnel).
4. ✅ Espace enseignant, borne publique.
   - À l'inscription, l'enseignant choisit ses classes ; l'administrateur les valide (ou les modifie) dans « Comptes ». L'enseignant peut redemander d'autres classes plus tard.
   - Page « Mes classes » : un onglet par classe ; élèves, livres lus ce trimestre, objectif atteint, retards ; fiche de chaque élève (en cours, déjà lus, badges).
   - « Donner un livre à la classe » : un livre, une consigne (« à lire et à présenter le … ») et une date. Chaque élève la voit en haut de son espace, avec l'étiquette « Nouveau » ; l'enseignant voit combien d'élèves l'ont vue et ont emprunté le livre. Kivuthèque prévient s'il n'y a pas assez d'exemplaires.
   - Objectif de lecture propre à chaque classe ; bilan de classe et diplômes en PDF.
   - Borne publique : adresse du site suivie de `?borne`. Catalogue en plein écran, recherche, genres, livres disponibles et rayon, sans compte et sans aucun nom. Retour à l'accueil après 90 secondes sans activité.
5. ✅ Rappels de retard, état des livres, bon de commande.
   - Rappels **par e-mail, à l'élève** (adresse de son compte), sans les parents : un clic ouvre Gmail avec le message déjà écrit ; date du dernier rappel sur l'emprunt. Envoi automatique possible avec un agent n8n (clé secrète dans Réglages).
   - Au retour : bon état, abîmé (frais proposés : un quart du prix) ou perdu (prix de remplacement ; un exemplaire est retiré). Prix de remplacement sur la fiche du livre.
   - Bon de commande PDF par fournisseur, articles sous le seuil cochés d'office, quantité proposée modifiable.

## Ajouts après l'étape 5

- **Assistant bibliothécaire IA** (API Claude, programme dans Supabase) : l'élève pose une question, l'assistant propose 1 à 4 livres du catalogue uniquement, avec disponibilité et rayon. Limite de questions par jour.
- **Import des élèves depuis Excel ou CSV** : création et mise à jour des fiches ; acceptation automatique des élèves de la liste (même adresse e-mail).
- **Tableau de bord de la direction** : élèves lecteurs, livres lus, lecture par classe et par mois, achats conseillés, livres jamais empruntés, export Excel.
- **Avis écrits** : après avoir rendu un livre, l'élève écrit son avis ; la bibliothèque le valide (et peut corriger une faute) ; il apparaît sur la fiche du livre et dans « Les élèves en parlent ».
- **Clubs de lecture** : créés par un enseignant ou la bibliothèque (toute l'école, une classe ou sur invitation) ; livre du moment, rendez-vous, question de la semaine (réponses validées), vote pour le prochain livre, « j'ai fini ma lecture », badge « Club de lecture ».

## Esthétique et expérience (ajouté)

- Ouverture animée façon Netflix : le logo KIS sans fond, avec halo et rayons ; les lettres de « Kivuthèque » montent ; zoom final et bandes de couleur. Un son « ta-dum » composé dans le navigateur ; un bouton pour couper le son ; un écran « Touche l'écran pour entrer » quand le navigateur bloque le son.
- Écran « Qui lit aujourd'hui ? » avec la photo ou l'avatar de l'élève.
- Logo sans fond blanc partout sur le site.
- Espace élève :
  - aperçu au survol ;
  - « Top 10 de l'école cette semaine » avec de grands chiffres ;
  - bandeau du haut qui tourne tout seul ;
  - fiche de livre en grand ;
  - 24 avatars illustrés ;
  - série de lecture (semaines d'affilée) ;
  - objectif personnel de l'année ;
  - « Mon année de lecture » : récapitulatif animé, avec une image à télécharger.

## Idées gardées pour plus tard

Ces idées ont été proposées et retenues, mais **pas encore choisies** pour un ordre de réalisation. À reprendre après les modifications d'esthétique et les étapes 4 et 5.

1. ~~Assistant bibliothécaire IA~~ : fait.
2. **Notifications par e-mail** : « Ton livre t'attend », « Rappel : à rendre demain ».
3. **Application installable** sur téléphone et tablette : icône sur l'écran d'accueil, ouverture plein écran, consultation hors connexion.
4. ~~Import des élèves depuis Excel~~ : fait.
5. ~~Tableau de bord de la direction~~ : fait.
6. **Journal des actions** : qui a prêté, modifié ou supprimé quoi, et quand.
7. ~~Clubs de lecture et avis écrits~~ : fait.


Made by Alexandre et Declaire
