(() => {
  "use strict";

  const PROCESS_STATIONS = ["grind", "heat", "infuse", "press"];
  const ALL_STATIONS = [...PROCESS_STATIONS, "assemble"];
  const STATION_LABELS = {
    grind: ["MORTAR MILL", "CRUSH / MILL", "◉"],
    heat: ["CALCINE OVEN", "FIRE / TEMPER", "△"],
    infuse: ["AETHER COIL", "INFUSE / CHARGE", "⌁"],
    press: ["SEAL PRESS", "STAMP / LAMINATE", "▣"],
    assemble: ["TRIUNE JIG", "ASSEMBLE THREE", "⬡"],
  };
  let model = null;
  let activeCleanup = null;

  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;");

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function record(kind, details = {}) {
    const item = {seq: model.events.length + 1, t_ms: eventTime(), kind, ...details};
    model.events.push(item);
    return item;
  }

  function later(callback, delay) {
    const timer = window.setTimeout(() => {
      model?.timers.delete(timer);
      callback();
    }, delay);
    model.timers.add(timer);
    return timer;
  }

  function clearTimers() {
    if (!model) return;
    for (const timer of model.timers) window.clearTimeout(timer);
    model.timers.clear();
  }

  function pointInRect(point, rect) {
    return Number(rect.x1) <= point.x && point.x <= Number(rect.x2)
      && Number(rect.y1) <= point.y && point.y <= Number(rect.y2);
  }

  function rootPoint(event) {
    const root = document.querySelector(".alchemy-bench");
    const rect = root.getBoundingClientRect();
    return {
      x: Math.round((event.clientX - rect.left) / rect.width * Number(model.state.geometry.width) * 10) / 10,
      y: Math.round((event.clientY - rect.top) / rect.height * Number(model.state.geometry.height) * 10) / 10,
    };
  }

  function pointStyle(rect) {
    const width = Number(model.state.geometry.width);
    const height = Number(model.state.geometry.height);
    return `left:${Number(rect.x1) / width * 100}%;top:${Number(rect.y1) / height * 100}%;width:${(Number(rect.x2) - Number(rect.x1)) / width * 100}%;height:${(Number(rect.y2) - Number(rect.y1)) / height * 100}%`;
  }

  function relativeStyle(child, parent) {
    const width = Number(parent.x2) - Number(parent.x1);
    const height = Number(parent.y2) - Number(parent.y1);
    return `left:${(Number(child.x1) - Number(parent.x1)) / width * 100}%;top:${(Number(child.y1) - Number(parent.y1)) / height * 100}%;width:${(Number(child.x2) - Number(child.x1)) / width * 100}%;height:${(Number(child.y2) - Number(child.y1)) / height * 100}%`;
  }

  function stateMeta(stateId) {
    return model.meta.get(stateId) || {name: "Spent Matter", symbol: "×", color: "#7a6558", branch: "WASTE", stage: "IRREVERSIBLE"};
  }

  function itemMarkup(stateId, slot = null, station = null) {
    if (!stateId) return "";
    const meta = stateMeta(stateId);
    const attrs = slot == null ? "" : ` data-slot="${slot}"`;
    const stationAttr = station ? ` data-machine-item="${clean(station)}"` : "";
    return `<div class="alchemy-item${meta.waste ? " is-waste" : ""}${stateId === model.state.recipe.device_state_id ? " is-device" : ""}"${attrs}${stationAttr} data-state-id="${clean(stateId)}" style="--item-color:${clean(meta.color)}"><i>${clean(meta.symbol)}</i><span>${clean(meta.name)}</span><b>${clean(meta.branch)}</b></div>`;
  }

  function buildMeta(state) {
    const meta = new Map();
    for (const branch of state.recipe.branches || []) {
      meta.set(branch.raw_state_id, {
        name: branch.raw_name, symbol: branch.symbol, color: branch.color,
        branch: `LINE ${branch.branch_id}`, stage: "RAW",
      });
      for (const step of branch.steps || []) {
        meta.set(step.output_state_id, {
          name: step.output_name, symbol: branch.symbol, color: branch.color,
          branch: `LINE ${branch.branch_id}`, stage: String(step.station_id).toUpperCase(),
        });
      }
    }
    meta.set(state.recipe.device_state_id, {
      name: state.recipe.device_name, symbol: state.recipe.device_symbol,
      color: state.palette.accent, branch: "DEVICE", stage: "COMPLETE",
    });
    return meta;
  }

  function registerWaste(stateId, station) {
    model.meta.set(stateId, {
      name: station === "assemble" ? "Misbound Husk" : `${STATION_LABELS[station][0]} Waste`,
      symbol: "×", color: "#8c5b45", branch: "WASTE", stage: "LINEAGE LOST", waste: true,
    });
  }

  function transitionMap(state) {
    const map = new Map();
    for (const branch of state.recipe.branches || []) {
      for (const step of branch.steps || []) {
        map.set(step.input_state_id, {station: step.station_id, output: step.output_state_id});
      }
    }
    return map;
  }

  function showVerdict(kind, title, detail) {
    const root = document.querySelector(".alchemy-bench");
    root?.classList.toggle("is-pass", kind === "pass");
    root?.classList.toggle("is-fail", kind === "fail");
    document.querySelector(".alchemy-verdict")?.remove();
    root?.insertAdjacentHTML("beforeend", `<div class="alchemy-verdict alchemy-verdict-${kind}"><small>CRAFTCHA / LINEAGE OFFICE</small><strong>${clean(title)}</strong><span>${clean(detail)}</span></div>`);
    if (kind === "fail") later(() => {
      document.querySelector(".alchemy-verdict-fail")?.remove();
      document.querySelector(".alchemy-bench")?.classList.remove("is-fail");
    }, 1650);
  }

  function setReadout(message, status = "idle") {
    model.helpers.setReadout(message, status);
  }

  function recipeLaneMarkup(branch) {
    const nodes = [
      `<span class="recipe-node is-raw" style="--branch:${clean(branch.color)}"><i>${clean(branch.symbol)}</i><b>${clean(branch.raw_name)}</b><small>RAW ${clean(branch.branch_id)}</small></span>`,
      ...(branch.steps || []).map((step) => `<em>›</em><span class="recipe-node" style="--branch:${clean(branch.color)}"><i>${clean(STATION_LABELS[step.station_id][2])}</i><b>${clean(step.station_id)}</b><small>${clean(step.output_name)}</small></span>`),
    ];
    return `<div class="recipe-lane"><label>${clean(branch.branch_id)}</label>${nodes.join("")}</div>`;
  }

  function openRecipe(reason) {
    if (!model || model.completed) return;
    model.recipeSealed = false;
    model.recipeReason = reason;
    const root = document.querySelector(".alchemy-bench");
    root?.setAttribute("data-recipe", "open");
    document.querySelector(".alchemy-recipe-shutter")?.classList.add("is-open");
    const duration = reason === "initial" ? Number(model.state.recipe_window_ms) : Number(model.state.replay_window_ms);
    setReadout(reason === "initial" ? "MEMORIZE THE FORMULA · SHUTTER CLOSING" : "COSTLY REPLAY · MEMORY CHARGE BURNING", "pending");
    model.recipeTimer = later(() => closeRecipe(reason), duration);
    updateState();
  }

  function closeRecipe(reason) {
    if (!model || model.completed || model.recipeSealed || model.recipeReason !== reason) return;
    model.recipeSealed = true;
    model.recipeReason = null;
    record("recipe_seal", {reason, recipe_hash: model.state.recipe_hash});
    const root = document.querySelector(".alchemy-bench");
    root?.setAttribute("data-recipe", "sealed");
    document.querySelector(".alchemy-recipe-shutter")?.classList.remove("is-open");
    setReadout("RECIPE SEALED · ROUTE MATERIALS FROM MEMORY", "idle");
    updateState();
  }

  function replayRecipe(event) {
    if (!model || model.busy || model.completed || !model.recipeSealed) return;
    const accepted = model.replayCount < Number(model.state.replay_limit)
      && model.memoryCharge >= Number(model.state.memory_replay_cost);
    const point = rootPoint(event);
    record("replay", {
      point, accepted,
      memory_after: accepted ? model.memoryCharge - Number(model.state.memory_replay_cost) : model.memoryCharge,
    });
    if (!accepted) {
      setReadout("RECIPE REPLAY SPENT", "error");
      return;
    }
    model.replayCount += 1;
    model.memoryCharge -= Number(model.state.memory_replay_cost);
    openRecipe("replay");
  }

  function resetBench(event) {
    if (!model || model.busy || model.completed || !model.recipeSealed) return;
    model.inventory = [...model.state.initial_inventory];
    model.stations = Object.fromEntries(ALL_STATIONS.map((station) => [station, null]));
    model.assembly = [];
    model.delivery = null;
    model.transformCount = 0;
    model.discardCount = 0;
    model.dragCount = 0;
    model.wasteSerial = 0;
    model.resetCount += 1;
    record("reset", {
      point: rootPoint(event), inventory_after: [...model.inventory], reset_count: model.resetCount,
    });
    setReadout("BENCH PURGED · RAW MATERIALS RESTORED", "idle");
    updateState();
  }

  function inventorySlotAt(point) {
    return (model.state.geometry.inventory_slots || []).findIndex((rect) => pointInRect(point, rect));
  }

  function destinationAt(point) {
    for (const station of ALL_STATIONS) {
      if (pointInRect(point, model.state.geometry.stations[station])) return station;
    }
    return pointInRect(point, model.state.geometry.delivery) ? "delivery" : null;
  }

  function beginDrag(event, item) {
    if (!model || model.busy || model.completed || !model.recipeSealed || event.button !== 0) return;
    const slot = Number(item.dataset.slot);
    const stateId = model.inventory[slot];
    if (!stateId) return;
    event.preventDefault();
    const start = rootPoint(event);
    model.drag = {
      pointerId: event.pointerId, slot, stateId, start, startedAt: performance.now(),
      samples: [start], clientX: event.clientX, clientY: event.clientY,
    };
    const meta = stateMeta(stateId);
    document.body.insertAdjacentHTML("beforeend", `<div class="alchemy-drag-ghost" style="left:${event.clientX}px;top:${event.clientY}px;--item-color:${clean(meta.color)}"><i>${clean(meta.symbol)}</i><span>${clean(meta.name)}</span></div>`);
    item.classList.add("is-dragging");
    window.addEventListener("pointermove", moveDrag);
    window.addEventListener("pointerup", endDrag, {once: true});
  }

  function moveDrag(event) {
    if (!model?.drag || event.pointerId !== model.drag.pointerId) return;
    const point = rootPoint(event);
    const previous = model.drag.samples[model.drag.samples.length - 1];
    if (model.drag.samples.length < 47 && Math.hypot(point.x - previous.x, point.y - previous.y) >= 2) {
      model.drag.samples.push(point);
    }
    model.drag.clientX = event.clientX;
    model.drag.clientY = event.clientY;
    const ghost = document.querySelector(".alchemy-drag-ghost");
    if (ghost) {
      ghost.style.left = `${event.clientX}px`;
      ghost.style.top = `${event.clientY}px`;
    }
  }

  function endDrag(event) {
    window.removeEventListener("pointermove", moveDrag);
    const drag = model?.drag;
    document.querySelector(".alchemy-drag-ghost")?.remove();
    document.querySelector(".alchemy-item.is-dragging")?.classList.remove("is-dragging");
    if (!drag || event.pointerId !== drag.pointerId) {
      if (model) model.drag = null;
      return;
    }
    const end = rootPoint(event);
    if (drag.samples.length < 48) drag.samples.push(end);
    else drag.samples[drag.samples.length - 1] = end;
    const duration = Math.round(performance.now() - drag.startedAt);
    const sourceSlot = inventorySlotAt(drag.start);
    const destination = destinationAt(end);
    const physical = duration >= 35 && drag.samples.length >= 4 && sourceSlot === drag.slot;
    let accepted = physical && destination && model.inventory[drag.slot] === drag.stateId;
    if (accepted && destination === "delivery") accepted = model.delivery == null;
    else if (accepted && destination === "assemble") accepted = model.assembly.length < 3;
    else if (accepted) accepted = model.stations[destination] == null;
    if (!accepted) {
      model.drag = null;
      setReadout(physical ? "TRANSFER REJECTED · SOCKET OCCUPIED" : "DRAG DELIBERATELY THROUGH THE BENCH", "error");
      updateState();
      return;
    }
    model.inventory[drag.slot] = null;
    if (destination === "delivery") model.delivery = drag.stateId;
    else if (destination === "assemble") model.assembly.push(drag.stateId);
    else model.stations[destination] = drag.stateId;
    model.dragCount += 1;
    record("drag", {
      start: drag.start, end, samples: drag.samples, duration_ms: duration,
      source_slot: drag.slot, destination, state_id: drag.stateId,
    });
    model.drag = null;
    setReadout(destination === "delivery" ? "DEVICE ENTERED CERTIFICATION BAY" : `${STATION_LABELS[destination][0]} LOADED`, "idle");
    updateState();
  }

  function cycleStation(event, station) {
    if (!model || model.busy || model.completed || !model.recipeSealed) return;
    const inputs = station === "assemble" ? [...model.assembly] : [model.stations[station]].filter(Boolean);
    if (!inputs.length) {
      setReadout(`${STATION_LABELS[station][0]} IS EMPTY`, "error");
      return;
    }
    model.busy = true;
    const started = performance.now();
    const point = rootPoint(event);
    const machine = document.querySelector(`[data-alchemy-station="${station}"]`);
    machine?.classList.add("is-cycling");
    setReadout(`${STATION_LABELS[station][0]} · CYCLE 1/4`, "pending");
    [95, 190, 285].forEach((delay, index) => later(() => setReadout(`${STATION_LABELS[station][0]} · CYCLE ${index + 2}/4`, "pending"), delay));
    later(() => {
      if (!model) return;
      let outputState;
      if (station === "assemble") {
        const terminals = model.state.recipe.assemble_step.input_state_ids;
        if (inputs.length === 3 && [...inputs].sort().join("|") === [...terminals].sort().join("|")) {
          outputState = model.state.recipe.device_state_id;
        } else {
          model.wasteSerial += 1;
          model.discardCount += 1;
          outputState = `${model.state.challenge_id}:waste:assemble:${model.wasteSerial}`;
          registerWaste(outputState, station);
        }
        model.assembly = [];
      } else {
        const input = inputs[0];
        const transition = model.transitions.get(input);
        if (transition && transition.station === station) {
          outputState = transition.output;
        } else {
          model.wasteSerial += 1;
          model.discardCount += 1;
          outputState = `${model.state.challenge_id}:waste:${station}:${model.wasteSerial}`;
          registerWaste(outputState, station);
        }
        model.stations[station] = null;
      }
      const outputSlot = model.inventory.indexOf(null);
      if (outputSlot < 0) {
        model.busy = false;
        machine?.classList.remove("is-cycling");
        setReadout("OUTPUT RACK JAMMED", "error");
        return;
      }
      model.inventory[outputSlot] = outputState;
      model.transformCount += 1;
      const duration = Math.round(performance.now() - started);
      record("cycle", {
        point, duration_ms: duration, cycle_pulses: [1, 2, 3, 4], station_id: station,
        input_state_ids: inputs, output_state_id: outputState, output_slot: outputSlot,
      });
      model.busy = false;
      machine?.classList.remove("is-cycling");
      const outputMeta = stateMeta(outputState);
      setReadout(outputMeta.waste ? "LINEAGE DESTROYED · RESET TO RECOVER" : `${outputMeta.name.toUpperCase()} READY IN SLOT ${outputSlot + 1}`, outputMeta.waste ? "error" : "idle");
      updateState();
    }, 410);
    updateState();
  }

  function finalState() {
    return {
      inventory: [...model.inventory],
      stations: Object.fromEntries(ALL_STATIONS.map((station) => [station, model.stations[station]])),
      assembly: [...model.assembly],
      delivery: model.delivery,
      recipe_sealed: model.recipeSealed,
      memory_charge: model.memoryCharge,
      replay_count: model.replayCount,
      reset_count: model.resetCount,
      transform_count: model.transformCount,
      discard_count: model.discardCount,
      drag_count: model.dragCount,
      submitted: model.submitted,
    };
  }

  function payload() {
    return {
      mechanic_id: model.state.mechanic_id,
      challenge_id: model.state.challenge_id,
      completed: model.delivery === model.state.recipe.device_state_id,
      events: model.events,
      final_state: finalState(),
    };
  }

  async function submitDevice(event) {
    if (!model || model.busy || model.completed || model.submitted || !model.recipeSealed) return;
    model.submitted = true;
    const certified = model.delivery === model.state.recipe.device_state_id;
    record("submit", {point: rootPoint(event), certified});
    updateState();
    const current = model;
    try {
      const response = await fetch("/result", {
        method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload()),
      });
      const outcome = await response.json();
      if (outcome.passed === true && model === current) {
        current.completed = true;
        setReadout("PASS", "passed");
        showVerdict("pass", "PASS", `${current.state.recipe.device_name} / LINEAGE CERTIFIED`);
        updateState();
      } else if (outcome.passed === false && outcome.state) {
        const helpers = current.helpers;
        await render(outcome.state, helpers, {freshFailure: true});
      } else if (model === current) {
        current.submitted = false;
        setReadout("CERTIFICATION LINK REFUSED", "error");
        updateState();
      }
    } catch (_error) {
      if (model === current) {
        current.submitted = false;
        setReadout("CERTIFICATION LINK LOST", "error");
        updateState();
      }
    }
  }

  function updateState() {
    if (!model) return;
    const root = document.querySelector(".alchemy-bench");
    if (!root) return;
    root.dataset.recipe = model.recipeSealed ? "sealed" : "open";
    root.dataset.busy = String(model.busy);
    root.dataset.completed = String(model.completed);
    root.style.setProperty("--memory-level", String(model.memoryCharge / Number(model.state.memory_charge_initial)));
    const memory = document.getElementById("alchemy-memory-count");
    if (memory) memory.textContent = `${model.memoryCharge}/${model.state.memory_charge_initial}`;
    const transforms = document.getElementById("alchemy-transform-count");
    if (transforms) transforms.textContent = `${model.transformCount}/${model.state.recipe.step_count}`;

    (model.state.geometry.inventory_slots || []).forEach((_rect, index) => {
      const slot = document.querySelector(`[data-alchemy-slot="${index}"]`);
      if (!slot) return;
      slot.dataset.filled = String(Boolean(model.inventory[index]));
      slot.innerHTML = model.inventory[index]
        ? itemMarkup(model.inventory[index], index)
        : `<span class="slot-empty"><i>${String(index + 1).padStart(2, "0")}</i><b>EMPTY</b></span>`;
    });
    for (const station of ALL_STATIONS) {
      const machine = document.querySelector(`[data-alchemy-station="${station}"]`);
      if (!machine) continue;
      machine.dataset.loaded = String(station === "assemble" ? model.assembly.length > 0 : Boolean(model.stations[station]));
      const chamber = machine.querySelector(".machine-chamber");
      if (chamber) {
        if (station === "assemble") {
          chamber.innerHTML = `<div class="assembly-sockets">${[0, 1, 2].map((index) => `<span data-filled="${Boolean(model.assembly[index])}">${model.assembly[index] ? itemMarkup(model.assembly[index], null, station) : `<i>${index + 1}</i>`}</span>`).join("")}</div>`;
        } else {
          chamber.innerHTML = model.stations[station] ? itemMarkup(model.stations[station], null, station) : `<span class="machine-empty">DROP MATERIAL<br>INTO CHAMBER</span>`;
        }
      }
      const cycle = machine.querySelector(".machine-cycle");
      if (cycle) cycle.disabled = model.busy || model.completed;
    }
    const bay = document.querySelector(".alchemy-delivery-object");
    if (bay) bay.innerHTML = model.delivery ? itemMarkup(model.delivery, null, "delivery") : `<span><i>⌁</i><b>DELIVERY BAY</b><small>DRAG FINISHED DEVICE HERE</small></span>`;
    const replay = document.getElementById("alchemy-replay");
    if (replay) replay.disabled = model.busy || model.completed || !model.recipeSealed || model.replayCount >= Number(model.state.replay_limit);
    const reset = document.getElementById("alchemy-reset");
    if (reset) reset.disabled = model.busy || model.completed || !model.recipeSealed;
    const verify = document.getElementById("alchemy-verify");
    if (verify) verify.disabled = model.busy || model.completed || model.submitted || !model.recipeSealed;
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
          method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({password: input.value}),
        });
        if (!response.ok) {
          output.textContent = response.status === 404 ? "Disabled." : "Denied.";
          return;
        }
        const data = await response.json();
        output.textContent = (data.solution_steps || []).map((step) => `${step.step}:${step.station_id}`).join(" · ");
      } catch (_error) {
        output.textContent = "Unavailable.";
      }
    });
  }

  function stationMarkup(station, state) {
    const rect = state.geometry.stations[station];
    const cycle = state.geometry.cycle_buttons[station];
    const labels = STATION_LABELS[station];
    return `<section class="alchemy-machine machine-${station}" data-alchemy-station="${station}" data-loaded="false" style="${pointStyle(rect)}">
      <header><span>${clean(labels[2])}</span><div><b>${clean(labels[0])}</b><small>${clean(state.station_serials[station])} · ${clean(labels[1])}</small></div><i></i></header>
      <div class="machine-chamber"></div>
      <div class="machine-gauge"><i></i><i></i><i></i><i></i></div>
      <button class="machine-cycle" type="button" data-cycle-station="${station}" style="${relativeStyle(cycle, rect)}">CYCLE <b>↻</b></button>
    </section>`;
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "craftcha-alchemy-bench";
    const stations = Object.fromEntries(ALL_STATIONS.map((station) => [station, null]));
    model = {
      state, helpers, startedAt: performance.now(), events: [], timers: new Set(), recipeTimer: null,
      recipeSealed: false, recipeReason: null, inventory: [...state.initial_inventory], stations,
      assembly: [], delivery: null, memoryCharge: Number(state.memory_charge_initial), replayCount: 0,
      resetCount: 0, transformCount: 0, discardCount: 0, dragCount: 0, wasteSerial: 0,
      submitted: false, completed: false, busy: false, drag: null,
      meta: buildMeta(state), transitions: transitionMap(state),
    };
    const geometry = state.geometry;
    helpers.app.innerHTML = `<section class="alchemy-bench palette-${clean(state.palette.name)}" data-challenge-id="${clean(state.challenge_id)}" data-recipe="open" data-fresh-failure="${Boolean(options.freshFailure)}" tabindex="0" style="--alchemy-accent:${clean(state.palette.accent)};--reagent-accent:${clean(state.palette.reagent)}">
      <header class="alchemy-head"><div><span>CRAFTCHA / TRANSFORMATION BUREAU</span><h1>${clean(state.prompt)}</h1></div><aside><small>BENCH SERIAL</small><b>${clean(state.bench_serial)}</b><i>RECIPE ${clean(state.recipe.recipe_code)}</i></aside></header>
      <main class="alchemy-field">
        <section class="alchemy-inventory"><header><span>MATERIAL RACK</span><b>4 SLOT LIMIT</b></header><div class="inventory-rule">INTERMEDIATES RETURN TO THE FIRST FREE SLOT</div></section>
        ${(geometry.inventory_slots || []).map((rect, index) => `<div class="alchemy-slot" data-alchemy-slot="${index}" data-filled="false" style="${pointStyle(rect)}"></div>`).join("")}
        <div class="memory-meter"><span>MEMORY CHARGE</span><b id="alchemy-memory-count">${state.memory_charge_initial}/${state.memory_charge_initial}</b><i><em></em></i></div>
        <button id="alchemy-replay" type="button" style="${pointStyle(geometry.replay_button)}"><span>REPLAY SEALED RECIPE</span><b>−${state.memory_replay_cost} CHARGE · ONCE</b></button>
        <div class="rack-warning">WRONG MACHINE → MATERIAL IS CONSUMED<br>RESET RESTORES THE ORIGINAL LOT</div>
        ${ALL_STATIONS.map((station) => stationMarkup(station, state)).join("")}
        <section class="alchemy-delivery" style="${pointStyle(geometry.delivery)}"><header><span>FINAL INSPECTION</span><b>LINEAGE SCANNER</b></header><div class="alchemy-delivery-object"></div><div class="delivery-coils"><i></i><i></i><i></i></div><footer><small>REQUESTED DEVICE</small><strong>${clean(state.recipe.device_symbol)} ${clean(state.recipe.device_name)}</strong><span>ALL THREE TERMINAL MATERIALS REQUIRED</span></footer></section>
      </main>
      <footer class="alchemy-foot"><button id="alchemy-reset" type="button" style="${pointStyle(geometry.reset_button)}">RESET BENCH</button><div class="readout" data-status="pending">MEMORIZE THE FORMULA · SHUTTER CLOSING</div><div class="transform-tally"><span>TRANSFORMS</span><b id="alchemy-transform-count">0/${state.recipe.step_count}</b></div><button id="alchemy-verify" type="button" style="${pointStyle(geometry.verify_button)}">${clean(state.submit_label || "CERTIFY DEVICE")}</button></footer>
      <section class="alchemy-recipe-shutter is-open"><div class="recipe-card"><header><span>TRANSIENT WORK ORDER</span><b>${clean(state.recipe.recipe_code)}</b><small>${state.recipe.step_count} TRANSFORMS · THEN DELIVER</small></header><div class="recipe-target"><i>${clean(state.recipe.device_symbol)}</i><div><small>FABRICATE</small><strong>${clean(state.recipe.device_name)}</strong></div><b>MEMORIZE NOW</b></div><div class="recipe-lanes">${(state.recipe.branches || []).map(recipeLaneMarkup).join("")}</div><footer><span>LOAD ALL THREE TERMINALS INTO</span><b>⬡ TRIUNE JIG</b><i>RECIPE WILL SEAL AUTOMATICALLY</i></footer></div><div class="shutter-left"></div><div class="shutter-right"></div></section>
      ${helpers.cheatPanelTemplate()}
    </section>`;

    const root = document.querySelector(".alchemy-bench");
    const pointerDown = (event) => {
      const item = event.target.closest(".alchemy-item[data-slot]");
      if (item) beginDrag(event, item);
    };
    root?.addEventListener("pointerdown", pointerDown);
    document.querySelectorAll("[data-cycle-station]").forEach((button) => button.addEventListener("click", (event) => cycleStation(event, button.dataset.cycleStation)));
    document.getElementById("alchemy-replay")?.addEventListener("click", replayRecipe);
    document.getElementById("alchemy-reset")?.addEventListener("click", resetBench);
    document.getElementById("alchemy-verify")?.addEventListener("click", submitDevice);
    installDeveloperReveal();
    activeCleanup = () => {
      root?.removeEventListener("pointerdown", pointerDown);
      window.removeEventListener("pointermove", moveDrag);
      window.removeEventListener("pointerup", endDrag);
      document.querySelector(".alchemy-drag-ghost")?.remove();
      clearTimers();
    };
    updateState();
    openRecipe("initial");
    if (options.freshFailure) {
      setReadout("FAIL", "error");
      showVerdict("fail", "FAIL", "LINEAGE REJECTED · FRESH LOT ISSUED");
    }
    root?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.craftcha_alchemy_bench = {rootSelector: ".alchemy-bench", render};
})();
