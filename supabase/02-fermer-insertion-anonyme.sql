-- =========================================================
--  PV Check — accès par code d'équipe   (étape 2 sur 2)
--
--  ⚠️  À EXÉCUTER SEULEMENT APRÈS avoir déployé la nouvelle
--      version du site sur Netlify ET vérifié qu'un PV
--      s'enregistre bien avec le code.
--
--  Tant que cette étape n'est pas faite, n'importe qui peut
--  encore insérer de faux PV. Une fois faite, l'insertion
--  directe est fermée : tout passe par pv_enregistrer(),
--  qui exige le code.
-- =========================================================

drop policy if exists "pv_insert_equipe" on public.pv;

-- Vérification : la requête ne doit plus renvoyer aucune ligne.
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'pv';
