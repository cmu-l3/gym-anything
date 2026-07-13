(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
  }

  function round2(value) {
    return Math.round(Number(value) * 100) / 100;
  }

  function clonePoint(point) {
    return {x: round2(point.x), y: round2(point.y)};
  }

  function eventTime() {
    return Math.round(performance.now() - model.startedAt);
  }

  function pushEvent(event) {
    const item = {seq: model.events.length + 1, t_ms: eventTime(), ...event};
    model.events.push(item);
    return item;
  }

  function deriveContract(challengeId, objects) {
    const forgeIndex = Number.parseInt(challengeId.slice(0, 2), 16) % objects.length;
    const lawIndex = Number.parseInt(challengeId.slice(2, 4), 16) % 3;
    const parameterByte = Number.parseInt(challengeId.slice(4, 6), 16);
    if (lawIndex === 0) {
      const sign = parameterByte % 2 ? -1 : 1;
      return {objectId: objects[forgeIndex].id, law: "wrong_pivot", parameter: sign * (0.38 + (parameterByte % 11) / 100)};
    }
    if (lawIndex === 1) {
      const scale = parameterByte % 2 ? 0.54 + (parameterByte % 8) / 100 : 1.38 + (parameterByte % 8) / 100;
      return {objectId: objects[forgeIndex].id, law: "wrong_scale", parameter: round2(scale)};
    }
    return {objectId: objects[forgeIndex].id, law: "lagged", parameter: round2(0.24 + (parameterByte % 9) / 100)};
  }

  function effectiveLamp(raw, initial, contract) {
    const dx = raw.x - initial.x;
    const dy = raw.y - initial.y;
    if (contract.law === "wrong_pivot") {
      const cosine = Math.cos(contract.parameter);
      const sine = Math.sin(contract.parameter);
      return {x: initial.x + dx * cosine - dy * sine, y: initial.y + dx * sine + dy * cosine};
    }
    return {x: initial.x + dx * contract.parameter, y: initial.y + dy * contract.parameter};
  }

  function shadowPolygon(object, lamp, areaRadius = model.areaRadius) {
    const dx = Number(object.x) - lamp.x;
    const dy = Number(object.y) - lamp.y;
    const distance = Math.max(62, Math.hypot(dx, dy));
    const ux = dx / distance;
    const uy = dy / distance;
    const px = -uy;
    const py = ux;
    const radius = Number(object.radius);
    const height = Number(object.height);
    const length = clamp(height * 250 / distance, 48, 158);
    const nearWidth = radius * (0.88 + areaRadius / Math.max(distance, 1) * 0.42);
    const farWidth = nearWidth * (1 + height / distance * 0.82) + areaRadius * 0.10;
    const nearX = Number(object.x) + ux * radius * 0.28;
    const nearY = Number(object.y) + uy * radius * 0.28;
    const farX = Number(object.x) + ux * (radius * 0.55 + length);
    const farY = Number(object.y) + uy * (radius * 0.55 + length);
    return [
      {x: nearX - px * nearWidth, y: nearY - py * nearWidth},
      {x: nearX + px * nearWidth, y: nearY + py * nearWidth},
      {x: farX + px * farWidth, y: farY + py * farWidth},
      {x: farX - px * farWidth, y: farY - py * farWidth},
    ];
  }

  function polygonsAt(lamp = model.lamp, areaRadius = model.areaRadius) {
    const forgedLamp = effectiveLamp(lamp, model.initialLamp, model.contract);
    return model.state.objects.map((object) => ({
      objectId: object.id,
      object,
      polygon: shadowPolygon(object, object.id === model.contract.objectId ? forgedLamp : lamp, areaRadius),
    }));
  }

  function pointInside(point, polygon) {
    let inside = false;
    let previous = polygon.length - 1;
    polygon.forEach((current, index) => {
      const before = polygon[previous];
      if ((current.y > point.y) !== (before.y > point.y) && point.x < (before.x - current.x) * (point.y - current.y) / ((before.y - current.y) || 1e-9) + current.x) inside = !inside;
      previous = index;
    });
    return inside;
  }

  function raycastShadow(point) {
    const polygons = polygonsAt();
    for (let index = polygons.length - 1; index >= 0; index -= 1) {
      if (pointInside(point, polygons[index].polygon)) return polygons[index].objectId;
    }
    return null;
  }

  function centroid(polygon) {
    return {
      x: polygon.reduce((sum, point) => sum + point.x, 0) / polygon.length,
      y: polygon.reduce((sum, point) => sum + point.y, 0) / polygon.length,
    };
  }

  function polygonArea(polygon) {
    let total = 0;
    polygon.forEach((point, index) => {
      const next = polygon[(index + 1) % polygon.length];
      total += point.x * next.y - next.x * point.y;
    });
    return Math.abs(total / 2);
  }

  function zoneAt(point) {
    return model.state.probe_zones.find((zone) => Math.hypot(point.x - Number(zone.x), point.y - Number(zone.y)) <= Number(zone.radius)) || null;
  }

  function responseSample() {
    return polygonsAt().map((entry) => ({
      object_id: entry.objectId,
      centroid: clonePoint(centroid(entry.polygon)),
      area: round2(polygonArea(entry.polygon)),
    }));
  }

  function tracePath(context, polygon) {
    context.beginPath();
    context.moveTo(polygon[0].x, polygon[0].y);
    polygon.slice(1).forEach((point) => context.lineTo(point.x, point.y));
    context.closePath();
  }

  function drawFloor(context, width, height) {
    context.fillStyle = "#d8d1c1";
    context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(65, 59, 48, .11)";
    context.lineWidth = 1;
    for (let x = 0; x <= width; x += 30) {
      context.beginPath(); context.moveTo(x, 0); context.lineTo(x, height); context.stroke();
    }
    for (let y = 0; y <= height; y += 30) {
      context.beginPath(); context.moveTo(0, y); context.lineTo(width, y); context.stroke();
    }
    context.strokeStyle = "rgba(164, 48, 33, .12)";
    context.setLineDash([7, 8]);
    context.beginPath(); context.moveTo(width / 2, 0); context.lineTo(width / 2, height); context.stroke();
    context.beginPath(); context.moveTo(0, height / 2); context.lineTo(width, height / 2); context.stroke();
    context.setLineDash([]);
  }

  function drawZones(context) {
    model.state.probe_zones.forEach((zone, index) => {
      const visited = model.visited.includes(zone.id);
      context.save();
      context.translate(Number(zone.x), Number(zone.y));
      context.beginPath();
      context.arc(0, 0, Number(zone.radius), 0, Math.PI * 2);
      context.fillStyle = visited ? "rgba(46, 138, 125, .16)" : "rgba(83, 72, 55, .045)";
      context.fill();
      context.strokeStyle = visited ? "#268a7b" : "rgba(68, 62, 51, .38)";
      context.lineWidth = visited ? 3 : 1.5;
      context.setLineDash(visited ? [] : [6, 6]);
      context.stroke();
      context.setLineDash([]);
      context.fillStyle = visited ? "#1d7165" : "#716755";
      context.font = "800 12px Courier New";
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillText(String.fromCharCode(65 + index), 0, 0);
      context.restore();
    });
  }

  function drawHistory(context) {
    model.snapshots.forEach((snapshot, snapshotIndex) => {
      context.save();
      context.globalAlpha = 0.08 + snapshotIndex * 0.025;
      context.fillStyle = ["#b94833", "#318a80", "#9b7735", "#554a75"][snapshotIndex % 4];
      snapshot.polygons.forEach((entry) => {
        tracePath(context, entry.polygon);
        context.fill();
      });
      context.restore();
    });
  }

  function drawShadows(context) {
    const soft = polygonsAt(model.lamp, model.areaRadius + 18);
    context.save();
    context.fillStyle = "rgba(27, 30, 28, .095)";
    soft.forEach((entry) => { tracePath(context, entry.polygon); context.fill(); });
    context.restore();
    polygonsAt().forEach((entry) => {
      tracePath(context, entry.polygon);
      context.fillStyle = entry.objectId === model.taggedId ? "rgba(117, 29, 23, .72)" : "rgba(22, 25, 23, .58)";
      context.fill();
      context.strokeStyle = entry.objectId === model.taggedId ? "#ff5c45" : "rgba(10, 12, 11, .48)";
      context.lineWidth = entry.objectId === model.taggedId ? 4 : 1.5;
      context.stroke();
    });
  }

  function objectColor(tone) {
    return {oxide: "#a64d38", slate: "#59676a", bone: "#b9ae94", brass: "#ad813b", umber: "#705744"}[tone] || "#6d6960";
  }

  function drawObject(context, object) {
    const x = Number(object.x);
    const y = Number(object.y);
    const radius = Number(object.radius);
    context.save();
    context.translate(x, y);
    context.fillStyle = objectColor(object.tone);
    context.strokeStyle = "#292b27";
    context.lineWidth = 2;
    if (object.shape === "cylinder") {
      context.fillRect(-radius, -radius * .55, radius * 2, radius * 1.15);
      context.beginPath(); context.ellipse(0, -radius * .55, radius, radius * .38, 0, 0, Math.PI * 2); context.fill(); context.stroke();
      context.beginPath(); context.ellipse(0, radius * .6, radius, radius * .38, 0, 0, Math.PI); context.stroke();
    } else if (object.shape === "crate") {
      context.fillRect(-radius, -radius, radius * 2, radius * 2); context.strokeRect(-radius, -radius, radius * 2, radius * 2);
      context.beginPath(); context.moveTo(-radius, -radius); context.lineTo(radius, radius); context.moveTo(radius, -radius); context.lineTo(-radius, radius); context.stroke();
    } else if (object.shape === "prism") {
      context.beginPath(); context.moveTo(0, -radius * 1.2); context.lineTo(radius * 1.1, radius); context.lineTo(-radius * 1.1, radius); context.closePath(); context.fill(); context.stroke();
      context.beginPath(); context.moveTo(0, -radius * 1.2); context.lineTo(0, radius); context.stroke();
    } else if (object.shape === "bust") {
      context.beginPath(); context.arc(0, -radius * .55, radius * .58, 0, Math.PI * 2); context.fill(); context.stroke();
      context.beginPath(); context.ellipse(0, radius * .45, radius, radius * .68, 0, 0, Math.PI * 2); context.fill(); context.stroke();
    } else {
      context.beginPath(); context.moveTo(0, -radius * 1.35); context.lineTo(radius * .62, radius); context.lineTo(-radius * .62, radius); context.closePath(); context.fill(); context.stroke();
      context.fillStyle = "rgba(255,255,255,.18)"; context.fillRect(-2, -radius, 4, radius * 1.5);
    }
    context.fillStyle = "#efe5ce";
    context.fillRect(-17, radius + 6, 34, 14);
    context.strokeStyle = "#4a4337";
    context.strokeRect(-17, radius + 6, 34, 14);
    context.fillStyle = "#463e32";
    context.font = "800 8px Courier New";
    context.textAlign = "center";
    context.textBaseline = "middle";
    context.fillText(object.case_label, 0, radius + 13);
    context.restore();
  }

  function drawLamp(context) {
    const radius = Number(model.state.lamp.drag_radius);
    const glow = context.createRadialGradient(model.lamp.x, model.lamp.y, 2, model.lamp.x, model.lamp.y, radius * 2.4);
    glow.addColorStop(0, "rgba(255, 232, 151, .85)");
    glow.addColorStop(.25, "rgba(255, 195, 68, .28)");
    glow.addColorStop(1, "rgba(255, 180, 30, 0)");
    context.fillStyle = glow;
    context.beginPath(); context.arc(model.lamp.x, model.lamp.y, radius * 2.4, 0, Math.PI * 2); context.fill();
    context.beginPath(); context.arc(model.lamp.x, model.lamp.y, radius, 0, Math.PI * 2);
    context.fillStyle = model.dragging ? "#fff3b8" : "#f3bd45";
    context.fill();
    context.strokeStyle = "#3c3424"; context.lineWidth = 3; context.stroke();
    if (model.areaRadius > 0) {
      context.beginPath(); context.arc(model.lamp.x, model.lamp.y, model.areaRadius, 0, Math.PI * 2);
      context.strokeStyle = "rgba(105, 69, 17, .7)"; context.lineWidth = 2; context.stroke();
    } else {
      context.fillStyle = "#5f451d"; context.beginPath(); context.arc(model.lamp.x, model.lamp.y, 4, 0, Math.PI * 2); context.fill();
    }
    context.fillStyle = "#483a22"; context.font = "900 7px Courier New"; context.textAlign = "center"; context.fillText("LAMP", model.lamp.x, model.lamp.y + radius + 13);
  }

  function drawScene() {
    if (!model) return;
    const canvas = document.getElementById("shadow-canvas");
    const context = canvas?.getContext("2d");
    if (!canvas || !context) return;
    drawFloor(context, canvas.width, canvas.height);
    drawZones(context);
    if (model.path.length > 1) {
      context.beginPath(); context.moveTo(model.path[0].x, model.path[0].y); model.path.slice(1).forEach((point) => context.lineTo(point.x, point.y));
      context.strokeStyle = "rgba(169, 61, 40, .34)"; context.lineWidth = 2; context.setLineDash([4, 5]); context.stroke(); context.setLineDash([]);
    }
    drawHistory(context);
    drawShadows(context);
    model.state.objects.forEach((object) => drawObject(context, object));
    drawLamp(context);
  }

  function updateInterface() {
    if (!model) return;
    const root = document.querySelector(".shadow-crime-lab");
    if (!root) return;
    root.dataset.probeCount = String(model.sampled.size);
    root.dataset.taggedObject = model.taggedId || "";
    root.dataset.dragging = String(model.dragging);
    document.querySelectorAll("[data-probe-id]").forEach((slot) => {
      slot.dataset.visited = String(model.visited.includes(slot.dataset.probeId));
      slot.dataset.sampled = String(model.sampled.has(slot.dataset.probeId));
    });
    document.querySelectorAll("[data-evidence-id]").forEach((row) => row.dataset.tagged = String(row.dataset.evidenceId === model.taggedId));
    const tag = document.getElementById("shadow-tag-readout");
    if (tag) tag.textContent = model.taggedId ? "SHADOW TAGGED" : "NO SHADOW TAG";
    const submit = document.getElementById("shadow-submit");
    if (submit) submit.disabled = model.submitting || model.completed;
    drawScene();
  }

  function canvasPoint(event) {
    const canvas = document.getElementById("shadow-canvas");
    const rect = canvas.getBoundingClientRect();
    return {
      x: round2((event.clientX - rect.left) / rect.width * canvas.width),
      y: round2((event.clientY - rect.top) / rect.height * canvas.height),
    };
  }

  function recordZone(zone) {
    if (!zone || model.sampled.has(zone.id)) return;
    model.visited.push(zone.id);
    model.sampled.add(zone.id);
    const responses = responseSample();
    pushEvent({type: "probe_sample", zone_id: zone.id, lamp: clonePoint(model.lamp), responses});
    model.snapshots.push({zoneId: zone.id, polygons: polygonsAt().map((entry) => ({objectId: entry.objectId, polygon: entry.polygon.map(clonePoint)}))});
    model.helpers.setReadout("PROBE RESPONSE RECORDED", "idle");
  }

  function pointerDown(event) {
    if (!model || model.submitting || model.completed) return;
    const point = canvasPoint(event);
    if (Math.hypot(point.x - model.lamp.x, point.y - model.lamp.y) <= Number(model.state.lamp.drag_radius)) {
      model.dragging = true;
      model.dragOffset = {x: round2(point.x - model.lamp.x), y: round2(point.y - model.lamp.y)};
      pushEvent({type: "lamp_start", pointer: point, lamp: clonePoint(model.lamp), drag_offset: clonePoint(model.dragOffset)});
      event.currentTarget.setPointerCapture?.(event.pointerId);
      model.helpers.setReadout("LIGHT PROBE ACTIVE", "idle");
      updateInterface();
      return;
    }
    if (model.sampled.size < Number(model.state.minimum_probe_zones || 4)) {
      model.helpers.setReadout("PROBE SEQUENCE INCOMPLETE", "error");
      return;
    }
    const objectId = raycastShadow(point);
    if (!objectId) {
      model.helpers.setReadout("TAG MISSED SHADOW", "error");
      return;
    }
    model.taggedId = objectId;
    pushEvent({type: "tag", point, object_id: objectId});
    model.helpers.setReadout("SHADOW TAGGED", "idle");
    updateInterface();
  }

  function pointerMove(event) {
    if (!model?.dragging || model.submitting || model.completed) return;
    const pointer = canvasPoint(event);
    const before = clonePoint(model.lamp);
    model.lamp = {
      x: round2(clamp(pointer.x - model.dragOffset.x, 20, Number(model.state.canvas.width) - 20)),
      y: round2(clamp(pointer.y - model.dragOffset.y, 20, Number(model.state.canvas.height) - 20)),
    };
    const zone = zoneAt(model.lamp);
    pushEvent({type: "lamp_move", pointer, from: before, to: clonePoint(model.lamp), zone_id: zone ? zone.id : null});
    model.path.push(clonePoint(model.lamp));
    if (zone && !model.visited.includes(zone.id)) recordZone(zone);
    updateInterface();
  }

  function pointerUp(event) {
    if (!model?.dragging) return;
    const point = canvasPoint(event);
    pushEvent({type: "lamp_end", pointer: point, lamp: clonePoint(model.lamp)});
    model.dragging = false;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    model.helpers.setReadout("LIGHT PROBE PARKED", "idle");
    updateInterface();
  }

  function resetScene() {
    if (!model || model.dragging || model.submitting || model.completed) return;
    model.lamp = clonePoint(model.initialLamp);
    model.dragOffset = {x: 0, y: 0};
    model.visited = [];
    model.sampled = new Set();
    model.snapshots = [];
    model.path = [clonePoint(model.lamp)];
    model.taggedId = null;
    model.resetCount += 1;
    pushEvent({type: "reset", lamp_after: clonePoint(model.lamp)});
    model.helpers.setReadout("SCENE RESET", "idle");
    updateInterface();
  }

  function finalState() {
    return {
      lamp_position: clonePoint(model.lamp),
      visited_zone_ids: [...model.visited],
      sample_count: model.sampled.size,
      tagged_object_id: model.taggedId,
      reset_count: model.resetCount,
    };
  }

  function showVerdict(kind) {
    const root = document.querySelector(".shadow-crime-lab");
    const verdict = root?.querySelector(".shadow-verdict");
    if (!root || !verdict) return;
    root.classList.toggle("is-passed", kind === "pass");
    root.classList.toggle("is-failed", kind === "fail");
    verdict.innerHTML = `<b>${kind === "pass" ? "PASS" : "FAIL"}</b><span>${kind === "pass" ? "CAUSAL FORGERY CONFIRMED" : "CASE REISSUED"}</span>`;
    if (kind === "fail") {
      const timer = window.setTimeout(() => root.classList.remove("is-failed"), 1500);
      model.timers.add(timer);
    }
  }

  async function submitFinding() {
    if (!model || model.submitting || model.completed) return;
    const current = model;
    current.submitting = true;
    updateInterface();
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({mechanic_id: current.state.mechanic_id, challenge_id: current.state.challenge_id, completed: true, events: current.events, final_state: finalState()}),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        current.completed = true;
        current.helpers.setReadout("PASS", "passed");
        showVerdict("pass");
        updateInterface();
      } else if (outcome.passed === false) {
        const helpers = current.helpers;
        if (outcome.state) await render(outcome.state, helpers, {freshFailure: true});
        model.helpers.setReadout("FAIL", "error");
        showVerdict("fail");
      }
    } catch (_error) {
      if (model === current) {
        current.submitting = false;
        current.helpers.setReadout("EVIDENCE LINK LOST", "error");
        updateInterface();
      }
    }
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
        const response = await fetch("/cheat", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify({password: input.value})});
        if (!response.ok) {
          output.textContent = response.status === 404 ? "Disabled." : "Denied.";
          return;
        }
        const data = await response.json();
        output.textContent = `Forged: ${data.forged_object_id} · ${data.forged_law} ${data.forged_parameter}`;
      } catch (_error) {
        output.textContent = "Unavailable.";
      }
    });
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "shadow-crime-lab";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const initialLamp = {x: Number(state.lamp.x), y: Number(state.lamp.y)};
    model = {
      state,
      helpers,
      contract: deriveContract(state.challenge_id, state.objects),
      areaRadius: Number(state.lamp.area_radius || 0),
      initialLamp,
      lamp: clonePoint(initialLamp),
      dragOffset: {x: 0, y: 0},
      dragging: false,
      events: [],
      visited: [],
      sampled: new Set(),
      snapshots: [],
      path: [clonePoint(initialLamp)],
      taggedId: null,
      resetCount: 0,
      submitting: false,
      completed: false,
      startedAt: performance.now(),
      timers: new Set(),
    };
    helpers.app.innerHTML = `
      <section class="shadow-crime-lab palette-${helpers.text(state.palette)}" data-fresh-failure="${options.freshFailure ? "true" : "false"}" data-probe-count="0" tabindex="0">
        <div class="shadow-verdict" aria-live="assertive"></div>
        <header class="shadow-head">
          <div><span>PHOTOMETRIC EVIDENCE UNIT / ${helpers.text(state.case_number)}</span><h1>${helpers.text(state.prompt)}</h1></div>
          <div class="shadow-case-mark"><i>◒</i><span>CASE<br><b>SHADOW</b></span></div>
        </header>
        <main class="shadow-workbench">
          <section class="shadow-stage">
            <canvas id="shadow-canvas" width="${Number(state.canvas.width)}" height="${Number(state.canvas.height)}" aria-label="analytic shadow crime scene"></canvas>
            <div class="stage-caption"><span>DRAG LIGHT / CLICK SHADOW TO TAG</span><b>ANALYTIC PROJECTION TABLE</b></div>
          </section>
          <aside class="shadow-console">
            <div class="lamp-manifest"><span>LIGHT SOURCE</span><b>${helpers.text(String(state.lamp.type).toUpperCase())}</b><i>${Number(state.lamp.area_radius) > 0 ? `AREA Ø${Number(state.lamp.area_radius) * 2}` : "POINT EMITTER"}</i></div>
            <div class="probe-ledger"><span>PROBE LEDGER</span>${state.probe_zones.map((zone, index) => `<div data-probe-id="${helpers.text(zone.id)}" data-visited="false" data-sampled="false"><i>${String.fromCharCode(65 + index)}</i><b>ZONE ${index + 1}</b><em></em></div>`).join("")}</div>
            <div class="evidence-ledger"><span>SHADOW EVIDENCE</span>${state.objects.map((object) => `<div data-evidence-id="${helpers.text(object.id)}" data-tagged="false"><i>${helpers.text(object.case_label)}</i><b>${helpers.text(String(object.shape).toUpperCase())}</b><em>TAG</em></div>`).join("")}</div>
            <div class="shadow-tag-panel"><span id="shadow-tag-readout">NO SHADOW TAG</span><button type="button" id="shadow-reset">RESET SCENE</button></div>
          </aside>
        </main>
        <footer class="shadow-foot"><div class="readout" data-status="idle">LIGHT RESPONSE READY</div><button type="button" id="shadow-submit">${helpers.text(state.submit_label || "FILE FINDING")}</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    const canvas = document.getElementById("shadow-canvas");
    canvas.addEventListener("pointerdown", pointerDown);
    canvas.addEventListener("pointermove", pointerMove);
    canvas.addEventListener("pointerup", pointerUp);
    canvas.addEventListener("pointercancel", pointerUp);
    document.getElementById("shadow-reset")?.addEventListener("click", resetScene);
    document.getElementById("shadow-submit")?.addEventListener("click", submitFinding);
    installDeveloperReveal();
    activeCleanup = () => {
      canvas.removeEventListener("pointerdown", pointerDown);
      canvas.removeEventListener("pointermove", pointerMove);
      canvas.removeEventListener("pointerup", pointerUp);
      canvas.removeEventListener("pointercancel", pointerUp);
      model?.timers.forEach((timer) => window.clearTimeout(timer));
    };
    updateInterface();
    document.querySelector(".shadow-crime-lab")?.focus();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.shadow_crime_lab = {rootSelector: ".shadow-crime-lab", render};
})();
