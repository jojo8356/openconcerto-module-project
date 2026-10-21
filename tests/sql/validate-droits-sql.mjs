// Validation du SQL utilise par scripts/test-droits-utilisateur.sh.
//
// Le script shell calcule les droits effectifs d'un utilisateur OpenConcerto
// (table USER_RIGHT) en reproduisant la regle de UserRightsManager.expand() :
// pour un couple (CODE, OBJECT), c'est la ligne d'ID le plus bas qui l'emporte.
//
// Ce test rejoue ce SQL sur un vrai moteur PostgreSQL (pglite, PostgreSQL
// compile en WebAssembly) pour verifier : le calcul des droits effectifs, le
// differentiel entre deux comptes, la generation du correctif, son application
// et le rollback.
//
// Execution :
//   npm install @electric-sql/pglite
//   node tests/sql/validate-droits-sql.mjs
//
// Sortie : 0 si tous les controles passent, 1 sinon.
//
//import { PGlite } from '@electric-sql/pglite'

const db = new PGlite()
await db.exec(`
  create schema "Common";
  create table "Common"."USER_COMMON" (
    id serial primary key, login text, nom text, prenom text,
    password text, admin boolean default false, superuser boolean default false);
  create table "Common"."RIGHT" (
    id serial primary key, code varchar(128), nom varchar(256), description varchar(500));
  create table "Common"."USER_RIGHT" (
    id serial primary key, id_user_common int references "Common"."USER_COMMON"(id),
    id_right int references "Common"."RIGHT"(id), object varchar(150) null, have_right boolean not null);
  create table "Common"."ACCES_SOCIETE" (
    id serial primary key, id_user_common int, id_societe_common int);
  insert into "Common"."USER_COMMON" (id, login, nom, prenom, admin, superuser) values
    (1,'admin','Administrateur','',true,true),
    (2,'yves','POLSINELLI','Yves',false,false),
    (3,'gisele','ABE','Gisèle',false,false),
    (4,'paul','DUPONT','Paul',false,false);
  insert into "Common"."RIGHT" (id, code, nom) values
    (1,'TABLE_ALL_RIGHTS','Tous les droits'),
    (2,'TABLE_ALL_MODIF_RIGHTS','Droits de modification'),
    (3,'INSERT_ROW','Insertion'),
    (4,'UPDATE_ROW','Modification'),
    (5,'SELECT_ROW','Consultation'),
    (6,'DROIT_SPECIFIQUE','Droit maison');
  insert into "Common"."USER_RIGHT" (id, id_user_common, id_right, object, have_right) values
    (10, 2, 1, null, true),
    (20, 3, 1, null, false),
    (21, 3, 1, null, true),
    (30, 4, 3, '"OpenConcerto42"."FACTURE_FOURNISSEUR"', true),
    (31, 4, 5, '"OpenConcerto42"."FACTURE_FOURNISSEUR"', true);
  insert into "Common"."ACCES_SOCIETE" (id_user_common, id_societe_common) values (2,42),(3,42),(4,42);
`)

