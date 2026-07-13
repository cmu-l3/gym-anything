(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;

  const clamp = (value, low, high) => Math.max(low, Math.min(high, value));
  const round2 = (value) => Math.round(Number(value) * 100) / 100;
  const point = (value) => ({x: round2(value.x), y: round2(value.y)});

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function pushEvent(event) {
    const item = {seq: model.events.length + 1, t_ms: eventTime(), ...event};
    model.events.push(item);
    return item;
  }

  function deriveContract(challengeId, objects, initial) {
    const far = objects.map((item, index) => ({item, index})).filter(({item}) => Math.abs(Number(item.x) - Number(initial.x)) > 1080 || Math.abs(Number(item.y) - Number(initial.y)) > 670);
    const chosen = far[Number.parseInt(challengeId.slice(0, 6), 16) % far.length];
    const periodMs = 5880 + (Number.parseInt(challengeId.slice(6, 8), 16) % 7) * 140;
    return {
      targetIndex: chosen.index,
      targetId: chosen.item.id,
      periodMs,
      windowMs: 1980,
      offsetMs: Number.parseInt(challengeId.slice(8, 12), 16) % periodMs,
    };
  }

  function cameraBounds(zoom = model.zoom) {
    const halfWidth = Number(model.state.viewport.width) / (2 * zoom);
    const halfHeight = Number(model.state.viewport.height) / (2 * zoom);
    return {
      minX: halfWidth,
      maxX: Number(model.state.world.width) - halfWidth,
      minY: halfHeight,
      maxY: Number(model.state.world.height) - halfHeight,
    };
  }

  function clampedCamera(value, zoom = model.zoom) {
    const bounds = cameraBounds(zoom);
    return {
      x: round2(clamp(value.x, bounds.minX, bounds.maxX)),
      y: round2(clamp(value.y, bounds.minY, bounds.maxY)),
    };
  }

  function cameraClaim() {
    return {x: round2(model.camera.x), y: round2(model.camera.y), zoom: round2(model.zoom), focus: round2(model.focus)};
  }

  function sectorAt(camera = model.camera) {
    const columns = Number(model.state.world.sector_columns);
    const rows = Number(model.state.world.sector_rows);
    const column = clamp(Math.floor(camera.x / (Number(model.state.world.width) / columns)), 0, columns - 1);
    const row = clamp(Math.floor(camera.y / (Number(model.state.world.height) / rows)), 0, rows - 1);
    return `${column}:${row}`;
  }

  function visitSector() {
    const sector = sectorAt();
    if (!model.visited.includes(sector)) model.visited.push(sector);
  }

  function targetPosition(item, timeMs) {
    const angle = (timeMs / Number(item.motion_period_ms) + Number(item.motion_phase)) * Math.PI * 2;
    return {
      x: Number(item.x) + Math.cos(angle) * Number(item.amp_x),
      y: Number(item.y) + Math.sin(angle * 1.17) * Number(item.amp_y),
    };
  }

  function phaseActive(timeMs) {
    return (timeMs + model.contract.offsetMs) % model.contract.periodMs < model.contract.windowMs;
  }

  function project(worldPoint) {
    return {
      x: Number(model.state.viewport.width) / 2 + (worldPoint.x - model.camera.x) * model.zoom,
      y: Number(model.state.viewport.height) / 2 + (worldPoint.y - model.camera.y) * model.zoom,
    };
  }

  function qualifiedAt(timeMs, camera = model.camera, zoom = model.zoom, focus = model.focus) {
    const target = model.state.objects[model.contract.targetIndex];
    const moving = targetPosition(target, timeMs);
    const projection = {
      x: Number(model.state.viewport.width) / 2 + (moving.x - camera.x) * zoom,
      y: Number(model.state.viewport.height) / 2 + (moving.y - camera.y) * zoom,
    };
    const qualifier = model.state.qualification;
    return phaseActive(timeMs)
      && zoom >= Number(qualifier.minimum_zoom)
      && zoom <= Number(qualifier.maximum_zoom)
      && Math.abs(focus - Number(target.depth)) <= Number(qualifier.focus_tolerance)
      && Math.hypot(projection.x - Number(model.state.viewport.width) / 2, projection.y - Number(model.state.viewport.height) / 2) <= Number(qualifier.reticle_radius);
  }

  function palette() {
    return {
      "night-survey": {sky: "#07171b", haze: "#18383b", ground: "#162b2b", line: "#4c7773", warm: "#e9b85c", cold: "#65f3f1"},
      "oxide-dusk": {sky: "#1d1114", haze: "#492829", ground: "#2c2020", line: "#8f5f4d", warm: "#ffc56d", cold: "#72e5e0"},
      "polar-archive": {sky: "#0d1821", haze: "#263d4c", ground: "#1b2b33", line: "#668ca0", warm: "#f5c873", cold: "#7df4ff"},
      "violet-hour": {sky: "#161224", haze: "#39304d", ground: "#29253c", line: "#766f9a", warm: "#f4bd74", cold: "#79f1ec"},
    }[model.state.palette] || {sky: "#07171b", haze: "#18383b", ground: "#162b2b", line: "#4c7773", warm: "#e9b85c", cold: "#65f3f1"};
  }

  function visible(screen, margin = 90) {
    return screen.x >= -margin && screen.y >= -margin && screen.x <= Number(model.state.viewport.width) + margin && screen.y <= Number(model.state.viewport.height) + margin;
  }

  function drawBackdrop(context, colors) {
    const width = Number(model.state.viewport.width);
    const height = Number(model.state.viewport.height);
    const gradient = context.createLinearGradient(0, 0, 0, height);
    gradient.addColorStop(0, colors.sky);
    gradient.addColorStop(0.55, colors.haze);
    gradient.addColorStop(1, colors.ground);
    context.fillStyle = gradient;
    context.fillRect(0, 0, width, height);
    context.fillStyle = "rgba(245,239,206,.06)";
    for (let index = 0; index < 95; index += 1) {
      const x = (Math.sin(index * 91.31 + model.camera.x * .001) + 1) * width / 2;
      const y = (Math.sin(index * 37.77 + model.camera.y * .001) + 1) * height * .44;
      context.fillRect(x, y, index % 9 === 0 ? 2 : 1, 1);
    }
  }

  function drawRoutes(context, colors) {
    context.save();
    model.state.routes.forEach((route) => {
      const start = project({x: Number(route.x1), y: Number(route.y1)});
      const end = project({x: Number(route.x2), y: Number(route.y2)});
      if (!visible(start, 500) && !visible(end, 500)) return;
      const center = {x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + Number(route.bend) * model.zoom};
      context.beginPath(); context.moveTo(start.x, start.y); context.quadraticCurveTo(center.x, center.y, end.x, end.y);
      context.strokeStyle = route.tone % 2 ? "rgba(238,186,92,.15)" : `${colors.line}55`;
      context.lineWidth = Math.max(1, model.zoom * 1.2);
      context.setLineDash(route.tone % 3 ? [8, 11] : [2, 8]);
      context.stroke();
    });
    context.setLineDash([]);
    context.restore();
  }

  function drawLandmarkShape(context, item, screen, colors) {
    const size = Number(item.size) * model.zoom;
    const soft = Math.min(7, Math.abs(Number(item.depth) - model.focus) / 8);
    const copies = soft > 1 ? [-soft, 0, soft] : [0];
    copies.forEach((offset, index) => {
      context.save();
      context.translate(screen.x + offset, screen.y + (index - 1) * soft * .35);
      context.globalAlpha = copies.length > 1 ? .20 : .72;
      context.fillStyle = item.tone % 2 ? colors.line : "#9a8064";
      context.strokeStyle = "rgba(233,220,184,.32)";
      context.lineWidth = Math.max(1, model.zoom);
      context.beginPath();
      if (item.kind === "mesa") {
        context.moveTo(-size, size * .35); context.lineTo(-size * .55, -size * .35); context.lineTo(size * .45, -size * .48); context.lineTo(size, size * .35); context.closePath();
      } else if (item.kind === "spire") {
        context.moveTo(-size * .3, size * .55); context.lineTo(0, -size); context.lineTo(size * .32, size * .55); context.closePath();
      } else if (item.kind === "dish") {
        context.arc(0, 0, size * .65, 0.1, Math.PI - .1); context.lineTo(0, size * .12); context.closePath();
      } else if (item.kind === "arch") {
        context.arc(0, 0, size * .65, Math.PI, 0); context.lineTo(size * .35, size * .35); context.arc(0, 0, size * .34, 0, Math.PI, true); context.closePath();
      } else if (item.kind === "relay") {
        context.rect(-size * .13, -size * .7, size * .26, size * 1.3); context.moveTo(-size * .5, -size * .35); context.lineTo(size * .5, -size * .35);
      } else {
        context.moveTo(-size * .45, size * .6); context.quadraticCurveTo(-size * .2, -size, 0, size * .55); context.quadraticCurveTo(size * .22, -size * .8, size * .42, size * .6);
      }
      context.fill(); context.stroke();
      context.restore();
    });
  }

  function drawLandmarks(context, colors) {
    model.state.landmarks.forEach((item) => {
      const screen = project({x: Number(item.x), y: Number(item.y)});
      if (visible(screen, Number(item.size) * model.zoom + 30)) drawLandmarkShape(context, item, screen, colors);
    });
  }

  function drawSpecimenCore(context, item, screen, timeMs, isTarget, colors) {
    const scale = model.zoom;
    const size = Number(item.vane_span) * scale;
    const focusError = Math.abs(Number(item.depth) - model.focus);
    const soft = Math.min(9, focusError / 4.8);
    const localFlare = (timeMs / 4300 + Number(item.flare_phase)) % 1 < .18;
    const unique = isTarget && phaseActive(timeMs) && model.zoom >= 1.05 && focusError <= 18;
    const flutter = Math.sin(timeMs / 230 + Number(item.motion_phase) * 10) * .38;
    const vaneAngle = unique ? Math.PI / 4 : flutter;
    const copies = soft > .8 ? [-soft, 0, soft] : [0];
    copies.forEach((offset, copyIndex) => {
      context.save();
      context.translate(screen.x + offset, screen.y + (copyIndex - 1) * soft * .42);
      context.globalAlpha = copies.length > 1 ? .23 : 1;
      context.strokeStyle = unique ? colors.cold : colors.warm;
      context.fillStyle = item.tone % 2 ? "#e5d7b3" : "#d8bd82";
      context.lineWidth = Math.max(1.2, 1.3 * scale);
      for (const side of [-1, 1]) {
        context.save();
        context.rotate(side * vaneAngle);
        context.beginPath();
        context.moveTo(side * 2.2 * scale, 0);
        context.lineTo(side * size, -size * .42);
        context.lineTo(side * size * .72, size * .42);
        context.closePath(); context.fill(); context.stroke();
        context.restore();
      }
      context.fillStyle = "#151b1d";
      context.beginPath(); context.ellipse(0, 0, 3.2 * scale, 6.2 * scale, 0, 0, Math.PI * 2); context.fill();
      context.strokeStyle = unique ? colors.cold : "rgba(255,222,150,.72)";
      context.beginPath(); context.moveTo(0, -5 * scale); context.lineTo(0, -10 * scale); context.stroke();
      if (!unique && localFlare) {
        context.strokeStyle = "rgba(255,190,90,.48)";
        context.beginPath(); context.ellipse(0, 0, size * 1.25, size * .74, 0, 0, Math.PI * 2); context.stroke();
      }
      context.restore();
    });
    if (unique) {
      const phase = ((timeMs + model.contract.offsetMs) % model.contract.periodMs) / model.contract.windowMs;
      context.save();
      context.translate(screen.x, screen.y);
      context.strokeStyle = colors.cold;
      context.lineWidth = Math.max(2, model.zoom * 1.6);
      context.globalAlpha = .95;
      for (const ring of [1, 1.58]) {
        const radius = size * (ring + phase * .72);
        context.beginPath(); context.arc(0, 0, radius, 0, Math.PI * 2); context.stroke();
      }
      context.fillStyle = "rgba(180,255,246,.9)";
      context.beginPath(); context.arc(0, 0, 2.5 * model.zoom, 0, Math.PI * 2); context.fill();
      context.restore();
    }
  }

  function drawSpecimens(context, colors, timeMs) {
    model.state.objects.forEach((item, index) => {
      const worldPosition = targetPosition(item, timeMs);
      const screen = project(worldPosition);
      if (visible(screen, 70)) drawSpecimenCore(context, item, screen, timeMs, index === model.contract.targetIndex, colors);
    });
  }

  function drawReticle(context, colors) {
    const x = Number(model.state.viewport.width) / 2;
    const y = Number(model.state.viewport.height) / 2;
    context.save();
    context.strokeStyle = model.holding ? colors.warm : "rgba(233,239,219,.72)";
    context.lineWidth = model.holding ? 3 : 1.3;
    context.beginPath(); context.arc(x, y, Number(model.state.qualification.reticle_radius), 0, Math.PI * 2); context.stroke();
    context.beginPath(); context.moveTo(x - 58, y); context.lineTo(x - 28, y); context.moveTo(x + 28, y); context.lineTo(x + 58, y); context.moveTo(x, y - 58); context.lineTo(x, y - 28); context.moveTo(x, y + 28); context.lineTo(x, y + 58); context.stroke();
    context.restore();
  }

  function drawScene() {
    if (!model) return;
    const canvas = document.getElementById("panorama-canvas");
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;
    const colors = palette();
    const timeMs = performance.now() - model.startedAt;
    drawBackdrop(context, colors);
    drawRoutes(context, colors);
    drawLandmarks(context, colors);
    drawSpecimens(context, colors, timeMs);
    drawReticle(context, colors);
  }

  function cameraViewportOnMap() {
    const width = Number(model.state.world.width);
    const height = Number(model.state.world.height);
    const halfWidth = Number(model.state.viewport.width) / (2 * model.zoom);
    const halfHeight = Number(model.state.viewport.height) / (2 * model.zoom);
    return {
      left: (model.camera.x - halfWidth) / width * 100,
      top: (model.camera.y - halfHeight) / height * 100,
      width: halfWidth * 2 / width * 100,
      height: halfHeight * 2 / height * 100,
    };
  }

  function updateInterface() {
    if (!model) return;
    const root = document.querySelector(".impossible-panorama");
    if (!root) return;
    root.dataset.cameraX = String(round2(model.camera.x));
    root.dataset.cameraY = String(round2(model.camera.y));
    root.dataset.zoom = String(round2(model.zoom));
    root.dataset.focus = String(round2(model.focus));
    root.dataset.visitedCount = String(model.visited.length);
    root.dataset.holding = String(model.holding);
    document.querySelectorAll("[data-sector]").forEach((node) => { node.dataset.visited = String(model.visited.includes(node.dataset.sector)); });
    const mapCamera = document.getElementById("panorama-map-camera");
    if (mapCamera) {
      const frame = cameraViewportOnMap();
      mapCamera.style.left = `${frame.left}%`; mapCamera.style.top = `${frame.top}%`; mapCamera.style.width = `${frame.width}%`; mapCamera.style.height = `${frame.height}%`;
    }
    const zoomValue = document.getElementById("panorama-zoom-value");
    const focusValue = document.getElementById("panorama-focus-value");
    if (zoomValue) zoomValue.textContent = `${model.zoom.toFixed(2)}×`;
    if (focusValue) focusValue.textContent = `${Math.round(model.focus).toString().padStart(2, "0")}`;
    const zoomSlider = document.getElementById("panorama-zoom-slider");
    const focusSlider = document.getElementById("panorama-focus-slider");
    if (zoomSlider && document.activeElement !== zoomSlider) zoomSlider.value = String(model.zoom);
    if (focusSlider && document.activeElement !== focusSlider) focusSlider.value = String(model.focus);
    const shutter = document.getElementById("panorama-shutter");
    const submit = document.getElementById("panorama-submit");
    if (shutter) shutter.disabled = model.submitting || model.completed;
    if (submit) submit.disabled = model.submitting || model.completed || model.holding || model.panning;
  }

  function canvasPoint(event) {
    const canvas = document.getElementById("panorama-canvas");
    const rect = canvas.getBoundingClientRect();
    return {
      x: round2((event.clientX - rect.left) / rect.width * canvas.width),
      y: round2((event.clientY - rect.top) / rect.height * canvas.height),
    };
  }

  function panStart(event) {
    if (!model || model.submitting || model.completed || model.holding || model.panning) return;
    model.panning = true;
    model.pointer = canvasPoint(event);
    pushEvent({type: "pan_start", pointer: point(model.pointer), camera: cameraClaim()});
    event.currentTarget.setPointerCapture?.(event.pointerId);
    model.helpers.setReadout("PANORAMA DRIVE ENGAGED", "idle");
    updateInterface();
  }

  function panMove(event) {
    if (!model?.panning || model.holding || model.submitting || model.completed) return;
    const nextPointer = canvasPoint(event);
    const before = point(model.camera);
    const next = clampedCamera({x: model.camera.x - (nextPointer.x - model.pointer.x) / model.zoom, y: model.camera.y - (nextPointer.y - model.pointer.y) / model.zoom});
    model.panTravel += Math.hypot(next.x - model.camera.x, next.y - model.camera.y);
    model.camera = next;
    model.pointer = nextPointer;
    model.panMoves += 1;
    visitSector();
    pushEvent({type: "pan_move", pointer: point(nextPointer), from: before, to: point(next)});
    updateInterface();
  }

  function panEnd(event) {
    if (!model?.panning) return;
    const current = canvasPoint(event);
    pushEvent({type: "pan_end", pointer: point(current), camera: cameraClaim()});
    model.panning = false;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    model.helpers.setReadout("PANORAMA DRIVE PARKED", "idle");
    updateInterface();
  }

  function nudge(direction) {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    const before = point(model.camera);
    const distance = Number(model.state.controls.pan_nudge_px) / model.zoom;
    const delta = {left: [-distance, 0], right: [distance, 0], up: [0, -distance], down: [0, distance]}[direction];
    const next = clampedCamera({x: model.camera.x + delta[0], y: model.camera.y + delta[1]});
    model.panTravel += Math.hypot(next.x - model.camera.x, next.y - model.camera.y);
    model.camera = next;
    model.panMoves += 1;
    visitSector();
    pushEvent({type: "pan_nudge", direction, from: before, to: point(next)});
    model.helpers.setReadout(`PAN ${direction.toUpperCase()}`, "idle");
    updateInterface();
  }

  function setZoom(value, source) {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    const before = model.zoom;
    model.zoom = round2(clamp(Number(value), Number(model.state.controls.zoom_min), Number(model.state.controls.zoom_max)));
    model.camera = clampedCamera(model.camera, model.zoom);
    model.zoomChanges += 1;
    pushEvent({type: "zoom", source, from: round2(before), to: round2(model.zoom), camera_after: point(model.camera)});
    model.helpers.setReadout("OPTICAL SCALE CHANGED", "idle");
    updateInterface();
  }

  function setFocus(value) {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    const before = model.focus;
    model.focus = round2(clamp(Number(value), Number(model.state.controls.focus_min), Number(model.state.controls.focus_max)));
    model.focusChanges += 1;
    pushEvent({type: "focus", source: "slider", from: round2(before), to: round2(model.focus)});
    model.helpers.setReadout("FOCAL PLANE SHIFTED", "idle");
    updateInterface();
  }

  function resetScene() {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    const initial = model.state.initial_camera;
    model.camera = {x: Number(initial.x), y: Number(initial.y)};
    model.zoom = Number(initial.zoom);
    model.focus = Number(initial.focus);
    model.visited = [sectorAt(model.camera)];
    model.panMoves = 0; model.panTravel = 0; model.zoomChanges = 0; model.focusChanges = 0;
    model.shutterAttempts = 0; model.validHolds = 0; model.resetCount += 1;
    pushEvent({type: "reset", camera_after: cameraClaim()});
    model.helpers.setReadout("PLATE RESET / EVENT LOOP CONTINUES", "idle");
    updateInterface();
  }

  function startShutter(event) {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    event?.preventDefault?.();
    model.holding = true;
    const start = pushEvent({type: "shutter_start", camera: cameraClaim()});
    model.holdStart = start.t_ms;
    model.holdCamera = {...model.camera};
    model.holdZoom = model.zoom;
    model.holdFocus = model.focus;
    model.holdSamples = [];
    model.shutterAttempts += 1;
    model.sampleTimer = window.setInterval(() => {
      if (!model?.holding) return;
      const sample = pushEvent({type: "shutter_sample", camera: cameraClaim()});
      model.holdSamples.push(sample.t_ms);
    }, 90);
    model.helpers.setReadout("EXPOSING — HOLD STEADY", "idle");
    updateInterface();
  }

  function endShutter(event) {
    if (!model?.holding) return;
    event?.preventDefault?.();
    window.clearInterval(model.sampleTimer);
    model.sampleTimer = null;
    const end = pushEvent({type: "shutter_end", camera: cameraClaim()});
    const maximumGap = Number(model.state.qualification.maximum_sample_gap_ms);
    const gapOkay = model.holdSamples.length > 0 && model.holdSamples[0] - model.holdStart <= maximumGap && end.t_ms - model.holdSamples[model.holdSamples.length - 1] <= maximumGap;
    const stable = model.camera.x === model.holdCamera.x && model.camera.y === model.holdCamera.y && model.zoom === model.holdZoom && model.focus === model.holdFocus;
    const allTimes = [model.holdStart, ...model.holdSamples, end.t_ms];
    const valid = end.t_ms - model.holdStart >= Number(model.state.qualification.minimum_hold_ms)
      && model.holdSamples.length >= Number(model.state.qualification.minimum_hold_samples)
      && gapOkay && stable && allTimes.every((timeMs) => qualifiedAt(timeMs, model.holdCamera, model.holdZoom, model.holdFocus));
    if (valid) model.validHolds += 1;
    model.holding = false;
    model.helpers.setReadout(valid ? "PLATE HOLDS A COHERENT EVENT" : "EXPOSURE UNRESOLVED", valid ? "idle" : "error");
    updateInterface();
  }

  function finalState() {
    return {
      camera: cameraClaim(),
      visited_sectors: [...model.visited],
      pan_moves: model.panMoves,
      pan_travel: round2(model.panTravel),
      zoom_changes: model.zoomChanges,
      focus_changes: model.focusChanges,
      shutter_attempts: model.shutterAttempts,
      valid_holds: model.validHolds,
      reset_count: model.resetCount,
    };
  }

  function showVerdict(kind) {
    const root = document.querySelector(".impossible-panorama");
    const verdict = root?.querySelector(".panorama-verdict");
    if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass");
    root.classList.toggle("is-failed", kind === "fail");
    verdict.innerHTML = `<b>${kind === "pass" ? "PASS" : "FAIL"}</b><span>${kind === "pass" ? "IMPOSSIBLE EVENT DEVELOPED" : "EMPTY PLATE / NEW PANORAMA ISSUED"}</span>`;
    if (kind === "fail") {
      const timer = window.setTimeout(() => root.classList.remove("is-failed"), 1600);
      model.timers.add(timer);
    }
  }

  async function submitPlate() {
    if (!model || model.panning || model.holding || model.submitting || model.completed) return;
    const current = model;
    pushEvent({type: "verify"});
    current.submitting = true;
    updateInterface();
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({mechanic_id: current.state.mechanic_id, task_id: current.state.task_id, challenge_id: current.state.challenge_id, completed: true, events: current.events, final_state: finalState()}),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        current.completed = true;
        current.helpers.setReadout("PASS", "passed");
        showVerdict("pass");
        updateInterface();
      } else if (outcome.passed === false) {
        const helpers = current.helpers;
        if (outcome.state) await render(outcome.state, helpers, {freshFailure: true});
        model.helpers.setReadout("FAIL", "error");
        showVerdict("fail");
      }
    } catch (_error) {
      if (model === current) {
        current.submitting = false;
        current.helpers.setReadout("DARKROOM LINK LOST", "error");
        updateInterface();
      }
    }
  }

  function installDeveloperReveal() {
    const form = document.getElementById("cheat-form");
    const input = document.getElementById("cheat-password");
    const output = document.getElementById("cheat-output");
    if (!form || !input || !output) return;
    form.addEventListener("submit", async (event) => {
      event.preventDefault(); output.textContent = "";
      try {
        const response = await fetch("/cheat", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({password: input.value})});
        if (!response.ok) { output.textContent = response.status === 404 ? "Disabled." : "Denied."; return; }
        const data = await response.json();
        output.textContent = `Specimen ${data.target_id} · depth ${data.solution?.target_depth} · loop ${data.event_contract?.period_ms}ms`;
      } catch (_error) { output.textContent = "Unavailable."; }
    });
  }

  function animate() {
    if (!model) return;
    drawScene();
    model.animationTimer = window.setInterval(drawScene, 50);
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "impossible-panorama";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const initial = state.initial_camera;
    model = {
      state, helpers,
      contract: deriveContract(state.challenge_id, state.objects, initial),
      camera: {x: Number(initial.x), y: Number(initial.y)},
      zoom: Number(initial.zoom), focus: Number(initial.focus),
      pointer: {x: 0, y: 0}, panning: false, holding: false,
      events: [], visited: [], panMoves: 0, panTravel: 0,
      zoomChanges: 0, focusChanges: 0, shutterAttempts: 0, validHolds: 0, resetCount: 0,
      holdSamples: [], holdStart: 0, holdCamera: null, holdZoom: 0, holdFocus: 0,
      sampleTimer: null, animationTimer: null, timers: new Set(), submitting: false, completed: false,
      startedAt: performance.now(), keyHandler: null,
    };
    model.visited = [sectorAt(model.camera)];
    const sectors = Array.from({length: Number(state.world.sector_rows)}, (_, row) => Array.from({length: Number(state.world.sector_columns)}, (_unused, column) => `<i data-sector="${column}:${row}" data-visited="false"></i>`).join("")).join("");
    helpers.app.innerHTML = `
      <section class="impossible-panorama palette-${helpers.text(state.palette)}" data-fresh-failure="${options.freshFailure ? "true" : "false"}" data-visited-count="1" tabindex="0">
        <div class="panorama-verdict" aria-live="assertive"></div>
        <header class="panorama-head">
          <div><span>DEEP-FIELD CARTOGRAPHY OFFICE / ${helpers.text(state.plate_number)}</span><h1>${helpers.text(state.prompt)}</h1></div>
          <div class="panorama-seal"><i>⊕</i><span>ACTIVE<br><b>PLATE</b></span></div>
        </header>
        <main class="panorama-workbench">
          <section class="panorama-stage">
            <canvas id="panorama-canvas" width="${Number(state.viewport.width)}" height="${Number(state.viewport.height)}" aria-label="interactive deep-field panorama"></canvas>
            <div class="panorama-stage-rail"><span>DRAG FIELD TO PAN</span><b>RETICLE / OPTICAL PLANE / REPEATING EVENT LOOP</b></div>
          </section>
          <aside class="panorama-console">
            <section class="panorama-map"><header><span>SEARCH LOG</span><b><em id="panorama-sector-count">${Number(state.world.sector_columns) * Number(state.world.sector_rows)}</em> SECTORS</b></header><div class="panorama-map-grid">${sectors}<strong id="panorama-map-camera"></strong></div></section>
            <section class="panorama-pan-pad" aria-label="pan controls"><span>PAN DRIVE</span><button type="button" data-pan="up">▲</button><button type="button" data-pan="left">◀</button><i>⊕</i><button type="button" data-pan="right">▶</button><button type="button" data-pan="down">▼</button></section>
            <section class="panorama-optic"><div><span>OPTICAL SCALE</span><b id="panorama-zoom-value">${Number(initial.zoom).toFixed(2)}×</b></div><div class="zoom-controls"><button type="button" id="panorama-zoom-out">−</button><input id="panorama-zoom-slider" type="range" min="${Number(state.controls.zoom_min)}" max="${Number(state.controls.zoom_max)}" step="${Number(state.controls.zoom_step)}" value="${Number(initial.zoom)}" aria-label="optical zoom"><button type="button" id="panorama-zoom-in">+</button></div></section>
            <section class="panorama-focus"><div><span>FOCAL PLANE</span><b id="panorama-focus-value">${Math.round(Number(initial.focus)).toString().padStart(2, "0")}</b></div><input id="panorama-focus-slider" type="range" min="${Number(state.controls.focus_min)}" max="${Number(state.controls.focus_max)}" step="${Number(state.controls.focus_step)}" value="${Number(initial.focus)}" aria-label="focal plane"><small>NEAR&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;FAR</small></section>
            <section class="panorama-exposure"><button type="button" id="panorama-shutter"><i></i><span>HOLD SHUTTER</span><b>STABLE INTERVAL</b></button><button type="button" id="panorama-reset">RESET OPTICS</button></section>
          </aside>
        </main>
        <footer class="panorama-foot"><div class="readout" data-status="idle">SCAN THE PLATE / EVENT LOOP ACTIVE</div><button type="button" id="panorama-submit">${helpers.text(state.submit_label || "DEVELOP PLATE")}</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    const canvas = document.getElementById("panorama-canvas");
    canvas.addEventListener("pointerdown", panStart);
    canvas.addEventListener("pointermove", panMove);
    canvas.addEventListener("pointerup", panEnd);
    canvas.addEventListener("pointercancel", panEnd);
    document.querySelectorAll("[data-pan]").forEach((button) => button.addEventListener("click", () => nudge(button.dataset.pan)));
    document.getElementById("panorama-zoom-in")?.addEventListener("click", () => setZoom(model.zoom + Number(state.controls.zoom_step), "button_in"));
    document.getElementById("panorama-zoom-out")?.addEventListener("click", () => setZoom(model.zoom - Number(state.controls.zoom_step), "button_out"));
    document.getElementById("panorama-zoom-slider")?.addEventListener("input", (event) => setZoom(event.currentTarget.value, "slider"));
    document.getElementById("panorama-focus-slider")?.addEventListener("input", (event) => setFocus(event.currentTarget.value));
    const shutter = document.getElementById("panorama-shutter");
    shutter?.addEventListener("pointerdown", startShutter);
    window.addEventListener("pointerup", endShutter);
    window.addEventListener("pointercancel", endShutter);
    document.getElementById("panorama-reset")?.addEventListener("click", resetScene);
    document.getElementById("panorama-submit")?.addEventListener("click", submitPlate);
    installDeveloperReveal();
    model.keyHandler = (event) => {
      if (["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key) && !["INPUT", "BUTTON"].includes(document.activeElement?.tagName)) {
        event.preventDefault(); nudge(event.key.replace("Arrow", "").toLowerCase());
      }
    };
    window.addEventListener("keydown", model.keyHandler);
    activeCleanup = () => {
      canvas.removeEventListener("pointerdown", panStart); canvas.removeEventListener("pointermove", panMove); canvas.removeEventListener("pointerup", panEnd); canvas.removeEventListener("pointercancel", panEnd);
      window.removeEventListener("pointerup", endShutter); window.removeEventListener("pointercancel", endShutter); window.removeEventListener("keydown", model?.keyHandler);
      window.clearInterval(model?.sampleTimer); window.clearInterval(model?.animationTimer); model?.timers.forEach((timer) => window.clearTimeout(timer));
    };
    updateInterface();
    animate();
    document.querySelector(".impossible-panorama")?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.impossible_panorama = {rootSelector: ".impossible-panorama", render};
})();
