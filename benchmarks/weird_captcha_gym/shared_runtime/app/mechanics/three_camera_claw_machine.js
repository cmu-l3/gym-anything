(() => {
  "use strict";
  let model = null;
  const clean = (value) =>
    String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const round = (value) => Math.round(Number(value) * 10000) / 10000;
  function record(kind, details = {}) {
    const event = { sequence: model.events.length + 1, kind, ...details };
    model.events.push(event);
    return event;
  }
  function cloneObjects(objects = model.objects) {
    return Object.fromEntries(
      Object.entries(objects).map((
        [id, obj],
      ) => [id, { ...obj, center: [...obj.center] }]),
    );
  }
  function project(camera, point) {
    return camera.matrix.map((row, index) =>
      round(
        camera.origin[index] +
          row.reduce((sum, value, column) => sum + value * point[column], 0),
      )
    );
  }
  function digest(camera, claw, objects, captured) {
    const items = [
      ["claw", claw],
      ...Object.entries(objects).sort().map((
        [id, obj],
      ) => [id, id === captured ? claw : obj.center]),
    ];
    return items.map(([id, point]) => {
      const p = project(camera, point);
      return `${id}:${p[0].toFixed(4)}:${p[1].toFixed(4)}`;
    }).join("|");
  }
  function pointAabb(point, obstacle, radius) {
    return point.every((value, index) =>
      Math.abs(value - obstacle.center[index]) <= obstacle.half[index] + radius
    );
  }
  function blocker(start, end, radius) {
    const distance = Math.hypot(...end.map((v, i) => v - start[i])),
      steps = Math.max(
        1,
        Math.ceil(distance / model.state.world.collision_step),
      ),
      bounds = model.state.world.bounds;
    for (let n = 1; n <= steps; n++) {
      const t = n / steps, p = start.map((v, i) => v + (end[i] - v) * t);
      for (const [i, axis] of ["x", "y", "z"].entries()) {
        if (
          p[i] - radius < bounds[axis][0] || p[i] + radius > bounds[axis][1]
        ) return "cage-boundary";
      }
      for (const obstacle of model.state.obstacles) {
        if (pointAabb(p, obstacle, radius)) return obstacle.id;
      }
    }
    return null;
  }
  function contained(point, radius, box) {
    return point.every((v, i) =>
      Math.abs(v - box.center[i]) + radius <= box.half[i] + 1e-6
    );
  }
  function snapshot() {
    return {
      position: [...model.position],
      objects: cloneObjects(),
      captured: model.captured,
    };
  }
  function frameState(viewId) {
    const camera = model.state.cameras[viewId],
      visibleTick = Math.max(0, model.tick - camera.delay),
      snap = model.history[visibleTick];
    return {
      tick: visibleTick,
      digest: digest(camera, snap.position, snap.objects, snap.captured),
      snapshot: snap,
    };
  }
  function updateHistory() {
    if (model.captured) {
      model.objects[model.captured].center = [...model.position];
    }
    model.history[model.tick] = snapshot();
  }
  function clearFresh() {
    const root = document.querySelector(".claw-captcha"),
      wasFresh = root?.dataset.freshFailure === "true";
    document.querySelector(".claw-fresh")?.remove();
    root?.removeAttribute("data-fresh-failure");
    if (wasFresh && model && !model.terminal && !model.delivered) {
      setMessage("FRESH CAGE ACTIVE · TRIANGULATE THE MARKED ARTIFACT");
    }
  }
  function setMessage(message, status = "idle") {
    model.helpers.setReadout(message, status);
  }
  function applyControl(axis, direction = 0) {
    if (model.terminal || model.submitting || model.delivered) return;
    clearFresh();
    const world = model.state.world;
    if (axis === "brake") model.velocity = model.velocity.map((v) => v * .15);
    else if (axis === "coast") {}
    else {
      const index = { x: 0, y: 1, z: 2 }[axis];
      model.velocity[index] += direction * world.acceleration;
      const speed = Math.hypot(...model.velocity);
      if (speed > world.max_speed) {
        model.velocity = model.velocity.map((v) => v * world.max_speed / speed);
      }
    }
    record("control", {
      axis,
      ...(axis === "x" || axis === "y" || axis === "z" ? { direction } : {}),
    });
    physicsTick();
  }
  function physicsTick() {
    const start = [...model.position],
      candidate = model.position.map((v, i) => v + model.velocity[i]),
      radius = model.captured
        ? Math.max(
          model.state.world.claw_radius,
          model.objects[model.captured].radius,
        )
        : model.state.world.claw_radius,
      contact = blocker(start, candidate, radius);
    let resolution = "full", resolved = candidate;
    if (contact) {
      resolved = [...start];
      let moved = false;
      for (let index = 0; index < 3; index++) {
        const trial = [...resolved];
        trial[index] = candidate[index];
        if (!blocker(resolved, trial, radius)) {
          resolved = trial;
          moved ||= Math.abs(trial[index] - start[index]) > 1e-9;
        } else model.velocity[index] = 0;
      }
      resolution = moved ? "slide" : "blocked";
      model.collisions++;
      const alert = document.querySelector(".claw-impact");
      alert.dataset.visible = "true";
      alert.querySelector("span").textContent =
        `${contact.toUpperCase()} · ${resolution.toUpperCase()}`;
      setMessage(
        `RIGID CONTACT · ${contact.toUpperCase()} · RECOVER WITH BRAKE / REVERSE`,
        "error",
      );
    } else document.querySelector(".claw-impact").dataset.visible = "false";
    model.position = resolved;
    model.velocity = model.velocity.map((v) => v * model.state.world.damping);
    model.tick++;
    updateHistory();
    const visibleFrames = {};
    Object.keys(model.state.cameras).forEach((view) => {
      const frame = frameState(view);
      visibleFrames[view] = { tick: frame.tick, digest: frame.digest };
    });
    record("physics_tick", {
      tick: model.tick,
      resolution,
      ...(contact ? { contact } : {}),
      position: model.position.map(round),
      velocity: model.velocity.map(round),
      visible_frames: visibleFrames,
    });
    drawFeeds();
    updateHUD();
  }
  function grip() {
    if (model.terminal || model.submitting || model.delivered) return;
    clearFresh();
    if (model.gripper === "open") {
      const candidates = Object.entries(model.objects).map((
        [id, obj],
      ) => [
        Math.hypot(...obj.center.map((v, i) => v - model.position[i])),
        id,
      ]).sort((a, b) => a[0] - b[0]);
      let captured = null;
      for (const [distance, id] of candidates) {
        const obj = model.objects[id];
        if (
          distance <= model.state.world.capture_distance &&
          !blocker(obj.center, model.position, obj.radius)
        ) {
          captured = id;
          break;
        }
      }
      model.gripper = "closed";
      model.captured = captured;
      record("gripper", { action: "close", captured_id: captured });
      if (captured) {
        model.objects[captured].center = [...model.position];
        setMessage(
          "GRIPPER LOAD DETECTED · LIFT ABOVE THE CAGE BAFFLES",
          "pending",
        );
      } else setMessage("GRIPPER CLOSED ON EMPTY AIR", "error");
    } else {
      const released = model.captured,
        delivered = Boolean(
          released && model.objects[released].marked &&
            contained(
              model.position,
              model.objects[released].radius,
              model.state.chute,
            ),
        );
      record("gripper", { action: "open", released_id: released, delivered });
      model.gripper = "open";
      model.captured = null;
      if (delivered) {
        model.delivered = model.terminal = true;
        document.querySelector(".claw-complete").dataset.visible = "true";
        setMessage("MARKED ARTIFACT CONTAINED IN DELIVERY CHUTE", "passed");
      } else {setMessage(
          released
            ? "LOAD RELEASED OUTSIDE CERTIFIED CHUTE"
            : "EMPTY GRIPPER OPENED",
          released ? "error" : "idle",
        );}
    }
    updateHistory();
    drawFeeds();
    updateHUD();
  }
  function resetClaw() {
    if (model.captured || model.delivered || model.submitting) return;
    record("reset_claw");
    model.resets++;
    model.position = [...model.state.initial.position];
    model.velocity = [...model.state.initial.velocity];
    model.objects = Object.fromEntries(
      model.state.objects.map(
        (obj) => [obj.id, { ...obj, center: [...obj.center] }],
      ),
    );
    model.gripper = "open";
    model.captured = null;
    model.tick = 0;
    model.history = { 0: snapshot() };
    document.querySelector(".claw-impact").dataset.visible = "false";
    drawFeeds();
    updateHUD();
    setMessage("CLAW AND CCTV BUFFERS REWOUND");
  }
  function drawFeed(viewId) {
    const canvas = document.querySelector(`.claw-feed[data-view='${viewId}']`),
      ctx = canvas.getContext("2d"),
      camera = model.state.cameras[viewId],
      frame = frameState(viewId),
      snap = frame.snapshot;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    ctx.fillStyle = "#0a100e";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = "#90ad9640";
    ctx.lineWidth = 1;
    for (let i = 0; i < 12; i++) {
      ctx.beginPath();
      ctx.moveTo(i * canvas.width / 11, 0);
      ctx.lineTo(i * canvas.width / 11, canvas.height);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * canvas.height / 11);
      ctx.lineTo(canvas.width, i * canvas.height / 11);
      ctx.stroke();
    }
    function drawBox(center, half, color) {
      const p = project(camera, center),
        hx = Math.max(
          5,
          Math.abs(camera.matrix[0][0]) * half[0] +
            Math.abs(camera.matrix[0][1]) * half[1] +
            Math.abs(camera.matrix[0][2]) * half[2],
        ),
        hy = Math.max(
          5,
          Math.abs(camera.matrix[1][0]) * half[0] +
            Math.abs(camera.matrix[1][1]) * half[1] +
            Math.abs(camera.matrix[1][2]) * half[2],
        );
      ctx.fillStyle = color;
      ctx.strokeStyle = color;
      ctx.fillRect(p[0] - hx, p[1] - hy, hx * 2, hy * 2);
      ctx.strokeRect(p[0] - hx, p[1] - hy, hx * 2, hy * 2);
    }
    const scale = Math.max(...camera.matrix.flat().map(Math.abs));
    const primitives = [
      ...model.state.obstacles.map((obstacle) => ({
        kind: "box",
        center: obstacle.center,
        half: obstacle.half,
        color: "#303a35",
        priority: 2,
      })),
      {
        kind: "box",
        center: model.state.chute.center,
        half: model.state.chute.half,
        color: model.state.palette.chute,
        priority: 1,
      },
      ...Object.entries(snap.objects).map(([id, obj]) => ({
        kind: "object",
        center: id === snap.captured ? snap.position : obj.center,
        obj,
        priority: 3,
      })),
      { kind: "claw", center: snap.position, priority: 4 },
    ];
    primitives.sort((a, b) =>
      (a.center[camera.depth_axis] * camera.depth_sign) -
        (b.center[camera.depth_axis] * camera.depth_sign) ||
      a.priority - b.priority
    );
    primitives.forEach((primitive) => {
      if (primitive.kind === "box") {
        drawBox(primitive.center, primitive.half, primitive.color);
        return;
      }
      const p = project(camera, primitive.center);
      if (primitive.kind === "object") {
        const obj = primitive.obj;
        ctx.fillStyle = obj.color;
        ctx.strokeStyle = obj.marked ? "#fff" : "#18231e";
        ctx.lineWidth = obj.marked ? 3 : 1;
        ctx.beginPath();
        ctx.arc(p[0], p[1], Math.max(5, obj.radius * scale), 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
        if (obj.marked) {
          const radius = obj.radius * scale;
          ctx.beginPath();
          ctx.moveTo(p[0], p[1] - radius - 4);
          ctx.lineTo(p[0] - 6, p[1] - radius - 12);
          ctx.lineTo(p[0] + 6, p[1] - radius - 12);
          ctx.closePath();
          ctx.fillStyle = "#fff";
          ctx.fill();
        }
        return;
      }
      const radius = model.state.world.claw_radius * scale;
      ctx.strokeStyle = model.state.palette.claw;
      ctx.fillStyle = model.state.palette.claw;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(p[0], p[1], Math.max(5, radius), 0, Math.PI * 2);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(p[0] - radius - 4, p[1] + radius + 5);
      ctx.lineTo(p[0], p[1] + 3);
      ctx.lineTo(p[0] + radius + 4, p[1] + radius + 5);
      ctx.stroke();
    });
    ctx.fillStyle = "#d8eadc";
    ctx.font = "700 10px ui-monospace";
    ctx.fillText(
      `${camera.label} · FRAME T${frame.tick} · DELAY ${camera.delay}`,
      10,
      15,
    );
    document.querySelector(`.claw-feed-tick[data-view='${viewId}']`)
      .textContent = `T${frame.tick}`;
  }
  function drawFeeds() {
    Object.keys(model.state.cameras).forEach(drawFeed);
  }
  function updateHUD() {
    document.querySelector(".claw-speed").textContent = Math.hypot(
      ...model.velocity,
    ).toFixed(2);
    document.querySelector(".claw-grip-state").textContent = model.gripper
      .toUpperCase();
    document.querySelector(".claw-load-state").textContent = model.captured
      ? "LOAD"
      : "EMPTY";
    document.querySelector(".claw-tick").textContent = String(model.tick);
    document.querySelector(".claw-grip").textContent = model.gripper === "open"
      ? "CLOSE GRIPPER"
      : "OPEN / RELEASE";
  }
  async function submit() {
    if (model.submitting || model.terminal && !model.delivered) return;
    model.submitting = true;
    setMessage(
      "REPLAYING INERTIAL TICKS, SWEPT CAGE CONTACTS, AND STAGGERED FEEDS…",
      "pending",
    );
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      delivered: model.delivered,
      position: model.position.map(round),
      velocity: model.velocity.map(round),
      captured_id: model.captured,
      gripper: model.gripper,
      ticks: model.tick,
      collisions: model.collisions,
      resets: model.resets,
      feeds_seen: Object.keys(model.state.cameras).sort(),
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
        document.querySelector(".claw-captcha").insertAdjacentHTML(
          "beforeend",
          '<div class="claw-verdict"><small>STAGGERED CCTV CHAIN VERIFIED</small><strong>PASS</strong><span>INERTIA · MULTI-VIEW PROJECTION · GEOMETRIC DELIVERY</span></div>',
        );
        setMessage("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const root = document.querySelector(".claw-captcha");
        root.dataset.freshFailure = "true";
        root.insertAdjacentHTML(
          "afterbegin",
          '<div class="claw-fresh"><b>FAIL</b><span>RETRIEVAL REJECTED · FRESH CAGE ISSUED</span></div>',
        );
        const readout = document.querySelector(".readout");
        readout.textContent = "FAIL · FRESH THREE-CAMERA CAGE ISSUED";
        readout.dataset.status = "error";
        setTimeout(clearFresh, 1800);
      } else {
        model.submitting = false;
        setMessage("FAIL · NO AUTHORITATIVE CLAW GRADE", "error");
      }
    } catch (_) {
      model.submitting = false;
      setMessage("FAIL · CLAW VERIFIER OFFLINE", "error");
    }
  }
  async function render(state, helpers) {
    document.body.dataset.mechanic = "three-camera-claw-machine";
    helpers.app.innerHTML = `<section class="claw-captcha" data-challenge-id="${
      clean(state.challenge_id)
    }"><header class="claw-head"><div><span>REMOTE RECOVERY CELL / ${
      clean(state.challenge_id)
    }</span><h1>${
      clean(state.prompt)
    }</h1></div><p>NO DIRECT WINDOW<br><b>THREE DELAYED CAMERA CLOCKS</b></p></header><main class="claw-main"><section class="claw-feeds">${
      Object.entries(state.cameras).map(([id, camera]) =>
        `<article><header><b>${
          clean(camera.label)
        }</b><span class="claw-feed-tick" data-view="${id}">T0</span></header><canvas class="claw-feed" data-view="${id}" width="340" height="230"></canvas></article>`
      ).join("")
    }</section><aside class="claw-console"><span class="claw-kicker">SIX-AXIS INERTIAL GANTRY</span><h2>Correct what the cameras have not shown you yet.</h2><div class="claw-controls">${
      ["x", "y", "z"].map((axis) =>
        `<div><b>${axis.toUpperCase()} AXIS</b><button class="claw-control" data-axis="${axis}" data-direction="-1">${axis.toUpperCase()}−</button><button class="claw-control" data-axis="${axis}" data-direction="1">${axis.toUpperCase()}+</button></div>`
      ).join("")
    }</div><button class="claw-control claw-coast" data-axis="coast">COAST ONE PHYSICS TICK</button><button class="claw-control claw-brake" data-axis="brake">BRAKE / DAMP INERTIA</button><button class="claw-grip">CLOSE GRIPPER</button><button class="claw-reset">REWIND GANTRY</button><div class="claw-stats"><span>SPEED<b class="claw-speed">0.00</b></span><span>GRIP<b class="claw-grip-state">OPEN</b></span><span>LOAD<b class="claw-load-state">EMPTY</b></span><span>TICK<b class="claw-tick">0</b></span></div></aside><div class="claw-impact" data-visible="false"><b>CAGE CONTACT</b><span>RECOVER</span></div><div class="claw-complete" data-visible="false"><b>DELIVERY CONTAINED</b><span>MARKED LOAD IN CHUTE</span></div></main><footer class="claw-foot"><div><span>DELAY-AWARE PHYSICS REPLAY</span><div class="readout" data-status="idle">TRIANGULATE THE MARKED ARTIFACT</div></div><button class="claw-submit">${
      clean(state.submit_label)
    }</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    model = {
      state,
      helpers,
      events: [],
      position: [...state.initial.position],
      velocity: [...state.initial.velocity],
      objects: Object.fromEntries(
        state.objects.map(
          (obj) => [obj.id, { ...obj, center: [...obj.center] }],
        ),
      ),
      gripper: "open",
      captured: null,
      delivered: false,
      terminal: false,
      submitting: false,
      tick: 0,
      collisions: 0,
      resets: 0,
      history: {},
    };
    model.history[0] = snapshot();
    window.threeCameraClawMachineModel = model;
    document.querySelectorAll(".claw-control").forEach((button) =>
      button.addEventListener(
        "click",
        () =>
          applyControl(
            button.dataset.axis,
            Number(button.dataset.direction || 0),
          ),
      )
    );
    document.querySelector(".claw-grip").addEventListener("click", grip);
    document.querySelector(".claw-reset").addEventListener("click", resetClaw);
    document.querySelector(".claw-submit").addEventListener("click", submit);
    helpers.installCheatPanel();
    drawFeeds();
    updateHUD();
  }
  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.three_camera_claw_machine = {
    rootSelector: ".claw-captcha",
    render,
  };
})();
