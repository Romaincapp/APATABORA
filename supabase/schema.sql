-- =====================================================================
-- Journée APA – inscriptions aux activités
-- À coller dans Supabase > SQL Editor, puis "Run".
-- Le script peut être relancé : il recrée les fonctions et les données
-- de référence (activités, tournantes) sans toucher aux inscriptions.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- Tables ----------------------------------------------------

create table if not exists public.activites (
  id     text primary key,
  nom    text not null,
  lieu   text not null,
  cap    int  not null check (cap > 0),
  ordre  int  not null
);

create table if not exists public.tournantes (
  id     int  primary key,             -- 1 à 15
  debut  time not null,
  fin    time not null,
  demi   text not null                 -- 'Matin' / 'Après-midi'
);

create table if not exists public.beneficiaires (
  id         uuid primary key default gen_random_uuid(),
  nom        text not null check (length(trim(nom)) between 1 and 120),
  groupe     text not null default '' check (length(groupe) <= 120),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.inscriptions (
  beneficiaire_id uuid not null references public.beneficiaires(id) on delete cascade,
  tournante       int  not null references public.tournantes(id),
  activite        text not null references public.activites(id),
  primary key (beneficiaire_id, tournante)   -- une seule activité par tournante
);
create index if not exists inscriptions_creneau on public.inscriptions (tournante, activite);

-- Code d'équipe (stocké haché, jamais lisible depuis la page)
create table if not exists public.config (
  id        int primary key default 1 check (id = 1),
  code_hash text not null
);

-- ---------- Sécurité : aucune lecture/écriture directe ----------------
-- La page passe UNIQUEMENT par les fonctions ci-dessous, qui vérifient
-- le code d'équipe. Les noms des bénéficiaires ne sont donc jamais
-- lisibles avec la seule clé publique.

alter table public.activites     enable row level security;
alter table public.tournantes    enable row level security;
alter table public.beneficiaires enable row level security;
alter table public.inscriptions  enable row level security;
alter table public.config        enable row level security;

drop policy if exists "lecture activites"  on public.activites;
drop policy if exists "lecture tournantes" on public.tournantes;
create policy "lecture activites"  on public.activites  for select to anon, authenticated using (true);
create policy "lecture tournantes" on public.tournantes for select to anon, authenticated using (true);
-- (pas de policy sur beneficiaires / inscriptions / config = accès refusé)

-- ---------- Données de référence -------------------------------------

insert into public.activites (id, nom, lieu, cap, ordre) values
  ('cheveux',    'Soin des cheveux',         'P1',  3,  1),
  ('ongles',     'Soin des ongles',          'P1',  3,  2),
  ('bocaux',     'Customisation de bocaux',  'P1',  6,  3),
  ('mandalas',   'Mandalas',                 'P1', 10,  4),
  ('massage',    'Massage',                  'P1',  4,  5),
  ('parachute',  'Parachute',                'P1', 10,  6),
  ('cirque',     'Cirque assiettes',         'P1',  5,  7),
  ('antistress', 'Balle anti-stress',        'P1',  8,  8),
  ('zumba',      'Zumba',                    'P2', 15,  9),
  ('massacre',   'Jeu de massacre',          'P2',  6, 10),
  ('kinball',    'Kinball',                  'P2', 16, 11),
  ('boccia',     'Boccia',                   'P2',  6, 12),
  ('basket',     'Initiation basket',        'P3', 10, 13),
  ('bowling',    'Bowling',                  'P3',  6, 14),
  ('psychomot',  'Parcours psychomotricité', 'P3',  6, 15),
  ('football',   'Initiation football',      'P3', 10, 16),
  ('flechettes', 'Fléchettes ventouses',     'P3',  5, 17)
on conflict (id) do update
  set nom = excluded.nom, lieu = excluded.lieu, cap = excluded.cap, ordre = excluded.ordre;

insert into public.tournantes (id, debut, fin, demi) values
  ( 1, '09:45', '10:00', 'Matin'),
  ( 2, '10:05', '10:20', 'Matin'),
  ( 3, '10:25', '10:40', 'Matin'),
  ( 4, '10:45', '11:00', 'Matin'),
  ( 5, '11:05', '11:20', 'Matin'),
  ( 6, '11:25', '11:40', 'Matin'),
  ( 7, '11:45', '12:00', 'Matin'),
  ( 8, '12:50', '13:05', 'Après-midi'),
  ( 9, '13:10', '13:25', 'Après-midi'),
  (10, '13:30', '13:45', 'Après-midi'),
  (11, '13:50', '14:05', 'Après-midi'),
  (12, '14:10', '14:25', 'Après-midi'),
  (13, '14:30', '14:45', 'Après-midi'),
  (14, '14:50', '15:05', 'Après-midi'),
  (15, '15:10', '15:25', 'Après-midi')
on conflict (id) do update
  set debut = excluded.debut, fin = excluded.fin, demi = excluded.demi;

-- ---------- Fonctions -------------------------------------------------

create or replace function public._apa_check_code(p_code text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_code is null or not exists (
    select 1 from public.config where code_hash = crypt(p_code, code_hash)
  ) then
    raise exception 'Code d''équipe incorrect.' using errcode = '28000';
  end if;
end $$;

-- Change le code d'équipe. À lancer depuis le SQL Editor uniquement :
--   select public.apa_definir_code('mon-code-secret');
create or replace function public.apa_definir_code(p_nouveau text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into public.config (id, code_hash) values (1, crypt(p_nouveau, gen_salt('bf')))
  on conflict (id) do update set code_hash = excluded.code_hash;
$$;

-- Vérifie le code (écran de connexion de la page).
create or replace function public.apa_connexion(p_code text)
returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._apa_check_code(p_code);
  return true;
end $$;

-- Tout l'état utile à la page : activités, tournantes, bénéficiaires + planning.
create or replace function public.apa_etat(p_code text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  perform public._apa_check_code(p_code);
  return jsonb_build_object(
    'activites', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nom', nom, 'lieu', lieu, 'cap', cap) order by ordre), '[]') from public.activites),
    'tournantes', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'debut', to_char(debut, 'HH24:MI'), 'fin', to_char(fin, 'HH24:MI'), 'demi', demi) order by id), '[]') from public.tournantes),
    'beneficiaires', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', b.id, 'nom', b.nom, 'groupe', b.groupe, 'maj', b.updated_at,
        'plan', coalesce((select jsonb_object_agg(i.tournante::text, i.activite) from public.inscriptions i where i.beneficiaire_id = b.id), '{}'::jsonb)
      ) order by b.nom), '[]')
      from public.beneficiaires b)
  );
