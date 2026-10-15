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

-- chaque inscription crée un profil ; la toute première personne devient administrateur
create or replace function public.kiv_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare m jsonb := coalesce(new.raw_user_meta_data, '{}');
begin
  perform pg_advisory_xact_lock(4242);
  insert into public.profiles (id, email, nom, role, profil, classe)
  values (
    new.id,
    new.email,
    left(coalesce(nullif(trim(m ->> 'nom'), ''), nullif(trim(m ->> 'full_name'), ''), nullif(trim(m ->> 'name'), ''), split_part(new.email, '@', 1)), 80),
    case when exists (select 1 from public.profiles where role = 'admin') then 'en_attente' else 'admin' end,
    case when m ->> 'profil' in ('eleve', 'enseignant', 'personnel') then m ->> 'profil' end,
    left(nullif(trim(m ->> 'classe'), ''), 60)
  )
  on conflict (id) do nothing;
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
-- compléter sa demande (inscription avec Google : profil et classe)
create or replace function public.kiv_ma_demande(profil text, classe text, nom text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() <> 'en_attente' then raise exception 'Votre compte est déjà validé.'; end if;
  if profil not in ('eleve', 'enseignant', 'personnel') then raise exception 'Profil inconnu.'; end if;
  update public.profiles set
    profil = kiv_ma_demande.profil,
    classe = left(nullif(trim(kiv_ma_demande.classe), ''), 60),
    nom    = coalesce(left(nullif(trim(kiv_ma_demande.nom), ''), 80), profiles.nom)
  where id = auth.uid();
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
  public.kiv_ma_demande(text, text, text), public.kiv_retirer_photo(uuid) from public, anon;
grant execute on function public.kiv_valider(uuid, text, text), public.kiv_set_role(uuid, text), public.kiv_mon_profil(text, text),
  public.kiv_ma_demande(text, text, text), public.kiv_retirer_photo(uuid), public.kiv_role(), public.kiv_membre(), public.kiv_classes() to authenticated;

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

-- ---------------------------------------------------------------- disponibilité des livres
-- un élève ne voit pas les emprunts des autres : on lui donne seulement le nombre d'exemplaires sortis
create or replace function public.kiv_dispo()
returns table (livre text, sortis int) language sql stable security definer set search_path = public as $$
  select data ->> 'livre', count(*)::int from public.emprunts
  where (data ->> 'retour') is null
    and public.kiv_role() in ('admin', 'bibliothecaire', 'fournitures', 'direction', 'enseignant', 'eleve')
  group by 1;
$$;
revoke execute on function public.kiv_dispo() from public, anon;
grant execute on function public.kiv_dispo() to authenticated;

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
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages', 'profiles'] loop
    begin
      execute format('alter publication supabase_realtime add table public.%I', t);
    exception when duplicate_object then null;
    end;
  end loop;
end $$;
