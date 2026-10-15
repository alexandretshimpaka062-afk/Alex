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

> **À chaque mise à jour de Kivuthèque**, relancez ce script de la même façon (SQL Editor › coller › Run).
> Il ne supprime aucune donnée : il met seulement à jour les règles et les fonctions.

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

1. Ouvrez `https://kivutheque.netlify.app`, cliquez sur **Créer un compte**, choisissez **Personnel** et remplissez le formulaire.
2. Vous arrivez sur l'accueil : choisissez **Découvrir avec des exemples** ou **Commencer vide**.

## 5. Inviter l'équipe, les enseignants et les élèves

1. Envoyez l'adresse du site à chaque personne. Elle clique sur **Créer un compte** et indique si elle est élève (avec sa classe), enseignant ou membre du personnel. Elle peut aussi utiliser le bouton **Continuer avec Google** (étape 6).
2. Sa demande apparaît dans **Comptes**, rubrique « Demandes en attente », avec un compteur rouge dans le menu.
3. Pour un élève ou un enseignant :
   - choisissez sa **fiche de membre**, ou laissez « Nouvelle fiche » pour lui donner le prochain numéro (A001, A002…). Kivuthèque présélectionne la fiche dont le nom complet ou l'e-mail correspond ;
   - cliquez sur **Accepter**.
4. Pour le personnel, choisissez son rôle. Cela est réservé à l'administrateur.

| Rôle | Peut faire | Validé par |
|---|---|---|
| **Administrateur** | Tout, y compris les comptes et les réglages | Administrateur |
| **Bibliothécaire** | Livres, membres, emprunts, retours ; valide les élèves et les enseignants | Administrateur |
| **Gestion des fournitures** | Articles et mouvements de stock | Administrateur |
| **Direction** | Tout voir, sans rien modifier | Administrateur |
| **Enseignant** | Son espace de lecteur (et bientôt le suivi de ses classes) | Administrateur ou bibliothécaire |
| **Élève** | Son espace personnel : carte de membre, livres en cours, lectures, catalogue | Administrateur ou bibliothécaire |

Pour retirer l'accès à quelqu'un, choisissez **Désactivé** dans « Tous les comptes ».
Un élève ne voit jamais les emprunts ni les fiches des autres élèves : c'est la base de données qui l'interdit.

## 6. Activer le bouton « Continuer avec Google » (facultatif, environ 10 minutes)

Cette étape permet aux élèves d'entrer avec leur compte Gmail, sans mot de passe à retenir. Toute nouvelle personne passe quand même par la liste d'attente.

1. Allez sur <https://console.cloud.google.com> avec le compte Google de l'école.
   - Créez un projet nommé `Kivutheque` (menu du haut › **Nouveau projet**).
2. Ouvrez **API et services › Écran de consentement OAuth** (ou **Google Auth Platform › Branding**) :
   - type d'utilisateur : **Externe** ;
   - nom de l'application : `Kivuthèque` ;
   - adresse e-mail d'assistance et coordonnées du développeur : l'e-mail de l'école ;
   - enregistrez. Dans **Audience**, cliquez sur **Publier l'application**, sinon seuls les comptes de test pourront se connecter.
3. Ouvrez **API et services › Identifiants › Créer des identifiants › ID client OAuth** :
   - type : **Application Web** ;
   - origines JavaScript autorisées : `https://kivutheque.netlify.app` ;
   - URI de redirection autorisés : collez l'adresse **Callback URL** que donne Supabase (point 4 ci-dessous). Elle ressemble à `https://abcdefgh.supabase.co/auth/v1/callback` ;
   - cliquez sur **Créer**, puis notez l'**ID client** et le **Code secret du client**.
4. Dans Supabase, ouvrez **Authentication › Sign In / Providers › Google** :
   - activez **Enable Sign in with Google** ;
   - collez l'ID client et le code secret, puis cliquez sur **Save**.
   Le code secret Google se colle **uniquement dans Supabase** : ne l'envoyez à personne et ne le mettez dans aucun fichier.
5. Testez : ouvrez le site, cliquez sur **Continuer avec Google**, puis complétez la demande (profil et classe).

## 7. Enseignants et borne publique

- **Classes des enseignants** : à l'inscription, l'enseignant choisit ses classes. Quand l'administrateur accepte son compte, ces classes sont validées en même temps. Si c'est la bibliothécaire qui accepte, les classes attendent l'administrateur dans **Comptes › Classes à valider**. Le lien **Modifier** dans « Tous les comptes » change les classes d'un enseignant à tout moment.
- **Import des élèves** : Membres › « Importer des élèves (Excel) ». Colonnes reconnues : Nom, Postnom, Prénom (ou Nom complet), Classe, E-mail, Sexe. Si l'option est cochée (Réglages), un élève de la liste qui crée son compte avec la même adresse e-mail entre directement, sans liste d'attente. Cela suppose que Supabase vérifie les adresses e-mail (réglage par défaut « Confirm email »).
- **Rappels de retard** : Emprunts › « Rappels par e-mail ». Pour un envoi automatique avec n8n : Réglages › Rappels automatiques › « Clé pour n8n ».
- **Borne publique** : sur l'ordinateur de la bibliothèque, ouvrez `https://kivutheque.netlify.app/?borne`, puis passez en plein écran (bouton en haut à droite, ou touche F11). Elle montre seulement le catalogue, les livres disponibles et leur rayon : aucun nom, aucune connexion. Le lien se trouve aussi dans **Réglages › Borne publique**.

## 8. Activer l'assistant bibliothécaire IA (facultatif, environ 10 minutes)

L'assistant répond aux élèves avec des livres du catalogue. Il utilise l'API Claude (Anthropic), payée à l'usage.

1. **Créer la clé Claude** : ouvrez <https://console.anthropic.com>, créez un compte, puis :
   - **Billing** : ajoutez un petit crédit (par exemple 5 $) ;
   - **Limits** : fixez une limite de dépense mensuelle, pour ne jamais être surpris ;
   - **API Keys › Create Key** : copiez la clé (elle commence par `sk-ant-`). Ne l'envoyez à personne et ne la mettez dans aucun fichier.
2. **Installer le programme de l'assistant** : dans Supabase, ouvrez **Edge Functions**, puis **Deploy a new function › Via Editor** :
   - nom de la fonction : `assistant` (exactement) ;
   - remplacez le code par tout le contenu du fichier [`supabase/functions/assistant/index.ts`](supabase/functions/assistant/index.ts) ;
   - cliquez sur **Deploy**.
3. **Donner la clé au programme** : toujours dans **Edge Functions**, ouvrez **Secrets**, puis ajoutez :
   - nom `ANTHROPIC_API_KEY`, valeur : votre clé `sk-ant-…` ;
   - facultatif : nom `CLAUDE_MODEL`, valeur `claude-haiku-5-5` pour un assistant beaucoup moins cher (voir ci-dessous).
4. Testez : connectez-vous avec un compte élève et cliquez sur **« Tu ne sais pas quoi lire ? »**.

**Coût.** Par défaut l'assistant utilise Claude Opus 5.5, le modèle le plus capable : compter environ 2 à 3 centimes de dollar par question avec un petit catalogue (quelques centaines de livres), davantage avec un très grand. Avec `CLAUDE_MODEL` = `claude-haiku-5-5`, le coût est environ 40 fois plus faible, pour des conseils un peu moins fins. Dans **Réglages**, l'administrateur fixe le nombre de questions par personne et par jour (10 par défaut).

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
