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

L'accès à la base partagée est protégé par un **code d'équipe**, saisi une seule fois par appareil
(voir « Accès » ci-dessous). Sans code, l'application reste pleinement utilisable : le PV se rédige,
le PDF se génère, et l'envoi part dès que le code est renseigné.

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

### Accès : le code d'équipe

L'application est publique — n'importe qui peut ouvrir le lien, et la clé Supabase est lisible dans
le code source, comme toute clé publiable. Ce qui protège la base, c'est un **code d'équipe** que le
driver saisit à sa première ouverture et que son appareil mémorise ensuite définitivement. Pas de
compte, pas de mot de passe individuel, rien à administrer.

L'application n'accède donc plus directement à la table `pv`. Elle appelle deux fonctions
`security definer` qui vérifient le code avant d'agir :

| Fonction | Rôle |
|----------|------|
| `public.pv_enregistrer(p_code, p_row)` | enregistre un PV (les doublons sont ignorés) |
| `public.pv_lister(p_code)` | renvoie les 400 derniers PV de l'équipe |

Le code n'est **jamais** dans `index.html` : il est tapé par le driver et conservé dans le
`localStorage` de son téléphone. En base, seule son empreinte bcrypt est stockée, dans le schéma
`prive` que PostgREST n'expose pas.

Pour définir ou changer le code :

```sql
select prive.definir_code('nouveau-code');
```

Les appareils qui ont l'ancien code se le verront refuser et le redemanderont automatiquement.
Pour vérifier qu'un code est le bon : `select prive.code_ok('le-code');`

### Schéma de la base

Les scripts se trouvent dans [`supabase/`](supabase/) et **doivent être exécutés dans cet ordre** :

1. [`01-acces-code-equipe.sql`](supabase/01-acces-code-equipe.sql) — à passer **avant** de déployer.
   Purement additif : la version en ligne continue de tourner pendant la bascule.
2. [`02-fermer-insertion-anonyme.sql`](supabase/02-fermer-insertion-anonyme.sql) — à passer
   **après** le déploiement, une fois qu'un vrai PV s'est bien enregistré. Ferme l'insertion directe.

La table elle-même :

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
```

Le PV complet est stocké dans la colonne `data` (jsonb) ; les autres colonnes sont extraites pour
permettre le tri et la recherche.

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
