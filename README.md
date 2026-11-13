# APATABORA

Inscriptions des bénéficiaires aux activités de la **Journée APA du 17 novembre**
(17 activités, 15 tournantes de 15 minutes et 5 minutes de battement).

- `site/index.html` : la page d'inscription (un seul fichier, sans dépendance).
- `supabase/schema.sql` : la base de données (tables, sécurité, contrôle des places).
- `.github/workflows/deploy.yml` : publication automatique sur GitHub Pages.

## Mise en place (une seule fois)

### 1. Base de données Supabase

1. Sur https://supabase.com, clique sur **New project** (le plan gratuit suffit, région EU).
2. Dans Supabase : **SQL Editor** → **New query** → colle `supabase/schema.sql` → **Run**.
3. Définis le **code d'équipe** (pour les éducateurs) et le **code organisateur** (pour toi
   seul, sert à déverrouiller), toujours dans le SQL Editor, jamais dans un fichier du dépôt :
   ```sql
   select public.apa_definir_code('code-equipe');
   select public.apa_definir_code_admin('code-organisateur');
   ```
4. Charge les institutions et leurs participants avec le fichier
   `institutions-participants.sql`. Ce fichier n'est **pas** dans le dépôt, car il contient
   des noms : garde-le en local. Il peut être relancé sans créer de doublons.

### 2. Configuration GitHub

1. Dans le dépôt : **Settings → Pages → Build and deployment → Source : GitHub Actions**.
2. **Settings → Secrets and variables → Actions → onglet Variables → New repository variable** :
   - `SUPABASE_URL` : le *Project URL* (Supabase → Project Settings → API)
   - `SUPABASE_KEY` : la clé **anon** / **publishable** (jamais `service_role` / `secret`)
3. **Actions → Déployer la page d'inscription → Run workflow**.
   L'adresse de la page s'affiche à la fin : `https://romaincapp.github.io/APATABORA/`.

Chaque modification de `site/` poussée sur `main` redéploie la page automatiquement.

La clé publique sera visible dans la page, c'est normal : sans le code d'équipe, elle ne
permet ni de lire les noms ni d'écrire.

## Utilisation par les éducateurs

Onglet **Par institution** : l'éducateur choisit son institution, et ses participants
s'affichent en tableau (une ligne par participant, une colonne par tournante).

- Il choisit une activité ou **Pause / repos** dans chaque case. Les places restantes
  s'affichent dans chaque menu, et une activité complète ne peut pas être choisie.
- **Remplir automatiquement les cases vides** propose un planning complet qui respecte
  les places et évite de refaire la même activité. Chaque nouveau clic (**Proposer une
  autre variante**) tire une autre répartition. Les cases proposées ont une bordure bleue,
  et les cases choisies à la main ne bougent pas. **Tout vider** repart de zéro (rien n'est
  effacé tant qu'on n'a pas enregistré).
- **Contrôles anti-oubli** : les cases vides sont en rouge, les activités faites deux fois
  sont en orange, et le nombre de participants est comparé au nombre annoncé.
- Les noms sont modifiables (ex. remplacer « Participant 3 » par le vrai nom), et on
  peut ajouter ou retirer un participant.
- **Enregistrer** envoie toute l'institution d'un coup. Si une place a été prise
  entre-temps, ou si un collègue a modifié la même fiche, rien n'est enregistré et la page
  explique quoi corriger.

**Téléchargement et verrouillage** : **Télécharger et verrouiller (PDF)** demande une
confirmation, puis verrouille le planning de l'institution et télécharge le PDF (vue
d'ensemble, « où sont les participants », une fiche par participant). Une fois verrouillé,
plus personne ne peut modifier, ajouter ou supprimer un participant de cette institution :
c'est contrôlé par la base, pas seulement par la page. Le PDF reste téléchargeable.
Seul l'organisateur peut déverrouiller : bouton **Déverrouiller (organisateur)** et code
organisateur.

Onglet **Inscription individuelle** : pour une personne seule ou un ajout de dernière
minute.

## Horaires

| Matin | | Après-midi | |
|---|---|---|---|
| T1 | 9h45–10h00 | T8 | 12h50–13h05 |
| T2 | 10h05–10h20 | T9 | 13h10–13h25 |
| T3 | 10h25–10h40 | T10 | 13h30–13h45 |
| T4 | 10h45–11h00 | T11 | 13h50–14h05 |
| T5 | 11h05–11h20 | T12 | 14h10–14h25 |
| T6 | 11h25–11h40 | T13 | 14h30–14h45 |
| T7 | 11h45–12h00 | T14 | 14h50–15h05 |
| | *Dîner 12h05* | T15 | 15h10–15h25 |

Pour changer un horaire ou une capacité, modifie `insert into public.tournantes` ou
`insert into public.activites` dans `schema.sql`, puis relance tout le script dans
Supabase. Les inscriptions et le code d'équipe sont conservés. La page lit les horaires
depuis la base : il n'y a pas besoin de la redéployer.

Changer le code d'équipe (SQL Editor) :
```sql
select public.apa_definir_code('nouveau-code');
```

## Comment ça marche

- La page n'accède jamais directement aux tables. Elle passe par 5 fonctions SQL
  (`apa_connexion`, `apa_etat`, `apa_enregistrer`, `apa_enregistrer_lot`, `apa_supprimer`)
  qui vérifient toutes le code d'équipe.
- **Places garanties** : les fonctions d'enregistrement verrouillent les activités,
  enregistrent, puis recomptent. Si une place manque, tout est annulé et la page affiche
  « Plus de place pour : … ». Tests effectués : 10 inscriptions simultanées sur la
  dernière place donnent 1 acceptée et 9 refusées ; 4 institutions qui enregistrent en
  même temps sur la dernière place donnent 1 acceptée et 3 refusées.
- Si deux personnes modifient la même fiche, la deuxième est prévenue au lieu d'écraser
  le travail de la première.
- Une seule activité par tournante et par bénéficiaire (garanti par la base).
- La page se met à jour toutes les 5 secondes.
- Export CSV (ouvrable dans Excel) par bénéficiaire ou par activité.

## À savoir

- **Projet gratuit mis en pause** : Supabase met en pause un projet gratuit après 7 jours
  sans activité. Il suffit de cliquer sur « Restore » dans le tableau de bord. Vérifie-le
  la veille.
- Toute personne qui a le code peut modifier ou supprimer n'importe quelle fiche.
  Change le code après la journée.
- Les noms des bénéficiaires sont des données personnelles : supprime-les après
  l'événement (`delete from public.beneficiaires;`).
