(function (global) {
  "use strict";
  const spec = global.__HALO_REFERENCE_SPEC__;
  const variants = global.__HALO_REFERENCE_VARIANTS__;
  if (!spec || !variants) throw new Error("Halo reference spec and variants must load before the controller");

  const schema = spec.controllerSchema;
  const allowedKeys = new Set(schema.required);
  const state = {
    config: null,
    phase: "inert",
    selected: null,
    animations: [],
    generation: 0
  };

  function assertEnum(name, value, values) {
    if (!values.includes(value)) throw new RangeError(`${name} must be one of: ${values.join(", ")}`);
  }

  function validateConfig(config) {
    if (!config || typeof config !== "object" || Array.isArray(config)) throw new TypeError("config must be an object");
    const keys = Object.keys(config);
    const unknown = keys.filter(k => !allowedKeys.has(k));
    const missing = schema.required.filter(k => !(k in config));
    if (unknown.length) throw new TypeError(`unknown config keys: ${unknown.join(", ")}`);
    if (missing.length) throw new TypeError(`missing config keys: ${missing.join(", ")}`);
    assertEnum("scenarioId", config.scenarioId, schema.scenarioIds);
    assertEnum("profile", config.profile, schema.profiles);
    assertEnum("motionMode", config.motionMode, schema.motionModes);
    assertEnum("accessibilityMode", config.accessibilityMode, schema.accessibilityModes);
    assertEnum("eventId", config.eventId, schema.eventIds);
    if (typeof config.seed !== "string" || !(new RegExp(schema.seedPattern)).test(config.seed)) throw new RangeError("seed is invalid");
    if (!Number.isFinite(config.timeMs) || config.timeMs < schema.timeMs.minimum || config.timeMs > schema.timeMs.maximum) throw new RangeError("timeMs is out of range");
    return Object.freeze({ ...config, timeMs: Number(config.timeMs) });
  }

  function aliases() {
    const sections = document.querySelectorAll("body > .board > section");
    return Array.from({ length: 11 }, (_, i) => sections[i]);
  }

  function resolveSelector(expression) {
    const ss = aliases();
    const names = ss.map((_, i) => `S${i + 1}`);
    const fn = Function(...names, `"use strict"; return (${expression});`);
    const result = fn(...ss);
    if (!result) throw new Error(`selector did not resolve: ${expression}`);
    return Array.isArray(result) ? result[0] : result;
  }

  function scoped(root, selector) {
    if (selector === ":scope") return root;
    if (selector.includes(":scope")) {
      const direct = selector.split(",").map(x => x.trim()).find(x => x === ":scope");
      if (direct) return root;
    }
    return root.querySelector(selector);
  }

  function applyPatch(root, patch) {
    const target = scoped(root, patch.selector);
    if (!target) return;
    if (patch.op === "setAttribute") target.setAttribute(patch.name, patch.value);
    else if (patch.op === "replaceText") target.textContent = patch.value;
    else if (patch.op === "setStateClass") {
      if (patch.value) target.classList.add(patch.value);
    }
    else if (patch.op === "appendBadge") {
      const badge = document.createElement("span");
      badge.className = "halo-reference-provenance";
      badge.setAttribute("data-halo-authored-note", patch.value);
      badge.textContent = patch.value;
      target.appendChild(badge);
    } else throw new Error(`unknown variant patch operation: ${patch.op}`);
  }

  function buildScenario(scenario) {
    let source;
    let provenance;
    if (scenario.mapping.kind === "established-anchor") {
      source = resolveSelector(scenario.mapping.selector);
      provenance = { kind: "established-anchor", selector: scenario.mapping.selector };
    } else {
      const decision = variants.decisions[scenario.mapping.variantId];
      if (!decision) throw new Error(`missing authored decision for ${scenario.id}`);
      source = resolveSelector(decision.cloneSelector);
      provenance = decision.provenance;
    }
    const clone = source.cloneNode(true);
    clone.setAttribute("data-halo-reference-root", "");
    clone.setAttribute("data-halo-scenario-id", scenario.id);
    clone.setAttribute("data-halo-provenance-kind", provenance.kind);
    if (scenario.mapping.kind === "authored-variant") {
      for (const patch of variants.decisions[scenario.id].patches) applyPatch(clone, patch);
    }
    return clone;
  }

  function ensureStage() {
    let stage = document.getElementById("halo-reference-stage");
    if (!stage) {
      stage = document.createElement("main");
      stage.id = "halo-reference-stage";
      stage.setAttribute("aria-label", "Halo deterministic reference stage");
      document.body.appendChild(stage);
    }
    return stage;
  }

  function discoverAnimations() {
    state.animations = state.selected && typeof state.selected.getAnimations === "function"
      ? state.selected.getAnimations({ subtree: true }) : [];
    return state.animations;
  }

  function seek(ms) {
    if (!Number.isFinite(ms) || ms < 0 || ms > schema.timeMs.maximum) throw new RangeError("seek time is out of range");
    for (const animation of discoverAnimations()) {
      animation.pause();
      const timing = animation.effect && animation.effect.getComputedTiming ? animation.effect.getComputedTiming() : {};
      const duration = Number(timing.duration);
      animation.currentTime = Number.isFinite(duration) && duration > 0 && timing.iterations !== 1 ? ms % duration : ms;
    }
    if (state.config) state.config = Object.freeze({ ...state.config, motionMode: "manual", timeMs: ms });
    document.documentElement.dataset.haloMotion = "manual";
    updateStatus();
    return dumpDOM();
  }

  function playNormal() {
    for (const animation of discoverAnimations()) animation.play();
    if (state.config) state.config = Object.freeze({ ...state.config, motionMode: "normal" });
    document.documentElement.dataset.haloMotion = "normal";
    updateStatus();
    return dumpDOM();
  }

  function setState(config) {
    const checked = validateConfig(config);
    const scenario = spec.scenarios.find(x => x.id === checked.scenarioId);
    const stage = ensureStage();
    stage.replaceChildren();
    state.selected = buildScenario(scenario);
    stage.appendChild(state.selected);
    state.config = checked;
    state.phase = spec.events[checked.eventId]?.to || "selected";
    state.generation += 1;
    const html = document.documentElement;
    html.dataset.haloHarness = "true";
    html.dataset.haloScenario = checked.scenarioId;
    html.dataset.haloProfile = checked.profile;
    html.dataset.haloMotion = checked.motionMode;
    html.dataset.haloA11y = checked.accessibilityMode;
    html.dataset.haloPhase = state.phase;
    state.selected.setAttribute("data-halo-phase", state.phase);
    discoverAnimations();
    if (checked.motionMode === "normal") playNormal();
    else {
      seek(checked.timeMs);
      state.config = checked;
      html.dataset.haloMotion = checked.motionMode;
    }
    updateStatus();
    return dumpDOM();
  }

  function dispatchEvent(eventId, payload) {
    assertEnum("eventId", eventId, schema.eventIds);
    if (payload !== undefined && (!payload || typeof payload !== "object" || Array.isArray(payload))) throw new TypeError("event payload must be an object");
    if (!state.config) throw new Error("setState must be called before dispatchEvent");
    state.phase = spec.events[eventId].to;
    state.config = Object.freeze({ ...state.config, eventId });
    document.documentElement.dataset.haloPhase = state.phase;
    state.selected.setAttribute("data-halo-phase", state.phase);
    state.selected.setAttribute("data-halo-event-payload", JSON.stringify(payload || {}));
    updateStatus();
    return dumpDOM();
  }

  function transitionPhase(eventId) {
    assertEnum("eventId", eventId, schema.eventIds);
    return spec.events[eventId].to;
  }

  function reset() {
    for (const animation of state.animations) animation.cancel();
    document.getElementById("halo-reference-stage")?.remove();
    const html = document.documentElement;
    for (const key of ["haloHarness", "haloScenario", "haloProfile", "haloMotion", "haloA11y", "haloPhase", "haloDebug"]) delete html.dataset[key];
    state.config = null; state.phase = "inert"; state.selected = null; state.animations = [];
    const status = document.getElementById("halo-reference-status");
    if (status) status.hidden = true;
    return { phase: state.phase, originalBoardVisible: true };
  }

  function textInventory(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const values = [];
    let node;
    while ((node = walker.nextNode())) {
      const value = node.nodeValue.replace(/\s+/g, " ").trim();
      if (value) values.push(value);
    }
    return values;
  }

  function dumpDOM() {
    return {
      schemaVersion: "1.0.0",
      generation: state.generation,
      phase: state.phase,
      config: state.config,
      scenario: state.config ? spec.scenarios.find(x => x.id === state.config.scenarioId) : null,
      provenance: state.selected ? {
        kind: state.selected.getAttribute("data-halo-provenance-kind"),
        authored: state.selected.getAttribute("data-halo-authored")
      } : null,
      copy: state.selected ? textInventory(state.selected) : [],
      dom: state.selected ? state.selected.outerHTML : null
    };
  }

  function dumpAXHints() {
    if (!state.selected) return { order: [], warning: "No selected reference scenario." };
    const nodes = [state.selected, ...state.selected.querySelectorAll("*")];
    return {
      order: nodes.filter(el => {
        const role = el.getAttribute("role");
        return role || /^(BUTTON|A|INPUT|SELECT|TEXTAREA)$/.test(el.tagName) || el.hasAttribute("aria-label");
      }).map((el, index) => ({
        index, tag: el.tagName.toLowerCase(), role: el.getAttribute("role"),
        label: el.getAttribute("aria-label") || el.textContent.replace(/\s+/g, " ").trim(),
        tabIndex: el.tabIndex, disabled: Boolean(el.disabled)
      })),
      provenance: "machine-readable hints only; actual IAB accessibility inspection remains required"
    };
  }

  async function exportPNG(options) {
    if (!state.selected) throw new Error("setState must be called before exportPNG");
    return global.HaloReferenceExport.exportCandidatePNG(state.selected, options);
  }

  function updateStatus() {
    const status = document.getElementById("halo-reference-status");
    if (!status) return;
    status.hidden = false;
    status.textContent = state.config ? `${state.config.scenarioId} · ${state.phase} · ${state.config.motionMode} @ ${state.config.timeMs}ms` : "inert";
  }

  function instrumentGeneratedCopy() {
    document.querySelectorAll("body > .board > section").forEach((section, i) => {
      section.id = `halo-reference-section-${i + 1}`;
      section.dataset.haloSectionIndex = String(i + 1);
    });
    document.querySelectorAll(".fid").forEach((fid, i) => fid.dataset.haloAnchorIndex = String(i + 1));
  }

  const ready = new Promise(resolve => {
    const start = () => {
      instrumentGeneratedCopy();
      const query = new URLSearchParams(global.location.search);
      if (query.has("scenario")) {
        const accessibilityMode = query.get("a11y") || "default";
        document.documentElement.dataset.haloDebug = query.get("debug") === "1" ? "true" : "false";
        setState({
          scenarioId: query.get("scenario"),
          profile: query.get("profile") || "notch-v1",
          motionMode: query.get("motion") || "manual",
          accessibilityMode,
          seed: query.get("seed") || "halo-reference-v1",
          eventId: query.get("event") || "none",
          timeMs: Number(query.get("time") || 0)
        });
        if (query.get("exportProbe") === "1") {
          exportPNG({ download: false }).then(result => {
            const html = document.documentElement;
            html.dataset.haloExportSignature = Array.from(result.bytes.slice(0, 8)).join(",");
            html.dataset.haloExportQualification = result.provenance.qualification;
            html.dataset.haloExportCanonical = String(result.provenance.canonicalCapture);
            html.dataset.haloExportDimensions = `${result.width}x${result.height}`;
          }).catch(error => {
            document.documentElement.dataset.haloExportError = String(error);
          });
        }
      }
      resolve({ scenarioCount: spec.scenarios.length, inert: !query.has("scenario") });
    };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
    else start();
  });

  global.HaloReferenceController = Object.freeze({
    ready, setState, dispatchEvent, seek, playNormal, reset, dumpDOM, dumpAXHints, exportPNG,
    validateConfig, transitionPhase
  });
})(window);
