#!/usr/bin/env node
import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../../..");
const sourcePath = "docs/design/overlay-redesign/06-halo.html";
const manifestPath = process.env.HALO_PARITY_SCENARIO_MANIFEST
  ? path.resolve(process.env.HALO_PARITY_SCENARIO_MANIFEST)
  : "Validation/HaloParity/halo-scenarios.json";
const authorityPath = "Validation/HaloParity/reference/reference-authority-v1.json";
const generatedPath = "Validation/HaloParity/reference/generated/halo-reference-v1.html";
const specPath = "Validation/HaloParity/reference/reference-spec-v1.json";
const variantsPath = "Validation/HaloParity/reference/reference-variants.json";
const lockPath = "Validation/HaloParity/reference/reference-input-lock-v1.json";
const rel = p => path.isAbsolute(p) ? p : path.join(repo, p);
const sha = value => createHash("sha256").update(value).digest("hex");
const canonical = value => JSON.stringify(value, null, 2) + "\n";
const read = p => readFile(rel(p), "utf8");

const source = await read(sourcePath);
const manifest = JSON.parse(await read(manifestPath));
const authorityText = await read(authorityPath);
const authority = JSON.parse(authorityText);

if (authority.source?.sha256 !== sha(source)) {
  throw new Error("reference authority source hash does not match 06-halo.html");
}
const manifestIds = manifest.scenarios.map(s => s.id).sort();
const authorityIds = authority.scenarios.map(s => s.id).sort();
if (JSON.stringify(manifestIds) !== JSON.stringify(authorityIds)) {
  throw new Error("reference authority and scenario manifest ID sets differ");
}
const laws = authority.designLaws;
const established = new Set(
  authority.scenarios
    .filter(s => s.mapping.kind === "established-anchor")
    .map(s => s.id)
);

const variants = {
  schemaVersion: "1.0.0",
  status: "reference-authoring-only-not-passed",
  designLaws: laws,
  decisions: Object.fromEntries(
    authority.scenarios
      .filter(s => s.mapping.kind === "authored-variant")
      .map(s => [
        s.id,
        {
          ...s.mapping.decision,
          provenance: {
            kind: "authored-reference-variant",
            authority: authority.authorityId,
            approval: null,
            parityClaim: "not-passed"
          }
        }
      ])
  )
};

const scenarios = authority.scenarios.map((s, index) => {
  const isEstablished = established.has(s.id);
  return {
    id: s.id,
    ordinal: index + 1,
    referenceSection: s.referenceSection,
    intent: s.intent,
    fixtureSeed: authority.referenceSeed,
    mapping: isEstablished ? {
      kind: "established-anchor",
      selector: s.mapping.selector,
      stateMechanism: s.mapping.stateMechanism,
      provenance: "06-halo.html pre-authored fragment"
    } : {
      kind: "authored-variant",
      variantId: s.mapping.variantId,
      selector: s.mapping.selector,
      sourceAnchor: s.mapping.sourceAnchor,
      laws: s.mapping.laws
    },
    expected: s.expected,
    checkpoints: s.checkpoints,
    events: s.referenceEvents
  };
});

const spec = {
  schemaVersion: "1.0.0",
  status: "not-passed",
  authorityId: authority.authorityId,
  defaultMode: authority.defaultMode,
  controllerSchema: authority.controllerSchema,
  events: authority.events,
  scenarios
};

const specText = canonical(spec);
const variantsText = canonical(variants);
await mkdir(path.dirname(rel(generatedPath)), { recursive: true });
await writeFile(rel(specPath), specText);
await writeFile(rel(variantsPath), variantsText);

const escapeScriptJson = text => text.replace(/</g, "\\u003c").replace(/-->/g, "--\\>");
const headInjection = [
  '<link rel="stylesheet" href="../halo-reference-variants.css" data-halo-injected="styles">',
  '<meta name="halo-reference-harness" content="v1">'
].join("\n");
const bodyInjection = [
  '<div id="halo-reference-status" hidden aria-live="polite"></div>',
  '<div id="halo-reference-fiducial" hidden aria-hidden="true"></div>',
  `<script data-halo-injected="spec">window.__HALO_REFERENCE_SPEC__=${escapeScriptJson(JSON.stringify(spec))};window.__HALO_REFERENCE_VARIANTS__=${escapeScriptJson(JSON.stringify(variants))};</script>`,
  '<script src="../halo-reference-export.js" data-halo-injected="export"></script>',
  '<script src="../halo-reference-controller.js" data-halo-injected="controller"></script>'
].join("\n");
if (!source.includes("</head>") || !source.includes("</body>")) throw new Error("reference source is missing deterministic injection anchors");
const generated = source.replace("</head>", `${headInjection}\n</head>`).replace("</body>", `${bodyInjection}\n</body>`);
await writeFile(rel(generatedPath), generated);

const inputPaths = [
  sourcePath, authorityPath,
  "Validation/HaloParity/reference/build-reference-harness.mjs",
  "Validation/HaloParity/reference/halo-reference-controller.js",
  "Validation/HaloParity/reference/halo-reference-variants.css",
  "Validation/HaloParity/reference/halo-reference-export.js"
];
const inputs = [];
for (const p of inputPaths) inputs.push({ path: p, sha256: sha(await read(p)) });
const merkleRoot = sha(inputs.map(x => `${x.path}\0${x.sha256}`).sort().join("\n"));
const lock = {
  schemaVersion: "1.0.0",
  algorithm: "sha256",
  generation: "deterministic-no-timestamps",
  merkleConstruction: "sha256(sorted(path + NUL + sha256(file)).join(LF))",
  merkleRoot,
  inputs,
  outputs: [
    { path: generatedPath, sha256: sha(generated) },
    { path: specPath, sha256: sha(specText) },
    { path: variantsPath, sha256: sha(variantsText) }
  ],
  sourceImmutability: { path: sourcePath, sha256: sha(source) }
};
await writeFile(rel(lockPath), canonical(lock));
console.log(`built ${generatedPath}`);
console.log(`scenarios=${scenarios.length} established=${established.size} authored=${scenarios.length - established.size}`);
console.log(`source=${sha(source)} generated=${sha(generated)} merkle=${merkleRoot}`);
