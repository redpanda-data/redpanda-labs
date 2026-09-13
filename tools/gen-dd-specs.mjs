#!/usr/bin/env node
// Generate the Doc Detective spec of every step of a solution from its pages.
//
//   node tools/gen-dd-specs.mjs <slug> --out <dir>   write <dir>/<step-id>.json per step
//   node tools/gen-dd-specs.mjs <slug> --check       validate only; exit 1 on any problem
//   node tools/gen-dd-specs.mjs <slug> --list        one line per command block: step, tag, runnable, expected
//
// The pages are the single source of truth. A step page shows a command with
//
//   [source,bash]
//   ----
//   include::example$steps/<step-id>/commands.sh[tag=<name>]
//   ----
//
// and, when the output matters, the captured output right after it with
//
//   [source,text]
//   ----
//   include::example$steps/<step-id>/expected/<name>.txt[]
//   ----
//
// For each command block, in page order, the generated spec runs exactly the
// tagged region of solutions/<slug>/steps/<step-id>/commands.sh with
// `set -euo pipefail`, the solution's .env loaded, and the solution directory
// as the working directory. When an expected-output include directly follows,
// the step also checks stdout against a regex built from the captured file
// (tools/capture-expected.sh writes those files): regex metacharacters are
// escaped, runs of digits become \d+, timestamps and hex ids become \S+,
// lines are matched in order and trailing whitespace is ignored.
//
// A command block carrying the `manual` role (`[.manual]` or `role=manual`
// on the block) is not run in CI; the generator notes it and moves on.
//
// Media. When solutions/<slug>/steps/<step-id>/media.json exists, it is an
// array of Doc Detective browser steps (goTo, find, wait, waitUntil,
// screenshot, record, stopRecord) that are appended to the step's spec after
// its command blocks, so every image and recording a page shows is produced
// by the test run. An entry {"runCommandTag": "<name>"} expands to that
// tagged command, which lets a recording wrap a command. `${VAR:-default}`
// in string values is expanded from the solution's .env (or .env.example).
// Output paths are relative to the solution directory and point into
// ../../docs/modules/<slug>/images/. A spec that records gets a headed Chrome
// context: in doc-detective 4.38.1 the browser recording engine needs headed
// Chrome, and the ffmpeg engine captures a physical display, so a recording
// cannot be made under the headless Firefox context the base config uses.
//
// _setup.json and _teardown.json (compose up and down) stay hand-written.
// No dependencies beyond Node itself.

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const slug = args.find((a) => !a.startsWith("--"));
const mode = args.includes("--check") ? "check" : args.includes("--list") ? "list" : args.includes("--media") ? "media" : args.includes("--out") ? "out" : null;
const outDir = mode === "out" ? args[args.indexOf("--out") + 1] : null;

if (!slug || !mode || (mode === "out" && !outDir)) {
  console.error("usage: gen-dd-specs.mjs <slug> (--out <dir> | --check | --list | --media)");
  process.exit(2);
}

const pagesDir = join(root, "docs", "modules", slug, "pages");
const codeDir = join(root, "solutions", slug);
const problems = [];
const problem = (where, msg) => problems.push(`${where}: ${msg}`);

// Step ids in order, from the overview header.
function stepIds() {
  const overview = join(pagesDir, "index.adoc");
  if (!existsSync(overview)) {
    problem(overview, "overview not found");
    return [];
  }
  const lines = readFileSync(overview, "utf8").split("\n");
  for (let i = 1; i < lines.length; i++) {
    if (/^\s*$/.test(lines[i])) break;
    const m = lines[i].match(/^:page-solution-steps:\s*(.*)$/);
    if (m) return m[1].split(",").map((s) => s.trim()).filter(Boolean);
  }
  problem(overview, ":page-solution-steps: not found in the header");
  return [];
}

