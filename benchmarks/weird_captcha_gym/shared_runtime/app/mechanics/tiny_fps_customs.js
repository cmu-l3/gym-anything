(() => {
  "use strict";

  const FOV = Math.PI * 0.3666667;
  const VIEW_WIDTH = 720;
  const VIEW_HEIGHT = 420;
  const model = {
    state: null,
    helpers: null,
    pose: null,
    alive: new Set(),
    ammo: 0,
    actions: [],
    hitLedger: [],
    eliminatedIds: [],
    counts: {moves: 0, turns: 0, shots: 0, collisions: 0, resets: 0},
    startedAt: 0,
    frame: 0,
    keyHandler: null,
    drag: null,
    suppressClick: false,
    feedbackUntil: 0,
    feedbackKind: "idle",
    feedbackText: "",
    submitting: false,
    terminal: false,
    spriteCache: new Map(),
  };

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function q(value) {
    return Math.round(value * 1e6) / 1e6;
  }

  function normalizeAngle(value) {
    return ((Math.round(value) % 360000) + 360000) % 360000;
  }

  function angleRadians(angleMdeg = model.pose.angle_mdeg) {
    return angleMdeg / 1000 * Math.PI / 180;
  }

  function signedAngle(value) {
    let angle = value;
    while (angle > Math.PI) angle -= Math.PI * 2;
    while (angle < -Math.PI) angle += Math.PI * 2;
    return angle;
  }

  function poseObject() {
    return {x: q(model.pose.x), y: q(model.pose.y), angle_mdeg: normalizeAngle(model.pose.angle_mdeg)};
  }

  function elapsed() {
    return Math.max(0, Math.round(performance.now() - model.startedAt));
  }

  function record(action) {
    model.actions.push({...action, seq: model.actions.length + 1, t_ms: elapsed()});
  }

  function traitKey(traits) {
    return [
      traits?.palette_name,
      traits?.body,
      traits?.shadow,
      traits?.accent,
      traits?.horn,
      Number(traits?.eyes),
      traits?.mark,
      traits?.stripe,
    ].join("|");
  }

  function wantedKeys() {
    return new Set((model.state?.wanted_posters || []).map((poster) => traitKey(poster.traits)));
  }

  function isWanted(creature) {
    return wantedKeys().has(traitKey(creature?.traits));
  }

  function creatureById(id) {
    return (model.state?.creatures || []).find((creature) => String(creature.id) === String(id));
  }

  function cleanup() {
    if (model.frame) cancelAnimationFrame(model.frame);
    model.frame = 0;
    if (model.keyHandler) window.removeEventListener("keydown", model.keyHandler);
    model.keyHandler = null;
  }

  function circleClear(x, y) {
    const rows = model.state.map;
    const radius = Number(model.state.player_radius || 0.18);
    const minX = Math.floor(x - radius);
    const maxX = Math.floor(x + radius);
    const minY = Math.floor(y - radius);
    const maxY = Math.floor(y + radius);
    for (let cellY = minY; cellY <= maxY; cellY += 1) {
      for (let cellX = minX; cellX <= maxX; cellX += 1) {
        if (cellY < 0 || cellY >= rows.length || cellX < 0 || cellX >= rows[0].length) return false;
        if (rows[cellY][cellX] !== "#") continue;
        const nearestX = Math.max(cellX, Math.min(x, cellX + 1));
        const nearestY = Math.max(cellY, Math.min(y, cellY + 1));
        const dx = x - nearestX;
        const dy = y - nearestY;
        if (dx * dx + dy * dy < radius * radius - 1e-10) return false;
      }
    }
    return true;
  }

  function castWall(x, y, angleMdeg) {
    const rows = model.state.map;
    const angle = angleRadians(angleMdeg);
    const directionX = Math.cos(angle);
    const directionY = Math.sin(angle);
    let mapX = Math.floor(x);
    let mapY = Math.floor(y);
    const deltaX = Math.abs(directionX) > 1e-12 ? Math.abs(1 / directionX) : 1e30;
    const deltaY = Math.abs(directionY) > 1e-12 ? Math.abs(1 / directionY) : 1e30;
    const stepX = directionX < 0 ? -1 : 1;
    const stepY = directionY < 0 ? -1 : 1;
    let sideX = directionX < 0 ? (x - mapX) * deltaX : (mapX + 1 - x) * deltaX;
    let sideY = directionY < 0 ? (y - mapY) * deltaY : (mapY + 1 - y) * deltaY;
    let side = 0;
    let distance = 0;
    for (let count = 0; count < 256; count += 1) {
      if (sideX < sideY) {
        distance = sideX;
        sideX += deltaX;
        mapX += stepX;
        side = 0;
      } else {
        distance = sideY;
        sideY += deltaY;
        mapY += stepY;
        side = 1;
      }
      if (mapY < 0 || mapY >= rows.length || mapX < 0 || mapX >= rows[0].length || rows[mapY][mapX] === "#") {
        return {distance, side, mapX, mapY};
      }
    }
    return {distance: 1e9, side, mapX, mapY};
  }

  function rayCreatureDistance(creature, angleMdeg) {
    const angle = angleRadians(angleMdeg);
    const directionX = Math.cos(angle);
    const directionY = Math.sin(angle);
    const offsetX = model.pose.x - Number(creature.x);
    const offsetY = model.pose.y - Number(creature.y);
    const radius = Number(model.state.creature_radius || 0.27);
    const b = directionX * offsetX + directionY * offsetY;
    const c = offsetX * offsetX + offsetY * offsetY - radius * radius;
    const discriminant = b * b - c;
    if (discriminant < 0) return null;
    const distance = -b - Math.sqrt(discriminant);
    return distance >= 0.04 ? distance : null;
  }

  function shotResult() {
    const wall = castWall(model.pose.x, model.pose.y, model.pose.angle_mdeg);
    let hitId = null;
    let distance = wall.distance;
    (model.state.creatures || []).forEach((creature) => {
      if (!model.alive.has(String(creature.id))) return;
      const candidate = rayCreatureDistance(creature, model.pose.angle_mdeg);
      if (candidate != null && candidate < distance - 1e-8) {
        distance = candidate;
        hitId = String(creature.id);
      }
    });
    return hitId ? {outcome: "creature", hitId, distance} : {outcome: "wall", hitId: null, distance: wall.distance};
  }

  function setFeedback(text, kind = "idle", duration = 1300) {
    model.feedbackText = text;
    model.feedbackKind = kind;
    model.feedbackUntil = performance.now() + duration;
    const node = document.querySelector(".fps-hit-feedback");
    if (node) {
      node.textContent = text;
      node.dataset.kind = kind;
      node.classList.add("is-visible");
    }
  }

  function updateHud() {
    const ammo = document.querySelector(".fps-ammo-pips");
    if (ammo) {
      ammo.innerHTML = Array.from({length: Number(model.state.ammo || 0)}, (_, index) =>
        `<i class="${index < model.ammo ? "live" : "spent"}"></i>`).join("");
    }
    const eliminated = document.querySelector(".fps-warrant-count");
    if (eliminated) eliminated.textContent = `${model.eliminatedIds.length} / ${(model.state.wanted_posters || []).length}`;
    const location = document.querySelector(".fps-sector");
    if (location) location.textContent = `${String(Math.floor(model.pose.x)).padStart(2, "0")}.${String(Math.floor(model.pose.y)).padStart(2, "0")}`;
    const compass = document.querySelector(".fps-compass-bearing");
    if (compass) {
      const cardinal = ["E", "SE", "S", "SW", "W", "NW", "N", "NE"];
      compass.textContent = cardinal[Math.round(model.pose.angle_mdeg / 45000) % 8];
      compass.style.setProperty("--bearing", `${model.pose.angle_mdeg / 1000}deg`);
    }
  }

  function turn(deltaMdeg) {
    if (model.terminal || model.submitting) return;
    const delta = Math.max(-36000, Math.min(36000, Math.round(deltaMdeg)));
    if (!delta) return;
    const before = normalizeAngle(model.pose.angle_mdeg);
    model.pose.angle_mdeg = normalizeAngle(before + delta);
    model.counts.turns += 1;
    record({type: "turn", delta_mdeg: delta, before_mdeg: before, after_mdeg: model.pose.angle_mdeg});
    updateHud();
  }

  function move(forward, strafe) {
    if (model.terminal || model.submitting) return;
    const from = poseObject();
    const angle = angleRadians();
    const step = Number(model.state.move_step || 0.2);
    const intendedX = q(model.pose.x + (Math.cos(angle) * forward + Math.cos(angle + Math.PI / 2) * strafe) * step);
    const intendedY = q(model.pose.y + (Math.sin(angle) * forward + Math.sin(angle + Math.PI / 2) * strafe) * step);
    const blockedX = !circleClear(intendedX, model.pose.y);
    if (!blockedX) model.pose.x = intendedX;
    const blockedY = !circleClear(model.pose.x, intendedY);
    if (!blockedY) model.pose.y = intendedY;
    model.pose.x = q(model.pose.x);
    model.pose.y = q(model.pose.y);
    model.counts.moves += 1;
    if (blockedX || blockedY) {
      model.counts.collisions += 1;
      setFeedback("BULKHEAD · ROUTE DENIED", "wall", 520);
    }
    record({type: "move", forward, strafe, from, to: poseObject(), blocked_x: blockedX, blocked_y: blockedY});
    updateHud();
  }

  function showTerminal(state, title, detail) {
    model.terminal = true;
    const viewport = document.querySelector(".fps-viewport-frame");
    if (!viewport) return;
    let terminal = viewport.querySelector(".fps-terminal");
    if (!terminal) {
      terminal = document.createElement("div");
      terminal.className = "fps-terminal";
      viewport.appendChild(terminal);
    }
    terminal.dataset.state = state;
    terminal.innerHTML = `<span>${clean(title)}</span><strong>${clean(state.toUpperCase())}</strong><p>${clean(detail)}</p>`;
  }

  function payload(completed) {
    return {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      actions: model.actions,
      completed,
      final_pose: poseObject(),
      ammo_remaining: model.ammo,
      eliminated_ids: [...model.eliminatedIds],
      protected_survivors: model.alive.size,
      hit_ledger: model.hitLedger,
      interaction_counts: {...model.counts},
    };
  }

  async function submit(completed, failReason = "") {
    if (model.submitting) return;
    model.submitting = true;
    const failedAt = performance.now();
    if (!completed) {
      showTerminal("fail", "CIVILIAN CASUALTY", failReason || "PROTECTED TRAVELLER HIT · DOSSIER REVOKED");
      model.helpers.setReadout("FAIL · CUSTOMS INCIDENT", "error");
    } else {
      model.helpers.setReadout("VERIFYING GEOMETRY + BALLISTICS…", "pending");
    }
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload(completed)),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        showTerminal("pass", "ALL WARRANTS CLEARED", "PROTECTED MANIFEST INTACT · TRANSIT AUTHORIZED");
        model.helpers.setReadout("PASS · CUSTOMS SEALED", "passed");
        updateHud();
        return;
      }
      if (outcome.passed === false && outcome.state) {
        if (completed) showTerminal("fail", "BALLISTICS REJECTED", "TRACE INVALID · NEW DOSSIER ISSUED");
        const remaining = Math.max(0, 850 - (performance.now() - failedAt));
        if (remaining) await new Promise((resolve) => window.setTimeout(resolve, remaining));
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".tiny-fps-customs");
        if (shell) shell.dataset.freshFailure = "true";
        model.helpers.setReadout("FAIL · FRESH MANIFEST", "error");
        return;
      }
      model.helpers.setReadout("FAIL · NO CUSTOMS GRADE", "error");
      model.submitting = false;
      model.terminal = false;
    } catch (_error) {
      model.helpers.setReadout("FAIL · CUSTOMS LINK LOST", "error");
      model.submitting = false;
      model.terminal = false;
    }
  }

  async function fire() {
    if (model.terminal || model.submitting) return;
    const origin = poseObject();
    const ammoBefore = model.ammo;
    let result = {outcome: "empty", hitId: null, distance: 0};
    if (model.ammo > 0) {
      model.ammo -= 1;
      result = shotResult();
    }
    model.counts.shots += 1;
    if (result.hitId) {
      model.alive.delete(result.hitId);
      model.hitLedger.push({shot: model.counts.shots, creature_id: result.hitId});
    }
    record({
      type: "shot",
      origin,
      ammo_before: ammoBefore,
      ammo_after: model.ammo,
      outcome: result.outcome,
      hit_id: result.hitId,
      distance: q(result.distance),
    });
    updateHud();
    const viewport = document.querySelector(".fps-viewport-frame");
    if (viewport) {
      viewport.classList.remove("fps-recoil");
      void viewport.offsetWidth;
      viewport.classList.add("fps-recoil");
    }
    if (!result.hitId) {
      setFeedback(result.outcome === "empty" ? "CHAMBER EMPTY · RESET OR REISSUE" : "IMPACT / BULKHEAD", result.outcome, 1000);
      model.helpers.setReadout(result.outcome === "empty" ? "AMMO DEPLETED" : "SHOT LOGGED · NO CONTACT", "idle");
      return;
    }
    const creature = creatureById(result.hitId);
    if (!isWanted(creature)) {
      setFeedback("PROTECTED TRAVELLER HIT", "protected", 4000);
      await submit(false, "PROTECTED TRAVELLER HIT · DOSSIER REVOKED");
      return;
    }
    model.eliminatedIds.push(result.hitId);
    updateHud();
    setFeedback(`WARRANT CONFIRMED · ${model.eliminatedIds.length}/3`, "wanted", 1500);
    model.helpers.setReadout(`WARRANT ${model.eliminatedIds.length}/3 CLEARED`, "idle");
    if (model.eliminatedIds.length === (model.state.wanted_posters || []).length) {
      await submit(true);
    }
  }

  function resetLocal() {
    if (model.submitting) return;
    model.pose = {...model.state.initial_pose};
    model.pose.x = Number(model.pose.x);
    model.pose.y = Number(model.pose.y);
    model.pose.angle_mdeg = normalizeAngle(model.pose.angle_mdeg);
    model.alive = new Set((model.state.creatures || []).map((creature) => String(creature.id)));
    model.ammo = Number(model.state.ammo || 0);
    model.hitLedger = [];
    model.eliminatedIds = [];
    model.terminal = false;
    model.counts.resets += 1;
    record({type: "reset", pose: poseObject(), ammo: model.ammo});
    const terminal = document.querySelector(".fps-terminal");
    if (terminal) terminal.remove();
    setFeedback("SHIFT RESET · ORIGINAL MANIFEST", "idle", 900);
    model.helpers.setReadout("RUN RESET · DOSSIER UNCHANGED", "idle");
    updateHud();
  }

  async function reissue() {
    if (model.submitting) return;
    model.submitting = true;
    model.helpers.setReadout("REQUESTING NEW MANIFEST…", "pending");
    try {
      const response = await fetch("/state", {cache: "no-store"});
      const state = await response.json();
      await model.helpers.render(state);
      model.helpers.setReadout("NEW MANIFEST ISSUED", "idle");
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("REISSUE LINK FAILED", "error");
    }
  }

  function drawCreature(ctx, traits, centerX, baseline, scale, pose = "alert") {
    ctx.save();
    ctx.translate(centerX, baseline);
    ctx.scale(scale, scale);
    const lean = pose === "side-eye" ? -0.08 : pose === "stooped" ? 0.05 : 0;
    ctx.rotate(lean);
    ctx.lineJoin = "round";
    ctx.lineCap = "round";

    ctx.fillStyle = "rgba(0,0,0,.3)";
    ctx.beginPath();
    ctx.ellipse(0, 4, 38, 8, 0, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = traits.shadow;
    ctx.beginPath();
    ctx.moveTo(-29, -9);
    ctx.bezierCurveTo(-38, -39, -26, -76, 0, -80);
    ctx.bezierCurveTo(30, -78, 39, -40, 27, -8);
    ctx.quadraticCurveTo(4, 5, -29, -9);
    ctx.fill();
    ctx.fillStyle = traits.body;
    ctx.beginPath();
    ctx.moveTo(-24, -12);
    ctx.bezierCurveTo(-31, -39, -22, -68, 1, -72);
    ctx.bezierCurveTo(25, -68, 31, -39, 22, -11);
    ctx.quadraticCurveTo(2, 0, -24, -12);
    ctx.fill();

    if (traits.stripe !== "none") {
      ctx.strokeStyle = traits.accent;
      ctx.lineWidth = 7;
      ctx.globalAlpha = 0.84;
      ctx.beginPath();
      const stripeY = traits.stripe === "shoulder" ? -49 : -27;
      ctx.moveTo(-23, stripeY);
      ctx.quadraticCurveTo(0, stripeY + 8, 23, stripeY);
      ctx.stroke();
      ctx.globalAlpha = 1;
    }

    ctx.strokeStyle = traits.accent;
    ctx.fillStyle = traits.accent;
    ctx.lineWidth = 4;
    if (traits.horn === "fork") {
      [-13, 13].forEach((x) => {
        ctx.beginPath(); ctx.moveTo(x, -64); ctx.lineTo(x * 1.25, -91); ctx.lineTo(x * 1.75, -102); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(x * 1.25, -91); ctx.lineTo(x * 0.65, -101); ctx.stroke();
      });
    } else if (traits.horn === "spiral") {
      [-1, 1].forEach((side) => {
        ctx.beginPath();
        ctx.arc(side * 19, -82, 13, side > 0 ? Math.PI * 0.2 : Math.PI * 0.8, side > 0 ? Math.PI * 2.1 : -Math.PI * 1.1, side < 0);
        ctx.stroke();
      });
    } else if (traits.horn === "blade") {
      ctx.beginPath(); ctx.moveTo(-20, -66); ctx.lineTo(-36, -102); ctx.lineTo(-7, -76); ctx.fill();
      ctx.beginPath(); ctx.moveTo(20, -66); ctx.lineTo(36, -102); ctx.lineTo(7, -76); ctx.fill();
    } else {
      [-12, 12].forEach((x) => {
        ctx.beginPath(); ctx.moveTo(x, -66); ctx.quadraticCurveTo(x * 1.7, -91, x * 1.2, -105); ctx.stroke();
        ctx.beginPath(); ctx.arc(x * 1.2, -106, 5, 0, Math.PI * 2); ctx.fill();
      });
    }

    const eyeCount = Number(traits.eyes || 2);
    const eyeXs = eyeCount === 1 ? [0] : eyeCount === 2 ? [-10, 10] : [-15, 0, 15];
    eyeXs.forEach((x) => {
      ctx.fillStyle = "#f7ffe8";
      ctx.beginPath(); ctx.ellipse(x, -49, 6, 8, 0, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = traits.shadow;
      ctx.beginPath(); ctx.arc(x + (pose === "side-eye" ? -2 : 1), -48, 2.5, 0, Math.PI * 2); ctx.fill();
    });

    ctx.strokeStyle = traits.accent;
    ctx.fillStyle = traits.accent;
    ctx.lineWidth = 4;
    const markY = -23;
    if (traits.mark === "ring") {
      ctx.beginPath(); ctx.arc(0, markY, 9, 0, Math.PI * 2); ctx.stroke();
    } else if (traits.mark === "chevron") {
      ctx.beginPath(); ctx.moveTo(-11, markY - 4); ctx.lineTo(0, markY + 7); ctx.lineTo(11, markY - 4); ctx.stroke();
    } else if (traits.mark === "triple-dot") {
      [-10, 0, 10].forEach((x) => { ctx.beginPath(); ctx.arc(x, markY, 3.5, 0, Math.PI * 2); ctx.fill(); });
    } else {
      ctx.fillRect(-13, markY - 3, 10, 6);
      ctx.fillRect(3, markY - 3, 10, 6);
    }

    ctx.restore();
  }

  function creatureSprite(creature) {
    const cacheKey = `${String(creature.id)}|${traitKey(creature.traits)}|${creature.pose}`;
    if (model.spriteCache.has(cacheKey)) return model.spriteCache.get(cacheKey);
    const canvas = document.createElement("canvas");
    canvas.width = 220;
    canvas.height = 260;
    const ctx = canvas.getContext("2d");
    drawCreature(ctx, creature.traits, 110, 235, 2.05, creature.pose);
    model.spriteCache.set(cacheKey, canvas);
    return canvas;
  }

  function drawPosters() {
    document.querySelectorAll(".fps-warrant-canvas").forEach((canvas, index) => {
      const poster = model.state.wanted_posters[index];
      const ctx = canvas.getContext("2d");
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      const wash = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
      wash.addColorStop(0, "#d9c99a");
      wash.addColorStop(1, "#8f805c");
      ctx.fillStyle = wash;
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.fillStyle = "rgba(38,28,18,.14)";
      for (let y = 3; y < canvas.height; y += 7) ctx.fillRect(0, y, canvas.width, 1);
      drawCreature(ctx, poster.traits, canvas.width / 2, canvas.height - 5, 0.78, "alert");
    });
  }

  function drawWorld() {
    const canvas = document.querySelector(".fps-world");
    if (!canvas || !model.state || !model.pose) return;
    const ctx = canvas.getContext("2d", {alpha: false});
    const width = canvas.width;
    const height = canvas.height;

    const sky = ctx.createLinearGradient(0, 0, 0, height / 2);
    sky.addColorStop(0, "#071a24");
    sky.addColorStop(1, "#183844");
    ctx.fillStyle = sky;
    ctx.fillRect(0, 0, width, height / 2);
    const floor = ctx.createLinearGradient(0, height / 2, 0, height);
    floor.addColorStop(0, "#26322f");
    floor.addColorStop(1, "#070b0b");
    ctx.fillStyle = floor;
    ctx.fillRect(0, height / 2, width, height / 2);

    const depth = new Float32Array(width);
    for (let screenX = 0; screenX < width; screenX += 2) {
      const relative = (screenX / width - 0.5) * FOV;
      const rayAngle = normalizeAngle(model.pose.angle_mdeg + relative * 180 / Math.PI * 1000);
      const ray = castWall(model.pose.x, model.pose.y, rayAngle);
      const corrected = Math.max(0.001, ray.distance * Math.cos(relative));
      const wallHeight = Math.min(height * 1.8, height / corrected);
      const top = Math.round((height - wallHeight) / 2);
      const hash = Math.abs(ray.mapX * 17 + ray.mapY * 31) % 4;
      const light = Math.max(0.28, Math.min(1, 1.7 / corrected));
      const base = ray.side ? [43, 108, 103] : [59, 137, 124];
      const grain = hash * 5;
      ctx.fillStyle = `rgb(${Math.round((base[0] + grain) * light)},${Math.round((base[1] + grain) * light)},${Math.round((base[2] + grain) * light)})`;
      ctx.fillRect(screenX, top, 2, wallHeight);
      if (hash === 0) {
        ctx.fillStyle = `rgba(255,220,115,${0.08 * light})`;
        ctx.fillRect(screenX, top, 1, wallHeight);
      }
      depth[screenX] = corrected;
      if (screenX + 1 < width) depth[screenX + 1] = corrected;
    }

    const visible = (model.state.creatures || [])
      .filter((creature) => model.alive.has(String(creature.id)))
      .map((creature) => {
        const dx = Number(creature.x) - model.pose.x;
        const dy = Number(creature.y) - model.pose.y;
        const distance = Math.hypot(dx, dy);
        const relative = signedAngle(Math.atan2(dy, dx) - angleRadians());
        return {creature, distance, relative};
      })
      .filter((item) => Math.abs(item.relative) < FOV * 0.64 && item.distance > 0.05)
      .sort((a, b) => b.distance - a.distance);

    visible.forEach((item) => {
      const corrected = item.distance * Math.cos(item.relative);
      const screenX = width / 2 + Math.tan(item.relative) / Math.tan(FOV / 2) * width / 2;
      const spriteHeight = Math.min(height * 1.45, height * 0.84 / Math.max(0.2, corrected));
      const spriteWidth = spriteHeight * 0.846;
      const left = Math.round(screenX - spriteWidth / 2);
      const top = Math.round(height / 2 - spriteHeight * 0.52);
      const sprite = creatureSprite(item.creature);
      const start = Math.max(0, left);
      const end = Math.min(width, Math.ceil(left + spriteWidth));
      for (let destinationX = start; destinationX < end; destinationX += 1) {
        if (corrected >= depth[destinationX] + 0.03) continue;
        const sourceX = Math.floor((destinationX - left) / spriteWidth * sprite.width);
        ctx.drawImage(sprite, sourceX, 0, 1, sprite.height, destinationX, top, 1.15, spriteHeight);
      }
    });

    ctx.strokeStyle = "rgba(255,235,151,.92)";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(width / 2 - 17, height / 2); ctx.lineTo(width / 2 - 5, height / 2);
    ctx.moveTo(width / 2 + 5, height / 2); ctx.lineTo(width / 2 + 17, height / 2);
    ctx.moveTo(width / 2, height / 2 - 17); ctx.lineTo(width / 2, height / 2 - 5);
    ctx.moveTo(width / 2, height / 2 + 5); ctx.lineTo(width / 2, height / 2 + 17);
    ctx.stroke();
    ctx.fillStyle = "rgba(255,235,151,.9)";
    ctx.fillRect(width / 2 - 1, height / 2 - 1, 3, 3);

    ctx.fillStyle = "rgba(3,10,12,.72)";
    ctx.beginPath();
    ctx.moveTo(width / 2 - 70, height); ctx.lineTo(width / 2 - 34, height - 74); ctx.lineTo(width / 2 + 34, height - 74); ctx.lineTo(width / 2 + 70, height); ctx.fill();
    ctx.fillStyle = "#b77d35";
    ctx.fillRect(width / 2 - 13, height - 79, 26, 31);
    ctx.fillStyle = "#f3c86c";
    ctx.fillRect(width / 2 - 6, height - 84, 12, 9);

    ctx.fillStyle = "rgba(255,255,255,.025)";
    for (let y = 0; y < height; y += 4) ctx.fillRect(0, y, width, 1);

    const feedback = document.querySelector(".fps-hit-feedback");
    if (feedback && model.feedbackUntil < performance.now()) feedback.classList.remove("is-visible");
    model.frame = requestAnimationFrame(drawWorld);
  }

  function installControls() {
    model.keyHandler = (event) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const code = event.code;
      if (["KeyW", "KeyA", "KeyS", "KeyD", "ArrowLeft", "ArrowRight", "Space"].includes(code)) event.preventDefault();
      if (code === "KeyW") move(1, 0);
      else if (code === "KeyS") move(-1, 0);
      else if (code === "KeyA") move(0, -1);
      else if (code === "KeyD") move(0, 1);
      else if (code === "ArrowLeft") turn(-15000);
      else if (code === "ArrowRight") turn(15000);
      else if (code === "Space" && !event.repeat) fire();
    };
    window.addEventListener("keydown", model.keyHandler);

    const canvas = document.querySelector(".fps-world");
    if (!canvas) return;
    canvas.addEventListener("pointerdown", (event) => {
      if (model.terminal || model.submitting) return;
      canvas.setPointerCapture(event.pointerId);
      model.drag = {pointerId: event.pointerId, lastX: event.clientX, distance: 0};
      model.suppressClick = false;
    });
    canvas.addEventListener("pointermove", (event) => {
      if (!model.drag || model.drag.pointerId !== event.pointerId) return;
      const deltaX = event.clientX - model.drag.lastX;
      model.drag.lastX = event.clientX;
      model.drag.distance += Math.abs(deltaX);
      const quantized = Math.max(-36000, Math.min(36000, Math.round(deltaX * 400 / 250) * 250));
      if (quantized) turn(quantized);
    });
    canvas.addEventListener("pointerup", (event) => {
      if (!model.drag || model.drag.pointerId !== event.pointerId) return;
      model.suppressClick = model.drag.distance > 4;
      model.drag = null;
      try { canvas.releasePointerCapture(event.pointerId); } catch (_error) { /* already released */ }
      if (model.suppressClick) window.setTimeout(() => { model.suppressClick = false; }, 80);
    });
    canvas.addEventListener("click", () => {
      if (!model.suppressClick) fire();
    });
    document.querySelector(".fps-reset")?.addEventListener("click", resetLocal);
    document.querySelector(".fps-reissue")?.addEventListener("click", reissue);
  }

  async function render(state, helpers) {
    cleanup();
    document.body.dataset.mechanic = "tiny-fps-customs";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model.state = state;
    model.helpers = helpers;
    model.pose = {
      x: Number(state.initial_pose.x),
      y: Number(state.initial_pose.y),
      angle_mdeg: normalizeAngle(Number(state.initial_pose.angle_mdeg)),
    };
    model.alive = new Set((state.creatures || []).map((creature) => String(creature.id)));
    model.ammo = Number(state.ammo || 0);
    model.actions = [];
    model.hitLedger = [];
    model.eliminatedIds = [];
    model.counts = {moves: 0, turns: 0, shots: 0, collisions: 0, resets: 0};
    model.startedAt = performance.now();
    model.submitting = false;
    model.terminal = false;
    model.drag = null;
    model.feedbackUntil = 0;
    model.spriteCache = new Map();

    helpers.app.innerHTML = `
      <section class="tiny-fps-customs" data-challenge-id="${clean(state.challenge_id)}">
        <header class="fps-masthead">
          <div class="fps-seal"><i>03</i><span>INTERZONE<br>CUSTOMS</span></div>
          <div class="fps-title"><span>LIVE BORDER EXAM / BALLISTIC IDENTITY CHECK</span><h1>${clean(state.prompt)}</h1></div>
          <div class="fps-clearance"><span>MANIFEST</span><b>${clean(String(state.challenge_id).slice(0, 7).toUpperCase())}</b><i>RESTRICTED</i></div>
        </header>
        <main class="fps-workbench">
          <aside class="fps-dossier">
            <header><span>ACTIVE WARRANTS</span><b>VISUAL ID ONLY</b></header>
            <p>Match horns, eyes, chest mark and stripe. Colour alone is not identity.</p>
            <div class="fps-warrant-stack">
              ${(state.wanted_posters || []).map((poster, index) => `
                <article class="fps-warrant">
                  <canvas class="fps-warrant-canvas" width="176" height="118" aria-label="wanted creature portrait ${index + 1}"></canvas>
                  <div><strong>${clean(poster.warrant)}</strong><span>${clean(poster.traits.palette_name)} / ${clean(poster.traits.horn)}</span></div>
                </article>`).join("")}
            </div>
            <footer>PROTECTED LOOK-ALIKES<br><b>ONE TRAIT MAY DIFFER</b></footer>
          </aside>
          <section class="fps-viewport-column">
            <div class="fps-viewport-frame">
              <div class="fps-viewport-label"><span>BODYCAM 7 / MAZE CUSTOMS</span><i>LIVE</i></div>
              <canvas class="fps-world" width="${VIEW_WIDTH}" height="${VIEW_HEIGHT}" tabindex="0" aria-label="first person customs maze"></canvas>
              <div class="fps-hit-feedback" data-kind="idle"></div>
              <div class="fps-corner corner-a"></div><div class="fps-corner corner-b"></div><div class="fps-corner corner-c"></div><div class="fps-corner corner-d"></div>
            </div>
            <div class="fps-controls"><b>W/S</b> MOVE <b>A/D</b> STRAFE <b>←/→</b> TURN <b>DRAG</b> LOOK <b>CLICK / SPACE</b> FIRE</div>
          </section>
          <aside class="fps-ledger">
            <header><span>SHIFT LEDGER</span><i>ARMED</i></header>
            <section><label>WARRANTS CLEARED</label><strong class="fps-warrant-count">0 / 3</strong></section>
            <section><label>CARTRIDGES</label><div class="fps-ammo-pips"></div></section>
            <section class="fps-bearing"><label>BEARING / SECTOR</label><div><strong class="fps-compass-bearing">E</strong><span class="fps-sector">01.01</span></div></section>
            <div class="fps-doctrine"><b>RULE 01</b><p>The center reticle owns the nearest unobstructed contact.</p><b>RULE 02</b><p>A protected hit revokes this dossier immediately.</p></div>
            <button type="button" class="fps-reset">RESET SHIFT</button>
            <button type="button" class="fps-reissue">REISSUE DOSSIER</button>
          </aside>
        </main>
        <footer class="fps-footer"><div class="readout" data-status="idle">CROSS THE MAZE · VERIFY BEFORE FIRING</div><span>NO OMNISCIENT MAP / BALLISTICS RECORDED</span></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    drawPosters();
    updateHud();
    installControls();
    helpers.installCheatPanel();
    helpers.setReadout("CROSS THE MAZE · VERIFY BEFORE FIRING", "idle");
    model.frame = requestAnimationFrame(drawWorld);
    document.querySelector(".fps-world")?.focus({preventScroll: true});
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.tiny_fps_customs = {rootSelector: ".tiny-fps-customs", render};
})();
