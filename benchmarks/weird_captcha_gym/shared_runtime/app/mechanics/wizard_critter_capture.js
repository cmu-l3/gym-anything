(() => {
  "use strict";

  const model = {
    state: null,
    helpers: null,
    critters: [],
    targetId: null,
    phase: "preview",
    tick: 0,
    events: [],
    resetCount: 0,
    previewCount: 0,
    previewStartedAt: 0,
    previewTimer: null,
    worldTimer: null,
    animationFrame: null,
    lure: null,
    lureArmed: false,
    freezeActive: false,
    freezeEnergy: 0,
    freezeTicksUsed: 0,
    freezeDowns: 0,
    freezeReleases: 0,
    nets: 0,
    cooldown: 0,
    projectile: null,
    launchCount: 0,
    targetCaptured: false,
    targetHitId: null,
    decoyHits: 0,
    misses: 0,
    busy: false,
    terminal: false,
    flash: null,
    trail: [],
  };

  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));
  const truncDiv = (value, divisor) => Math.trunc(value / divisor);
  const clone = (value) => JSON.parse(JSON.stringify(value));

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function appearancesMatch(left, right) {
    const keys = Object.keys(left || {}).sort();
    return keys.length === Object.keys(right || {}).length
      && keys.every((key) => left[key] === right[key]);
  }

  function targetCritter() {
    return model.critters.find((item) => item.id === model.targetId);
  }

  function insideOccluder(x10, y10) {
    const x = x10 / 10;
    const y = y10 / 10;
    return model.state.occluders.some((item) => (
      Number(item.x) <= x && x <= Number(item.x) + Number(item.width)
      && Number(item.y) <= y && y <= Number(item.y) + Number(item.height)
    ));
  }

  function lureVector(critter, lure) {
    const dx = lure[0] - Number(critter.x10);
    const dy = lure[1] - Number(critter.y10);
    return [dx > 250 ? 10 : dx < -250 ? -10 : 0, dy > 220 ? 7 : dy < -220 ? -7 : 0];
  }

  function stepCritter(critter, lure, frozen) {
    const next = {...critter};
    const [ax, ay] = lureVector(next, lure);
    next.vx10 = clamp(Number(next.vx10) + ax, -74, 74);
    next.vy10 = clamp(Number(next.vy10) + ay, -54, 54);
    const divisor = frozen ? 3 : 1;
    next.x10 = Number(next.x10) + truncDiv(Number(next.vx10), divisor);
    next.y10 = Number(next.y10) + truncDiv(Number(next.vy10), divisor);
    const arena = model.state.arena;
    const minimumY = Number(arena.y_min) * 10;
    const maximumY = Number(arena.y_max) * 10;
    if (next.y10 < minimumY) {
      next.y10 = minimumY + (minimumY - next.y10);
      next.vy10 = Math.abs(next.vy10);
    } else if (next.y10 > maximumY) {
      next.y10 = maximumY - (next.y10 - maximumY);
      next.vy10 = -Math.abs(next.vy10);
    }
    const minimumX = Number(arena.x_min) * 10;
    const maximumX = Number(arena.x_max) * 10;
    if (next.x10 > maximumX) {
      next.x10 = minimumX + (next.x10 - maximumX);
      next.portal_count = Number(next.portal_count || 0) + 1;
      model.flash = {side: "west", until: performance.now() + 250};
    } else if (next.x10 < minimumX) {
      next.x10 = maximumX - (minimumX - next.x10);
      next.portal_count = Number(next.portal_count || 0) + 1;
      model.flash = {side: "east", until: performance.now() + 250};
    }
    next.occluded = insideOccluder(next.x10, next.y10);
    if (next.occluded) next.occluded_ticks = Number(next.occluded_ticks || 0) + 1;
    return next;
  }

  function snapshot() {
    return model.critters.map((item) => ({
      id: String(item.id),
      x10: Number(item.x10),
      y10: Number(item.y10),
      vx10: Number(item.vx10),
      vy10: Number(item.vy10),
      portal_count: Number(item.portal_count || 0),
      occluded: Boolean(item.occluded),
      occluded_ticks: Number(item.occluded_ticks || 0),
    }));
  }

  function projectilePoint(projectile) {
    const flight = Number(model.state.arena.net_flight_ticks);
    return [
      projectile.origin10[0] + truncDiv((projectile.aim10[0] - projectile.origin10[0]) * projectile.age, flight),
      projectile.origin10[1] + truncDiv((projectile.aim10[1] - projectile.origin10[1]) * projectile.age, flight),
    ];
  }

  function projectilePublic() {
    if (!model.projectile) return null;
    return {
      id: model.projectile.id,
      age: model.projectile.age,
      x10: model.projectile.x10,
      y10: model.projectile.y10,
      aim: [Math.trunc(model.projectile.aim10[0] / 10), Math.trunc(model.projectile.aim10[1] / 10)],
    };
  }

  function finalPayload(completed) {
    const target = targetCritter();
    return {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      final_tick: model.tick,
      nets_remaining: model.nets,
      freeze_energy_ticks: model.freezeEnergy,
      freeze_ticks_used: model.freezeTicksUsed,
      lure: model.lure ? [Math.trunc(model.lure[0] / 10), Math.trunc(model.lure[1] / 10)] : null,
      target_captured: model.targetCaptured,
      target_hit_id: model.targetHitId,
      decoy_hits: model.decoyHits,
      misses: model.misses,
      reset_count: model.resetCount,
      preview_count: model.previewCount,
      final_critters: snapshot(),
      projectile: projectilePublic(),
      target_portal_transitions: Number(target?.portal_count || 0),
      target_occluded_ticks: Number(target?.occluded_ticks || 0),
      completed,
    };
  }

  function proofState() {
    const requirements = model.state.requirements;
    const target = targetCritter();
    return {
      lure: Boolean(model.lure),
      freeze: model.freezeTicksUsed >= Number(requirements.minimum_freeze_ticks) && model.freezeReleases >= 1,
      cover: Number(target?.occluded_ticks || 0) >= Number(requirements.target_occluded_ticks),
      portal: Number(target?.portal_count || 0) >= Number(requirements.target_portal_transitions),
    };
  }

  function proofReady() {
    return Object.values(proofState()).every(Boolean);
  }

  function stopClocks() {
    if (model.previewTimer) window.clearTimeout(model.previewTimer);
    if (model.worldTimer) window.clearInterval(model.worldTimer);
    model.previewTimer = null;
    model.worldTimer = null;
  }

  function setPhase(phase) {
    model.phase = phase;
    const shell = document.querySelector(".wizard-observatory");
    if (shell) shell.dataset.phase = phase;
  }

  function beginPreview() {
    setPhase("preview");
    model.previewStartedAt = performance.now();
    updateReadout("MEMORIZE THE MARKED FAMILIAR · OBSERVATION WINDOW", "pending");
    model.previewTimer = window.setTimeout(() => {
      if (model.terminal || model.phase !== "preview") return;
      const elapsed = Math.max(Number(model.state.requirements.preview_min_ms), Math.round(performance.now() - model.previewStartedAt));
      record("preview_complete", {elapsed_ms: elapsed, signature: model.state.target_cue.signature});
      model.previewCount += 1;
      setPhase("ready");
      updateReadout("SIGIL SHUTTERED · ARM AND PLACE THE LURE", "idle");
      updatePanels();
    }, 1080);
  }

  function armLure() {
    if (model.busy || model.terminal || model.phase !== "ready" || model.lure) return;
    model.lureArmed = !model.lureArmed;
    document.getElementById("wizard-lure-arm")?.classList.toggle("is-armed", model.lureArmed);
    updateReadout(model.lureArmed ? "LURE WELL ARMED · PLACE IT IN THE ARENA" : "LURE DISARMED", model.lureArmed ? "pending" : "idle");
  }

  function arenaPoint(event) {
    const canvas = event.currentTarget;
    const rect = canvas.getBoundingClientRect();
    return [
      clamp(Math.round((event.clientX - rect.left) / rect.width * Number(model.state.arena.width)), 0, Number(model.state.arena.width)),
      clamp(Math.round((event.clientY - rect.top) / rect.height * Number(model.state.arena.height)), 0, Number(model.state.arena.height)),
    ];
  }

  function placeLure(point) {
    model.lure = [point[0] * 10, point[1] * 10];
    model.lureArmed = false;
    const target = targetCritter();
    record("lure", {point, target_vector: lureVector(target, model.lure)});
    setPhase("hunt");
    model.worldTimer = window.setInterval(stepWorld, Number(model.state.arena.tick_ms));
    updateReadout("TRAJECTORIES BENDING · HOLD F, RELEASE, THEN LEAD A NET", "passed");
    updatePanels();
  }

  function launchNet(point) {
    if (model.phase !== "hunt" || model.busy || model.terminal) return;
    if (model.projectile || model.cooldown > 0) {
      updateReadout("ORB STILL IN FLIGHT · WAIT FOR THE COOLDOWN RING", "error");
      return;
    }
    if (model.nets <= 0) {
      updateReadout("NO NETS REMAIN", "error");
      return;
    }
    const origin = model.state.arena.projectile_origin.map(Number);
    model.launchCount += 1;
    const netId = `net-${model.launchCount}`;
    model.projectile = {
      id: netId,
      age: 0,
      origin10: [origin[0] * 10, origin[1] * 10],
      aim10: [point[0] * 10, point[1] * 10],
      x10: origin[0] * 10,
      y10: origin[1] * 10,
    };
    model.nets -= 1;
    model.cooldown = Number(model.state.arena.net_flight_ticks);
    record("net_launch", {
      tick: model.tick,
      net_id: netId,
      origin,
      aim: point,
      flight_ticks: Number(model.state.arena.net_flight_ticks),
    });
    updateReadout("NET LAUNCHED · IT WILL ARRIVE IN TWELVE CLOCK TICKS", "pending");
    updatePanels();
  }

  function arenaClick(event) {
    if (model.busy || model.terminal || model.phase === "preview") return;
    const point = arenaPoint(event);
    if (model.phase === "ready") {
      if (!model.lureArmed) {
        updateReadout("ARM THE LURE BEFORE TOUCHING THE FIELD", "error");
        return;
      }
      placeLure(point);
      return;
    }
    launchNet(point);
  }

  function freezeDown(event) {
    if (String(event.key).toLowerCase() !== "f" || event.repeat) return;
    if (model.phase !== "hunt" || model.busy || model.terminal || model.freezeActive || model.freezeEnergy <= 0) return;
    event.preventDefault();
    model.freezeActive = true;
    model.freezeDowns += 1;
    record("freeze_down", {tick: model.tick, key: "f"});
    document.querySelector(".wizard-observatory")?.classList.add("is-frozen");
    updateReadout("TIME GLASS ENGAGED · ENERGY DRAINING", "pending");
  }

  function freezeUp(event) {
    if (String(event.key).toLowerCase() !== "f" || !model.freezeActive) return;
    event.preventDefault();
    model.freezeActive = false;
    model.freezeReleases += 1;
    record("freeze_up", {tick: model.tick, key: "f"});
    document.querySelector(".wizard-observatory")?.classList.remove("is-frozen");
    updateReadout("TIME RELEASED · LEAD THE MOVING SIGIL", model.freezeTicksUsed >= Number(model.state.requirements.minimum_freeze_ticks) ? "passed" : "error");
    updatePanels();
  }

  function stepWorld() {
    if (model.phase !== "hunt" || model.busy || model.terminal || !model.lure) return;
    if (model.tick >= Number(model.state.requirements.time_limit_ticks)) {
      finish(false, "OBSERVATORY CLOCK EXPIRED");
      return;
    }
    model.tick += 1;
    const frozen = model.freezeActive && model.freezeEnergy > 0;
    const vector = lureVector(targetCritter(), model.lure);
    if (frozen) {
      model.freezeEnergy -= 1;
      model.freezeTicksUsed += 1;
    }
    const autoRelease = model.freezeActive && model.freezeEnergy === 0;
    model.critters = model.critters.map((item) => stepCritter(item, model.lure, frozen));
    model.cooldown = Math.max(0, model.cooldown - 1);
    let resolution = null;
    if (model.projectile) {
      model.projectile.age += 1;
      [model.projectile.x10, model.projectile.y10] = projectilePoint(model.projectile);
      model.trail.push({x10: model.projectile.x10, y10: model.projectile.y10, until: performance.now() + 650});
      const radius = Number(model.state.arena.creature_radius_x10) + Number(model.state.arena.net_radius_x10);
      const radiusSquared = radius * radius;
      let hitId = null;
      for (const critter of model.critters) {
        const dx = model.projectile.x10 - Number(critter.x10);
        const dy = model.projectile.y10 - Number(critter.y10);
        if (dx * dx + dy * dy <= radiusSquared) {
          hitId = String(critter.id);
          break;
        }
      }
      if (hitId) {
        resolution = {kind: hitId === model.targetId ? "target" : "decoy", net_id: model.projectile.id, critter_id: hitId};
        model.targetHitId = hitId;
        if (hitId === model.targetId) model.targetCaptured = true;
        else model.decoyHits += 1;
        model.projectile = null;
      } else if (model.projectile.age >= Number(model.state.arena.net_flight_ticks)) {
        resolution = {kind: "miss", net_id: model.projectile.id, critter_id: null};
        model.misses += 1;
        model.projectile = null;
      }
    }
    if (autoRelease) {
      model.freezeActive = false;
      document.querySelector(".wizard-observatory")?.classList.remove("is-frozen");
    }
    record("tick", {
      tick: model.tick,
      frozen,
      freeze_energy_after: model.freezeEnergy,
      freeze_ticks_used: model.freezeTicksUsed,
      freeze_auto_released: autoRelease,
      target_lure_vector: vector,
      critters: snapshot(),
      projectile: projectilePublic(),
      resolution,
      nets_after: model.nets,
      cooldown_after: model.cooldown,
    });
    updatePanels();
    if (resolution?.kind === "target") {
      const complete = proofReady();
      finish(complete, complete ? "MARKED FAMILIAR INTERCEPTED" : "TARGET TOUCHED BEFORE RITUAL PROOF");
    } else if (resolution?.kind === "decoy") {
      flashVerdict("DECOY", "A RELATED FAMILIAR TOOK THE NET", "error");
      updateReadout("DECOY STRIKE · ONE NET LOST", "error");
    } else if (resolution?.kind === "miss") {
      updateReadout("NET CLOSED ON EMPTY AIR · LEAD FARTHER", "error");
    }
    if (!model.targetCaptured && model.nets === 0 && !model.projectile && model.cooldown === 0) {
      finish(false, "ALL FOUR NETS SPENT");
    }
  }

  function resetWorld(event = null) {
    if (model.busy) return;
    if (event) record("reset", {tick_before: model.tick});
    stopClocks();
    model.resetCount += event ? 1 : 0;
    model.critters = clone(model.state.critters);
    model.tick = 0;
    model.lure = null;
    model.lureArmed = false;
    model.freezeActive = false;
    model.freezeEnergy = Number(model.state.requirements.freeze_energy_ticks);
    model.freezeTicksUsed = 0;
    model.freezeDowns = 0;
    model.freezeReleases = 0;
    model.nets = Number(model.state.requirements.net_count);
    model.cooldown = 0;
    model.projectile = null;
    model.launchCount = 0;
    model.targetCaptured = false;
    model.targetHitId = null;
    model.decoyHits = 0;
    model.misses = 0;
    model.terminal = false;
    model.trail = [];
    model.flash = null;
    document.querySelector(".wizard-observatory")?.classList.remove("is-frozen", "is-pass", "is-fail");
    document.querySelectorAll(".wizard-verdict").forEach((node) => node.remove());
    document.querySelector(".wizard-flash")?.remove();
    beginPreview();
    updatePanels();
  }

  function clearFreshFailure() {
    document.querySelector(".wizard-observatory")?.classList.remove("is-fresh-fail");
    document.querySelector(".wizard-verdict-fresh")?.remove();
  }

  async function finish(completed, reason) {
    if (model.busy || model.terminal) return;
    stopClocks();
    model.busy = true;
    model.terminal = true;
    setPhase("terminal");
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    updateReadout("CONSULTING THE INTERCEPTION LEDGER…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(finalPayload(completed)),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        const shell = document.querySelector(".wizard-observatory");
        shell?.classList.add("is-pass");
        shell?.insertAdjacentHTML("beforeend", '<div class="wizard-verdict wizard-verdict-pass"><small>MARKED FAMILIAR SECURED</small><strong>CAPTURE</strong><i>PASS</i></div>');
        updateReadout("PASS · PREDICTIVE INTERCEPTION CONFIRMED", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".wizard-observatory");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", `<div class="wizard-verdict wizard-verdict-fail wizard-verdict-fresh"><small>${clean(reason)} · NEW CONSTELLATION</small><strong>ESCAPED</strong><i>FAIL</i></div>`);
        updateReadout(`FAIL · ${reason} · FRESH OBSERVATORY`, "error");
        window.setTimeout(() => document.querySelector(".wizard-verdict-fresh")?.remove(), 720);
      } else {
        model.busy = false;
        model.terminal = false;
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
        updateReadout("FAIL · NO OBSERVATORY GRADE", "error");
      }
    } catch (_error) {
      model.busy = false;
      model.terminal = false;
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      updateReadout("FAIL · OBSERVATORY OFFLINE", "error");
    }
  }

  function flashVerdict(title, detail, status) {
    document.querySelector(".wizard-flash")?.remove();
    document.querySelector(".wizard-stage")?.insertAdjacentHTML("beforeend", `<div class="wizard-flash" data-status="${clean(status)}"><strong>${clean(title)}</strong><span>${clean(detail)}</span></div>`);
    window.setTimeout(() => document.querySelector(".wizard-flash")?.remove(), 900);
  }

  function updateReadout(message, status = "idle") {
    model.helpers?.setReadout(message, status);
  }

  function updatePanels() {
    const requirements = model.state.requirements;
    const proof = proofState();
    document.querySelectorAll("[data-wizard-proof]").forEach((node) => {
      node.classList.toggle("is-lit", Boolean(proof[node.dataset.wizardProof]));
    });
    const energy = document.getElementById("wizard-freeze-energy");
    if (energy) energy.style.setProperty("--level", String(model.freezeEnergy / Number(requirements.freeze_energy_ticks)));
    const energyText = document.getElementById("wizard-freeze-value");
    if (energyText) energyText.textContent = `${model.freezeEnergy} / ${requirements.freeze_energy_ticks}`;
    const used = document.getElementById("wizard-freeze-used");
    if (used) used.textContent = `${model.freezeTicksUsed} TICKS SPENT`;
    const nets = document.getElementById("wizard-nets");
    if (nets) nets.innerHTML = Array.from({length: Number(requirements.net_count)}, (_, index) => `<i class="${index < model.nets ? "is-live" : ""}"></i>`).join("");
    const clock = document.getElementById("wizard-clock");
    if (clock) clock.textContent = `${String(model.tick).padStart(3, "0")} / ${requirements.time_limit_ticks}`;
    const cooldown = document.getElementById("wizard-cooldown");
    if (cooldown) {
      cooldown.textContent = model.projectile ? `ORB ${model.projectile.age}/${model.state.arena.net_flight_ticks}` : model.cooldown ? `COOLDOWN ${model.cooldown}` : "ORB READY";
      cooldown.dataset.ready = !model.projectile && model.cooldown === 0 && model.nets > 0 ? "true" : "false";
    }
    const lureButton = document.getElementById("wizard-lure-arm");
    if (lureButton) {
      lureButton.classList.toggle("is-armed", model.lureArmed);
      lureButton.classList.toggle("is-spent", Boolean(model.lure));
      lureButton.disabled = model.phase !== "ready" || Boolean(model.lure) || model.busy;
    }
    const phase = document.getElementById("wizard-phase");
    if (phase) phase.textContent = model.phase === "preview" ? "OBSERVE" : model.phase === "ready" ? "PLACE LURE" : model.phase === "hunt" ? "INTERCEPT" : "LEDGER";
    const tape = document.getElementById("wizard-tape");
    if (tape) {
      const items = model.events.filter((event) => ["lure", "freeze_down", "freeze_up", "net_launch", "tick"].includes(event.kind))
        .filter((event) => event.kind !== "tick" || event.resolution)
        .slice(-5).reverse();
      tape.innerHTML = items.length ? items.map((event) => {
        const label = event.kind === "tick" ? String(event.resolution?.kind || "tick").toUpperCase() : event.kind.replaceAll("_", " ").toUpperCase();
        const value = event.kind === "net_launch" ? event.net_id : event.kind === "tick" ? event.resolution?.net_id : `T${String(event.tick ?? model.tick).padStart(3, "0")}`;
        return `<li><b>${String(event.sequence).padStart(3, "0")}</b><span>${clean(label)}</span><i>${clean(value)}</i></li>`;
      }).join("") : '<li><b>000</b><span>NO SPELLS CAST</span><i>—</i></li>';
    }
  }

  function glyphPath(context, glyph, scale = 1) {
    context.beginPath();
    if (glyph === "crescent") {
      context.arc(0, 0, 8 * scale, -.75 * Math.PI, .75 * Math.PI);
      context.arc(4 * scale, 0, 6 * scale, .7 * Math.PI, -.7 * Math.PI, true);
    } else if (glyph === "trident") {
      context.moveTo(0, 9 * scale); context.lineTo(0, -8 * scale); context.moveTo(-7 * scale, -5 * scale); context.quadraticCurveTo(-6 * scale, 1 * scale, 0, 0); context.moveTo(7 * scale, -5 * scale); context.quadraticCurveTo(6 * scale, 1 * scale, 0, 0);
    } else if (glyph === "hourglass") {
      context.moveTo(-7 * scale, -8 * scale); context.lineTo(7 * scale, -8 * scale); context.lineTo(-7 * scale, 8 * scale); context.lineTo(7 * scale, 8 * scale); context.closePath();
    } else if (glyph === "comet") {
      context.arc(3 * scale, -2 * scale, 5 * scale, 0, Math.PI * 2); context.moveTo(-1 * scale, 2 * scale); context.lineTo(-10 * scale, 9 * scale); context.moveTo(-3 * scale, -1 * scale); context.lineTo(-12 * scale, 3 * scale);
    } else if (glyph === "thorn") {
      context.moveTo(0, -9 * scale); context.lineTo(7 * scale, 7 * scale); context.lineTo(0, 3 * scale); context.lineTo(-7 * scale, 7 * scale); context.closePath();
    } else {
      context.rect(-6 * scale, -5 * scale, 12 * scale, 12 * scale); context.moveTo(-3 * scale, -5 * scale); context.quadraticCurveTo(0, -12 * scale, 3 * scale, -5 * scale);
    }
  }

  function drawCritter(context, critter, x, y, scale = 1, selected = false) {
    const appearance = critter.appearance;
    context.save();
    context.translate(x, y);
    context.scale(scale, scale);
    if (selected) {
      context.strokeStyle = appearance.accent;
      context.lineWidth = 2;
      context.setLineDash([3, 5]);
      context.beginPath(); context.arc(0, 0, 30, 0, Math.PI * 2); context.stroke();
      context.setLineDash([]);
    }
    context.strokeStyle = appearance.shadow;
    context.fillStyle = appearance.body;
    context.lineWidth = 3;
    context.beginPath();
    context.moveTo(-15, 9);
    if (appearance.tail === "fork") { context.lineTo(-28, 14); context.lineTo(-21, 4); context.lineTo(-29, -2); }
    else if (appearance.tail === "fan") { context.quadraticCurveTo(-33, 8, -25, -8); context.quadraticCurveTo(-19, 4, -15, 9); }
    else { context.quadraticCurveTo(-31, 11, -26, appearance.tail === "ribbon" ? -10 : 2); }
    context.stroke();
    context.beginPath(); context.ellipse(0, 2, 20, 16, 0, 0, Math.PI * 2); context.fill(); context.stroke();
    context.beginPath(); context.arc(11, -11, 12, 0, Math.PI * 2); context.fill(); context.stroke();
    context.beginPath();
    if (appearance.horn === "fork") { context.moveTo(5, -20); context.lineTo(1, -32); context.moveTo(4, -27); context.lineTo(-3, -29); context.moveTo(15, -22); context.lineTo(20, -33); context.moveTo(18, -28); context.lineTo(25, -27); }
    else if (appearance.horn === "curl") { context.arc(4, -24, 6, .3, Math.PI * 2); context.moveTo(17, -20); context.arc(18, -25, 6, 2.8, -.2); }
    else if (appearance.horn === "leaf") { context.moveTo(4, -20); context.quadraticCurveTo(-2, -34, 8, -29); context.moveTo(16, -21); context.quadraticCurveTo(24, -34, 22, -24); }
    else { context.moveTo(5, -20); context.lineTo(4, -34); context.moveTo(17, -21); context.lineTo(20, -34); }
    context.stroke();
    context.fillStyle = appearance.shadow;
    for (let eye = 0; eye < Number(appearance.eyes); eye += 1) {
      context.beginPath(); context.arc(7 + eye * 6, -12, 1.8, 0, Math.PI * 2); context.fill();
    }
    context.strokeStyle = appearance.accent;
    context.lineWidth = 2;
    glyphPath(context, appearance.glyph, .7); context.stroke();
    context.fillStyle = appearance.accent;
    for (let index = 0; index < Number(appearance.spots); index += 1) {
      context.beginPath(); context.arc(-11 + (index % 3) * 8, 5 + Math.floor(index / 3) * 6, 1.5, 0, Math.PI * 2); context.fill();
    }
    context.restore();
  }

  function drawPortal(context, portal, time, active) {
    context.save();
    context.translate(Number(portal.x), Number(portal.y));
    context.strokeStyle = getComputedStyle(document.body).getPropertyValue("--wizard-magic").trim() || "#33c7b4";
    context.lineWidth = active ? 6 : 3;
    context.globalAlpha = active ? 1 : .68;
    for (let ring = 0; ring < 3; ring += 1) {
      context.beginPath();
      context.ellipse(0, 0, 7 + ring * 6, 30 + ring * 5, 0, time / 900 + ring, time / 900 + ring + 4.6);
      context.stroke();
    }
    context.restore();
  }

  function drawOccluder(context, item) {
    const x = Number(item.x), y = Number(item.y), width = Number(item.width), height = Number(item.height);
    context.save();
    if (item.kind === "curtain") {
      const gradient = context.createLinearGradient(x, y, x + width, y);
      gradient.addColorStop(0, "#5d2c45"); gradient.addColorStop(.5, "#b06771"); gradient.addColorStop(1, "#48243e");
      context.fillStyle = gradient; context.fillRect(x, y, width, height);
      context.strokeStyle = "rgba(255,230,190,.22)";
      for (let offset = 12; offset < width; offset += 18) { context.beginPath(); context.moveTo(x + offset, y); context.quadraticCurveTo(x + offset - 8, y + height / 2, x + offset, y + height); context.stroke(); }
      context.fillStyle = "#d2a267"; context.fillRect(x - 6, y - 7, width + 12, 7);
    } else if (item.kind === "tower") {
      context.fillStyle = "#263747"; context.fillRect(x, y + 18, width, height - 18);
      context.fillStyle = "#334c5b";
      for (let index = 0; index < 5; index += 1) context.fillRect(x + index * width / 5, y, width / 10, 22);
      context.strokeStyle = "rgba(224,213,171,.18)"; context.strokeRect(x + 10, y + 36, width - 20, height - 50);
      context.fillStyle = "#9dc8b4"; context.beginPath(); context.arc(x + width / 2, y + 62, 18, 0, Math.PI * 2); context.fill();
      context.fillStyle = "#263747"; context.beginPath(); context.arc(x + width / 2 + 7, y + 57, 16, 0, Math.PI * 2); context.fill();
    } else {
      const gradient = context.createLinearGradient(x, y, x, y + height);
      gradient.addColorStop(0, "rgba(212,226,214,.96)"); gradient.addColorStop(1, "rgba(107,137,133,.96)");
      context.fillStyle = gradient;
      context.beginPath(); context.moveTo(x, y + 30); context.bezierCurveTo(x + 30, y - 5, x + 58, y + 24, x + 88, y + 8); context.bezierCurveTo(x + 132, y - 6, x + width, y + 30, x + width, y + 58); context.lineTo(x + width, y + height); context.lineTo(x, y + height); context.closePath(); context.fill();
    }
    context.strokeStyle = "rgba(26,37,44,.72)"; context.lineWidth = 2; context.strokeRect(x, y, width, height);
    context.restore();
  }

  function drawPreview(context, width, height) {
    const cue = model.state.target_cue;
    context.save();
    context.fillStyle = "rgba(16,26,35,.88)"; context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(231,223,197,.18)";
    for (let radius = 55; radius < 250; radius += 42) { context.beginPath(); context.arc(width / 2, height / 2, radius, 0, Math.PI * 2); context.stroke(); }
    context.fillStyle = "rgba(51,199,180,.1)"; context.beginPath(); context.arc(width / 2, height / 2, 96, 0, Math.PI * 2); context.fill();
    drawCritter(context, {appearance: cue.appearance}, width / 2, height / 2 + 10, 2.45, true);
    context.fillStyle = "#e7dfc5"; context.font = "700 14px Courier New"; context.textAlign = "center"; context.fillText("MEMORIZE THIS FAMILIAR", width / 2, 62);
    context.fillStyle = "#77d8c6"; context.font = "12px Courier New"; context.fillText(cue.mnemonic.toUpperCase(), width / 2, height - 54);
    context.restore();
  }

  function drawArena(timestamp) {
    const canvas = document.getElementById("wizard-arena");
    if (!canvas || !model.state) return;
    const context = canvas.getContext("2d");
    const width = Number(model.state.arena.width), height = Number(model.state.arena.height);
    const palette = model.state.palette;
    context.clearRect(0, 0, width, height);
    context.fillStyle = palette.paper; context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(28,48,60,.09)"; context.lineWidth = 1;
    for (let x = 0; x <= width; x += 28) { context.beginPath(); context.moveTo(x, 0); context.lineTo(x, height); context.stroke(); }
    for (let y = 0; y <= height; y += 28) { context.beginPath(); context.moveTo(0, y); context.lineTo(width, y); context.stroke(); }
    context.strokeStyle = "rgba(39,52,73,.2)";
    for (let radius = 80; radius <= 420; radius += 72) { context.beginPath(); context.arc(width / 2, height / 2, radius, 0, Math.PI * 2); context.stroke(); }
    context.fillStyle = "rgba(39,52,73,.68)"; context.font = "9px Courier New";
    context.fillText("WEST MOON", 9, 24); context.fillText("EAST MOON", width - 74, 24);
    if (model.phase === "preview") {
      drawPreview(context, width, height);
      return;
    }
    model.state.portals.forEach((portal) => drawPortal(context, portal, timestamp, Boolean(model.flash && model.flash.until > performance.now() && model.flash.side === (portal.x < width / 2 ? "west" : "east"))));
    if (model.lure) {
      const x = model.lure[0] / 10, y = model.lure[1] / 10;
      const pulse = 30 + Math.sin(timestamp / 120) * 6;
      context.strokeStyle = palette.magic; context.lineWidth = 2; context.setLineDash([5, 7]);
      context.beginPath(); context.arc(x, y, pulse, 0, Math.PI * 2); context.stroke(); context.setLineDash([]);
      context.fillStyle = palette.magic; context.beginPath(); context.arc(x, y, 7, 0, Math.PI * 2); context.fill();
      context.fillStyle = palette.ink; context.font = "8px Courier New"; context.fillText("LURE", x + 12, y - 10);
    }
    model.trail = model.trail.filter((point) => point.until > performance.now());
    model.trail.forEach((point, index) => {
      context.globalAlpha = (index + 1) / (model.trail.length + 1) * .55;
      context.fillStyle = palette.danger; context.beginPath(); context.arc(point.x10 / 10, point.y10 / 10, 4, 0, Math.PI * 2); context.fill();
    });
    context.globalAlpha = 1;
    model.critters.forEach((critter) => drawCritter(context, critter, Number(critter.x10) / 10, Number(critter.y10) / 10, 1, false));
    if (model.projectile) {
      const x = model.projectile.x10 / 10, y = model.projectile.y10 / 10;
      context.strokeStyle = palette.danger; context.lineWidth = 2; context.beginPath(); context.arc(x, y, 10 + model.projectile.age, 0, Math.PI * 2); context.stroke();
      context.beginPath(); context.moveTo(x - 8, y - 8); context.lineTo(x + 8, y + 8); context.moveTo(x + 8, y - 8); context.lineTo(x - 8, y + 8); context.stroke();
    }
    model.state.occluders.forEach((item) => drawOccluder(context, item));
    if (model.freezeActive) {
      context.fillStyle = "rgba(90,176,214,.10)"; context.fillRect(0, 0, width, height);
      context.strokeStyle = "rgba(150,231,244,.7)"; context.lineWidth = 4; context.strokeRect(4, 4, width - 8, height - 8);
    }
  }

  function drawTargetToken() {
    const canvas = document.getElementById("wizard-target-token");
    if (!canvas) return;
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, canvas.width, canvas.height);
    drawCritter(context, {appearance: model.state.target_cue.appearance}, canvas.width / 2, canvas.height / 2 + 7, 1.28, true);
  }

  function animate(timestamp) {
    if (!model.state) return;
    drawArena(timestamp);
    drawTargetToken();
    model.animationFrame = requestAnimationFrame(animate);
  }

  async function render(state, helpers) {
    stopClocks();
    if (model.animationFrame) cancelAnimationFrame(model.animationFrame);
    document.body.dataset.mechanic = "wizard-critter-capture";
    document.body.style.setProperty("--wizard-ink", state.palette.ink);
    document.body.style.setProperty("--wizard-paper", state.palette.paper);
    document.body.style.setProperty("--wizard-magic", state.palette.magic);
    document.body.style.setProperty("--wizard-danger", state.palette.danger);
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    Object.assign(model, {
      state,
      helpers,
      critters: clone(state.critters),
      targetId: String(state.critters.find((item) => appearancesMatch(item.appearance, state.target_cue.appearance))?.id || ""),
      phase: "preview",
      tick: 0,
      events: [],
      resetCount: 0,
      previewCount: 0,
      lure: null,
      lureArmed: false,
      freezeActive: false,
      freezeEnergy: Number(state.requirements.freeze_energy_ticks),
      freezeTicksUsed: 0,
      freezeDowns: 0,
      freezeReleases: 0,
      nets: Number(state.requirements.net_count),
      cooldown: 0,
      projectile: null,
      launchCount: 0,
      targetCaptured: false,
      targetHitId: null,
      decoyHits: 0,
      misses: 0,
      busy: false,
      terminal: false,
      flash: null,
      trail: [],
    });
    helpers.app.innerHTML = `<section class="wizard-observatory" data-challenge-id="${clean(state.challenge_id)}" data-phase="preview">
      <header class="wizard-head"><div><span>ROYAL WIZARD INTERCEPTION OBSERVATORY / FIELD LEDGER Ⅳ</span><h1>${clean(state.prompt)}</h1></div><aside><small>CURRENT OPERATION</small><b id="wizard-phase">OBSERVE</b><i>${clean(state.palette.name).replaceAll("_", " ")}</i></aside></header>
      <main class="wizard-workbench"><section class="wizard-stage"><canvas id="wizard-arena" width="${state.arena.width}" height="${state.arena.height}" aria-label="moving wizard familiar interception arena"></canvas><div class="wizard-stage-key"><span>F · HOLD TIME GLASS</span><i>CLICK · LAUNCH TRAVELING NET</i><b>PORTALS WRAP EAST ↔ WEST</b></div></section>
      <aside class="wizard-console"><div class="wizard-console-title"><span>MARKED FAMILIAR / MEMORY PLATE</span><i>DO NOT LOSE IT</i></div><div class="wizard-target"><canvas id="wizard-target-token" width="116" height="86"></canvas><div><small>SIGIL MNEMONIC</small><b>${clean(state.target_cue.mnemonic)}</b><i>identity vanishes after observation</i></div></div>
      <button type="button" class="wizard-lure" id="wizard-lure-arm"><span>✦</span><b>ARM LURE WELL</b><small>ONE PLACEMENT · BENDS ALL PATHS</small></button>
      <section class="wizard-freeze"><header><span>TIME GLASS / HOLD F</span><b id="wizard-freeze-value">${state.requirements.freeze_energy_ticks} / ${state.requirements.freeze_energy_ticks}</b></header><div id="wizard-freeze-energy"><i></i></div><footer><span id="wizard-freeze-used">0 TICKS SPENT</span><b>${state.requirements.minimum_freeze_ticks} REQUIRED</b></footer></section>
      <section class="wizard-ammo"><header><span>TRAVELING NET ORBS</span><b id="wizard-cooldown" data-ready="true">ORB READY</b></header><div id="wizard-nets">${Array.from({length: state.requirements.net_count}, () => '<i class="is-live"></i>').join("")}</div><small>DECOYS CONSUME ORBS · FLIGHT = ${state.arena.net_flight_ticks} TICKS</small></section>
      <div class="wizard-proof"><span data-wizard-proof="lure"><i></i>LURE CAST</span><span data-wizard-proof="freeze"><i></i>TIME SPENT</span><span data-wizard-proof="cover"><i></i>COVER TRACKED</span><span data-wizard-proof="portal"><i></i>PORTAL SEEN</span></div>
      <ol class="wizard-tape" id="wizard-tape"><li><b>000</b><span>NO SPELLS CAST</span><i>—</i></li></ol></aside></main>
      <footer class="wizard-foot"><button type="button" id="wizard-reset">↺ RESET OBSERVATORY</button><div><div class="readout" data-status="pending">MEMORIZE THE MARKED FAMILIAR · OBSERVATION WINDOW</div><div class="wizard-clockline"><span>ASTRAL CLOCK</span><b id="wizard-clock">000 / ${state.requirements.time_limit_ticks}</b></div></div><section><span>INTERCEPTION RULE</span><b>LEAD THE TARGET</b><small>CLICKING ITS CURRENT POSITION ARRIVES LATE</small></section></footer>
      ${helpers.cheatPanelTemplate()}</section>`;
    document.getElementById("wizard-arena")?.addEventListener("click", arenaClick);
    document.getElementById("wizard-lure-arm")?.addEventListener("click", armLure);
    document.getElementById("wizard-reset")?.addEventListener("click", (event) => { clearFreshFailure(); resetWorld(event); });
    window.addEventListener("keydown", freezeDown);
    window.addEventListener("keyup", freezeUp);
    helpers.installCheatPanel();
    window.wizardCritterCaptureModel = model;
    beginPreview();
    updatePanels();
    model.animationFrame = requestAnimationFrame(animate);
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.wizard_critter_capture = {rootSelector: ".wizard-observatory", render};
})();