// Listing blocks of a page, in order, with the attribute lines above them.
// Returns [{line, attrs, includes:[{path, attrs}]}].
function listingBlocks(pagePath) {
  const lines = readFileSync(pagePath, "utf8").split("\n");
  const blocks = [];
  let attrs = [];
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    if (l === "----" || l === "....") {
      const block = { line: i + 1, attrs, includes: [] };
      let j = i + 1;
      for (; j < lines.length && lines[j] !== l; j++) {
        const inc = lines[j].match(/^include::example\$([^\[]+)\[([^\]]*)\]\s*$/);
        if (inc) block.includes.push({ path: inc[1], attrs: inc[2], line: j + 1 });
      }
      blocks.push(block);
      i = j;
      attrs = [];
      continue;
    }
    if (/^\[.*\]$/.test(l) || /^\.[^.\s]/.test(l)) attrs.push(l);
    else attrs = [];
  }
  return blocks;
}

// Command and expected-output blocks of one step page.
function stepBlocks(step) {
  const page = join(pagesDir, `${step}.adoc`);
  const out = [];
  if (!existsSync(page)) {
    problem(page, "step page not found");
    return out;
  }
  for (const b of listingBlocks(page)) {
    for (const inc of b.includes) {
      let m = inc.path.match(new RegExp(`^steps/${step}/commands\\.sh$`));
      if (m) {
        const tag = (inc.attrs.match(/(?:^|,)\s*tags?=([^,\]]+)/) || [])[1];
        if (!tag) {
          problem(`${page}:${inc.line}`, "commands.sh must be included with tag=<name>");
          continue;
        }
        const manual = b.attrs.some((a) => /^\[\.manual\]$/.test(a) || /role=manual\b/.test(a));
        out.push({ kind: "command", tag, manual, line: inc.line, page });
        continue;
      }
      m = inc.path.match(new RegExp(`^steps/${step}/expected/([^/]+)\\.txt$`));
      if (m) {
        out.push({ kind: "expected", tag: m[1], line: inc.line, page });
        continue;
      }
      if (/^steps\//.test(inc.path)) {
        problem(`${page}:${inc.line}`, `include ${inc.path} does not belong to step '${step}' (steps/<step-id>/commands.sh or steps/<step-id>/expected/<name>.txt)`);
      }
    }
  }
  return out;
}

// The text of one tagged region of commands.sh.
function commandText(step, tag, where) {
  const file = join(codeDir, "steps", step, "commands.sh");
  if (!existsSync(file)) {
    problem(where, `${file} not found`);
    return null;
  }
  const lines = readFileSync(file, "utf8").split("\n");
  const start = lines.findIndex((l) => l.trim() === `# tag::${tag}[]`);
  const end = lines.findIndex((l) => l.trim() === `# end::${tag}[]`);
  if (start < 0 || end < 0 || end < start) {
    problem(where, `tag '${tag}' not found in ${file} (need '# tag::${tag}[]' and '# end::${tag}[]')`);
    return null;
  }
  const body = lines.slice(start + 1, end).join("\n").trim();
  if (!body) problem(where, `tag '${tag}' in ${file} is empty`);
  return body;
}

// Regex for stdout from a captured expected-output file.
const D = "\u0000D", S = "\u0000S";
function expectedRegex(step, tag, where) {
  const file = join(codeDir, "steps", step, "expected", `${tag}.txt`);
  if (!existsSync(file)) {
    problem(where, `${file} not found (run tools/capture-expected.sh ${slug} on a running stack)`);
    return null;
  }
  const text = readFileSync(file, "utf8").replace(/\s+$/, "");
  if (!text) {
    problem(where, `${file} is empty`);
    return null;
  }
  const pattern = text
    .split("\n")
    .map((line) =>
      line
        .replace(/\s+$/, "")
        .replace(/\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})?/g, S) // ISO timestamps
        .replace(/\d{4}\/\d{2}\/\d{2} \d{2}:\d{2}:\d{2}/g, S) // Go log timestamps
        .replace(/\b\d{1,2}:\d{2}:\d{2}\b/g, S) // clock times
        .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, S) // uuids
        .replace(/\b(?=[0-9a-f]*\d)(?=[0-9a-f]*[a-f])[0-9a-f]{12,}\b/gi, S) // long hex ids
        .replace(/\d+/g, D) // every other number
        .replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")
        .split(D).join("\\d+")
        .split(S).join("\\S+")
    )
    .join("[ \\t]*\\n");
  return `/${pattern}[ \\t]*/`;
}

