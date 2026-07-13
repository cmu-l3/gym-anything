(() => {
  "use strict";
  let model = null;
  const clean = value => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const round = value => Math.round(value * 10000) / 10000;
  function record(kind, details = {}) { const event = {sequence: model.events.length + 1, kind, ...details}; model.events.push(event); return event; }
  function road(progress) { const p = model.state.physics; return 240 + p.road_amplitude * Math.sin(progress / p.road_period + p.road_phase); }
  function targetPoint(target, tick = model.tick) { return [target.base_x + target.orbit_x * Math.sin(tick * .17 + target.phase), target.base_y + target.orbit_y * Math.cos(tick * .13 + target.phase * .7)]; }
  function stagePoint(event) { const rect = model.canvas.getBoundingClientRect(); return [Math.max(0, Math.min(model.state.stage.width, (event.clientX - rect.left) / rect.width * model.state.stage.width)), Math.max(0, Math.min(model.state.stage.height, (event.clientY - rect.top) / rect.height * model.state.stage.height))]; }
  function setMessage(message, status = "idle") { model.helpers.setReadout(message, status); }
  function clearFreshFailure() { document.querySelector(".hover-fresh-stamp")?.remove(); document.querySelector(".hovercar-captcha")?.removeAttribute("data-fresh-failure"); }
  function freshRun() { const lateral = road(0); Object.assign(model, {tick: 0, progress: 0, lateral, lateralVelocity: 0, speed: model.state.physics.start_speed, keys: new Set(), pointer: null, crashed: false, finished: false, crashReason: null, dwell: Object.fromEntries(model.state.targets.map(item => [item.id, 0])), checks: new Set()}); }
  function normalizedKey(key) { const value = String(key).toLowerCase(); if (["arrowup", "w"].includes(value)) return "up"; if (["arrowdown", "s"].includes(value)) return "down"; if (["arrowleft", "a"].includes(value)) return "left"; if (["arrowright", "d"].includes(value)) return "right"; return null; }
  function updateKey(event, down) { const key = normalizedKey(event.key); if (!key || model.crashed || model.finished || model.terminal) return; clearFreshFailure(); event.preventDefault(); if (down === model.keys.has(key)) return; if (down) model.keys.add(key); else model.keys.delete(key); record("key_transition", {tick: model.tick, key, down}); updateControls(); }
  function updateControls() { document.querySelectorAll(".hover-key").forEach(node => { node.dataset.active = model.keys.has(node.dataset.key) ? "true" : "false"; }); }
  function collisionReason() {
    const p = model.state.physics, center = road(model.progress);
    if (Math.abs(model.lateral - center) > p.road_half_width - p.car_half_height) return "road_departure";
    for (const obstacle of model.state.obstacles) {
      const obstacleY = road(obstacle.world_x) + obstacle.lane_offset;
      const hitX = Math.abs(model.progress - obstacle.world_x) <= obstacle.width / 2 + p.car_half_width;
      const hitY = Math.abs(model.lateral - obstacleY) <= obstacle.height / 2 + p.car_half_height;
      if (hitX && hitY) return `collision:${obstacle.id}`;
    }
    if (model.tick > p.deadline_tick) return "deadline";
    return null;
  }
  function finishCrash(reason) {
    model.crashed = true; model.crashReason = reason; model.keys.clear(); record("crash", {tick: model.tick, reason}); updateControls();
    const panel = document.querySelector(".hover-crash"); if (panel) { panel.dataset.visible = "true"; panel.querySelector("span").textContent = reason.replaceAll("_", " ").toUpperCase(); }
    document.querySelector(".hover-stage")?.classList.add("is-crashed"); setMessage(`CRASH · ${reason.replaceAll("_", " ").toUpperCase()} · RETRY WITHOUT RELOADING`, "error");
  }
  function physicsTick() {
    if (!model || model.crashed || model.finished || model.terminal) return;
    const p = model.state.physics, up = model.keys.has("up"), down = model.keys.has("down");
    const previousProgress = model.progress;
    const steer = (model.keys.has("right") ? 1 : 0) - (model.keys.has("left") ? 1 : 0);
    model.speed = Math.max(p.min_speed, Math.min(p.max_speed, model.speed + (up ? p.acceleration : 0) - (down ? p.brake : 0) - p.drag));
    model.lateralVelocity = (model.lateralVelocity + steer * p.steer_gain) * p.lateral_damping;
    model.lateral += model.lateralVelocity; model.progress += model.speed / 10; model.tick += 1;
    const state = {progress: round(model.progress), lateral: round(model.lateral), lateral_velocity: round(model.lateralVelocity), speed: round(model.speed), road_center: round(road(model.progress))};
    record("physics_tick", {tick: model.tick, state});
    for (const target of model.state.targets) {
      if (model.checks.has(target.id)) continue; const position = targetPoint(target); const insideWindow = model.tick >= target.window_start && model.tick <= target.window_end;
      const inside = model.pointer && Math.hypot(model.pointer[0] - position[0], model.pointer[1] - position[1]) <= target.radius;
      if (insideWindow && inside && model.speed >= p.min_speed && model.progress - previousProgress >= model.state.requirements.minimum_motion_during_dwell) {
        model.dwell[target.id] += 1;
        setMessage(`TRACKING CHECK ${model.checks.size + 1} · KEEP STEERING`, "pending");
        if (model.dwell[target.id] >= target.required_ticks) { model.checks.add(target.id); record("check_complete", {tick: model.tick, target_id: target.id}); document.querySelector(`.hover-check[data-target-id="${CSS.escape(target.id)}"]`)?.setAttribute("data-complete", "true"); }
      } else model.dwell[target.id] = 0;
    }
    const reason = collisionReason();
    if (reason) { finishCrash(reason); return; }
    if (model.progress >= p.finish_progress) {
      if (model.checks.size === model.state.targets.length) {
        model.finished = true; model.keys.clear(); record("finish", {tick: model.tick, checks: [...model.checks].sort()}); updateControls(); document.querySelector(".hover-finish")?.setAttribute("data-visible", "true"); setMessage("FINISH GATE CROSSED · ALL MOVING CHECKS HELD UNDER LIVE PHYSICS", "passed");
      } else finishCrash("inspection_incomplete");
    }
    updateHUD();
  }
  function updateHUD() {
    const p = model.state.physics;
    const tick = document.querySelector(".hover-tick-value"); if (tick) tick.textContent = `${model.tick} / ${p.deadline_tick}`;
    const speed = document.querySelector(".hover-speed-value"); if (speed) speed.textContent = `${model.speed.toFixed(1)}`;
    const progress = document.querySelector(".hover-progress-meter i"); if (progress) progress.style.width = `${Math.min(100, model.progress / p.finish_progress * 100)}%`;
    for (const target of model.state.targets) { const meter = document.querySelector(`.hover-check[data-target-id="${CSS.escape(target.id)}"] i`); if (meter) meter.style.width = `${Math.min(100, model.dwell[target.id] / target.required_ticks * 100)}%`; }
  }
  function retry() {
    if (!model.crashed || model.terminal) return; record("retry", {from_tick: model.tick}); model.retries += 1; freshRun(); document.querySelector(".hover-crash")?.setAttribute("data-visible", "false"); document.querySelector(".hover-stage")?.classList.remove("is-crashed"); document.querySelectorAll(".hover-check").forEach(node => node.dataset.complete = "false"); updateControls(); updateHUD(); setMessage("HOVERCRAFT RE-ARMED · STEERING AND INSPECTION CLOCK RESTARTED");
  }
  async function submit() {
    if (model.submitting || model.terminal) return; model.submitting = true; setMessage("FIXED-STEP REPLAYING KEYS, COLLISIONS, POINTER SAMPLES, AND CONTIGUOUS DWELL…", "pending");
    const payload = {mechanic_id: model.state.mechanic_id, task_id: model.state.task_id, challenge_id: model.state.challenge_id, events: model.events, completed_checks: [...model.checks].sort(), crashes: model.crashes, retries: model.retries, pointer_samples: model.pointerSamples, final_tick: model.tick, final_progress: Math.round(model.progress * 1000) / 1000, finished: model.finished};
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload)}); const outcome = await response.json();
      if (outcome.passed === true) { model.terminal = true; document.querySelector(".hovercar-captcha")?.insertAdjacentHTML("beforeend", '<div class="hover-verdict"><span>DIVIDED-ATTENTION FLIGHT AUTHENTICATED</span><strong>PASS</strong><small>CONTINUOUS DRIVE · SYMMETRIC COLLISIONS · TEMPORAL POINTER REPLAY</small></div>'); model.helpers.setReadout("PASS", "passed"); }
      else if (outcome.passed === false && outcome.state) { await model.helpers.render(outcome.state); const root = document.querySelector(".hovercar-captcha"); root?.setAttribute("data-fresh-failure", "true"); root?.insertAdjacentHTML("afterbegin", '<div class="hover-fresh-stamp"><b>FAIL</b><span>FLIGHT RECORD REJECTED · FRESH COURSE ISSUED</span></div>'); setTimeout(clearFreshFailure, 1700); const readout = document.querySelector(".readout"); if (readout) { readout.textContent = "FAIL · FRESH HOVERCAR COURSE ISSUED"; readout.dataset.status = "error"; } }
      else { model.submitting = false; setMessage("FAIL · NO AUTHORITATIVE FLIGHT GRADE", "error"); }
    } catch (_error) { model.submitting = false; setMessage("FAIL · FLIGHT REPLAY VERIFIER OFFLINE", "error"); }
  }
  function motif(ctx, target, point, active) {
    ctx.save(); ctx.translate(point[0], point[1]); ctx.strokeStyle = target.color; ctx.fillStyle = active ? `${target.color}35` : `${target.color}12`; ctx.lineWidth = active ? 5 : 2; ctx.shadowColor = target.color; ctx.shadowBlur = active ? 20 : 6; ctx.beginPath();
    if (target.motif === "ring-notch") { ctx.arc(0, 0, 19, .3, Math.PI * 1.75); ctx.lineTo(7, -7); }
    else if (target.motif === "split-kite") { ctx.moveTo(0, -23); ctx.lineTo(20, 0); ctx.lineTo(0, 23); ctx.lineTo(-20, 0); ctx.closePath(); ctx.moveTo(-10, 0); ctx.lineTo(10, 0); }
    else if (target.motif === "triple-fin") { ctx.moveTo(-22, 18); ctx.lineTo(-8, -20); ctx.lineTo(0, 16); ctx.lineTo(9, -18); ctx.lineTo(22, 18); }
    else if (target.motif === "hollow-cross") { ctx.rect(-6, -22, 12, 44); ctx.rect(-22, -6, 44, 12); }
    else { ctx.arc(0, 0, 18, 0, Math.PI * 2); ctx.moveTo(9, -13); ctx.arc(9, -13, 4, 0, Math.PI * 2); }
    ctx.fill(); ctx.stroke(); ctx.restore();
  }
  function draw() {
    if (!model) return; const ctx = model.canvas.getContext("2d"), stage = model.state.stage, p = model.state.physics;
    ctx.clearRect(0, 0, stage.width, stage.height); const gradient = ctx.createLinearGradient(0, 0, stage.width, stage.height); gradient.addColorStop(0, "#09151c"); gradient.addColorStop(1, "#07100f"); ctx.fillStyle = gradient; ctx.fillRect(0, 0, stage.width, stage.height);
    const carX = 220, scale = .72; ctx.lineCap = "round";
    for (const offset of [-p.road_half_width, p.road_half_width]) { ctx.beginPath(); for (let x = -20; x <= stage.width + 20; x += 12) { const world = model.progress + (x - carX) / scale, y = road(world) + offset; x === -20 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); } ctx.strokeStyle = "#6dffdc66"; ctx.lineWidth = 3; ctx.stroke(); }
    ctx.beginPath(); for (let x = -20; x <= stage.width + 20; x += 18) { const world = model.progress + (x - carX) / scale, y = road(world); x === -20 ? ctx.moveTo(x, y) : ctx.lineTo(x, y); } ctx.setLineDash([9, 13]); ctx.strokeStyle = "#e7fffb33"; ctx.lineWidth = 2; ctx.stroke(); ctx.setLineDash([]);
    for (const obstacle of model.state.obstacles) { const x = carX + (obstacle.world_x - model.progress) * scale, y = road(obstacle.world_x) + obstacle.lane_offset; if (x < -80 || x > stage.width + 80) continue; ctx.save(); ctx.translate(x, y); ctx.fillStyle = "#ff6f5c"; ctx.shadowColor = "#ff6f5c"; ctx.shadowBlur = 10; ctx.fillRect(-obstacle.width / 2, -obstacle.height / 2, obstacle.width, obstacle.height); ctx.fillStyle = "#170908"; for (let stripe = -obstacle.width; stripe < obstacle.width; stripe += 16) ctx.fillRect(stripe, -3, 9, 6); ctx.restore(); }
    for (const target of model.state.targets) { const visible = model.tick >= target.window_start && model.tick <= target.window_end && !model.checks.has(target.id); if (visible) motif(ctx, target, targetPoint(target), model.pointer && Math.hypot(model.pointer[0] - targetPoint(target)[0], model.pointer[1] - targetPoint(target)[1]) <= target.radius); }
    ctx.save(); ctx.translate(carX, model.lateral); const bank = Math.max(-.22, Math.min(.22, model.lateralVelocity / 25)); ctx.rotate(bank); ctx.fillStyle = model.crashed ? "#ff6f5c" : "#b8ff58"; ctx.shadowColor = ctx.fillStyle; ctx.shadowBlur = 18; ctx.beginPath(); ctx.roundRect(-p.car_half_width, -p.car_half_height, p.car_half_width * 2, p.car_half_height * 2, 9); ctx.fill(); ctx.fillStyle = "#07100f"; ctx.fillRect(-8, -8, 18, 16); ctx.fillStyle = "#60e6ff"; ctx.fillRect(-p.car_half_width - 6, -8, 8, 4); ctx.fillRect(-p.car_half_width - 6, 4, 8, 4); ctx.restore();
    if (model.pointer) { ctx.strokeStyle = "#fff"; ctx.lineWidth = 1; ctx.beginPath(); ctx.arc(model.pointer[0], model.pointer[1], 9, 0, Math.PI * 2); ctx.stroke(); ctx.beginPath(); ctx.moveTo(model.pointer[0] - 14, model.pointer[1]); ctx.lineTo(model.pointer[0] + 14, model.pointer[1]); ctx.moveTo(model.pointer[0], model.pointer[1] - 14); ctx.lineTo(model.pointer[0], model.pointer[1] + 14); ctx.stroke(); }
    model.raf = requestAnimationFrame(draw);
  }
  async function render(state, helpers) {
    if (model?.raf) cancelAnimationFrame(model.raf); if (model?.timer) clearInterval(model.timer); if (model?.onKeyDown) window.removeEventListener("keydown", model.onKeyDown); if (model?.onKeyUp) window.removeEventListener("keyup", model.onKeyUp);
    document.body.dataset.mechanic = "crash-deadline-hovercar"; document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    helpers.app.innerHTML = `<section class="hovercar-captcha" data-challenge-id="${clean(state.challenge_id)}"><header class="hover-head"><div><span>DUAL-CHANNEL FLIGHT / COURSE ${clean(state.challenge_id)}</span><h1>${clean(state.prompt)}</h1></div><div class="hover-warning"><b>THE VEHICLE NEVER PAUSES</b><span>Steer with the keyboard while your pointer tracks each sigil.</span></div></header><main class="hover-main"><section class="hover-stage"><canvas class="hover-canvas" width="${state.stage.width}" height="${state.stage.height}"></canvas><div class="hover-stage-label">KEYBOARD: DRIVE · POINTER: TRACK</div><div class="hover-crash" data-visible="false"><b>IMPACT</b><span>ROAD DEPARTURE</span><button type="button" class="hover-retry">RETRY COURSE</button></div><div class="hover-finish" data-visible="false"><b>FLIGHT COMPLETE</b><span>ALL CHECKS LOCKED WHILE MOVING</span></div></section><aside class="hover-console"><p>INSPECTION MANIFEST</p><h2>Hold the pointer inside each moving mark without losing the road.</h2><div class="hover-checks">${state.targets.map((target, index) => `<div class="hover-check" data-target-id="${clean(target.id)}" data-complete="false" style="--target:${clean(target.color)}"><div class="hover-motif-preview" data-motif="${clean(target.motif)}">${index + 1}</div><span>FLIGHT CHECK ${index + 1}<small>HOLD UNTIL THE BAR LOCKS</small></span><em><i></i></em></div>`).join("")}</div><div class="hover-hud"><div><span>COURSE TIME</span><b class="hover-tick-value">0 / ${state.physics.deadline_tick}</b></div><div><span>SPEED</span><b class="hover-speed-value">${state.physics.start_speed.toFixed(1)}</b></div><em class="hover-progress-meter"><i></i></em></div><div class="hover-keys"><i class="hover-key" data-key="up">W</i><i class="hover-key" data-key="left">A</i><i class="hover-key" data-key="down">S</i><i class="hover-key" data-key="right">D</i></div><p class="hover-console-note">Missing the mark resets only that lock. A crash can be retried immediately.</p></aside></main><footer class="hover-foot"><div><span>FLIGHT STATUS</span><div class="readout" data-status="idle">PRESS W / ARROW-UP TO ACCELERATE</div></div><button type="button" class="hover-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    model = {state, helpers, canvas: document.querySelector(".hover-canvas"), events: [], pointerSamples: 0, crashes: 0, retries: 0, submitting: false, terminal: false, timer: null, raf: null}; window.crashDeadlineHovercarModel = model; freshRun(); model.targetPoint = targetPoint;
    model.onKeyDown = event => updateKey(event, true); model.onKeyUp = event => updateKey(event, false); window.addEventListener("keydown", model.onKeyDown); window.addEventListener("keyup", model.onKeyUp);
    model.canvas.addEventListener("pointermove", event => { if (model.crashed || model.finished || model.terminal) return; clearFreshFailure(); const point = stagePoint(event); model.pointer = point; model.pointerSamples += 1; record("pointer_move", {tick: model.tick, point: point.map(round)}); });
    document.querySelector(".hover-retry").addEventListener("click", () => { model.crashes += 1; retry(); }); document.querySelector(".hover-submit").addEventListener("click", submit); helpers.installCheatPanel(); model.timer = setInterval(physicsTick, state.physics.tick_ms); model.raf = requestAnimationFrame(draw); updateHUD();
  }
  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {}; window.WeirdCaptchaMechanics.crash_deadline_hovercar = {rootSelector: ".hovercar-captcha", render};
})();
