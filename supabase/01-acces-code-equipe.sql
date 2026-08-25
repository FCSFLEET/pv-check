-- =========================================================
--  PV Check — accès par code d'équipe   (étape 1 sur 2)
--
--  À EXÉCUTER MAINTENANT, avant de déployer la nouvelle version
--  du site. Ce script est purement additif : il n'enlève aucun
--  droit existant, donc la version actuellement en ligne
--  continue de fonctionner pendant la bascule.
--
--  Supabase > SQL Editor > New query > coller > Run
-- =========================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------
-- 1. Où le code est rangé : un schéma privé, que l'API
--    PostgREST n'expose pas (elle ne publie que « public »).
-- ---------------------------------------------------------
create schema if not exists prive;
revoke all on schema prive from anon, authenticated;

create table if not exists prive.acces (
  id        smallint primary key default 1,
  code_hash text not null,
  maj_le    timestamptz not null default now(),
  constraint acces_ligne_unique check (id = 1)
);

-- ---------------------------------------------------------
-- 2. Définir ou changer le code.
--    Le code n'est jamais stocké en clair : seul son
--    empreinte bcrypt est conservée.
-- ---------------------------------------------------------
create or replace function prive.definir_code(p_code text)
returns void
language plpgsql
security definer
set search_path = prive, extensions, public, pg_temp
as $$
begin
  if length(coalesce(p_code, '')) < 4 then
    raise exception 'code trop court : 4 caractères minimum';
  end if;
  insert into prive.acces (id, code_hash)
  values (1, crypt(p_code, gen_salt('bf')))
  on conflict (id) do update
    set code_hash = excluded.code_hash, maj_le = now();
end;
$$;

revoke all on function prive.definir_code(text) from public;

-- ---------------------------------------------------------
-- 3. Vérification interne du code
-- ---------------------------------------------------------
create or replace function prive.code_ok(p_code text)
returns boolean
language sql
stable
security definer
set search_path = prive, extensions, public, pg_temp
as $$
  select exists (
    select 1 from prive.acces
    where id = 1 and code_hash = crypt(coalesce(p_code, ''), code_hash)
  );
$$;

revoke all on function prive.code_ok(text) from public;

-- ---------------------------------------------------------
-- 4. Enregistrer un PV — seul point d'écriture de l'appli
-- ---------------------------------------------------------
create or replace function public.pv_enregistrer(p_code text, p_row jsonb)
returns void
language plpgsql
security definer
set search_path = public, prive, extensions, pg_temp
as $$
begin
  if not prive.code_ok(p_code) then
    raise exception 'code_invalide' using errcode = '28000';
  end if;

  insert into public.pv (ref, type, pv_date, immat, client, driver, damages, note, data)
  values (
    p_row->>'ref',
    p_row->>'type',
    nullif(p_row->>'pv_date', '')::date,
    p_row->>'immat',
    p_row->>'client',
    p_row->>'driver',
    coalesce((p_row->>'damages')::int, 0),
    nullif(p_row->>'note', '')::int,
    p_row->'data'
  )
  on conflict (ref) do nothing;   -- PV déjà envoyé : rien à refaire
end;
$$;

-- ---------------------------------------------------------
-- 5. Lister les PV de l'équipe — seul point de lecture
-- ---------------------------------------------------------
create or replace function public.pv_lister(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, prive, extensions, pg_temp
as $$
declare v jsonb;
begin
  if not prive.code_ok(p_code) then
    raise exception 'code_invalide' using errcode = '28000';
  end if;

  select coalesce(jsonb_agg(t.data order by t.created_at desc), '[]'::jsonb)
  into v
  from (select data, created_at from public.pv order by created_at desc limit 400) t;

  return v;
end;
$$;

-- ---------------------------------------------------------
-- 6. Qui peut appeler quoi
-- ---------------------------------------------------------
revoke all on function public.pv_enregistrer(text, jsonb) from public;
revoke all on function public.pv_lister(text)             from public;
grant execute on function public.pv_enregistrer(text, jsonb) to anon, authenticated;
grant execute on function public.pv_lister(text)             to anon, authenticated;

-- =========================================================
--  ENFIN : choisissez votre code.
--  Remplacez la valeur ci-dessous, exécutez cette ligne,
--  et ne l'enregistrez nulle part — ce fichier est versionné.
-- =========================================================
-- select prive.definir_code('CHANGEZ-MOI');
