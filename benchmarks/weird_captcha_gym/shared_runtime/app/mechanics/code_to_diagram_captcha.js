(() => {
  "use strict";

  let helpersCache = null;
  let model = null;
  let pointerMoveHandler = null;
  let pointerUpHandler = null;
  let resizeHandler = null;

  function esc(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function nodeById(nodeId) {
    return model.nodes.get(String(nodeId));
  }

  function normalizedWires() {
    return [...model.wires.values()]
      .map((wire) => ({from_port: wire.from_port, label: wire.label, to_node: wire.to_node}))
      .sort((a, b) => a.from_port.localeCompare(b.from_port));
  }

  function pathFor(x1, y1, x2, y2) {
    const bend = Math.max(54, Math.abs(x2 - x1) * 0.42);
    return `M ${x1.toFixed(1)} ${y1.toFixed(1)} C ${(x1 + bend).toFixed(1)} ${y1.toFixed(1)}, ${(x2 - bend).toFixed(1)} ${y2.toFixed(1)}, ${x2.toFixed(1)} ${y2.toFixed(1)}`;
  }

  function portPoint(element, rect) {
    const bounds = element?.getBoundingClientRect();
    if (!bounds) return null;
    return {x: bounds.left + bounds.width / 2 - rect.left, y: bounds.top + bounds.height / 2 - rect.top};
  }

  function drawWires() {
    const canvas = document.querySelector(".flow-canvas");
    const svg = document.getElementById("flow-wire-svg");
    if (!canvas || !svg || !model) return;
    const rect = canvas.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${Math.max(1, rect.width)} ${Math.max(1, rect.height)}`);
    const pieces = [`<defs><marker id="flow-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z"></path></marker></defs>`];
    normalizedWires().forEach((wire, index) => {
      const start = portPoint(document.querySelector(`[data-port-id="${CSS.escape(wire.from_port)}"]`), rect);
      const end = portPoint(document.querySelector(`.flow-port-in[data-node-id="${CSS.escape(wire.to_node)}"]`), rect);
      if (!start || !end) return;
      const midX = (start.x + end.x) / 2;
      const midY = (start.y + end.y) / 2 - 7 - (index % 2) * 4;
      pieces.push(`<path class="flow-wire flow-wire-${wire.label.toLowerCase()}" d="${pathFor(start.x, start.y, end.x, end.y)}" marker-end="url(#flow-arrow)"></path>`);
      pieces.push(`<text class="flow-wire-label" x="${midX.toFixed(1)}" y="${midY.toFixed(1)}">${esc(wire.label)}</text>`);
    });
    if (model.drag) {
      const start = portPoint(document.querySelector(`[data-port-id="${CSS.escape(model.drag.from_port)}"]`), rect);
      if (start) pieces.push(`<path class="flow-wire is-preview" d="${pathFor(start.x, start.y, model.drag.x, model.drag.y)}"></path>`);
    }
    svg.innerHTML = pieces.join("");
  }

  function recordWire(action, wire) {
    model.wireEvents.push({
      sequence: model.wireEvents.length + 1,
      action,
      from_port: wire.from_port,
      label: wire.label,
      to_node: wire.to_node,
    });
  }

  function clearFreshFailure() {
    const root = document.querySelector(".flow-lab");
    if (!root || root.dataset.freshFailure !== "true") return;
    root.dataset.freshFailure = "false";
    document.querySelector(".flow-fail-stamp")?.remove();
    helpersCache.setReadout("RIG LIVE · PROBE AND PATCH", "idle");
  }

  function renderWireLedger() {
    const ledger = document.getElementById("flow-wire-ledger");
    if (!ledger) return;
    const wires = normalizedWires();
    ledger.innerHTML = wires.length ? wires.map((wire) => `
      <li><b>${esc(wire.from_port)}</b><span>→ ${esc(wire.to_node)}</span><i>${esc(wire.label)}</i><button type="button" data-remove-port="${esc(wire.from_port)}" aria-label="remove ${esc(wire.from_port)} wire">×</button></li>`).join("") : "<li class=\"is-empty\">NO PATCH CORDS INSTALLED</li>";
    ledger.querySelectorAll("[data-remove-port]").forEach((button) => {
      button.addEventListener("click", () => {
        const fromPort = String(button.dataset.removePort || "");
        const old = model.wires.get(fromPort);
        if (!old || model.submitting || model.terminal) return;
        clearFreshFailure();
        recordWire("disconnect", old);
        model.wires.delete(fromPort);
        renderWireLedger();
        drawWires();
        updateReadiness();
      });
    });
    const count = document.getElementById("flow-wire-count");
    if (count) count.textContent = `${String(wires.length).padStart(2, "0")} / 06`;
  }

  function connectWire(fromPort, label, toNode) {
    const sourceNode = fromPort.split(":", 1)[0];
    if (!toNode || toNode === sourceNode || model.submitting || model.terminal) return;
    clearFreshFailure();
    const old = model.wires.get(fromPort);
    if (old && old.to_node === toNode) return;
    if (old) {
      recordWire("disconnect", old);
      model.wires.delete(fromPort);
    }
    const wire = {from_port: fromPort, label, to_node: toNode};
    recordWire("connect", wire);
    model.wires.set(fromPort, wire);
    renderWireLedger();
    drawWires();
    updateReadiness();
  }

  function beginWire(event) {
    if (!model || model.submitting || model.terminal) return;
    event.preventDefault();
    const button = event.currentTarget;
    const canvas = document.querySelector(".flow-canvas");
    const rect = canvas?.getBoundingClientRect();
    if (!rect) return;
    clearFreshFailure();
    model.drag = {
      from_port: String(button.dataset.portId || ""),
      label: String(button.dataset.label || ""),
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
    button.setPointerCapture?.(event.pointerId);
    drawWires();
  }

  function renderProbeButtons() {
    document.querySelectorAll("[data-probe-index]").forEach((button) => {
      const index = Number(button.dataset.probeIndex);
      const value = Number(model.state.probe_inputs[index]);
      button.dataset.status = model.completedInputs.has(value) ? "done" : model.currentRun?.input === value ? "active" : "waiting";
      button.disabled = model.completedInputs.has(value) || model.submitting || model.terminal;
    });
  }

  function updateReadiness() {
    const probes = model.probeRuns.length;
    const nodes = model.coverage.size;
    const probeCount = document.getElementById("flow-probe-count");
    const coverage = document.getElementById("flow-coverage-count");
    if (probeCount) probeCount.textContent = `${probes} / 3`;
    if (coverage) coverage.textContent = `${nodes} / 6`;
    const ready = probes === 3 && nodes === 6 && model.wires.size === 6;
    const button = document.getElementById("flow-certify");
    if (button) button.dataset.ready = ready ? "true" : "false";
    if (ready && !model.submitting && !model.terminal) helpersCache.setReadout("HARNESS POPULATED · READY TO VALIDATE", "idle");
  }

  function startProbe(index) {
    if (!model || model.submitting || model.terminal) return;
    const input = Number(model.state.probe_inputs[index]);
    if (model.completedInputs.has(input)) return;
    clearFreshFailure();
    const runtime = model.runtimeRuns.get(input);
    if (!runtime) throw new Error("debugger trace is unavailable");
    model.currentRun = {input, runtime, stepIndex: 0, steps: []};
    const stepButton = document.getElementById("flow-step");
    if (stepButton) stepButton.disabled = false;
    const display = document.getElementById("flow-current-state");
    if (display) display.innerHTML = `<span>PROBE ${input >= 0 ? "+" : ""}${input} ARMED</span><b>PRESS STEP</b>`;
    renderProbeButtons();
    helpersCache.setReadout("DEBUGGER ARMED · STATE WILL ERASE", "idle");
  }

  function stepProbe() {
    if (!model?.currentRun || model.submitting || model.terminal) return;
    clearFreshFailure();
    const run = model.currentRun;
    const runtimeStep = run.runtime.steps[run.stepIndex];
    const node = nodeById(runtimeStep?.node_id);
    if (!node) return;
    const step = {
      sequence: Number(runtimeStep.sequence),
      node_id: String(runtimeStep.node_id),
      value_before: Number(runtimeStep.value_before),
      value_after: Number(runtimeStep.value_after),
      branch: String(runtimeStep.branch),
      next_node_id: runtimeStep.next_node_id == null ? null : String(runtimeStep.next_node_id),
    };
    run.steps.push(step);
    run.stepIndex += 1;
    model.coverage.add(node.id);
    document.querySelectorAll(".flow-node").forEach((item) => item.classList.remove("is-debug-active"));
    const active = document.querySelector(`.flow-node[data-node-id="${CSS.escape(node.id)}"]`);
    active?.classList.add("is-debug-active");
    const display = document.getElementById("flow-current-state");
    if (display) display.innerHTML = `<span>NODE ${esc(node.id)} / ${esc(step.branch)}</span><b>ACC ${step.value_before} → ${step.value_after}</b>`;
    const tape = document.getElementById("flow-probe-tape");
    tape?.querySelector(".is-empty")?.remove();
    tape?.querySelectorAll("li:not(.is-empty)").forEach((oldRow) => {
      const oldNode = oldRow.querySelector("b");
      const oldDetail = oldRow.querySelector(".flow-trace-detail");
      if (oldNode) oldNode.textContent = "••";
      if (oldDetail) oldDetail.textContent = "STATE ERASED";
    });
    const rowId = `trace-${model.traceSequence += 1}`;
    tape?.insertAdjacentHTML("afterbegin", `<li id="${rowId}"><i>${String(step.sequence).padStart(2, "0")}</i><b>${esc(node.id)}</b><span class="flow-trace-detail">${esc(step.branch)} · ${step.value_before}→${step.value_after}</span></li>`);
    while (tape && tape.children.length > 7) tape.lastElementChild?.remove();
    window.setTimeout(() => {
      active?.classList.remove("is-debug-active");
      const detail = document.querySelector(`#${rowId} .flow-trace-detail`);
      const oldNode = document.querySelector(`#${rowId} b`);
      if (oldNode) oldNode.textContent = "••";
      if (detail) detail.textContent = "STATE ERASED";
      if (display && model?.currentRun === run) display.innerHTML = "<span>TRANSIENT REGISTER</span><b>•• ERASED ••</b>";
    }, 720);

    if (step.branch === "HALT") {
      const finished = {input: run.input, steps: run.steps, halted: true, output: step.value_after};
      model.probeRuns.push(finished);
      model.completedInputs.add(run.input);
      model.currentRun = null;
      const stepButton = document.getElementById("flow-step");
      if (stepButton) stepButton.disabled = true;
      helpersCache.setReadout(`PROBE ${run.input} CAPTURED · REGISTER ERASED`, "idle");
      renderProbeButtons();
    }
    updateReadiness();
  }

  async function certify() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    document.getElementById("flow-certify")?.setAttribute("disabled", "disabled");
    helpersCache.setReadout("REPLAYING PROBES + CONTINUITY TEST…", "pending");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      challenge_id: model.state.challenge_id,
      probe_runs: model.probeRuns,
      wire_events: model.wireEvents,
      final_wires: normalizedWires(),
      completed: true,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".flow-lab")?.classList.add("is-pass");
        document.getElementById("flow-verdict")?.classList.add("is-pass");
        const verdict = document.getElementById("flow-verdict");
        if (verdict) verdict.innerHTML = "<span>CONTROL PATH VERIFIED</span><strong>PASS</strong><i>ALL PROBES / ALL WIRES</i>";
        helpersCache.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await helpersCache.render(outcome.state);
        const root = document.querySelector(".flow-lab");
        if (root) root.dataset.freshFailure = "true";
        root?.insertAdjacentHTML("beforeend", '<div class="flow-fail-stamp"><span>SCHEMATIC REJECTED</span><strong>FAIL</strong><i>FRESH RIG ISSUED</i></div>');
        helpersCache.setReadout("FAIL · FRESH RIG ISSUED", "error");
      } else {
        helpersCache.setReadout("FAIL · GRADE UNAVAILABLE", "error");
        model.submitting = false;
        document.getElementById("flow-certify")?.removeAttribute("disabled");
      }
    } catch (_error) {
      helpersCache.setReadout("FAIL · CONTROL LINK OFFLINE", "error");
      model.submitting = false;
      document.getElementById("flow-certify")?.removeAttribute("disabled");
    }
  }

  function nodeMarkup(node) {
    const outputs = (node.ports || []).map((label) => `<button type="button" class="flow-port-out is-${String(label).toLowerCase()}" data-port-id="${esc(node.id)}:${esc(label)}" data-label="${esc(label)}"><i></i><span>${esc(label)}</span></button>`).join("");
    return `<article class="flow-node is-${esc(node.kind)}" data-node-id="${esc(node.id)}" style="--x:${Number(node.x)}%;--y:${Number(node.y)}%">
      <button type="button" class="flow-port-in" data-node-id="${esc(node.id)}" aria-label="input for ${esc(node.id)}"><i></i><span>IN</span></button>
      <header><b>${esc(node.id)}</b><span>${esc(node.title)}</span></header>
      <p>${esc(node.code).replaceAll("   ", "<br>")}</p>
      <div class="flow-node-outputs">${outputs}</div>
    </article>`;
  }

  async function render(state, helpers) {
    helpersCache = helpers || helpersCache;
    if (!helpersCache) throw new Error("code_to_diagram_captcha requires runtime helpers");
    if (pointerMoveHandler) window.removeEventListener("pointermove", pointerMoveHandler);
    if (pointerUpHandler) window.removeEventListener("pointerup", pointerUpHandler);
    if (resizeHandler) window.removeEventListener("resize", resizeHandler);
    document.body.dataset.mechanic = "code-flow-wiring";
    document.body.dataset.flowPalette = String(state.palette || "oxide");
    document.body.dataset.cheatMode = helpersCache.isCheatMode() ? "true" : "false";
    model = {
      state,
      nodes: new Map((state.nodes || []).map((node) => [String(node.id), node])),
      runtimeRuns: new Map((state.runtime_probe_runs || []).map((run) => [Number(run.input), run])),
      probeRuns: [],
      currentRun: null,
      completedInputs: new Set(),
      coverage: new Set(),
      traceSequence: 0,
      wires: new Map(),
      wireEvents: [],
      drag: null,
      submitting: false,
      terminal: false,
    };
    helpersCache.app.innerHTML = `<section class="flow-lab" data-challenge-id="${esc(state.challenge_id)}" data-fresh-failure="false">
      <header class="flow-head">
        <div><span>LIVE CONTROL-FLOW WIRING LAB / ${esc(state.program_id)}</span><h1>${esc(state.prompt)}</h1></div>
        <aside><i></i><b>TRANSIENT DEBUG BUS</b><span>STATE ERASES AFTER EACH STEP</span></aside>
      </header>
      <main class="flow-main">
        <aside class="flow-debugger">
          <div class="flow-panel-title"><span>01 / PROBE THE PROGRAM</span><i>REQUIRED</i></div>
          <ol class="flow-code-list">${(state.nodes || []).map((node) => `<li><b>${esc(node.id)}</b><code>${esc(node.code)}</code></li>`).join("")}</ol>
          <div class="flow-probe-picker">${(state.probe_inputs || []).map((value, index) => `<button type="button" data-probe-index="${index}" data-status="waiting"><span>PROBE</span><b>${Number(value) >= 0 ? "+" : ""}${Number(value)}</b></button>`).join("")}</div>
          <button class="flow-step" id="flow-step" type="button" disabled><span>STEP DEBUGGER</span><b>→</b></button>
          <div class="flow-current" id="flow-current-state"><span>TRANSIENT REGISTER</span><b>SELECT A PROBE</b></div>
          <ol class="flow-probe-tape" id="flow-probe-tape"><li class="is-empty">NO TRANSIENT TRACE CAPTURED</li></ol>
        </aside>
        <section class="flow-rig">
          <div class="flow-rig-head"><div><span>02 / PATCH THE DIRECTED GRAPH</span><b>DRAG OUTPUT PORT → NODE INPUT</b></div><div><span>PROBES <b id="flow-probe-count">0 / 3</b></span><span>NODES <b id="flow-coverage-count">0 / 6</b></span><span>WIRES <b id="flow-wire-count">00 / 06</b></span></div></div>
          <div class="flow-canvas" aria-label="control-flow wiring board">
            <svg id="flow-wire-svg" aria-hidden="true"></svg>
            ${(state.nodes || []).map(nodeMarkup).join("")}
            <div class="flow-grid-label">PATCH FIELD / ${esc(state.challenge_id).toUpperCase()}</div>
          </div>
          <div class="flow-ledger-shell"><span>PATCH LEDGER</span><ol id="flow-wire-ledger"><li class="is-empty">NO PATCH CORDS INSTALLED</li></ol></div>
        </section>
      </main>
      <footer class="flow-foot"><div class="readout" data-status="idle">RIG LIVE · PROBE AND PATCH</div><span>DEBUGGER EVIDENCE + PHYSICAL WIRE REPLAY</span><button id="flow-certify" type="button">${esc(state.submit_label || "VALIDATE HARNESS")} →</button></footer>
      <div class="flow-verdict" id="flow-verdict"><span>CONTROL PATH</span><strong>LIVE</strong><i>UNVERIFIED</i></div>
      ${helpersCache.cheatPanelTemplate()}
    </section>`;
    document.querySelectorAll("[data-probe-index]").forEach((button) => button.addEventListener("click", () => startProbe(Number(button.dataset.probeIndex))));
    document.getElementById("flow-step")?.addEventListener("click", stepProbe);
    document.getElementById("flow-certify")?.addEventListener("click", certify);
    document.querySelectorAll(".flow-port-out").forEach((button) => button.addEventListener("pointerdown", beginWire));
    pointerMoveHandler = (event) => {
      if (!model?.drag) return;
      const rect = document.querySelector(".flow-canvas")?.getBoundingClientRect();
      if (!rect) return;
      model.drag.x = event.clientX - rect.left;
      model.drag.y = event.clientY - rect.top;
      drawWires();
    };
    pointerUpHandler = (event) => {
      if (!model?.drag) return;
      const drag = model.drag;
      model.drag = null;
      const input = document.elementFromPoint(event.clientX, event.clientY)?.closest?.(".flow-port-in");
      if (input) connectWire(drag.from_port, drag.label, String(input.dataset.nodeId || ""));
      drawWires();
    };
    resizeHandler = () => drawWires();
    window.addEventListener("pointermove", pointerMoveHandler);
    window.addEventListener("pointerup", pointerUpHandler);
    window.addEventListener("resize", resizeHandler);
    renderProbeButtons();
    renderWireLedger();
    updateReadiness();
    window.requestAnimationFrame(drawWires);
    helpersCache.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.code_to_diagram_captcha = {rootSelector: ".flow-lab", render};
})();
