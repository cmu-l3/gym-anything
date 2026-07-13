(() => {
  "use strict";

  const DIRECTIONS = {N: [0, -1], E: [1, 0], S: [0, 1], W: [-1, 0]};
  const OPPOSITE = {N: "S", E: "W", S: "N", W: "E"};
  const KEY_DIRECTIONS = {
    w: "N", arrowup: "N",
    d: "E", arrowright: "E",
    s: "S", arrowdown: "S",
    a: "W", arrowleft: "W",
  };
  const PIPS = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };
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

  function pointKey(point) {
    return `${Number(point.x)},${Number(point.y)}`;
  }

  function samePoint(a, b) {
    return Number(a.x) === Number(b.x) && Number(a.y) === Number(b.y);
  }

  function roll(orientation, direction) {
    const old = cloneOrientation(orientation);
    if (direction === "N") return {top: old.south, bottom: old.north, north: old.top, south: old.bottom, east: old.east, west: old.west};
    if (direction === "S") return {top: old.north, bottom: old.south, north: old.bottom, south: old.top, east: old.east, west: old.west};
    if (direction === "E") return {top: old.west, bottom: old.east, north: old.north, south: old.south, east: old.top, west: old.bottom};
    return {top: old.east, bottom: old.west, north: old.north, south: old.south, east: old.bottom, west: old.top};
  }

  function screenToWorld(direction) {
    return model.view === 0 ? direction : OPPOSITE[direction];
  }

  function displayPoint(point) {
    if (model.view === 0) return clonePoint(point);
    return {
      x: Number(model.state.board.columns) - 1 - Number(point.x),
      y: Number(model.state.board.rows) - 1 - Number(point.y),
    };
  }

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function pushEvent(event) {
    const item = {seq: model.events.length + 1, t_ms: eventTime(), ...event};
    model.events.push(item);
    return item;
  }

  function isVisible(die) {
    return die.initialReveal || die.scannerCells.has(pointKey(die.position)) || die.docked;
  }

  function pipMarkup(value) {
    const active = new Set(PIPS[Number(value)] || []);
    return `<span class="foundry-pip-face" aria-label="top face ${Number(value)}">${Array.from({length: 9}, (_, index) => `<i data-lit="${active.has(index)}"></i>`).join("")}</span>`;
  }

  function dieFaceMarkup(die) {
    if (!isVisible(die)) {
      return `<span class="foundry-face-seal"><i></i><b>SEALED</b></span>`;
    }
    return pipMarkup(die.orientation.top);
  }

  function settleProfile(delta) {
    if (delta === 0) return [26, -16, 10, -6, 3, -1, 0];
    const bias = Math.max(-34, Math.min(34, delta * 6));
    return [bias + 22, bias - 13, bias + 8, bias - 5, bias + 3, bias - 1, bias];
  }

  function topSum() {
    return [...model.dice.values()].reduce((sum, die) => sum + (die.docked ? Number(die.orientation.top) : 0), 0);
  }

  function clearTimers() {
    if (!model) return;
    for (const timer of model.timers) window.clearTimeout(timer);
    model.timers.clear();
  }

  function later(callback, delay) {
    const timer = window.setTimeout(() => {
      model?.timers.delete(timer);
      callback();
    }, delay);
    model.timers.add(timer);
    return timer;
  }

  function showVerdict(kind, detail) {
    const root = document.querySelector(".foundry-scale");
    const verdict = root?.querySelector(".foundry-verdict");
    if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass");
    root.classList.toggle("is-failed", kind === "fail");
    verdict.innerHTML = `<b>${kind === "pass" ? "PASS" : "FAIL"}</b><span>${detail}</span>`;
    if (kind === "fail") later(() => root.classList.remove("is-failed"), 1600);
  }

  function updateScene() {
    if (!model) return;
    const root = document.querySelector(".foundry-scale");
    if (!root) return;
    root.dataset.view = String(model.view);
    root.dataset.selectedDie = model.selectedId;
    root.dataset.settling = String(model.settling);
    root.dataset.settled = String(model.settled);
    root.style.setProperty("--scale-deflection", `${model.deflection}deg`);
    root.style.setProperty("--beam-deflection", `${model.deflection * 0.16}deg`);
    const viewLabel = document.getElementById("foundry-view-label");
    if (viewLabel) viewLabel.textContent = model.view === 0 ? "000°" : "180°";

    for (const die of model.dice.values()) {
      const lane = document.querySelector(`[data-foundry-lane="${die.id}"]`);
      const selector = document.querySelector(`[data-die-select="${die.id}"]`);
      const token = document.querySelector(`[data-foundry-token="${die.id}"]`);
      const scaleSlot = document.querySelector(`[data-scale-slot="${die.id}"]`);
      lane?.setAttribute("data-selected", String(model.selectedId === die.id));
      lane?.setAttribute("data-docked", String(die.docked));
      selector?.setAttribute("data-selected", String(model.selectedId === die.id));
      selector?.setAttribute("data-docked", String(die.docked));
      scaleSlot?.setAttribute("data-filled", String(die.docked));
      if (scaleSlot) {
        scaleSlot.innerHTML = die.docked
          ? `<i style="--die-color:${die.config.color}"></i><b>${model.helpers.text(die.config.label.slice(0, 1))}</b>`
          : `<span>${model.helpers.text(die.config.label.slice(0, 1))}</span>`;
      }
      if (token) {
        const display = displayPoint(die.position);
        token.style.left = `${((display.x + 0.5) / Number(model.state.board.columns)) * 100}%`;
        token.style.top = `${((display.y + 0.5) / Number(model.state.board.rows)) * 100}%`;
        token.style.setProperty("--die-color", die.config.color);
        token.dataset.visible = String(isVisible(die));
        token.dataset.docked = String(die.docked);
        token.dataset.x = String(die.position.x);
        token.dataset.y = String(die.position.y);
        token.innerHTML = `${dieFaceMarkup(die)}<em>${model.helpers.text(die.config.label.slice(0, 1))}</em>`;
      }
      document.querySelectorAll(`[data-foundry-lane="${die.id}"] .foundry-cell`).forEach((cell) => {
        const point = {x: Number(cell.dataset.worldX), y: Number(cell.dataset.worldY)};
        const display = displayPoint(point);
        cell.style.gridColumn = String(display.x + 1);
        cell.style.gridRow = String(display.y + 1);
      });
    }
    const weigh = document.getElementById("foundry-weigh");
    if (weigh) weigh.disabled = model.submitting || model.settling || model.completed;
    document.querySelectorAll(".foundry-roll-key, .foundry-die-selector, #foundry-view-rotate, #foundry-reset").forEach((control) => {
      control.disabled = model.submitting || model.settling || model.completed;
    });
  }

  function selectDie(dieId) {
    if (!model || model.completed || model.settling || !model.dice.has(dieId)) return;
    const before = model.selectedId;
    model.selectedId = dieId;
    pushEvent({type: "select", die_id: dieId, selected_before: before, selected_after: dieId});
    model.helpers.setReadout("DIE CLAMP SELECTED", "idle");
    updateScene();
  }

  function rotateView() {
    if (!model || model.completed || model.settling) return;
    const before = model.view;
    model.view = (model.view + 2) % 4;
    model.viewRotations += 1;
    pushEvent({type: "view_rotate", delta: 2, view_before: before, view_after: model.view});
    model.helpers.setReadout("TABLE VIEW TURNED", "idle");
    const root = document.querySelector(".foundry-scale");
    root?.classList.add("is-turning");
    later(() => root?.classList.remove("is-turning"), 420);
    updateScene();
  }

  function rollSelected(inputDirection) {
    if (!model || model.completed || model.settling || !DIRECTIONS[inputDirection]) return;
    const die = model.dice.get(model.selectedId);
    if (!die) return;
    const worldDirection = screenToWorld(inputDirection);
    const [dx, dy] = DIRECTIONS[worldDirection];
    const before = clonePoint(die.position);
    const candidate = {x: before.x + dx, y: before.y + dy};
    const accepted = !die.docked && die.openCells.has(pointKey(candidate));
    if (accepted) {
      die.position = candidate;
      die.orientation = roll(die.orientation, worldDirection);
      die.acceptedRolls += 1;
      die.initialReveal = false;
      die.docked = samePoint(die.position, die.config.dock);
    }
    pushEvent({
      type: "roll",
      die_id: die.id,
      input_direction: inputDirection,
      world_direction: worldDirection,
      view: model.view,
      from: before,
      to: clonePoint(die.position),
      accepted,
      orientation_after: cloneOrientation(die.orientation),
      accepted_rolls_after: die.acceptedRolls,
      docked: die.docked,
      top_visible: isVisible(die),
    });
    const token = document.querySelector(`[data-foundry-token="${die.id}"]`);
    token?.classList.remove("is-rolling");
    void token?.offsetWidth;
    token?.classList.add("is-rolling");
    later(() => token?.classList.remove("is-rolling"), 260);
    if (!accepted) {
      model.helpers.setReadout(die.docked ? "DOCK MAGNET LOCKED" : "RAIL STOP", "error");
      const lane = document.querySelector(`[data-foundry-lane="${die.id}"]`);
      lane?.classList.add("is-collision");
      later(() => lane?.classList.remove("is-collision"), 340);
    } else if (die.docked) {
      model.helpers.setReadout("SCALE DOCK ENGAGED", "idle");
    } else if (isVisible(die)) {
      model.helpers.setReadout("SCANNER PAD ACTIVE", "idle");
    } else {
      model.helpers.setReadout("FACE UNDER HOUSING", "idle");
    }
    updateScene();
  }

  function resetTable() {
    if (!model || model.completed || model.settling) return;
    for (const die of model.dice.values()) {
      die.position = clonePoint(die.config.start);
      die.orientation = cloneOrientation(die.config.initial_orientation);
      die.acceptedRolls = 0;
      die.docked = false;
      die.initialReveal = true;
    }
    model.view = Number(model.state.starting_view || 0);
    model.selectedId = model.state.initial_selected_die_id;
    model.viewRotations = 0;
    model.resetCount += 1;
    model.settleSamples = [];
    model.settled = false;
    model.deflection = 0;
    pushEvent({type: "reset", view_after: model.view, selected_after: model.selectedId});
    model.helpers.setReadout("TABLE RESET", "idle");
    updateScene();
  }

  function finalState() {
    return {
      view: model.view,
      selected_die_id: model.selectedId,
      view_rotations: model.viewRotations,
      reset_count: model.resetCount,
      dice: model.state.dice.map((config) => {
        const die = model.dice.get(config.id);
        return {
          die_id: die.id,
          position: clonePoint(die.position),
          orientation: cloneOrientation(die.orientation),
          accepted_rolls: die.acceptedRolls,
          docked: die.docked,
          top_visible: isVisible(die),
        };
      }),
      top_sum: topSum(),
      settled: model.settled,
      settle_samples: [...model.settleSamples],
    };
  }

  function payload() {
    return {
      mechanic_id: model.state.mechanic_id,
      challenge_id: model.state.challenge_id,
      completed: model.settled,
      events: model.events,
      final_state: finalState(),
    };
  }

  async function postResult() {
    if (!model || model.submitting) return;
    const current = model;
    current.submitting = true;
    updateScene();
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload()),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        current.completed = true;
        current.helpers.setReadout("PASS", "passed");
        showVerdict("pass", "FOUNDRY LOT BALANCED");
        updateScene();
      } else if (outcome.passed === false) {
        const helpers = current.helpers;
        if (outcome.state) await render(outcome.state, helpers, {freshFailure: true});
        model.helpers.setReadout("FAIL", "error");
        showVerdict("fail", "LOT RECAST");
      }
    } catch (_error) {
      if (model === current) {
        current.submitting = false;
        current.helpers.setReadout("SCALE LINK LOST", "error");
        updateScene();
      }
    }
  }

  function runSettlement() {
    if (!model || model.settling || model.completed) return;
    const dice = [...model.dice.values()];
    const ready = dice.every((die) => die.docked && die.acceptedRolls >= 2) && model.viewRotations >= 1;
    if (!ready) {
      model.helpers.setReadout("WEIGHING…", "idle");
      postResult();
      return;
    }
    const profile = settleProfile(topSum() - Number(model.state.target_sum));
    model.settling = true;
    model.settleSamples = [];
    pushEvent({type: "settle_start", sample_count: profile.length});
    model.helpers.setReadout("BALANCE SETTLING", "idle");
    updateScene();
    let index = 0;
    const nextSample = () => {
      if (!model || !model.settling) return;
      const deflection = profile[index];
      model.deflection = deflection;
      model.settleSamples.push(deflection);
      pushEvent({type: "settle_sample", sample_index: index + 1, deflection});
      updateScene();
      index += 1;
      if (index < profile.length) {
        later(nextSample, 115);
        return;
      }
      later(() => {
        const sum = topSum();
        model.settling = false;
        model.settled = true;
        pushEvent({type: "settle_complete", balanced: sum === Number(model.state.target_sum), top_sum: sum});
        model.helpers.setReadout("BALANCE LOCKED", "idle");
        updateScene();
        postResult();
      }, 150);
    };
    later(nextSample, 90);
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
        output.textContent = (data.solution_plans || [])
          .map((plan) => `${plan.die_id}: ${(plan.world_directions || []).join(" ")} → ${plan.final_top}`)
          .join(" · ");
      } catch (_error) {
        output.textContent = "Unavailable.";
      }
    });
  }

  function laneMarkup(config, state, helpers) {
    const open = new Set((config.open_cells || []).map(pointKey));
    const scanners = new Set((config.scanner_cells || []).map(pointKey));
    const housings = new Set((config.housing_cells || []).map(pointKey));
    const cells = [];
    for (let y = 0; y < Number(state.board.rows); y += 1) {
      for (let x = 0; x < Number(state.board.columns); x += 1) {
        const point = {x, y};
        const key = pointKey(point);
        const isOpen = open.has(key);
        const scanner = scanners.has(key);
        const housing = housings.has(key);
        const start = samePoint(point, config.start);
        const dock = samePoint(point, config.dock);
        const classes = ["foundry-cell", isOpen ? "is-rail" : "is-blocked", scanner ? "is-scanner" : "", housing ? "is-housing" : "", start ? "is-origin" : "", dock ? "is-dock" : ""].filter(Boolean).join(" ");
        const mark = scanner
          ? "<span class=\"scanner-coil\"><i></i><b>SCAN</b></span>"
          : dock
            ? `<span class="dock-mark"><i></i><b>${helpers.text(config.label.slice(0, 1))}</b></span>`
            : start
              ? "<span class=\"origin-mark\">CAST</span>"
              : housing
                ? "<span class=\"housing-roof\"><i></i><i></i><i></i></span>"
                : "";
        cells.push(`<div class="${classes}" data-world-x="${x}" data-world-y="${y}">${mark}</div>`);
      }
    }
    return `
      <article class="foundry-lane" data-foundry-lane="${helpers.text(config.id)}" data-selected="false" data-docked="false">
        <div class="lane-identity"><span>${helpers.text(config.rail_code)}</span><b>${helpers.text(config.label)}</b></div>
        <div class="foundry-grid">${cells.join("")}<button type="button" class="foundry-die-token" data-foundry-token="${helpers.text(config.id)}" aria-label="select ${helpers.text(config.label)} die" style="--die-color:${helpers.text(config.color)}"></button></div>
      </article>`;
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "top-face-dice-arithmetic";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const dice = new Map();
    for (const config of state.dice || []) {
      dice.set(config.id, {
        id: config.id,
        config,
        position: clonePoint(config.start),
        orientation: cloneOrientation(config.initial_orientation),
        openCells: new Set((config.open_cells || []).map(pointKey)),
        scannerCells: new Set((config.scanner_cells || []).map(pointKey)),
        acceptedRolls: 0,
        docked: false,
        initialReveal: true,
      });
    }
    model = {
      state,
      helpers,
      dice,
      startedAt: performance.now(),
      events: [],
      selectedId: state.initial_selected_die_id,
      view: Number(state.starting_view || 0),
      viewRotations: 0,
      resetCount: 0,
      settleSamples: [],
      deflection: 0,
      settling: false,
      settled: false,
      submitting: false,
      completed: false,
      timers: new Set(),
    };

    helpers.app.innerHTML = `
      <section class="foundry-scale palette-${helpers.text(state.palette)}" data-view="0" data-fresh-failure="${options.freshFailure ? "true" : "false"}" tabindex="0">
        <div class="foundry-verdict" aria-live="assertive"></div>
        <header class="foundry-head">
          <div class="foundry-title"><span>THREE-DIE FOUNDRY SCALE / ${helpers.text(state.foundry_serial)}</span><h1>${helpers.text(state.prompt)}</h1></div>
          <div class="foundry-target"><span>TOP SUM</span><b>${Number(state.target_sum)}</b><i>TARE / D6×3</i></div>
        </header>
        <main class="foundry-workbench">
          <aside class="foundry-controls">
            <div class="control-heading"><span>DIE CLAMPS</span><b>SELECT</b></div>
            <div class="foundry-die-selectors">
              ${(state.dice || []).map((config, index) => `<button type="button" class="foundry-die-selector" data-die-select="${helpers.text(config.id)}" data-selected="${index === 0}" data-docked="false" style="--die-color:${helpers.text(config.color)}"><i>${helpers.text(config.label.slice(0, 1))}</i><span>${helpers.text(config.label)}</span><b>${helpers.text(config.rail_code)}</b></button>`).join("")}
            </div>
            <div class="control-heading roll-heading"><span>ROLL JOG</span><b>WASD / ↕↔</b></div>
            <div class="foundry-roll-pad">
              <button type="button" class="foundry-roll-key key-n" id="foundry-roll-n" data-roll-direction="N">N</button>
              <button type="button" class="foundry-roll-key key-w" id="foundry-roll-w" data-roll-direction="W">W</button>
              <span class="roll-hub">D6</span>
              <button type="button" class="foundry-roll-key key-e" id="foundry-roll-e" data-roll-direction="E">E</button>
              <button type="button" class="foundry-roll-key key-s" id="foundry-roll-s" data-roll-direction="S">S</button>
            </div>
          </aside>
          <section class="foundry-table-wrap">
            <div class="foundry-table-toolbar"><span>ORIENTATION TABLE</span><button type="button" id="foundry-view-rotate"><i>↻</i> ROTATE VIEW <b id="foundry-view-label">000°</b></button></div>
            <div class="foundry-table">
              ${(state.dice || []).map((config) => laneMarkup(config, state, helpers)).join("")}
            </div>
            <div class="foundry-table-index"><span>HOUSING</span><i></i><span>SCANNER</span><i></i><span>SCALE DOCK</span></div>
          </section>
          <aside class="foundry-balance">
            <div class="balance-plate"><span>CALIBRATED LOT</span><b>${Number(state.target_sum)}</b><i>Σ TOP</i></div>
            <div class="balance-machine">
              <div class="balance-beam"><i></i><b></b></div>
              <div class="balance-needle"><i></i></div>
              <div class="balance-dock-slots">${(state.dice || []).map((config) => `<div data-scale-slot="${helpers.text(config.id)}" data-filled="false"><span>${helpers.text(config.label.slice(0, 1))}</span></div>`).join("")}</div>
              <div class="balance-plinth"><span>0</span><i></i><span>${Number(state.target_sum)}</span></div>
            </div>
            <div class="balance-seal"><span>WEIGHTS &amp; MEASURES</span><b>F-3</b></div>
          </aside>
        </main>
        <footer class="foundry-foot"><button type="button" id="foundry-reset">RESET TABLE</button><div class="readout" data-status="idle">INITIAL TOP FACES EXPOSED</div><button type="button" id="foundry-weigh">${helpers.text(state.submit_label || "WEIGH LOT")}</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;

    const keydown = (event) => {
      if (!model || model.completed || model.settling || event.repeat) return;
      const key = String(event.key || "").toLowerCase();
      if (key === "r") {
        event.preventDefault();
        resetTable();
        return;
      }
      if (key === "v" || key === "t") {
        event.preventDefault();
        rotateView();
        return;
      }
      if (["1", "2", "3"].includes(key)) {
        event.preventDefault();
        const config = state.dice[Number(key) - 1];
        if (config) selectDie(config.id);
        return;
      }
      const direction = KEY_DIRECTIONS[key];
      if (!direction) return;
      event.preventDefault();
      rollSelected(direction);
    };
    window.addEventListener("keydown", keydown);
    document.querySelectorAll("[data-die-select], [data-foundry-token]").forEach((element) => {
      const dieId = element.dataset.dieSelect || element.dataset.foundryToken;
      element.addEventListener("click", () => selectDie(dieId));
    });
    document.querySelectorAll("[data-roll-direction]").forEach((button) => button.addEventListener("click", () => rollSelected(button.dataset.rollDirection)));
    document.getElementById("foundry-view-rotate")?.addEventListener("click", rotateView);
    document.getElementById("foundry-reset")?.addEventListener("click", resetTable);
    document.getElementById("foundry-weigh")?.addEventListener("click", runSettlement);
    installDeveloperReveal();
    const shell = document.querySelector(".foundry-scale");
    activeCleanup = () => {
      window.removeEventListener("keydown", keydown);
      clearTimers();
    };
    updateScene();
    shell?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.top_face_dice_arithmetic = {rootSelector: ".foundry-scale", render};
})();
