(() => {
  "use strict";
  let model = null;
  const AXIS = { x: 0, y: 1, z: 2 };
  const clean = (value) =>
    String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const round = (value) => Math.round(Number(value) * 10000) / 10000;
  function record(kind, details = {}) {
    const event = { sequence: model.events.length + 1, kind, ...details };
    model.events.push(event);
    return event;
  }
  function worldCenter(center, q) {
    const [x, y, z] = center;
    return [[x, y, z], [z, y, -x], [-x, y, -z], [-z, y, x]][((q % 4) + 4) % 4];
  }
  function intersections(axis, offset, q) {
    const index = AXIS[axis],
      remaining = { x: [2, 1], y: [0, 2], z: [0, 1] }[axis],
      records = [];
    model.state.solids.forEach((solid) => {
      const center = worldCenter(solid.center, q),
        distance = Math.abs(offset - center[index]);
      let a, b;
      if (solid.kind === "sphere") {
        if (distance > solid.radius + 1e-9) return;
        a = b = Math.sqrt(Math.max(0, solid.radius ** 2 - distance ** 2));
      } else if (solid.kind === "box") {
        const half = q % 2
          ? [solid.half[2], solid.half[1], solid.half[0]]
          : solid.half;
        if (distance > half[index] + 1e-9) return;
        a = half[remaining[0]];
        b = half[remaining[1]];
      } else if (axis === "y") {
        const vertical = Math.abs(offset - center[1]);
        let cross;
        if (vertical <= solid.half_segment) cross = solid.radius;
        else if (vertical <= solid.half_segment + solid.radius) {
          cross = Math.sqrt(
            Math.max(
              0,
              solid.radius ** 2 - (vertical - solid.half_segment) ** 2,
            ),
          );
        } else return;
        a = b = cross;
      } else {
        if (distance > solid.radius + 1e-9) return;
        const cross = Math.sqrt(Math.max(0, solid.radius ** 2 - distance ** 2));
        a = cross;
        b = solid.half_segment + cross;
      }
      records.push({
        id: solid.id,
        kind: solid.kind,
        material: solid.material,
        u: round(center[remaining[0]]),
        v: round(center[remaining[1]]),
        a: round(a),
        b: round(b),
      });
    });
    return records.sort((a, b) => a.id.localeCompare(b.id));
  }
  function digest(records) {
    return records.map((r) =>
      `${r.id}:${r.kind}:${r.material}:${r.u.toFixed(4)}:${r.v.toFixed(4)}:${
        r.a.toFixed(4)
      }:${r.b.toFixed(4)}`
    ).join("|");
  }
  function inside(solid, point, extra = 0) {
    const [dx, dy, dz] = point.map((v, i) => v - solid.center[i]);
    if (solid.kind === "sphere") {
      return dx * dx + dy * dy + dz * dz <= (solid.radius + extra) ** 2;
    }
    if (solid.kind === "box") {
      return point.every((v, i) =>
        Math.abs(v - solid.center[i]) <= solid.half[i] + extra
      );
    }
    const radial = Math.hypot(dx, dz),
      vertical = Math.max(0, Math.abs(dy) - solid.half_segment);
    return radial * radial + vertical * vertical <= (solid.radius + extra) ** 2;
  }
  function blocker(start, end) {
    const target = model.state.solids.find((s) => s.material === "hot"),
      distance = Math.hypot(...end.map((v, i) => v - start[i])),
      steps = Math.max(1, Math.ceil(distance / model.state.probe.sweep_step)),
      r = Math.max(
        model.state.probe.radius,
        model.captured ? target.radius : 0,
      ),
      b = model.state.bounds;
    for (let n = 1; n <= steps; n++) {
      const t = n / steps, p = start.map((v, i) => v + (end[i] - v) * t);
      if (
        !(p[0] >= b.x[0] + r && p[0] <= b.x[1] - r && p[1] >= -4.6 &&
          p[1] <= 4.6 && p[2] >= b.z[0] + r && p[2] <= b.z[1] - r)
      ) return "suitcase-wall";
      for (const solid of model.state.solids) {
        if (solid.material !== "hot" && inside(solid, p, r)) return solid.id;
      }
    }
    return null;
  }
  function screenToCoord(view, screen, current) {
    const point = [...current];
    view.axes.forEach((axis, i) =>
      point[AXIS[axis]] = (screen[i] - view.center[i]) /
        (view.scale * view.signs[i])
    );
    return point;
  }
  function coordToScreen(view, point) {
    return view.axes.map((axis, i) =>
      view.center[i] + view.scale * view.signs[i] * point[AXIS[axis]]
    );
  }
  function canvasPoint(canvas, event) {
    const rect = canvas.getBoundingClientRect();
    return [
      (event.clientX - rect.left) / rect.width * canvas.width,
      (event.clientY - rect.top) / rect.height * canvas.height,
    ];
  }
  function clearFresh() {
    document.querySelector(".tomo-fresh")?.remove();
    document.querySelector(".tomo-captcha")?.removeAttribute(
      "data-fresh-failure",
    );
  }
  function setMessage(message, status = "idle") {
    model.helpers.setReadout(message, status);
  }
  function observe() {
    if (model.caseLocked) return;
    clearFresh();
    const records = intersections(model.axis, model.offset, model.rotation);
    model.lastRecords = records;
    record("slice_observation", {
      axis: model.axis,
      offset: round(model.offset),
      rotation: model.rotation,
      records,
      digest: digest(records),
    });
    model.observations++;
    if (records.some((r) => r.material === "hot")) {
      model.targetSignatures.add(
        `${model.rotation}:${model.axis}:${round(model.offset)}`,
      );
      model.targetHits = model.targetSignatures.size;
    }
    drawSlice();
    updateHUD();
    setMessage(
      records.some((r) => r.material === "hot")
        ? "TARGET-DENSITY MATERIAL INTERSECTS THIS PLANE"
        : "SLICE REGISTERED · NEUTRAL DENSITIES ONLY",
      records.some((r) => r.material === "hot") ? "pending" : "idle",
    );
  }
  function lockCase() {
    if (model.caseLocked) return;
    const scans = model.events.filter((event) =>
      event.kind === "slice_observation"
    );
    const rotations = new Set(scans.map((event) => event.rotation));
    const offsets = scans.map((event) => event.offset);
    const ready = scans.length >= model.state.requirements.min_observations &&
      rotations.size >= model.state.requirements.min_rotations &&
      offsets.length && Math.max(...offsets) - Math.min(...offsets) >=
        model.state.requirements.min_offset_span &&
      model.targetHits >= model.state.requirements.min_target_observations;
    if (!ready) {
      setMessage(
        "LOCK REFUSED · COLLECT SEPARATED HOT SLICES ACROSS TWO CASE ORIENTATIONS",
        "error",
      );
      return;
    }
    const fromRotation = model.rotation;
    model.rotation = 0;
    record("lock_case", { from_rotation: fromRotation, rotation: 0 });
    model.caseLocked = true;
    document.querySelector(".tomo-slicer").dataset.locked = "true";
    updateHUD();
    setMessage(
      "CASE LOCKED AT SURGERY ORIENTATION · PROBE VIEWS NOW CO-REGISTERED",
      "pending",
    );
  }
  function drawSlice() {
    const canvas = model.sliceCanvas, ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#08171b";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = "#6ff4db44";
    ctx.lineWidth = 1;
    for (let i = 0; i <= 10; i++) {
      ctx.beginPath();
      ctx.moveTo(i * canvas.width / 10, 0);
      ctx.lineTo(i * canvas.width / 10, canvas.height);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * canvas.height / 10);
      ctx.lineTo(canvas.width, i * canvas.height / 10);
      ctx.stroke();
    }
    ctx.strokeStyle = model.state.palette.scan;
    ctx.lineWidth = 2;
    ctx.strokeRect(28, 22, canvas.width - 56, canvas.height - 44);
    const sx = 42, sy = 37, cx = canvas.width / 2, cy = canvas.height / 2;
    model.lastRecords.forEach((r) => {
      ctx.save();
      ctx.translate(cx + r.u * sx, cy - r.v * sy);
      ctx.fillStyle = r.material === "hot"
        ? model.state.palette.target + "cc"
        : model.state.palette.scan + "70";
      ctx.strokeStyle = r.material === "hot"
        ? "#fff"
        : model.state.palette.scan;
      ctx.shadowColor = ctx.strokeStyle;
      ctx.shadowBlur = r.material === "hot" ? 18 : 7;
      ctx.lineWidth = 2;
      if (r.kind === "box") {
        ctx.fillRect(-r.a * sx, -r.b * sy, 2 * r.a * sx, 2 * r.b * sy);
        ctx.strokeRect(-r.a * sx, -r.b * sy, 2 * r.a * sx, 2 * r.b * sy);
      } else {
        ctx.beginPath();
        ctx.ellipse(
          0,
          0,
          Math.max(2, r.a * sx),
          Math.max(2, r.b * sy),
          0,
          0,
          Math.PI * 2,
        );
        ctx.fill();
        ctx.stroke();
      }
      ctx.restore();
    });
    ctx.fillStyle = "#d8fff7";
    ctx.font = "700 11px ui-monospace";
    ctx.fillText(
      `${model.axis.toUpperCase()} PLANE ${
        model.offset.toFixed(2)
      } · RIGID QUARTER ${model.rotation}`,
      18,
      18,
    );
  }
  function drawProbeView(viewId) {
    const canvas = document.querySelector(`.tomo-probe[data-view='${viewId}']`),
      view = model.state.views[viewId],
      ctx = canvas.getContext("2d");
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#0a171c";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = "#a9d9d044";
    ctx.strokeRect(12, 12, canvas.width - 24, canvas.height - 24);
    model.state.solids.forEach((solid) => {
      if (model.captured && solid.material === "hot") return;
      const point = coordToScreen(view, solid.center);
      ctx.strokeStyle = "#9bbcb7";
      ctx.fillStyle = "#87aaa522";
      ctx.beginPath();
      if (solid.kind === "sphere") {
        ctx.arc(
          point[0],
          point[1],
          Math.max(5, solid.radius * view.scale),
          0,
          Math.PI * 2,
        );
      } else if (solid.kind === "box") {
        const halfA = solid.half[AXIS[view.axes[0]]] * view.scale;
        const halfB = solid.half[AXIS[view.axes[1]]] * view.scale;
        ctx.rect(point[0] - halfA, point[1] - halfB, halfA * 2, halfB * 2);
      } else if (view.axes.includes("y")) {
        const aIndex = view.axes.indexOf("y");
        const halfA =
          (aIndex === 0 ? solid.half_segment + solid.radius : solid.radius) *
          view.scale;
        const halfB =
          (aIndex === 1 ? solid.half_segment + solid.radius : solid.radius) *
          view.scale;
        ctx.roundRect(
          point[0] - halfA,
          point[1] - halfB,
          halfA * 2,
          halfB * 2,
          solid.radius * view.scale,
        );
      } else {
        ctx.arc(
          point[0],
          point[1],
          Math.max(5, solid.radius * view.scale),
          0,
          Math.PI * 2,
        );
      }
      ctx.fill();
      ctx.stroke();
    });
    const p = coordToScreen(view, model.probe);
    if (model.captured) {
      const target = model.state.solids.find((solid) =>
        solid.material === "hot"
      );
      ctx.fillStyle = model.state.palette.target + "88";
      ctx.strokeStyle = model.state.palette.target;
      ctx.beginPath();
      ctx.arc(p[0], p[1], target.radius * view.scale, 0, Math.PI * 2);
      ctx.fill();
      ctx.stroke();
    }
    ctx.strokeStyle = model.captured ? model.state.palette.target : "#fff";
    ctx.fillStyle = model.captured
      ? model.state.palette.target
      : model.state.palette.scan;
    ctx.shadowColor = ctx.fillStyle;
    ctx.shadowBlur = 12;
    ctx.beginPath();
    ctx.arc(p[0], p[1], 7, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
    ctx.shadowBlur = 0;
    ctx.fillStyle = "#dffaf4";
    ctx.font = "700 10px ui-monospace";
    ctx.fillText(viewId.toUpperCase(), 10, 14);
  }
  function drawProbe() {
    Object.keys(model.state.views).forEach(drawProbeView);
  }
  function updateHUD() {
    document.querySelector(".tomo-axis-value").textContent = model.axis
      .toUpperCase();
    document.querySelector(".tomo-offset-value").textContent = model.offset
      .toFixed(2);
    document.querySelector(".tomo-rotation-value").textContent = `${
      model.rotation * 90
    }°`;
    document.querySelector(".tomo-observation-value").textContent = String(
      model.observations,
    );
    document.querySelector(".tomo-probe-state").textContent = model.captured
      ? "TARGET HELD"
      : "EMPTY";
    document.querySelector(".tomo-damage-value").textContent = String(
      model.damages,
    );
  }
  function startProbe(viewId, event) {
    if (!model.caseLocked || model.completed || model.submitting) return;
    clearFresh();
    const canvas = event.currentTarget,
      screen = canvasPoint(canvas, event),
      mapped = screenToCoord(model.state.views[viewId], screen, model.probe),
      axes = model.state.views[viewId].axes.map((a) => AXIS[a]);
    if (Math.hypot(...axes.map((i) => mapped[i] - model.probe[i])) > .34) {
      return;
    }
    model.drag = { viewId, canvas };
    canvas.setPointerCapture?.(event.pointerId);
    record("probe_drag_start", { view_id: viewId, screen: screen.map(round) });
  }
  function moveProbe(event) {
    if (
      !model.drag || event.currentTarget !== model.drag.canvas ||
      model.completed
    ) return;
    const view = model.state.views[model.drag.viewId],
      screen = canvasPoint(event.currentTarget, event),
      candidate = screenToCoord(view, screen, model.probe),
      hit = blocker(model.probe, candidate),
      accepted = !hit;
    record("probe_sample", {
      view_id: model.drag.viewId,
      screen: screen.map(round),
      coordinate: candidate.map(round),
      accepted,
      ...(hit ? { blocker: hit } : {}),
    });
    if (accepted) {
      model.probe = candidate;
      document.querySelector(".tomo-local-fail")?.setAttribute(
        "data-visible",
        "false",
      );
    } else {
      model.damages++;
      const fail = document.querySelector(".tomo-local-fail");
      fail.dataset.visible = "true";
      fail.querySelector("span").textContent =
        `${hit.toUpperCase()} CONTACT · PROBE HELD AT LAST SAFE POINT`;
      setMessage("LOCAL DAMAGE STOP · REPOSITION OR RESET PROBE", "error");
    }
    drawProbe();
    updateHUD();
  }
  function endProbe(event) {
    if (!model.drag || event.currentTarget !== model.drag.canvas) return;
    record("probe_drag_end", { view_id: model.drag.viewId });
    model.drag = null;
    if (model.captured && model.probe[1] >= model.state.probe.exit_y) {
      record("withdrawal");
      model.completed = true;
      document.querySelector(".tomo-complete").dataset.visible = "true";
      setMessage("TARGET WITHDRAWN · SUITCASE INNOCENTS INTACT", "passed");
    }
    updateHUD();
  }
  function resetProbe() {
    if (model.drag || model.captured || model.completed) return;
    record("reset_probe");
    model.probe = [...model.state.probe.initial];
    model.resets++;
    document.querySelector(".tomo-local-fail").dataset.visible = "false";
    drawProbe();
    updateHUD();
    setMessage(
      "PROBE RECOVERED TO STERILE ENTRY POINT · DAMAGE REMAINS ON REPORT",
    );
  }
  function capture() {
    if (model.drag || model.captured || model.completed) return;
    const target = model.state.solids.find((s) => s.material === "hot");
    if (!target || !inside(target, model.probe, model.state.probe.radius)) {
      setMessage("CLAMP CLOSED ON EMPTY VOLUME", "error");
      return;
    }
    record("capture");
    model.captured = true;
    drawProbe();
    updateHUD();
    setMessage(
      "TARGET MATERIAL CAPTURED · WITHDRAW THROUGH SUPERIOR EDGE",
      "pending",
    );
  }
  async function submit() {
    if (model.submitting || model.terminal) return;
    model.submitting = true;
    setMessage(
      "REPLAYING RIGID SLICES, VIEW REGISTRATION, AND SWEPT PROBE…",
      "pending",
    );
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      extracted: model.completed,
      captured: model.captured,
      probe: model.probe.map(round),
      observations: model.observations,
      rotations: [
        ...new Set(
          model.events.filter((e) => e.kind === "slice_observation").map((e) =>
            e.rotation
          ),
        ),
      ].sort(),
      target_observations: model.targetHits,
      damages: model.damages,
      resets: model.resets,
      views_used: [
        ...new Set(
          model.events.filter((e) => e.kind === "probe_drag_start").map((e) =>
            e.view_id
          ),
        ),
      ].sort(),
    };
    try {
      const response = await fetch("/result", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(payload),
        }),
        outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".tomo-captcha").insertAdjacentHTML(
          "beforeend",
          '<div class="tomo-verdict"><small>VOLUMETRIC CHAIN OF CUSTODY</small><strong>PASS</strong><span>SLICE GEOMETRY · CROSS-VIEW REGISTRATION · CLEAN EXTRACTION</span></div>',
        );
        setMessage("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const root = document.querySelector(".tomo-captcha");
        root.dataset.freshFailure = "true";
        root.insertAdjacentHTML(
          "afterbegin",
          '<div class="tomo-fresh"><b>FAIL</b><span>REPORT REJECTED · FRESH SEALED SUITCASE ISSUED</span></div>',
        );
        const readout = document.querySelector(".readout");
        readout.textContent = "FAIL · FRESH TOMOGRAPHY SCENE ISSUED";
        readout.dataset.status = "error";
        setTimeout(clearFresh, 1800);
      } else {
        model.submitting = false;
        setMessage("FAIL · NO AUTHORITATIVE TOMOGRAPHY GRADE", "error");
      }
    } catch (_) {
      model.submitting = false;
      setMessage("FAIL · TOMOGRAPHY VERIFIER OFFLINE", "error");
    }
  }
  async function render(state, helpers) {
    document.body.dataset.mechanic = "tomographic-baggage-surgery";
    helpers.app.innerHTML = `<section class="tomo-captcha" data-challenge-id="${
      clean(state.challenge_id)
    }"><header class="tomo-head"><div><span>VOLUMETRIC CUSTOMS / CASE ${
      clean(state.challenge_id)
    }</span><h1>${
      clean(state.prompt)
    }</h1></div><p>OPAQUE CASE · LIVE PLANE INTERSECTIONS<br><b>NO DIRECT VOLUME VIEW</b></p></header><main class="tomo-main"><section class="tomo-slicer"><div class="tomo-panel-title"><b>X-RAY SLICE TABLE</b><span>ROTATE THE CASE, NOT THE ANSWER</span></div><canvas class="tomo-slice" width="520" height="245"></canvas><div class="tomo-slice-controls"><div class="tomo-axis-buttons">${
      state.slice.axes.map((a) =>
        `<button data-axis="${a}">${a.toUpperCase()}</button>`
      ).join("")
    }</div><button class="tomo-offset" data-delta="-.25">− PLANE</button><button class="tomo-offset" data-delta=".25">+ PLANE</button><button class="tomo-rotate">↻ CASE 90°</button><button class="tomo-observe">CAPTURE SLICE</button><button class="tomo-lock">LOCK FOR SURGERY</button></div><div class="tomo-stats"><span>AXIS <b class="tomo-axis-value">Z</b></span><span>OFFSET <b class="tomo-offset-value">0.00</b></span><span>ROTATION <b class="tomo-rotation-value">0°</b></span><span>SLICES <b class="tomo-observation-value">0</b></span></div></section><section class="tomo-surgery"><div class="tomo-panel-title"><b>ORTHOGONAL PROBE REGISTRATION</b><span>DRAG THE SAME BODY IN MULTIPLE VIEWS</span></div><div class="tomo-probe-grid">${
      Object.keys(state.views).map((v) =>
        `<canvas class="tomo-probe" data-view="${v}" width="330" height="224"></canvas>`
      ).join("")
    }</div><div class="tomo-actions"><button class="tomo-reset">RECOVER PROBE</button><button class="tomo-capture">CLOSE EXTRACTION CLAMP</button><span>CLAMP <b class="tomo-probe-state">EMPTY</b></span><span>DAMAGE <b class="tomo-damage-value">0</b></span></div><div class="tomo-local-fail" data-visible="false"><b>LOCAL DAMAGE STOP</b><span>INNOCENT CONTACT</span></div><div class="tomo-complete" data-visible="false"><b>EXTRACTION COMPLETE</b><span>WITHDRAWAL VOLUME CLEARED</span></div></section></main><footer class="tomo-foot"><div><span>INDEPENDENT GEOMETRY REPLAY</span><div class="readout" data-status="idle">SWEEP A PLANE THROUGH THE SEALED CASE</div></div><button class="tomo-submit">${
      clean(state.submit_label)
    }</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    model = {
      state,
      helpers,
      events: [],
      axis: "z",
      offset: 0,
      rotation: 0,
      caseLocked: false,
      lastRecords: [],
      observations: 0,
      targetHits: 0,
      targetSignatures: new Set(),
      probe: [...state.probe.initial],
      captured: false,
      completed: false,
      damages: 0,
      resets: 0,
      drag: null,
      submitting: false,
      terminal: false,
      sliceCanvas: document.querySelector(".tomo-slice"),
    };
    window.tomographicBaggageSurgeryModel = model;
    document.querySelectorAll(".tomo-axis-buttons button").forEach((button) =>
      button.addEventListener("click", () => {
        model.axis = button.dataset.axis;
        observe();
      })
    );
    document.querySelectorAll(".tomo-offset").forEach((button) =>
      button.addEventListener("click", () => {
        model.offset = Math.max(
          state.slice.minimum,
          Math.min(
            state.slice.maximum,
            model.offset + Number(button.dataset.delta),
          ),
        );
        observe();
      })
    );
    document.querySelector(".tomo-rotate").addEventListener("click", () => {
      if (model.caseLocked) return;
      const from = model.rotation;
      model.rotation = (model.rotation + 1) % 4;
      record("rotate_case", { from, to: model.rotation });
      observe();
    });
    document.querySelector(".tomo-observe").addEventListener("click", observe);
    document.querySelector(".tomo-lock").addEventListener("click", lockCase);
    document.querySelector(".tomo-reset").addEventListener("click", resetProbe);
    document.querySelector(".tomo-capture").addEventListener("click", capture);
    document.querySelector(".tomo-submit").addEventListener("click", submit);
    document.querySelectorAll(".tomo-probe").forEach((canvas) => {
      const view = canvas.dataset.view;
      canvas.addEventListener(
        "pointerdown",
        (event) => startProbe(view, event),
      );
      canvas.addEventListener("pointermove", moveProbe);
      canvas.addEventListener("pointerup", endProbe);
      canvas.addEventListener("pointercancel", endProbe);
    });
    helpers.installCheatPanel();
    model.lastRecords = intersections(model.axis, model.offset, model.rotation);
    drawSlice();
    drawProbe();
    updateHUD();
  }
  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.tomographic_baggage_surgery = {
    rootSelector: ".tomo-captcha",
    render,
  };
})();
