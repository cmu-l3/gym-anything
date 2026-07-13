(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;
  const COLOR_MAP = {
    crimson: "#e64a53", amber: "#e6aa38", cobalt: "#4475c7", ivory: "#eee2bd",
    violet: "#985fc4", jade: "#51a87c", coral: "#ee7d68", slate: "#71808b", copper: "#bd7448",
  };
  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const round = (value) => Math.round(Number(value) * 1000) / 1000;
  const clonePose = (pose) => ({x: Number(pose.x), y: Number(pose.y), angle_deg: Number(pose.angle_deg), flipped: Boolean(pose.flipped)});

  function nowMs() { return Math.round(performance.now() - model.startedAt); }
  function record(type, details = {}) {
    const event = {seq: model.events.length + 1, t_ms: nowMs(), type, ...details};
    model.events.push(event);
    return event;
  }
  function wrapAngle(value) { return ((Number(value) % 360) + 360) % 360; }
  function plateById(id) { return model.state.plates.find((plate) => plate.id === id) || null; }
  function activePlate() { return plateById(model.selectedPlateId); }
  function activePose() { return model.poses[model.selectedPlateId] || null; }
  function poseClaim(pose) { return {x: round(pose.x), y: round(pose.y), angle_deg: wrapAngle(pose.angle_deg), flipped: Boolean(pose.flipped)}; }

  function transformPoint(point, pose) {
    let x = Number(point.x), y = Number(point.y);
    if (pose.flipped) x = -x;
    const angle = Number(pose.angle_deg) * Math.PI / 180;
    const cosine = Math.cos(angle), sine = Math.sin(angle);
    return {x: pose.x + x * cosine - y * sine, y: pose.y + x * sine + y * cosine};
  }

  function localPoint(point, pose) {
    const dx = point.x - pose.x, dy = point.y - pose.y;
    const angle = -Number(pose.angle_deg) * Math.PI / 180;
    const cosine = Math.cos(angle), sine = Math.sin(angle);
    let x = dx * cosine - dy * sine;
    const y = dx * sine + dy * cosine;
    if (pose.flipped) x = -x;
    return {x, y};
  }

  function canvasPoint(event) {
    const rect = model.canvas.getBoundingClientRect();
    return {
      x: Math.max(0, Math.min(model.state.stage.width, (event.clientX - rect.left) / rect.width * model.state.stage.width)),
      y: Math.max(0, Math.min(model.state.stage.height, (event.clientY - rect.top) / rect.height * model.state.stage.height)),
    };
  }

  function pointInPlate(point, plate, pose) {
    const local = localPoint(point, pose);
    return Math.abs(local.x) <= Number(plate.width) / 2 && Math.abs(local.y) <= Number(plate.height) / 2;
  }

  function drawPin(context, pin, color, hole = false) {
    context.save();
    context.translate(Number(pin.x), Number(pin.y));
    context.strokeStyle = hole ? "rgba(245,255,251,.9)" : color;
    context.fillStyle = hole ? "rgba(1,8,7,.92)" : color;
    context.lineWidth = hole ? 2 : 3;
    context.shadowColor = color;
    context.shadowBlur = hole ? 0 : 11;
    context.beginPath();
    if (pin.shape === "triangle") {
      context.moveTo(0, -9); context.lineTo(8, 7); context.lineTo(-8, 7); context.closePath();
    } else if (pin.shape === "square") {
      context.rect(-7, -7, 14, 14);
    } else {
      context.arc(0, 0, 8, 0, Math.PI * 2);
    }
    if (!hole) context.fill();
    context.stroke();
    context.restore();
  }

  function drawDevice(context) {
    const device = model.state.stage.device;
    const gradient = context.createLinearGradient(device.x, device.y, device.x + device.width, device.y + device.height);
    gradient.addColorStop(0, "#56524b"); gradient.addColorStop(.55, "#34332f"); gradient.addColorStop(1, "#22231f");
    context.fillStyle = "rgba(0,0,0,.42)";
    context.beginPath(); context.roundRect(device.x + 9, device.y + 14, device.width, device.height, 24); context.fill();
    context.fillStyle = gradient;
    context.strokeStyle = "#7f7769";
    context.lineWidth = 7;
    context.beginPath(); context.roundRect(device.x, device.y, device.width, device.height, 24); context.fill(); context.stroke();
    context.setLineDash([7, 8]); context.strokeStyle = "rgba(240,226,196,.18)"; context.lineWidth = 1;
    context.beginPath(); context.roundRect(device.x + 18, device.y + 18, device.width - 36, device.height - 36, 14); context.stroke();
    context.setLineDash([]);
    context.fillStyle = "#171814"; context.fillRect(76, 75, 584, 352);
    context.strokeStyle = "#696359"; context.lineWidth = 2; context.strokeRect(76, 75, 584, 352);
    for (const wire of model.state.wires) {
      const y = Number(wire.y);
      const color = COLOR_MAP[wire.color] || "#aaa";
      context.strokeStyle = "rgba(0,0,0,.65)"; context.lineWidth = 13; context.beginPath(); context.moveTo(96, y + 3); context.bezierCurveTo(220, y - 11, 500, y + 12, 640, y - 2); context.stroke();
      context.strokeStyle = color; context.lineWidth = 8; context.shadowColor = color; context.shadowBlur = model.selectedWireId === wire.id ? 20 : 4;
      context.beginPath(); context.moveTo(96, y); context.bezierCurveTo(220, y - 14, 500, y + 9, 640, y - 5); context.stroke(); context.shadowBlur = 0;
      if (wire.striped) {
        context.setLineDash([11, 9]); context.strokeStyle = "rgba(255,255,255,.65)"; context.lineWidth = 2;
        context.beginPath(); context.moveTo(96, y); context.bezierCurveTo(220, y - 14, 500, y + 9, 640, y - 5); context.stroke(); context.setLineDash([]);
      }
      context.fillStyle = "#d7c9aa"; context.font = "900 11px Courier New"; context.textAlign = "center"; context.fillText(String(Number(wire.slot) + 1).padStart(2, "0"), 93, y + 4);
      context.fillStyle = "#171814"; context.fillRect(633, y - 13, 23, 22); context.strokeStyle = "#8f8067"; context.strokeRect(633, y - 13, 23, 22);
    }
    context.fillStyle = "#d5c69f"; context.fillRect(105, 52, 180, 34);
    context.fillStyle = "#302d27"; context.font = "900 18px Courier New"; context.textAlign = "left"; context.fillText("ACETATE DEFUSAL", 118, 75);
    context.fillStyle = "#9c3d35"; context.font = "900 9px Courier New"; context.fillText("ALIGN BEFORE CUTTING", 475, 61);
    [[56,58],[675,58],[56,445],[675,445]].forEach(([x,y]) => { context.fillStyle = "#171814"; context.beginPath(); context.arc(x,y,7,0,Math.PI*2); context.fill(); context.strokeStyle="#938879"; context.stroke(); });
  }

  function drawPlate(context, plate, pose, {selected = false, locked = false} = {}) {
    context.save();
    context.translate(pose.x, pose.y);
    context.rotate(pose.angle_deg * Math.PI / 180);
    context.scale(pose.flipped ? -1 : 1, 1);
    const halfWidth = Number(plate.width) / 2, halfHeight = Number(plate.height) / 2;
    context.beginPath();
    context.rect(-halfWidth, -halfHeight, Number(plate.width), Number(plate.height));
    for (const aperture of plate.apertures) {
      context.moveTo(Number(aperture.x) + Number(model.state.requirements.aperture_radius_px), Number(aperture.y));
      context.arc(Number(aperture.x), Number(aperture.y), Number(model.state.requirements.aperture_radius_px), 0, Math.PI * 2);
    }
    context.fillStyle = locked ? `${plate.color}62` : `${plate.color}48`;
    context.fill("evenodd");
    context.strokeStyle = selected ? "#ffffff" : plate.color;
    context.lineWidth = selected ? 3 : 2;
    context.shadowColor = plate.color;
    context.shadowBlur = selected ? 18 : 8;
    context.strokeRect(-halfWidth, -halfHeight, Number(plate.width), Number(plate.height));
    context.shadowBlur = 0;
    context.setLineDash([9, 7]); context.strokeStyle = `${plate.color}cc`; context.lineWidth = 1;
    context.strokeRect(-halfWidth + 12, -halfHeight + 12, Number(plate.width) - 24, Number(plate.height) - 24); context.setLineDash([]);
    for (const aperture of plate.apertures) {
      context.strokeStyle = `${plate.color}dd`; context.lineWidth = 2; context.beginPath(); context.arc(Number(aperture.x), Number(aperture.y), Number(model.state.requirements.aperture_radius_px), 0, Math.PI * 2); context.stroke();
    }
    for (const anchor of plate.anchors) drawPin(context, anchor, plate.color, true);
    context.fillStyle = "rgba(255,255,255,.82)"; context.font = "900 13px Courier New"; context.textAlign = "left";
    context.fillText(`${plate.label} / ${locked ? "SEATED" : pose.flipped ? "REVERSE" : "FACE"}`, -halfWidth + 22, -halfHeight + 34);
    context.restore();
  }

  function drawScene() {
    if (!model?.context) return;
    const context = model.context;
    context.clearRect(0, 0, model.canvas.width, model.canvas.height);
    const floor = context.createLinearGradient(0, 0, 0, model.canvas.height);
    floor.addColorStop(0, "#261d16"); floor.addColorStop(1, "#100d0a");
    context.fillStyle = floor; context.fillRect(0, 0, model.canvas.width, model.canvas.height);
    context.strokeStyle = "rgba(238,182,111,.06)"; context.lineWidth = 1;
    for (let x = 0; x < 900; x += 30) { context.beginPath(); context.moveTo(x,0); context.lineTo(x,500); context.stroke(); }
    for (let y = 0; y < 500; y += 30) { context.beginPath(); context.moveTo(0,y); context.lineTo(900,y); context.stroke(); }
    drawDevice(context);
    const selected = activePlate();
    for (const plate of model.state.plates) {
      if (model.locked.has(plate.id)) drawPlate(context, plate, model.poses[plate.id], {locked: true, selected: false});
    }
    if (selected && !model.locked.has(selected.id)) drawPlate(context, selected, model.poses[selected.id], {selected: true});
    if (selected) {
      for (const pin of selected.pins) drawPin(context, pin, selected.color, false);
    }
    if (model.locked.size === model.state.plates.length) {
      context.fillStyle = "rgba(4,10,8,.82)"; context.fillRect(708, 372, 180, 92);
      context.strokeStyle = "#7ef0c2"; context.strokeRect(708, 372, 180, 92);
      context.fillStyle = "#7ef0c2"; context.font = "900 11px Courier New"; context.textAlign = "center"; context.fillText("APERTURES COMBINED", 798, 402);
      context.fillStyle = "#dfffee"; context.font = "700 9px Courier New"; context.fillText("SELECT THE ONLY", 798, 424); context.fillText("FULLY EXPOSED WIRE", 798, 440);
    }
  }

  function maxAnchorError(plate, pose) {
    let maximum = 0;
    for (const anchor of plate.anchors) {
      const pin = plate.pins.find((item) => item.shape === anchor.shape);
      const point = transformPoint(anchor, pose);
      maximum = Math.max(maximum, Math.hypot(point.x - Number(pin.x), point.y - Number(pin.y)));
    }
    return maximum;
  }

  function snapTranslation(plate, pose) {
    let dx = 0, dy = 0;
    for (const anchor of plate.anchors) {
      const pin = plate.pins.find((item) => item.shape === anchor.shape);
      const point = transformPoint(anchor, pose);
      dx += Number(pin.x) - point.x;
      dy += Number(pin.y) - point.y;
    }
    return {...pose, x: pose.x + dx / plate.anchors.length, y: pose.y + dy / plate.anchors.length};
  }

  function clearFreshFailure() {
    const root = document.querySelector(".bomb-manual-captcha");
    root?.removeAttribute("data-fresh-failure");
    root?.querySelector(".bomb-fresh-stamp")?.remove();
  }

  function updateInterface() {
    document.querySelectorAll(".bomb-plate-card").forEach((button) => {
      const id = button.dataset.plateId;
      button.dataset.selected = String(id === model.selectedPlateId);
      button.dataset.locked = String(model.locked.has(id));
      button.disabled = model.submitting || model.terminal;
    });
    const plate = activePlate(), pose = activePose();
    const plateName = document.querySelector(".bomb-active-plate");
    if (plateName && plate && pose) plateName.innerHTML = `<b>${clean(plate.label)}</b><span>${pose.flipped ? "REVERSE" : "FACE"} · ${String(pose.angle_deg).padStart(3, "0")}°</span>`;
    document.querySelectorAll(".bomb-transform-controls button").forEach((button) => { button.disabled = !plate || model.locked.has(plate.id) || model.submitting || model.terminal; });
    const count = document.querySelector(".bomb-status-count b");
    if (count) count.textContent = `${model.locked.size} / ${model.state.plates.length}`;
    const selection = document.querySelector(".bomb-selected-wire");
    if (selection) selection.textContent = model.selectedWireId ? `WIRE ${String(Number(model.state.wires.find(item => item.id === model.selectedWireId).slot) + 1).padStart(2, "0")} SELECTED` : model.locked.size === model.state.plates.length ? "CLICK THE EXPOSED WIRE" : `SEAT ALL ${model.state.plates.length} PLATES`;
    const cut = document.querySelector(".bomb-cut-button");
    if (cut) cut.disabled = !model.selectedWireId || model.locked.size !== model.state.plates.length || model.submitting || model.terminal;
    drawScene();
  }

  function selectPlate(plateId) {
    if (!model || model.submitting || model.terminal || model.selectedPlateId === plateId) return;
    clearFreshFailure();
    model.selectedPlateId = plateId;
    record("plate_select", {plate_id: plateId});
    model.helpers.setReadout(model.locked.has(plateId) ? "PLATE ALREADY SEATED" : "DRAG KEYHOLES OVER THE MATCHING PINS", "idle");
    updateInterface();
  }

  function rotatePlate(direction) {
    const plate = activePlate(), pose = activePose();
    if (!plate || !pose || model.locked.has(plate.id) || model.submitting || model.terminal) return;
    clearFreshFailure();
    const before = pose.angle_deg;
    const delta = direction * Number(model.state.requirements.rotation_step_deg);
    pose.angle_deg = wrapAngle(before + delta);
    record("plate_rotate", {plate_id: plate.id, from_deg: before, to_deg: pose.angle_deg, delta_deg: delta});
    model.helpers.setReadout("ROTATION APPLIED · CHECK ALL THREE KEYHOLES", "idle");
    updateInterface();
  }

  function flipPlate() {
    const plate = activePlate(), pose = activePose();
    if (!plate || !pose || model.locked.has(plate.id) || model.submitting || model.terminal) return;
    clearFreshFailure();
    const before = pose.flipped;
    pose.flipped = !pose.flipped;
    record("plate_flip", {plate_id: plate.id, from_flipped: before, to_flipped: pose.flipped});
    model.helpers.setReadout(pose.flipped ? "ACETATE REVERSED" : "ACETATE FACE UP", "idle");
    updateInterface();
  }

  function resetPlate() {
    const plate = activePlate();
    if (!plate || model.locked.has(plate.id) || model.submitting || model.terminal) return;
    clearFreshFailure();
    const before = poseClaim(model.poses[plate.id]);
    model.poses[plate.id] = clonePose(plate.initial_pose);
    record("plate_reset", {plate_id: plate.id, before_pose: before, after_pose: poseClaim(model.poses[plate.id])});
    model.helpers.setReadout("PLATE RETURNED TO THE BINDER", "idle");
    updateInterface();
  }

  function seatPlate() {
    const plate = activePlate(), pose = activePose();
    if (!plate || !pose || model.locked.has(plate.id) || model.submitting || model.terminal) return;
    clearFreshFailure();
    const before = poseClaim(pose);
    const error = maxAnchorError(plate, pose);
    const accepted = error <= Number(model.state.requirements.snap_tolerance_px);
    if (accepted) {
      model.poses[plate.id] = snapTranslation(plate, pose);
      model.locked.add(plate.id);
    } else {
      model.misseatCount += 1;
      const stage = document.querySelector(".bomb-canvas-shell");
      stage?.classList.remove("is-miss"); void stage?.offsetWidth; stage?.classList.add("is-miss");
    }
    record("plate_lock", {plate_id: plate.id, before_pose: before, accepted, max_error: round(error), after_pose: poseClaim(model.poses[plate.id])});
    if (accepted) {
      model.helpers.setReadout(model.locked.size === model.state.plates.length ? "ALL PLATES SEATED · FIND THE ONLY FULL APERTURE" : `${plate.label} PLATE SEATED`, "passed");
      const next = model.state.plates.find((item) => !model.locked.has(item.id));
      if (next) {
        model.selectedPlateId = next.id;
        record("plate_select", {plate_id: next.id, reason: "binder_advance"});
      }
    } else {
      model.helpers.setReadout("KEYHOLES MISS THE PINS · DRAG / ROTATE / FLIP AND TRY AGAIN", "error");
    }
    updateInterface();
  }

  function selectWire(point) {
    if (model.locked.size !== model.state.plates.length || model.submitting || model.terminal) return;
    const candidates = model.state.wires
      .map((wire) => ({wire, distance: Math.abs(point.y - Number(wire.y))}))
      .filter((item) => item.distance <= 18 && point.x >= 82 && point.x <= 660)
      .sort((a, b) => a.distance - b.distance);
    if (!candidates.length) return;
    clearFreshFailure();
    model.selectedWireId = candidates[0].wire.id;
    record("wire_select", {wire_id: model.selectedWireId, point: [round(point.x), round(point.y)]});
    model.helpers.setReadout("WIRE SELECTED · CUTTING IS IRREVERSIBLE", "pending");
    updateInterface();
  }

  async function submit(completed) {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    const helpers = model.helpers;
    if (completed) {
      model.cutCount += 1;
      record("cut", {wire_id: model.selectedWireId, cut_count: model.cutCount});
      helpers.setReadout("CUT COMMITTED · VERIFYING PLATE REGISTRATION…", "pending");
    }
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      completed: Boolean(completed),
      locked_plate_ids: [...model.locked].sort(),
      plate_poses: Object.fromEntries(Object.entries(model.poses).map(([id, pose]) => [id, poseClaim(pose)])),
      selected_wire_id: model.selectedWireId,
      cut_count: model.cutCount,
      misseat_count: model.misseatCount,
    };
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload)});
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".bomb-manual-captcha")?.insertAdjacentHTML("beforeend", '<div class="bomb-terminal"><span>ACETATE REGISTRATION VERIFIED</span><strong>PASS</strong><i>DEVICE SAFE</i></div>');
        helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await render(outcome.state, helpers, {freshFailure: true});
        helpers.setReadout("FAIL · FRESH DEVICE ISSUED", "error");
      } else {
        model.submitting = false;
        helpers.setReadout("DEFUSAL VERDICT UNAVAILABLE", "error");
        updateInterface();
      }
    } catch (_error) {
      model.submitting = false;
      helpers.setReadout("DEFUSAL LINK LOST", "error");
      updateInterface();
    }
  }

  function bindCanvas() {
    const canvas = model.canvas;
    const pointerdown = (event) => {
      const plate = activePlate(), pose = activePose();
      if (!plate || !pose || model.locked.has(plate.id) || model.submitting || model.terminal || event.button !== 0) return;
      const point = canvasPoint(event);
      if (!pointInPlate(point, plate, pose)) return;
      clearFreshFailure();
      event.preventDefault();
      model.drag = {plateId: plate.id, pointerId: event.pointerId, start: point, origin: {x: pose.x, y: pose.y}, last: point};
      record("drag_start", {plate_id: plate.id, point: [round(point.x), round(point.y)], pose: poseClaim(pose)});
      try { canvas.setPointerCapture(event.pointerId); } catch (_error) { /* best effort */ }
    };
    const pointermove = (event) => {
      if (!model.drag || event.pointerId !== model.drag.pointerId) return;
      const point = canvasPoint(event), pose = model.poses[model.drag.plateId];
      pose.x = Math.max(110, Math.min(840, model.drag.origin.x + point.x - model.drag.start.x));
      pose.y = Math.max(70, Math.min(430, model.drag.origin.y + point.y - model.drag.start.y));
      if (Math.hypot(point.x - model.drag.last.x, point.y - model.drag.last.y) >= 5) {
        model.drag.last = point;
        record("drag_sample", {plate_id: model.drag.plateId, point: [round(point.x), round(point.y)], pose: poseClaim(pose)});
      }
      drawScene();
    };
    const pointerup = (event) => {
      if (!model.drag || event.pointerId !== model.drag.pointerId) return;
      const point = canvasPoint(event), drag = model.drag, pose = model.poses[drag.plateId];
      record("drag_end", {plate_id: drag.plateId, point: [round(point.x), round(point.y)], pose: poseClaim(pose)});
      model.drag = null;
      model.suppressClickUntil = performance.now() + 180;
      try { canvas.releasePointerCapture(event.pointerId); } catch (_error) { /* best effort */ }
      model.helpers.setReadout("PLATE MOVED · ALIGN ALL THREE KEYHOLES", "idle");
      updateInterface();
    };
    const click = (event) => { if (performance.now() >= model.suppressClickUntil) selectWire(canvasPoint(event)); };
    canvas.addEventListener("pointerdown", pointerdown);
    canvas.addEventListener("pointermove", pointermove);
    canvas.addEventListener("pointerup", pointerup);
    canvas.addEventListener("pointercancel", pointerup);
    canvas.addEventListener("click", click);
    return () => {
      canvas.removeEventListener("pointerdown", pointerdown); canvas.removeEventListener("pointermove", pointermove);
      canvas.removeEventListener("pointerup", pointerup); canvas.removeEventListener("pointercancel", pointerup); canvas.removeEventListener("click", click);
    };
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "bomb-manual-from-hell";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {
      state, helpers, startedAt: performance.now(), events: [],
      poses: Object.fromEntries(state.plates.map((plate) => [plate.id, clonePose(plate.initial_pose)])),
      locked: new Set(), selectedPlateId: state.plates[0]?.id || null, selectedWireId: null,
      drag: null, suppressClickUntil: 0, misseatCount: 0, cutCount: 0,
      submitting: false, terminal: false, canvas: null, context: null,
    };
    window.bombManualAcetateModel = model;
    helpers.app.innerHTML = `
      <section class="bomb-manual-captcha" data-challenge-id="${clean(state.challenge_id)}" ${options.freshFailure ? 'data-fresh-failure="true"' : ""}>
        ${options.freshFailure ? '<div class="bomb-fresh-stamp"><b>FAIL</b><span>FRESH DEVICE / NEW PLATES</span></div>' : ""}
        <header class="bomb-head"><div><span>DEFUSAL ARCHIVE / ACETATE EDITION</span><h1>${clean(state.prompt)}</h1></div><div class="bomb-clock"><i></i><b>DEVICE ARMED</b><span>NO TEXT FORMULAS · TRUST THE KEYHOLES</span></div></header>
        <main class="bomb-workspace">
          <section class="bomb-canvas-shell"><canvas id="bomb-acetate-canvas" width="${Number(state.stage.width)}" height="${Number(state.stage.height)}" aria-label="bomb and transparent manual plate workbench"></canvas><div class="bomb-canvas-caption"><span>DRAG THE ACTIVE PLATE · ROTATE / FLIP IN THE BINDER</span><b>THE ${state.plates.length} APERTURE SETS SHARE EXACTLY ONE WIRE</b></div></section>
          <aside class="bomb-binder">
            <header><span>TRANSPARENT MANUAL</span><b>3 LEAVES</b></header>
            <div class="bomb-plate-list">${state.plates.map((plate, index) => `<button type="button" class="bomb-plate-card" data-plate-id="${clean(plate.id)}" data-selected="${index === 0 ? "true" : "false"}" data-locked="false" style="--plate:${clean(plate.color)}"><i>${String(index + 1).padStart(2, "0")}</i><span><b>${clean(plate.label)}</b><small>${plate.anchors.length} KEYHOLES / ${plate.apertures.length} WINDOWS</small></span><em>OPEN</em></button>`).join("")}</div>
            <section class="bomb-transform-panel"><div class="bomb-active-plate"><b>${clean(state.plates[0].label)}</b><span>FACE · 000°</span></div><div class="bomb-transform-controls"><button type="button" data-transform="rotate-left">↶ ${Number(state.requirements.rotation_step_deg)}°</button><button type="button" data-transform="flip">⇋ FLIP</button><button type="button" data-transform="rotate-right">${Number(state.requirements.rotation_step_deg)}° ↷</button><button type="button" data-transform="reset">RETURN</button></div><button type="button" id="bomb-seat-plate">SEAT KEYHOLES ON PINS</button></section>
            <section class="bomb-pictogram"><div><b>1</b><span>ALIGN<br>KEYHOLES</span></div><i>→</i><div><b>2</b><span>STACK<br>${state.plates.length} PLATES</span></div><i>→</i><div><b>3</b><span>CUT<br>OPEN WIRE</span></div></section>
            <div class="bomb-status-count"><span>PLATES SEATED</span><b>0 / ${state.plates.length}</b></div>
          </aside>
        </main>
        <footer class="bomb-foot"><button type="button" id="bomb-reissue">REISSUE DEVICE</button><div><span class="bomb-selected-wire">SEAT ALL ${state.plates.length} PLATES</span><div class="readout" data-status="idle">SELECT A PLATE AND ALIGN ITS THREE KEYHOLES</div></div><button type="button" class="bomb-cut-button" disabled>${clean(state.submit_label)}</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    model.canvas = document.getElementById("bomb-acetate-canvas");
    model.context = model.canvas.getContext("2d");
    const unbindCanvas = bindCanvas();
    document.querySelectorAll(".bomb-plate-card").forEach((button) => button.addEventListener("click", () => selectPlate(button.dataset.plateId)));
    document.querySelector('[data-transform="rotate-left"]')?.addEventListener("click", () => rotatePlate(-1));
    document.querySelector('[data-transform="rotate-right"]')?.addEventListener("click", () => rotatePlate(1));
    document.querySelector('[data-transform="flip"]')?.addEventListener("click", flipPlate);
    document.querySelector('[data-transform="reset"]')?.addEventListener("click", resetPlate);
    document.getElementById("bomb-seat-plate")?.addEventListener("click", seatPlate);
    document.querySelector(".bomb-cut-button")?.addEventListener("click", () => submit(true));
    document.getElementById("bomb-reissue")?.addEventListener("click", () => submit(false));
    helpers.installCheatPanel();
    updateInterface();
    activeCleanup = unbindCanvas;
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.bomb_manual_from_hell = {rootSelector: ".bomb-manual-captcha", render};
})();
