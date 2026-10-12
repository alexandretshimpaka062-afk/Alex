-- =====================================================================
-- Kivuthèque — base de données Supabase
-- À exécuter une seule fois : Supabase › SQL Editor › New query › coller › Run.
-- Le script peut être relancé sans risque (il ne supprime aucune donnée).
-- =====================================================================

-- ---------------------------------------------------------------- rôles
-- admin          : tout, y compris la gestion des comptes et les réglages
-- bibliothecaire : livres, membres, emprunts (lecture des fournitures)
-- fournitures    : articles et mouvements de stock (lecture de la bibliothèque)
-- consultation   : lecture seule
-- en_attente     : compte créé, pas encore validé par un administrateur
-- desactive      : accès retiré
create table if not exists public.profiles (
  id         uuid primary key references auth.users (id) on delete cascade,
  email      text,
  nom        text,
  role       text not null default 'en_attente'
             check (role in ('admin', 'bibliothecaire', 'fournitures', 'consultation', 'en_attente', 'desactive')),
  created_at timestamptz not null default now()
);

-- rôle de la personne connectée (security definer : évite la récursion des règles)
create or replace function public.kiv_role()
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select role from public.profiles where id = auth.uid()), 'aucun');
$$;

-- chaque inscription crée un profil ; la toute première personne devient administrateur
create or replace function public.kiv_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform pg_advisory_xact_lock(4242);
  insert into public.profiles (id, email, nom, role)
  values (
    new.id,
    new.email,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'nom'), ''), split_part(new.email, '@', 1)),
    case when exists (select 1 from public.profiles where role = 'admin') then 'en_attente' else 'admin' end
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists kiv_on_auth_user_created on auth.users;
create trigger kiv_on_auth_user_created
  after insert on auth.users
  for each row execute function public.kiv_new_user();

-- changement de rôle : administrateurs uniquement, et jamais le dernier administrateur
create or replace function public.kiv_set_role(target uuid, new_role text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.kiv_role() <> 'admin' then
    raise exception 'Seul un administrateur peut modifier les rôles.';
  end if;
  if new_role not in ('admin', 'bibliothecaire', 'fournitures', 'consultation', 'en_attente', 'desactive') then
    raise exception 'Rôle inconnu : %', new_role;
  end if;
  if new_role <> 'admin'
     and (select role from public.profiles where id = target) = 'admin'
     and (select count(*) from public.profiles where role = 'admin') <= 1 then
    raise exception 'Il faut garder au moins un administrateur.';
  end if;
  update public.profiles set role = new_role where id = target;
end;
$$;

alter table public.profiles enable row level security;
drop policy if exists "profil : lecture" on public.profiles;
create policy "profil : lecture" on public.profiles
  for select to authenticated using (id = auth.uid() or public.kiv_role() = 'admin');
-- aucune règle d'écriture directe : les rôles changent uniquement via kiv_set_role()
revoke insert, update, delete on public.profiles from anon, authenticated;
grant execute on function public.kiv_set_role(uuid, text) to authenticated;
grant execute on function public.kiv_role() to authenticated;

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

-- règles d'accès : lecture pour tous les comptes validés, écriture selon le rôle
do $$
declare
  t text;
  writers text;
begin
  foreach t in array array['livres', 'membres', 'emprunts', 'fournitures', 'mouvements', 'reglages'] loop
    writers := case
      when t in ('livres', 'membres', 'emprunts') then '''admin'', ''bibliothecaire'''
      when t in ('fournitures', 'mouvements') then '''admin'', ''fournitures'''
      else '''admin'''
    end;
    execute format('drop policy if exists "lecture" on public.%I', t);
    execute format('create policy "lecture" on public.%I for select to authenticated
      using (public.kiv_role() in (''admin'', ''bibliothecaire'', ''fournitures'', ''consultation''))', t);
    execute format('drop policy if exists "ajout" on public.%I', t);
    execute format('create policy "ajout" on public.%I for insert to authenticated with check (public.kiv_role() in (%s))', t, writers);
    execute format('drop policy if exists "modification" on public.%I', t);
    execute format('create policy "modification" on public.%I for update to authenticated
      using (public.kiv_role() in (%s)) with check (public.kiv_role() in (%s))', t, writers, writers);
    execute format('drop policy if exists "suppression" on public.%I', t);
    execute format('create policy "suppression" on public.%I for delete to authenticated using (public.kiv_role() in (%s))', t, writers);
  end loop;
end $$;

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
