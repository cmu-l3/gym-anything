(() => {
  "use strict";

  const model = {
    state: null,
    rail: 0,
    depth: 0,
    events: [],
    railTravel: 0,
    depthTravel: 0,
    inertiaSamples: 0,
    railDrag: null,
    depthDrag: null,
    inertia: null,
    inertiaTimer: null,
    scan: null,
    scanTimer: null,
    busy: false,
    terminal: false,
    helpers: null,
  };

  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const px = (milli) => Number(milli) / 1000;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function record(type, details = {}) {
    const event = {
      sequence: model.events.length + 1,
      type,
      ...details,
      rail_milli: model.rail,
      depth_milli: model.depth,
    };
    model.events.push(event);
    return event;
  }

  function sceneLayer(layerId) {
    return model.state.scene.layers.find((layer) => layer.id === layerId);
  }

  function projectOffset(depth, parallax) {
    return Math.round((depth - 500) * Number(parallax) / 1000);
  }

  function derivedTargetDepth() {
    const {scene} = model.state;
    const piece = scene.piece;
    const gap = scene.gap;
    let bestDepth = Number(scene.depth.minimum_milli);
    let bestError = Number.POSITIVE_INFINITY;
    for (let depth = Number(scene.depth.minimum_milli); depth <= Number(scene.depth.maximum_milli); depth += 1) {
      const y = Number(piece.base_y_milli) + Math.round(depth * Number(piece.vertical_span_milli) / 1000);
      const scale = Number(piece.scale_base_milli) + Math.round(Number(piece.scale_span_milli) * depth / 1000);
      const width = Math.round(Number(piece.base_width_milli) * scale / 1000);
      const height = Math.round(Number(piece.base_height_milli) * scale / 1000);
      const error = Math.abs(y - Number(gap.y_milli)) + Math.abs(width - Number(gap.width_milli)) + Math.abs(height - Number(gap.height_milli));
      if (error < bestError) {
        bestDepth = depth;
        bestError = error;
      }
    }
    return bestDepth;
  }

  function geometry() {
    const {scene} = model.state;
    const gap = scene.gap;
    const piece = scene.piece;
    const layer = sceneLayer(gap.layer_id);
    const gapX = Number(gap.base_x_milli) + projectOffset(model.depth, layer.parallax_milli);
    const pieceX = model.rail + projectOffset(model.depth, piece.parallax_milli);
    const scale = Number(piece.scale_base_milli) + Math.round(Number(piece.scale_span_milli) * model.depth / 1000);
    const pieceY = Number(piece.base_y_milli) + Math.round(model.depth * Number(piece.vertical_span_milli) / 1000);
    const width = Math.round(Number(piece.base_width_milli) * scale / 1000);
    const height = Math.round(Number(piece.base_height_milli) * scale / 1000);
    const depthError = Math.abs(model.depth - derivedTargetDepth());
    return {
      gapX,
      pieceX,
      pieceY,
      width,
      height,
      xError: Math.abs(pieceX - gapX),
      depthError,
    };
  }

  function axisState() {
    const current = geometry();
    const tolerance = model.state.tolerances;
    return {
      ...current,
      railStable: current.xError <= Number(tolerance.x_milli),
      depthStable: current.depthError <= Number(tolerance.depth_milli),
    };
  }

  function stopInertiaTimer() {
    if (model.inertiaTimer) window.clearInterval(model.inertiaTimer);
    model.inertiaTimer = null;
  }

  function stopScanTimer() {
    if (model.scanTimer) window.clearInterval(model.scanTimer);
    model.scanTimer = null;
  }

  function clearFreshFailure() {
    document.querySelector(".alignment-verdict-fail")?.remove();
    document.querySelector(".alignment-captcha")?.classList.remove("is-fresh-fail");
  }

  function ridgePath(seedValue, baseY, amplitude, count = 10) {
    let seed = Number(seedValue) >>> 0;
    const points = [`M -40 ${baseY}`];
    for (let index = 0; index <= count; index += 1) {
      seed = (seed * 1664525 + 1013904223) >>> 0;
      const x = index * (900 / count);
      const y = baseY - 22 - (seed % amplitude);
      points.push(`L ${x.toFixed(1)} ${y}`);
    }
    points.push(`L 940 ${baseY + 90} L -40 ${baseY + 90} Z`);
    return points.join(" ");
  }

  function notchClass(notch) {
    return `notch-${String(notch || "round_left").replaceAll("_", "-")}`;
  }

  function gapMarkup(layerId) {
    const {scene} = model.state;
    if (scene.gap.layer_id !== layerId) return "";
    const gap = scene.gap;
    return `<div class="alignment-gap ${notchClass(gap.notch)}" style="left:${px(gap.base_x_milli)}px;top:${px(gap.y_milli)}px;width:${px(gap.width_milli)}px;height:${px(gap.height_milli)}px"><i></i><b>MISSING</b></div>`;
  }

  function layerMarkup(layer) {
    const decor = model.state.scene.decor;
    const layerGap = gapMarkup(layer.id);
    if (layer.id === "distant") {
      return `<div class="alignment-layer layer-distant" data-layer="${layer.id}">
        <svg viewBox="0 0 900 390" preserveAspectRatio="none"><path d="${ridgePath(decor.ridge_seed, 235, 88)}"></path><path d="${ridgePath(Number(decor.ridge_seed) + 117, 276, 54, 13)}"></path></svg>
        <i class="scene-orb" style="left:${px(decor.orb_x_milli)}px;top:${px(decor.orb_y_milli)}px"></i>${layerGap}</div>`;
    }
    if (layer.id === "middle") {
      return `<div class="alignment-layer layer-middle" data-layer="${layer.id}"><div class="scene-spires" style="--spire-x:${px(decor.spire_x_milli)}px"><i></i><i></i><i></i><i></i><i></i></div><div class="scene-wire"><i></i><i></i><i></i></div>${layerGap}</div>`;
    }
    return `<div class="alignment-layer layer-near" data-layer="${layer.id}"><div class="scene-bridge" style="top:${px(decor.bridge_y_milli)}px"><i></i><i></i><i></i></div><div class="scene-reeds">${Array.from({length: 18}, (_, index) => `<i style="--reed:${index};--reed-height:${34 + (index % 7) * 7}px;--reed-angle:${-9 + (index % 5) * 4}deg"></i>`).join("")}</div>${layerGap}</div>`;
  }

  function tapeMarkup() {
    const rows = model.events.filter((event) => ["rail_sample", "depth_sample", "inertia_sample", "scan_sample"].includes(event.type)).slice(-6).reverse();
    if (!rows.length) return '<li><b>000</b><span>OPTICS IDLE</span><i>—</i></li>';
    return rows.map((event) => {
      const labels = {
        rail_sample: "RAIL / HAND",
        depth_sample: "DEPTH / GRIP",
        inertia_sample: "RAIL / COAST",
        scan_sample: "OPTICAL / SAMPLE",
      };
      const detail = event.type === "scan_sample"
        ? (event.stable ? "STABLE" : "DRIFT")
        : event.type === "depth_sample"
          ? `${event.delta_milli > 0 ? "+" : ""}${event.delta_milli}`
          : `${event.delta_milli > 0 ? "+" : ""}${(event.delta_milli / 1000).toFixed(1)}`;
      return `<li><b>${String(event.sequence).padStart(3, "0")}</b><span>${labels[event.type]}</span><i>${detail}</i></li>`;
    }).join("");
  }

  function updateScene() {
    if (!model.state) return;
    const {scene} = model.state;
    scene.layers.forEach((layer) => {
      const node = document.querySelector(`.alignment-layer[data-layer="${layer.id}"]`);
      if (node) node.style.transform = `translateX(${px(projectOffset(model.depth, layer.parallax_milli))}px)`;
    });
    const current = geometry();
    const piece = document.getElementById("alignment-piece");
    if (piece) {
      piece.style.left = `${px(current.pieceX)}px`;
      piece.style.top = `${px(current.pieceY)}px`;
      piece.style.width = `${px(current.width)}px`;
      piece.style.height = `${px(current.height)}px`;
    }
    const carriage = document.getElementById("alignment-carriage");
    if (carriage) carriage.style.left = `${px(model.rail)}px`;
    const depthTrack = document.getElementById("alignment-depth-track");
    const depthGrip = document.getElementById("alignment-depth-grip");
    if (depthTrack && depthGrip) {
      const trackHeight = depthTrack.clientHeight || 246;
      const normalized = (model.depth - Number(scene.depth.minimum_milli)) / (Number(scene.depth.maximum_milli) - Number(scene.depth.minimum_milli));
      depthGrip.style.top = `${(1 - normalized) * (trackHeight - 46)}px`;
    }
    const shell = document.querySelector(".alignment-captcha");
    shell?.style.setProperty("--depth-phase", String(model.depth / 1000));
  }

  function updatePanels(message = null, status = "idle") {
    const axes = axisState();
    const railLamp = document.querySelector('[data-axis="rail"]');
    const depthLamp = document.querySelector('[data-axis="depth"]');
    railLamp?.classList.toggle("is-locked", axes.railStable);
    depthLamp?.classList.toggle("is-locked", axes.depthStable);
    if (railLamp) railLamp.querySelector("b").textContent = axes.railStable ? "COINCIDENT" : "UNRESOLVED";
    if (depthLamp) depthLamp.querySelector("b").textContent = axes.depthStable ? "COINCIDENT" : "UNRESOLVED";
    const inertia = document.getElementById("alignment-inertia");
    if (inertia) {
      inertia.dataset.active = model.inertia ? "true" : "false";
      inertia.innerHTML = model.inertia
        ? `<b>COASTING</b><span>${Math.abs(model.inertia.velocity / 1000).toFixed(0)} PX/S</span>`
        : `<b>SETTLED</b><span>${model.inertiaSamples} SAMPLES CAPTURED</span>`;
    }
    const proofRail = document.querySelector('[data-proof="rail"]');
    const proofDepth = document.querySelector('[data-proof="depth"]');
    const proofInertia = document.querySelector('[data-proof="inertia"]');
    proofRail?.classList.toggle("is-lit", model.railTravel >= Number(model.state.tolerances.minimum_rail_travel_milli));
    proofDepth?.classList.toggle("is-lit", model.depthTravel >= Number(model.state.tolerances.minimum_depth_travel_milli));
    proofInertia?.classList.toggle("is-lit", model.inertiaSamples >= Number(model.state.tolerances.minimum_inertia_samples));
    const tape = document.getElementById("alignment-tape");
    if (tape) tape.innerHTML = tapeMarkup();
    if (message !== null) model.helpers.setReadout(message, status);
    updateScene();
  }

  function beginRail(event) {
    if (model.busy || model.terminal || model.scan || model.inertia || model.railDrag || model.depthDrag) return;
    clearFreshFailure();
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    model.railDrag = {
      pointerId: event.pointerId,
      lastX: event.clientX,
      lastTime: performance.now(),
      lastDelta: 0,
      lastDt: 1,
    };
    record("rail_start");
    document.querySelector(".alignment-captcha")?.classList.add("is-rail-dragging");
    updatePanels("RAIL CLUTCH ENGAGED", "idle");
  }

  function moveRail(event) {
    const drag = model.railDrag;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const now = performance.now();
    const dtMs = clamp(Math.round(now - drag.lastTime), 1, 250);
    const requested = Math.round((event.clientX - drag.lastX) * 1000);
    const rail = model.state.scene.rail;
    const next = clamp(model.rail + requested, Number(rail.minimum_milli), Number(rail.maximum_milli));
    const delta = next - model.rail;
    model.rail = next;
    model.railTravel += Math.abs(delta);
    drag.lastX = event.clientX;
    drag.lastTime = now;
    drag.lastDelta = delta;
    drag.lastDt = dtMs;
    record("rail_sample", {delta_milli: delta, dt_ms: dtMs});
    updatePanels(delta === 0 ? "RAIL HARD STOP" : "RAIL TRACKING", delta === 0 ? "error" : "idle");
  }

  function startInertia(velocity) {
    model.inertia = {velocity};
    stopInertiaTimer();
    updatePanels("CARRIAGE RELEASED · INERTIA LIVE", "pending");
    const contract = model.state.inertia;
    model.inertiaTimer = window.setInterval(() => {
      if (!model.inertia || model.terminal) {
        stopInertiaTimer();
        return;
      }
      const rail = model.state.scene.rail;
      const currentVelocity = model.inertia.velocity;
      const requested = Math.round(currentVelocity * Number(contract.tick_ms) / 1000);
      const next = clamp(model.rail + requested, Number(rail.minimum_milli), Number(rail.maximum_milli));
      const delta = next - model.rail;
      let velocityAfter = Math.round(currentVelocity * Number(contract.friction_milli) / 1000);
      let reason = null;
      if (delta === 0) {
        velocityAfter = 0;
        reason = "boundary";
      } else if (Math.abs(velocityAfter) < Number(contract.stop_velocity_milli_s)) {
        reason = "friction";
      }
      model.rail = next;
      model.inertiaSamples += 1;
      record("inertia_sample", {delta_milli: delta, velocity_after_milli_s: velocityAfter});
      model.inertia.velocity = velocityAfter;
      updatePanels("CARRIAGE COASTING · WAIT FOR SETTLE", "pending");
      if (reason) {
        record("inertia_end", {reason});
        model.inertia = null;
        stopInertiaTimer();
        updatePanels(reason === "boundary" ? "HARD STOP CAUGHT THE CARRIAGE" : "FRICTION SETTLED THE CARRIAGE", "idle");
      }
    }, Number(contract.tick_ms));
  }

  function endRail(event) {
    const drag = model.railDrag;
    if (!drag || drag.pointerId !== event.pointerId) return;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    document.querySelector(".alignment-captcha")?.classList.remove("is-rail-dragging");
    const cap = Number(model.state.inertia.velocity_cap_milli_s);
    const velocity = clamp(Math.round(drag.lastDelta * 1000 / drag.lastDt), -cap, cap);
    model.railDrag = null;
    record("rail_end", {velocity_milli_s: velocity});
    if (Math.abs(velocity) >= Number(model.state.inertia.velocity_threshold_milli_s)) startInertia(velocity);
    else updatePanels("RAIL RELEASED · NO COAST", "idle");
  }

  function beginDepth(event) {
    if (model.busy || model.terminal || model.scan || model.inertia || model.railDrag || model.depthDrag) return;
    clearFreshFailure();
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    const track = document.getElementById("alignment-depth-track");
    model.depthDrag = {
      pointerId: event.pointerId,
      lastY: event.clientY,
      lastTime: performance.now(),
      trackHeight: track?.getBoundingClientRect().height || 246,
    };
    record("depth_start");
    document.querySelector(".alignment-captcha")?.classList.add("is-depth-dragging");
    updatePanels("DEPTH GRIP ENGAGED", "idle");
  }

  function moveDepth(event) {
    const drag = model.depthDrag;
    if (!drag || drag.pointerId !== event.pointerId) return;
    const now = performance.now();
    const dtMs = clamp(Math.round(now - drag.lastTime), 1, 250);
    const requested = Math.round(-(event.clientY - drag.lastY) * 1000 / drag.trackHeight);
    const depth = model.state.scene.depth;
    const next = clamp(model.depth + requested, Number(depth.minimum_milli), Number(depth.maximum_milli));
    const delta = next - model.depth;
    model.depth = next;
    model.depthTravel += Math.abs(delta);
    drag.lastY = event.clientY;
    drag.lastTime = now;
    record("depth_sample", {delta_milli: delta, dt_ms: dtMs});
    updatePanels(delta === 0 ? "DEPTH HARD STOP" : "PARALLAX PLANES SHIFTING", delta === 0 ? "error" : "idle");
  }

  function endDepth(event) {
    const drag = model.depthDrag;
    if (!drag || drag.pointerId !== event.pointerId) return;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    model.depthDrag = null;
    document.querySelector(".alignment-captcha")?.classList.remove("is-depth-dragging");
    record("depth_end");
    updatePanels("DEPTH GRIP RELEASED", "idle");
  }

  function takeScanSample() {
    if (!model.scan) return;
    const axes = axisState();
    const stable = axes.railStable && axes.depthStable;
    record("scan_sample", {
      x_error_milli: axes.xError,
      depth_error_milli: axes.depthError,
      stable,
    });
    model.scan.samples.push({stable, railStable: axes.railStable, depthStable: axes.depthStable});
    model.scan.lastSampleAt = performance.now();
    const progress = document.querySelector(".alignment-scan-progress i");
    if (progress) {
      const elapsed = performance.now() - model.scan.startedAt;
      progress.style.width = `${Math.min(100, elapsed / Number(model.state.tolerances.hold_ms) * 100)}%`;
    }
    const status = stable ? "OPTICAL COINCIDENCE HOLDING" : !axes.railStable && !axes.depthStable ? "RAIL + DEPTH DRIFT" : !axes.railStable ? "RAIL DRIFT" : "DEPTH DRIFT";
    updatePanels(status, stable ? "pending" : "error");
  }

  function beginScan(event) {
    if (model.busy || model.terminal || model.scan || model.railDrag || model.depthDrag) return;
    clearFreshFailure();
    if (model.inertia) {
      updatePanels("RAIL STILL COASTING · WAIT FOR SETTLE", "error");
      return;
    }
    event.preventDefault();
    event.currentTarget.setPointerCapture(event.pointerId);
    model.scan = {
      pointerId: event.pointerId,
      startedAt: performance.now(),
      lastSampleAt: 0,
      samples: [],
    };
    record("scan_start");
    document.querySelector(".alignment-captcha")?.classList.add("is-scanning");
    takeScanSample();
    stopScanTimer();
    model.scanTimer = window.setInterval(takeScanSample, Number(model.state.tolerances.sample_ms));
  }

  function failureReason(samples, duration, proofReady) {
    if (duration < Number(model.state.tolerances.hold_ms) - 40) return "LOCK RELEASED EARLY";
    if (!proofReady) return "INERTIA / TRAVEL UNPROVEN";
    const railBad = samples.some((sample) => !sample.railStable);
    const depthBad = samples.some((sample) => !sample.depthStable);
    if (railBad && depthBad) return "RAIL + DEPTH DRIFT";
    if (railBad) return "RAIL DRIFT";
    if (depthBad) return "DEPTH DRIFT";
    return "OPTICAL HOLD REJECTED";
  }

  async function submitScan(completed, reason) {
    model.busy = true;
    model.terminal = true;
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    model.helpers.setReadout("ANALYZING STABILITY TAPE…", "pending");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      final_rail_milli: model.rail,
      final_depth_milli: model.depth,
      completed,
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        const shell = document.querySelector(".alignment-captcha");
        shell?.classList.add("is-pass");
        shell?.insertAdjacentHTML("beforeend", '<div class="alignment-verdict alignment-verdict-pass"><small>PROJECTION COINCIDENT</small><strong>PASS</strong></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".alignment-captcha");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", `<div class="alignment-verdict alignment-verdict-fail"><small>${clean(reason)} · FRESH OPTICS</small><strong>FAIL</strong></div>`);
        model.helpers.setReadout(`FAIL · ${reason} · NEW GEOMETRY`, "error");
        window.setTimeout(() => document.querySelector(".alignment-verdict-fail")?.remove(), 1700);
      } else {
        model.busy = false;
        model.terminal = false;
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
        model.helpers.setReadout("FAIL · NO STABILITY GRADE", "error");
      }
    } catch (_error) {
      model.busy = false;
      model.terminal = false;
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      model.helpers.setReadout("FAIL · OPTICAL BUS OFFLINE", "error");
    }
  }

  function endScan(event) {
    const scan = model.scan;
    if (!scan || scan.pointerId !== event.pointerId) return;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    stopScanTimer();
    const duration = Math.round(performance.now() - scan.startedAt);
    if (performance.now() - scan.lastSampleAt >= 45) takeScanSample();
    model.scan = null;
    document.querySelector(".alignment-captcha")?.classList.remove("is-scanning");
    record("scan_end", {duration_ms: duration, sample_count: scan.samples.length});
    const proofReady = model.railTravel >= Number(model.state.tolerances.minimum_rail_travel_milli)
      && model.depthTravel >= Number(model.state.tolerances.minimum_depth_travel_milli)
      && model.inertiaSamples >= Number(model.state.tolerances.minimum_inertia_samples);
    const completed = duration >= Number(model.state.tolerances.hold_ms) - 40
      && scan.samples.length >= Number(model.state.tolerances.minimum_scan_samples)
      && scan.samples.every((sample) => sample.stable)
      && proofReady;
    const reason = failureReason(scan.samples, duration, proofReady);
    submitScan(completed, reason);
  }

  function resetInstrument() {
    if (model.busy) return;
    stopInertiaTimer();
    stopScanTimer();
    model.rail = Number(model.state.scene.rail.initial_milli);
    model.depth = Number(model.state.scene.depth.initial_milli);
    model.events = [];
    model.railTravel = 0;
    model.depthTravel = 0;
    model.inertiaSamples = 0;
    model.railDrag = null;
    model.depthDrag = null;
    model.inertia = null;
    model.scan = null;
    model.terminal = false;
    document.querySelector(".alignment-captcha")?.classList.remove("is-scanning", "is-rail-dragging", "is-depth-dragging", "is-pass");
    document.querySelectorAll(".alignment-verdict").forEach((node) => node.remove());
    const progress = document.querySelector(".alignment-scan-progress i");
    if (progress) progress.style.width = "0%";
    updatePanels("INSTRUMENT ZEROED · TAPE CLEARED", "idle");
  }

  async function render(state, helpers) {
    stopInertiaTimer();
    stopScanTimer();
    document.body.dataset.mechanic = "jigsaw-slider-alignment";
    document.body.dataset.alignmentPalette = String(state.palette || "oxide_cyan");
    document.body.dataset.alignmentTransform = String(state.scene.transform || "standard");
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    Object.assign(model, {
      state,
      rail: Number(state.scene.rail.initial_milli),
      depth: Number(state.scene.depth.initial_milli),
      events: [],
      railTravel: 0,
      depthTravel: 0,
      inertiaSamples: 0,
      railDrag: null,
      depthDrag: null,
      inertia: null,
      inertiaTimer: null,
      scan: null,
      scanTimer: null,
      busy: false,
      terminal: false,
      helpers,
    });
    const scene = state.scene;
    helpers.app.innerHTML = `
      <section class="alignment-captcha" data-challenge-id="${clean(state.challenge_id)}">
        <header class="alignment-head"><div><span>PARALLAX CALIBRATION / FRAGMENT 10</span><h1>${clean(state.prompt)}</h1></div><div class="alignment-challenge"><small>OPTICAL LOT</small><b>${clean(state.challenge_id).toUpperCase()}</b><i>${clean(scene.transform).replaceAll("_", " ")}</i></div></header>
        <main class="alignment-workbench">
          <section class="alignment-stage">
            <div class="alignment-scene transform-${clean(scene.transform)}" id="alignment-scene">
              <div class="scene-reticle"><i></i><i></i><b></b></div>
              ${scene.layers.map(layerMarkup).join("")}
              <div class="alignment-piece ${notchClass(scene.gap.notch)}" id="alignment-piece" aria-label="draggable missing scene fragment"><div class="fragment-orb"></div><div class="fragment-lines"><i></i><i></i><i></i></div><b>FRAGMENT</b></div>
              <div class="scene-chromatic chromatic-cyan"></div><div class="scene-chromatic chromatic-red"></div>
            </div>
            <div class="alignment-rail"><div class="rail-scale">${Array.from({length: 25}, (_, index) => `<i class="${index % 5 === 0 ? "major" : ""}"></i>`).join("")}</div><div class="rail-track"></div><button type="button" class="rail-carriage" id="alignment-carriage"><i></i><b>◁ DRAG RAIL ▷</b></button></div>
          </section>
          <aside class="alignment-console">
            <div class="alignment-console-title"><span>DEPTH PROJECTION</span><i>ANALYTIC</i></div>
            <div class="alignment-axis-pair"><div data-axis="rail"><i></i><span>HORIZONTAL</span><b>UNRESOLVED</b></div><div data-axis="depth"><i></i><span>DEPTH / SCALE</span><b>UNRESOLVED</b></div></div>
            <div class="alignment-depth-rig"><div class="depth-label depth-far">FAR PLANE</div><div class="depth-track" id="alignment-depth-track"><i></i><i></i><i></i><i></i><i></i><button type="button" id="alignment-depth-grip" class="depth-grip"><b>DEPTH</b><span>↕</span></button></div><div class="depth-label depth-near">NEAR PLANE</div></div>
            <div class="alignment-inertia" id="alignment-inertia" data-active="false"><i></i><div><b>SETTLED</b><span>0 SAMPLES CAPTURED</span></div></div>
            <div class="alignment-proof"><span data-proof="rail"><i></i>RAIL TRAVEL</span><span data-proof="depth"><i></i>DEPTH TRAVEL</span><span data-proof="inertia"><i></i>COAST OBSERVED</span></div>
            <ol class="alignment-tape" id="alignment-tape">${tapeMarkup()}</ol>
          </aside>
        </main>
        <footer class="alignment-foot"><button type="button" class="alignment-reset" id="alignment-reset">↺ ZERO INSTRUMENT</button><div><div class="readout" data-status="idle">CALIBRATE TWO AXES · SETTLE INERTIA</div><div class="alignment-scan-progress"><i></i></div></div><button type="button" class="alignment-scan" id="alignment-scan"><span>${clean(state.submit_label || "HOLD OPTICAL LOCK")}</span><small>PRESS · HOLD · RELEASE</small></button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    const carriage = document.getElementById("alignment-carriage");
    const piece = document.getElementById("alignment-piece");
    [carriage, piece].forEach((node) => {
      node?.addEventListener("pointerdown", beginRail);
      node?.addEventListener("pointermove", moveRail);
      node?.addEventListener("pointerup", endRail);
      node?.addEventListener("pointercancel", endRail);
    });
    const depthGrip = document.getElementById("alignment-depth-grip");
    depthGrip?.addEventListener("pointerdown", beginDepth);
    depthGrip?.addEventListener("pointermove", moveDepth);
    depthGrip?.addEventListener("pointerup", endDepth);
    depthGrip?.addEventListener("pointercancel", endDepth);
    const scan = document.getElementById("alignment-scan");
    scan?.addEventListener("pointerdown", beginScan);
    scan?.addEventListener("pointerup", endScan);
    scan?.addEventListener("pointercancel", endScan);
    document.getElementById("alignment-reset")?.addEventListener("click", resetInstrument);
    updatePanels();
    helpers.installCheatPanel();
    window.jigsawSliderAlignmentModel = model;
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.jigsaw_slider_alignment = {
    rootSelector: ".alignment-captcha",
    render,
  };
})();
