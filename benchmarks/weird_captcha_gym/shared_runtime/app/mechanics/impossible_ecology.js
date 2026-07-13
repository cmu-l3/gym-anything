(() => {
  "use strict";

  let model = null;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function stagePoint(event) {
    const stage = document.querySelector(".eco-stage");
    const rect = stage.getBoundingClientRect();
    return [
      Math.max(0, Math.min(model.state.stage.width, Math.round((event.clientX - rect.left) / rect.width * model.state.stage.width))),
      Math.max(0, Math.min(model.state.stage.height, Math.round((event.clientY - rect.top) / rect.height * model.state.stage.height))),
    ];
  }

  function inside(point, rect) {
    return point[0] >= rect.x && point[0] <= rect.x + rect.width
      && point[1] >= rect.y && point[1] <= rect.y + rect.height;
  }

  function cycleForStep(step) {
    return model.state.cycles.find((cycle) => cycle.step === step);
  }

  function applySnapshot(snapshot) {
    for (const state of snapshot) {
      const organism = document.querySelector(`.eco-organism[data-habitat-id="${CSS.escape(state.habitat_id)}"]`);
      if (!organism) continue;
      organism.style.left = `${state.x}%`;
      organism.style.top = `${state.y}%`;
      organism.style.setProperty("--eco-scale", String(state.scale / 100));
      organism.style.setProperty("--eco-lean", `${state.lean}deg`);
      organism.style.setProperty("--eco-pulse", String(Math.max(0, Math.min(100, state.pulse)) / 100));
      organism.dataset.pulse = String(state.pulse);
    }
  }

  function resetOrganisms() {
    document.querySelectorAll(".eco-organism").forEach((organism) => {
      organism.style.left = "50%";
      organism.style.top = "54%";
      organism.style.setProperty("--eco-scale", "1");
      organism.style.setProperty("--eco-lean", "0deg");
      organism.style.setProperty("--eco-pulse", ".5");
      organism.classList.remove("is-quarantined");
      organism.dataset.pulse = "50";
    });
    document.querySelectorAll(".eco-trace").forEach((trace) => { trace.innerHTML = "<i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i>"; });
  }

  function updateProtocol() {
    document.querySelectorAll(".eco-protocol-step").forEach((step, index) => {
      step.dataset.status = index < model.progress ? "done" : index === model.progress ? "next" : "waiting";
    });
    document.querySelectorAll(".eco-probe").forEach((button) => {
      const next = model.state.protocol[model.progress];
      button.disabled = model.active || model.poisoned || model.progress >= model.state.protocol.length;
      button.classList.toggle("is-next", button.dataset.probe === next && !button.disabled);
    });
    const gate = document.querySelector(".eco-quarantine-gate");
    if (gate) gate.dataset.ready = model.progress === 3 && !model.poisoned ? "true" : "false";
    document.querySelectorAll(".eco-organism").forEach((organism) => {
      organism.dataset.draggable = model.progress === 3 && !model.poisoned ? "true" : "false";
    });
  }

  function traceCycle(snapshot) {
    for (const state of snapshot) {
      const trace = document.querySelector(`.eco-habitat[data-habitat-id="${CSS.escape(state.habitat_id)}"] .eco-trace`);
      if (!trace) continue;
      const direction = state.x > 56 ? "→" : state.x < 44 ? "←" : state.scale > 125 ? "↟" : state.pulse < 40 ? "·" : "↗";
      trace.innerHTML = Array.from({length: 8}, (_, index) => `<i style="height:${10 + Math.abs((state.pulse + index * 7) % 28)}%"></i>`).join("") + `<b>${direction}</b>`;
    }
  }

  function finishCycle(cycle, startedAt) {
    const finalSnapshot = cycle.frames.at(-1).snapshot;
    traceCycle(finalSnapshot);
    record("cycle_complete", {step: cycle.step, probe: cycle.probe, elapsed_ms: Math.round(performance.now() - startedAt)});
    model.completedCycles.push(cycle.probe);
    model.progress += 1;
    model.active = false;
    model.timer = null;
    updateProtocol();
    if (model.progress === model.state.protocol.length) {
      model.helpers.setReadout("PROTOCOL COMPLETE · DRAG THE CAUSAL VIOLATOR INTO QUARANTINE", "idle");
      document.querySelector(".eco-stage")?.classList.add("is-quarantine-ready");
    } else {
      model.helpers.setReadout(`CYCLE STORED · NEXT ${model.state.protocol[model.progress]}`, "idle");
    }
  }

  function runProbe(probe) {
    if (!model || model.submitting || model.terminal || model.active || model.progress >= 3) return;
    document.querySelector(".eco-failure-stamp")?.remove();
    const expected = model.state.protocol[model.progress];
    if (probe !== expected) {
      record("probe_rejected", {probe, expected, step: model.progress});
      model.poisoned = true;
      updateProtocol();
      document.querySelector(".eco-stage")?.classList.add("is-protocol-error");
      model.helpers.setReadout(`PROTOCOL CONTAMINATED · EXPECTED ${expected} · RESET LAB`, "error");
      return;
    }
    const cycle = cycleForStep(model.progress);
    model.active = true;
    record("probe", {step: model.progress, probe});
    updateProtocol();
    document.querySelector(".eco-stage")?.setAttribute("data-active-probe", probe.toLowerCase());
    model.helpers.setReadout(`${probe} RESPONSE RUNNING · OBSERVE ALL FIVE HABITATS`, "pending");
    const startedAt = performance.now();
    let tick = 0;
    model.timer = window.setInterval(() => {
      tick += 1;
      const frame = cycle.frames[tick - 1];
      applySnapshot(frame.snapshot);
      const elapsed = Math.max(Math.round(performance.now() - startedAt), tick * 70);
      record("tick", {step: cycle.step, probe: cycle.probe, tick, elapsed_ms: elapsed, snapshot: frame.snapshot});
      model.tickTotal += 1;
      const meter = document.querySelector(".eco-cycle-meter i");
      if (meter) meter.style.width = `${tick / model.state.ticks_per_cycle * 100}%`;
      const label = document.querySelector(".eco-cycle-meter b");
      if (label) label.textContent = `${probe} ${String(tick).padStart(2, "0")}/${String(model.state.ticks_per_cycle).padStart(2, "0")}`;
      if (tick >= model.state.ticks_per_cycle) {
        window.clearInterval(model.timer);
        finishCycle(cycle, startedAt);
      }
    }, model.state.tick_ms);
  }

  function quarantineDown(event) {
    const organism = event.target.closest(".eco-organism");
    if (!organism || organism.dataset.draggable !== "true" || model.active || model.poisoned || model.terminal) return;
    event.preventDefault();
    const habitatId = organism.dataset.habitatId;
    const point = stagePoint(event);
    record("quarantine_down", {habitat_id: habitatId, point});
    model.drag = {habitatId, pointerId: event.pointerId};
    const stage = document.querySelector(".eco-stage");
    stage.setPointerCapture(event.pointerId);
    const ghost = document.querySelector(".eco-drag-ghost");
    ghost.classList.add("is-visible");
    ghost.dataset.habitatId = habitatId;
    ghost.style.left = `${point[0] / model.state.stage.width * 100}%`;
    ghost.style.top = `${point[1] / model.state.stage.height * 100}%`;
    model.helpers.setReadout(`SPECIMEN ${habitatId.toUpperCase()} IN TRANSFER`, "pending");
  }

  function quarantineMove(event) {
    if (!model?.drag) return;
    event.preventDefault();
    const point = stagePoint(event);
    record("quarantine_move", {habitat_id: model.drag.habitatId, point});
    model.quarantineMoves += 1;
    const ghost = document.querySelector(".eco-drag-ghost");
    ghost.style.left = `${point[0] / model.state.stage.width * 100}%`;
    ghost.style.top = `${point[1] / model.state.stage.height * 100}%`;
  }

  function quarantineUp(event) {
    if (!model?.drag) return;
    event.preventDefault();
    const point = stagePoint(event);
    const habitatId = model.drag.habitatId;
    record("quarantine_up", {habitat_id: habitatId, point});
    const dropped = inside(point, model.state.quarantine_rect);
    model.quarantinedId = dropped ? habitatId : null;
    model.drag = null;
    const ghost = document.querySelector(".eco-drag-ghost");
    ghost.classList.remove("is-visible");
    document.querySelectorAll(".eco-organism").forEach((organism) => organism.classList.toggle("is-quarantined", dropped && organism.dataset.habitatId === habitatId));
    const chamber = document.querySelector(".eco-quarantine");
    if (chamber) {
      chamber.dataset.occupied = dropped ? "true" : "false";
      chamber.querySelector("b").textContent = dropped ? habitatId.toUpperCase() : "EMPTY";
    }
    model.helpers.setReadout(dropped ? `${habitatId.toUpperCase()} SEALED · CERTIFY WHEN READY` : "QUARANTINE DROP MISSED", dropped ? "idle" : "error");
  }

  function resetLab() {
    if (!model || model.submitting || model.terminal) return;
    document.querySelector(".eco-failure-stamp")?.remove();
    if (model.timer) window.clearInterval(model.timer);
    record("reset");
    model.progress = 0;
    model.active = false;
    model.timer = null;
    model.poisoned = false;
    model.completedCycles = [];
    model.tickTotal = 0;
    model.quarantinedId = null;
    model.drag = null;
    model.quarantineMoves = 0;
    model.resetCount += 1;
    resetOrganisms();
    document.querySelector(".eco-stage")?.classList.remove("is-protocol-error", "is-quarantine-ready");
    document.querySelector(".eco-quarantine")?.setAttribute("data-occupied", "false");
    const chamberLabel = document.querySelector(".eco-quarantine b");
    if (chamberLabel) chamberLabel.textContent = "EMPTY";
    const meter = document.querySelector(".eco-cycle-meter i");
    if (meter) meter.style.width = "0";
    updateProtocol();
    model.helpers.setReadout(`LAB RESET · BEGIN WITH ${model.state.protocol[0]}`, "idle");
  }

  async function submit() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    model.helpers.setReadout("REPLAYING CAUSAL RESPONSE RECORD…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          mechanic_id: model.state.mechanic_id,
          challenge_id: model.state.challenge_id,
          events: model.events,
          protocol_progress: model.progress,
          completed_cycles: model.completedCycles,
          quarantined_id: model.quarantinedId,
          tick_total: model.tickTotal,
          quarantine_moves: model.quarantineMoves,
          reset_count: model.resetCount,
          completed: model.progress === 3 && Boolean(model.quarantinedId),
        }),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".impossible-ecology-captcha")?.classList.add("is-pass");
        document.querySelector(".impossible-ecology-captcha")?.insertAdjacentHTML("beforeend", '<div class="eco-verdict eco-verdict-pass"><span>CAUSAL LAW VIOLATION CONTAINED</span><strong>PASS</strong><small>THREE COMPLETE RESPONSE CYCLES VERIFIED</small></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".impossible-ecology-captcha");
        shell?.setAttribute("data-fresh-failure", "true");
        shell?.insertAdjacentHTML("afterbegin", '<div class="eco-failure-stamp"><b>FAIL</b><span>CAUSAL RECORD REJECTED · FRESH TERRARIUM ISSUED</span></div>');
        const readout = document.querySelector(".readout");
        if (readout) { readout.textContent = "FAIL · FRESH TERRARIUM ISSUED"; readout.dataset.status = "error"; }
      } else {
        model.submitting = false;
        model.helpers.setReadout("FAIL · NO AUTHORITATIVE GRADE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("FAIL · LAB VERIFIER OFFLINE", "error");
    }
  }

  function habitatMarkup(habitat) {
    const stage = model.state.stage;
    const rect = habitat.rect;
    return `<article class="eco-habitat" data-habitat-id="${clean(habitat.id)}" style="left:${rect.x / stage.width * 100}%;top:${rect.y / stage.height * 100}%;width:${rect.width / stage.width * 100}%;height:${rect.height / stage.height * 100}%"><header><span>${clean(habitat.label)}</span><i>LIVE</i></header><div class="eco-tank"><div class="eco-lamp"></div><div class="eco-food"></div><div class="eco-organism" data-habitat-id="${clean(habitat.id)}" data-draggable="false"><i></i><b></b><em></em></div><div class="eco-substrate"></div></div><footer><span>RESPONSE TRACE</span><div class="eco-trace"><i></i><i></i><i></i><i></i><i></i><i></i><i></i><i></i></div></footer></article>`;
  }

  async function render(state, helpers) {
    document.body.dataset.mechanic = "impossible-ecology";
    document.body.dataset.ecologyPalette = state.palette;
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {
      state,
      helpers,
      progress: 0,
      active: false,
      timer: null,
      poisoned: false,
      events: [],
      completedCycles: [],
      tickTotal: 0,
      quarantinedId: null,
      quarantineMoves: 0,
      resetCount: 0,
      drag: null,
      submitting: false,
      terminal: false,
    };
    window.impossibleEcologyModel = model;
    const quarantine = state.quarantine_rect;
    helpers.app.innerHTML = `<section class="impossible-ecology-captcha" data-challenge-id="${clean(state.challenge_id)}"><header class="eco-head"><div><span>CAUSAL TERRARIUM / QUARANTINE LAB</span><h1>${clean(state.prompt)}</h1></div><div class="eco-protocol">${state.protocol.map((probe, index) => `<div class="eco-protocol-step" data-status="${index === 0 ? "next" : "waiting"}"><b>${String(index + 1).padStart(2, "0")}</b><span>${clean(probe)}</span></div>`).join("")}</div></header><main class="eco-main"><section class="eco-stage">${state.habitats.map(habitatMarkup).join("")}<div class="eco-quarantine" data-occupied="false" style="left:${quarantine.x / state.stage.width * 100}%;top:${quarantine.y / state.stage.height * 100}%;width:${quarantine.width / state.stage.width * 100}%;height:${quarantine.height / state.stage.height * 100}%"><span>SEALED QUARANTINE</span><b>EMPTY</b><i></i></div><div class="eco-quarantine-gate" data-ready="false">DRAG SPECIMEN HERE AFTER ALL THREE CYCLES</div><div class="eco-drag-ghost"><i></i></div></section><aside class="eco-console"><p>ENVIRONMENTAL ACTUATORS</p><h2>Intervene. Wait. Compare.</h2><div class="eco-probes"><button type="button" class="eco-probe" data-probe="CLIMATE"><i>≈</i><b>CLIMATE</b><span>Thermal pulse</span></button><button type="button" class="eco-probe" data-probe="FOOD"><i>◌</i><b>FOOD</b><span>Nutrient drop</span></button><button type="button" class="eco-probe" data-probe="LIGHT"><i>☼</i><b>LIGHT</b><span>Directional lamp</span></button></div><div class="eco-cycle-meter"><span><b>AWAITING PROBE</b><i></i></span></div><ol>${state.rules.map((rule, index) => `<li><b>${index + 1}</b><span>${clean(rule)}</span></li>`).join("")}</ol><p class="eco-console-note">The five organisms are visually identical at rest. Only causal response is admissible evidence.</p></aside></main><footer class="eco-foot"><button type="button" class="eco-reset">RESET LAB</button><div><span>OBSERVATION RECORD</span><div class="readout" data-status="idle">BEGIN WITH ${clean(state.protocol[0])}</div></div><button type="button" class="eco-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    document.querySelectorAll(".eco-probe").forEach((button) => button.addEventListener("click", () => runProbe(button.dataset.probe)));
    const stage = document.querySelector(".eco-stage");
    stage.addEventListener("pointerdown", quarantineDown);
    stage.addEventListener("pointermove", quarantineMove);
    stage.addEventListener("pointerup", quarantineUp);
    stage.addEventListener("pointercancel", quarantineUp);
    document.querySelector(".eco-reset").addEventListener("click", resetLab);
    document.querySelector(".eco-submit").addEventListener("click", submit);
    updateProtocol();
    helpers.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.impossible_ecology = {rootSelector: ".impossible-ecology-captcha", render};
})();
