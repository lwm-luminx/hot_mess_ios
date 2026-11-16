#!/usr/bin/env node
// Checks the GraphQL documents embedded in client source against a schema dump, so a renamed or removed field
// fails in CI instead of at runtime. No client uses codegen: the Kotlin and Swift SDKs, the staff apps and the
// web clients keep their operations as string literals, which nothing else reads.
//
//   node scripts/graphql-documents/check.mjs --schema contracts/schema/schema.graphql [options] <files, directories or globs>
//
//   --schema <path>       The schema dump to validate against (required). Run once per endpoint.
//   --endpoint <name>     The endpoint the schema serves (consumer, staff, tenants). A document sent elsewhere says so
//                         with a `# endpoint: staff` comment and is left to that endpoint's run.
//   --only-endpoint <name>  Check only the documents annotated with this endpoint (the other half of a mixed client).
//   --allow-deprecated    Don't fail on fields, arguments and enum values marked @deprecated.
//   --strict              Fail on documents that can't be checked because they interpolate runtime values.
//   --verbose             List every document found, not only the failures.
//   --snapshot <dir>      Also write each operation, with the fragments it spreads, to <dir> as a standalone
//                         <OperationName>.graphql file (scripts/client-contracts keeps these for shipped app releases).
//
// What counts as a document, per language:
//   Kotlin, Swift     """…""" and "…" literals whose body starts with query, mutation, subscription, fragment or {.
//   TypeScript, JS    graphql`…` and gql`…` tagged templates, and plain templates or strings that start like one.
//   Ruby              <<~GRAPHQL / <<~GQL heredocs (any delimiter), and other heredocs or strings that start like one.
//   GraphQL           a .graphql or .gql file is one document.
//
// Interpolations ($name, ${…}, \(…), #{…}) are resolved when they name a string constant defined in one of the
// checked files (Kotlin `const val`, Swift `static let`, TS `const`, Ruby constants), including constants built by
// concatenating other constants. Anything else makes the document unverifiable: it's reported as skipped, and fails
// only under --strict. Fragments defined in one document can be spread from documents in other files of the same run.
//
// Output: one line per finding, `file:line: message`, then a summary. Exit 1 on any failure, 2 on a usage error.
import { readFileSync, statSync, readdirSync, globSync, mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { resolve, relative, extname, join } from 'node:path';
import { buildSchema, parse, validate, specifiedRules, NoDeprecatedCustomRule, NoUnusedFragmentsRule, Kind } from 'graphql';

const EXTENSIONS = {
  '.kt': 'kotlin', '.kts': 'kotlin',
  '.swift': 'swift',
  '.ts': 'typescript', '.tsx': 'typescript', '.mts': 'typescript', '.js': 'typescript', '.jsx': 'typescript',
  '.mjs': 'typescript', '.cjs': 'typescript',
  '.rb': 'ruby',
  '.graphql': 'graphql', '.gql': 'graphql',
};
const SKIPPED_DIRECTORIES = new Set(['node_modules', '.git', '.build', 'build', '__generated__', 'dist', 'Pods', 'DerivedData']);
const KEYWORDS = /^(query|mutation|subscription)\b/;

function usage(message) {
  if (message) console.error(`check: ${message}`);
  console.error('usage: node check.mjs --schema <schema.graphql> [--endpoint <name> | --only-endpoint <name>] [--allow-deprecated] [--strict] [--verbose] [--snapshot <dir>] <files or globs>');
  process.exit(2);
}

function parseArguments(argv) {
  const options = { schema: null, endpoint: null, onlyEndpoint: null, allowDeprecated: false, strict: false, verbose: false, snapshot: null, inputs: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const argument = argv[i];
    if (argument === '--schema') {
      options.schema = argv[++i];
      if (!options.schema) usage('--schema needs a path');
    } else if (argument.startsWith('--schema=')) options.schema = argument.slice('--schema='.length);
    else if (argument === '--endpoint' || argument === '--only-endpoint') {
      const name = argv[++i];
      if (!name || !/^[a-z]+$/.test(name)) usage(`${argument} needs an endpoint name such as consumer, staff or tenants`);
      options[argument === '--endpoint' ? 'endpoint' : 'onlyEndpoint'] = name;
    } else if (argument === '--allow-deprecated') options.allowDeprecated = true;
    else if (argument === '--strict') options.strict = true;
    else if (argument === '--verbose') options.verbose = true;
    else if (argument === '--snapshot') {
      options.snapshot = argv[++i];
      if (!options.snapshot) usage('--snapshot needs a directory');
    }
    else if (argument === '--help' || argument === '-h') usage();
    else if (argument.startsWith('-')) usage(`unknown option ${argument}`);
    else options.inputs.push(argument);
  }
  if (!options.schema) usage('--schema is required');
  if (options.inputs.length === 0) usage('name the files, directories or globs to check');
  return options;
}

// Files to check: a directory is walked for the known extensions, a glob is expanded, a file is taken as is.
// Each file maps to the input it was found under, which --snapshot names sources relative to.
const roots = new Map();
function collectFiles(inputs) {
  const files = new Set();
  const addFile = (path, root) => { if (EXTENSIONS[extname(path)]) { files.add(resolve(path)); roots.set(resolve(path), root); } };
  const walk = (directory, root) => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
      if (entry.isDirectory()) { if (!SKIPPED_DIRECTORIES.has(entry.name)) walk(join(directory, entry.name), root); }
      else if (entry.isFile()) addFile(join(directory, entry.name), root);
    }
  };
  for (const input of inputs) {
    const matches = /[*?[{]/.test(input) ? globSync(input) : [input];
    for (const match of matches) {
      let stat;
      try { stat = statSync(match); } catch { usage(`${match} doesn't exist`); }
      if (stat.isDirectory()) walk(match, resolve(match, '..'));
      else { files.add(resolve(match)); roots.set(resolve(match), resolve(match, '..')); }
    }
  }
  return [...files].sort();
}

// --- Extraction -----------------------------------------------------------------------------------------------
// A scanner walks a file, skipping comments, and yields its string literals as templates: a list of text parts and
// interpolation parts ({ ref }). Each literal remembers where its body starts so findings point at source lines.

class Scanner {
  constructor(source) { this.source = source; this.i = 0; this.strings = []; }
  get done() { return this.i >= this.source.length; }
  peek(offset = 0) { return this.source[this.i + offset]; }
  startsWith(text) { return this.source.startsWith(text, this.i); }
  skipLineComment() { while (!this.done && this.peek() !== '\n') this.i += 1; }
  skipBlockComment(open, close, nests) {
    let depth = 1; this.i += open.length;
    while (!this.done && depth > 0) {
      if (nests && this.startsWith(open)) { depth += 1; this.i += open.length; }
      else if (this.startsWith(close)) { depth -= 1; this.i += close.length; }
      else this.i += 1;
    }
  }
  // Reads a delimited expression (after `${`, `\(`, `#{`) up to the balancing close, allowing nested brackets and
  // quoted strings inside it.
  readBalanced(openChar, closeChar) {
    const start = this.i; let depth = 1;
    while (!this.done && depth > 0) {
      const c = this.peek();
      if (c === '"' || c === "'" || c === '`') { this.i += 1; while (!this.done && this.peek() !== c) this.i += this.peek() === '\\' ? 2 : 1; }
      else if (c === openChar) depth += 1;
      else if (c === closeChar) depth -= 1;
      this.i += 1;
    }
    return this.source.slice(start, this.i - 1);
  }
  // Reads a string literal whose opening delimiter is at this.i. `interpolation` recognises the start of an
  // interpolation and returns the expression text (advancing past it) or null.
  readString(delimiter, { escapes = true, interpolation = null, multiline = false } = {}) {
    const start = this.i;
    this.i += delimiter.length;
    if (multiline && delimiter === '"""' && this.peek() === '\n') this.i += 1; // Swift: the body starts on the next line.
    const bodyStart = this.i;
    const parts = []; let text = '';
    while (!this.done && !this.startsWith(delimiter)) {
      const c = this.peek();
      if (escapes && c === '\\') {
        const next = this.peek(1);
        if (interpolation && next === '(') { const ref = interpolation(); if (ref !== null) { parts.push({ text }); text = ''; parts.push({ ref }); continue; } }
        this.i += 2;
        text += next === 'n' ? '\n' : next === 't' ? '\t' : next === '\n' ? '' : next;
        continue;
      }
      if (interpolation && c !== '\\') {
        const ref = interpolation();
        if (ref !== null) { parts.push({ text }); text = ''; parts.push({ ref }); continue; }
      }
      text += c; this.i += 1;
    }
    this.i += delimiter.length;
    parts.push({ text });
    const literal = { start, bodyStart, end: this.i, parts };
    this.strings.push(literal);
    return literal;
  }
}

// Kotlin: "..." and """...""" (raw) literals, both with $name and ${expr} templates. Comments // and /* */ (nested).
function scanKotlin(source) {
  const s = new Scanner(source);
  const interpolation = () => {
    if (s.peek() !== '$') return null;
    if (s.peek(1) === '{') { s.i += 2; return s.readBalanced('{', '}'); }
    const match = /^\$([A-Za-z_]\w*)/.exec(source.slice(s.i, s.i + 200));
    if (!match) return null;
    s.i += match[0].length; return match[1];
  };
  while (!s.done) {
    if (s.startsWith('//')) s.skipLineComment();
    else if (s.startsWith('/*')) s.skipBlockComment('/*', '*/', true);
    else if (s.startsWith('"""')) s.readString('"""', { escapes: false, interpolation });
    else if (s.peek() === '"') s.readString('"', { interpolation });
    else if (s.peek() === "'") { s.i += 1; while (!s.done && s.peek() !== "'") s.i += s.peek() === '\\' ? 2 : 1; s.i += 1; }
    else s.i += 1;
  }
  return s.strings;
}

// Swift: "..." and multi-line """...""" literals with \(expr) interpolation. Raw #"..."# literals are left alone.
function scanSwift(source) {
  const s = new Scanner(source);
  const interpolation = () => {
    if (s.peek() !== '\\' || s.peek(1) !== '(') return null;
    s.i += 2; return s.readBalanced('(', ')');
  };
  while (!s.done) {
    if (s.startsWith('//')) s.skipLineComment();
    else if (s.startsWith('/*')) s.skipBlockComment('/*', '*/', true);
    else if (s.startsWith('"""')) s.readString('"""', { interpolation, multiline: true });
    else if (s.peek() === '"') s.readString('"', { interpolation });
    else s.i += 1;
  }
  return s.strings;
}

// TypeScript and JavaScript: `...` templates with ${expr}, and "..." / '...' strings. A template tagged graphql or
// gql (or preceded by a /* GraphQL */ comment) is a document whatever it starts with.
function scanTypeScript(source) {
  const s = new Scanner(source);
  const interpolation = () => {
    if (s.peek() !== '$' || s.peek(1) !== '{') return null;
    s.i += 2; return s.readBalanced('{', '}');
  };
  while (!s.done) {
    if (s.startsWith('//')) s.skipLineComment();
    else if (s.startsWith('/*')) s.skipBlockComment('/*', '*/', false);
    else if (s.peek() === '`') {
      const before = source.slice(Math.max(0, s.i - 80), s.i);
      const literal = s.readString('`', { interpolation });
      literal.tagged = /(?:\b(?:graphql|gql)|\/\*\s*GraphQL\s*\*\/)\s*$/.test(before);
    } else if (s.peek() === '"' || s.peek() === "'") s.readString(s.peek());
    else s.i += 1;
  }
  return s.strings;
}

// Ruby: <<~ID, <<-ID and <<ID heredocs (quoted IDs too; 'ID' disables interpolation), plus "..." strings with #{}.
function scanRuby(source) {
  const s = new Scanner(source);
  const skipRegions = []; // heredoc bodies, jumped over once the scanner reaches them
  const heredoc = /^<<([~-]?)(?:([A-Z_][A-Z0-9_]*)|"([A-Z_][A-Z0-9_]*)"|'([A-Z_][A-Z0-9_]*)')/;
  const interpolation = () => {
    if (s.peek() !== '#' || s.peek(1) !== '{') return null;
    s.i += 2; return s.readBalanced('{', '}');
  };
  while (!s.done) {
    const c = s.peek();
    if (c === '#') s.skipLineComment();
    else if (c === '<' && s.peek(1) === '<') {
      const match = heredoc.exec(source.slice(s.i, s.i + 60));
      if (!match) { s.i += 2; continue; }
      const id = match[2] ?? match[3] ?? match[4];
      const interpolates = match[4] === undefined;
      const lineEnd = source.indexOf('\n', s.i);
      if (lineEnd < 0) break;
      // The body is every line up to the one holding only the delimiter.
      const terminator = new RegExp(`^[ \\t]*${id}[ \\t]*$`, 'm');
      terminator.lastIndex = 0;
      const rest = source.slice(lineEnd + 1);
      const end = terminator.exec(rest);
      const body = end ? rest.slice(0, end.index) : rest;
      const literal = { start: s.i, bodyStart: lineEnd + 1, end: lineEnd + 1 + body.length, parts: [], heredoc: id };
      if (interpolates) {
        const inner = new Scanner(body); let text = '';
        while (!inner.done) {
          if (inner.peek() === '#' && inner.peek(1) === '{') { inner.i += 2; literal.parts.push({ text }); text = ''; literal.parts.push({ ref: inner.readBalanced('{', '}') }); }
          else { text += inner.peek(); inner.i += 1; }
        }
        literal.parts.push({ text });
      } else literal.parts.push({ text: body });
      s.strings.push(literal);
      // Resume after the opening line: other code on that line (`.freeze`, arguments) is scanned normally, and the
      // body is jumped over when the scanner reaches it.
      s.i += match[0].length;
      skipRegions.push([lineEnd + 1, literal.end + (end ? end[0].length : 0)]);
    } else if (c === '"') s.readString('"', { interpolation });
    else if (c === "'") s.readString("'", { escapes: false });
    else s.i += 1;
    while (skipRegions.length && s.i >= skipRegions[0][0]) { s.i = Math.max(s.i, skipRegions[0][1]); skipRegions.shift(); }
  }
  return s.strings;
}

// GraphQL: the whole file is one document.
function scanGraphQL(source) {
  return [{ start: 0, bodyStart: 0, end: source.length, parts: [{ text: source }], tagged: true }];
}

const SCANNERS = { kotlin: scanKotlin, swift: scanSwift, typescript: scanTypeScript, ruby: scanRuby, graphql: scanGraphQL };

// `"query Q { a " +\n "b }"`: literals joined with `+` (Kotlin, Swift, TypeScript, Ruby) are one string, so one
// document. Only plain literals are joined, never tagged templates or heredocs.
function joinConcatenated(source, strings) {
  const joined = [];
  for (const literal of strings) {
    const previous = joined.at(-1);
    const plain = (string) => !string.tagged && !string.heredoc;
    if (previous && plain(previous) && plain(literal) && /^\s*\+\s*$/.test(source.slice(previous.end, literal.start))) {
      joined[joined.length - 1] = { ...previous, end: literal.end, parts: [...previous.parts, ...literal.parts] };
    } else joined.push(literal);
  }
  return joined;
}

// Constants: `val NAME = <string> + NAME2 + "…"` (Kotlin), `static let name = …` (Swift), `const name = …` (TS),
// `NAME = …` (Ruby). The value is a template too, so a constant may build on other constants.
const DECLARATIONS = {
  kotlin: /\bval\s+([A-Za-z_]\w*)\s*(?::\s*String\??)?\s*=\s*/g,
  swift: /\blet\s+([A-Za-z_]\w*)\s*(?::\s*String\??)?\s*=\s*/g,
  typescript: /\b(?:const|let|var)\s+([A-Za-z_$]\w*)\s*(?::\s*string)?\s*=\s*/g,
  ruby: /^\s*([A-Z][A-Za-z0-9_]*)\s*=\s*/gm,
  graphql: /(?!)/g,
};

// The type a declaration sits in: the nearest preceding top-level class, struct, enum, object or extension (nested
// types don't count, so a constant in `extension VenueManagementClient` belongs to it even after a nested struct).
// Enough to tell PeopleManagement's eventFields from VenueManagement's.
const OWNERS = /\b(?:class|struct|enum|object|extension|interface|protocol|module)\s+([A-Z]\w*)/g;
function findOwners(source, strings) {
  const owners = [];
  let depth = 0; let next = 0;
  for (const match of source.matchAll(OWNERS)) {
    for (; next < match.index; next += 1) {
      const literal = strings.find((l) => l.start <= next && next < l.end);
      if (literal) { next = literal.end - 1; continue; }
      if (source[next] === '{') depth += 1; else if (source[next] === '}') depth -= 1;
    }
    if (depth === 0) owners.push([match.index, match[1]]);
  }
  return owners;
}
function ownerAt(owners, offset) {
  let owner = null;
  for (const [start, name] of owners) { if (start > offset) break; owner = name; }
  return owner;
}

function findConstants(source, language, strings, file, owners) {
  const byStart = new Map(strings.map((literal) => [literal.start, literal]));
  const constants = [];
  for (const match of source.matchAll(DECLARATIONS[language])) {
    let i = match.index + match[0].length;
    const parts = [];
    let literals = 0;
    for (;;) {
      while (/\s/.test(source[i] ?? '')) i += 1;
      const literal = byStart.get(i);
      if (literal) { parts.push(...literal.parts); i = literal.end; literals += 1; }
      else {
        const ref = /^(?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*/.exec(source.slice(i, i + 200));
        if (!ref) break;
        parts.push({ ref: ref[0] }); i += ref[0].length;
      }
      const rest = source.slice(i, i + 40);
      const plus = /^\s*\+\s*/.exec(rest) ?? /^\.freeze\s*\+\s*/.exec(rest);
      if (!plus) break;
      i += plus[0].length;
    }
    // Only string constants: a declaration without a literal in its chain (`let first = first ?? 50`) isn't one.
    if (literals > 0) constants.push({ name: match[1], parts, file, owner: ownerAt(owners, match.index), line: lineOf(source, match.index) });
  }
  return constants;
}

function lineOf(source, offset) {
  let line = 1;
  for (let i = 0; i < offset; i += 1) if (source.charCodeAt(i) === 10) line += 1;
  return line;
}

// --- Resolution -----------------------------------------------------------------------------------------------

// `Type.name`, `Self.name` or `name`: the constant's name and, when given, the type it belongs to.
const parseReference = (ref) => {
  const match = /^\s*(?:((?:[A-Za-z_]\w*\.)*[A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*$/.exec(ref);
  if (!match) return null;
  const qualifier = match[1]?.split('.').pop();
  return { name: match[2], type: qualifier && !/^(?:Self|self|this|Companion)$/.test(qualifier) ? qualifier : null };
};

// Turns a template into text, substituting constants by name. A qualified reference (`Type.name`) takes the
// constant declared in that type; an unqualified one takes the nearest constant (same type and file, then same
// type, then same file), else one defined the same way everywhere in the run. A quoted literal (Kotlin's ${'$'}) is spliced in as is.
// Returns { text } or { unresolved: reason }.
function resolveTemplate(parts, constants, scope, trail = []) {
  let text = '';
  for (const part of parts) {
    if (part.text !== undefined) { text += part.text; continue; }
    const quoted = /^\s*(['"])(.*)\1\s*$/s.exec(part.ref);
    if (quoted) { text += quoted[2]; continue; }
    const reference = parseReference(part.ref);
    const everywhere = reference ? constants.get(reference.name) ?? [] : [];
    if (!reference || everywhere.length === 0) return { unresolved: `interpolates ${part.ref.trim()}, which isn't a string constant in the checked files` };
    const sameOwner = (candidate) => candidate.owner && candidate.owner === scope.owner;
    const sameFile = (candidate) => candidate.file === scope.file;
    const preferences = reference.type
      ? [(candidate) => candidate.owner === reference.type]
      : [(candidate) => sameOwner(candidate) && sameFile(candidate), sameOwner, sameFile];
    const narrowed = preferences.map((prefer) => everywhere.filter(prefer)).find((found) => found.length) ?? everywhere;
    const candidates = narrowed.filter((candidate) => !trail.includes(candidate));
    if (candidates.length === 0) return { unresolved: `${reference.name} is defined in terms of itself` };
    const values = new Set();
    let unresolved = null;
    for (const candidate of candidates) {
      const resolved = resolveTemplate(candidate.parts, constants, candidate, [...trail, candidate]);
      if (resolved.unresolved) unresolved = resolved.unresolved; else values.add(resolved.text);
    }
    if (values.size === 0) return { unresolved: `${reference.name} isn't constant: it ${unresolved}` };
    if (values.size !== 1) return { unresolved: `${reference.name} is defined ${values.size} different ways in the checked files` };
    // Constants are spliced in on one line so findings after them still point at the right source line.
    text += [...values][0].replace(/\s*\n\s*/g, ' ');
  }
  return { text };
}

// Does this text look like a GraphQL document? Operations need a name, arguments or a selection after the keyword;
// a bare `{` must open a selection (JSON starts `{"`), and `{latitude}` with nothing around the name is a URL or
// string template's placeholder, not one.
function looksLikeDocument(text) {
  const trimmed = text.replace(/^(?:\s*#[^\n]*\n)*\s*/, ''); // leading GraphQL comments don't decide
  if (/^\{[A-Za-z_]\w*\}/.test(trimmed)) return false;
  if (/^fragment\s+[A-Za-z_]\w*\s+on\s+[A-Za-z_]/.test(trimmed)) return true;
  if (KEYWORDS.test(trimmed)) return /^(query|mutation|subscription)\s*(?:[A-Za-z_]\w*\s*)?[({@]/.test(trimmed);
  return /^\{\s*(?:[A-Za-z_]|\.\.\.|#)/.test(trimmed);
}

// --- Validation -----------------------------------------------------------------------------------------------

function main() {
  const options = parseArguments(process.argv.slice(2));
  let schema;
  try { schema = buildSchema(readFileSync(options.schema, 'utf8')); }
  catch (error) { console.error(`check: can't load ${options.schema}: ${error.message}`); process.exit(2); }

  const files = collectFiles(options.inputs);
  if (files.length === 0) usage(`nothing to check: no Kotlin, Swift, TypeScript, JavaScript or Ruby files matched ${options.inputs.join(' ')}`);

  const constants = new Map();
  const candidates = [];
  for (const file of files) {
    const language = EXTENSIONS[extname(file)];
    const source = readFileSync(file, 'utf8');
    const strings = joinConcatenated(source, SCANNERS[language](source));
    const owners = findOwners(source, strings);
    for (const constant of findConstants(source, language, strings, file, owners)) {
      if (!constants.has(constant.name)) constants.set(constant.name, []);
      constants.get(constant.name).push(constant);
    }
    for (const literal of strings) {
      const sketch = literal.parts.map((part) => part.text ?? ' X ').join('');
      if (!(literal.tagged || (literal.heredoc && /^(GRAPHQL|GQL)$/.test(literal.heredoc)) || looksLikeDocument(sketch))) continue;
      candidates.push({ file, owner: ownerAt(owners, literal.start), line: lineOf(source, literal.bodyStart), parts: literal.parts });
    }
  }

  const failures = [];
  const skipped = [];
  const documents = [];
  let elsewhere = 0;
  for (const candidate of candidates) {
    // A document says which endpoint it's sent to with a `# endpoint: staff` comment; the run checks one endpoint.
    const annotated = /^\s*#\s*endpoint:\s*([a-z]+)\s*$/im.exec(candidate.parts.map((part) => part.text ?? '').join(''))?.[1];
    if (options.onlyEndpoint ? annotated !== options.onlyEndpoint : annotated && options.endpoint && annotated !== options.endpoint) { elsewhere += 1; continue; }
    const resolved = resolveTemplate(candidate.parts, constants, candidate);
    if (resolved.unresolved) { skipped.push({ ...candidate, reason: resolved.unresolved }); continue; }
    let ast;
    try { ast = parse(resolved.text, { noLocation: false }); }
    catch (error) {
      failures.push({ file: candidate.file, line: candidate.line + (error.locations?.[0]?.line ?? 1) - 1, message: `syntax: ${error.message.replace(/^Syntax Error: /, '')}` });
      continue;
    }
    documents.push({ ...candidate, text: resolved.text, ast });
  }

  // Fragments are shared across the run: a document may spread one defined in another file.
  const fragments = new Map();
  for (const document of documents) {
    for (const definition of document.ast.definitions) {
      if (definition.kind !== Kind.FRAGMENT_DEFINITION) continue;
      const text = document.text.slice(definition.loc.start, definition.loc.end);
      const line = document.line + lineOf(document.text, definition.loc.start) - 1;
      const known = fragments.get(definition.name.value);
      if (known && known.text.replace(/\s+/g, ' ') !== text.replace(/\s+/g, ' ')) {
        failures.push({ file: document.file, line, message: `fragment ${definition.name.value} is also defined, differently, at ${show(known.file)}:${known.line}` });
      } else if (!known) fragments.set(definition.name.value, { text, file: document.file, line, document });
    }
  }

  const rules = specifiedRules.concat(options.allowDeprecated ? [] : [NoDeprecatedCustomRule]);
  for (const document of documents) {
    // Validate the document with the fragments it spreads (transitively) from the rest of the run appended, and keep
    // a line map so a finding inside a borrowed fragment points at the fragment's own file.
    const lineMap = [];
    const addLines = (file, firstLine, text) => { const count = text.split('\n').length; for (let n = 0; n < count; n += 1) lineMap.push({ file, line: firstLine + n }); };
    let text = document.text;
    addLines(document.file, document.line, text);
    const defined = new Set(document.ast.definitions.filter((d) => d.kind === Kind.FRAGMENT_DEFINITION).map((d) => d.name.value));
    const queue = spreadsIn(document.text);
    const borrowed = [];
    while (queue.length) {
      const name = queue.shift();
      if (defined.has(name)) continue;
      defined.add(name);
      const fragment = fragments.get(name);
      if (!fragment) continue; // KnownFragmentNamesRule reports it.
      borrowed.push(fragment);
      queue.push(...spreadsIn(fragment.text));
    }
    for (const fragment of borrowed) { text += `\n${fragment.text}`; addLines(fragment.file, fragment.line, fragment.text); }
    const hasOperation = document.ast.definitions.some((d) => d.kind === Kind.OPERATION_DEFINITION);
    if (options.snapshot && hasOperation) snapshot(options.snapshot, document, text);
    const applicable = hasOperation ? rules : rules.filter((rule) => rule !== NoUnusedFragmentsRule);
    const errors = validate(schema, parse(text), applicable);
    for (const error of errors) {
      const where = lineMap[(error.locations?.[0]?.line ?? 1) - 1] ?? { file: document.file, line: document.line };
      failures.push({ file: where.file, line: where.line, message: error.message });
    }
    if (options.verbose) console.log(`${show(document.file)}:${document.line}: checked ${describe(document.ast)}${errors.length ? ` (${errors.length} problem${errors.length === 1 ? '' : 's'})` : ''}`);
  }

  const sortByPlace = (a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : a.line - b.line);
  for (const failure of failures.sort(sortByPlace)) console.log(`${show(failure.file)}:${failure.line}: ${failure.message}`);
  for (const skip of skipped.sort(sortByPlace)) console.log(`${show(skip.file)}:${skip.line}: ${options.strict ? 'unverifiable' : 'skipped'}: ${skip.reason}`);
  const failing = failures.length + (options.strict ? skipped.length : 0);
  console.log(`${documents.length} document${documents.length === 1 ? '' : 's'} in ${files.length} file${files.length === 1 ? '' : 's'} checked against ${options.schema}: ` +
    `${failures.length} failure${failures.length === 1 ? '' : 's'}, ${skipped.length} skipped${options.strict && skipped.length ? ' (failing under --strict)' : ''}` +
    `${elsewhere ? `, ${elsewhere} for another endpoint` : ''}.`);
  process.exit(failing ? 1 : 0);
}

const show = (file) => relative(process.cwd(), file);

// Writes one operation (with its borrowed fragments) as <dir>/<OperationName>.graphql. The same text found twice is
// written once; a different operation under a taken name gets a -2, -3… suffix. The first line names the source.
function snapshot(directory, document, text) {
  mkdirSync(directory, { recursive: true });
  const names = document.ast.definitions.filter((d) => d.kind === Kind.OPERATION_DEFINITION).map((d) => d.name?.value ?? 'Anonymous');
  const source = relative(roots.get(document.file) ?? process.cwd(), document.file);
  const body = `${text.replace(/^\s*\n/, '').replace(/\s+$/, '')}\n`;
  const stem = names.join('+');
  for (let n = 1; ; n += 1) {
    const path = join(directory, `${stem}${n === 1 ? '' : `-${n}`}.graphql`);
    if (!existsSync(path)) { writeFileSync(path, `# source: ${source}\n${body}`); return; }
    if (readFileSync(path, 'utf8').replace(/^# source: .*\n/, '') === body) return;
  }
}
const spreadsIn = (text) => [...text.matchAll(/\.\.\.\s*([A-Za-z_]\w*)/g)].map((m) => m[1]).filter((name) => name !== 'on');

function describe(ast) {
  return ast.definitions.map((d) => (d.kind === Kind.OPERATION_DEFINITION ? `${d.operation} ${d.name?.value ?? '(anonymous)'}` : `fragment ${d.name.value}`)).join(', ');
}

main();
