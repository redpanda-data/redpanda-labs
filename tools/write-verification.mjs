#!/usr/bin/env node
// Write docs/modules/<slug>/attachments/verification.json from the results of
// a Doc Detective run that passed.
//
//   node tools/write-verification.mjs <slug> <results-file>
//
// Called by tools/run-doc-detective.sh after the verdict is parsed, and only
// when every spec passed. The file is evidence: every number in it is counted
// from the run's own results, never authored, and nothing is derived from the
// pages. That is the whole point, so this script has two rules:
//
//   It writes only a complete manifest. Every field is computed first and the
//   file is written once, through a temporary file and a rename, so a crash
//   or a full disk cannot leave a half-written manifest behind that looks
//   like evidence.
//
//   It writes only what the run produced. The one value read from outside the
//   results file is the Redpanda version, which comes from the .env the run
//   used (falling back to .env.example, which is what `make up` copies).
//
// Why a manifest at all: the generated specs live in a transient run
// directory and never reach the Antora catalog, so nothing at build time can
// otherwise know what a test run proved. This file is an attachment, so the
// build sees it like any other published file.
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// Paths are resolved against the repository this script lives in, not against
// the working directory: tools/run-doc-detective.sh calls it from inside
// solutions/<slug>/, which is where the results file is written.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const [slug, resultsPath] = process.argv.slice(2);
if (!slug || !resultsPath) {
  console.error("usage: write-verification.mjs <slug> <results-file>");
  process.exit(2);
}

const fail = (msg) => {
  console.error(`write-verification: ${msg}`);
  process.exit(1);
};

let results;
try {
  results = JSON.parse(readFileSync(resultsPath, "utf8"));
} catch (e) {
  fail(`cannot read ${resultsPath}: ${e.message}`);
}

// Every context that actually ran. Doc Detective emits a context per platform
// and skips the ones that do not apply, and a skipped context has no steps, so
// counting steps over every context would count the same spec twice.
const contexts = [];
for (const spec of results.specs || []) {
  for (const test of spec.tests || []) {
    for (const ctx of test.contexts || [test]) {
      if ((ctx.steps || []).length) contexts.push(ctx);
    }
  }
}
if (!contexts.length) fail("the results file records no step that ran");

let steps = 0;
let commands = 0;
let checks = 0;
let verifyLine = "";
const mediaPaths = new Set();

for (const ctx of contexts) {
  for (const step of ctx.steps || []) {
    steps += 1;
    const outputs = step.outputs || {};
    if (step.runShell !== undefined) {
      commands += 1;
      const shell = typeof step.runShell === "object" ? step.runShell : { command: String(step.runShell) };
      if (shell.stdio) checks += 1;
      // The verify script's own verdict, taken from the step that ran it
      // rather than from anything this script knows how to compute. The last
      // such step wins: a solution shows the full output and then the summary
      // line, and the summary line is the claim.
      if ((shell.command || "").includes("scripts/verify.sh") || (shell.command || "").includes("make verify")) {
        const out = String((outputs.stdio || {}).stdout || "").trim();
        const lines = out.split("\n").map((l) => l.trim()).filter(Boolean);
        if (lines.length) verifyLine = lines[lines.length - 1];
      }
    }
    // A recording reports its path on the stopRecord step as well as the
    // record step, so count distinct output paths rather than steps.
    for (const key of ["screenshotPath", "recordingPath"]) {
      if (outputs[key]) mediaPaths.add(String(outputs[key]));
    }
  }
}

const specSummary = (results.summary || {}).specs || {};
const specsRun = ["pass", "fail", "warning"].reduce((n, k) => n + (specSummary[k] || 0), 0) || contexts.length;

// The run's own id is its UTC start time with : and . replaced, which is what
// doc-detective names the run directory. Turned back into a real ISO instant
// so the manifest is machine-readable; if the shape ever changes, say so
// rather than inventing a timestamp.
const runId = String(results.runId || "");
const m = runId.match(/^(\d{4}-\d{2}-\d{2})T(\d{2})-(\d{2})-(\d{2})-(\d{3})Z$/);
if (!m) fail(`cannot read the run's timestamp from runId ${JSON.stringify(runId)}`);
const runAt = `${m[1]}T${m[2]}:${m[3]}:${m[4]}.${m[5]}Z`;

// The version the run actually used. .env is what the services and rpk read;
// .env.example is what `make up` copies it from.
const readVersion = () => {
  for (const name of [".env", ".env.example"]) {
    const path = join(root, "solutions", slug, name);
    if (!existsSync(path)) continue;
    for (const line of readFileSync(path, "utf8").split("\n")) {
      const hit = line.match(/^REDPANDA_VERSION=(.*)$/);
      if (hit) return hit[1].trim();
    }
  }
  return "";
};
const redpandaVersion = readVersion();
if (!redpandaVersion) fail(`no REDPANDA_VERSION in solutions/${slug}/.env or .env.example`);
if (!verifyLine) fail("no step ran the verify script, so there is no verdict to record");

const manifest = {
  suite: "doc-detective",
  specs: specsRun,
  steps,
  commands,
  checks,
  media: mediaPaths.size,
  verify_script: verifyLine,
  redpanda_version: redpandaVersion,
  run_at: runAt,
};

const out = join(root, "docs", "modules", slug, "attachments", "verification.json");
mkdirSync(dirname(out), { recursive: true });
const tmp = `${out}.tmp`;
writeFileSync(tmp, `${JSON.stringify(manifest, null, 2)}\n`);
renameSync(tmp, out);
console.error(`write-verification: docs/modules/${slug}/attachments/verification.json (${manifest.specs} specs, ${manifest.steps} steps, ${manifest.commands} commands, ${manifest.checks} checks, ${manifest.media} media, ${manifest.verify_script})`);
