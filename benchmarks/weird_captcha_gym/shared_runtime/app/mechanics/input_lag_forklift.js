(() => {
  "use strict";

  const DELTAS = {
    UP: [0, -1],
    RIGHT: [1, 0],
    DOWN: [0, 1],
    LEFT: [-1, 0],
  };
  const GLYPHS = {UP: "↑", RIGHT: "→", DOWN: "↓", LEFT: "←"};
  let helpersCache = null;
  let keyHandler = null;
  let model = null;

  function pointKey(point) {
    return `${Number(point[0])},${Number(point[1])}`;
  }

  function clonePoints(points) {
    return (points || []).map((point) => [Number(point[0]), Number(point[1])]);
  }

  function snapshot() {
    return {
      player: [model.player[0], model.player[1]],
      crates: clonePoints(model.crates).sort((a, b) => a[0] - b[0] || a[1] - b[1]),
    };
  }

  function samePoint(first, second) {
    return first[0] === second[0] && first[1] === second[1];
  }

  function executeDirection(direction) {
    const [dx, dy] = DELTAS[direction];
    const target = [model.player[0] + dx, model.player[1] + dy];
    const targetKey = pointKey(target);
    if (model.walls.has(targetKey)) return "collision_wall";
    const crateIndex = model.crates.findIndex((crate) => samePoint(crate, target));
    if (crateIndex < 0) {
      model.player = target;
      return "move";
    }
    const beyond = [target[0] + dx, target[1] + dy];
    if (model.walls.has(pointKey(beyond)) || model.crates.some((crate) => samePoint(crate, beyond))) {
      return "collision_crate_blocked";
    }
    model.crates[crateIndex] = beyond;
    model.player = target;
    return "push";
  }

  function allCratesDocked() {
    const crates = new Set(model.crates.map(pointKey));
    return crates.size === model.goals.size && Array.from(model.goals).every((goal) => crates.has(goal));
  }

  function outcomeLabel(outcome) {
    return {
      queued: "NOTHING / QUEUED",
      move: "FORKLIFT MOVED",
      push: "CRATE PUSHED",
      collision_wall: "RACK COLLISION",
      collision_crate_blocked: "LOAD BLOCKED",
      flushed_empty: "QUEUE ALREADY EMPTY",
      recalibrated: "ORIGIN RESTORED",
    }[outcome] || outcome;
  }

  function renderBoard() {
    document.querySelectorAll(".forklift-cell").forEach((cell) => {
      const key = `${cell.dataset.x},${cell.dataset.y}`;
      const playerHere = key === pointKey(model.player);
      const crateHere = model.crates.some((crate) => pointKey(crate) === key);
      cell.classList.toggle("has-forklift", playerHere);
      cell.classList.toggle("has-crate", crateHere);
      cell.classList.toggle("is-docked", crateHere && model.goals.has(key));
    });
  }

  function renderTape() {
    const tape = document.getElementById("forklift-tape");
    if (!tape) return;
    const rows = model.events.slice(-6).reverse();
    tape.innerHTML = rows.length ? rows.map((event) => {
      const pressed = event.issued in GLYPHS ? `${GLYPHS[event.issued]} ${event.issued}` : event.issued;
      const executed = event.executed ? `${GLYPHS[event.executed]} ${event.executed}` : "—";
      return `<li data-outcome="${event.outcome}"><b>${String(event.sequence).padStart(2, "0")}</b><span>${pressed}</span><i>${executed}</i><em>${outcomeLabel(event.outcome)}</em></li>`;
    }).join("") : '<li class="is-empty"><b>00</b><span>NO INPUT</span><i>—</i><em>CALIBRATED</em></li>';
  }

  function renderTelemetry(issued, executed, outcome) {
    const pressed = document.getElementById("forklift-pressed");
    const ran = document.getElementById("forklift-executed");
    const queue = document.getElementById("forklift-pending");
    const collisionCounter = document.getElementById("forklift-collisions");
    const resetCounter = document.getElementById("forklift-resets");
    if (pressed) pressed.innerHTML = issued ? `<b>${GLYPHS[issued] || "⟲"}</b><span>${issued}</span>` : '<b>—</b><span>WAITING</span>';
    if (ran) ran.innerHTML = executed ? `<b>${GLYPHS[executed]}</b><span>${executed}<small>${outcomeLabel(outcome)}</small></span>` : `<b>∅</b><span>${outcomeLabel(outcome || "queued")}</span>`;
    if (queue) {
      queue.dataset.empty = model.pending ? "false" : "true";
      queue.innerHTML = model.pending ? `<span>${GLYPHS[model.pending]}</span><b>${model.pending}</b>` : "<span>∅</span><b>EMPTY</b>";
    }
    if (collisionCounter) collisionCounter.textContent = String(model.collisions).padStart(2, "0");
    if (resetCounter) resetCounter.textContent = String(model.calibrationHistory.length).padStart(2, "0");
  }

  function updateCertification() {
    const ready = allCratesDocked() && model.pending === null && model.events.at(-1)?.issued === "FLUSH";
    const button = document.getElementById("forklift-certify");
    const manifest = document.getElementById("forklift-manifest-state");
    if (button) button.classList.toggle("is-ready", ready);
    if (manifest) {
      manifest.dataset.ready = ready ? "true" : "false";
      manifest.textContent = ready ? "BAY LOCKED · QUEUE EMPTY" : allCratesDocked() ? "ON BAY · EMPTY THE QUEUE" : "LOAD IN TRANSIT";
    }
  }

  function recordCommand(issued) {
    if (!model || model.submitting || model.terminal) return;
    const sequence = model.events.length + 1;
    const before = snapshot();
    const pendingBefore = model.pending;
    let executed = null;
    let outcome;
    let type;

    if (issued in DELTAS) {
      type = "direction";
      if (model.pending === null) {
        outcome = "queued";
      } else {
        executed = model.pending;
        outcome = executeDirection(executed);
      }
      model.pending = issued;
    } else if (issued === "FLUSH") {
      type = "flush";
      if (model.pending === null) {
        outcome = "flushed_empty";
      } else {
        executed = model.pending;
        outcome = executeDirection(executed);
      }
      model.pending = null;
    } else if (issued === "RESET") {
      type = "reset";
      outcome = "recalibrated";
      model.player = [...model.initial.player];
      model.crates = clonePoints(model.initial.crates);
      model.pending = null;
      model.calibrationHistory.push({sequence, reason: "operator_recalibration"});
    } else {
      return;
    }

    if (outcome.startsWith("collision_")) {
      model.collisions += 1;
      const board = document.querySelector(".forklift-board-shell");
      board?.classList.remove("is-collision");
      void board?.offsetWidth;
      board?.classList.add("is-collision");
    }
    model.events.push({
      sequence,
      type,
      issued,
      pending_before: pendingBefore,
      executed,
      outcome,
      before,
      after: snapshot(),
      pending_after: model.pending,
    });
    renderBoard();
    renderTape();
    renderTelemetry(issued, executed, outcome);
    updateCertification();
    helpersCache.setReadout(
      outcome.startsWith("collision_") ? `${outcomeLabel(outcome)} · STATE HELD` :
        allCratesDocked() && model.pending === null ? "LOAD ALIGNED · READY TO CERTIFY" :
          "ONE-CYCLE DELAY ACTIVE",
      outcome.startsWith("collision_") ? "error" : "idle",
    );
  }

  async function certify() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    const button = document.getElementById("forklift-certify");
    if (button) button.disabled = true;
    helpersCache.setReadout("AUDITING COMMAND TAPE…", "idle");
    const completed = allCratesDocked() && model.pending === null && model.events.at(-1)?.issued === "FLUSH";
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      issued_commands: model.events,
      final_state: snapshot(),
      pending_command: model.pending,
      collisions: model.collisions,
      reset_count: model.calibrationHistory.length,
      calibration_history: model.calibrationHistory,
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
        model.terminal = true;
        document.querySelector(".forklift-captcha")?.classList.add("is-pass");
        const verdict = document.getElementById("forklift-verdict");
        if (verdict) verdict.innerHTML = "<b>PASS</b><span>LOAD MANIFEST VERIFIED</span>";
        helpersCache.setReadout("PASS", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) await helpersCache.render(outcome.state);
        helpersCache.setReadout("FAIL · LOAD REJECTED / FRESH SHIFT", "error");
      } else {
        helpersCache.setReadout("AUDIT UNAVAILABLE", "error");
        model.submitting = false;
        if (button) button.disabled = false;
      }
    } catch (_error) {
      helpersCache.setReadout("AUDIT LINK OFFLINE", "error");
      model.submitting = false;
      if (button) button.disabled = false;
    }
  }

  function boardCells(state) {
    const warehouse = state.warehouse;
    const walls = new Set((warehouse.walls || []).map(pointKey));
    const goals = new Set((warehouse.goals || []).map(pointKey));
    const cells = [];
    for (let y = 0; y < Number(warehouse.height); y += 1) {
      for (let x = 0; x < Number(warehouse.width); x += 1) {
        const key = `${x},${y}`;
        const wall = walls.has(key);
        const goal = goals.has(key);
        cells.push(`<div class="forklift-cell${wall ? " is-wall" : ""}${goal ? " is-goal" : ""}" data-x="${x}" data-y="${y}">
          ${wall ? '<span class="rack"><i></i><i></i><i></i></span>' : ""}
          ${goal ? '<span class="loading-bay"><b>LOAD</b><i></i></span>' : ""}
          <span class="warehouse-crate"><b>FRAGILE</b><i></i></span>
          <span class="warehouse-forklift"><b></b><i></i><i></i><em></em></span>
        </div>`);
      }
    }
    return cells.join("");
  }

  async function render(state, helpers) {
    helpersCache = helpers || helpersCache;
    if (!helpersCache) throw new Error("input_lag_forklift requires runtime helpers");
    if (keyHandler) window.removeEventListener("keydown", keyHandler);
    const warehouse = state.warehouse || {};
    document.body.dataset.mechanic = "input-lag-forklift";
    document.body.dataset.forkliftPalette = state.palette || "amber";
    document.body.dataset.cheatMode = helpersCache.isCheatMode() ? "true" : "false";
    model = {
      state,
      initial: {player: clonePoints([warehouse.player])[0], crates: clonePoints(warehouse.crates)},
      player: clonePoints([warehouse.player])[0],
      crates: clonePoints(warehouse.crates),
      walls: new Set((warehouse.walls || []).map(pointKey)),
      goals: new Set((warehouse.goals || []).map(pointKey)),
      pending: null,
      events: [],
      collisions: 0,
      calibrationHistory: [],
      submitting: false,
      terminal: false,
    };
    window.inputLagForkliftModel = model;
    helpersCache.app.innerHTML = `<section class="forklift-captcha" data-challenge-id="${helpersCache.text(state.challenge_id)}" tabindex="0">
      <header class="forklift-head">
        <div class="forklift-brand"><span>SHIFT CONTROL / BAY 04</span><h1>${helpersCache.text(state.prompt)}</h1></div>
        <div class="forklift-lag-badge"><i></i><span>CONTROL LINK</span><b>+1 CYCLE</b></div>
      </header>
      <main class="forklift-workspace">
        <section class="forklift-board-shell" aria-label="warehouse floor">
          <div class="forklift-grid" style="--cols:${Number(warehouse.width)};--rows:${Number(warehouse.height)}">${boardCells(state)}</div>
          <div class="forklift-coordinate-tag">WHS-${helpersCache.text(state.challenge_id).toUpperCase()}</div>
          <div class="forklift-verdict" id="forklift-verdict"><b>LIVE</b><span>MANIFEST OPEN</span></div>
        </section>
        <aside class="forklift-console">
          <div class="console-title"><span>DELAY COMPENSATOR</span><i>CALIBRATED</i></div>
          <div class="forklift-signal-flow">
            <section><label>PRESSED NOW</label><div id="forklift-pressed"><b>—</b><span>WAITING</span></div></section>
            <strong>≠</strong>
            <section><label>EXECUTED NOW</label><div id="forklift-executed"><b>∅</b><span>NOTHING / QUEUED</span></div></section>
          </div>
          <div class="forklift-queue-panel"><label>PENDING / NEXT CYCLE</label><div id="forklift-pending" data-empty="true"><span>∅</span><b>EMPTY</b></div></div>
          <div class="forklift-keypad" aria-label="forklift direction controls">
            <button type="button" data-command="UP" aria-label="queue up"><kbd>W</kbd><b>↑</b></button>
            <button type="button" data-command="LEFT" aria-label="queue left"><kbd>A</kbd><b>←</b></button>
            <button type="button" data-command="DOWN" aria-label="queue down"><kbd>S</kbd><b>↓</b></button>
            <button type="button" data-command="RIGHT" aria-label="queue right"><kbd>D</kbd><b>→</b></button>
          </div>
          <button class="forklift-flush" id="forklift-flush" type="button"><kbd>F</kbd><span>EXECUTE QUEUE</span><small>RUN PENDING · ADD NOTHING</small></button>
          <div class="forklift-counters"><span>IMPACTS <b id="forklift-collisions">00</b></span><span>RESETS <b id="forklift-resets">00</b></span></div>
        </aside>
      </main>
      <section class="forklift-tape-wrap"><div><label>COMMAND TAPE</label><p>INPUT</p><p>EXECUTED</p><p>PHYSICAL RESULT</p></div><ol id="forklift-tape"></ol></section>
      <footer class="forklift-foot">
        <button class="forklift-reset" id="forklift-reset" type="button">↺ RECALIBRATE</button>
        <div><span id="forklift-manifest-state">LOAD IN TRANSIT</span><div class="readout" data-status="idle">ONE-CYCLE DELAY ACTIVE</div></div>
        <button class="forklift-certify" id="forklift-certify" type="button">${helpersCache.text(state.submit_label || "CERTIFY LOAD")} →</button>
      </footer>
    </section>`;

    document.querySelectorAll("[data-command]").forEach((button) => button.addEventListener("click", () => recordCommand(button.dataset.command)));
    document.getElementById("forklift-flush")?.addEventListener("click", () => recordCommand("FLUSH"));
    document.getElementById("forklift-reset")?.addEventListener("click", () => recordCommand("RESET"));
    document.getElementById("forklift-certify")?.addEventListener("click", certify);
    keyHandler = (event) => {
      if (event.repeat || model?.submitting || model?.terminal) return;
      const key = event.key.toLowerCase();
      const command = {
        arrowup: "UP", w: "UP",
        arrowright: "RIGHT", d: "RIGHT",
        arrowdown: "DOWN", s: "DOWN",
        arrowleft: "LEFT", a: "LEFT",
      }[key];
      if (command) {
        event.preventDefault();
        recordCommand(command);
      } else if (key === "f") {
        event.preventDefault();
        recordCommand("FLUSH");
      } else if (key === "r") {
        event.preventDefault();
        recordCommand("RESET");
      }
    };
    window.addEventListener("keydown", keyHandler);
    renderBoard();
    renderTape();
    renderTelemetry(null, null, null);
    updateCertification();
    document.querySelector(".forklift-captcha")?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.input_lag_forklift = {
    rootSelector: ".forklift-captcha",
    render,
  };
})();
