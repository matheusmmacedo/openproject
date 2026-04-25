#!/usr/bin/env node
// One-off helpers for the live OpenProject DB:
//   1) Rename the admin login from `admin` -> `matheus`
//   2) Set default language to pt-BR (and ensure it's in available_languages)
//
// Usage:
//   node scripts/admin-rename-and-locale.mjs --host HOST --port PORT --pass PASS

import { Client } from 'pg';

const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, cur, i, arr) => {
    if (cur.startsWith('--')) acc.push([cur.slice(2), arr[i + 1]]);
    return acc;
  }, []),
);

const c = new Client({
  host: args.host, port: Number(args.port),
  user: 'postgres', password: args.pass,
  database: 'openproject', ssl: false,
});
await c.connect();
console.log('connected');

// 1) Inspect candidate users
const users = await c.query(
  `SELECT id, login, mail, firstname, lastname, admin, type
     FROM users WHERE admin = true OR login IN ('admin','matheus') ORDER BY id`,
);
console.log('admins:', users.rows);

// Avoid clobbering an existing 'matheus' login
const existsMatheus = users.rows.some(u => u.login === 'matheus');
if (existsMatheus) {
  console.log('SKIP rename: a user with login=matheus already exists');
} else {
  const r = await c.query(`UPDATE users SET login = 'matheus' WHERE login = 'admin' RETURNING id`);
  console.log(`renamed admin -> matheus (${r.rowCount} row)`);
}

// 2) Settings — discover schema
const cols = await c.query(
  `SELECT column_name FROM information_schema.columns WHERE table_name = 'settings'`,
);
console.log('settings cols:', cols.rows.map(x => x.column_name).join(', '));

const settingNames = ['default_language', 'available_languages'];
for (const name of settingNames) {
  const got = await c.query(`SELECT name, value FROM settings WHERE name = $1`, [name]);
  console.log(`  ${name}: ${JSON.stringify(got.rows)}`);
}

// Set default_language = pt-BR (OpenProject uses pt-BR with capital BR)
const candidates = ['pt-BR', 'pt'];
let chosen = null;
for (const cand of candidates) {
  // Probe value: see if any user has it as language preference (just sanity)
  const r = await c.query(
    `INSERT INTO settings (name, value, created_at, updated_at)
     VALUES ('default_language', $1, NOW(), NOW())
     ON CONFLICT (name) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
     RETURNING value`,
    [cand],
  );
  chosen = cand;
  console.log(`set default_language -> ${cand} (returning=${JSON.stringify(r.rows)})`);
  break;
}

// Ensure pt-BR is enabled in available_languages (Rails serializes arrays as YAML in `value`).
const av = await c.query(`SELECT value FROM settings WHERE name = 'available_languages'`);
if (av.rowCount === 0) {
  console.log('available_languages not set in DB — OpenProject default kicks in (which already includes pt-BR if compiled).');
} else {
  const raw = av.rows[0].value || '';
  if (!raw.includes('pt-BR') && !raw.includes('pt-br')) {
    console.log(`available_languages does not include pt-BR — current value:\n${raw.substring(0,500)}`);
    console.log('NOT modifying — recommend setting via Admin UI to keep YAML formatting safe');
  } else {
    console.log('available_languages already includes pt-BR');
  }
}

await c.end();
console.log('done. restart web service to bust the settings cache');
