(() => {
  "use strict";

  const model = {
    state: null,
    tileById: new Map(),
    slots: [],
    rotations: {},
    phases: {},
    selected: null,
    events: [],
    spatialTouched: new Set(),
    rotationTouched: new Set(),
    phaseTouched: new Set(),
    startedAt: 0,
    animationFrame: null,
    lastDrawAt: -1,
    dragged: null,
    dragSucceeded: false,
    phaseDrag: null,
    sync: null,
    syncTimer: null,
    busy: false,
    terminal: false,
    helpers: null,
  };

  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const mod = (value, modulus) => ((value % modulus) + modulus) % modulus;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function record(type, details = {}) {
    const event = {sequence: model.events.length + 1, type, ...details};
    model.events.push(event);
    return event;
  }

  function triangle(value, span) {
    const phase = mod(value, span * 2);
    return span - Math.abs(phase - span);
  }

  function field(x, y, time) {
    const scene = model.state.scene;
    const seed = Number(scene.field_seed);
    const target = scene.target;
    const targetX = mod((seed % 3000) + Math.floor(time * Number(target.speed_x_milli) / 1000), 3000);
    const targetY = triangle(mod(Math.floor(seed / 17), 6000) + Math.floor(time * Number(target.speed_y_milli) / 1000), 3000);
    const base = mod(x * 17 + y * 29 + Math.floor(time / 20) * 31 + seed, 4093);
    const pulse = Math.max(0, 1100 - Math.floor((Math.abs(x - targetX) + Math.abs(y - targetY)) / 2));
    return mod(base + pulse * 3, 8192);
  }

  function worldCoordinate(tile, rotation, localX, localY) {
    if (rotation === 180) {
      localX = 1000 - localX;
      localY = 1000 - localY;
    }
    return [Number(tile.source.column) * 1000 + localX, Number(tile.source.row) * 1000 + localY];
  }

  function continuity(sceneTick) {
    const samples = [220, 500, 780];
    const phaseMs = Number(model.state.scene.phase_tick_ms);
    let error = 0;
    for (let row = 0; row < 3; row += 1) {
      for (let column = 0; column < 2; column += 1) {
        const leftId = model.slots[row * 3 + column];
        const rightId = model.slots[row * 3 + column + 1];
        for (const localY of samples) {
          const [leftX, leftY] = worldCoordinate(model.tileById.get(leftId), model.rotations[leftId], 1000, localY);
          const [rightX, rightY] = worldCoordinate(model.tileById.get(rightId), model.rotations[rightId], 0, localY);
          error += Math.abs(
            field(leftX, leftY, sceneTick + model.phases[leftId] * phaseMs)
            - field(rightX, rightY, sceneTick + model.phases[rightId] * phaseMs)
          );
        }
      }
    }
    for (let row = 0; row < 2; row += 1) {
      for (let column = 0; column < 3; column += 1) {
        const topId = model.slots[row * 3 + column];
        const bottomId = model.slots[(row + 1) * 3 + column];
        for (const localX of samples) {
          const [topX, topY] = worldCoordinate(model.tileById.get(topId), model.rotations[topId], localX, 1000);
          const [bottomX, bottomY] = worldCoordinate(model.tileById.get(bottomId), model.rotations[bottomId], localX, 0);
          error += Math.abs(
            field(topX, topY, sceneTick + model.phases[topId] * phaseMs)
            - field(bottomX, bottomY, sceneTick + model.phases[bottomId] * phaseMs)
          );
        }
      }
    }
    return error;
  }

  function sceneErrors(sceneTick = Math.round(performance.now() - model.startedAt)) {
    let spatialError = 0;
    let rotationError = 0;
    let phaseError = 0;
    model.slots.forEach((tileId, slot) => {
      const tile = model.tileById.get(tileId);
      const sourceSlot = Number(tile.source.row) * 3 + Number(tile.source.column);
      if (sourceSlot !== slot) spatialError += 1;
      if (model.rotations[tileId] !== 0) rotationError += 1;
      phaseError += Math.abs(model.phases[tileId]);
    });
    return {
      spatial_error: spatialError,
      rotation_error: rotationError,
      phase_error: phaseError,
      continuity_milli: continuity(sceneTick),
    };
  }

  function stableErrors(errors) {
    return Object.values(errors).every((value) => value === 0);
  }

  function tileMarkup(tileId, slot) {
    const tile = model.tileById.get(tileId);
    const selected = tileId === model.selected;
    return `<div class="mosaic-slot" data-slot="${slot}"><article class="mosaic-tile${selected ? " is-selected" : ""}" draggable="true" data-tile-id="${clean(tileId)}" data-slot="${slot}" data-rotation="${model.rotations[tileId]}">
      <canvas width="300" height="200" aria-label="animated scene shard ${slot + 1}"></canvas>
      <span class="tile-corners"><i></i><i></i><i></i><i></i></span>
      <b>${clean(tileId.slice(-4).toUpperCase())}</b><em>${model.rotations[tileId] ? "180°" : ""}</em>
    </article></div>`;
  }

  function bindTiles() {
    document.querySelectorAll(".mosaic-tile").forEach((tileNode) => {
      tileNode.addEventListener("click", () => selectTile(String(tileNode.dataset.tileId)));
      tileNode.addEventListener("dragstart", (event) => {
        if (model.busy || model.terminal || model.sync) {
          event.preventDefault();
          return;
        }
        clearFreshFailure();
        model.dragged = String(tileNode.dataset.tileId);
        model.dragSucceeded = false;
        model.selected = model.dragged;
        event.dataTransfer.setData("text/plain", model.dragged);
        event.dataTransfer.effectAllowed = "move";
        tileNode.classList.add("is-dragging");
        updateInspector();
      });
      tileNode.addEventListener("dragover", (event) => event.preventDefault());
      tileNode.addEventListener("drop", (event) => {
        event.preventDefault();
        const movingId = event.dataTransfer.getData("text/plain") || model.dragged;
        const destinationSlot = Number(tileNode.dataset.slot);
        swapTiles(String(movingId || ""), destinationSlot);
      });
      tileNode.addEventListener("dragend", () => {
        tileNode.classList.remove("is-dragging");
        if (!model.dragSucceeded) model.helpers.setReadout("DROP CANCELED · MOSAIC UNCHANGED", "error");
        model.dragged = null;
      });
    });
  }

  function renderBoard() {
    const grid = document.getElementById("mosaic-grid");
    if (!grid) return;
    grid.innerHTML = model.slots.map(tileMarkup).join("");
    bindTiles();
    updateInspector();
  }

  function selectTile(tileId) {
    if (!model.tileById.has(tileId) || model.busy || model.terminal) return;
    clearFreshFailure();
    model.selected = tileId;
    document.querySelectorAll(".mosaic-tile").forEach((node) => node.classList.toggle("is-selected", node.dataset.tileId === tileId));
    updateInspector();
    model.helpers.setReadout("SHARD LOADED INTO TEMPORAL CONSOLE", "idle");
  }

  function swapTiles(tileId, destinationSlot) {
    if (!model.tileById.has(tileId) || !Number.isInteger(destinationSlot) || destinationSlot < 0 || destinationSlot >= 9) return;
    const fromSlot = model.slots.indexOf(tileId);
    if (fromSlot < 0 || fromSlot === destinationSlot) {
      model.helpers.setReadout("DROP CANCELED · CHOOSE ANOTHER CELL", "error");
      return;
    }
    const displacedId = model.slots[destinationSlot];
    model.slots[fromSlot] = displacedId;
    model.slots[destinationSlot] = tileId;
    model.spatialTouched.add(tileId);
    model.spatialTouched.add(displacedId);
    record("swap", {tile_id: tileId, from_slot: fromSlot, to_slot: destinationSlot, displaced_id: displacedId});
    model.dragSucceeded = true;
    model.dragged = null;
    renderBoard();
    updatePanels("SPATIAL SHARDS EXCHANGED", "idle");
  }

  function rotateSelected() {
    if (!model.selected || model.busy || model.terminal || model.sync) return;
    const tileId = model.selected;
    model.rotations[tileId] = model.rotations[tileId] === 180 ? 0 : 180;
    model.rotationTouched.add(tileId);
    record("rotate", {tile_id: tileId, rotation_after: model.rotations[tileId]});
    renderBoard();
    updatePanels("SHARD FLIPPED 180°", "idle");
  }

  function setSelectedPhase(nextPhase) {
    if (!model.selected || model.busy || model.terminal || model.sync) return;
    const range = model.state.phase_range;
    const tileId = model.selected;
    nextPhase = clamp(Math.round(nextPhase), Number(range.minimum), Number(range.maximum));
    const previous = model.phases[tileId];
    if (nextPhase === previous) return;
    model.phases[tileId] = nextPhase;
    model.phaseTouched.add(tileId);
    record("phase", {tile_id: tileId, delta_ticks: nextPhase - previous, phase_after: nextPhase});
    updateInspector();
    updatePanels(nextPhase === 0 ? "SHARD ON MASTER PHASE" : "SHARD TEMPORAL OFFSET CHANGED", nextPhase === 0 ? "passed" : "idle");
  }

  function phaseFromPointer(event, track) {
    const rect = track.getBoundingClientRect();
    const ratio = clamp((event.clientX - rect.left) / rect.width, 0, 1);
    const range = model.state.phase_range;
    return Number(range.minimum) + Math.round(ratio * (Number(range.maximum) - Number(range.minimum)));
  }

  function beginPhase(event) {
    if (!model.selected || model.busy || model.terminal || model.sync) return;
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    model.phaseDrag = {pointerId: event.pointerId};
    setSelectedPhase(phaseFromPointer(event, event.currentTarget));
  }

  function movePhase(event) {
    if (!model.phaseDrag || model.phaseDrag.pointerId !== event.pointerId) return;
    setSelectedPhase(phaseFromPointer(event, event.currentTarget));
  }

  function endPhase(event) {
    if (!model.phaseDrag || model.phaseDrag.pointerId !== event.pointerId) return;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    model.phaseDrag = null;
  }

  function updateInspector() {
    if (!model.selected || !model.tileById.has(model.selected)) return;
    const tile = model.tileById.get(model.selected);
    const selectedLabel = document.getElementById("selected-shard-id");
    const sourceLabel = document.getElementById("selected-shard-channel");
    const rotate = document.getElementById("mosaic-rotate");
    const phaseHandle = document.getElementById("phase-handle");
    const phaseLabel = document.getElementById("phase-label");
    if (selectedLabel) selectedLabel.textContent = model.selected.slice(-6).toUpperCase();
    if (sourceLabel) sourceLabel.textContent = `UNLABELED FEED ${model.selected.slice(6, 8).toUpperCase()}`;
    if (rotate) rotate.dataset.active = model.rotations[model.selected] === 180 ? "true" : "false";
    if (phaseHandle) {
      const range = model.state.phase_range;
      const ratio = (model.phases[model.selected] - Number(range.minimum)) / (Number(range.maximum) - Number(range.minimum));
      phaseHandle.style.left = `${ratio * 100}%`;
    }
    if (phaseLabel) {
      const phase = model.phases[model.selected];
      phaseLabel.dataset.master = phase === 0 ? "true" : "false";
      phaseLabel.textContent = phase === 0 ? "MASTER PHASE" : phase < 0 ? "EARLY OFFSET" : "LATE OFFSET";
    }
  }

  function updatePanels(message = null, status = "idle") {
    const tick = Math.round(performance.now() - model.startedAt);
    const errors = sceneErrors(tick);
    const labels = {
      spatial_error: ["space", "SPACE"],
      rotation_error: ["rotation", "ROTATION"],
      phase_error: ["phase", "PHASE"],
      continuity_milli: ["continuity", "SEAMS"],
    };
    Object.entries(labels).forEach(([fieldName, [selector]]) => {
      const node = document.querySelector(`[data-error="${selector}"]`);
      if (!node) return;
      const value = errors[fieldName];
      node.classList.toggle("is-clear", value === 0);
      node.querySelector("b").textContent = value === 0 ? "LOCKED" : "DRIFT";
    });
    const req = model.state.requirements;
    document.querySelector('[data-proof="space"]')?.classList.toggle("is-lit", model.spatialTouched.size >= Number(req.minimum_spatial_touches));
    document.querySelector('[data-proof="rotation"]')?.classList.toggle("is-lit", model.rotationTouched.size >= Number(req.minimum_rotation_touches));
    document.querySelector('[data-proof="phase"]')?.classList.toggle("is-lit", model.phaseTouched.size >= Number(req.minimum_phase_touches));
    const tape = document.getElementById("mosaic-tape");
    if (tape) tape.innerHTML = tapeMarkup();
    if (message !== null) model.helpers.setReadout(message, status);
    updateInspector();
  }

  function tapeMarkup() {
    const rows = model.events.filter((event) => ["swap", "rotate", "phase", "sync_sample"].includes(event.type)).slice(-6).reverse();
    if (!rows.length) return '<li><b>000</b><span>NO OPERATIONS</span><i>—</i></li>';
    return rows.map((event) => {
      let label = event.type.toUpperCase();
      let value = "—";
      if (event.type === "swap") value = `${event.from_slot + 1}↔${event.to_slot + 1}`;
      if (event.type === "rotate") value = `${event.rotation_after}°`;
      if (event.type === "phase") value = event.phase_after === 0 ? "MASTER" : `${event.phase_after > 0 ? "+" : ""}${event.phase_after}`;
      if (event.type === "sync_sample") {
        label = "SYNC / SAMPLE";
        value = event.stable ? "COHERENT" : "TEAR";
      }
      return `<li><b>${String(event.sequence).padStart(3, "0")}</b><span>${label}</span><i>${value}</i></li>`;
    }).join("");
  }

  function scenePosition(item, elapsed, width, height, index = 0) {
    const x = mod(Number(item.phase) / 13 + elapsed * Number(item.speed_x_milli) / 1000 + index * 137, width);
    const y = 35 + triangle(Number(item.phase) / 19 + elapsed * Number(item.speed_y_milli) / 1000 + index * 83, (height - 70) / 2);
    return [x, y];
  }

  function drawFullScene(context, elapsed) {
    const scene = model.state.scene;
    const width = Number(scene.width);
    const height = Number(scene.height);
    const palette = getComputedStyle(document.body);
    const cyan = palette.getPropertyValue("--mosaic-cyan").trim() || "#55e7df";
    const magenta = palette.getPropertyValue("--mosaic-magenta").trim() || "#ff4f9a";
    const signal = palette.getPropertyValue("--mosaic-signal").trim() || "#e9ff65";
    const background = context.createLinearGradient(0, 0, 0, height);
    background.addColorStop(0, "#071826");
    background.addColorStop(.52, "#102c37");
    background.addColorStop(1, "#061014");
    context.fillStyle = background;
    context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(175,220,220,.08)";
    context.lineWidth = 1;
    for (let x = 0; x <= width; x += 50) { context.beginPath(); context.moveTo(x, 0); context.lineTo(x, height); context.stroke(); }
    for (let y = 0; y <= height; y += 50) { context.beginPath(); context.moveTo(0, y); context.lineTo(width, y); context.stroke(); }
    context.fillStyle = "rgba(42,77,83,.72)";
    context.beginPath();
    context.moveTo(0, scene.horizon);
    for (let x = 0; x <= width; x += 90) {
      const y = Number(scene.horizon) - 45 - mod(Number(scene.field_seed) + x * 13, 105);
      context.lineTo(x, y);
    }
    context.lineTo(width, height); context.lineTo(0, height); context.closePath(); context.fill();
    context.fillStyle = "rgba(7,22,27,.78)";
    context.fillRect(0, Number(scene.horizon) + 70, width, height);
    for (let index = 0; index < scene.decoys.length; index += 1) {
      const decoy = scene.decoys[index];
      const [x, y] = scenePosition(decoy, elapsed * Number(decoy.depth_milli) / 1000, width, height, index);
      context.save();
      context.globalAlpha = .35 + Number(decoy.depth_milli) / 1800;
      context.fillStyle = index % 2 ? magenta : cyan;
      context.shadowColor = context.fillStyle;
      context.shadowBlur = 14;
      context.beginPath(); context.arc(x, y, Number(decoy.radius), 0, Math.PI * 2); context.fill();
      context.restore();
    }
    const [targetX, targetY] = scenePosition(scene.target, elapsed, width, height, 11);
    context.save();
    context.translate(targetX, targetY);
    context.fillStyle = signal;
    context.shadowColor = signal;
    context.shadowBlur = 24;
    context.beginPath(); context.moveTo(-34, 0); context.quadraticCurveTo(-8, -28, 24, -12); context.lineTo(38, 0); context.lineTo(24, 12); context.quadraticCurveTo(-8, 28, -34, 0); context.fill();
    context.fillStyle = "#0c2025"; context.beginPath(); context.arc(8, 0, 7, 0, Math.PI * 2); context.fill();
    context.restore();
    const sweepX = mod(elapsed * .105 + Number(scene.field_seed) % width, width);
    context.strokeStyle = "rgba(240,255,190,.42)"; context.lineWidth = 2; context.beginPath(); context.moveTo(sweepX, 0); context.lineTo(sweepX, height); context.stroke();
    context.strokeStyle = "rgba(230,238,218,.27)"; context.lineWidth = 3; context.beginPath(); context.moveTo(0, Number(scene.horizon) + 18); context.bezierCurveTo(width * .25, Number(scene.horizon) - 90, width * .7, Number(scene.horizon) + 120, width, Number(scene.horizon) - 25); context.stroke();
  }

  function drawTile(canvas, tileId, elapsed) {
    const context = canvas.getContext("2d");
    if (!context) return;
    const tile = model.tileById.get(tileId);
    const localTime = elapsed + model.phases[tileId] * Number(model.state.scene.phase_tick_ms);
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.save();
    if (model.rotations[tileId] === 180) {
      context.translate(canvas.width, canvas.height);
      context.rotate(Math.PI);
    }
    context.scale(canvas.width / 300, canvas.height / 200);
    context.translate(-Number(tile.source.column) * 300, -Number(tile.source.row) * 200);
    drawFullScene(context, localTime);
    context.restore();
  }

  function drawFrame(timestamp) {
    if (!model.state || model.terminal && document.body.dataset.mechanic !== "single-scene-split-boxes") return;
    if (timestamp - model.lastDrawAt >= 32) {
      model.lastDrawAt = timestamp;
      const elapsed = performance.now() - model.startedAt;
      document.querySelectorAll(".mosaic-tile").forEach((node) => {
        const canvas = node.querySelector("canvas");
        if (canvas) drawTile(canvas, String(node.dataset.tileId), elapsed);
      });
      const chronograph = document.getElementById("master-chronograph");
      if (chronograph) chronograph.style.setProperty("--master-phase", String(mod(elapsed, Number(model.state.scene.period_ms)) / Number(model.state.scene.period_ms)));
    }
    model.animationFrame = requestAnimationFrame(drawFrame);
  }

  function takeSyncSample() {
    if (!model.sync) return;
    const elapsed = Math.round(performance.now() - model.sync.startedAt);
    const sceneTick = Math.round(performance.now() - model.startedAt);
    const errors = sceneErrors(sceneTick);
    const stable = stableErrors(errors);
    record("sync_sample", {elapsed_ms: elapsed, scene_tick: sceneTick, ...errors, stable});
    model.sync.samples.push({stable, errors});
    model.sync.lastSampleAt = performance.now();
    const progress = document.querySelector(".mosaic-sync-progress i");
    if (progress) progress.style.width = `${Math.min(100, elapsed / Number(model.state.requirements.hold_ms) * 100)}%`;
    const reason = stable ? "ALL SEAMS COHERENT · HOLD" : errors.spatial_error ? "SPATIAL SHATTER" : errors.rotation_error ? "ROTATION BREAK" : errors.phase_error ? "PHASE DRIFT" : "BOUNDARY TEAR";
    updatePanels(reason, stable ? "pending" : "error");
  }

  function beginSync(event) {
    if (model.busy || model.terminal || model.sync || model.dragged || model.phaseDrag) return;
    clearFreshFailure();
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const sceneTick = Math.round(performance.now() - model.startedAt);
    model.sync = {pointerId: event.pointerId, startedAt: performance.now(), lastSampleAt: 0, samples: []};
    record("sync_start", {scene_tick: sceneTick});
    document.querySelector(".mosaic-captcha")?.classList.add("is-syncing");
    takeSyncSample();
    if (model.syncTimer) window.clearInterval(model.syncTimer);
    model.syncTimer = window.setInterval(takeSyncSample, Number(model.state.requirements.sample_ms));
  }

  function syncFailureReason(samples, duration, proofReady) {
    if (duration < Number(model.state.requirements.hold_ms) - 40) return "SYNC RELEASED EARLY";
    if (!proofReady) return "OPERATIONS UNPROVEN";
    const firstBad = samples.find((sample) => !sample.stable);
    if (!firstBad) return "SCENE SYNC REJECTED";
    if (firstBad.errors.spatial_error) return "SPATIAL SHATTER";
    if (firstBad.errors.rotation_error) return "ROTATION BREAK";
    if (firstBad.errors.phase_error) return "PHASE DRIFT";
    return "BOUNDARY TEAR";
  }

  async function submitSync(completed, reason) {
    model.busy = true;
    model.terminal = true;
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    model.helpers.setReadout("REPLAYING NINE CHANNELS…", "pending");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      final_slots: Object.fromEntries(model.slots.map((tileId, slot) => [tileId, slot])),
      final_rotations: {...model.rotations},
      final_phases: {...model.phases},
      completed,
    };
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload)});
      const outcome = await response.json();
      if (outcome.passed === true) {
        const shell = document.querySelector(".mosaic-captcha");
        shell?.classList.add("is-pass");
        shell?.insertAdjacentHTML("beforeend", '<div class="mosaic-verdict mosaic-verdict-pass"><small>NINE CHANNELS COHERENT</small><strong>PASS</strong></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".mosaic-captcha");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", `<div class="mosaic-verdict mosaic-verdict-fail"><small>${clean(reason)} · FRESH CHANNELS</small><strong>FAIL</strong></div>`);
        model.helpers.setReadout(`FAIL · ${reason} · NEW SHATTER`, "error");
        window.setTimeout(() => document.querySelector(".mosaic-verdict-fail")?.remove(), 1700);
      } else {
        model.busy = false;
        model.terminal = false;
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
        model.helpers.setReadout("FAIL · NO SYNCHRONIZER GRADE", "error");
      }
    } catch (_error) {
      model.busy = false;
      model.terminal = false;
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      model.helpers.setReadout("FAIL · SYNCHRONIZER OFFLINE", "error");
    }
  }

  function endSync(event) {
    const sync = model.sync;
    if (!sync || sync.pointerId !== event.pointerId) return;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    if (model.syncTimer) window.clearInterval(model.syncTimer);
    model.syncTimer = null;
    const duration = Math.round(performance.now() - sync.startedAt);
    if (performance.now() - sync.lastSampleAt >= 45) takeSyncSample();
    model.sync = null;
    document.querySelector(".mosaic-captcha")?.classList.remove("is-syncing");
    record("sync_end", {duration_ms: duration, sample_count: sync.samples.length});
    const requirements = model.state.requirements;
    const proofReady = model.spatialTouched.size >= Number(requirements.minimum_spatial_touches)
      && model.rotationTouched.size >= Number(requirements.minimum_rotation_touches)
      && model.phaseTouched.size >= Number(requirements.minimum_phase_touches);
    const completed = duration >= Number(requirements.hold_ms) - 40
      && sync.samples.length >= Number(requirements.minimum_samples)
      && sync.samples.every((sample) => sample.stable)
      && proofReady;
    const reason = syncFailureReason(sync.samples, duration, proofReady);
    submitSync(completed, reason);
  }

  function clearFreshFailure() {
    document.querySelector(".mosaic-verdict-fail")?.remove();
    document.querySelector(".mosaic-captcha")?.classList.remove("is-fresh-fail");
  }

  function resetMosaic() {
    if (model.busy) return;
    if (model.syncTimer) window.clearInterval(model.syncTimer);
    model.syncTimer = null;
    model.sync = null;
    model.events = [];
    model.spatialTouched = new Set();
    model.rotationTouched = new Set();
    model.phaseTouched = new Set();
    model.slots = Array(9).fill(null);
    model.state.tiles.forEach((tile) => {
      model.slots[Number(tile.initial_slot)] = String(tile.id);
      model.rotations[tile.id] = Number(tile.initial_rotation);
      model.phases[tile.id] = Number(tile.initial_phase);
    });
    model.selected = model.slots[0];
    model.dragged = null;
    model.phaseDrag = null;
    model.terminal = false;
    document.querySelector(".mosaic-captcha")?.classList.remove("is-pass", "is-syncing");
    document.querySelectorAll(".mosaic-verdict").forEach((node) => node.remove());
    const progress = document.querySelector(".mosaic-sync-progress i");
    if (progress) progress.style.width = "0%";
    renderBoard();
    updatePanels("MOSAIC RESET · OPERATION TAPE CLEARED", "idle");
  }

  async function render(state, helpers) {
    if (model.animationFrame) cancelAnimationFrame(model.animationFrame);
    if (model.syncTimer) window.clearInterval(model.syncTimer);
    document.body.dataset.mechanic = "single-scene-split-boxes";
    document.body.dataset.mosaicPalette = String(state.palette || "abyssal_cyan");
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const tileById = new Map(state.tiles.map((tile) => [String(tile.id), tile]));
    const slots = Array(9).fill(null);
    const rotations = {};
    const phases = {};
    state.tiles.forEach((tile) => {
      slots[Number(tile.initial_slot)] = String(tile.id);
      rotations[tile.id] = Number(tile.initial_rotation);
      phases[tile.id] = Number(tile.initial_phase);
    });
    Object.assign(model, {
      state,
      tileById,
      slots,
      rotations,
      phases,
      selected: slots[0],
      events: [],
      spatialTouched: new Set(),
      rotationTouched: new Set(),
      phaseTouched: new Set(),
      startedAt: performance.now(),
      animationFrame: null,
      lastDrawAt: -1,
      dragged: null,
      dragSucceeded: false,
      phaseDrag: null,
      sync: null,
      syncTimer: null,
      busy: false,
      terminal: false,
      helpers,
    });
    helpers.app.innerHTML = `<section class="mosaic-captcha" data-challenge-id="${clean(state.challenge_id)}">
      <header class="mosaic-head"><div><span>LIVE SCENE SYNCHRONIZER / NINE CHANNELS</span><h1>${clean(state.prompt)}</h1></div><div class="master-clock" id="master-chronograph"><small>MASTER CHRONOGRAPH</small><b><i></i></b><em>${clean(state.scene.motif).replaceAll("_", " ")}</em></div></header>
      <main class="mosaic-workbench"><section class="mosaic-stage"><div class="mosaic-grid" id="mosaic-grid">${slots.map(tileMarkup).join("")}</div><div class="mosaic-stage-caption"><span>DRAG TO EXCHANGE SHARDS</span><i>MOTION NEVER STOPS</i><b>3 × 3</b></div></section>
      <aside class="mosaic-console"><div class="mosaic-console-title"><span>SHARD TRANSFORM BAY</span><i>LIVE</i></div><div class="selected-shard"><small>SELECTED SHARD</small><b id="selected-shard-id">${clean(slots[0].slice(-6).toUpperCase())}</b><i id="selected-shard-channel">UNLABELED FEED</i></div>
      <button type="button" class="mosaic-rotate" id="mosaic-rotate"><span>↻</span><b>FLIP 180°</b><small>SELECTED SHARD ONLY</small></button>
      <div class="phase-console"><header><span>TEMPORAL SCRUB</span><b id="phase-label">OFFSET</b></header><div class="phase-track" id="phase-track">${Array.from({length: 9}, (_, index) => `<i class="${index === 4 ? "master" : ""}"></i>`).join("")}<button type="button" id="phase-handle" class="phase-handle"><span></span></button></div><footer><i>EARLY</i><b>MASTER</b><i>LATE</i></footer></div>
      <div class="mosaic-errors"><div data-error="space"><i></i><span>SPACE</span><b>DRIFT</b></div><div data-error="rotation"><i></i><span>ROTATION</span><b>DRIFT</b></div><div data-error="phase"><i></i><span>PHASE</span><b>DRIFT</b></div><div data-error="continuity"><i></i><span>SEAMS</span><b>DRIFT</b></div></div>
      <div class="mosaic-proof"><span data-proof="space"><i></i>SHARDS MOVED</span><span data-proof="rotation"><i></i>FLIPS WORKED</span><span data-proof="phase"><i></i>PHASES SCRUBBED</span></div><ol class="mosaic-tape" id="mosaic-tape">${tapeMarkup()}</ol></aside></main>
      <footer class="mosaic-foot"><button type="button" class="mosaic-reset" id="mosaic-reset">↺ RESET SHATTER</button><div><div class="readout" data-status="idle">REASSEMBLE SPACE · ORIENTATION · TIME</div><div class="mosaic-sync-progress"><i></i></div></div><button type="button" class="mosaic-sync" id="mosaic-sync"><span>${clean(state.submit_label || "HOLD SCENE SYNC")}</span><small>PRESS · HOLD · RELEASE</small></button></footer>
      ${helpers.cheatPanelTemplate()}</section>`;
    bindTiles();
    document.getElementById("mosaic-rotate")?.addEventListener("click", rotateSelected);
    const phaseTrack = document.getElementById("phase-track");
    phaseTrack?.addEventListener("pointerdown", beginPhase);
    phaseTrack?.addEventListener("pointermove", movePhase);
    phaseTrack?.addEventListener("pointerup", endPhase);
    phaseTrack?.addEventListener("pointercancel", endPhase);
    const sync = document.getElementById("mosaic-sync");
    sync?.addEventListener("pointerdown", beginSync);
    sync?.addEventListener("pointerup", endSync);
    sync?.addEventListener("pointercancel", endSync);
    document.getElementById("mosaic-reset")?.addEventListener("click", resetMosaic);
    updatePanels();
    helpers.installCheatPanel();
    model.animationFrame = requestAnimationFrame(drawFrame);
    window.singleSceneSplitBoxesModel = model;
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.single_scene_split_boxes = {rootSelector: ".mosaic-captcha", render};
})();
