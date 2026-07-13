(() => {
  "use strict";

  let model = null;

  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function stagePoint(event) {
    const rect = document.querySelector(".trace-stage").getBoundingClientRect();
    return [
      Math.max(0, Math.min(model.state.stage.width, Math.round((event.clientX - rect.left) / rect.width * model.state.stage.width))),
      Math.max(0, Math.min(model.state.stage.height, Math.round((event.clientY - rect.top) / rect.height * model.state.stage.height))),
    ];
  }

  function driftAt(sampleIndex) {
    const spec = model.state.drift;
    return [
      Math.round(spec.amplitude_x * (Math.sin(spec.phase_x + sampleIndex * spec.rate_x) - Math.sin(spec.phase_x))),
      Math.round(spec.amplitude_y * (Math.cos(spec.phase_y + sampleIndex * spec.rate_y) - Math.cos(spec.phase_y))),
    ];
  }

  function effectivePoint(raw, sampleIndex) {
    const drift = driftAt(sampleIndex);
    return [raw[0] + drift[0], raw[1] + drift[1]];
  }

  function nearestOnPath(point, path) {
    let bestDistance = Number.POSITIVE_INFINITY;
    let bestProgress = 0;
    for (let index = 0; index < path.length - 1; index += 1) {
      const first = path[index], second = path[index + 1];
      const vx = second[0] - first[0], vy = second[1] - first[1];
      const lengthSq = vx * vx + vy * vy;
      const t = lengthSq <= 0 ? 0 : Math.max(0, Math.min(1, ((point[0] - first[0]) * vx + (point[1] - first[1]) * vy) / lengthSq));
      const x = first[0] + t * vx, y = first[1] + t * vy;
      const candidate = Math.hypot(point[0] - x, point[1] - y);
      if (candidate < bestDistance) {
        bestDistance = candidate;
        bestProgress = index + t;
      }
    }
    return {distance: bestDistance, progress: bestProgress};
  }

  function edgePoint(path, index, side, radius) {
    const previous = path[Math.max(0, index - 1)];
    const next = path[Math.min(path.length - 1, index + 1)];
    const vx = next[0] - previous[0], vy = next[1] - previous[1];
    const length = Math.max(1, Math.hypot(vx, vy));
    return [path[index][0] - vy / length * radius * side, path[index][1] + vx / length * radius * side];
  }

  function updateSonarCoverage(point) {
    const radius = model.state.sonar_radius;
    model.state.main_path.forEach((pathPoint, index) => {
      if (distance(point, pathPoint) <= radius) model.mainCoverage.add(index);
    });
    const offMain = nearestOnPath(point, model.state.main_path).distance > radius * .58;
    model.state.branches.forEach((branch) => {
      const distal = branch.points.slice(Math.max(1, Math.floor(branch.points.length * .4)));
      if (offMain && distal.some((pathPoint) => distance(point, pathPoint) <= radius * .62)) model.branchCoverage.add(branch.id);
    });
    model.probeCells.add(`${Math.floor(point[0] / 55)}:${Math.floor(point[1] / 55)}`);
  }

  function revealNear(point, now = performance.now()) {
    const radius = model.state.sonar_radius;
    const expires = now + model.state.sonar_fade_ms;
    model.state.main_path.forEach((pathPoint, index) => {
      if (distance(point, pathPoint) <= radius) model.revealed.set(`m:${index}`, expires);
    });
    model.state.branches.forEach((branch) => branch.points.forEach((pathPoint, index) => {
      if (distance(point, pathPoint) <= radius) model.revealed.set(`${branch.id}:${index}`, expires);
    }));
  }

  function explorationReady() {
    const requirement = model.state.requirements;
    return model.probeCount >= requirement.min_probe_samples
      && model.probeCells.size >= requirement.min_probe_cells
      && model.mainCoverage.size >= requirement.min_main_coverage
      && model.branchCoverage.size >= requirement.min_branch_coverage;
  }

  function meter(selector, value, maximum) {
    const node = document.querySelector(selector);
    if (node) node.style.width = `${Math.min(100, value / Math.max(1, maximum) * 100)}%`;
  }

  function updateExplorationPanel() {
    const requirement = model.state.requirements;
    const values = {
      ".trace-probe-value": `${model.probeCount}/${requirement.min_probe_samples}`,
      ".trace-cell-value": `${model.probeCells.size}/${requirement.min_probe_cells}`,
      ".trace-main-value": `${model.mainCoverage.size}/${requirement.min_main_coverage}`,
      ".trace-branch-value": `${model.branchCoverage.size}/${requirement.min_branch_coverage}`,
    };
    Object.entries(values).forEach(([selector, value]) => { const node = document.querySelector(selector); if (node) node.textContent = value; });
    meter(".trace-probe-meter i", model.probeCount, requirement.min_probe_samples);
    meter(".trace-cell-meter i", model.probeCells.size, requirement.min_probe_cells);
    meter(".trace-main-meter i", model.mainCoverage.size, requirement.min_main_coverage);
    meter(".trace-branch-meter i", model.branchCoverage.size, requirement.min_branch_coverage);
    const ready = explorationReady();
    const start = document.querySelector(".trace-start-beacon");
    if (start) start.dataset.armed = ready && !model.collisionPending && !model.completed ? "true" : "false";
    const status = document.querySelector(".trace-map-status");
    if (status) {
      status.dataset.ready = ready ? "true" : "false";
      status.textContent = ready ? "SONAR MAP SUFFICIENT · START ARMED" : "MAP THE MAIN SIGNAL + FALSE ECHOES";
    }
  }

  function updateDriftDisplay(sampleIndex) {
    const [dx, dy] = driftAt(sampleIndex);
    const arrow = document.querySelector(".trace-wind-arrow");
    const magnitude = Math.hypot(dx, dy);
    const angle = Math.atan2(dy, dx) * 180 / Math.PI;
    if (arrow) {
      arrow.style.rotate = `${angle}deg`;
      arrow.style.setProperty("--wind-length", `${24 + magnitude * 2.1}px`);
    }
    const vector = document.querySelector(".trace-wind-vector");
    if (vector) vector.textContent = `Δ ${dx >= 0 ? "+" : ""}${dx} X / ${dy >= 0 ? "+" : ""}${dy} Y`;
    const sample = document.querySelector(".trace-sample-index");
    if (sample) sample.textContent = String(sampleIndex).padStart(3, "0");
  }

  function updateProbeVisual(raw, effective, active) {
    const cursor = document.querySelector(".trace-raw-cursor");
    const probe = document.querySelector(".trace-effective-probe");
    const sonar = document.querySelector(".trace-sonar-lens");
    const position = (node, point) => {
      if (!node) return;
      node.style.left = `${point[0] / model.state.stage.width * 100}%`;
      node.style.top = `${point[1] / model.state.stage.height * 100}%`;
    };
    position(cursor, raw); position(probe, effective); position(sonar, active ? effective : raw);
    if (cursor) cursor.dataset.visible = "true";
    if (probe) probe.dataset.visible = active ? "true" : "false";
    if (sonar) sonar.dataset.visible = "true";
  }

  function drawPathEdges(context, path, keyPrefix, radius, color, now) {
    for (const side of [-1, 1]) {
      for (let index = 1; index < path.length; index += 1) {
        const expiry = Math.max(model.revealed.get(`${keyPrefix}:${index - 1}`) || 0, model.revealed.get(`${keyPrefix}:${index}`) || 0);
        const remaining = (expiry - now) / model.state.sonar_fade_ms;
        if (remaining <= 0) continue;
        const first = edgePoint(path, index - 1, side, radius);
        const second = edgePoint(path, index, side, radius);
        context.beginPath();
        context.moveTo(first[0], first[1]);
        context.lineTo(second[0], second[1]);
        context.globalAlpha = Math.min(1, Math.max(.04, remaining));
        context.strokeStyle = color;
        context.lineWidth = keyPrefix === "m" ? 2.3 : 1.6;
        context.shadowColor = color;
        context.shadowBlur = keyPrefix === "m" ? 8 : 5;
        context.stroke();
      }
    }
    context.globalAlpha = 1;
  }

  function drawScope(now) {
    if (!model) return;
    const canvas = document.querySelector(".trace-scope");
    if (!canvas) return;
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.lineCap = "round";
    context.lineJoin = "round";
    drawPathEdges(context, model.state.main_path, "m", model.state.corridor_radius, "rgba(95,255,213,.96)", now);
    model.state.branches.forEach((branch) => drawPathEdges(context, branch.points, branch.id, model.state.corridor_radius, "rgba(255,177,70,.88)", now));
    if (model.traceTail.length > 1) {
      context.beginPath();
      context.moveTo(model.traceTail[0][0], model.traceTail[0][1]);
      model.traceTail.slice(1).forEach((point) => context.lineTo(point[0], point[1]));
      context.strokeStyle = model.completed ? "#d6ff9c" : "rgba(255,255,255,.65)";
      context.lineWidth = 1.5;
      context.shadowColor = context.strokeStyle;
      context.shadowBlur = 4;
      context.stroke();
    }
    for (const [key, expiry] of model.revealed.entries()) if (expiry <= now - 80) model.revealed.delete(key);
    model.raf = requestAnimationFrame(drawScope);
  }

  function sonarMove(event) {
    if (!model || model.trace || model.awaitingPointerUp || model.completed || model.submitting) return;
    document.querySelector(".trace-failure-stamp")?.remove();
    const point = stagePoint(event);
    if (model.lastSonarPoint && distance(point, model.lastSonarPoint) < 8) return;
    model.lastSonarPoint = point;
    model.probeCount += 1;
    record("sonar_probe", {point});
    updateSonarCoverage(point);
    revealNear(point);
    updateProbeVisual(point, point, false);
    updateExplorationPanel();
    model.helpers.setReadout(explorationReady() ? "SONAR MAP SUFFICIENT · PRESS AND HOLD START" : "LOCAL ECHO ACQUIRED · KEEP MAPPING", explorationReady() ? "idle" : "pending");
  }

  function traceStart(event) {
    if (!event.target.closest(".trace-start-beacon") || !explorationReady() || model.collisionPending || model.completed || model.submitting) return;
    event.preventDefault();
    document.querySelector(".trace-failure-stamp")?.remove();
    const raw = stagePoint(event);
    const effective = effectivePoint(raw, 0);
    record("trace_start", {raw, effective, sample_index: 0, elapsed_ms: 0});
    model.trace = {sampleIndex: 0, startedAt: performance.now(), lastRaw: raw, lastEffective: effective, lastProgress: 0, checkpointCursor: 1, samples: 0, distance: 0};
    model.traceTail = [effective];
    document.querySelector(".trace-stage").setPointerCapture(event.pointerId);
    document.querySelector(".trace-stage").classList.add("is-tracing");
    document.querySelector(".trace-start-beacon").dataset.active = "true";
    updateProbeVisual(raw, effective, true);
    updateDriftDisplay(0);
    revealNear(effective);
    model.helpers.setReadout("CONTINUOUS HOLD ACTIVE · STEER THE DRIFTED PROBE", "pending");
  }

  function setBreach(message) {
    document.querySelector(".trace-stage")?.classList.remove("is-tracing");
    document.querySelector(".trace-stage")?.classList.add("has-breach");
    const start = document.querySelector(".trace-start-beacon"); if (start) start.dataset.active = "false";
    const breach = document.querySelector(".trace-breach"); if (breach) breach.dataset.visible = "true";
    const detail = document.querySelector(".trace-breach span"); if (detail) detail.textContent = message;
    const rearm = document.querySelector(".trace-rearm"); if (rearm) rearm.disabled = true;
  }

  function traceMove(event) {
    if (!model?.trace || model.awaitingPointerUp) return;
    event.preventDefault();
    const sampleIndex = model.trace.sampleIndex + 1;
    const raw = stagePoint(event);
    const effective = effectivePoint(raw, sampleIndex);
    const elapsed = Math.max(0, Math.round(performance.now() - model.trace.startedAt));
    const nearest = nearestOnPath(effective, model.state.main_path);
    updateProbeVisual(raw, effective, true);
    updateDriftDisplay(sampleIndex);
    revealNear(effective);
    if (nearest.distance > model.state.corridor_radius) {
      record("trace_cancel", {reason: "wall", raw, effective, sample_index: sampleIndex, elapsed_ms: elapsed});
      model.collisions += 1;
      model.collisionPending = true;
      model.awaitingPointerUp = true;
      model.trace = null;
      setBreach("PROBE LEFT THE HIDDEN CORRIDOR · RELEASE, THEN RE-ARM");
      model.helpers.setReadout("WALL BREACH · CURRENT HOLD CANCELLED", "error");
      updateExplorationPanel();
      return;
    }
    record("trace_sample", {raw, effective, sample_index: sampleIndex, elapsed_ms: elapsed});
    model.trace.distance += distance(effective, model.trace.lastEffective);
    Object.assign(model.trace, {sampleIndex, lastRaw: raw, lastEffective: effective, lastProgress: nearest.progress, samples: model.trace.samples + 1});
    const checkpointIndex = model.state.checkpoint_indices[model.trace.checkpointCursor];
    if (checkpointIndex != null && distance(effective, model.state.main_path[checkpointIndex]) <= Math.max(25, model.state.corridor_radius - 8)) {
      model.trace.checkpointCursor += 1;
      const flash = document.querySelector(".trace-checkpoint-flash");
      if (flash) { flash.textContent = `HIDDEN GATE ${model.trace.checkpointCursor - 1}/${model.state.checkpoint_indices.length - 1}`; flash.classList.remove("is-flashing"); void flash.offsetWidth; flash.classList.add("is-flashing"); }
    }
    model.traceTail.push(effective);
    if (model.traceTail.length > 130) model.traceTail.shift();
    const gate = document.querySelector(".trace-gate-value"); if (gate) gate.textContent = `${model.trace.checkpointCursor - 1}/${model.state.checkpoint_indices.length - 1}`;
    meter(".trace-gate-meter i", model.trace.checkpointCursor - 1, model.state.checkpoint_indices.length - 1);
  }

  function traceEnd(event) {
    if (model.awaitingPointerUp) {
      model.awaitingPointerUp = false;
      const rearm = document.querySelector(".trace-rearm"); if (rearm) rearm.disabled = false;
      return;
    }
    if (!model?.trace) return;
    event.preventDefault();
    const raw = stagePoint(event);
    const effective = effectivePoint(raw, model.trace.sampleIndex);
    const elapsed = Math.max(0, Math.round(performance.now() - model.trace.startedAt));
    const requirement = model.state.requirements;
    const success = distance(effective, model.state.exit) <= Math.max(24, model.state.corridor_radius - 8)
      && model.trace.checkpointCursor === model.state.checkpoint_indices.length
      && model.trace.samples >= requirement.min_trace_samples
      && model.trace.distance >= requirement.min_trace_distance
      && elapsed >= requirement.min_trace_ms;
    if (success) {
      record("trace_end", {raw, effective, sample_index: model.trace.sampleIndex, elapsed_ms: elapsed});
      model.completed = true;
      model.completedSamples = model.trace.samples;
      model.completedDistance = model.trace.distance;
      model.finalProbe = effective;
      model.trace = null;
      document.querySelector(".trace-stage")?.classList.remove("is-tracing");
      document.querySelector(".trace-stage")?.classList.add("is-complete");
      document.querySelector(".trace-start-beacon").dataset.active = "false";
      document.querySelector(".trace-exit-beacon").dataset.complete = "true";
      model.helpers.setReadout("EXIT LOCKED · CONTINUOUS TRACE READY TO CERTIFY", "passed");
    } else {
      record("trace_cancel", {reason: "release", raw, effective, sample_index: model.trace.sampleIndex, elapsed_ms: elapsed});
      model.collisions += 1;
      model.collisionPending = true;
      model.trace = null;
      setBreach("HOLD RELEASED BEFORE EXIT OR BEFORE ALL HIDDEN GATES");
      const rearm = document.querySelector(".trace-rearm"); if (rearm) rearm.disabled = false;
      model.helpers.setReadout("TRACE RELEASED EARLY · RE-ARM AND RETRY", "error");
    }
    updateExplorationPanel();
  }

  function rearmTrace() {
    if (!model.collisionPending || model.trace || model.completed || model.submitting) return;
    record("rearm");
    model.collisionPending = false;
    model.rearmCount += 1;
    model.traceTail = [];
    document.querySelector(".trace-stage")?.classList.remove("has-breach");
    const breach = document.querySelector(".trace-breach"); if (breach) breach.dataset.visible = "false";
    const rearm = document.querySelector(".trace-rearm"); if (rearm) rearm.disabled = true;
    const gate = document.querySelector(".trace-gate-value"); if (gate) gate.textContent = `0/${model.state.checkpoint_indices.length - 1}`;
    meter(".trace-gate-meter i", 0, 1);
    updateDriftDisplay(0);
    updateExplorationPanel();
    model.helpers.setReadout("TRACE RE-ARMED · PRESS AND HOLD START", "idle");
  }

  async function submit() {
    if (model.submitting || model.terminal) return;
    model.submitting = true;
    model.helpers.setReadout("REPLAYING SONAR, DRIFT, WALL DISTANCE, AND HOLD…", "pending");
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({
        mechanic_id: model.state.mechanic_id,
        challenge_id: model.state.challenge_id,
        events: model.events,
        probe_count: model.probeCount,
        explored_cells: model.probeCells.size,
        explored_main: model.mainCoverage.size,
        explored_branches: model.branchCoverage.size,
        trace_samples: model.completedSamples,
        trace_distance: Math.round(model.completedDistance),
        collisions: model.collisions,
        rearm_count: model.rearmCount,
        final_probe: model.finalProbe,
        completed: model.completed,
      })});
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".blind-corridor-captcha")?.insertAdjacentHTML("beforeend", '<div class="trace-verdict"><span>BLIND CORRIDOR RECORD AUTHENTICATED</span><strong>PASS</strong><small>SONAR MAP · CROSSWIND · CONTINUOUS HOLD REPLAY VERIFIED</small></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".blind-corridor-captcha");
        shell?.setAttribute("data-fresh-failure", "true");
        shell?.insertAdjacentHTML("afterbegin", '<div class="trace-failure-stamp"><b>FAIL</b><span>INVALID TRACE RECORD · FRESH CORRIDOR ISSUED</span></div>');
        const readout = document.querySelector(".readout"); if (readout) { readout.textContent = "FAIL · FRESH BLIND CORRIDOR ISSUED"; readout.dataset.status = "error"; }
      } else {
        model.submitting = false;
        model.helpers.setReadout("FAIL · NO AUTHORITATIVE GRADE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("FAIL · OSCILLOSCOPE VERIFIER OFFLINE", "error");
    }
  }

  async function render(state, helpers) {
    if (model?.raf) cancelAnimationFrame(model.raf);
    document.body.dataset.mechanic = "blind-corridor";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {
      state, helpers, events: [], revealed: new Map(), mainCoverage: new Set(), branchCoverage: new Set(), probeCells: new Set(),
      probeCount: 0, lastSonarPoint: null, trace: null, traceTail: [], collisionPending: false, awaitingPointerUp: false,
      collisions: 0, rearmCount: 0, completed: false, completedSamples: 0, completedDistance: 0, finalProbe: null,
      submitting: false, terminal: false, raf: null,
    };
    window.blindCorridorModel = model;
    const start = state.start, exit = state.exit;
    helpers.app.innerHTML = `<section class="blind-corridor-captcha" data-challenge-id="${clean(state.challenge_id)}"><header class="trace-head"><div><span>BCO / BLIND CORRIDOR OSCILLOSCOPE / ${clean(state.challenge_id)}</span><h1>${clean(state.prompt)}</h1></div><div class="trace-head-instruments"><div><b>01</b><span>SONAR MAP</span><i>HOVER / NO PENALTY</i></div><div><b>02</b><span>COMMIT HOLD</span><i>START → EXIT</i></div><div><b>03</b><span>CORRECT DRIFT</span><i>FOLLOW PROBE, NOT CURSOR</i></div></div></header><main class="trace-main"><section class="trace-stage"><canvas class="trace-scope" width="${state.stage.width}" height="${state.stage.height}"></canvas><div class="trace-stage-label">CHANNEL Ω / WALLS SUPPRESSED / LOCAL ECHO ONLY</div><div class="trace-start-beacon" data-armed="false" data-active="false" style="left:${start[0]/state.stage.width*100}%;top:${start[1]/state.stage.height*100}%"><i></i><b>START</b><span>HOLD</span></div><div class="trace-exit-beacon" data-complete="false" style="left:${exit[0]/state.stage.width*100}%;top:${exit[1]/state.stage.height*100}%"><i></i><b>EXIT</b><span>RELEASE</span></div><div class="trace-sonar-lens" data-visible="false"></div><div class="trace-raw-cursor" data-visible="false"><i></i></div><div class="trace-effective-probe" data-visible="false"><i></i><b>PROBE</b></div><div class="trace-checkpoint-flash"></div><div class="trace-breach" data-visible="false"><b>WALL BREACH</b><span>PROBE LEFT THE HIDDEN CORRIDOR</span></div></section><aside class="trace-console"><p>OSCILLOSCOPE CONTROL</p><h2>The corridor exists only where you listen.</h2><div class="trace-wind"><header><span>LIVE CROSSWIND VECTOR</span><b class="trace-sample-index">000</b></header><div class="trace-wind-field"><i class="trace-wind-arrow"></i><b class="trace-wind-vector">Δ +0 X / +0 Y</b><span>WHITE = RAW CURSOR<br>GREEN = DRIFTED PROBE</span></div></div><div class="trace-mapping"><div><span>SONAR SAMPLES</span><b class="trace-probe-value">0/${state.requirements.min_probe_samples}</b><em class="trace-probe-meter"><i></i></em></div><div><span>MAP CELLS</span><b class="trace-cell-value">0/${state.requirements.min_probe_cells}</b><em class="trace-cell-meter"><i></i></em></div><div><span>MAIN ECHO</span><b class="trace-main-value">0/${state.requirements.min_main_coverage}</b><em class="trace-main-meter"><i></i></em></div><div><span>FALSE ECHOES</span><b class="trace-branch-value">0/${state.requirements.min_branch_coverage}</b><em class="trace-branch-meter"><i></i></em></div></div><div class="trace-gates"><span>HIDDEN GATES CROSSED</span><b class="trace-gate-value">0/${state.checkpoint_indices.length-1}</b><em class="trace-gate-meter"><i></i></em></div><button type="button" class="trace-rearm" disabled>RE-ARM CANCELLED TRACE</button><ol><li><b>1</b><span>Hover freely. Local sonar fades; probing never fails.</span></li><li><b>2</b><span>Map the green main signal and at least ${state.requirements.min_branch_coverage} amber false echoes.</span></li><li><b>3</b><span>Hold START continuously. Steer the green probe as crosswind separates it from the white cursor.</span></li></ol></aside></main><footer class="trace-foot"><div class="trace-map-status" data-ready="false">MAP THE MAIN SIGNAL + FALSE ECHOES</div><div><span>TRACE RECORD</span><div class="readout" data-status="idle">MOVE THE POINTER TO EMIT LOCAL SONAR</div></div><button type="button" class="trace-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    const stageNode = document.querySelector(".trace-stage");
    stageNode.addEventListener("pointermove", (event) => { if (model.trace) traceMove(event); else sonarMove(event); });
    stageNode.addEventListener("pointerdown", traceStart);
    stageNode.addEventListener("pointerup", traceEnd);
    stageNode.addEventListener("pointercancel", traceEnd);
    document.querySelector(".trace-rearm").addEventListener("click", rearmTrace);
    document.querySelector(".trace-submit").addEventListener("click", submit);
    updateExplorationPanel(); updateDriftDisplay(0); helpers.installCheatPanel();
    model.raf = requestAnimationFrame(drawScope);
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.trace_shape_without_walls = {rootSelector: ".blind-corridor-captcha", render};
})();
