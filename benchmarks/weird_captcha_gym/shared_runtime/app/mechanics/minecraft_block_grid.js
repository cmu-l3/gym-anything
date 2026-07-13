(() => {
  "use strict";

  const GRID = 5;
  const WIDTH = 900;
  const HEIGHT = 500;
  const TILE_W = 78;
  const TILE_H = 38;
  const CUBE_H = 38;
  let helpersCache = null;
  let model = null;

  function esc(value) {
    return String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  }

  function rotate(x, y, orientation) {
    const view = ((orientation % 4) + 4) % 4;
    if (view === 0) return [x, y];
    if (view === 1) return [GRID - 1 - y, x];
    if (view === 2) return [GRID - 1 - x, GRID - 1 - y];
    return [y, GRID - 1 - x];
  }

  function inverse(rx, ry, orientation) {
    const view = ((orientation % 4) + 4) % 4;
    if (view === 0) return [rx, ry];
    if (view === 1) return [ry, GRID - 1 - rx];
    if (view === 2) return [GRID - 1 - rx, GRID - 1 - ry];
    return [GRID - 1 - ry, rx];
  }

  function neighbor(x, y, orientation, axis) {
    const [rx0, ry0] = rotate(x, y, orientation);
    return inverse(rx0 + (axis === "x" ? 1 : 0), ry0 + (axis === "y" ? 1 : 0), orientation);
  }

  function project(x, y, z, orientation) {
    const [rx, ry] = rotate(x, y, orientation);
    return [WIDTH / 2 + (rx - ry) * TILE_W / 2, 55 + (rx + ry) * TILE_H / 2 + (2 - z) * CUBE_H];
  }

  function faces() {
    const voxels = [...model.voxels.values()];
    const occupied = new Set(voxels.map((voxel) => `${voxel.x},${voxel.y},${voxel.z}`));
    voxels.sort((first, second) => {
      const a = rotate(Number(first.x), Number(first.y), model.orientation);
      const b = rotate(Number(second.x), Number(second.y), model.orientation);
      return (a[0] + a[1]) - (b[0] + b[1]) || Number(first.z) - Number(second.z) || a[0] - b[0];
    });
    const result = [];
    voxels.forEach((voxel) => {
      const x = Number(voxel.x); const y = Number(voxel.y); const z = Number(voxel.z);
      const [sx, sy] = project(x, y, z, model.orientation);
      const nx = neighbor(x, y, model.orientation, "x");
      const ny = neighbor(x, y, model.orientation, "y");
      if (!occupied.has(`${nx[0]},${nx[1]},${z}`)) result.push({voxel, face: "right", points: [[sx, sy], [sx + TILE_W / 2, sy + TILE_H / 2], [sx + TILE_W / 2, sy + TILE_H / 2 + CUBE_H], [sx, sy + CUBE_H]]});
      if (!occupied.has(`${ny[0]},${ny[1]},${z}`)) result.push({voxel, face: "left", points: [[sx, sy], [sx - TILE_W / 2, sy + TILE_H / 2], [sx - TILE_W / 2, sy + TILE_H / 2 + CUBE_H], [sx, sy + CUBE_H]]});
      if (!occupied.has(`${x},${y},${z + 1}`)) result.push({voxel, face: "top", points: [[sx, sy], [sx + TILE_W / 2, sy + TILE_H / 2], [sx, sy + TILE_H], [sx - TILE_W / 2, sy + TILE_H / 2]]});
    });
    return result;
  }

  function inside(x, y, points) {
    let result = false;
    let previous = points.length - 1;
    points.forEach(([xi, yi], index) => {
      const [xj, yj] = points[previous];
      if ((yi > y) !== (yj > y) && x < (xj - xi) * (y - yi) / ((yj - yi) || 1e-9) + xi) result = !result;
      previous = index;
    });
    return result;
  }

  function raycast(x, y) {
    const drawn = faces();
    for (let index = drawn.length - 1; index >= 0; index -= 1) {
      if (inside(x, y, drawn[index].points)) return drawn[index];
    }
    return null;
  }

  function shade(material, face) {
    const palettes = {
      stone: {top: "#9b9d96", right: "#6f746e", left: "#7f837c"},
      diamond: {top: "#55f2db", right: "#159f9c", left: "#27c6b8"},
      lava: {top: "#ff6a25", right: "#a72e18", left: "#d4441c"},
      support: {top: "#f2c84d", right: "#9b7120", left: "#c7942d"},
    };
    return palettes[material]?.[face] || "#777";
  }

  function polygon(context, points) {
    context.beginPath();
    points.forEach(([x, y], index) => index ? context.lineTo(x, y) : context.moveTo(x, y));
    context.closePath();
  }

  function drawFace(context, item) {
    const material = String(item.voxel.material);
    polygon(context, item.points);
    context.fillStyle = shade(material, item.face);
    context.fill();
    context.strokeStyle = material === "diamond" ? "#c7fff4" : material === "lava" ? "#ffb04c" : "#454a46";
    context.lineWidth = material === "diamond" ? 2 : 1;
    context.stroke();
    const cx = item.points.reduce((sum, point) => sum + point[0], 0) / item.points.length;
    const cy = item.points.reduce((sum, point) => sum + point[1], 0) / item.points.length;
    if (material === "diamond") {
      context.fillStyle = "rgba(225,255,248,.9)";
      for (let index = 0; index < 3; index += 1) {
        context.beginPath();
        context.arc(cx + (index - 1) * 9, cy + (index % 2 ? 4 : -4), 3.2, 0, Math.PI * 2);
        context.fill();
      }
    } else if (material === "lava") {
      context.strokeStyle = "rgba(255,226,83,.8)";
      context.lineWidth = 2;
      context.beginPath(); context.moveTo(cx - 15, cy); context.lineTo(cx - 4, cy - 6); context.lineTo(cx + 7, cy + 4); context.lineTo(cx + 17, cy - 3); context.stroke();
    } else if (material === "support") {
      context.strokeStyle = "rgba(45,37,8,.7)";
      context.lineWidth = 3;
      context.beginPath(); context.moveTo(cx - 18, cy - 8); context.lineTo(cx + 18, cy + 8); context.moveTo(cx - 18, cy + 4); context.lineTo(cx + 8, cy + 15); context.stroke();
    } else {
      context.fillStyle = "rgba(45,51,47,.22)";
      context.fillRect(cx - 10, cy - 2, 6, 6);
      context.fillRect(cx + 5, cy - 10, 4, 4);
    }
  }

  function drawMine() {
    const canvas = document.getElementById("voxel-canvas");
    if (!canvas || !model) return;
    const context = canvas.getContext("2d");
    context.clearRect(0, 0, WIDTH, HEIGHT);
    const gradient = context.createLinearGradient(0, 0, 0, HEIGHT);
    gradient.addColorStop(0, "#17222a"); gradient.addColorStop(1, "#080d11");
    context.fillStyle = gradient; context.fillRect(0, 0, WIDTH, HEIGHT);
    context.strokeStyle = "rgba(113,162,170,.13)"; context.lineWidth = 1;
    for (let x = 0; x < WIDTH; x += 45) { context.beginPath(); context.moveTo(x, 0); context.lineTo(x, HEIGHT); context.stroke(); }
    for (let y = 0; y < HEIGHT; y += 45) { context.beginPath(); context.moveTo(0, y); context.lineTo(WIDTH, y); context.stroke(); }
    faces().forEach((item) => drawFace(context, item));
    if (model.lastClick) {
      context.strokeStyle = model.lastClick.outcome === "diamond_extracted" ? "#7dffe6" : "#ff6f4f";
      context.lineWidth = 2;
      context.beginPath(); context.arc(model.lastClick.x, model.lastClick.y, 16, 0, Math.PI * 2); context.stroke();
    }
    if (model.collapsed) {
      context.fillStyle = "rgba(47,8,4,.72)"; context.fillRect(0, 0, WIDTH, HEIGHT);
      context.fillStyle = "#ffd0c1"; context.font = "52px Georgia"; context.textAlign = "center"; context.fillText("SUPPORT COLLAPSE", WIDTH / 2, HEIGHT / 2);
      context.font = "16px Courier New"; context.fillText("REBUILD MINE TO CONTINUE", WIDTH / 2, HEIGHT / 2 + 38);
    }
  }

  function clearFreshFailure() {
    const root = document.querySelector(".voxel-mine");
    if (!root || root.dataset.freshFailure !== "true") return;
    root.dataset.freshFailure = "false";
    document.querySelector(".voxel-fail-stamp")?.remove();
    helpersCache.setReadout("MINE LIVE · ROTATE / RAYCAST / EXTRACT", "idle");
  }

  function renderHud() {
    const durability = document.getElementById("voxel-durability");
    if (durability) durability.innerHTML = Array.from({length: Number(model.state.starting_durability)}, (_, index) => `<i data-live="${index < model.durability}"></i>`).join("");
    const durabilityValue = document.getElementById("voxel-durability-value");
    if (durabilityValue) durabilityValue.textContent = `${model.durability} / ${model.state.starting_durability}`;
    const inventory = document.getElementById("voxel-inventory");
    if (inventory) inventory.innerHTML = Array.from({length: Number(model.state.target_count)}, (_, index) => `<li data-filled="${index < model.inventory.length}">${index < model.inventory.length ? "◆" : "◇"}<span>${index < model.inventory.length ? "EXTRACTED" : "EMPTY"}</span></li>`).join("");
    document.querySelectorAll("[data-view]").forEach((button) => button.dataset.active = Number(button.dataset.view) === model.orientation ? "true" : "false");
    const compass = document.getElementById("voxel-compass");
    if (compass) compass.style.transform = `rotate(${model.orientation * 90}deg)`;
    const eventCount = document.getElementById("voxel-event-count");
    if (eventCount) eventCount.textContent = String(model.events.length).padStart(2, "0");
    const exit = document.getElementById("voxel-exit");
    if (exit) exit.dataset.ready = model.inventory.length === Number(model.state.target_count) && !model.collapsed ? "true" : "false";
    renderTape();
  }

  function renderTape() {
    const tape = document.getElementById("voxel-tape");
    if (!tape) return;
    const events = model.events.slice(-8).reverse();
    tape.innerHTML = events.length ? events.map((item) => `<li data-action="${esc(item.action)}"><i>${String(item.sequence).padStart(2, "0")}</i><b>${esc(item.action.toUpperCase())}</b><span>${esc(item.outcome || (item.action === "rotate" ? `VIEW ${item.orientation_after}` : "MINE REBUILT"))}</span></li>`).join("") : '<li class="is-empty">NO TOOL EVENTS</li>';
  }

  function rotateView(delta) {
    if (!model || model.submitting || model.terminal) return;
    clearFreshFailure();
    const before = model.orientation;
    model.orientation = (model.orientation + delta + 4) % 4;
    model.events.push({sequence: model.events.length + 1, action: "rotate", delta, orientation_before: before, orientation_after: model.orientation});
    model.visited.add(model.orientation);
    helpersCache.setReadout(`CAMERA ROTATED · VIEW ${model.orientation + 1}/4`, "idle");
    renderHud(); drawMine();
  }

  function mineAt(x, y) {
    if (!model || model.submitting || model.terminal || model.collapsed) return;
    clearFreshFailure();
    const hit = raycast(x, y);
    let outcome = "miss";
    if (hit && model.durability <= 0) outcome = "tool_broken";
    else if (hit) {
      const voxel = hit.voxel;
      model.durability -= 1;
      if (voxel.material === "diamond") {
        model.inventory.push(voxel.id);
        model.voxels.delete(voxel.id);
        outcome = "diamond_extracted";
      } else if (voxel.material === "stone") {
        model.voxels.delete(voxel.id);
        outcome = "stone_removed";
      } else if (voxel.material === "lava") outcome = "lava_strike";
      else if (voxel.material === "support") { model.collapsed = true; outcome = "support_collapse"; }
    }
    const event = {
      sequence: model.events.length + 1,
      action: "mine",
      orientation: model.orientation,
      x: Number(x.toFixed(2)), y: Number(y.toFixed(2)),
      voxel_id: hit ? hit.voxel.id : null,
      face: hit ? hit.face : null,
      outcome,
      durability_after: model.durability,
      inventory_after: [...model.inventory].sort(),
    };
    model.events.push(event);
    model.lastClick = {x, y, outcome};
    const labels = {diamond_extracted: "DIAMOND EXTRACTED", stone_removed: "STONE REMOVED · VISIBILITY CHANGED", lava_strike: "LAVA STRIKE · DURABILITY LOST", support_collapse: "SUPPORT COLLAPSE · REBUILD REQUIRED", tool_broken: "PICK EXHAUSTED", miss: "RAY MISS"};
    helpersCache.setReadout(labels[outcome], outcome === "diamond_extracted" || outcome === "stone_removed" ? "idle" : "error");
    renderHud(); drawMine();
  }

  function resetMine() {
    if (!model || model.submitting || model.terminal) return;
    clearFreshFailure();
    model.events.push({sequence: model.events.length + 1, action: "reset"});
    model.voxels = new Map((model.state.voxels || []).map((voxel) => [String(voxel.id), {...voxel}]));
    model.orientation = Number(model.state.starting_orientation || 0);
    model.durability = Number(model.state.starting_durability || 0);
    model.inventory = [];
    model.collapsed = false;
    model.lastClick = null;
    model.visited = new Set([model.orientation]);
    helpersCache.setReadout("MINE REBUILT · TOOL RESTORED", "idle");
    renderHud(); drawMine();
  }

  function finalState() {
    return {orientation: model.orientation, durability: model.durability, inventory: [...model.inventory].sort(), collapsed: model.collapsed, remaining_voxel_ids: [...model.voxels.keys()].sort()};
  }

  async function exitMine() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    document.getElementById("voxel-exit")?.setAttribute("disabled", "disabled");
    helpersCache.setReadout("REPLAYING CAMERA / RAYS / SUPPORT GRAPH…", "pending");
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({mechanic_id: model.state.mechanic_id, challenge_id: model.state.challenge_id, events: model.events, final_state: finalState(), completed: true})});
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".voxel-mine")?.insertAdjacentHTML("beforeend", '<div class="voxel-pass-stamp"><span>ORE MANIFEST + SUPPORT VERIFIED</span><strong>PASS</strong><i>EXTRACTION SHAFT CLEARED</i></div>');
        helpersCache.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await helpersCache.render(outcome.state);
        const root = document.querySelector(".voxel-mine");
        if (root) root.dataset.freshFailure = "true";
        root?.insertAdjacentHTML("beforeend", '<div class="voxel-fail-stamp"><span>EXTRACTION MANIFEST REJECTED</span><strong>FAIL</strong><i>FRESH SHAFT ISSUED</i></div>');
        helpersCache.setReadout("FAIL · FRESH SHAFT ISSUED", "error");
      } else {
        model.submitting = false;
        helpersCache.setReadout("FAIL · MINE REPLAY UNAVAILABLE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      helpersCache.setReadout("FAIL · SHAFT LINK OFFLINE", "error");
    }
  }

  async function render(state, helpers) {
    helpersCache = helpers || helpersCache;
    if (!helpersCache) throw new Error("minecraft_block_grid requires runtime helpers");
    document.body.dataset.mechanic = "voxel-extraction-mine";
    document.body.dataset.minePalette = String(state.palette || "cavern");
    document.body.dataset.cheatMode = helpersCache.isCheatMode() ? "true" : "false";
    model = {state, voxels: new Map((state.voxels || []).map((voxel) => [String(voxel.id), {...voxel}])), orientation: Number(state.starting_orientation || 0), durability: Number(state.starting_durability || 0), inventory: [], collapsed: false, events: [], lastClick: null, visited: new Set([Number(state.starting_orientation || 0)]), submitting: false, terminal: false};
    helpersCache.app.innerHTML = `<section class="voxel-mine" data-challenge-id="${esc(state.challenge_id)}" data-fresh-failure="false"><header class="voxel-head"><div><span>ISOMETRIC VOXEL EXTRACTION MINE / SHAFT ${esc(state.challenge_id).toUpperCase()}</span><h1>${esc(state.prompt)}</h1></div><aside><span>PICK DURABILITY</span><div id="voxel-durability"></div><b id="voxel-durability-value"></b></aside></header><main class="voxel-main"><section class="voxel-view"><div class="voxel-canvas-shell"><canvas id="voxel-canvas" width="900" height="500"></canvas><div class="voxel-view-tag">CLICK RAY / FRONTMOST EXPOSED FACE</div></div><div class="voxel-camera"><button type="button" id="voxel-left">↶ ROTATE</button><div class="voxel-compass-shell"><i id="voxel-compass">▲</i><span>CAMERA</span></div><div class="voxel-view-pips">${[0,1,2,3].map((view) => `<i data-view="${view}">${view + 1}</i>`).join("")}</div><button type="button" id="voxel-right">ROTATE ↷</button></div></section><aside class="voxel-console"><div class="voxel-console-title"><span>EXTRACTION MANIFEST</span><i>${state.target_count} TARGETS</i></div><ol id="voxel-inventory"></ol><div class="voxel-legend"><span>MATERIAL HAZARDS</span><p><i class="is-stone"></i> STONE / COST 1</p><p><i class="is-diamond"></i> DIAMOND / EXTRACT</p><p><i class="is-lava"></i> LAVA / DAMAGES PICK</p><p><i class="is-support"></i> FRAGILE SUPPORT / COLLAPSE</p></div><div class="voxel-procedure"><span>FIELD PROCEDURE</span><ol><li>Rotate all four viewpoints.</li><li>Mine frontmost stone blockers.</li><li>Recheck the changed depth order.</li><li>Preserve yellow supports.</li></ol></div><button type="button" id="voxel-reset">↺ REBUILD MINE</button><div class="voxel-tape-title"><span>TOOL TAPE</span><b>EVENTS <i id="voxel-event-count">00</i></b></div><ol id="voxel-tape"></ol></aside></main><footer class="voxel-foot"><div class="readout" data-status="idle">MINE LIVE · ROTATE / RAYCAST / EXTRACT</div><span>5×5×3 / DEPTH-SORTED CLICK RAYS / LIMITED TOOL</span><button type="button" id="voxel-exit">${esc(state.submit_label || "EXIT MINE")} →</button></footer>${helpersCache.cheatPanelTemplate()}</section>`;
    document.getElementById("voxel-left")?.addEventListener("click", () => rotateView(-1));
    document.getElementById("voxel-right")?.addEventListener("click", () => rotateView(1));
    document.getElementById("voxel-reset")?.addEventListener("click", resetMine);
    document.getElementById("voxel-exit")?.addEventListener("click", exitMine);
    document.getElementById("voxel-canvas")?.addEventListener("click", (clickEvent) => {
      const rect = clickEvent.currentTarget.getBoundingClientRect();
      mineAt((clickEvent.clientX - rect.left) / rect.width * WIDTH, (clickEvent.clientY - rect.top) / rect.height * HEIGHT);
    });
    renderHud(); drawMine(); helpersCache.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.minecraft_block_grid = {rootSelector: ".voxel-mine", render};
})();
