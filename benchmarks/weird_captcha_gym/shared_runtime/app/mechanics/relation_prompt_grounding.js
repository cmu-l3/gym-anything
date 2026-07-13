(() => {
  "use strict";

  let model = null;

  function clean(value) {
    return String(value == null ? "" : value).replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  }

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function stagePoint(event) {
    const rect = document.querySelector(".rel-stage").getBoundingClientRect();
    return [
      Math.max(0, Math.min(model.state.stage.width, Math.round((event.clientX - rect.left) / rect.width * model.state.stage.width))),
      Math.max(0, Math.min(model.state.stage.height, Math.round((event.clientY - rect.top) / rect.height * model.state.stage.height))),
    ];
  }

  function inside(point, rect) {
    return point[0] >= rect.x && point[0] <= rect.x + rect.width && point[1] >= rect.y && point[1] <= rect.y + rect.height;
  }

  function carouselPoint(item) {
    const carousel = model.state.carousel;
    const angle = Math.PI * 2 * ((item.carousel_phase + model.carouselTick) % carousel.ticks) / carousel.ticks;
    return [
      Math.round(carousel.center[0] + carousel.radius_x * Math.cos(angle)),
      Math.round(carousel.center[1] + carousel.radius_y * Math.sin(angle)),
    ];
  }

  function stateSnapshot() {
    return Object.keys(model.objects).sort().map((id) => {
      const item = model.objects[id];
      return {id, x: item.x, y: item.y, depth: item.depth, placed: item.placed};
    });
  }

  function objectPosition(item) {
    return item.placed ? [item.x, item.y] : carouselPoint(item);
  }

  function applyObjectStyles() {
    for (const item of Object.values(model.objects)) {
      const node = document.querySelector(`.rel-object[data-object-id="${CSS.escape(item.id)}"]`);
      if (!node) continue;
      const point = objectPosition(item);
      node.style.left = `${point[0] / model.state.stage.width * 100}%`;
      node.style.top = `${point[1] / model.state.stage.height * 100}%`;
      node.style.setProperty("--rel-size", `${item.radius * 2 / model.state.stage.width * 100}%`);
      node.style.setProperty("--rel-depth-scale", String(.78 + item.depth * .0045));
      node.style.zIndex = String(10 + item.depth);
      node.dataset.placed = item.placed ? "true" : "false";
      node.classList.toggle("is-selected", model.selectedId === item.id);
    }
    const placed = Object.values(model.objects).filter((item) => item.placed).length;
    const placedNode = document.querySelector(".rel-placed-count");
    if (placedNode) placedNode.textContent = `${placed}/5 ON TABLE`;
  }

  function updateDepthConsole() {
    const selected = model.objects[model.selectedId];
    const label = document.querySelector(".rel-depth-selection b");
    const value = document.querySelector(".rel-depth-value");
    const knob = document.querySelector(".rel-depth-knob");
    if (label) label.textContent = selected ? selected.label : "NO OBJECT";
    if (value) value.textContent = selected ? String(selected.depth).padStart(3, "0") : "---";
    if (knob) knob.style.top = `${selected ? 100 - selected.depth : 50}%`;
    document.querySelectorAll(".rel-select").forEach((button) => button.classList.toggle("is-selected", button.dataset.objectId === model.selectedId));
  }

  function selectObject(objectId) {
    if (!model.objects[objectId]?.placed || model.settling || model.settled) return;
    model.selectedId = objectId;
    applyObjectStyles();
    updateDepthConsole();
    model.helpers.setReadout(`${model.objects[objectId].label} SELECTED · ADJUST DEPTH OR POSITION`, "idle");
  }

  function dragStart(event) {
    const node = event.target.closest(".rel-object");
    if (!node || model.settling || model.settled || model.submitting || model.terminal) return;
    event.preventDefault();
    document.querySelector(".rel-failure-stamp")?.remove();
    const objectId = node.dataset.objectId;
    const item = model.objects[objectId];
    const point = stagePoint(event);
    record("drag_start", {object_id: objectId, source: item.placed ? "table" : "carousel", carousel_tick: model.carouselTick, point});
    model.drag = {objectId, original: {...item}, start: point, moves: 0};
    model.selectedId = objectId;
    document.querySelector(".rel-stage").setPointerCapture(event.pointerId);
    node.classList.add("is-dragging");
    applyObjectStyles();
    updateDepthConsole();
  }

  function dragMove(event) {
    if (!model?.drag) return;
    event.preventDefault();
    const point = stagePoint(event);
    record("drag_move", {object_id: model.drag.objectId, point});
    model.drag.moves += 1;
    model.dragSamples += 1;
    const item = model.objects[model.drag.objectId];
    item.x = point[0]; item.y = point[1]; item.placed = true;
    applyObjectStyles();
  }

  function dragEnd(event) {
    if (!model?.drag) return;
    event.preventDefault();
    const point = stagePoint(event);
    const drag = model.drag;
    const item = model.objects[drag.objectId];
    document.querySelector(`.rel-object[data-object-id="${CSS.escape(drag.objectId)}"]`)?.classList.remove("is-dragging");
    if (drag.moves >= 2 && inside(point, model.state.worktable_rect)) {
      record("drag_end", {object_id: drag.objectId, point});
      item.x = point[0]; item.y = point[1]; item.placed = true;
      model.dragCount += 1;
      model.helpers.setReadout(`${item.label} PLACED · DEPTH ${item.depth}`, "idle");
    } else {
      record("drag_cancel", {object_id: drag.objectId, point});
      Object.assign(item, drag.original);
      model.helpers.setReadout("DROP CANCELLED · OBJECT RETURNED", "error");
    }
    model.drag = null;
    applyObjectStyles();
    updateDepthConsole();
    updateControls();
  }

  function depthValue(event) {
    const rect = document.querySelector(".rel-depth-track").getBoundingClientRect();
    return Math.max(0, Math.min(100, Math.round(100 - (event.clientY - rect.top) / rect.height * 100)));
  }

  function depthStart(event) {
    const item = model.objects[model.selectedId];
    if (!item?.placed || model.settling || model.settled || model.terminal) return;
    event.preventDefault();
    document.querySelector(".rel-failure-stamp")?.remove();
    record("depth_start", {object_id: item.id, value: item.depth});
    model.depthDrag = {objectId: item.id, start: item.depth, moves: 0};
    document.querySelector(".rel-depth-track").setPointerCapture(event.pointerId);
  }

  function depthMove(event) {
    if (!model?.depthDrag) return;
    event.preventDefault();
    const value = depthValue(event);
    record("depth_move", {object_id: model.depthDrag.objectId, value});
    model.objects[model.depthDrag.objectId].depth = value;
    model.depthDrag.moves += 1;
    model.depthSamples += 1;
    applyObjectStyles();
    updateDepthConsole();
  }

  function depthEnd(event) {
    if (!model?.depthDrag) return;
    event.preventDefault();
    const item = model.objects[model.depthDrag.objectId];
    if (model.depthDrag.moves < 2) {
      const target = depthValue(event);
      for (const value of [Math.round((item.depth + target) / 2), target]) {
        record("depth_move", {object_id: item.id, value});
        item.depth = value;
        model.depthDrag.moves += 1;
        model.depthSamples += 1;
      }
    }
    record("depth_end", {object_id: item.id, value: item.depth});
    model.depthDistance += Math.abs(item.depth - model.depthDrag.start);
    model.depthDrag = null;
    applyObjectStyles(); updateDepthConsole(); updateControls();
    model.helpers.setReadout(`${item.label} DEPTH LOCKED AT ${item.depth}`, "idle");
  }

  function updateControls() {
    const allPlaced = Object.values(model.objects).every((item) => item.placed);
    const settleButton = document.querySelector(".rel-settle");
    if (settleButton) settleButton.disabled = !allPlaced || model.settling || model.settled;
    const status = document.querySelector(".rel-placed-count");
    if (status) status.dataset.ready = allPlaced ? "true" : "false";
  }

  function startSettle() {
    if (model.settling || model.settled || !Object.values(model.objects).every((item) => item.placed)) return;
    document.querySelector(".rel-failure-stamp")?.remove();
    record("settle_start");
    model.settling = true;
    model.selectedId = null;
    updateDepthConsole(); updateControls();
    document.querySelector(".rel-stage")?.classList.add("is-settling");
    model.helpers.setReadout("SETTLE TEST RUNNING · OBSERVE THE FINAL GRAPH", "pending");
    const startedAt = performance.now();
    let tick = 0;
    model.settleTimer = window.setInterval(() => {
      tick += 1;
      for (const item of Object.values(model.objects)) {
        const vector = model.state.settle_vectors[item.id];
        const factor = model.state.settle_ticks - tick + 1;
        item.x += Math.round(vector.dx * factor / model.state.settle_ticks);
        item.y += Math.round(vector.dy * factor / model.state.settle_ticks);
      }
      applyObjectStyles();
      const elapsed = Math.max(Math.round(performance.now() - startedAt), tick * 70);
      record("settle_tick", {tick, elapsed_ms: elapsed, snapshot: stateSnapshot()});
      model.settleSamples += 1;
      const meter = document.querySelector(".rel-settle-meter i");
      if (meter) meter.style.width = `${tick / model.state.settle_ticks * 100}%`;
      if (tick >= model.state.settle_ticks) {
        window.clearInterval(model.settleTimer);
        model.settleTimer = null;
        model.settling = false;
        model.settled = true;
        record("settle_complete", {elapsed_ms: Math.round(performance.now() - startedAt)});
        document.querySelector(".rel-stage")?.classList.remove("is-settling");
        document.querySelector(".rel-stage")?.classList.add("is-settled");
        model.helpers.setReadout("SETTLED · INSPECT THE FINAL RELATION GRAPH", "idle");
        updateControls();
      }
    }, model.state.settle_tick_ms);
  }

  function resetAssembly() {
    if (model.submitting || model.terminal) return;
    document.querySelector(".rel-failure-stamp")?.remove();
    if (model.settleTimer) window.clearInterval(model.settleTimer);
    record("reset");
    model.objects = Object.fromEntries(model.state.objects.map((item) => [item.id, {...item, x: null, y: null, depth: item.initial_depth, placed: false}]));
    model.drag = model.depthDrag = null;
    model.selectedId = null;
    model.settling = model.settled = false;
    model.dragCount = model.dragSamples = model.depthSamples = model.depthDistance = model.settleSamples = 0;
    model.resetCount += 1;
    document.querySelector(".rel-stage")?.classList.remove("is-settling", "is-settled");
    const meter = document.querySelector(".rel-settle-meter i"); if (meter) meter.style.width = "0";
    applyObjectStyles(); updateDepthConsole(); updateControls();
    model.helpers.setReadout("ASSEMBLY RESET · CAROUSEL RESTORED", "idle");
  }

  async function submit() {
    if (model.submitting || model.terminal) return;
    model.submitting = true;
    model.helpers.setReadout("REPLAYING GEOMETRY AND SETTLE FORCES…", "pending");
    try {
      const response = await fetch("/result", {method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({
        mechanic_id:model.state.mechanic_id,challenge_id:model.state.challenge_id,events:model.events,final_states:stateSnapshot(),
        drag_count:model.dragCount,drag_samples:model.dragSamples,depth_samples:model.depthSamples,depth_distance:model.depthDistance,
        settle_samples:model.settleSamples,reset_count:model.resetCount,completed:model.settled,
      })});
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".relation-assembly-captcha")?.insertAdjacentHTML("beforeend",'<div class="rel-verdict"><span>STABLE RELATION GRAPH CERTIFIED</span><strong>PASS</strong><small>DRAG · DEPTH · SETTLE REPLAY VERIFIED</small></div>');
        model.helpers.setReadout("PASS","passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell=document.querySelector(".relation-assembly-captcha"); shell?.setAttribute("data-fresh-failure","true"); shell?.insertAdjacentHTML("afterbegin",'<div class="rel-failure-stamp"><b>FAIL</b><span>UNSTABLE GRAPH · FRESH CONTRACT ISSUED</span></div>');
        const readout=document.querySelector(".readout"); if(readout){readout.textContent="FAIL · FRESH CONTRACT ISSUED";readout.dataset.status="error";}
      } else { model.submitting=false; model.helpers.setReadout("FAIL · NO AUTHORITATIVE GRADE","error"); }
    } catch (_error) { model.submitting=false; model.helpers.setReadout("FAIL · GEOMETRY VERIFIER OFFLINE","error"); }
  }

  function objectMarkup(item) {
    return `<div class="rel-object rel-shape-${clean(item.shape)} rel-color-${clean(item.color)}" data-object-id="${clean(item.id)}"><div class="rel-object-art"><i></i><b></b></div><span>${clean(item.label)}</span></div>`;
  }

  async function render(state, helpers) {
    if (model?.carouselTimer) window.clearInterval(model.carouselTimer);
    if (model?.settleTimer) window.clearInterval(model.settleTimer);
    document.body.dataset.mechanic="relation-assembly"; document.body.dataset.cheatMode=helpers.isCheatMode()?"true":"false";
    model={state,helpers,objects:Object.fromEntries(state.objects.map((item)=>[item.id,{...item,x:null,y:null,depth:item.initial_depth,placed:false}])),events:[],carouselTick:0,carouselTimer:null,settleTimer:null,drag:null,depthDrag:null,selectedId:null,settling:false,settled:false,dragCount:0,dragSamples:0,depthSamples:0,depthDistance:0,settleSamples:0,resetCount:0,submitting:false,terminal:false};
    window.relationAssemblyModel=model;
    helpers.app.innerHTML=`<section class="relation-assembly-captcha" data-challenge-id="${clean(state.challenge_id)}"><header class="rel-head"><div><span>RELATION ASSEMBLY TABLE / CONTRACT ${clean(state.challenge_id)}</span><h1>${clean(state.prompt)}</h1></div><div class="rel-contract">${state.constraints.map((item,index)=>`<div><b>R${index+1}</b><span>${clean(item.text)}</span></div>`).join("")}</div></header><main class="rel-main"><section class="rel-stage"><div class="rel-carousel"><span>ROTATING STAGING CAROUSEL</span><i></i></div><div class="rel-table"><span>STABLE WORKTABLE</span><div class="rel-depth-bands"><i>REAR</i><i>MID</i><i>FRONT</i></div></div>${state.objects.map(objectMarkup).join("")}<div class="rel-settle-overlay"><b>SETTLE / INSPECTION</b><span>MILD DETERMINISTIC FORCES ACTIVE</span></div></section><aside class="rel-console"><p>DEPTH CALIBRATION</p><h2>Position is only half the graph.</h2><div class="rel-depth-selection"><span>SELECTED OBJECT</span><b>NO OBJECT</b></div><div class="rel-depth-rig"><div><span>FRONT / 100</span><div class="rel-depth-track"><i></i><b class="rel-depth-knob"></b></div><span>REAR / 000</span></div><strong class="rel-depth-value">---</strong></div><div class="rel-object-list">${state.objects.map((item)=>`<button type="button" class="rel-select" data-object-id="${clean(item.id)}"><i class="rel-mini-${clean(item.shape)}"></i><span>${clean(item.label)}</span></button>`).join("")}</div><div class="rel-settle-meter"><span>SETTLE OBSERVATION</span><b><i></i></b></div><button type="button" class="rel-settle" disabled>START SETTLE / INSPECTION</button><p class="rel-console-note">All five objects must leave the moving carousel. The verifier reconstructs centers, contact radii, containment, depth, and every settle displacement.</p></aside></main><footer class="rel-foot"><button type="button" class="rel-reset">RESET ASSEMBLY</button><div><span class="rel-placed-count" data-ready="false">0/5 ON TABLE</span><div class="readout" data-status="idle">MOVE EVERY OBJECT FROM THE CAROUSEL</div></div><button type="button" class="rel-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    const stage=document.querySelector(".rel-stage"); stage.addEventListener("pointerdown",dragStart);stage.addEventListener("pointermove",dragMove);stage.addEventListener("pointerup",dragEnd);stage.addEventListener("pointercancel",dragEnd);
    const depth=document.querySelector(".rel-depth-track");depth.addEventListener("pointerdown",depthStart);depth.addEventListener("pointermove",depthMove);depth.addEventListener("pointerup",depthEnd);depth.addEventListener("pointercancel",depthEnd);
    document.querySelectorAll(".rel-console .rel-select").forEach((button)=>button.addEventListener("click",()=>selectObject(button.dataset.objectId)));
    document.querySelector(".rel-settle").addEventListener("click",startSettle);document.querySelector(".rel-reset").addEventListener("click",resetAssembly);document.querySelector(".rel-submit").addEventListener("click",submit);
    model.carouselTimer=window.setInterval(()=>{model.carouselTick=(model.carouselTick+1)%state.carousel.ticks;applyObjectStyles();},state.carousel.tick_ms);
    applyObjectStyles();updateDepthConsole();updateControls();helpers.installCheatPanel();
  }

  window.WeirdCaptchaMechanics=window.WeirdCaptchaMechanics||{};
  window.WeirdCaptchaMechanics.relation_prompt_grounding={rootSelector:".relation-assembly-captcha",render};
})();
