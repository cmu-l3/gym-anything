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

  function cloneOrientation(orientation) {
    return {
      top: Number(orientation.top), bottom: Number(orientation.bottom),
      north: Number(orientation.north), south: Number(orientation.south),
      east: Number(orientation.east), west: Number(orientation.west),
    };
  }

  function samePoint(a, b) {
    return Number(a.x) === Number(b.x) && Number(a.y) === Number(b.y);
  }

  function pointKey(point) {
    return `${Number(point.x)},${Number(point.y)}`;
  }

  function roll(orientation, direction) {
    const old = cloneOrientation(orientation);
    if (direction === "N") return {top: old.south, bottom: old.north, north: old.top, south: old.bottom, east: old.east, west: old.west};
    if (direction === "S") return {top: old.north, bottom: old.south, north: old.bottom, south: old.top, east: old.east, west: old.west};
    if (direction === "E") return {top: old.west, bottom: old.east, north: old.north, south: old.south, east: old.top, west: old.bottom};
    return {top: old.east, bottom: old.west, north: old.north, south: old.south, east: old.bottom, west: old.top};
  }

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function pushAction(record) {
    const action = {seq: model.actions.length + 1, t_ms: eventTime(), ...record};
    model.actions.push(action);
    return action;
  }

  function currentScanner() {
    return (model.state.board.scanners || []).find((scanner) => samePoint(scanner, model.position));
  }

  function orientationMarkup(orientation, hidden) {
    const value = (face) => hidden ? "?" : Number(orientation[face]);
    return `
      <div class="courier-cube${hidden ? " is-blind" : ""}">
        <i class="cube-face cube-top">${value("top")}</i>
        <i class="cube-face cube-front">${value("south")}</i>
        <i class="cube-face cube-side">${value("east")}</i>
      </div>
      <div class="orientation-net">
        <span>N <b>${value("north")}</b></span><span>TOP <b>${value("top")}</b></span><span>E <b>${value("east")}</b></span>
        <span>W <b>${value("west")}</b></span><span>BOT <b>${value("bottom")}</b></span><span>S <b>${value("south")}</b></span>
      </div>`;
  }

  function installDeveloperReveal() {
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
        const gateTrace = (data.solution_trace || [])
          .map((step) => `${step.step}:${step.direction}/T${step.orientation?.top}`)
          .join(" ");
        output.textContent = `Route: ${(data.solution_path || []).join(" ")} · Trace: ${gateTrace}`;
      } catch (_error) {
        output.textContent = "Unavailable.";
      }
    });
  }

  function updateScene({blockedGate = null} = {}) {
    if (!model) return;
    const {board} = model.state;
    const root = document.querySelector(".blind-dice-captcha");
    const token = document.querySelector(".courier-token");
    if (!root || !token) return;
    token.style.left = `${((model.position.x + 0.5) / Number(board.columns)) * 100}%`;
    token.style.top = `${((model.position.y + 0.5) / Number(board.rows)) * 100}%`;
    token.dataset.blind = String(!(model.initialReveal || currentScanner()));
    token.innerHTML = `<b>${model.initialReveal || currentScanner() ? model.orientation.top : "?"}</b><i></i>`;
    document.querySelectorAll(".dice-gate").forEach((gate) => {
      gate.dataset.crossed = String(model.crossings.includes(gate.dataset.gateId));
      gate.dataset.blocked = String(blockedGate === gate.dataset.gateId);
    });
    const reveal = model.initialReveal || Boolean(currentScanner());
    const panel = document.querySelector(".dice-orientation-panel");
    if (panel) {
      panel.dataset.revealed = String(reveal);
      panel.innerHTML = `<span class="orientation-kicker">${model.initialReveal ? "INITIAL SEAL" : currentScanner() ? "SCANNER LIVE" : "SIGNAL LOST"}</span>${orientationMarkup(model.orientation, !reveal)}`;
    }
    const gates = document.querySelector(".dice-crossing-count b");
    if (gates) gates.textContent = `${model.crossings.length} / ${board.gates.length}`;
    const rolls = document.querySelector(".dice-roll-count b");
    if (rolls) rolls.textContent = String(model.actions.filter((item) => item.type === "move").length).padStart(2, "0");
    root.dataset.completed = String(model.completed);
  }

  function showTerminalVerdict(kind, title, detail) {
    const root = document.querySelector(".blind-dice-captcha");
    const verdict = root?.querySelector(".dice-terminal-verdict");
    if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass");
    root.classList.toggle("is-failed", kind === "fail");
    verdict.innerHTML = `<b>${title}</b><span>${detail}</span>`;
    if (kind === "fail") {
      window.setTimeout(() => root.classList.remove("is-failed"), 1350);
    }
  }

  function clearTerminalVerdict() {
    const root = document.querySelector(".blind-dice-captcha");
    root?.classList.remove("is-failed");
    const verdict = root?.querySelector(".dice-terminal-verdict");
    if (verdict) verdict.replaceChildren();
  }

  function resetCourier() {
    if (!model || model.completed) return;
    clearTerminalVerdict();
    model.position = clonePoint(model.state.board.start);
    model.orientation = cloneOrientation(model.state.initial_orientation);
    model.crossings = [];
    model.initialReveal = true;
    model.resetCount += 1;
    pushAction({type: "reset", position: clonePoint(model.position), orientation: cloneOrientation(model.orientation)});
    model.helpers.setReadout("MANIFEST RESET · INITIAL ORIENTATION RESTORED", "idle");
    updateScene();
  }

  async function submitDelivery() {
    if (!model || model.submitting || model.completed) return;
    model.submitting = true;
    model.completed = true;
    updateScene();
    model.helpers.setReadout("DISPATCH SCANNING…", "idle");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      completed: true,
      actions: model.actions,
      path: model.actions.filter((item) => item.type === "move").map((item) => item.direction),
      gate_crossings: model.crossings,
      reset_count: model.resetCount,
      final_position: clonePoint(model.position),
      final_orientation: cloneOrientation(model.orientation),
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        showTerminalVerdict("pass", "PASS", "SEALED CARGO ACCEPTED");
        model.helpers.setReadout("PASS · SEALED CARGO ACCEPTED", "passed");
      } else if (outcome.passed === false) {
        if (outcome.state) await render(outcome.state, model.helpers);
        showTerminalVerdict("fail", "FAIL", "MANIFEST REISSUED");
        model.helpers.setReadout("FAIL · MANIFEST REISSUED", "error");
      }
    } catch (_error) {
      model.completed = false;
      model.submitting = false;
      model.helpers.setReadout("DISPATCH LINK LOST", "error");
      updateScene();
    }
  }

  function move(direction) {
    if (!model || model.completed) return;
    clearTerminalVerdict();
    model.initialReveal = false;
    const before = clonePoint(model.position);
    const [dx, dy] = DELTAS[direction];
    const candidate = {x: before.x + dx, y: before.y + dy};
    let accepted = model.openCells.has(pointKey(candidate));
    let nextOrientation = accepted ? roll(model.orientation, direction) : cloneOrientation(model.orientation);
    const gate = accepted ? model.gatesByCell.get(pointKey(candidate)) : null;
    if (gate && Number(nextOrientation.top) !== Number(gate.required_top)) {
      accepted = false;
      nextOrientation = cloneOrientation(model.orientation);
    }
    if (accepted) {
      model.position = candidate;
      model.orientation = nextOrientation;
      if (gate && !model.crossings.includes(gate.id)) model.crossings.push(gate.id);
      model.helpers.setReadout(currentScanner() ? "SCANNER LOCK · ORIENTATION REVEALED" : gate ? `GATE ${gate.required_top} CLEARED` : "ROLL ACCEPTED", "idle");
    } else if (gate) {
      model.helpers.setReadout(`GATE REJECTED · NEED TOP ${gate.required_top}`, "error");
    } else {
      model.helpers.setReadout("AISLE CLOSED", "error");
    }
    pushAction({
      type: "move",
      direction,
      from: before,
      to: clonePoint(model.position),
      accepted,
      gate_id: gate ? gate.id : null,
      orientation_after: cloneOrientation(model.orientation),
    });
    updateScene({blockedGate: gate && !accepted ? gate.id : null});
    if (accepted && samePoint(model.position, model.state.board.goal) && model.crossings.length === model.state.board.gates.length) {
      window.setTimeout(submitDelivery, 240);
    }
  }

  async function abandonManifest() {
    if (!model || model.submitting || model.completed) return;
    model.submitting = true;
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({mechanic_id: model.state.mechanic_id, task_id: model.state.task_id, challenge_id: model.state.challenge_id, completed: false, actions: []}),
      });
      const outcome = await response.json();
      if (outcome.state) await render(outcome.state, model.helpers);
      showTerminalVerdict("fail", "FAIL", "NEW MANIFEST ISSUED");
      model.helpers.setReadout("FAIL · NEW MANIFEST ISSUED", "error");
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("REISSUE FAILED", "error");
    }
  }

  async function render(state, helpers) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "blind-dice-courier";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const openCells = new Set((state.board.open_cells || []).map(pointKey));
    const gatesByCell = new Map((state.board.gates || []).map((gate) => [pointKey(gate), gate]));
    const scannersByCell = new Map((state.board.scanners || []).map((scanner) => [pointKey(scanner), scanner]));
    model = {
      state,
      helpers,
      startedAt: performance.now(),
      actions: [],
      position: clonePoint(state.board.start),
      orientation: cloneOrientation(state.initial_orientation),
      crossings: [],
      resetCount: 0,
      initialReveal: true,
      completed: false,
      submitting: false,
      openCells,
      gatesByCell,
    };

    const cells = [];
    for (let y = 0; y < Number(state.board.rows); y += 1) {
      for (let x = 0; x < Number(state.board.columns); x += 1) {
        const key = `${x},${y}`;
        const open = openCells.has(key);
        const gate = gatesByCell.get(key);
        const scanner = scannersByCell.get(key);
        const start = Number(state.board.start.x) === x && Number(state.board.start.y) === y;
        const goal = Number(state.board.goal.x) === x && Number(state.board.goal.y) === y;
        const classes = ["dice-cell", open ? "is-open" : "is-void", gate ? "dice-gate" : "", scanner ? "dice-scanner" : "", start ? "is-start" : "", goal ? "is-goal" : ""].filter(Boolean).join(" ");
        cells.push(`<div class="${classes}" data-gate-id="${gate ? gate.id : ""}" data-crossed="false" data-blocked="false">${gate ? `<span class="gate-face"><i>TOP</i><b>${gate.required_top}</b></span>` : ""}${scanner ? "<span class=\"scanner-mark\"><i></i><b>SCAN</b></span>" : ""}${goal ? "<span class=\"dispatch-mark\">DISPATCH</span>" : ""}</div>`);
      }
    }

    helpers.app.innerHTML = `
      <section class="blind-dice-captcha" data-completed="false" tabindex="0">
        <div class="dice-terminal-verdict" aria-live="assertive"></div>
        <header class="blind-dice-head">
          <div><span>ORIENTATION-SEALED FREIGHT / D6</span><h1>${helpers.text(state.prompt)}</h1></div>
          <div class="dice-manifest-mark">BLIND<br><b>COURIER</b></div>
        </header>
        <section class="blind-dice-workbench">
          <div class="dice-board-wrap">
            <div class="dice-board" style="--dice-columns:${Number(state.board.columns)};--dice-rows:${Number(state.board.rows)}">
              <div class="dice-grid">${cells.join("")}</div>
              <div class="courier-token" data-blind="false"><b>${Number(state.initial_orientation.top)}</b><i></i></div>
            </div>
            <div class="dice-board-caption"><span>WASD / ARROWS TO ROLL</span><b>GATES READ THE TOP FACE AFTER THE ROLL</b></div>
          </div>
          <aside class="dice-console">
            <div class="dice-orientation-panel" data-revealed="true"></div>
            <div class="gate-orders">
              <span>FACE GATES</span>
              ${(state.board.gates || []).map((gate, index) => `<div class="gate-order gate-${gate.tone}"><i>${index + 1}</i><b>TOP ${gate.required_top}</b></div>`).join("")}
            </div>
            <div class="dice-console-stats"><span class="dice-crossing-count">CROSSED <b>0 / ${state.board.gates.length}</b></span><span class="dice-roll-count">ROLLS <b>00</b></span></div>
            <button type="button" class="dice-reset">RESET CRATE</button>
          </aside>
        </section>
        <footer class="blind-dice-foot"><div class="readout" data-status="idle">INITIAL ORIENTATION UNSEALED UNTIL FIRST ROLL</div><button type="button" class="dice-abandon">REISSUE MANIFEST</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>
    `;

    const shell = document.querySelector(".blind-dice-captcha");
    const keydown = (event) => {
      if (!model || model.completed || event.repeat) return;
      const key = String(event.key || "").toLowerCase();
      if (key === "r") {
        event.preventDefault();
        resetCourier();
        return;
      }
      const direction = KEY_TO_DIRECTION[key];
      if (!direction) return;
      event.preventDefault();
      move(direction);
    };
    window.addEventListener("keydown", keydown);
    document.querySelector(".dice-reset")?.addEventListener("click", resetCourier);
    document.querySelector(".dice-abandon")?.addEventListener("click", abandonManifest);
    installDeveloperReveal();
    activeCleanup = () => window.removeEventListener("keydown", keydown);
    updateScene();
    shell?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.blind_dice_courier = {rootSelector: ".blind-dice-captcha", render};
})();