// The shell prefix every generated command runs under.
const shellPrefix = "set -euo pipefail\nset -a; [ -f .env ] && . ./.env; set +a\n";

// Variables from the solution's .env (or .env.example), for ${VAR:-default}.
function dotenv() {
  for (const name of [".env", ".env.example"]) {
    const f = join(codeDir, name);
    if (!existsSync(f)) continue;
    const vars = {};
    for (const line of readFileSync(f, "utf8").split("\n")) {
      const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
      if (m) vars[m[1]] = m[2];
    }
    return vars;
  }
  return {};
}
const envVars = dotenv();
function expandVars(v) {
  if (typeof v === "string") {
    return v.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/g, (_, name, def) => (envVars[name] !== undefined && envVars[name] !== "" ? envVars[name] : def ?? ""));
  }
  if (Array.isArray(v)) return v.map(expandVars);
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, expandVars(x)]));
  return v;
}

const MEDIA_STEPS = new Set(["goTo", "find", "wait", "waitUntil", "screenshot", "record", "stopRecord"]);

// The output path of a screenshot or record step, relative to the solution dir.
function outputPath(v) {
  if (typeof v === "string") return v;
  if (v && typeof v === "object" && typeof v.path === "string") return v.directory ? `${v.directory.replace(/\/$/, "")}/${v.path}` : v.path;
  return null;
}

// Browser steps of steps/<step-id>/media.json, appended after the command blocks.
function mediaSteps(step, summary) {
  const file = join(codeDir, "steps", step, "media.json");
  if (!existsSync(file)) return [];
  let entries;
  try {
    entries = JSON.parse(readFileSync(file, "utf8"));
  } catch (e) {
    problem(file, `invalid JSON: ${e.message}`);
    return [];
  }
  if (!Array.isArray(entries)) {
    problem(file, "must be a JSON array of Doc Detective steps");
    return [];
  }
  const out = [];
  entries.forEach((e, i) => {
    const where = `${file}[${i}]`;
    if (!e || typeof e !== "object" || Array.isArray(e) || Object.keys(e).length !== 1) {
      problem(where, "each entry is an object with exactly one key (a Doc Detective step, or runCommandTag)");
      return;
    }
    const [key] = Object.keys(e);
    if (key === "runCommandTag") {
      const text = commandText(step, e.runCommandTag, where);
      if (text === null) return;
      out.push({ runShell: { command: shellPrefix + text, workingDirectory: ".", timeout: 600000 } });
      summary.runShell++;
      return;
    }
    if (!MEDIA_STEPS.has(key)) {
      problem(where, `unknown step '${key}' (allowed: ${[...MEDIA_STEPS].join(", ")}, runCommandTag)`);
      return;
    }
    const expanded = expandVars(e);
    if (key === "screenshot" || key === "record") {
      const p = outputPath(expanded[key]);
      const ok = p && (key === "screenshot" ? /\.png$/i.test(p) : /\.(gif|mp4|webm)$/i.test(p));
      if (!ok) {
        problem(where, `${key} needs a path ending in ${key === "screenshot" ? ".png" : ".gif, .mp4, or .webm"}`);
        return;
      }
      summary.media.push(p);
      if (key === "record") summary.record = true;
    }
    out.push(expanded);
    summary.mediaSteps++;
  });
  return out;
}

