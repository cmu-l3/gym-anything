(() => {
  "use strict";

  let model = null;
  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const round2 = (value) => Math.round(Number(value) * 100) / 100;
  const clean = (value) => String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const sector = (angle) => angle < -36 ? 0 : angle < -12 ? 1 : angle < 12 ? 2 : angle < 36 ? 3 : 4;
  function record(kind, details = {}) { const event = {sequence: model.events.length + 1, kind, ...details}; model.events.push(event); return event; }
  function stagePoint(event) { const rect = document.getElementById("orchard-canvas").getBoundingClientRect(); return [round2(clamp((event.clientX - rect.left) / rect.width * model.state.stage.width, 0, model.state.stage.width)), round2(clamp((event.clientY - rect.top) / rect.height * model.state.stage.height, 0, model.state.stage.height))]; }

  function project(point, angle = model.angle) {
    const radians = angle * Math.PI / 180, [x, y, z] = point;
    return [430 + x * Math.cos(radians) + z * Math.sin(radians), 246 + y + .10 * z * Math.cos(radians) - .05 * x * Math.sin(radians)];
  }
  function depth(point, angle = model.angle) { const radians = angle * Math.PI / 180; return point[2] * Math.cos(radians) - point[0] * Math.sin(radians); }
  function exploredEnough() {
    const r = model.state.requirements;
    const span = Math.max(...model.angles) - Math.min(...model.angles);
    const travel = model.angles.slice(1).reduce((sum, angle, index) => sum + Math.abs(angle - model.angles[index]), 0);
    return model.orbitSamples >= r.minimum_orbit_samples && span >= r.minimum_orbit_span_deg && travel >= r.minimum_orbit_travel_deg && model.sectors.size >= r.minimum_view_sectors;
  }
  function stats() {
    const span = round2(Math.max(...model.angles) - Math.min(...model.angles));
    const travel = round2(model.angles.slice(1).reduce((sum, angle, index) => sum + Math.abs(angle - model.angles[index]), 0));
    return {span, travel};
  }

  function drawBranch(context, branch) {
    const points = branch.points.map((point) => project(point));
    context.beginPath(); context.moveTo(points[0][0], points[0][1]); points.slice(1).forEach((point) => context.lineTo(point[0], point[1]));
    context.strokeStyle = "#3e241b"; context.lineWidth = 13; context.lineCap = "round"; context.lineJoin = "round"; context.stroke();
    context.strokeStyle = "#9a6040"; context.lineWidth = 4; context.stroke();
  }
  function drawFruit(context, apple) {
    if (model.plucked.has(apple.id)) return;
    const center = project(apple.position), stemTop = project([apple.position[0], apple.position[1] - 28, apple.position[2]]), radius = Number(apple.radius);
    context.beginPath(); context.moveTo(center[0], center[1] - radius * .45); context.lineTo(stemTop[0], stemTop[1]); context.strokeStyle = "#3a2718"; context.lineWidth = 5; context.lineCap = "round"; context.stroke();
    const palette = apple.hue === "gold" ? ["#ffd569", "#bf6a24"] : apple.hue === "rose" ? ["#ff7b82", "#9b273d"] : ["#ec4150", "#741d2a"];
    const gradient = context.createRadialGradient(center[0] - radius * .32, center[1] - radius * .36, 2, center[0], center[1], radius * 1.25);
    gradient.addColorStop(0, palette[0]); gradient.addColorStop(1, palette[1]);
    context.beginPath(); context.ellipse(center[0], center[1], radius, radius * .92, 0, 0, Math.PI * 2); context.fillStyle = gradient; context.shadowColor = "rgba(48,12,18,.45)"; context.shadowBlur = 12; context.fill(); context.shadowBlur = 0;
    context.beginPath(); context.ellipse(center[0] - radius * .25, center[1] - radius * .28, radius * .16, radius * .25, -.6, 0, Math.PI * 2); context.fillStyle = "rgba(255,255,255,.34)"; context.fill();
    if (apple.scar) { context.fillStyle = "rgba(74,22,22,.62)"; context.fillRect(center[0] + radius * .25, center[1] + radius * .05, 3 + apple.scar, 2); }
  }
  function drawBasket(context) {
    const basket = model.state.basket;
    context.save(); context.fillStyle = "rgba(73,41,23,.88)"; context.strokeStyle = "#e4ad64"; context.lineWidth = 4;
    context.beginPath(); context.moveTo(basket.x + 10, basket.y + 24); context.lineTo(basket.x + basket.width - 10, basket.y + 24); context.lineTo(basket.x + basket.width - 32, basket.y + basket.height); context.lineTo(basket.x + 32, basket.y + basket.height); context.closePath(); context.fill(); context.stroke();
    context.strokeStyle = "rgba(248,203,126,.48)"; context.lineWidth = 2; for (let y = basket.y + 43; y < basket.y + basket.height; y += 20) { context.beginPath(); context.moveTo(basket.x + 20, y); context.lineTo(basket.x + basket.width - 20, y); context.stroke(); }
    context.fillStyle = "#f1c177"; context.font = "900 10px Courier New"; context.textAlign = "center"; context.fillText(`HARVEST ${model.plucked.size}/3`, basket.x + basket.width / 2, basket.y + 18); context.restore();
  }
  function draw() {
    if (!model) return;
    const canvas = document.getElementById("orchard-canvas"), context = canvas?.getContext("2d"); if (!canvas || !context) return;
    const sky = context.createLinearGradient(0, 0, 0, canvas.height); sky.addColorStop(0, "#101c30"); sky.addColorStop(.62, "#273d3b"); sky.addColorStop(1, "#17251e"); context.fillStyle = sky; context.fillRect(0, 0, canvas.width, canvas.height);
    context.strokeStyle = "rgba(172,218,190,.10)"; context.lineWidth = 1; const shift = model.angle * 2.2; for (let x = -220; x < canvas.width + 220; x += 55) { context.beginPath(); context.moveTo(x + shift, 368); context.lineTo(430 + (x - 430) * .2, 246); context.stroke(); }
    context.beginPath(); context.ellipse(430, 430, 410, 58, 0, 0, Math.PI * 2); context.fillStyle = "rgba(7,15,14,.42)"; context.fill();
    context.beginPath(); context.moveTo(396, 390); context.bezierCurveTo(402, 302, 388, 218, 418, 132); context.bezierCurveTo(451, 216, 445, 314, 468, 390); context.closePath(); context.fillStyle = "#54301f"; context.fill(); context.strokeStyle = "#a0633f"; context.lineWidth = 5; context.stroke();
    const items = [];
    model.state.branches.forEach((branch) => items.push({kind: "branch", depth: branch.points.reduce((sum, p) => sum + depth(p), 0) / branch.points.length, value: branch}));
    model.state.apples.forEach((apple) => items.push({kind: "fruit", depth: depth(apple.position), value: apple}));
    items.sort((a, b) => a.depth - b.depth).forEach((item) => item.kind === "branch" ? drawBranch(context, item.value) : drawFruit(context, item.value));
    drawBasket(context);
    if (model.dragFruit) { const apple = model.appleMap[model.dragFruit.appleId], p = model.dragFruit.point, r = Number(apple.radius); context.globalAlpha = .72; context.beginPath(); context.arc(p[0], p[1], r, 0, Math.PI * 2); context.fillStyle = apple.hue === "gold" ? "#f5b946" : "#e94d61"; context.fill(); context.globalAlpha = 1; }
    context.fillStyle = "rgba(219,239,224,.76)"; context.font = "800 9px Courier New"; context.textAlign = "left"; context.fillText(`ORBIT ${model.angle > 0 ? "+" : ""}${Math.round(model.angle)}°`, 22, 28);
  }

  function updateInterface() {
    if (!model) return; const root = document.querySelector(".parallax-orchard"), s = stats(), ready = exploredEnough();
    root.dataset.ready = ready ? "true" : "false"; root.dataset.strike = model.strikeActive ? "true" : "false"; root.dataset.completed = model.plucked.size === 3 ? "true" : "false";
    document.getElementById("orchard-angle").textContent = `${model.angle > 0 ? "+" : ""}${Math.round(model.angle)}°`;
    document.getElementById("orchard-span").textContent = `${Math.round(s.span)}°`;
    document.getElementById("orchard-views").textContent = `${model.sectors.size}/5`;
    document.getElementById("orchard-count").textContent = `${model.plucked.size}/3`;
    const instruction = document.getElementById("orchard-status");
    if (model.strikeActive) instruction.textContent = "FALSE DEPTH CONTACT — RESET THE HARVEST";
    else if (model.plucked.size === 3) instruction.textContent = "THREE TRUE STEMS HARVESTED";
    else if (ready) instruction.textContent = "DEPTH BASELINE ACQUIRED — DRAG JOINED FRUIT INTO BASKET";
    else instruction.textContent = "DRAG THE ORCHARD LEFT AND RIGHT TO EXPOSE DEPTH";
    draw();
  }

  function hitApple(point) {
    const candidates = model.state.apples.filter((apple) => !model.plucked.has(apple.id)).map((apple) => ({apple, center: project(apple.position), depth: depth(apple.position)})).filter((item) => distance(point, item.center) <= Number(item.apple.radius) + 8).sort((a, b) => b.depth - a.depth);
    return candidates[0]?.apple || null;
  }
  function pointerDown(event) {
    if (!model || model.submitting || model.terminal || model.hold) return; const point = stagePoint(event), apple = exploredEnough() && !model.strikeActive ? hitApple(point) : null;
    if (apple) { model.hold = {kind: "pluck", pointerId: event.pointerId, appleId: apple.id, startedAt: performance.now(), moves: 0}; model.dragFruit = {appleId: apple.id, point}; record("pluck_start", {apple_id: apple.id, point, angle: model.angle}); }
    else { model.hold = {kind: "orbit", pointerId: event.pointerId, start: point, last: point, baseAngle: model.angle}; record("orbit_start", {point, angle_before: model.angle}); }
    event.currentTarget.setPointerCapture?.(event.pointerId); event.preventDefault(); updateInterface();
  }
  function pointerMove(event) {
    if (!model?.hold || model.hold.pointerId !== event.pointerId) return; const point = stagePoint(event);
    if (model.hold.kind === "orbit") { if (distance(point, model.hold.last) < 2) return; model.angle = round2(clamp(model.hold.baseAngle + (point[0] - model.hold.start[0]) * .24, -model.state.view_limit_deg, model.state.view_limit_deg)); model.hold.last = point; model.orbitSamples += 1; model.angles.push(model.angle); model.sectors.add(sector(model.angle)); record("orbit_move", {point, angle_after: model.angle}); }
    else { if (distance(point, model.dragFruit.point) < 4) return; model.dragFruit.point = point; model.hold.moves += 1; record("pluck_move", {apple_id: model.hold.appleId, point, elapsed_ms: Math.round(performance.now() - model.hold.startedAt)}); }
    if (model.hold.kind === "orbit") model.helpers.setReadout(exploredEnough() ? "DEPTH BASELINE ACQUIRED" : "PARALLAX SWEEP IN PROGRESS", exploredEnough() ? "idle" : "pending");
    updateInterface(); event.preventDefault();
  }
  function pointerUp(event) {
    if (!model?.hold || model.hold.pointerId !== event.pointerId) return; const point = stagePoint(event), hold = model.hold; model.hold = null; event.currentTarget.releasePointerCapture?.(event.pointerId);
    if (hold.kind === "orbit") record("orbit_end", {point, angle: model.angle});
    else {
      const b = model.state.basket, inBasket = point[0] >= b.x && point[0] <= b.x + b.width && point[1] >= b.y && point[1] <= b.y + b.height;
      const accepted = inBasket && model.attached.has(hold.appleId) && hold.moves >= model.state.requirements.minimum_pluck_moves && performance.now() - hold.startedAt >= model.state.requirements.minimum_pluck_ms;
      record("pluck_end", {apple_id: hold.appleId, point, duration_ms: Math.round(performance.now() - hold.startedAt), in_basket: inBasket, accepted});
      if (accepted) { model.plucked.add(hold.appleId); model.helpers.setReadout("TRUE STEM RELEASED", "idle"); }
      else if (inBasket) { model.invalidPlucks += 1; model.strikeActive = true; model.helpers.setReadout("FALSE CONTACT / HARVEST QUARANTINED", "error"); }
      model.dragFruit = null;
    }
    updateInterface();
  }
  function resetHarvest() { if (!model || model.hold || model.submitting || model.terminal) return; record("reset"); model.plucked.clear(); model.strikeActive = false; model.resetCount += 1; model.helpers.setReadout("HARVEST RESET / CAMERA BASELINE RETAINED", "idle"); updateInterface(); }
  function payload() { const s = stats(); return {mechanic_id: model.state.mechanic_id, task_id: model.state.task_id, challenge_id: model.state.challenge_id, events: model.events, final_angle_deg: model.angle, orbit_samples: model.orbitSamples, orbit_span_deg: s.span, orbit_travel_deg: s.travel, view_sector_count: model.sectors.size, plucked_ids: [...model.plucked].sort(), invalid_plucks: model.invalidPlucks, reset_count: model.resetCount, seal_count: model.sealCount, completed: model.plucked.size === 3 && !model.strikeActive}; }
  async function submit() {
    if (!model || model.submitting || model.terminal || model.hold) return; record("seal"); model.sealCount += 1; const current = model; current.submitting = true; current.helpers.setReadout("REPLAYING CAMERA PARALLAX AND HARVEST GEOMETRY…", "pending");
    try { const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload())}); const outcome = await response.json(); if (outcome.passed === true) { current.terminal = true; current.helpers.setReadout("PASS", "passed"); const verdict = document.querySelector(".orchard-verdict"); if (verdict) verdict.innerHTML = "<b>PASS</b><span>TRUE DEPTH CONTACTS VERIFIED</span>"; document.querySelector(".parallax-orchard")?.setAttribute("data-verdict", "pass"); } else if (outcome.passed === false && outcome.state) { const helpers = current.helpers; await render(outcome.state, helpers, {freshFailure: true}); model.helpers.setReadout("FAIL", "error"); } else { current.submitting = false; current.helpers.setReadout("HARVEST REJECTED", "error"); } } catch (_error) { if (model === current) { current.submitting = false; current.helpers.setReadout("ORCHARD VERIFIER OFFLINE", "error"); } }
  }

  async function render(state, helpers, options = {}) {
    document.body.dataset.mechanic = "parallax-orchard"; document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {state, helpers, appleMap: Object.fromEntries(state.apples.map((apple) => [apple.id, apple])), attached: new Set(), angle: Number(state.initial_angle_deg), angles: [Number(state.initial_angle_deg)], sectors: new Set([sector(Number(state.initial_angle_deg))]), orbitSamples: 0, events: [], hold: null, dragFruit: null, plucked: new Set(), invalidPlucks: 0, strikeActive: false, resetCount: 0, sealCount: 0, submitting: false, terminal: false}; window.parallaxOrchardModel = model;
    // Attachment is derived from exact 3-D branch/stem contact, not a public
    // answer flag. This is also what the player sees after orbiting.
    const branchByFruit = Object.fromEntries(state.branches.map((branch) => [branch.fruit_id, branch])); state.apples.forEach((apple) => { const tip = branchByFruit[apple.id].points.at(-1); if (Math.abs(tip[2] - apple.position[2]) < .01) model.attached.add(apple.id); });
    helpers.app.innerHTML = `<section class="parallax-orchard" data-fresh-failure="${options.freshFailure ? "true" : "false"}" data-verdict=""><div class="orchard-verdict"><b>${options.freshFailure ? "FAIL" : ""}</b><span>${options.freshFailure ? "FRESH ORCHARD ISSUED" : ""}</span></div><header class="orchard-head"><div><span>PARALLAX ORCHARD / ${clean(state.challenge_id)}</span><h1>${clean(state.prompt)}</h1></div><div class="orchard-dial"><span>VIEW</span><b id="orchard-angle">0°</b><i></i></div></header><main class="orchard-main"><section class="orchard-stage"><canvas id="orchard-canvas" width="${state.stage.width}" height="${state.stage.height}"></canvas><div class="orbit-gesture"><i>↔</i><span>DRAG SPACE TO ORBIT<br>DRAG FRUIT TO HARVEST</span></div></section><aside class="orchard-console"><span>DEPTH NOTE</span><h2>Projection lies.<br>Parallax does not.</h2><div class="orchard-rule"></div><dl><div><dt>BASELINE</dt><dd id="orchard-span">0°</dd></div><div><dt>VIEWS</dt><dd id="orchard-views">1/5</dd></div><div><dt>TRUE STEMS</dt><dd id="orchard-count">0/3</dd></div></dl><p>A branch that only touches a stem from one viewpoint is not joined to it.</p><button id="orchard-reset">RESET HARVEST</button></aside></main><footer class="orchard-foot"><div><span id="orchard-status">DRAG THE ORCHARD LEFT AND RIGHT TO EXPOSE DEPTH</span><div class="readout" data-status="idle">ORBIT LOCK RELEASED</div></div><button id="orchard-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    const canvas = document.getElementById("orchard-canvas"); canvas.addEventListener("pointerdown", pointerDown); canvas.addEventListener("pointermove", pointerMove); canvas.addEventListener("pointerup", pointerUp); canvas.addEventListener("pointercancel", pointerUp); document.getElementById("orchard-reset").addEventListener("click", resetHarvest); document.getElementById("orchard-submit").addEventListener("click", submit); helpers.installCheatPanel(); updateInterface();
    if (options.freshFailure) { const current = model; setTimeout(() => { if (model !== current) return; document.querySelector(".parallax-orchard")?.setAttribute("data-fresh-failure", "false"); if (!current.events.length) current.helpers.setReadout("ORBIT LOCK RELEASED", "idle"); }, 1350); }
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.surreal_apple_on_tree_grid = {rootSelector: ".parallax-orchard", render};
})();
