# Mettre Kivuthèque en ligne

Kivuthèque fonctionne avec deux services gratuits :

- **Supabase** : les comptes (e-mail et mot de passe), la base de données et la sécurité des rôles.
- **Netlify** : le site lui-même, à l'adresse `https://kivutheque.netlify.app` (ou votre propre nom de domaine).

Comptez environ 15 minutes. Les étapes 1 à 3 se font une seule fois.

---

## 1. Créer la base de données (Supabase)

1. Allez sur <https://supabase.com> et cliquez sur **Start your project**. Inscrivez-vous, par exemple avec votre compte GitHub.
2. Cliquez sur **New project** :
   - **Name** : `kivutheque` ;
   - **Database password** : cliquez sur *Generate a password* et gardez-le précieusement ;
   - **Region** : *West EU (Paris)* ou *Central EU (Frankfurt)*, les plus proches de Goma ;
   - cliquez sur **Create new project**, puis attendez environ 2 minutes.
3. Dans le menu de gauche, ouvrez **SQL Editor**, puis **New query**.
4. Copiez tout le contenu du fichier [`supabase/schema.sql`](supabase/schema.sql), collez-le, puis cliquez sur **Run**.
   Le message *Success. No rows returned* doit s'afficher.

## 2. Régler la connexion (Supabase)

1. Ouvrez **Authentication**, puis **Sign In / Providers**, puis **Email** :
   - désactivez **Confirm email**. C'est conseillé, car un administrateur valide de toute façon chaque compte dans Kivuthèque ;
   - cliquez sur **Save**.
2. Ouvrez **Project Settings**, puis **API Keys**, et notez ces deux valeurs :
   - **Project URL**, de la forme `https://abcdefgh.supabase.co` (elle se trouve aussi dans *Project Settings*, rubrique *Data API*) ;
   - la clé **Publishable** (`sb_publishable_…`) ou, sur les anciens projets, la clé **anon public**.
3. Mettez ces deux valeurs dans le fichier [`web/config.js`](web/config.js), ou envoyez-les à Claude, qui le fera.
   Ces deux valeurs sont prévues pour être publiques : la sécurité repose sur les règles de la base installées à l'étape 1.
   **Ne donnez jamais** la clé *secret* ou *service_role*.

## 3. Publier le site (Netlify)

1. Allez sur <https://app.netlify.com> et inscrivez-vous avec **GitHub**.
2. Cliquez sur **Add new site**, puis **Import an existing project**, puis **GitHub**. Autorisez l'accès au dépôt **Alex**.
3. Choisissez :
   - la branche `claude/library-dashboard-design-11rghh`, ou `main` si les changements y ont été fusionnés ;
   - laissez les autres champs tels quels : le fichier `netlify.toml` indique déjà de publier le dossier `web` ;
   - cliquez sur **Deploy**.
4. Ouvrez **Site configuration**, puis **Change site name**, et tapez `kivutheque`. L'adresse devient `https://kivutheque.netlify.app`.
5. Retournez dans Supabase, ouvrez **Authentication**, puis **URL Configuration** :
   - **Site URL** : `https://kivutheque.netlify.app` ;
   - **Redirect URLs** : ajoutez `https://kivutheque.netlify.app/**` ;
   - cliquez sur **Save**. C'est nécessaire pour les e-mails « mot de passe oublié ».

Chaque modification envoyée sur GitHub met le site à jour automatiquement, en environ une minute.

## 4. Créer le compte administrateur

> **Important** : la toute première personne qui crée un compte devient **administrateur**.
> Faites-le vous-même tout de suite après la mise en ligne.

1. Ouvrez `https://kivutheque.netlify.app`, cliquez sur **Créer un compte** et remplissez le formulaire.
2. Vous arrivez sur l'accueil : choisissez **Découvrir avec des exemples** ou **Commencer vide**.

## 5. Inviter l'équipe

1. Envoyez l'adresse du site à chaque personne. Elle clique sur **Créer un compte**.
2. Son compte apparaît dans **Comptes**, marqué « à valider ». Choisissez son rôle :

| Rôle | Peut faire |
|---|---|
| **Administrateur** | Tout, y compris les comptes et les réglages |
| **Bibliothécaire** | Livres, membres, emprunts, retours et amendes |
| **Gestion des fournitures** | Articles et mouvements de stock |
| **Consultation** | Tout voir, sans rien modifier |

Pour retirer l'accès à quelqu'un, choisissez **Désactivé**.

## Rapports PDF

Le menu **Rapports** propose quatre rapports, chacun téléchargeable en PDF (format A4) :

- **Bibliothèque** : l'activité du mois, les catégories, les livres les plus empruntés et les emprunts par classe ;
- **Fournitures** : le stock en début et en fin de mois, les mouvements et les sorties par bénéficiaire ;
- **Retards et amendes** : les livres à récupérer et les amendes impayées ;
- **Inventaire des livres** : le catalogue complet par catégorie.

## Sauvegardes

L'administrateur peut télécharger une **sauvegarde complète** à tout moment, depuis **Réglages**, rubrique **Données**.
Supabase conserve aussi les données de son côté. Le plan gratuit ne fait pas de sauvegarde automatique :
téléchargez une sauvegarde complète chaque mois et gardez-la en lieu sûr.

---

Made by Alexandre et Declaire
