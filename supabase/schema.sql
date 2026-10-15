-- =====================================================================
-- Kivuthèque — base de données Supabase
-- À exécuter : Supabase › SQL Editor › New query › coller › Run.
-- Le script peut être relancé sans risque (il ne supprime aucune donnée) :
-- relancez-le après chaque mise à jour de Kivuthèque.
-- =====================================================================

-- ---------------------------------------------------------------- rôles
-- admin          : tout, y compris les comptes et les réglages
-- bibliothecaire : livres, membres, emprunts ; valide les élèves et les enseignants
-- fournitures    : articles et mouvements de stock
-- direction      : tout voir, rien modifier
-- enseignant     : son espace de lecteur et ses classes
-- eleve          : son espace de lecteur uniquement
-- en_attente     : inscription pas encore validée
-- desactive      : accès retiré ou demande refusée
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  nom        text,
  role       text not null default 'en_attente',
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists profil    text;            -- demandé à l'inscription : eleve, enseignant, personnel
alter table public.profiles add column if not exists classe    text;            -- classe indiquée à l'inscription
alter table public.profiles add column if not exists membre_id text;            -- fiche de membre reliée (A001…)
alter table public.profiles add column if not exists avatar    text;            -- photo de profil (petite image JPEG)
alter table public.profiles add column if not exists classes   text[] not null default '{}';  -- classes d'un enseignant
alter table public.profiles add column if not exists genres    text[] not null default '{}';  -- genres préférés (espace lecteur)
alter table public.profiles add column if not exists a_lire    text[] not null default '{}';  -- « à lire plus tard » (codes de livres)
alter table public.profiles add column if not exists objectif_perso int;                       -- objectif personnel de l'année (livres)
alter table public.profiles add column if not exists classes_demande text[] not null default '{}';  -- classes demandées par un enseignant (à valider par l'administrateur)

-- l'ancien rôle « consultation » s'appelle désormais « direction »
alter table public.profiles drop constraint if exists profiles_role_check;
update public.profiles set role = 'direction' where role = 'consultation';
alter table public.profiles add constraint profiles_role_check
  check (role in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve', 'en_attente', 'desactive'));
alter table public.profiles drop constraint if exists profiles_avatar_check;
alter table public.profiles add constraint profiles_avatar_check
  check (avatar is null or (length(avatar) < 80000 and avatar ~ '^data:image/(jpeg|png|webp);base64,[A-Za-z0-9+/=]+$'));
create unique index if not exists profiles_membre_unique on public.profiles (membre_id) where membre_id is not null;

-- ---------------------------------------------------------------- qui est connecté ?
-- (security definer : évite la récursion des règles d'accès)
create or replace function public.kiv_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'aucun');
$$;
create or replace function public.kiv_membre()
returns text language sql stable security definer set search_path = public as $$
  select membre_id from public.profiles where id = auth.uid();
$$;
create or replace function public.kiv_classes()
returns text[] language sql stable security definer set search_path = public as $$
  select coalesce((select classes from public.profiles where id = auth.uid() and role = 'enseignant'), '{}');
$$;

-- liste de classes propre (sans vide ni doublon, 12 au maximum)
create or replace function public.kiv_liste_classes(j jsonb)
returns text[] language sql immutable as $$
  select coalesce(array(select distinct left(trim(x), 60) from jsonb_array_elements_text(case when jsonb_typeof(j) = 'array' then j else '[]'::jsonb end) x
                        where trim(x) <> '' limit 12), '{}');
$$;

-- élève présent dans la liste importée (même adresse e-mail) : accepté tout de suite si l'option est activée dans Réglages
create or replace function public.kiv_auto_accepter(uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare
  p public.profiles;
  m text;
begin
  select * into p from public.profiles where id = uid;
  if not found or p.role <> 'en_attente' or coalesce(p.profil, '') <> 'eleve' or coalesce(p.email, '') = '' then return; end if;
  if to_regclass('public.reglages') is null or coalesce((select (data ->> 'autoAccept')::boolean from public.reglages where id = 'params'), false) is not true then return; end if;
  select mb.id into m from public.membres mb
  where lower(trim(mb.data ->> 'email')) = lower(trim(p.email)) and coalesce(mb.data ->> 'type', 'Élève') = 'Élève'
    and not exists (select 1 from public.profiles o where o.membre_id = mb.id)
  limit 1;
  if m is null then return; end if;
  update public.profiles set role = 'eleve', membre_id = m where id = uid;
end;
$$;
revoke execute on function public.kiv_auto_accepter(uuid) from public, anon, authenticated;

-- chaque inscription crée un profil ; la toute première personne devient administrateur
create or replace function public.kiv_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}');
begin
  perform pg_advisory_xact_lock(4242);
  insert into public.profiles (id, email, nom, role, profil, classe, classes_demande)
  values (
    new.id,
    new.email,
    left(coalesce(nullif(trim(m ->> 'nom'), ''), nullif(trim(m ->> 'full_name'), ''), nullif(trim(m ->> 'name'), ''), split_part(new.email, '@', 1)), 80),
    case when exists (select 1 from public.profiles where role = 'admin') then 'en_attente' else 'admin' end,
    case when m ->> 'profil' in ('eleve', 'enseignant', 'personnel') then m ->> 'profil' end,
    left(nullif(trim(m ->> 'classe'), ''), 60),
    case when m ->> 'profil' = 'enseignant' then public.kiv_liste_classes(m -> 'classes') else '{}' end
  )
  on conflict (id) do nothing;
  perform public.kiv_auto_accepter(new.id);
  return new;
end;
$$;
drop trigger if exists kiv_on_auth_user_created on auth.users;
create trigger kiv_on_auth_user_created
  after insert on auth.users
  for each row execute function public.kiv_new_user();

-- ---------------------------------------------------------------- validation des comptes
-- administrateur : tous les rôles ; bibliothécaire : élèves et enseignants uniquement
create or replace function public.kiv_valider(target uuid, new_role text, membre text default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  me   text := public.kiv_role();
  cur  public.profiles;
begin
  select * into cur from public.profiles where id = target;
  if not found then raise exception 'Compte introuvable.'; end if;
  if new_role not in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve', 'en_attente', 'desactive') then
    raise exception 'Rôle inconnu : %', new_role;
  end if;
  if me = 'bibliothecaire' then
    if target = auth.uid() then raise exception 'Vous ne pouvez pas modifier votre propre rôle.'; end if;
    if new_role not in ('eleve', 'enseignant', 'en_attente', 'desactive') or cur.role not in ('eleve', 'enseignant', 'en_attente', 'desactive') then
      raise exception 'La bibliothécaire ne peut attribuer que les rôles élève et enseignant.';
    end if;
  elsif me <> 'admin' then
    raise exception 'Seuls l''administrateur et la bibliothécaire peuvent valider les comptes.';
  end if;
  if new_role <> 'admin' and cur.role = 'admin'
     and (select count(*) from public.profiles where role = 'admin') <= 1 then
    raise exception 'Il faut garder au moins un administrateur.';
  end if;
  if membre is not null then
    if not exists (select 1 from public.membres where id = membre) then raise exception 'Fiche de membre introuvable : %', membre; end if;
    if exists (select 1 from public.profiles where membre_id = membre and id <> target) then
      raise exception 'La fiche % est déjà reliée à un autre compte.', membre;
    end if;
  end if;
  if new_role in ('eleve', 'enseignant') and coalesce(membre, cur.membre_id) is null then
    raise exception 'Reliez d''abord ce compte à une fiche de membre.';
  end if;
  update public.profiles set role = new_role, membre_id = coalesce(membre, membre_id) where id = target;
end;
$$;
-- ancienne fonction, conservée pour compatibilité
create or replace function public.kiv_set_role(target uuid, new_role text)
returns void language sql security definer set search_path = public as $$
  select public.kiv_valider(target, new_role, null);
$$;

-- mon profil : nom et photo (l'avatar vide '' retire la photo)
create or replace function public.kiv_mon_profil(nom text default null, avatar text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connectez-vous d''abord.'; end if;
  update public.profiles set
    nom    = coalesce(left(nullif(trim(kiv_mon_profil.nom), ''), 80), profiles.nom),
    avatar = case when kiv_mon_profil.avatar is null then profiles.avatar when kiv_mon_profil.avatar = '' then null else kiv_mon_profil.avatar end
  where id = auth.uid();
end;
$$;
-- compléter sa demande (inscription avec Google : profil, classe, classes d'un enseignant)
drop function if exists public.kiv_ma_demande(text, text, text);
create or replace function public.kiv_ma_demande(profil text, classe text, nom text default null, classes text[] default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() <> 'en_attente' then raise exception 'Votre compte est déjà validé.'; end if;
  if profil not in ('eleve', 'enseignant', 'personnel') then raise exception 'Profil inconnu.'; end if;
  update public.profiles set
    profil = kiv_ma_demande.profil,
    classe = left(nullif(trim(kiv_ma_demande.classe), ''), 60),
    nom    = coalesce(left(nullif(trim(kiv_ma_demande.nom), ''), 80), profiles.nom),
    classes_demande = case when kiv_ma_demande.profil = 'enseignant' then public.kiv_liste_classes(to_jsonb(coalesce(kiv_ma_demande.classes, '{}'))) else '{}' end
  where id = auth.uid();
  perform public.kiv_auto_accepter(auth.uid());
end;
$$;
-- un enseignant demande ses classes (l'administrateur valide ensuite)
create or replace function public.kiv_mes_classes(classes text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() not in ('enseignant', 'en_attente') then raise exception 'Réservé aux enseignants.'; end if;
  update public.profiles set classes_demande = public.kiv_liste_classes(to_jsonb(coalesce(kiv_mes_classes.classes, '{}'))) where id = auth.uid();
end;
$$;
-- l'administrateur valide (ou modifie) les classes d'un enseignant
create or replace function public.kiv_classes_valider(target uuid, classes text[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() <> 'admin' then raise exception 'Seul l''administrateur valide les classes des enseignants.'; end if;
  update public.profiles set classes = public.kiv_liste_classes(to_jsonb(coalesce(kiv_classes_valider.classes, '{}'))), classes_demande = '{}' where id = target;
  if not found then raise exception 'Compte introuvable.'; end if;
end;
$$;
-- modération : retirer la photo de quelqu'un
create or replace function public.kiv_retirer_photo(target uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() not in ('admin', 'bibliothecaire') then raise exception 'Action réservée à l''administrateur et à la bibliothécaire.'; end if;
  update public.profiles set avatar = null where id = target;
end;
$$;

alter table public.profiles enable row level security;
drop policy if exists "profil : lecture" on public.profiles;
create policy "profil : lecture" on public.profiles
  for select to authenticated using (id = auth.uid() or public.kiv_role() in ('admin', 'bibliothecaire', 'direction'));
-- aucune écriture directe : uniquement par les fonctions ci-dessus
revoke all on public.profiles from anon;
revoke insert, update, delete on public.profiles from authenticated;
grant select on public.profiles to authenticated;   -- les règles ci-dessus filtrent les lignes
revoke execute on function public.kiv_valider(uuid, text, text), public.kiv_set_role(uuid, text), public.kiv_mon_profil(text, text),
  public.kiv_ma_demande(text, text, text, text[]), public.kiv_retirer_photo(uuid), public.kiv_mes_classes(text[]), public.kiv_classes_valider(uuid, text[]) from public, anon;
grant execute on function public.kiv_valider(uuid, text, text), public.kiv_set_role(uuid, text), public.kiv_mon_profil(text, text),
  public.kiv_ma_demande(text, text, text, text[]), public.kiv_retirer_photo(uuid), public.kiv_mes_classes(text[]), public.kiv_classes_valider(uuid, text[]),
  public.kiv_role(), public.kiv_membre(), public.kiv_classes() to authenticated;

-- ---------------------------------------------------------------- données
-- Chaque enregistrement est un document JSON (même format que l'application).
do $$
declare t text;
begin
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages'] loop
    execute format('create table if not exists public.%I (
      id         text primary key,
      data       jsonb not null,
      updated_at timestamptz not null default now(),
      updated_by uuid default auth.uid()
    )', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- horodatage et auteur de chaque modification
create or replace function public.kiv_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;
do $$
declare t text;
begin
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages'] loop
    execute format('drop trigger if exists kiv_touch on public.%I', t);
    execute format('create trigger kiv_touch before insert or update on public.%I for each row execute function public.kiv_touch()', t);
  end loop;
end $$;

-- règles d'accès
--   écriture : selon le rôle du personnel
--   lecture  : le personnel lit tout ; un élève ne lit que sa fiche et ses emprunts ;
--              un enseignant lit aussi les élèves de ses classes et leurs emprunts
do $$
declare
  t text;
  writers text;
  readers text;
begin
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages'] loop
    writers := case
      when t in ('livres', 'membres', 'emprunts') then '''admin'', ''bibliothecaire'''
      when t in ('fournitures', 'mouvements') then '''admin'', ''fournitures'''
      else '''admin'''
    end;
    readers := case
      when t in ('livres', 'reglages') then
        'public.kiv_role() in (''admin'', ''bibliothecaire'', ''fournitures'', ''direction'', ''enseignant'', ''eleve'')'
      when t = 'membres' then
        'public.kiv_role() in (''admin'', ''bibliothecaire'', ''fournitures'', ''direction'')
         or (public.kiv_role() in (''enseignant'', ''eleve'') and id = public.kiv_membre())
         or (public.kiv_role() = ''enseignant'' and data ->> ''classe'' = any (public.kiv_classes()))'
      when t = 'emprunts' then
        'public.kiv_role() in (''admin'', ''bibliothecaire'', ''fournitures'', ''direction'')
         or (public.kiv_role() in (''enseignant'', ''eleve'') and data ->> ''membre'' = public.kiv_membre())
         or (public.kiv_role() = ''enseignant'' and exists (select 1 from public.membres m
               where m.id = emprunts.data ->> ''membre'' and m.data ->> ''classe'' = any (public.kiv_classes())))'
      else
        'public.kiv_role() in (''admin'', ''bibliothecaire'', ''fournitures'', ''direction'')'
    end;
    execute format('drop policy if exists "lecture" on public.%I', t);
    execute format('create policy "lecture" on public.%I for select to authenticated using (%s)', t, readers);
    execute format('drop policy if exists "ajout" on public.%I', t);
    execute format('create policy "ajout" on public.%I for insert to authenticated with check (public.kiv_role() in (%s))', t, writers);
    execute format('drop policy if exists "modification" on public.%I', t);
    execute format('create policy "modification" on public.%I for update to authenticated
      using (public.kiv_role() in (%s)) with check (public.kiv_role() in (%s))', t, writers, writers);
    execute format('drop policy if exists "suppression" on public.%I', t);
    execute format('create policy "suppression" on public.%I for delete to authenticated using (public.kiv_role() in (%s))', t, writers);
  end loop;
end $$;

-- ---------------------------------------------------------------- numéros de membre A001 … A999, B001 …
create or replace function public.kiv_rang(num text)
returns int language sql immutable as $$
  select case when num ~ '^[A-Z][0-9]{3}$' then (ascii(left(num, 1)) - 65) * 999 + right(num, 3)::int end;
$$;
create or replace function public.kiv_numero(rang int)
returns text language sql immutable as $$
  select chr(65 + (rang - 1) / 999) || lpad(((rang - 1) % 999 + 1)::text, 3, '0');
$$;
-- création d'une fiche de membre avec le prochain numéro libre (sans doublon, même à plusieurs)
create or replace function public.kiv_nouveau_membre(fiche jsonb)
returns text language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if public.kiv_role() not in ('admin', 'bibliothecaire') then raise exception 'Votre rôle ne permet pas cette modification.'; end if;
  perform pg_advisory_xact_lock(4243);
  n := public.kiv_numero(coalesce((select max(public.kiv_rang(id)) from public.membres), 0) + 1);
  insert into public.membres (id, data) values (n, fiche - 'id');
  return n;
end;
$$;
revoke execute on function public.kiv_nouveau_membre(jsonb) from public, anon;
grant execute on function public.kiv_nouveau_membre(jsonb) to authenticated;

-- anciens numéros (MEM-001…) → A001… ; les emprunts et les comptes suivent
do $$
declare
  r record;
  n int := coalesce((select max(public.kiv_rang(id)) from public.membres), 0);
begin
  for r in select id from public.membres where public.kiv_rang(id) is null order by id loop
    n := n + 1;
    update public.membres set id = public.kiv_numero(n) where id = r.id;
    update public.emprunts set data = jsonb_set(data, '{membre}', to_jsonb(public.kiv_numero(n))) where data ->> 'membre' = r.id;
    update public.profiles set membre_id = public.kiv_numero(n) where membre_id = r.id;
  end loop;
end $$;

-- ---------------------------------------------------------------- réservations
-- statut : attente (file d'attente) → prete (mis de côté, gardé 3 jours) → servie (emprunté)
--          ou annulee / expiree
create table if not exists public.reservations (
  id         uuid primary key default gen_random_uuid(),
  livre      text not null,
  membre     text not null,
  statut     text not null default 'attente' check (statut in ('attente', 'prete', 'servie', 'annulee', 'expiree')),
  created_at timestamptz not null default now(),
  prete_le   timestamptz,
  expire_le  date,
  updated_by uuid default auth.uid()
);
create index if not exists reservations_livre on public.reservations (livre, statut);
create index if not exists reservations_membre on public.reservations (membre, statut);
alter table public.reservations enable row level security;
revoke all on public.reservations from anon;
revoke insert, delete on public.reservations from authenticated;
grant select, update on public.reservations to authenticated;
drop policy if exists "reservations : lecture" on public.reservations;
create policy "reservations : lecture" on public.reservations for select to authenticated
  using (public.kiv_role() in ('admin', 'bibliothecaire', 'direction') or membre = public.kiv_membre());
drop policy if exists "reservations : gestion" on public.reservations;
create policy "reservations : gestion" on public.reservations for update to authenticated
  using (public.kiv_role() in ('admin', 'bibliothecaire')) with check (public.kiv_role() in ('admin', 'bibliothecaire'));

-- exemplaires d'un livre : total, sortis, mis de côté (réservation prête et pas encore expirée)
create or replace function public.kiv_stock_livre(l text)
returns table (ex int, sortis int, reserves int) language sql stable security definer set search_path = public as $$
  select coalesce((select (data ->> 'ex')::int from public.livres where id = l), 0),
         (select count(*)::int from public.emprunts where data ->> 'livre' = l and (data ->> 'retour') is null),
         (select count(*)::int from public.reservations where livre = l and statut = 'prete' and expire_le >= current_date);
$$;
revoke execute on function public.kiv_stock_livre(text) from public, anon, authenticated;

-- réserver un livre (élève, enseignant ; la bibliothécaire peut réserver pour un membre)
create or replace function public.kiv_reserver(livre text, pour text default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me  text := public.kiv_role();
  m   text;
  st  record;
  nid uuid;
begin
  if me in ('admin', 'bibliothecaire') and pour is not null then m := pour;
  elsif me in ('eleve', 'enseignant', 'admin', 'bibliothecaire') then m := public.kiv_membre();
  else raise exception 'Votre rôle ne permet pas de réserver.'; end if;
  if m is null then raise exception 'Ton compte n''est pas encore relié à une fiche de membre.'; end if;
  if not exists (select 1 from public.livres where id = kiv_reserver.livre) then raise exception 'Livre introuvable.'; end if;
  if exists (select 1 from public.reservations r where r.livre = kiv_reserver.livre and r.membre = m and r.statut in ('attente', 'prete')) then
    raise exception 'Tu as déjà réservé ce livre.'; end if;
  if exists (select 1 from public.emprunts e where e.data ->> 'livre' = kiv_reserver.livre and e.data ->> 'membre' = m and (e.data ->> 'retour') is null) then
    raise exception 'Tu as déjà ce livre en ce moment.'; end if;
  if (select count(*) from public.reservations r where r.membre = m and r.statut in ('attente', 'prete')) >= 3 then
    raise exception 'Tu as déjà 3 réservations : c''est le maximum.'; end if;
  select * into st from public.kiv_stock_livre(kiv_reserver.livre);
  if me in ('eleve', 'enseignant') and st.ex - st.sortis - st.reserves
       - (select count(*) from public.reservations r where r.livre = kiv_reserver.livre and r.statut = 'attente') > 0 then
    raise exception 'Ce livre est disponible : passe le chercher à la bibliothèque !'; end if;
  insert into public.reservations (livre, membre) values (kiv_reserver.livre, m) returning id into nid;
  return nid;
end;
$$;
-- annuler (l'élève : les siennes ; la bibliothécaire : toutes)
create or replace function public.kiv_annuler_reservation(rid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.reservations set statut = 'annulee', updated_by = auth.uid()
  where id = rid and statut in ('attente', 'prete')
    and (public.kiv_role() in ('admin', 'bibliothecaire') or membre = public.kiv_membre());
  if not found then raise exception 'Réservation introuvable ou déjà terminée.'; end if;
end;
$$;
-- mes réservations, avec ma place dans la file d'attente
create or replace function public.kiv_mes_reservations()
returns table (id uuid, livre text, statut text, created_at timestamptz, expire_le date, rang int)
language sql stable security definer set search_path = public as $$
  select r.id, r.livre,
         case when r.statut = 'prete' and r.expire_le < current_date then 'expiree' else r.statut end,
         r.created_at, r.expire_le,
         case when r.statut = 'attente' then 1 + (select count(*)::int from public.reservations o
           where o.livre = r.livre and o.statut = 'attente' and o.created_at < r.created_at) end
  from public.reservations r
  where r.membre = public.kiv_membre() and r.statut in ('attente', 'prete')
  order by r.created_at;
$$;

-- ---------------------------------------------------------------- disponibilité des livres
-- un lecteur ne voit pas les emprunts des autres : on lui donne seulement des nombres
drop function if exists public.kiv_dispo();
create or replace function public.kiv_dispo()
returns table (livre text, sortis int, reserves int, attente int, total int)
language sql stable security definer set search_path = public as $$
  with e as (
    select data ->> 'livre' as livre, count(*) filter (where (data ->> 'retour') is null)::int as sortis, count(*)::int as total
    from public.emprunts group by 1
  ), r as (
    select livre, count(*) filter (where statut = 'prete' and expire_le >= current_date)::int as reserves,
           count(*) filter (where statut = 'attente')::int as attente
    from public.reservations where statut in ('attente', 'prete') group by 1
  )
  select coalesce(e.livre, r.livre), coalesce(e.sortis, 0), coalesce(r.reserves, 0), coalesce(r.attente, 0), coalesce(e.total, 0)
  from e full join r on r.livre = e.livre
  where public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve');
$$;

-- préférences du lecteur : genres préférés et liste « à lire plus tard »
create or replace function public.kiv_mes_genres(genres text[])
returns void language sql security definer set search_path = public as $$
  update public.profiles set genres = coalesce(kiv_mes_genres.genres[1:20], '{}') where id = auth.uid();
$$;
create or replace function public.kiv_a_lire(livre text, garder boolean)
returns void language sql security definer set search_path = public as $$
  update public.profiles set a_lire = case
    when garder then (array_remove(a_lire, kiv_a_lire.livre) || kiv_a_lire.livre)[greatest(1, cardinality(array_remove(a_lire, kiv_a_lire.livre)) - 98):]
    else array_remove(a_lire, kiv_a_lire.livre) end
  where id = auth.uid();
$$;
revoke execute on function public.kiv_dispo(), public.kiv_reserver(text, text), public.kiv_annuler_reservation(uuid), public.kiv_mes_reservations(),
  public.kiv_mes_genres(text[]), public.kiv_a_lire(text, boolean) from public, anon;
grant execute on function public.kiv_dispo(), public.kiv_reserver(text, text), public.kiv_annuler_reservation(uuid), public.kiv_mes_reservations(),
  public.kiv_mes_genres(text[]), public.kiv_a_lire(text, boolean) to authenticated;

-- ---------------------------------------------------------------- notes des lecteurs (1 à 5 étoiles)
create table if not exists public.avis (
  livre      text not null,
  membre     text not null,
  note       int  not null check (note between 1 and 5),
  updated_at timestamptz not null default now(),
  primary key (livre, membre)
);
alter table public.avis enable row level security;
revoke all on public.avis from anon;
revoke insert, update, delete on public.avis from authenticated;
grant select on public.avis to authenticated;
drop policy if exists "avis : lecture" on public.avis;
create policy "avis : lecture" on public.avis for select to authenticated
  using (public.kiv_role() in ('admin', 'bibliothecaire', 'direction') or membre = public.kiv_membre());
-- avis écrits : quelques lignes après la lecture, publiées après validation par la bibliothèque
alter table public.avis add column if not exists texte      text check (length(texte) <= 500);
alter table public.avis add column if not exists statut     text check (statut in ('attente', 'publie', 'refuse'));
alter table public.avis add column if not exists motif      text;
alter table public.avis add column if not exists texte_le   timestamptz;
alter table public.avis add column if not exists valide_par uuid;
-- noter un livre qu'on a emprunté (0 = retirer sa note)
create or replace function public.kiv_noter(livre text, note int)
returns void language plpgsql security definer set search_path = public as $$
declare m text := public.kiv_membre();
begin
  if m is null or public.kiv_role() not in ('eleve', 'enseignant', 'admin', 'bibliothecaire') then raise exception 'Connecte-toi avec ton compte de lecteur.'; end if;
  if not exists (select 1 from public.emprunts e where e.data ->> 'livre' = kiv_noter.livre and e.data ->> 'membre' = m) then
    raise exception 'Tu peux noter un livre après l''avoir emprunté.'; end if;
  if coalesce(kiv_noter.note, 0) = 0 then delete from public.avis a where a.livre = kiv_noter.livre and a.membre = m; return; end if;
  if kiv_noter.note not between 1 and 5 then raise exception 'La note va de 1 à 5 étoiles.'; end if;
  insert into public.avis as a (livre, membre, note) values (kiv_noter.livre, m, kiv_noter.note)
  on conflict on constraint avis_pkey do update set note = excluded.note, updated_at = now();
end;
$$;
-- écrire (ou modifier) son avis : le livre doit avoir été rendu
create or replace function public.kiv_avis_ecrire(livre text, note int, texte text)
returns void language plpgsql security definer set search_path = public as $$
declare m text := public.kiv_membre(); t text := left(nullif(trim(kiv_avis_ecrire.texte), ''), 500);
begin
  if m is null or public.kiv_role() not in ('eleve', 'enseignant', 'admin', 'bibliothecaire') then raise exception 'Connecte-toi avec ton compte de lecteur.'; end if;
  if not exists (select 1 from public.emprunts e where e.data ->> 'livre' = kiv_avis_ecrire.livre and e.data ->> 'membre' = m and (e.data ->> 'retour') is not null) then
    raise exception 'Tu pourras donner ton avis quand tu auras rendu ce livre.'; end if;
  if kiv_avis_ecrire.note not between 1 and 5 then raise exception 'Choisis d''abord une note de 1 à 5 étoiles.'; end if;
  insert into public.avis as a (livre, membre, note, texte, statut, motif, texte_le)
  values (kiv_avis_ecrire.livre, m, kiv_avis_ecrire.note, t, case when t is null then null else 'attente' end, null, case when t is null then null else now() end)
  on conflict on constraint avis_pkey do update set note = excluded.note, texte = excluded.texte, statut = excluded.statut, motif = null,
    texte_le = excluded.texte_le, updated_at = now(), valide_par = null;
end;
$$;
-- publier ou refuser un avis (la bibliothécaire peut corriger une faute)
create or replace function public.kiv_avis_valider(livre text, membre text, publier boolean, texte text default null, motif text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() not in ('admin', 'bibliothecaire') then raise exception 'Action réservée à la bibliothèque.'; end if;
  update public.avis a set statut = case when publier then 'publie' else 'refuse' end,
    texte = coalesce(left(nullif(trim(kiv_avis_valider.texte), ''), 500), a.texte),
    motif = left(nullif(trim(kiv_avis_valider.motif), ''), 300), valide_par = auth.uid()
  where a.livre = kiv_avis_valider.livre and a.membre = kiv_avis_valider.membre and a.texte is not null;
  if not found then raise exception 'Avis introuvable.'; end if;
end;
$$;
-- avis publiés (nom affiché « Prénom N. »)
create or replace function public.kiv_nom_court(n text)
returns text language sql immutable as $$
  select split_part(trim(regexp_replace(coalesce(n, ''), '^(M\.|Mme)\s+', '')), ' ', 1)
    || case when position(' ' in trim(regexp_replace(coalesce(n, ''), '^(M\.|Mme)\s+', ''))) > 0
       then ' ' || left(regexp_replace(trim(n), '^.*\s', ''), 1) || '.' else '' end;
$$;
create or replace function public.kiv_avis_publies(livre text default null, n int default 30)
returns table (livre_id text, note int, texte text, nom text, classe text, le timestamptz, moi boolean)
language sql stable security definer set search_path = public as $$
  select a.livre, a.note, a.texte, public.kiv_nom_court(m.data ->> 'nom'), case when m.data ->> 'classe' = 'Personnel' then 'Enseignant' else m.data ->> 'classe' end,
         a.texte_le, a.membre = public.kiv_membre()
  from public.avis a left join public.membres m on m.id = a.membre
  where a.statut = 'publie' and (kiv_avis_publies.livre is null or a.livre = kiv_avis_publies.livre)
    and public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve')
  order by a.texte_le desc limit greatest(1, least(coalesce(n, 30), 200));
$$;
revoke execute on function public.kiv_avis_ecrire(text, int, text), public.kiv_avis_valider(text, text, boolean, text, text), public.kiv_avis_publies(text, int) from public, anon;
grant execute on function public.kiv_avis_ecrire(text, int, text), public.kiv_avis_valider(text, text, boolean, text, text), public.kiv_avis_publies(text, int) to authenticated;

-- moyenne des notes par livre (sans les noms)
create or replace function public.kiv_notes()
returns table (livre text, moyenne numeric, nb int) language sql stable security definer set search_path = public as $$
  select a.livre, round(avg(a.note)::numeric, 1), count(*)::int from public.avis a
  where public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve')
  group by a.livre;
$$;

-- ---------------------------------------------------------------- recommandations
-- « les lecteurs qui ont lu ce livre ont aussi lu… »
create or replace function public.kiv_aussi_lu(livre text)
returns table (livre_id text, nb int) language sql stable security definer set search_path = public as $$
  with lecteurs as (select distinct data ->> 'membre' as m from public.emprunts where data ->> 'livre' = kiv_aussi_lu.livre)
  select e.data ->> 'livre', count(distinct e.data ->> 'membre')::int
  from public.emprunts e join lecteurs l on l.m = e.data ->> 'membre'
  where e.data ->> 'livre' <> kiv_aussi_lu.livre
    and public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve')
  group by 1 order by 2 desc, 1 limit 12;
$$;
-- pour moi : les livres lus par les lecteurs qui ont les mêmes lectures que moi
create or replace function public.kiv_pour_moi()
returns table (livre text, score int) language sql stable security definer set search_path = public as $$
  with mine as (select distinct data ->> 'livre' as l from public.emprunts where data ->> 'membre' = public.kiv_membre()),
  proches as (
    select e.data ->> 'membre' as m, count(distinct e.data ->> 'livre')::int as communs
    from public.emprunts e where e.data ->> 'livre' in (select l from mine) and e.data ->> 'membre' <> public.kiv_membre() group by 1
  )
  select e.data ->> 'livre', sum(p.communs)::int
  from public.emprunts e join proches p on p.m = e.data ->> 'membre'
  where e.data ->> 'livre' not in (select l from mine)
  group by 1 order by 2 desc, 1 limit 24;
$$;

-- ---------------------------------------------------------------- top 10 de la semaine et objectif personnel
create or replace function public.kiv_top_semaine()
returns table (livre text, nb int) language sql stable security definer set search_path = public as $$
  select data ->> 'livre', count(*)::int from public.emprunts
  where (data ->> 'date')::date >= current_date - 7
    and public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve')
  group by 1 order by 2 desc, 1 limit 10;
$$;
create or replace function public.kiv_mon_objectif(n int)
returns void language sql security definer set search_path = public as $$
  update public.profiles set objectif_perso = case when n between 1 and 200 then n end where id = auth.uid();
$$;
revoke execute on function public.kiv_top_semaine(), public.kiv_mon_objectif(int) from public, anon;
grant execute on function public.kiv_top_semaine(), public.kiv_mon_objectif(int) to authenticated;

-- ---------------------------------------------------------------- défis de lecture : classements
-- livres rendus entre deux dates, par élève. Noms affichés « Prénom N. » ; photo seulement pour les premiers.
create or replace function public.kiv_classement(debut date, fin date)
returns table (membre text, nom text, classe text, lus int, rang_ecole int, rang_classe int, avatar text, moi boolean)
language sql stable security definer set search_path = public as $$
  with base as (
    select m.id, m.data ->> 'nom' as nom, coalesce(m.data ->> 'classe', '') as classe,
           count(e.id) filter (where (e.data ->> 'retour') is not null and (e.data ->> 'retour')::date between debut and fin)::int as lus
    from public.membres m left join public.emprunts e on e.data ->> 'membre' = m.id
    where coalesce(m.data ->> 'type', 'Élève') = 'Élève'
    group by m.id, m.data
  ), r as (
    select *, rank() over (order by lus desc)::int as re, rank() over (partition by classe order by lus desc)::int as rc from base
  ), me as (select classe from base where id = public.kiv_membre())
  select r.id,
         split_part(trim(r.nom), ' ', 1) || case when position(' ' in trim(r.nom)) > 0
           then ' ' || left(regexp_replace(trim(r.nom), '^.*\s', ''), 1) || '.' else '' end,
         r.classe, r.lus, r.re, r.rc,
         case when r.lus > 0 and (r.re <= 10 or (r.rc <= 10 and r.classe = (select classe from me)) or r.id = public.kiv_membre())
           then (select p.avatar from public.profiles p where p.membre_id = r.id) end,
         r.id = public.kiv_membre()
  from r
  where public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve');
$$;
revoke execute on function public.kiv_noter(text, int), public.kiv_notes(), public.kiv_aussi_lu(text), public.kiv_pour_moi(), public.kiv_classement(date, date) from public, anon;
grant execute on function public.kiv_noter(text, int), public.kiv_notes(), public.kiv_aussi_lu(text), public.kiv_pour_moi(), public.kiv_classement(date, date) to authenticated;

-- ---------------------------------------------------------------- espace enseignant
-- classe de l'élève connecté (d'après sa fiche de membre)
create or replace function public.kiv_ma_classe()
returns text language sql stable security definer set search_path = public as $$
  select data ->> 'classe' from public.membres where id = public.kiv_membre();
$$;
-- lectures données par un enseignant à toute une classe (« à lire et à présenter pour le … »)
create table if not exists public.consignes (
  id         uuid primary key default gen_random_uuid(),
  classe     text not null,
  livre      text not null,
  message    text not null default '' check (length(message) <= 600),
  echeance   date,
  auteur     uuid default auth.uid(),
  auteur_nom text,
  created_at timestamptz not null default now()
);
create index if not exists consignes_classe on public.consignes (classe, created_at);
-- qui a vu la consigne (l'enseignant voit « vue par 18 élèves sur 25 »)
create table if not exists public.consigne_vues (
  consigne uuid not null references public.consignes (id) on delete cascade,
  membre   text not null,
  vu_le    timestamptz not null default now(),
  primary key (consigne, membre)
);
alter table public.consignes enable row level security;
alter table public.consigne_vues enable row level security;
revoke all on public.consignes, public.consigne_vues from anon;
revoke insert, update, delete on public.consignes, public.consigne_vues from authenticated;
grant select on public.consignes, public.consigne_vues to authenticated;
drop policy if exists "consignes : lecture" on public.consignes;
create policy "consignes : lecture" on public.consignes for select to authenticated
  using (public.kiv_role() in ('admin', 'bibliothecaire', 'direction')
         or (public.kiv_role() = 'enseignant' and classe = any (public.kiv_classes()))
         or (public.kiv_role() = 'eleve' and classe = public.kiv_ma_classe()));
drop policy if exists "consignes vues : lecture" on public.consigne_vues;
create policy "consignes vues : lecture" on public.consigne_vues for select to authenticated
  using (membre = public.kiv_membre() or public.kiv_role() in ('admin', 'bibliothecaire', 'direction')
         or (public.kiv_role() = 'enseignant' and exists (select 1 from public.consignes c where c.id = consigne and c.classe = any (public.kiv_classes()))));
-- donner un livre à une ou plusieurs classes (l'enseignant : ses classes ; l'administrateur et la bibliothécaire : toutes)
create or replace function public.kiv_consigne(classes text[], livre text, message text, echeance date default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  me text := public.kiv_role();
  c  text;
  n  int := 0;
begin
  if me not in ('enseignant', 'admin', 'bibliothecaire') then raise exception 'Réservé aux enseignants.'; end if;
  if not exists (select 1 from public.livres where id = kiv_consigne.livre) then raise exception 'Livre introuvable.'; end if;
  if kiv_consigne.echeance is not null and kiv_consigne.echeance < current_date then raise exception 'La date est déjà passée.'; end if;
  foreach c in array coalesce(kiv_consigne.classes, '{}') loop
    if me = 'enseignant' and not (c = any (public.kiv_classes())) then raise exception 'La classe % n''est pas une de vos classes.', c; end if;
    insert into public.consignes (classe, livre, message, echeance, auteur_nom)
    values (c, kiv_consigne.livre, left(coalesce(kiv_consigne.message, ''), 600), kiv_consigne.echeance, (select nom from public.profiles where id = auth.uid()));
    n := n + 1;
  end loop;
  if n = 0 then raise exception 'Choisissez au moins une classe.'; end if;
  return n;
end;
$$;
create or replace function public.kiv_consigne_retirer(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  delete from public.consignes c where c.id = cid
    and (public.kiv_role() in ('admin', 'bibliothecaire') or (public.kiv_role() = 'enseignant' and c.classe = any (public.kiv_classes())));
  if not found then raise exception 'Consigne introuvable.'; end if;
end;
$$;
-- l'élève a vu la consigne
create or replace function public.kiv_consigne_vue(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_membre() is null then return; end if;
  if not exists (select 1 from public.consignes c where c.id = cid and c.classe = public.kiv_ma_classe()) then return; end if;
  insert into public.consigne_vues (consigne, membre) values (cid, public.kiv_membre()) on conflict do nothing;
end;
$$;
-- objectif de lecture propre à une classe (sinon : celui des Réglages)
create table if not exists public.objectifs_classe (
  classe     text primary key,
  objectif   int not null check (objectif between 1 and 50),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.objectifs_classe enable row level security;
revoke all on public.objectifs_classe from anon;
revoke insert, update, delete on public.objectifs_classe from authenticated;
grant select on public.objectifs_classe to authenticated;
drop policy if exists "objectifs : lecture" on public.objectifs_classe;
create policy "objectifs : lecture" on public.objectifs_classe for select to authenticated
  using (public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve'));
create or replace function public.kiv_objectif_classe(classe text, n int)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (public.kiv_role() in ('admin', 'bibliothecaire') or (public.kiv_role() = 'enseignant' and kiv_objectif_classe.classe = any (public.kiv_classes()))) then
    raise exception 'Vous ne pouvez régler que l''objectif de vos classes.'; end if;
  if coalesce(n, 0) = 0 then delete from public.objectifs_classe o where o.classe = kiv_objectif_classe.classe; return; end if;
  if n not between 1 and 50 then raise exception 'L''objectif va de 1 à 50 livres.'; end if;
  insert into public.objectifs_classe as o (classe, objectif) values (kiv_objectif_classe.classe, n)
  on conflict on constraint objectifs_classe_pkey do update set objectif = excluded.objectif, updated_at = now(), updated_by = auth.uid();
end;
$$;
revoke execute on function public.kiv_ma_classe(), public.kiv_consigne(text[], text, text, date), public.kiv_consigne_retirer(uuid), public.kiv_consigne_vue(uuid),
  public.kiv_objectif_classe(text, int) from public, anon;
grant execute on function public.kiv_ma_classe(), public.kiv_consigne(text[], text, text, date), public.kiv_consigne_retirer(uuid), public.kiv_consigne_vue(uuid),
  public.kiv_objectif_classe(text, int) to authenticated;

-- ---------------------------------------------------------------- clubs de lecture
-- un enseignant ou la bibliothèque crée un club ; les élèves le rejoignent, répondent à la question
-- de la semaine (réponses validées avant d'être visibles) et votent pour le prochain livre
create table if not exists public.clubs (
  id            uuid primary key default gen_random_uuid(),
  nom           text not null check (length(nom) between 2 and 60),
  description   text check (length(description) <= 400),
  livre         text,
  animateur     uuid default auth.uid(),
  animateur_nom text,
  acces         text not null default 'ecole' check (acces in ('ecole', 'classe', 'invitation')),
  classe        text,
  rdv           timestamptz,
  lieu          text check (length(lieu) <= 80),
  a_lire        text check (length(a_lire) <= 160),
  vote          text[] not null default '{}',
  created_at    timestamptz not null default now()
);
create table if not exists public.club_membres (
  club    uuid not null references public.clubs (id) on delete cascade,
  membre  text not null,
  fini    boolean not null default false,
  rejoint timestamptz not null default now(),
  primary key (club, membre)
);
create table if not exists public.club_questions (
  id         uuid primary key default gen_random_uuid(),
  club       uuid not null references public.clubs (id) on delete cascade,
  texte      text not null check (length(texte) between 3 and 300),
  created_at timestamptz not null default now()
);
create table if not exists public.club_reponses (
  id         uuid primary key default gen_random_uuid(),
  question   uuid not null references public.club_questions (id) on delete cascade,
  membre     text not null,
  texte      text not null check (length(texte) between 1 and 500),
  statut     text not null default 'attente' check (statut in ('attente', 'publie', 'refuse')),
  created_at timestamptz not null default now(),
  unique (question, membre)
);
create table if not exists public.club_votes (
  club   uuid not null references public.clubs (id) on delete cascade,
  membre text not null,
  livre  text not null,
  primary key (club, membre)
);
do $$
declare t text;
begin
  foreach t in array array['clubs', 'club_membres', 'club_questions', 'club_reponses', 'club_votes'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);   -- lecture et écriture uniquement par les fonctions ci-dessous
  end loop;
end $$;
-- peut voir le club / peut le gérer
create or replace function public.kiv_club_voit(c public.clubs)
returns boolean language sql stable security definer set search_path = public as $$
  select public.kiv_role() in ('admin', 'bibliothecaire', 'direction')
      or c.animateur = auth.uid()
      or (public.kiv_role() in ('eleve', 'enseignant') and (c.acces = 'ecole'
          or (c.acces = 'classe' and (c.classe = public.kiv_ma_classe() or c.classe = any (public.kiv_classes())))
          or exists (select 1 from public.club_membres cm where cm.club = c.id and cm.membre = public.kiv_membre())));
$$;
create or replace function public.kiv_club_gere(c public.clubs)
returns boolean language sql stable security definer set search_path = public as $$
  select public.kiv_role() in ('admin', 'bibliothecaire') or (public.kiv_role() = 'enseignant' and c.animateur = auth.uid());
$$;
create or replace function public.kiv_clubs()
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', c.id, 'nom', c.nom, 'description', c.description, 'livre', c.livre, 'animateur_nom', c.animateur_nom, 'acces', c.acces, 'classe', c.classe,
    'rdv', c.rdv, 'lieu', c.lieu, 'a_lire', c.a_lire, 'vote', c.vote, 'created_at', c.created_at,
    'membres', (select count(*) from public.club_membres cm where cm.club = c.id),
    'moi', exists (select 1 from public.club_membres cm where cm.club = c.id and cm.membre = public.kiv_membre()),
    'gere', public.kiv_club_gere(c),
    'a_valider', case when public.kiv_club_gere(c) then (select count(*) from public.club_reponses r join public.club_questions q on q.id = r.question where q.club = c.id and r.statut = 'attente') else 0 end
  ) order by c.created_at desc), '[]'::jsonb)
  from public.clubs c where public.kiv_club_voit(c);
$$;
create or replace function public.kiv_club(cid uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c public.clubs; g boolean; me text := public.kiv_membre();
begin
  select * into c from public.clubs where id = cid;
  if not found or not public.kiv_club_voit(c) then raise exception 'Club introuvable.'; end if;
  g := public.kiv_club_gere(c);
  return jsonb_build_object(
    'membres', coalesce((select jsonb_agg(jsonb_build_object('membre', cm.membre, 'nom', public.kiv_nom_court(m.data ->> 'nom'), 'classe', m.data ->> 'classe',
        'avatar', (select p.avatar from public.profiles p where p.membre_id = cm.membre), 'fini', cm.fini, 'moi', cm.membre = me) order by cm.rejoint)
      from public.club_membres cm left join public.membres m on m.id = cm.membre where cm.club = cid), '[]'::jsonb),
    'questions', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'texte', q.texte, 'le', q.created_at,
        'reponses', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'nom', public.kiv_nom_court(m.data ->> 'nom'), 'texte', r.texte, 'statut', r.statut, 'moi', r.membre = me) order by r.created_at)
          from public.club_reponses r left join public.membres m on m.id = r.membre
          where r.question = q.id and (r.statut = 'publie' or r.membre = me or g)), '[]'::jsonb)) order by q.created_at desc)
      from public.club_questions q where q.club = cid), '[]'::jsonb),
    'votes', coalesce((select jsonb_object_agg(v.livre, v.nb) from (select livre, count(*) as nb from public.club_votes where club = cid group by livre) v), '{}'::jsonb),
    'mon_vote', (select livre from public.club_votes where club = cid and membre = me));
end;
$$;
create or replace function public.kiv_club_enregistrer(cid uuid, nom text, description text, livre text, acces text, classe text, rdv timestamptz, lieu text, a_lire text, vote text[])
returns uuid language plpgsql security definer set search_path = public as $$
declare c public.clubs; nid uuid; me text := public.kiv_role();
begin
  if me not in ('enseignant', 'admin', 'bibliothecaire') then raise exception 'Seuls les enseignants et la bibliothèque créent des clubs.'; end if;
  if acces = 'classe' and me = 'enseignant' and not (classe = any (public.kiv_classes())) then raise exception 'Choisissez une de vos classes.'; end if;
  if acces = 'classe' and coalesce(classe, '') = '' then raise exception 'Choisissez la classe du club.'; end if;
  if cid is null then
    insert into public.clubs (nom, description, livre, acces, classe, rdv, lieu, a_lire, vote, animateur_nom)
    values (trim(nom), nullif(trim(description), ''), nullif(livre, ''), acces, case when acces = 'classe' then classe end, rdv, nullif(trim(lieu), ''), nullif(trim(a_lire), ''),
            coalesce(vote[1:3], '{}'), (select p.nom from public.profiles p where p.id = auth.uid()))
    returning id into nid;
    return nid;
  end if;
  select * into c from public.clubs where id = cid;
  if not found or not public.kiv_club_gere(c) then raise exception 'Vous ne pouvez pas modifier ce club.'; end if;
  if c.livre is distinct from nullif(livre, '') then update public.club_membres set fini = false where club = cid; end if;
  if c.vote is distinct from coalesce(vote[1:3], '{}') then delete from public.club_votes where club = cid; end if;
  update public.clubs set nom = trim(kiv_club_enregistrer.nom), description = nullif(trim(kiv_club_enregistrer.description), ''), livre = nullif(kiv_club_enregistrer.livre, ''),
    acces = kiv_club_enregistrer.acces, classe = case when kiv_club_enregistrer.acces = 'classe' then kiv_club_enregistrer.classe end, rdv = kiv_club_enregistrer.rdv,
    lieu = nullif(trim(kiv_club_enregistrer.lieu), ''), a_lire = nullif(trim(kiv_club_enregistrer.a_lire), ''), vote = coalesce(kiv_club_enregistrer.vote[1:3], '{}')
  where id = cid;
  return cid;
end;
$$;
create or replace function public.kiv_club_supprimer(cid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs;
begin
  select * into c from public.clubs where id = cid;
  if not found or not public.kiv_club_gere(c) then raise exception 'Vous ne pouvez pas supprimer ce club.'; end if;
  delete from public.clubs where id = cid;
end;
$$;
-- rejoindre ou quitter (l'élève) ; inviter ou retirer (l'animateur)
create or replace function public.kiv_club_rejoindre(cid uuid, oui boolean)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs; m text := public.kiv_membre();
begin
  select * into c from public.clubs where id = cid;
  if not found or m is null or not public.kiv_club_voit(c) then raise exception 'Club introuvable.'; end if;
  if not oui then delete from public.club_membres where club = cid and membre = m; delete from public.club_votes where club = cid and membre = m; return; end if;
  if c.acces = 'invitation' then raise exception 'Ce club est sur invitation : demande à son animateur.'; end if;
  insert into public.club_membres (club, membre) values (cid, m) on conflict do nothing;
end;
$$;
create or replace function public.kiv_club_inviter(cid uuid, membre text, oui boolean)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs;
begin
  select * into c from public.clubs where id = cid;
  if not found or not public.kiv_club_gere(c) then raise exception 'Vous ne gérez pas ce club.'; end if;
  if not exists (select 1 from public.membres where id = membre) then raise exception 'Membre introuvable.'; end if;
  if oui then insert into public.club_membres (club, membre) values (cid, kiv_club_inviter.membre) on conflict do nothing;
  else delete from public.club_membres cm where cm.club = cid and cm.membre = kiv_club_inviter.membre; end if;
end;
$$;
create or replace function public.kiv_club_fini(cid uuid, oui boolean)
returns void language sql security definer set search_path = public as $$
  update public.club_membres set fini = oui where club = cid and membre = public.kiv_membre();
$$;
create or replace function public.kiv_club_question(cid uuid, texte text)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs;
begin
  select * into c from public.clubs where id = cid;
  if not found or not public.kiv_club_gere(c) then raise exception 'Seul l''animateur pose les questions.'; end if;
  insert into public.club_questions (club, texte) values (cid, trim(texte));
end;
$$;
create or replace function public.kiv_club_repondre(qid uuid, texte text)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs; m text := public.kiv_membre();
begin
  select cl.* into c from public.clubs cl join public.club_questions q on q.club = cl.id where q.id = qid;
  if not found or m is null then raise exception 'Question introuvable.'; end if;
  if not exists (select 1 from public.club_membres where club = c.id and membre = m) and not public.kiv_club_gere(c) then raise exception 'Rejoins d''abord le club.'; end if;
  insert into public.club_reponses as r (question, membre, texte, statut)
  values (qid, m, left(trim(texte), 500), case when public.kiv_club_gere(c) then 'publie' else 'attente' end)
  on conflict (question, membre) do update set texte = excluded.texte, statut = excluded.statut, created_at = now();
end;
$$;
create or replace function public.kiv_club_moderer(rid uuid, publier boolean)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs;
begin
  select cl.* into c from public.clubs cl join public.club_questions q on q.club = cl.id join public.club_reponses r on r.question = q.id where r.id = rid;
  if not found or not public.kiv_club_gere(c) then raise exception 'Vous ne gérez pas ce club.'; end if;
  update public.club_reponses set statut = case when publier then 'publie' else 'refuse' end where id = rid;
end;
$$;
create or replace function public.kiv_club_voter(cid uuid, livre text)
returns void language plpgsql security definer set search_path = public as $$
declare c public.clubs; m text := public.kiv_membre();
begin
  select * into c from public.clubs where id = cid;
  if not found or not exists (select 1 from public.club_membres where club = cid and membre = m) then raise exception 'Rejoins d''abord le club pour voter.'; end if;
  if not (livre = any (c.vote)) then raise exception 'Ce livre ne fait pas partie du vote.'; end if;
  insert into public.club_votes (club, membre, livre) values (cid, m, kiv_club_voter.livre)
  on conflict (club, membre) do update set livre = excluded.livre;
end;
$$;
revoke execute on function public.kiv_club_voit(public.clubs), public.kiv_club_gere(public.clubs) from public, anon, authenticated;
revoke execute on function public.kiv_clubs(), public.kiv_club(uuid), public.kiv_club_enregistrer(uuid, text, text, text, text, text, timestamptz, text, text, text[]),
  public.kiv_club_supprimer(uuid), public.kiv_club_rejoindre(uuid, boolean), public.kiv_club_inviter(uuid, text, boolean), public.kiv_club_fini(uuid, boolean),
  public.kiv_club_question(uuid, text), public.kiv_club_repondre(uuid, text), public.kiv_club_moderer(uuid, boolean), public.kiv_club_voter(uuid, text) from public, anon;
grant execute on function public.kiv_clubs(), public.kiv_club(uuid), public.kiv_club_enregistrer(uuid, text, text, text, text, text, timestamptz, text, text, text[]),
  public.kiv_club_supprimer(uuid), public.kiv_club_rejoindre(uuid, boolean), public.kiv_club_inviter(uuid, text, boolean), public.kiv_club_fini(uuid, boolean),
  public.kiv_club_question(uuid, text), public.kiv_club_repondre(uuid, text), public.kiv_club_moderer(uuid, boolean), public.kiv_club_voter(uuid, text) to authenticated;

-- ---------------------------------------------------------------- import des élèves (Excel)
-- lignes : [{ "id": "A012" (fiche existante) ou absent (nouvelle fiche), "nom", "classe", "email", "sexe" }]
create or replace function public.kiv_import_membres(lignes jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare l jsonb; n int := 0; u int := 0; r int;
begin
  if public.kiv_role() not in ('admin', 'bibliothecaire') then raise exception 'Votre rôle ne permet pas cette modification.'; end if;
  perform pg_advisory_xact_lock(4243);
  r := coalesce((select max(public.kiv_rang(id)) from public.membres), 0);
  for l in select * from jsonb_array_elements(coalesce(lignes, '[]'::jsonb)) loop
    if coalesce(trim(l ->> 'nom'), '') = '' then continue; end if;
    if l ? 'id' and exists (select 1 from public.membres where id = l ->> 'id') then
      update public.membres set data = data
        || jsonb_build_object('nom', left(trim(l ->> 'nom'), 80))
        || case when coalesce(trim(l ->> 'classe'), '') <> '' then jsonb_build_object('classe', left(trim(l ->> 'classe'), 60)) else '{}'::jsonb end
        || case when coalesce(trim(l ->> 'email'), '') <> '' then jsonb_build_object('email', lower(left(trim(l ->> 'email'), 120))) else '{}'::jsonb end
        || case when coalesce(trim(l ->> 'sexe'), '') <> '' then jsonb_build_object('sexe', left(trim(l ->> 'sexe'), 1)) else '{}'::jsonb end
      where id = l ->> 'id';
      u := u + 1;
    else
      r := r + 1;
      insert into public.membres (id, data) values (public.kiv_numero(r), jsonb_build_object('nom', left(trim(l ->> 'nom'), 80), 'type', 'Élève',
        'classe', left(coalesce(trim(l ->> 'classe'), ''), 60), 'email', lower(left(coalesce(trim(l ->> 'email'), ''), 120)), 'sexe', left(coalesce(trim(l ->> 'sexe'), ''), 1),
        'inscription', to_char(current_date, 'YYYY-MM-DD')));
      n := n + 1;
    end if;
  end loop;
  return jsonb_build_object('crees', n, 'modifies', u);
end;
$$;
revoke execute on function public.kiv_import_membres(jsonb) from public, anon;
grant execute on function public.kiv_import_membres(jsonb) to authenticated;

-- ---------------------------------------------------------------- rappels de retard pour un agent n8n
-- L'administrateur crée une clé dans Réglages ; n8n appelle kiv_retards_n8n avec cette clé.
create table if not exists public.kiv_secrets (id text primary key, valeur text not null, created_at timestamptz not null default now());
alter table public.kiv_secrets enable row level security;
revoke all on public.kiv_secrets from anon, authenticated;
create or replace function public.kiv_cle_n8n(nouvelle boolean default false)
returns text language plpgsql security definer set search_path = public as $$
declare k text;
begin
  if public.kiv_role() <> 'admin' then raise exception 'Réservé à l''administrateur.'; end if;
  if nouvelle then
    k := replace(gen_random_uuid()::text || gen_random_uuid()::text, '-', '');
    insert into public.kiv_secrets (id, valeur) values ('n8n', k) on conflict (id) do update set valeur = excluded.valeur, created_at = now();
    return k;
  end if;
  return (select valeur from public.kiv_secrets where id = 'n8n');
end;
$$;
create or replace function public.kiv_retards_n8n(cle text)
returns table (membre text, nom text, classe text, email text, livre text, titre text, emprunte_le date, a_rendre_le date, jours_retard int, amende int)
language plpgsql stable security definer set search_path = public as $$
declare k text := (select valeur from public.kiv_secrets where id = 'n8n'); p jsonb := coalesce((select data from public.reglages where id = 'params'), '{}');
begin
  if k is null or cle is null or cle <> k then raise exception 'Clé invalide.'; end if;
  return query
  with e as (
    select x.data ->> 'membre' as m, x.data ->> 'livre' as l, (x.data ->> 'date')::date as d,
           coalesce(nullif(x.data ->> 'prevu', '')::date, (x.data ->> 'date')::date + coalesce((p ->> 'duree')::int, 14)) as prevu
    from public.emprunts x where (x.data ->> 'retour') is null
  )
  select e.m, mb.data ->> 'nom', mb.data ->> 'classe',
         coalesce((select pr.email from public.profiles pr where pr.membre_id = e.m), nullif(mb.data ->> 'email', '')),
         e.l, lv.data ->> 'titre', e.d, e.prevu, (current_date - e.prevu)::int, ((current_date - e.prevu) * coalesce((p ->> 'amende')::int, 0))::int
  from e left join public.membres mb on mb.id = e.m left join public.livres lv on lv.id = e.l
  where e.prevu < current_date
  order by mb.data ->> 'classe', mb.data ->> 'nom';
end;
$$;
revoke execute on function public.kiv_cle_n8n(boolean), public.kiv_retards_n8n(text) from public;
grant execute on function public.kiv_cle_n8n(boolean) to authenticated;
grant execute on function public.kiv_retards_n8n(text) to anon, authenticated;

-- ---------------------------------------------------------------- assistant bibliothécaire IA
-- nombre de questions par personne et par jour (10 par défaut, réglable dans Réglages)
create table if not exists public.assistant_log (
  uid  uuid not null,
  jour date not null default current_date,
  nb   int  not null default 0,
  primary key (uid, jour)
);
alter table public.assistant_log enable row level security;
revoke all on public.assistant_log from anon, authenticated;
create or replace function public.kiv_assistant_quota()
returns int language plpgsql security definer set search_path = public as $$
declare lim int := coalesce((select (data ->> 'assistantMax')::int from public.reglages where id = 'params'), 10); n int;
begin
  if public.kiv_role() not in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve') then raise exception 'Connectez-vous d''abord.'; end if;
  insert into public.assistant_log as a (uid, jour, nb) values (auth.uid(), current_date, 1)
  on conflict (uid, jour) do update set nb = a.nb + 1 returning nb into n;
  if n > lim then raise exception 'Tu as posé tes % questions du jour. Reviens demain !', lim; end if;
  return lim - n;
end;
$$;
-- ce que l'assistant sait du lecteur : ses lectures et ses genres préférés
create or replace function public.kiv_assistant_profil()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'prenom', split_part((select nom from public.profiles where id = auth.uid()), ' ', 1),
    'classe', public.kiv_ma_classe(),
    'genres', (select genres from public.profiles where id = auth.uid()),
    'lus', coalesce((select jsonb_agg(distinct e.data ->> 'livre') from public.emprunts e where e.data ->> 'membre' = public.kiv_membre()), '[]'::jsonb));
$$;
revoke execute on function public.kiv_assistant_quota(), public.kiv_assistant_profil() from public, anon;
grant execute on function public.kiv_assistant_quota(), public.kiv_assistant_profil() to authenticated;

-- ---------------------------------------------------------------- borne publique (sans compte)
-- Seulement le catalogue et le nombre d'exemplaires disponibles : aucun nom, aucun emprunt.
create or replace function public.kiv_catalogue_public()
returns table (id text, titre text, auteur text, categorie text, rayon text, annee text, resume text, cover text, ex int, dispo int)
language sql stable security definer set search_path = public as $$
  select l.id, l.data ->> 'titre', l.data ->> 'auteur', l.data ->> 'categorie', l.data ->> 'rayon', l.data ->> 'annee',
         left(l.data ->> 'resume', 400), l.data ->> 'cover', coalesce((l.data ->> 'ex')::int, 0),
         greatest(0, coalesce((l.data ->> 'ex')::int, 0)
           - (select count(*)::int from public.emprunts e where e.data ->> 'livre' = l.id and (e.data ->> 'retour') is null)
           - (select count(*)::int from public.reservations r where r.livre = l.id and r.statut = 'prete' and r.expire_le >= current_date))
  from public.livres l
  order by l.data ->> 'titre';
$$;
revoke execute on function public.kiv_catalogue_public() from public;
grant execute on function public.kiv_catalogue_public() to anon, authenticated;

-- ---------------------------------------------------------------- couvertures des livres
-- Copie réduite (environ 15 Ko) de chaque couverture, gardée dans Supabase :
-- elle reste affichée même si Google Livres ou Open Library la retire.
-- Lecture publique (comme le catalogue), ajout et suppression par l'administrateur et la bibliothécaire.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('couvertures', 'couvertures', true, 400000, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
drop policy if exists "couvertures : ajout" on storage.objects;
create policy "couvertures : ajout" on storage.objects for insert to authenticated
  with check (bucket_id = 'couvertures' and public.kiv_role() in ('admin', 'bibliothecaire'));
drop policy if exists "couvertures : lecture" on storage.objects;
create policy "couvertures : lecture" on storage.objects for select to authenticated
  using (bucket_id = 'couvertures' and public.kiv_role() in ('admin', 'bibliothecaire'));
drop policy if exists "couvertures : suppression" on storage.objects;
create policy "couvertures : suppression" on storage.objects for delete to authenticated
  using (bucket_id = 'couvertures' and public.kiv_role() in ('admin', 'bibliothecaire'));

-- ---------------------------------------------------------------- temps réel
-- Les écrans de tous les utilisateurs se mettent à jour instantanément.
do $$
declare t text;
begin
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages', 'profiles', 'reservations', 'avis', 'consignes', 'consigne_vues', 'objectifs_classe'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
