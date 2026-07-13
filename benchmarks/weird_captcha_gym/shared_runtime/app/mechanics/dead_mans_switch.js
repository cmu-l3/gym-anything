(() => {
  "use strict";

  const KEY_TO_DIRECTION = {
    w: "N", arrowup: "N",
    d: "E", arrowright: "E",
    s: "S", arrowdown: "S",
    a: "W", arrowleft: "W",
  };
  const DELTAS = {N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0]};
  let model = null;
  let activeCleanup = null;

  function clonePoint(point) {
    return {x: Number(point.x), y: Number(point.y)};
  }

  function samePoint(a, b) {
    return Number(a.x) === Number(b.x) && Number(a.y) === Number(b.y);
  }

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function pushEvent(record) {
    const event = {seq: model.events.length + 1, t_ms: eventTime(), ...record};
    model.events.push(event);
    return event;
  }

  function pointKey(point) {
    return `${Number(point.x)},${Number(point.y)}`;
  }

  function pressureCenter(tMs = eventTime()) {
    const motion = model.state.pressure_motion;
    const phase = Number(motion.phase_milliradians) / 1000;
    const angle = Number(tMs) / Number(motion.period_ms) * Math.PI * 2 + phase;
    return {
      x: .5 + Number(motion.x_amplitude_milli) / 1000 * Math.sin(angle),
      y: .5 + Number(motion.y_amplitude_milli) / 1000 * Math.sin(angle * 2 + phase * .63),
    };
  }

  function normalizedPointer(event) {
    const track = document.querySelector(".pressure-track");
    const rect = track?.getBoundingClientRect();
    if (!rect) return null;
    return {
      x: Math.max(0, Math.min(1, (event.clientX - rect.left) / rect.width)),
      y: Math.max(0, Math.min(1, (event.clientY - rect.top) / rect.height)),
    };
  }

  function pressureContains(pointer, tMs = eventTime()) {
    if (!pointer) return false;
    const center = pressureCenter(tMs);
    const motion = model.state.pressure_motion;
    const dx = (Number(pointer.x) - center.x) / (Number(motion.hit_x_milli) / 1000);
    const dy = (Number(pointer.y) - center.y) / (Number(motion.hit_y_milli) / 1000);
    return dx * dx + dy * dy <= 1;
  }

  function updatePressureMotion() {
    if (!model) return;
    const tMs = eventTime();
    const center = pressureCenter(tMs);
    const pad = document.querySelector(".pressure-pad");
    if (pad) {
      pad.style.left = `${center.x * 100}%`;
      pad.style.top = `${center.y * 100}%`;
    }
    if (model.holding && !model.completed) {
      const inside = pressureContains(model.lastPointer, tMs);
      if (inside) {
        model.outsideSince = null;
        if (tMs - model.lastPressureSample >= Number(model.state.pressure_motion.sample_ms)) {
          pushEvent({type: "hold_sample", pointer: {x: Math.round(model.lastPointer.x * 1000), y: Math.round(model.lastPointer.y * 1000)}});
          model.lastPressureSample = tMs;
          model.pressureSamples += 1;
        }
      } else {
        if (model.outsideSince == null) model.outsideSince = tMs;
        if (tMs - model.outsideSince > Number(model.state.pressure_motion.outside_grace_ms)) {
          resetSuccessfulRun("pointerleave");
        }
      }
      maybeComplete();
    }
    const continuity = document.querySelector(".pressure-continuity i");
    const continuityText = document.querySelector(".pressure-continuity b");
    if (continuity && continuityText) {
      const started = model.events.find((event) => event.seq === model.currentHoldStartSeq);
      const elapsed = model.holding && started ? Math.max(0, tMs - Number(started.t_ms)) : 0;
      continuity.style.width = `${Math.min(100, elapsed / Number(model.state.pressure_motion.minimum_hold_ms) * 100)}%`;
      continuityText.textContent = `${(elapsed / 1000).toFixed(1)} / ${(Number(model.state.pressure_motion.minimum_hold_ms) / 1000).toFixed(1)}s`;
    }
    model.motionRaf = requestAnimationFrame(updatePressureMotion);
  }

  function installDeveloperReveal(state) {
    const form = document.getElementById("cheat-form");
    const input = document.getElementById("cheat-password");
    const output = document.getElementById("cheat-output");
    if (!form || !input || !output) return;
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      output.textContent = "";
      try {
        const response = await fetch("/cheat", {
          method: "POST",
          headers: {"content-type": "application/json"},
          body: JSON.stringify({password: input.value}),
        });
        if (!response.ok) {
          output.textContent = response.status === 404 ? "Disabled." : "Denied.";
          return;
        }
        const data = await response.json();
        output.textContent = `Route: ${(data.solution_path || []).join(" ")} · ${Number(data.minimum_success_moves || 0)} accepted moves`;
      } catch (_error) {
        output.textContent = "Unavailable.";
      }
    });
  }

  function updateScene() {
    if (!model) return;
    const {board} = model.state;
    const root = document.querySelector(".dead-switch-captcha");
    const vehicle = document.querySelector(".switch-vehicle");
    if (!root || !vehicle) return;
    root.dataset.holding = String(model.holding);
    root.dataset.completed = String(model.completed);
    vehicle.style.left = `${((model.position.x + 0.5) / Number(board.columns)) * 100}%`;
    vehicle.style.top = `${((model.position.y + 0.5) / Number(board.rows)) * 100}%`;
    vehicle.dataset.heading = model.heading;
    document.querySelectorAll(".switch-checkpoint").forEach((node) => {
      const order = Number(node.dataset.order || 0);
      node.dataset.passed = String(order <= model.checkpointIndex);
    });
    const pressureState = document.querySelector(".pressure-state");
    if (pressureState) pressureState.textContent = model.holding ? "CIRCUIT CLOSED" : "CIRCUIT OPEN";
    const progress = document.querySelector(".switch-route-progress b");
    if (progress) progress.textContent = `${model.checkpointIndex} / ${board.checkpoints.length}`;
    const resets = document.querySelector(".switch-reset-count b");
    if (resets) resets.textContent = String(model.resetCount).padStart(2, "0");
  }

  function showTerminalVerdict(kind, title, detail) {
    const root = document.querySelector(".dead-switch-captcha");
    const verdict = root?.querySelector(".switch-terminal-verdict");
    if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass");
    root.classList.toggle("is-failed", kind === "fail");
    verdict.innerHTML = `<b>${title}</b><span>${detail}</span>`;
    if (kind === "fail") {
      window.setTimeout(() => root.classList.remove("is-failed"), 1350);
    }
  }

  function clearTerminalVerdict() {
    const root = document.querySelector(".dead-switch-captcha");
    root?.classList.remove("is-failed");
    const verdict = root?.querySelector(".switch-terminal-verdict");
    if (verdict) verdict.replaceChildren();
  }

  function resetSuccessfulRun(reason) {
    if (!model || !model.holding || model.completed) return;
    pushEvent({type: "hold_end", reason, position: clonePoint(model.position)});
    model.holding = false;
    model.pointerId = null;
    model.position = clonePoint(model.state.board.start);
    model.checkpointIndex = 0;
    model.currentHoldStartSeq = null;
    model.lastPointer = null;
    model.lastPressureSample = 0;
    model.outsideSince = null;
    model.resetCount += 1;
    model.helpers.setReadout(`RESET ${String(model.resetCount).padStart(2, "0")} · HOLD AGAIN`, "error");
    const course = document.querySelector(".switch-course");
    if (course) {
      course.classList.remove("is-resetting");
      void course.offsetWidth;
      course.classList.add("is-resetting");
    }
    updateScene();
  }

  async function submitCompletion() {
    if (!model || model.submitting || model.completed) return;
    model.submitting = true;
    model.completed = true;
    const submittedAt = eventTime();
    const holdStartEvent = model.events.find((event) => event.seq === model.currentHoldStartSeq);
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      completed: true,
      holding: true,
      events: model.events,
      path: model.events.filter((event) => event.type === "move").map((event) => event.direction),
      visited_checkpoints: model.state.board.checkpoints.slice(0, model.checkpointIndex).map((item) => item.id),
      reset_count: model.resetCount,
      final_position: clonePoint(model.position),
      successful_hold_start_seq: model.currentHoldStartSeq,
      submitted_t_ms: submittedAt,
      continuous_hold_duration_ms: holdStartEvent ? submittedAt - Number(holdStartEvent.t_ms) : 0,
      pressure_sample_count: model.pressureSamples,
    };
    updateScene();
    model.helpers.setReadout("DOCK HANDSHAKE…", "idle");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        showTerminalVerdict("pass", "PASS", "CONTINUITY CONFIRMED");
        model.helpers.setReadout("PASS · CONTINUITY CONFIRMED", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) await render(outcome.state, model.helpers);
        showTerminalVerdict("fail", "FAIL", "COURSE REISSUED");
        model.helpers.setReadout("FAIL · COURSE REISSUED", "error");
      }
    } catch (_error) {
      model.completed = false;
      model.submitting = false;
      model.helpers.setReadout("LINK LOST · HOLD AND RETRY", "error");
      updateScene();
    }
  }

  function maybeComplete() {
    if (!model || !model.holding || model.completed || model.submitting) return;
    const board = model.state.board;
    if (!samePoint(model.position, board.goal) || model.checkpointIndex !== board.checkpoints.length) return;
    const holdStartEvent = model.events.find((event) => event.seq === model.currentHoldStartSeq);
    const duration = holdStartEvent ? eventTime() - Number(holdStartEvent.t_ms) : 0;
    if (duration < Number(model.state.pressure_motion.minimum_hold_ms)) {
      model.helpers.setReadout("DOCK READY · KEEP TRACKING UNTIL CONTINUITY FILLS", "pending");
      return;
    }
    if (eventTime() - model.lastPressureSample > Number(model.state.pressure_motion.maximum_sample_gap_ms)) return;
    submitCompletion();
  }

  function move(direction) {
    if (!model || !model.holding || model.completed) return;
    const before = clonePoint(model.position);
    const [dx, dy] = DELTAS[direction];
    const candidate = {x: before.x + dx, y: before.y + dy};
    const {board} = model.state;
    const accepted = (
      candidate.x >= 0 && candidate.x < Number(board.columns)
      && candidate.y >= 0 && candidate.y < Number(board.rows)
      && !model.walls.has(pointKey(candidate))
    );
    if (accepted) {
      model.position = candidate;
      model.heading = direction;
      const expected = board.checkpoints[model.checkpointIndex];
      if (expected && samePoint(candidate, expected)) {
        model.checkpointIndex += 1;
        model.helpers.setReadout(`CHECKPOINT ${model.checkpointIndex} LATCHED`, "idle");
      } else {
        model.helpers.setReadout("PRESSURE STABLE", "idle");
      }
    } else {
      model.helpers.setReadout("BULKHEAD · ROUTE BLOCKED", "error");
    }
    pushEvent({
      type: "move",
      direction,
      from: before,
      to: clonePoint(model.position),
      accepted,
      checkpoint_index: model.checkpointIndex,
    });
    updateScene();
    if (accepted && samePoint(model.position, board.goal) && model.checkpointIndex === board.checkpoints.length) {
      maybeComplete();
    }
  }

  async function abandonCourse() {
    if (!model || model.submitting || model.completed) return;
    model.submitting = true;
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({mechanic_id: model.state.mechanic_id, task_id: model.state.task_id, challenge_id: model.state.challenge_id, completed: false, events: []}),
      });
      const outcome = await response.json();
      if (outcome.state) await render(outcome.state, model.helpers);
      showTerminalVerdict("fail", "FAIL", "NEW COURSE ISSUED");
      model.helpers.setReadout("FAIL · NEW COURSE ISSUED", "error");
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("REISSUE FAILED", "error");
    }
  }

  async function render(state, helpers) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "dead-mans-switch";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const walls = new Set((state.board.walls || []).map(pointKey));
    model = {
      state,
      helpers,
      startedAt: performance.now(),
      events: [],
      position: clonePoint(state.board.start),
      checkpointIndex: 0,
      resetCount: 0,
      holding: false,
      completed: false,
      submitting: false,
      pointerId: null,
      currentHoldStartSeq: null,
      lastPointer: null,
      lastPressureSample: 0,
      outsideSince: null,
      pressureSamples: 0,
      motionRaf: 0,
      heading: "E",
      walls,
    };

    const cellRecords = [];
    for (let y = 0; y < Number(state.board.rows); y += 1) {
      for (let x = 0; x < Number(state.board.columns); x += 1) {
        const wall = walls.has(`${x},${y}`);
        const checkpoint = state.board.checkpoints.find((item) => Number(item.x) === x && Number(item.y) === y);
        const start = Number(state.board.start.x) === x && Number(state.board.start.y) === y;
        const goal = Number(state.board.goal.x) === x && Number(state.board.goal.y) === y;
        cellRecords.push(`<div class="switch-cell${wall ? " is-wall" : ""}${checkpoint ? " switch-checkpoint" : ""}${start ? " is-start" : ""}${goal ? " is-goal" : ""}" data-order="${checkpoint ? checkpoint.order : ""}" data-passed="false">${checkpoint ? `<span>${checkpoint.order}</span>` : ""}${goal ? "<i>DOCK</i>" : ""}</div>`);
      }
    }

    helpers.app.innerHTML = `
      <section class="dead-switch-captcha" data-holding="false" data-completed="false">
        <div class="switch-terminal-verdict" aria-live="assertive"></div>
        <header class="dead-switch-head">
          <div><span>CONTINUITY TRIAL / HOLD-07</span><h1>${helpers.text(state.prompt)}</h1></div>
          <div class="switch-live-lamp"><i></i><b>DEAD-MAN LINE</b></div>
        </header>
        <section class="dead-switch-workbench">
          <div class="switch-course-wrap">
            <div class="switch-course" style="--switch-columns:${Number(state.board.columns)};--switch-rows:${Number(state.board.rows)}">
              <div class="switch-course-grid">${cellRecords.join("")}</div>
              <div class="switch-vehicle" data-heading="E"><i></i><b></b><span></span></div>
            </div>
            <div class="switch-route-legend"><span>ORDERED RELAYS</span><b>${state.board.checkpoints.map((item) => item.order).join(" → ")} → DOCK</b></div>
          </div>
          <aside class="pressure-console">
            <div class="pressure-gauge"><i></i><b></b><span class="pressure-state">CIRCUIT OPEN</span></div>
            <div class="pressure-track"><button type="button" class="pressure-pad" aria-label="Track and hold the moving pressure plate"><span>KEEP<br>DEPRESSED</span><i></i><b></b></button><div class="pressure-continuity"><span></span><i></i><b>0.0 / ${(Number(state.pressure_motion.minimum_hold_ms) / 1000).toFixed(1)}s</b></div></div>
            <p>Follow the moving plate while held.<br>Steer with WASD or arrows.</p>
            <div class="switch-console-stats"><span class="switch-route-progress">RELAYS <b>0 / ${state.board.checkpoints.length}</b></span><span class="switch-reset-count">RESETS <b>00</b></span></div>
          </aside>
        </section>
        <footer class="dead-switch-foot"><div class="readout" data-status="idle">PRESS AND HOLD TO ARM</div><button type="button" class="switch-abandon">REISSUE COURSE</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>
    `;

    const pad = document.querySelector(".pressure-pad");
    const keydown = (event) => {
      const direction = KEY_TO_DIRECTION[String(event.key || "").toLowerCase()];
      if (!direction || event.repeat || !model || model.completed) return;
      event.preventDefault();
      if (!model.holding) {
        helpers.setReadout("PRESSURE REQUIRED", "error");
        return;
      }
      move(direction);
    };
    const pointerdown = (event) => {
      if (!model || model.completed || model.holding || event.button !== 0) return;
      event.preventDefault();
      clearTerminalVerdict();
      model.holding = true;
      model.pointerId = event.pointerId;
      model.lastPointer = normalizedPointer(event);
      if (!pressureContains(model.lastPointer)) { model.holding = false; model.pointerId = null; return; }
      try { pad.setPointerCapture(event.pointerId); } catch (_error) { /* capture is best effort */ }
      const started = pushEvent({type: "hold_start", position: clonePoint(model.position), pointer: {x: Math.round(model.lastPointer.x * 1000), y: Math.round(model.lastPointer.y * 1000)}});
      model.currentHoldStartSeq = started.seq;
      model.lastPressureSample = started.t_ms;
      model.outsideSince = null;
      helpers.setReadout("CIRCUIT CLOSED · STEER NOW", "idle");
      updateScene();
    };
    const pointermove = (event) => {
      if (!model?.holding || event.pointerId !== model.pointerId || model.completed) return;
      model.lastPointer = normalizedPointer(event);
    };
    const pointerup = (event) => {
      if (model?.holding && event.pointerId === model.pointerId) resetSuccessfulRun("pointerup");
    };
    const pointercancel = (event) => {
      if (model?.holding && event.pointerId === model.pointerId) resetSuccessfulRun("pointercancel");
    };
    const lostcapture = () => {
      if (model?.holding && !model.completed) resetSuccessfulRun("lostcapture");
    };
    const blur = () => {
      if (model?.holding && !model.completed) resetSuccessfulRun("blur");
    };
    pad.addEventListener("pointerdown", pointerdown);
    pad.addEventListener("lostpointercapture", lostcapture);
    window.addEventListener("pointermove", pointermove);
    window.addEventListener("pointerup", pointerup);
    window.addEventListener("pointercancel", pointercancel);
    window.addEventListener("keydown", keydown);
    window.addEventListener("blur", blur);
    document.querySelector(".switch-abandon")?.addEventListener("click", abandonCourse);
    installDeveloperReveal(state);
    activeCleanup = () => {
      if (model?.motionRaf) cancelAnimationFrame(model.motionRaf);
      pad.removeEventListener("pointerdown", pointerdown);
      pad.removeEventListener("lostpointercapture", lostcapture);
      window.removeEventListener("pointermove", pointermove);
      window.removeEventListener("pointerup", pointerup);
      window.removeEventListener("pointercancel", pointercancel);
      window.removeEventListener("keydown", keydown);
      window.removeEventListener("blur", blur);
    };
    updateScene();
    model.motionRaf = requestAnimationFrame(updatePressureMotion);
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.dead_mans_switch = {rootSelector: ".dead-switch-captcha", render};
})();
