#!/usr/bin/env node
import { createHash } from "node:crypto";
import { access, readFile, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../../..");
const sourcePath = path.join(repo, "docs/design/overlay-redesign/06-halo.html");
const specPath = path.join(here, "reference-spec-v1.json");
const variantsPath = path.join(here, "reference-variants.json");
const outputPath = path.join(here, "reference-authority-v1.json");
const sha256 = value => createHash("sha256").update(value).digest("hex");

if (process.argv.includes("--force")) {
  throw new Error(
    "--force is forbidden: the authored authority cannot be overwritten from generated artifacts"
  );
}
try {
  await access(outputPath, constants.F_OK);
  throw new Error(
    "reference-authority-v1.json already exists; review and edit the authored authority directly"
  );
} catch (error) {
  if (error.code !== "ENOENT") throw error;
}

const source = await readFile(sourcePath);
const spec = JSON.parse(await readFile(specPath, "utf8"));
const variants = JSON.parse(await readFile(variantsPath, "utf8"));
const scenarios = spec.scenarios.map(scenario => {
  const intent = scenario.id === "RESPONSIVE-560"
    ? "The HTML board's narrow rule is recorded without treating it as a shipped capture profile."
    : scenario.intent;
  const expected = structuredClone(scenario.expected);
  if (scenario.id === "K-condense") {
    expected.lightBehavior = "1.9s attention pulse.";
  }
  if (scenario.mapping.kind === "established-anchor") {
    return {
      id: scenario.id,
      referenceSection: scenario.referenceSection,
      intent,
      mapping: {
        kind: "established-anchor",
        selector: scenario.mapping.selector,
        stateMechanism: scenario.mapping.stateMechanism
      },
      expected,
      checkpoints: scenario.checkpoints,
      referenceEvents: []
    };
  }
  const decision = variants.decisions[scenario.id];
  if (!decision) throw new Error(`missing authored decision for ${scenario.id}`);
  const frameZeroEvent = decision.eventSeam?.frameZeroEvent;
  return {
    id: scenario.id,
    referenceSection: scenario.referenceSection,
    intent,
    mapping: {
      kind: "authored-variant",
      variantId: scenario.id,
      selector: `[data-halo-authored="${scenario.id}"]`,
      sourceAnchor: decision.cloneSelector,
      laws: decision.laws,
      decision: {
        cloneSelector: decision.cloneSelector,
        laws: decision.laws,
        eventSeam: decision.eventSeam,
        patches: decision.patches.map(patch =>
          scenario.id === "RESPONSIVE-560" && patch.name === "aria-label"
            ? { ...patch, value: intent }
            : patch
        )
      }
    },
    expected,
    checkpoints: scenario.checkpoints,
    referenceEvents:
      frameZeroEvent && frameZeroEvent !== "none" ? [frameZeroEvent] : []
  };
});

const authority = {
  schemaVersion: "1.0.0",
  authorityId: "halo-reference-authority-v1",
  status: "pending-authorized-human-approval",
  source: {
    path: "docs/design/overlay-redesign/06-halo.html",
    sha256: sha256(source)
  },
  referenceSeed: "halo-parity-reference-v1",
  designLaws: variants.designLaws,
  defaultMode: spec.defaultMode,
  controllerSchema: spec.controllerSchema,
  events: spec.events,
  scenarios
};

await writeFile(outputPath, JSON.stringify(authority, null, 2) + "\n");
console.log(`froze ${path.relative(repo, outputPath)}`);
console.log(`scenarios=${scenarios.length} sha256=${sha256(await readFile(outputPath))}`);