function buildSpec(step) {
  const blocks = stepBlocks(step);
  const page = join(pagesDir, `${step}.adoc`);
  const steps = [];
  const summary = { step, runShell: 0, stdio: 0, manual: [], mediaSteps: 0, media: [], record: false };
  const list = [];
  for (let i = 0; i < blocks.length; i++) {
    const b = blocks[i];
    if (b.kind === "expected") {
      const prev = blocks[i - 1];
      if (!prev || prev.kind !== "command") problem(`${b.page}:${b.line}`, `expected/${b.tag}.txt does not directly follow a command block`);
      else if (prev.tag !== b.tag) problem(`${b.page}:${b.line}`, `expected/${b.tag}.txt follows command tag '${prev.tag}'; name them the same`);
      continue;
    }
    const next = blocks[i + 1];
    const expects = next && next.kind === "expected" && next.tag === b.tag;
    list.push(`${step}\t${b.tag}\t${b.manual ? 0 : 1}\t${expects ? 1 : 0}`);
    const where = `${b.page}:${b.line}`;
    const text = commandText(step, b.tag, where);
    if (b.manual) {
      summary.manual.push(b.tag);
      if (expects) problem(`${next.page}:${next.line}`, `expected/${b.tag}.txt follows a [.manual] command, which is never run; drop one of them`);
      continue;
    }
    if (text === null) continue;
    const runShell = {
      command: shellPrefix + text,
      workingDirectory: ".",
      timeout: 600000,
    };
    if (expects) {
      const re = expectedRegex(step, b.tag, `${next.page}:${next.line}`);
      if (re) {
        runShell.stdio = re;
        summary.stdio++;
      }
    }
    steps.push({ runShell });
    summary.runShell++;
  }
  steps.push(...mediaSteps(step, summary));
  if (summary.runShell === 0) problem(page, "no runnable command block (include steps/<step-id>/commands.sh[tag=...] in a listing)");
  if (summary.stdio === 0) problem(page, "no expected-output check (include steps/<step-id>/expected/<name>.txt right after a command block)");
  const spec = {
    specId: step,
    description: `Generated by tools/gen-dd-specs.mjs from docs/modules/${slug}/pages/${step}.adoc; every command block of the page, in order. Do not edit: change the page or steps/${step}/commands.sh.`,
    contentPath: `docs/modules/${slug}/pages/${step}.adoc`,
    tests: [{ testId: step, description: `Every command shown on the '${step}' page runs, and every shown output matches`, steps }],
  };
  if (summary.record) {
    // The recording engine needs headed Chrome; screenshots elsewhere use the
    // base config's headless Firefox context at the same size.
    spec.runOn = [{ platforms: ["linux", "mac"], browsers: [{ name: "chrome", headless: false, viewport: { width: 1280, height: 800 } }] }];
  }
  return { spec, summary, list };
}

const ids = stepIds();
const results = ids.map(buildSpec);

if (mode === "list") {
  for (const r of results) for (const l of r.list) console.log(l);
} else if (mode === "media") {
  for (const r of results) for (const p of r.summary.media) console.log(`${r.summary.step}\t${p}`);
} else {
  if (mode === "out") mkdirSync(outDir, { recursive: true });
  for (const r of results) {
    if (mode === "out" && problems.length === 0) {
      writeFileSync(join(outDir, `${r.summary.step}.json`), JSON.stringify(r.spec, null, 2) + "\n");
    }
    const manual = r.summary.manual.length ? `, manual (skipped): ${r.summary.manual.join(", ")}` : "";
    const media = r.summary.mediaSteps ? `, ${r.summary.mediaSteps} media steps (${r.summary.media.map((p) => p.split("/").pop()).join(", ")})` : "";
    console.error(`gen-dd-specs: ${r.summary.step}: ${r.summary.runShell} runShell, ${r.summary.stdio} stdout checks${media}${manual}`);
  }
}
if (problems.length) {
  for (const p of problems) console.error(`gen-dd-specs: ERROR ${p}`);
  process.exit(1);
}
