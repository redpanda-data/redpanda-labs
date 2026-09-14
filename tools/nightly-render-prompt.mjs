#!/usr/bin/env node
// Render the nightly investigation prompt.
//
//   node tools/nightly-render-prompt.mjs <template.md> <output.md>
//
// Substitutes every ${NAME} in the template with the environment variable of
// that name, literally: no shell, no sed. sed's replacement text is not
// literal (& re-inserts the whole match) and its delimiter can appear in a
// value, and a prompt is the one input a model reads as instructions, so a
// value that rewrites the surrounding text is worth ruling out by
// construction.
//
// Fails, rather than rendering something half-substituted, when a placeholder
// has no value in the environment or when any ${NAME} survives. A prompt that
// still says ${ISSUE_NUMBER} would send the investigation to comment on an
// issue that does not exist.
//
// Lives in its own file, called with no inline JavaScript, so the workflow
// step that calls it holds no single-quoted script: that keeps shellcheck
// quiet about the `${` inside it (SC2016) and keeps the substitution testable
// outside CI.
import { readFileSync, writeFileSync } from "node:fs";

const [template, output] = process.argv.slice(2);
if (!template || !output) {
  console.error("usage: nightly-render-prompt.mjs <template.md> <output.md>");
  process.exit(2);
}

const placeholder = /\$\{([A-Z_][A-Z0-9_]*)\}/g;
let text = readFileSync(template, "utf8");
const names = [...new Set([...text.matchAll(placeholder)].map((m) => m[1]))];

const missing = names.filter((n) => !process.env[n]);
if (missing.length) {
  console.error(`nightly-render-prompt: no value for ${missing.join(", ")}`);
  process.exit(1);
}

for (const name of names) {
  text = text.split(`$\{${name}}`).join(process.env[name]);
}

const left = text.match(placeholder);
if (left) {
  console.error(`nightly-render-prompt: unsubstituted ${[...new Set(left)].join(", ")}`);
  process.exit(1);
}

writeFileSync(output, text);
console.error(`nightly-render-prompt: substituted ${names.join(", ")}`);
