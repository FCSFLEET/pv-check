# PV Check — FCS Fleet Services

Application web de rédaction de procès-verbaux (PV) pour les interventions sur véhicules :
constat contradictoire rempli sur mobile avec le client, véhicule sous les yeux, puis génération
d'un PDF signé.

🔗 **Production :** https://pv-check-fcsfleet.netlify.app/

---

## Fonctionnement

L'application est une **PWA mono-fichier** : tout (HTML, CSS, JavaScript, icônes, schémas des
véhicules) tient dans `index.html`. Aucune étape de build, aucune dépendance à installer.

### Types de PV

| Type | Usage |
|------|-------|
| **PV de récupération** | Constat à la prise en charge du véhicule chez le client |
| **PV de livraison** | Constat à la restitution du véhicule au client |
| **PV check-lavage** | Contrôle après lavage vapeur et prestations atelier |

Chaque type affiche son propre parcours d'étapes (les prestations atelier ne sont demandées que
pour les PV de livraison et de check-lavage).

### Parcours

1. **Informations générales** — client, driver, immatriculation (format `AA-000-BB`), date,
   kilométrage, adresse
2. **État du véhicule** — dommages positionnés au doigt sur les schémas (face avant, face arrière,
   côté gauche, côté droit), avec photo obligatoire pour chaque dommage relevé
3. **Équipements et pneus** — kit sécurité, roue de secours, carte carburant, badge télépéage,
   état des pneus, nombre de clés…
4. **Prestations** — travaux réalisés (selon le type de PV)
5. **Signatures et satisfaction** — signature du client et du driver au doigt, note de la
   prestation sur 5 donnée par le client
6. **PDF** — généré côté navigateur, signatures et photos comprises

### Génération du PDF

Le PDF est construit **entièrement en JavaScript, sans bibliothèque externe** : écriture directe
des objets PDF, polices Helvetica/Helvetica-Bold en `WinAnsiEncoding`, photos recompressées en
JPEG (max 1100 px, qualité 0.55) et schémas véhicule encodés en image indexée Flate pour rester
légers tout en gardant des traits nets. Les marqueurs de dommage sont tracés en vectoriel.

### Stockage

- **Local** — chaque PV est d'abord enregistré dans le `localStorage` de l'appareil. L'application
  reste donc utilisable hors réseau.
- **Centralisé** — si Supabase est configuré, les PV sont aussi poussés dans une base partagée pour
  constituer l'historique de l'équipe. Les PV non synchronisés sont marqués « à envoyer » et
  repartent automatiquement au retour du réseau.

---

## Configuration

Les paramètres se trouvent en haut du bloc `<script>` de `index.html` :

```js
var SUPABASE_URL   = 'https://<votre-projet>.supabase.co';
var SUPABASE_KEY   = '<clé publique : sb_publishable_... ou eyJ...>';
var SUPABASE_TABLE = 'pv';
```

Ces valeurs se récupèrent dans Supabase sous **Project Settings → API**. Si elles sont laissées
vides, l'application bascule en **mode local** : les PV ne sont enregistrés que sur l'appareil et
un bandeau d'avertissement le signale.

Les coordonnées imprimées en en-tête du PDF se règlent juste à côté :

```js
var COMPANY = {
  name: 'FCS Fleet Services',
  addr: '32 rue de Paris 92100 Boulogne-Billancourt',
  tel:  '09.84.52.42.69'
};
```

### Schéma de la base

À exécuter dans l'éditeur SQL de Supabase :

```sql
create table if not exists public.pv (
  id          bigint generated always as identity primary key,
  ref         text        not null unique,
  type        text        not null,
  pv_date     date,
  immat       text,
  client      text,
  driver      text,
  damages     integer     not null default 0,
  note        integer,
  data        jsonb       not null,
  created_at  timestamptz not null default now()
);

create index if not exists pv_created_at_idx on public.pv (created_at desc);
create index if not exists pv_immat_idx      on public.pv (immat);
create index if not exists pv_driver_idx     on public.pv (driver);

alter table public.pv enable row level security;

drop policy if exists "pv_select_equipe" on public.pv;
create policy "pv_select_equipe" on public.pv
  for select to anon, authenticated using (true);

drop policy if exists "pv_insert_equipe" on public.pv;
create policy "pv_insert_equipe" on public.pv
  for insert to anon, authenticated with check (true);

create or replace view public.pv_liste as
  select ref, pv_date, type, immat, client, driver, damages, note, created_at
  from public.pv
  order by created_at desc;
```

Le PV complet est stocké dans la colonne `data` (jsonb) ; les autres colonnes sont extraites pour
permettre le tri et la recherche. La vue `pv_liste` sert aux exports et à la consultation rapide
sans charger les photos.

> **Note :** aucune politique `delete` n'est définie — les PV ne peuvent pas être supprimés depuis
> l'application, par conception.

---

## Développement

Aucun build. Pour travailler en local, servir le dossier :

```bash
python3 -m http.server 8000
```

puis ouvrir http://localhost:8000. Un simple double-clic sur `index.html` fonctionne aussi, mais
passer par un serveur local reproduit mieux les conditions de production (service worker,
permissions caméra).

L'application est pensée **mobile d'abord** : la tester dans les outils développeur en mode
appareil mobile, écran tactile activé, car les schémas de dommages et les signatures reposent sur
les événements tactiles.

## Déploiement

Le site est hébergé sur **Netlify**. `index.html` étant autonome, un déploiement consiste à
publier ce seul fichier à la racine du site.