end $$;

-- Crée ou modifie un bénéficiaire et son planning, en une seule transaction.
-- p_plan : {"1": "zumba", "4": "kinball", ...}  (tournante -> activité)
-- La capacité est vérifiée SOUS VERROU : deux inscriptions simultanées sur
-- la dernière place ne peuvent pas passer toutes les deux.
create or replace function public.apa_enregistrer(p_code text, p_id uuid, p_nom text, p_groupe text, p_plan jsonb)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v_id     uuid := p_id;
  v_pleins text;
begin
  perform public._apa_check_code(p_code);

  if p_nom is null or length(trim(p_nom)) = 0 then
    raise exception 'Le nom est obligatoire.' using errcode = '22023';
  end if;
  if p_plan is null or jsonb_typeof(p_plan) <> 'object' or p_plan = '{}'::jsonb then
    raise exception 'Choisis au moins une activité.' using errcode = '22023';
  end if;

  -- Verrouille les activités concernées (toujours dans le même ordre, pas d'interblocage).
  perform 1 from public.activites
   where id in (select value from jsonb_each_text(p_plan))
   order by id
   for update;

  if v_id is null then
    insert into public.beneficiaires (nom, groupe) values (trim(p_nom), coalesce(trim(p_groupe), ''))
    returning id into v_id;
  else
    update public.beneficiaires set nom = trim(p_nom), groupe = coalesce(trim(p_groupe), ''), updated_at = now()
     where id = v_id;
    if not found then
      raise exception 'Cette fiche a été supprimée entre-temps.' using errcode = 'P0002';
    end if;
    delete from public.inscriptions where beneficiaire_id = v_id;
  end if;

  insert into public.inscriptions (beneficiaire_id, tournante, activite)
  select v_id, key::int, value from jsonb_each_text(p_plan);

  -- Contrôle de capacité après insertion, toujours sous verrou.
  select string_agg(format('%s (T%s)', a.nom, i.tournante), ', ' order by i.tournante)
    into v_pleins
    from (select tournante, activite, count(*) n from public.inscriptions
           where (tournante, activite) in (select key::int, value from jsonb_each_text(p_plan))
           group by tournante, activite) i
    join public.activites a on a.id = i.activite
   where i.n > a.cap;

  if v_pleins is not null then
    raise exception 'Plus de place pour : %', v_pleins using errcode = 'P0001';  -- annule tout
  end if;

  return v_id;
end $$;

create or replace function public.apa_supprimer(p_code text, p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public._apa_check_code(p_code);
  delete from public.beneficiaires where id = p_id;
end $$;

-- ---------- Droits d'appel --------------------------------------------
revoke all on function public._apa_check_code(text)   from public, anon, authenticated;
revoke all on function public.apa_definir_code(text)  from public, anon, authenticated;
grant execute on function public.apa_connexion(text)                          to anon, authenticated;
grant execute on function public.apa_etat(text)                               to anon, authenticated;
grant execute on function public.apa_enregistrer(text, uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.apa_supprimer(text, uuid)                    to anon, authenticated;

-- ---------- Code d'équipe initial -------------------------------------
-- Défini seulement au premier lancement. Pour le changer ensuite :
--   select public.apa_definir_code('nouveau-code');
-- ⚠ Remplace 'change-moi' par le code à donner aux collègues avant le premier lancement.
do $$ begin
  if not exists (select 1 from public.config) then
    perform public.apa_definir_code('APATABORA');
  end if;
end $$;