const T_USERS = '"Common"."USER_COMMON"'
const T_RIGHTS = '"Common"."USER_RIGHT"'
const T_CODES = '"Common"."RIGHT"'
const ID1 = 2, ID2 = 3
let failures = 0
const check = (label, got, expected) => {
  const ok = JSON.stringify(got) === JSON.stringify(expected)
  if (!ok) failures++
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${label} : ${JSON.stringify(got)}${ok ? '' : ' (attendu ' + JSON.stringify(expected) + ')'}`)
}

const EFF_CTE = `with eff as (
    select distinct on (ur.id_user_common, r.code, coalesce(ur.object,''))
           ur.id_user_common, ur.id, r.code, r.nom, ur.object, ur.have_right
    from ${T_RIGHTS} ur
    join ${T_CODES} r on r.id = ur.id_right
    where ur.id_user_common in (${ID1}, ${ID2})
    order by ur.id_user_common, r.code, coalesce(ur.object,''), ur.id
)`

// --- droits effectifs : un par utilisateur ---
const eff = (await db.query(`${EFF_CTE} select e.id_user_common, e.id, e.code, e.object, e.have_right from eff e order by 1,3`)).rows
console.log('\nDroits effectifs :', JSON.stringify(eff))
check('droits effectifs : Yves = 1 ligne, true', eff.filter(r => r.id_user_common === 2).map(r => [r.id, r.have_right]), [[10, true]])
check('droits effectifs : Gisele = 1 ligne, false (ligne 20)', eff.filter(r => r.id_user_common === 3).map(r => [r.id, r.have_right]), [[20, false]])

// --- differentiel ---
const diff = (await db.query(`${EFF_CTE},
u1 as (select * from eff where id_user_common = ${ID1}),
u2 as (select * from eff where id_user_common = ${ID2})
select coalesce(u1.code, u2.code) as code, coalesce('['||u1.object||']','<tous>') as objet_ref,
       u1.have_right as "droit_yves", u2.have_right as "droit_gisele",
       case when u1.have_right is distinct from u2.have_right then 'DIFFERENT' else '' end as statut
from u1 full outer join u2 on u1.code = u2.code and coalesce(u1.object,'') = coalesce(u2.object,'')
where u1.have_right is distinct from u2.have_right order by 1,2`)).rows
console.log('\nDiferentiel :', JSON.stringify(diff))
check('differentiel = 1 ligne, DIFFERENT', diff.map(r => [r.code, r.droit_yves, r.droit_gisele, r.statut]),
  [['TABLE_ALL_RIGHTS', true, false, 'DIFFERENT']])

// --- compteurs ---
const missing = (await db.query(`${EFF_CTE},
u1 as (select * from eff where id_user_common = ${ID1}),
u2 as (select * from eff where id_user_common = ${ID2})
select count(*) as n from u1 left join u2 on u1.code = u2.code and coalesce(u1.object,'') = coalesce(u2.object,'')
where u1.have_right = true and (u2.have_right is null or u2.have_right = false)`)).rows[0].n
check('droits manquants = 1', Number(missing), 1)

const shadow = (await db.query(`${EFF_CTE},
tgt as (select * from eff where id_user_common = ${ID2})
select count(*) as n from ${T_RIGHTS} ur
join ${T_CODES} r on r.id = ur.id_right
join tgt on tgt.code = r.code and coalesce(tgt.object,'') = coalesce(ur.object,'')
where ur.id_user_common = ${ID2} and ur.id <> tgt.id
  and ur.have_right is distinct from tgt.have_right`)).rows[0].n
check('lignes masquees = 1', Number(shadow), 1)

// --- sauvegarde (avant correctif) puis correctif ---
const backupInserts = (await db.query(
  `select 'INSERT INTO ${T_RIGHTS} (id_user_common, id_right, object, have_right) VALUES (' ||
          ur.id_user_common || ', ' || ur.id_right || ', ' ||
          case when ur.object is null then 'NULL' else quote_literal(ur.object) end || ', ' ||
          case when ur.have_right then 'true' else 'false' end || ');' as stmt
   from ${T_RIGHTS} ur where ur.id_user_common = ${ID2} order by ur.id`)).rows.map(r => r.stmt)
console.log('\nSauvegarde :\n' + backupInserts.join('\n'))

const fixRows = (await db.query(`${EFF_CTE},
ref as (select * from eff where id_user_common = ${ID1}),
tgt as (select * from eff where id_user_common = ${ID2})
select case
         when tgt.code is null then
           'INSERT INTO ${T_RIGHTS} (id_user_common, id_right, object, have_right) VALUES (${ID2}, (select id from ${T_CODES} where code = ' || quote_literal(ref.code) || '), ' ||
           case when ref.object is null then 'NULL' else quote_literal(ref.object) end || ', ' ||
           case when ref.have_right then 'true' else 'false' end || ');'
         when ref.have_right is distinct from tgt.have_right then
           'UPDATE ${T_RIGHTS} SET have_right = ' || case when ref.have_right then 'true' else 'false' end ||
           ' WHERE id = ' || tgt.id || ';'
         else null
       end as stmt
from ref full outer join tgt on ref.code = tgt.code and coalesce(ref.object,'') = coalesce(tgt.object,'')
where ref.have_right is distinct from tgt.have_right`)).rows.map(r => r.stmt).filter(Boolean)

const dupRows = (await db.query(`${EFF_CTE},
ref as (select * from eff where id_user_common = ${ID1}),
tgt as (select * from eff where id_user_common = ${ID2})
select 'DELETE FROM ${T_RIGHTS} WHERE id = ' || ur.id || ';' as stmt
from ${T_RIGHTS} ur
join ${T_CODES} r on r.id = ur.id_right
join ref on ref.code = r.code and coalesce(ref.object,'') = coalesce(ur.object,'')
join tgt on tgt.code = ref.code and coalesce(tgt.object,'') = coalesce(ref.object,'')
where ur.id_user_common = ${ID2}
  and ref.have_right is distinct from tgt.have_right
  and exists (select 1 from ${T_RIGHTS} ur2
              where ur2.id_user_common = ${ID2}
                and ur2.id_right = ur.id_right
                and coalesce(ur2.object,'') = coalesce(ur.object,'')
                and ur2.id < ur.id)`)).rows.map(r => r.stmt).filter(Boolean)

console.log('\nCorrectif genere :\n' + [...fixRows, ...dupRows].join('\n'))
check('correctif = 1 UPDATE (pas d INSERT)', fixRows.length === 1 && fixRows[0].startsWith('UPDATE'), true)
check('nettoyage = 1 DELETE (la ligne 21)', dupRows.length === 1 && dupRows[0].includes('21'), true)

await db.exec('BEGIN;')
for (const s of [...fixRows, ...dupRows]) await db.exec(s)
await db.exec('COMMIT;')

const eff2 = (await db.query(`${EFF_CTE} select e.id_user_common, e.id, e.code, e.have_right from eff e order by 1`)).rows
console.log('\nDroits effectifs apres correctif :', JSON.stringify(eff2))
check('apres correctif : Gisele = true', eff2.filter(r => r.id_user_common === 3).map(r => r.have_right), [true])

const diff2 = (await db.query(`${EFF_CTE},
u1 as (select * from eff where id_user_common = ${ID1}),
u2 as (select * from eff where id_user_common = ${ID2})
select count(*) as n from u1 full outer join u2 on u1.code = u2.code and coalesce(u1.object,'') = coalesce(u2.object,'')
where u1.have_right is distinct from u2.have_right`)).rows[0].n
check('ecarts restants = 0', Number(diff2), 0)

// --- rollback ---
await db.exec('BEGIN;')
await db.exec(`DELETE FROM ${T_RIGHTS} WHERE id_user_common = ${ID2};`)
for (const s of backupInserts) await db.exec(s)
await db.exec('COMMIT;')
const eff3 = (await db.query(`${EFF_CTE} select e.id_user_common, e.id, e.have_right from eff e where id_user_common = ${ID2} order by 2`)).rows
console.log('\nDroits effectifs apres rollback :', JSON.stringify(eff3))
check('apres rollback : Gisele = false (etat initial)', eff3.map(r => r.have_right), [false])

// --- scenario objet : Paul (droits sur une table precise) vs Yves ---
const IDP = 4
const effP = (await db.query(`with eff as (
    select distinct on (ur.id_user_common, r.code, coalesce(ur.object,''))
           ur.id_user_common, ur.id, r.code, ur.object, ur.have_right
    from ${T_RIGHTS} ur join ${T_CODES} r on r.id = ur.id_right
    where ur.id_user_common in (${ID1}, ${IDP})
    order by ur.id_user_common, r.code, coalesce(ur.object,''), ur.id)
  select * from eff order by 1,3`)).rows
console.log('\nYves vs Paul (droits par table) :', JSON.stringify(effP))
check('Paul : 2 lignes (INSERT_ROW + SELECT_ROW sur FACTURE_FOURNISSEUR)', effP.filter(r => r.id_user_common === IDP).length, 2)

await db.close()
console.log('\n' + (failures === 0 ? 'TOUS LES CONTROLES PASSENT' : failures + ' CONTROLE(S) EN ECHEC'))
process.exit(failures === 0 ? 0 : 1)
