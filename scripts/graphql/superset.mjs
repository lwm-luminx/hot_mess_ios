#!/usr/bin/env node
// Checks that a server's schema still contains everything a client was built against: every type, field, argument
// and enum value of the client's copy, with types the client can still read (graphql-js findBreakingChanges). The
// apps keep the schema they were built and tested against in their repository; before a release, CI runs this with
// production's running schema (GET /v1/schemas/<view>) as the server, so an app can't ship against a schema that
// production doesn't serve yet, or no longer serves.
//
//   node superset.mjs --client <app's schema.graphql> --server <production's schema.graphql> [--label <name>]
//
// Output: one line per missing or changed element, then a summary. Exit 1 if any, 2 on a usage error.
import { readFileSync } from 'node:fs';
import { buildSchema, findBreakingChanges } from 'graphql';

function usage(message) {
  if (message) console.error(`superset: ${message}`);
  console.error('usage: node superset.mjs --client <schema.graphql> --server <schema.graphql> [--label <name>]');
  process.exit(2);
}

const options = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i += 1) {
  const name = argv[i].replace(/^--/, '');
  if (!['client', 'server', 'label'].includes(name) || !argv[i + 1]) usage(`unknown or incomplete option ${argv[i]}`);
  options[name] = argv[++i];
}
if (!options.client || !options.server) usage('--client and --server are required');

const load = (path) => {
  try { return buildSchema(readFileSync(path, 'utf8')); }
  catch (error) { console.error(`superset: can't load ${path}: ${error.message}`); process.exit(2); }
};
const client = load(options.client);
const server = load(options.server);
const label = options.label ?? options.client;

const changes = findBreakingChanges(client, server);
for (const change of changes) console.log(`${label}: ${change.description}`);
console.log(changes.length === 0
  ? `${options.server} contains all of ${options.client}.`
  : `${options.server} lacks ${changes.length} thing${changes.length === 1 ? '' : 's'} ${options.client} has.`);
process.exit(changes.length === 0 ? 0 : 1);
