#!/usr/bin/env node
//
// Faux « psql » qui exécute réellement le SQL sur un PostgreSQL compilé en
// WebAssembly (pglite). Sert à faire tourner scripts/test-droits-utilisateur.sh
// de bout en bout, sans PostgreSQL installé.
//
// Utilisation (le client ne voit aucune différence) :
//   psql -X -A -t -U r -d b -v ON_ERROR_STOP=1 -c "select 1"
//
// Variables d'environnement :
//   PGLITE_DIR  répertoire de données (défaut : /tmp/pglite-droits)
//   PGLITE_DB   nom de base simulation (ignoré, pglite n'a qu'une base)
//
import { PGlite } from '@electric-sql/pglite'
import fs from 'node:fs'

const DATA_DIR = process.env.PGLITE_DIR || '/tmp/pglite-droits'
fs.mkdirSync(DATA_DIR, { recursive: true })

const args = process.argv.slice(2)
let sql = null
let tuplesOnly = false
let fromFile = null

// Analyse des options courtes, y compris groupées (-tAc, -X, -v, ...).
// Les options qui prennent une valeur consomment le reste du groupe, sinon
// l'argument suivant.
const WITH_VALUE = new Set(['c', 'f', 'h', 'p', 'U', 'd', 'v'])
for (let i = 0; i < args.length; i++) {
  const a = args[i]
  if (a === '--') continue
  if (a.length > 1 && a[0] === '-') {
    for (let j = 1; j < a.length; j++) {
      const c = a[j]
      if (c === 'A' || c === 't') { tuplesOnly = true; continue }
      if (WITH_VALUE.has(c)) {
        let val = a.slice(j + 1)
        if (val === '') { val = args[++i] }
        if (c === 'c') sql = val
        else if (c === 'f') fromFile = val
        break
      }
      // -X et les autres options sans valeur sont ignorees
    }
  }
}

if (fromFile !== null) {
  sql = fromFile === '-' ? fs.readFileSync(0, 'utf8') : fs.readFileSync(fromFile, 'utf8')
}
if (sql === null) {
  // SQL envoye sur l'entree standard (comme le fait le script de correctif)
  try {
    if (!process.stdin.isTTY) sql = fs.readFileSync(0, 'utf8')
  } catch (_) { /* pas d'entree standard lisible */ }
}
if (sql === null || sql.trim() === '') {
  process.stderr.write('psql (shim pglite) : ni -c ni -f fourni, et rien sur entree standard\n')
  process.exit(2)
}

const db = new PGlite({ dataDir: DATA_DIR })

const toText = (v) => {
  if (v === null || v === undefined) return ''
  if (typeof v === 'boolean') return v ? 't' : 'f'
  if (v instanceof Date) return v.toISOString()
  if (typeof v === 'object') return JSON.stringify(v)
  return String(v)
}

// Une seule instruction, ou plusieurs ? Le point-virgule doit etre ignore
// s'il est dans une chaine de caracteres.
const isMultiStatement = (s) => {
  let inSingle = false
  let inDouble = false
  for (let i = 0; i < s.length; i++) {
    const c = s[i]
    if (inSingle) {
      if (c === "'") { if (s[i + 1] === "'") i++; else inSingle = false }
      continue
    }
    if (inDouble) {
      if (c === '"') { if (s[i + 1] === '"') i++; else inDouble = false }
      continue
    }
    if (c === "'") { inSingle = true; continue }
    if (c === '"') { inDouble = true; continue }
    if (c === ';') {
      const rest = s.slice(i + 1).trim()
      if (rest !== '' && !rest.startsWith(';')) return true
    }
  }
  return false
}

try {
  let res
  if (isMultiStatement(sql)) {
    // BEGIN; ... COMMIT; : db.query() refuse, db.exec() accepte.
    await db.exec(sql)
    res = { rows: [], fields: [] }
  } else {
    res = await db.query(sql)
  }
  const rows = res.rows || []
  const fields = (res.fields || []).map(f => f.name)
  // psql affiche les doublons de noms de colonnes ; pglite renvoie un objet
  // par ligne, ou un nom en double ecrase l'autre. On le signale.
  if (new Set(fields).size !== fields.length) {
    process.stderr.write('AVERTISSEMENT : nom de colonne en double dans le resultat\n')
  }
  if (tuplesOnly) {
    for (const r of rows) {
      process.stdout.write(fields.map(f => toText(r[f])).join('|') + '\n')
    }
  } else if (rows.length > 0) {
    const widths = fields.map((f, i) => Math.max(f.length, ...rows.map(r => toText(r[f]).length)))
    const line = (cells) => cells.map((c, i) => c.padEnd(widths[i])).join(' | ').trimEnd()
    process.stdout.write(line(fields) + '\n')
    process.stdout.write(widths.map(w => '-'.repeat(w)).join('-+-') + '\n')
    for (const r of rows) process.stdout.write(line(fields.map(f => toText(r[f]))) + '\n')
  }
  await db.close()
  process.exit(0)
} catch (e) {
  process.stderr.write('ERROR:  ' + (e && e.message ? e.message : String(e)) + '\n')
  process.stderr.write('LIGNE 1 : ' + sql + '\n')
  try { await db.close() } catch (_) { /* ignore */ }
  process.exit(1)
}
