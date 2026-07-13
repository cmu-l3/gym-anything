(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)); }
  function round2(value) { return Math.round(Number(value) * 100) / 100; }
  function point(value) { return {x: round2(value.x), y: round2(value.y)}; }
  function catcherCopy(value) { return {x: round2(value.x), y: round2(value.y), angle_deg: Number(value.angle_deg), aperture: Number(value.aperture), armed: Boolean(value.armed)}; }
  function globalTime() { return Math.round(performance.now() - model.startedAt); }
  function roundTime() { return clamp(Math.round(performance.now() - model.roundStartedAt), 0, Number(currentRound().duration_ms)); }
  function pushEvent(event) { const item = {seq: model.events.length + 1, t_ms: globalTime(), ...event}; model.events.push(item); return item; }
  function currentRound() { return model.state.rounds[model.roundIndex]; }

  function pathAt(round, tMs) {
    const duration = Number(round.duration_ms);
    const u = clamp(Number(tMs) / duration, 0, 1);
    const travel = round.direction === "ltr" ? u : 1 - u;
    const x = 70 + travel * 760;
    const base = Number(round.base_y), amplitude = Number(round.amplitude), wobble = Number(round.wobble), phase = Number(round.phase);
    let y;
    if (round.family === "ballistic_arc") y = base + amplitude * (4 * u * (1 - u) - 0.48) + wobble * Math.sin(Math.PI * 2 * u + phase);
    else if (round.family === "sine_drift") y = base + amplitude * Math.sin(Math.PI * 2 * (u + phase)) + wobble * Math.sin(6 * Math.PI * u);
    else { const centered = 2 * u - 1; y = base + amplitude * (centered ** 3 - 0.34 * centered) + wobble * Math.sin(4 * Math.PI * u + phase); }
    return {x, y};
  }

  function velocityAngle(round, tMs) {
    const before = pathAt(round, Math.max(0, tMs - 6));
    const after = pathAt(round, Math.min(Number(round.duration_ms), tMs + 6));
    return (Math.atan2(after.y - before.y, after.x - before.x) * 180 / Math.PI + 360) % 360;
  }

  function localPoint(position, catcher) {
    const radians = Number(catcher.angle_deg) * Math.PI / 180;
    const cosine = Math.cos(radians), sine = Math.sin(radians);
    const dx = position.x - catcher.x, dy = position.y - catcher.y;
    return {x: dx * cosine + dy * sine, y: -dx * sine + dy * cosine};
  }

  function angleError(first, second) { return Math.abs(((first - second + 90) % 180 + 180) % 180 - 90); }

  function sweptCatch(round, catcher) {
    if (!catcher.armed) return {caught: false, crossing: null};
    let previousT = Number(round.wall_exit_ms);
    let previous = localPoint(pathAt(round, previousT), catcher);
    for (let currentT = previousT + 10; currentT <= Number(round.duration_ms) + 0.001; currentT += 10) {
      const current = localPoint(pathAt(round, currentT), catcher);
      const crosses = previous.x === 0 || current.x === 0 || previous.x * current.x < 0;
      if (crosses) {
        const denominator = previous.x - current.x;
        const amount = Math.abs(denominator) < 1e-9 ? 0 : clamp(previous.x / denominator, 0, 1);
        const crossing = previousT + (currentT - previousT) * amount;
        const crossingY = previous.y + (current.y - previous.y) * amount;
        const clearance = catcher.aperture / 2 - Number(round.projectile_radius);
        if (clearance >= 0 && Math.abs(crossingY) <= clearance + 1e-9 && angleError(velocityAngle(round, crossing), catcher.angle_deg) <= Number(round.alignment_tolerance_deg) + 1e-9) return {caught: true, crossing};
      }
      previousT = currentT;
      previous = current;
    }
    return {caught: false, crossing: null};
  }

  function initialCatcher(round) { return {...catcherCopy({...round.initial_catcher, armed: false})}; }
  function commitOpen() { const round = currentRound(); const t = roundTime(); return model.phase === "hidden" && t >= Number(round.wall_enter_ms) && t <= Number(round.wall_exit_ms) - Number(round.commit_margin_ms) && !model.catcher.armed; }

  function canvasPoint(event) {
    const canvas = document.getElementById("trajectory-canvas");
    const rect = canvas.getBoundingClientRect();
    return {x: round2((event.clientX - rect.left) / rect.width * canvas.width), y: round2((event.clientY - rect.top) / rect.height * canvas.height)};
  }

  function drawGrid(context, width, height) {
    context.fillStyle = "#071720"; context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(91, 188, 190, .095)"; context.lineWidth = 1;
    for (let x = 0; x <= width; x += 30) { context.beginPath(); context.moveTo(x, 0); context.lineTo(x, height); context.stroke(); }
    for (let y = 0; y <= height; y += 30) { context.beginPath(); context.moveTo(0, y); context.lineTo(width, y); context.stroke(); }
    context.strokeStyle = "rgba(239, 174, 83, .17)"; context.setLineDash([6, 8]); context.beginPath(); context.moveTo(0, height / 2); context.lineTo(width, height / 2); context.stroke(); context.setLineDash([]);
  }

  function drawTail(context) {
    if (model.observedTail.length < 2) return;
    context.beginPath(); context.moveTo(model.observedTail[0].x, model.observedTail[0].y); model.observedTail.slice(1).forEach((sample) => context.lineTo(sample.x, sample.y));
    context.strokeStyle = "rgba(255, 145, 173, .58)"; context.lineWidth = 2; context.setLineDash([3, 7]); context.stroke(); context.setLineDash([]);
    model.observedTail.filter((_, index) => index % 4 === 0).forEach((sample) => { context.beginPath(); context.arc(sample.x, sample.y, 2.5, 0, Math.PI * 2); context.fillStyle = "#ff8eae"; context.fill(); });
  }

  function drawProjectile(context, round, t) {
    const position = pathAt(round, t);
    context.save(); context.translate(position.x, position.y);
    context.beginPath(); context.arc(0, 0, Number(round.projectile_radius) + 8, 0, Math.PI * 2); context.fillStyle = "rgba(255, 105, 146, .16)"; context.fill();
    context.beginPath(); context.arc(0, 0, Number(round.projectile_radius), 0, Math.PI * 2); context.fillStyle = "#ff769f"; context.fill(); context.strokeStyle = "#ffe3ec"; context.lineWidth = 2; context.stroke();
    context.fillStyle = "#33131f"; context.beginPath(); context.arc(-2, -2, 3, 0, Math.PI * 2); context.fill(); context.restore();
  }

  function drawWall(context, wall) {
    context.fillStyle = "#101214"; context.fillRect(Number(wall.x), Number(wall.y), Number(wall.width), Number(wall.height));
    context.strokeStyle = "#c08b45"; context.lineWidth = 3; context.strokeRect(Number(wall.x), Number(wall.y), Number(wall.width), Number(wall.height));
    context.save(); context.beginPath(); context.rect(Number(wall.x), Number(wall.y), Number(wall.width), Number(wall.height)); context.clip();
    context.strokeStyle = "rgba(224, 167, 88, .17)"; context.lineWidth = 8;
    for (let x = Number(wall.x) - 500; x < Number(wall.x) + Number(wall.width) + 500; x += 28) { context.beginPath(); context.moveTo(x, Number(wall.y) + Number(wall.height)); context.lineTo(x + 360, Number(wall.y)); context.stroke(); }
    context.restore();
    context.fillStyle = "#d8a65b"; context.font = "900 9px Courier New"; context.textAlign = "center"; context.fillText("OPAQUE / NO OPTICAL RETURN", Number(wall.x) + Number(wall.width) / 2, 34);
  }

  function drawCatcher(context) {
    const catcher = model.catcher;
    context.save(); context.translate(catcher.x, catcher.y); context.rotate(catcher.angle_deg * Math.PI / 180);
    context.strokeStyle = catcher.armed ? "#66f4cb" : "#f3c66f"; context.fillStyle = catcher.armed ? "rgba(59, 215, 168, .18)" : "rgba(229, 174, 79, .12)"; context.lineWidth = catcher.armed ? 4 : 2;
    context.setLineDash(catcher.armed ? [] : [7, 5]);
    const aperture = catcher.aperture;
    context.strokeRect(-18, -aperture / 2 - 16, 36, 16); context.fillRect(-18, -aperture / 2 - 16, 36, 16);
    context.strokeRect(-18, aperture / 2, 36, 16); context.fillRect(-18, aperture / 2, 36, 16);
    context.beginPath(); context.moveTo(0, -aperture / 2); context.lineTo(0, aperture / 2); context.stroke();
    context.setLineDash([]); context.beginPath(); context.arc(0, 0, 9, 0, Math.PI * 2); context.fillStyle = catcher.armed ? "#5de1bb" : "#e1aa51"; context.fill(); context.strokeStyle = "#071319"; context.lineWidth = 2; context.stroke();
    context.restore();
    context.fillStyle = catcher.armed ? "#83f6d5" : "#e7c07b"; context.font = "800 7px Courier New"; context.textAlign = "center"; context.fillText(`${catcher.angle_deg}° / ${catcher.aperture}`, catcher.x, catcher.y + catcher.aperture / 2 + 31);
  }

  function drawScene() {
    if (!model) return;
    const canvas = document.getElementById("trajectory-canvas"); const context = canvas?.getContext("2d"); if (!canvas || !context) return;
    const round = currentRound(); const t = model.phase === "result" ? Number(round.duration_ms) : roundTime();
    drawGrid(context, canvas.width, canvas.height); drawTail(context);
    if (model.phase !== "hidden") drawProjectile(context, round, t);
    drawWall(context, round.wall); drawCatcher(context);
    context.fillStyle = "rgba(224, 177, 103, .8)"; context.font = "800 8px Courier New"; context.textAlign = "left"; context.fillText(`FLIGHT ${round.sequence + 1} / LIVE VECTOR`, 14, 18);
  }

  function updateInterface() {
    if (!model) return;
    const root = document.querySelector(".trajectory-catcher"); if (!root) return;
    root.dataset.phase = model.phase; root.dataset.roundIndex = String(model.roundIndex); root.dataset.attempt = String(model.attempt); root.dataset.armed = String(model.catcher.armed); root.dataset.result = model.result || "";
    document.getElementById("trajectory-round")?.replaceChildren(document.createTextNode(`${model.roundIndex + 1} / ${model.state.round_count}`));
    document.getElementById("trajectory-angle")?.replaceChildren(document.createTextNode(`${model.catcher.angle_deg}°`));
    document.getElementById("trajectory-aperture")?.replaceChildren(document.createTextNode(String(model.catcher.aperture)));
    const phaseLabel = document.getElementById("trajectory-phase"); if (phaseLabel) phaseLabel.textContent = model.phase === "observing" ? "OBSERVE" : model.phase === "hidden" ? "OCCLUDED" : model.phase === "emerged" ? "EMERGENCE" : model.result === "caught" ? "CAUGHT" : model.result === "miss" ? "MISS" : "STANDBY";
    const canCommitNow = commitOpen();
    document.querySelectorAll(".catcher-transform").forEach((button) => { button.disabled = !canCommitNow || model.dragging || model.catcher.armed; });
    const arm = document.getElementById("trajectory-arm"); if (arm) arm.disabled = !canCommitNow || model.dragging || model.catcher.armed;
    const reset = document.getElementById("trajectory-reset-catcher"); if (reset) reset.disabled = !canCommitNow || model.dragging || model.catcher.armed;
    const replay = document.getElementById("trajectory-replay"); if (replay) { replay.hidden = model.result !== "miss" || model.replayUsed[model.roundIndex] >= Number(currentRound().replay_limit); }
    const next = document.getElementById("trajectory-next"); if (next) next.hidden = model.result !== "caught" || model.roundIndex >= model.state.round_count - 1;
    const restart = document.getElementById("trajectory-restart"); if (restart) restart.hidden = !(model.phase === "result" && model.result === "miss" && model.replayUsed[model.roundIndex] >= Number(currentRound().replay_limit));
    drawScene();
  }

  function frame(now) {
    if (!model || model.phase === "result") return;
    const round = currentRound(); const t = clamp(Math.round(now - model.roundStartedAt), 0, Number(round.duration_ms));
    model.phase = t <= Number(round.wall_enter_ms) ? "observing" : t < Number(round.wall_exit_ms) ? "hidden" : "emerged";
    if (t <= Number(round.wall_enter_ms) && t - model.lastObservation >= 95) {
      const position = pathAt(round, t); pushEvent({type: "observe_sample", round_id: round.id, attempt: model.attempt, round_t_ms: t, position: point(position)}); model.observedTail.push(position); model.lastObservation = t;
    }
    updateInterface();
    if (t >= Number(round.duration_ms)) { finishRound(); return; }
    model.frameId = requestAnimationFrame(frame);
  }

  function startRound() {
    if (model.frameId) cancelAnimationFrame(model.frameId);
    const round = currentRound(); model.catcher = initialCatcher(round); model.phase = "observing"; model.result = null; model.dragging = false; model.dragOffset = {x: 0, y: 0}; model.lastPointer = null; model.observedTail = []; model.lastObservation = -1000; model.roundStartedAt = performance.now(); model.attemptCounts[model.roundIndex] += 1;
    pushEvent({type: "round_start", round_id: round.id, attempt: model.attempt, round_t_ms: 0}); model.helpers.setReadout("OBSERVE FLIGHT", "idle"); updateInterface(); model.frameId = requestAnimationFrame(frame);
  }

  function finishRound() {
    if (!model || model.phase === "result") return;
    if (model.frameId) cancelAnimationFrame(model.frameId); model.frameId = null;
    const round = currentRound();
    // Preserve real elapsed time when an overloaded VNC/browser delivers the
    // final animation frame a little late; the grader allows this bounded tail.
    const resultTime = clamp(Math.round(performance.now() - model.roundStartedAt), Number(round.duration_ms), Number(round.duration_ms) + 500);
    if (model.dragging) {
      const pointer = model.lastPointer || {x: model.catcher.x, y: model.catcher.y};
      pushEvent({type: "catcher_drag_end", round_id: round.id, attempt: model.attempt, round_t_ms: resultTime, pointer: point(pointer), catcher_after: catcherCopy(model.catcher)});
      model.dragging = false;
    }
    const outcome = sweptCatch(round, model.catcher); model.phase = "result"; model.result = outcome.caught ? "caught" : "miss";
    pushEvent({type: "round_result", round_id: round.id, attempt: model.attempt, round_t_ms: resultTime, caught: outcome.caught, crossing_ms: outcome.caught ? round2(outcome.crossing) : null, catcher: catcherCopy(model.catcher)});
    if (outcome.caught) { model.completed.push(round.id); model.helpers.setReadout("CATCH CONFIRMED", "idle"); }
    else model.helpers.setReadout("MISS / REWIND AVAILABLE", "error");
    updateInterface();
  }

  function pointerDown(event) {
    if (!model || !commitOpen() || model.dragging) return;
    const pointer = canvasPoint(event); if (Math.hypot(pointer.x - model.catcher.x, pointer.y - model.catcher.y) > 42) return;
    model.dragging = true; model.dragOffset = {x: round2(pointer.x - model.catcher.x), y: round2(pointer.y - model.catcher.y)}; model.lastPointer = pointer;
    pushEvent({type: "catcher_drag_start", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), pointer, catcher_before: catcherCopy(model.catcher)}); event.currentTarget.setPointerCapture?.(event.pointerId); updateInterface();
  }
  function pointerMove(event) {
    if (!model?.dragging || !commitOpen()) return;
    const pointer = canvasPoint(event); const before = {x: model.catcher.x, y: model.catcher.y}; model.catcher.x = round2(clamp(pointer.x - model.dragOffset.x, 34, 866)); model.catcher.y = round2(clamp(pointer.y - model.dragOffset.y, 34, 446));
    pushEvent({type: "catcher_drag_move", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), pointer, from: before, to: {x: model.catcher.x, y: model.catcher.y}}); model.lastPointer = pointer; updateInterface();
  }
  function pointerUp(event) {
    if (!model?.dragging) return;
    const pointer = canvasPoint(event); pushEvent({type: "catcher_drag_end", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), pointer, catcher_after: catcherCopy(model.catcher)}); model.dragging = false; event.currentTarget.releasePointerCapture?.(event.pointerId); updateInterface();
  }

  function rotateCatcher(delta) {
    if (!commitOpen() || model.dragging) return; const before = model.catcher.angle_deg; model.catcher.angle_deg = (before + delta + 180) % 180;
    pushEvent({type: "catcher_rotate", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), delta_deg: delta, angle_before: before, angle_after: model.catcher.angle_deg}); updateInterface();
  }
  function resizeCatcher(delta) {
    if (!commitOpen() || model.dragging) return; const round = currentRound(); const before = model.catcher.aperture; const after = before + delta; if (after < Number(round.aperture_min) || after > Number(round.aperture_max)) return; model.catcher.aperture = after;
    pushEvent({type: "catcher_resize", round_id: round.id, attempt: model.attempt, round_t_ms: roundTime(), delta, aperture_before: before, aperture_after: after}); updateInterface();
  }
  function resetCatcher() {
    if (!commitOpen() || model.dragging) return; model.catcher = initialCatcher(currentRound()); model.catcherResetCount += 1;
    pushEvent({type: "catcher_reset", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), catcher_after: catcherCopy(model.catcher)}); model.helpers.setReadout("CATCHER RESET", "idle"); updateInterface();
  }
  function armCatcher() {
    if (!commitOpen() || model.dragging) return; model.catcher.armed = true;
    pushEvent({type: "arm", round_id: currentRound().id, attempt: model.attempt, round_t_ms: roundTime(), catcher: catcherCopy(model.catcher)}); model.helpers.setReadout("CATCHER ARMED / TRANSFORM LOCKED", "idle"); updateInterface();
  }
  function replayRound() {
    if (model.result !== "miss" || model.replayUsed[model.roundIndex] >= Number(currentRound().replay_limit)) return;
    pushEvent({type: "replay", round_id: currentRound().id, attempt_before: model.attempt}); model.replayUsed[model.roundIndex] += 1; model.replayCount += 1; model.attempt += 1; startRound();
  }
  function advanceRound() {
    if (model.result !== "caught" || model.roundIndex >= model.state.round_count - 1) return; const before = currentRound().id; const after = model.state.rounds[model.roundIndex + 1].id;
    pushEvent({type: "advance", from_round_id: before, to_round_id: after}); model.roundIndex += 1; model.attempt = 0; startRound();
  }
  function restartChallenge() {
    if (model.phase !== "result") return; pushEvent({type: "challenge_reset", next_round_id: model.state.rounds[0].id}); model.challengeResetCount += 1; model.roundIndex = 0; model.attempt = 0; model.completed = []; model.replayUsed = model.state.rounds.map(() => 0); startRound();
  }

  function finalState() {
    return {completed_round_ids: [...model.completed], replay_count: model.replayCount, catcher_reset_count: model.catcherResetCount, challenge_reset_count: model.challengeResetCount, round_attempt_counts: model.state.rounds.map((round, index) => ({round_id: round.id, attempts: model.attemptCounts[index]}))};
  }

  function showVerdict(kind) {
    const root = document.querySelector(".trajectory-catcher"); const verdict = root?.querySelector(".trajectory-verdict"); if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass"); root.classList.toggle("is-failed", kind === "fail"); verdict.innerHTML = `<b>${kind === "pass" ? "PASS" : "FAIL"}</b><span>${kind === "pass" ? "ALL HIDDEN FLIGHTS CAUGHT" : "FRESH RANGE ISSUED"}</span>`;
    if (kind === "fail") { const timer = setTimeout(() => root.classList.remove("is-failed"), 1500); model.timers.add(timer); }
  }

  async function submitLog() {
    if (!model || model.submitting || model.completedSubmission) return; const current = model; current.submitting = true; updateInterface();
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: current.state.mechanic_id, task_id: current.state.task_id, challenge_id: current.state.challenge_id, events: current.events, final_state: finalState(), completed: current.completed.length === current.state.round_count})});
      const outcome = await response.json();
      if (outcome.passed === true) { current.completedSubmission = true; current.helpers.setReadout("PASS", "passed"); showVerdict("pass"); }
      else if (outcome.passed === false) { const helpers = current.helpers; if (outcome.state) await render(outcome.state, helpers, {freshFailure: true}); model.helpers.setReadout("FAIL", "error"); showVerdict("fail"); }
    } catch (_error) { if (model === current) { current.submitting = false; current.helpers.setReadout("FLIGHT LOG LINK LOST", "error"); updateInterface(); } }
  }

  function installDeveloperReveal() {
    const form = document.getElementById("cheat-form"), input = document.getElementById("cheat-password"), output = document.getElementById("cheat-output"); if (!form || !input || !output) return;
    form.addEventListener("submit", async (event) => { event.preventDefault(); output.textContent = ""; try { const response = await fetch("/cheat", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({password: input.value})}); if (!response.ok) { output.textContent = response.status === 404 ? "Disabled." : "Denied."; return; } const data = await response.json(); output.textContent = (data.solutions || []).map((item) => `${item.round_id}: ${item.x},${item.y} ${item.angle_deg}° A${item.aperture}`).join(" · "); } catch (_error) { output.textContent = "Unavailable."; } });
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup(); document.body.dataset.mechanic = "trajectory-catcher"; document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {state, helpers, startedAt: performance.now(), roundStartedAt: performance.now(), frameId: null, events: [], roundIndex: 0, attempt: 0, catcher: initialCatcher(state.rounds[0]), phase: "standby", result: null, dragging: false, dragOffset: {x: 0, y: 0}, lastPointer: null, observedTail: [], lastObservation: -1000, completed: [], replayUsed: state.rounds.map(() => 0), attemptCounts: state.rounds.map(() => 0), replayCount: 0, catcherResetCount: 0, challengeResetCount: 0, submitting: false, completedSubmission: false, timers: new Set()};
    helpers.app.innerHTML = `
      <section class="trajectory-catcher palette-${helpers.text(state.palette)}" data-fresh-failure="${options.freshFailure ? "true" : "false"}" data-phase="standby" tabindex="0">
        <div class="trajectory-verdict" aria-live="assertive"></div>
        <header class="trajectory-head"><div><span>PREDICTIVE INTERCEPT RANGE / ${helpers.text(state.range_id)}</span><h1>${helpers.text(state.prompt)}</h1></div><div class="trajectory-mark"><i>⤷</i><span>HIDDEN<br><b>FLIGHT</b></span></div></header>
        <main class="trajectory-workbench">
          <section class="trajectory-stage"><canvas id="trajectory-canvas" width="${Number(state.canvas.width)}" height="${Number(state.canvas.height)}" aria-label="hidden trajectory flight range"></canvas><div class="trajectory-caption"><span>OBSERVE / COMMIT UNDER OCCLUSION</span><b>NO OPTICAL RETURN THROUGH WALL</b></div></section>
          <aside class="trajectory-console">
            <div class="trajectory-round-card"><span>FLIGHT</span><b id="trajectory-round">1 / ${Number(state.round_count)}</b><i id="trajectory-phase">OBSERVE</i></div>
            <div class="catcher-controls"><span>CATCHER TRANSFORM</span><div class="control-pair"><button class="catcher-transform" id="trajectory-rotate-left">−15°</button><b id="trajectory-angle">0°</b><button class="catcher-transform" id="trajectory-rotate-right">+15°</button></div><div class="control-pair"><button class="catcher-transform" id="trajectory-size-down">−</button><b id="trajectory-aperture">70</b><button class="catcher-transform" id="trajectory-size-up">+</button></div><button id="trajectory-reset-catcher">RESET CATCHER</button><button id="trajectory-arm">ARM CATCHER</button></div>
            <div class="flight-ledger"><span>FLIGHT LEDGER</span>${state.rounds.map((_round, index) => `<div data-flight-ledger="${index}"><i>${String(index + 1).padStart(2, "0")}</i><b>OBSERVATION SEALED</b><em>VECTOR WITHHELD</em></div>`).join("")}</div>
            <div class="round-actions"><button id="trajectory-replay" hidden>REWIND ROUND</button><button id="trajectory-next" hidden>NEXT FLIGHT</button><button id="trajectory-restart" hidden>RESTART TEST</button></div>
          </aside>
        </main>
        <footer class="trajectory-foot"><div class="readout" data-status="idle">OBSERVE FLIGHT</div><button id="trajectory-file">${helpers.text(state.submit_label || "FILE FLIGHT LOG")}</button></footer>${helpers.cheatPanelTemplate()}
      </section>`;
    const canvas = document.getElementById("trajectory-canvas"); canvas.addEventListener("pointerdown", pointerDown); canvas.addEventListener("pointermove", pointerMove); canvas.addEventListener("pointerup", pointerUp); canvas.addEventListener("pointercancel", pointerUp);
    document.getElementById("trajectory-rotate-left")?.addEventListener("click", () => rotateCatcher(-15)); document.getElementById("trajectory-rotate-right")?.addEventListener("click", () => rotateCatcher(15)); document.getElementById("trajectory-size-down")?.addEventListener("click", () => resizeCatcher(-10)); document.getElementById("trajectory-size-up")?.addEventListener("click", () => resizeCatcher(10)); document.getElementById("trajectory-reset-catcher")?.addEventListener("click", resetCatcher); document.getElementById("trajectory-arm")?.addEventListener("click", armCatcher); document.getElementById("trajectory-replay")?.addEventListener("click", replayRound); document.getElementById("trajectory-next")?.addEventListener("click", advanceRound); document.getElementById("trajectory-restart")?.addEventListener("click", restartChallenge); document.getElementById("trajectory-file")?.addEventListener("click", submitLog); installDeveloperReveal();
    activeCleanup = () => { if (model?.frameId) cancelAnimationFrame(model.frameId); model?.timers.forEach((timer) => clearTimeout(timer)); canvas.removeEventListener("pointerdown", pointerDown); canvas.removeEventListener("pointermove", pointerMove); canvas.removeEventListener("pointerup", pointerUp); canvas.removeEventListener("pointercancel", pointerUp); };
    if (options.freshFailure) {
      // A fresh analytic flight must never run invisibly behind the failure card.
      // Hold at standby, then issue a full observation interval after it clears.
      updateInterface();
      const freshModel = model;
      const timer = setTimeout(() => { if (model === freshModel) startRound(); }, 1550);
      model.timers.add(timer);
    } else startRound();
    document.querySelector(".trajectory-catcher")?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.trajectory_catcher = {rootSelector: ".trajectory-catcher", render};
})();
