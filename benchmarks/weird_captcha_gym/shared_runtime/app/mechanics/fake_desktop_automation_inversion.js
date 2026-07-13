(() => {
  "use strict";

  let model = null;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function cloneWindows(source) {
    return Object.fromEntries((source || []).map((item) => [item.id, {...item}]));
  }

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value));
  }

  function inside(point, rect) {
    return point[0] >= rect[0] && point[0] <= rect[0] + rect[2]
      && point[1] >= rect[1] && point[1] <= rect[1] + rect[3];
  }

  function mappingName() {
    return model.state.mapping_sequence[model.boundary];
  }

  function mapPoint(physical) {
    const {width, height} = model.state.desktop;
    const [x, y] = physical;
    if (mappingName() === "mirror_x") return [width - x, y];
    if (mappingName() === "mirror_y") return [x, height - y];
    if (mappingName() === "rotate_180") return [width - x, height - y];
    return [x, y];
  }

  function eventPoint(event) {
    const desktop = document.querySelector(".fd-desktop");
    const rect = desktop.getBoundingClientRect();
    const physical = [
      clamp(Math.round((event.clientX - rect.left) / rect.width * model.state.desktop.width), 0, model.state.desktop.width),
      clamp(Math.round((event.clientY - rect.top) / rect.height * model.state.desktop.height), 0, model.state.desktop.height),
    ];
    return {physical, remote: mapPoint(physical)};
  }

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function topWindow(point) {
    return Object.values(model.windows)
      .filter((item) => !item.closed && inside(point, [item.x, item.y, item.width, item.height]))
      .sort((a, b) => b.z - a.z)[0] || null;
  }

  function fileRect(window, file) {
    const geometry = model.state.geometry;
    const [originX, originY] = geometry.file_origin;
    const [width, height] = geometry.file_size;
    return [window.x + originX + file.slot * (width + geometry.file_gap), window.y + originY, width, height];
  }

  function relativeRect(window, values) {
    return [window.x + values[0], window.y + values[1], values[2], values[3]];
  }

  function downHit(point) {
    const window = topWindow(point);
    if (!window) return {hit: "desktop", window: null};
    const closeRect = [
      window.x + window.width - model.state.geometry.close_width,
      window.y,
      model.state.geometry.close_width,
      model.state.geometry.title_height,
    ];
    if (window.closable && inside(point, closeRect)) return {hit: `close:${window.id}`, window};
    if (window.id === "vault") {
      for (const file of model.state.files) {
        if (inside(point, fileRect(window, file))) return {hit: `file:${file.id}`, window};
      }
    }
    if (window.id === "verifier" && inside(point, relativeRect(window, model.state.geometry.arm_control))) {
      return {hit: "arm", window};
    }
    if (point[1] <= window.y + model.state.geometry.title_height) return {hit: `title:${window.id}`, window};
    return {hit: `window:${window.id}`, window};
  }

  function bringToFront(window) {
    const top = Math.max(...Object.values(model.windows).filter((item) => !item.closed).map((item) => item.z));
    if (window.z !== top) model.zOrderChanges += 1;
    model.zCounter += 1;
    window.z = model.zCounter;
  }

  function fileMarkup(window) {
    const geometry = model.state.geometry;
    return model.state.files.map((file) => {
      const rect = fileRect(window, file);
      const left = (rect[0] - window.x) / window.width * 100;
      const top = (rect[1] - window.y) / window.height * 100;
      const width = rect[2] / window.width * 100;
      const height = rect[3] / window.height * 100;
      const loaded = model.loadedFileId === file.id;
      return `<div class="fd-keyfile ${loaded ? "is-loaded" : ""}" data-file-id="${clean(file.id)}" style="left:${left}%;top:${top}%;width:${width}%;height:${height}%"><i></i><b>${clean(file.name)}</b><span>${loaded ? "IN VERIFIER" : "LOCAL FILE"}</span></div>`;
    }).join("");
  }

  function windowBody(window) {
    if (window.id === "directive") {
      return `<div class="fd-directive"><strong>HUMAN INPUT REQUIRED</strong><span>Recover <b>${clean(model.state.target_filename)}</b></span><small>Pointer mapping is visible. Follow the remote cursor—not the physical ring.</small></div>`;
    }
    if (window.id === "vault") {
      return `<div class="fd-vault-grid">${fileMarkup(window)}</div>`;
    }
    if (window.id === "verifier") {
      const drop = model.state.geometry.drop_zone;
      const arm = model.state.geometry.arm_control;
      return `<div class="fd-drop-zone ${model.loadedFileId ? "has-file" : ""}" style="left:${drop[0] / window.width * 100}%;top:${drop[1] / window.height * 100}%;width:${drop[2] / window.width * 100}%;height:${drop[3] / window.height * 100}%"><span>${model.loadedFileId ? "KEYFILE INGESTED" : "DROP KEYFILE HERE"}</span><b>${model.loadedFileId ? clean((model.state.files.find((item) => item.id === model.loadedFileId) || {}).name) : "NO TOKEN"}</b></div><div class="fd-arm-control ${model.armed ? "is-armed" : ""}" style="left:${arm[0] / window.width * 100}%;top:${arm[1] / window.height * 100}%;width:${arm[2] / window.width * 100}%;height:${arm[3] / window.height * 100}%"><i></i><b>${model.armed ? "MANUAL CONTROL ARMED" : "ARM MANUAL CONTROL"}</b></div>`;
    }
    return `<div class="fd-interceptor-body"><div class="fd-scan-lines"><i></i><i></i><i></i><i></i></div><strong>AUTOMATION SIGNATURE DETECTED</strong><p>This window is obstructing operator files. Close it with the transformed remote cursor.</p><span>CONFIDENCE ${(86 + Number(model.state.challenge_id.slice(-1), 16) % 12)}%</span></div>`;
  }

  function renderWindows() {
    const layer = document.querySelector(".fd-window-layer");
    if (!layer) return;
    const {width, height} = model.state.desktop;
    layer.innerHTML = Object.values(model.windows)
      .filter((window) => !window.closed)
      .sort((a, b) => a.z - b.z)
      .map((window) => `<section class="fd-window fd-window-${clean(window.id)}" data-window-id="${clean(window.id)}" style="left:${window.x / width * 100}%;top:${window.y / height * 100}%;width:${window.width / width * 100}%;height:${window.height / height * 100}%;z-index:${window.z}"><header class="fd-window-title" style="height:${model.state.geometry.title_height / window.height * 100}%"><span><i></i>${clean(window.title)}</span><b style="width:${model.state.geometry.close_width / window.width * 100}%">×</b></header><div class="fd-window-body">${windowBody(window)}</div></section>`).join("");
  }

  function updateCursor(physical, remote) {
    const physicalNode = document.querySelector(".fd-physical-cursor");
    const remoteNode = document.querySelector(".fd-remote-cursor");
    const {width, height} = model.state.desktop;
    if (physicalNode) {
      physicalNode.style.left = `${physical[0] / width * 100}%`;
      physicalNode.style.top = `${physical[1] / height * 100}%`;
    }
    if (remoteNode) {
      remoteNode.style.left = `${remote[0] / width * 100}%`;
      remoteNode.style.top = `${remote[1] / height * 100}%`;
    }
    const coordinates = document.querySelector(".fd-coordinate-readout");
    if (coordinates) coordinates.textContent = `PHYSICAL ${String(physical[0]).padStart(3, "0")},${String(physical[1]).padStart(3, "0")}  →  REMOTE ${String(remote[0]).padStart(3, "0")},${String(remote[1]).padStart(3, "0")}`;
  }

  function showBoundary() {
    const label = model.state.mapping_labels[mappingName()] || mappingName();
    const badge = document.querySelector(".fd-mapping-badge");
    if (badge) badge.innerHTML = `<span>CHANNEL ${model.boundary + 1}/2</span><b>${clean(label)}</b>`;
    const banner = document.querySelector(".fd-remap-banner");
    if (banner) {
      banner.innerHTML = `<span>WORKFLOW BOUNDARY</span><b>REMOTE CURSOR REMAPPED</b><small>${clean(label)}</small>`;
      banner.classList.add("is-visible");
      window.setTimeout(() => banner.classList.remove("is-visible"), 1600);
    }
  }

  function pointerDown(event) {
    if (!model || model.submitting || model.terminal) return;
    event.preventDefault();
    document.querySelector(".fd-failure-stamp")?.remove();
    const points = eventPoint(event);
    updateCursor(points.physical, points.remote);
    const result = downHit(points.remote);
    record("pointer_down", {physical: points.physical, remote: points.remote, boundary: model.boundary, mapping: mappingName(), hit: result.hit});
    model.pointerDown = true;
    const desktop = document.querySelector(".fd-desktop");
    if (desktop && event.pointerId != null) desktop.setPointerCapture(event.pointerId);

    if (result.hit.startsWith("close:") && result.window) {
      result.window.closed = true;
      model.closedCount += 1;
      renderWindows();
      model.helpers.setReadout(`${result.window.title} CLOSED · REMOTE INPUT ACCEPTED`, "idle");
      return;
    }
    if (result.window) bringToFront(result.window);
    if (result.hit.startsWith("title:") && result.window) {
      model.drag = {type: "window", id: result.window.id, offset: [points.remote[0] - result.window.x, points.remote[1] - result.window.y], start: [result.window.x, result.window.y]};
    } else if (result.hit.startsWith("file:")) {
      model.drag = {type: "file", id: result.hit.split(":", 2)[1], moves: 0};
      const ghost = document.querySelector(".fd-file-ghost");
      if (ghost) {
        const file = model.state.files.find((item) => item.id === model.drag.id);
        ghost.textContent = file ? file.name : "KEYFILE";
        ghost.classList.add("is-visible");
      }
    } else if (result.hit === "arm") {
      if (model.boundary === 1 && model.loadedFileId === model.targetFileId) {
        model.armed = true;
        model.helpers.setReadout("MANUAL CONTROL ARMED · READY TO SUBMIT", "idle");
      } else {
        model.helpers.setReadout("ARM REJECTED · LOAD THE REQUESTED KEYFILE", "error");
      }
    }
    renderWindows();
  }

  function pointerMove(event) {
    if (!model) return;
    const points = eventPoint(event);
    updateCursor(points.physical, points.remote);
    if (!model.pointerDown) return;
    record("pointer_move", {physical: points.physical, remote: points.remote, boundary: model.boundary, mapping: mappingName()});
    if (model.drag?.type === "window") {
      const windowModel = model.windows[model.drag.id];
      windowModel.x = clamp(points.remote[0] - model.drag.offset[0], 0, model.state.desktop.width - windowModel.width);
      windowModel.y = clamp(points.remote[1] - model.drag.offset[1], 0, model.state.desktop.height - windowModel.height);
      renderWindows();
    } else if (model.drag?.type === "file") {
      model.drag.moves += 1;
      model.fileDragMoves += 1;
      const ghost = document.querySelector(".fd-file-ghost");
      if (ghost) {
        ghost.style.left = `${points.remote[0] / model.state.desktop.width * 100}%`;
        ghost.style.top = `${points.remote[1] / model.state.desktop.height * 100}%`;
      }
    }
  }

  function pointerUp(event) {
    if (!model || !model.pointerDown) return;
    const points = eventPoint(event);
    updateCursor(points.physical, points.remote);
    record("pointer_up", {physical: points.physical, remote: points.remote, boundary: model.boundary, mapping: mappingName()});
    const drag = model.drag;
    model.pointerDown = false;
    model.drag = null;
    if (drag?.type === "window") {
      const windowModel = model.windows[drag.id];
      const distance = Math.hypot(windowModel.x - drag.start[0], windowModel.y - drag.start[1]);
      if (distance >= 44) model.moveCount += 1;
      model.helpers.setReadout(distance >= 44 ? "WINDOW REPOSITIONED · Z-ORDER UPDATED" : "WINDOW FOCUSED", "idle");
    } else if (drag?.type === "file") {
      const verifier = model.windows.verifier;
      const validDrop = verifier && !verifier.closed && inside(points.remote, relativeRect(verifier, model.state.geometry.drop_zone));
      if (validDrop) {
        model.loadedFileId = drag.id;
        const file = model.state.files.find((item) => item.id === drag.id);
        if (drag.id === model.targetFileId) {
          record("boundary", {from: 0, to: 1, reason: "keyfile_loaded", mapping: model.state.mapping_sequence[1]});
          model.boundary = 1;
          model.helpers.setReadout("KEYFILE ACCEPTED · CONTROL CHANNEL REMAPPED", "idle");
          showBoundary();
        } else {
          model.helpers.setReadout(`${file ? file.name : "KEYFILE"} REJECTED · WRONG TOKEN`, "error");
        }
      } else {
        model.helpers.setReadout("KEYFILE DROP MISSED · TRY AGAIN", "error");
      }
      const ghost = document.querySelector(".fd-file-ghost");
      if (ghost) ghost.classList.remove("is-visible");
    }
    renderWindows();
  }

  function snapshotWindows() {
    return Object.values(model.windows)
      .sort((a, b) => a.id.localeCompare(b.id))
      .map((window) => ({id: window.id, x: window.x, y: window.y, z: window.z, closed: window.closed}));
  }

  function resetDesktop() {
    if (!model || model.submitting || model.terminal) return;
    document.querySelector(".fd-failure-stamp")?.remove();
    record("reset");
    model.windows = cloneWindows(model.state.windows);
    model.zCounter = Math.max(...Object.values(model.windows).map((item) => item.z));
    model.boundary = 0;
    model.loadedFileId = null;
    model.armed = false;
    model.drag = null;
    model.pointerDown = false;
    model.moveCount = 0;
    model.closedCount = 0;
    model.zOrderChanges = 0;
    model.fileDragMoves = 0;
    model.resetCount += 1;
    renderWindows();
    showBoundary();
    model.helpers.setReadout("DESKTOP RESTORED · CHANNEL 1 RECALIBRATED", "idle");
  }

  async function submit() {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    model.helpers.setReadout("REPLAYING TRANSFORMED INPUT…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          mechanic_id: model.state.mechanic_id,
          challenge_id: model.state.challenge_id,
          events: model.events,
          window_state: snapshotWindows(),
          boundary_index: model.boundary,
          active_mapping: mappingName(),
          loaded_file_id: model.loadedFileId,
          armed: model.armed,
          move_count: model.moveCount,
          closed_count: model.closedCount,
          z_order_changes: model.zOrderChanges,
          file_drag_moves: model.fileDragMoves,
          reset_count: model.resetCount,
          completed: model.armed && model.loadedFileId === model.targetFileId,
        }),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".fake-desktop-captcha")?.classList.add("is-pass");
        document.querySelector(".fake-desktop-captcha")?.insertAdjacentHTML("beforeend", '<div class="fd-verdict fd-verdict-pass"><span>MANUAL INPUT AUTHENTICATED</span><strong>PASS</strong><small>TRANSFORMED POINTER TRACE VERIFIED</small></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".fake-desktop-captcha");
        shell?.setAttribute("data-fresh-failure", "true");
        shell?.insertAdjacentHTML("afterbegin", '<div class="fd-failure-stamp"><b>FAIL</b><span>TRACE REJECTED · FRESH DESKTOP ISSUED</span></div>');
        const readout = document.querySelector(".readout");
        if (readout) { readout.textContent = "FAIL · FRESH DESKTOP ISSUED"; readout.dataset.status = "error"; }
      } else {
        model.submitting = false;
        model.helpers.setReadout("FAIL · NO AUTHORITATIVE GRADE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      model.helpers.setReadout("FAIL · VERIFIER OFFLINE", "error");
    }
  }

  async function render(state, helpers) {
    document.body.dataset.mechanic = "fake-desktop-automation-inversion";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    const targetFile = state.files.find((item) => item.name === state.target_filename);
    model = {
      state,
      helpers,
      windows: cloneWindows(state.windows),
      targetFileId: targetFile ? targetFile.id : "",
      zCounter: Math.max(...state.windows.map((item) => item.z)),
      boundary: 0,
      loadedFileId: null,
      armed: false,
      events: [],
      drag: null,
      pointerDown: false,
      moveCount: 0,
      closedCount: 0,
      zOrderChanges: 0,
      fileDragMoves: 0,
      resetCount: 0,
      submitting: false,
      terminal: false,
    };
    window.fakeDesktopInversionModel = model;
    helpers.app.innerHTML = `<section class="fake-desktop-captcha" data-challenge-id="${clean(state.challenge_id)}"><header class="fd-head"><div><span>MANUALITY LAB / REMOTE DESKTOP 04</span><h1>${clean(state.prompt)}</h1></div><div class="fd-mapping-badge"><span>CHANNEL 1/2</span><b>${clean(state.mapping_labels[state.mapping_sequence[0]])}</b></div></header><main class="fd-workbench"><section class="fd-desktop" aria-label="Transformed remote desktop"><div class="fd-grid-labels"><span>000</span><span>450</span><span>900</span></div><div class="fd-window-layer"></div><div class="fd-file-ghost"></div><div class="fd-physical-cursor"><i></i><span>PHYSICAL</span></div><div class="fd-remote-cursor"><i></i><span>REMOTE</span></div><div class="fd-remap-banner"></div><div class="fd-coordinate-readout">MOVE INSIDE GRID TO CALIBRATE</div></section><aside class="fd-brief"><p class="fd-brief-label">WORK ORDER / ${clean(state.challenge_id)}</p><h2>Prove you are not automating the automation.</h2><ol>${state.workflow.map((item, index) => `<li><b>${String(index + 1).padStart(2, "0")}</b><span>${clean(item)}</span></li>`).join("")}</ol><div class="fd-legend"><span><i class="is-physical"></i>Physical ring</span><span><i class="is-remote"></i>Remote action cursor</span></div><p class="fd-brief-note">Every mapped pointer action, window move, z-order change, and keyfile drop is replayed by the verifier.</p></aside></main><footer class="fd-foot"><button type="button" class="fd-reset">RESTORE WINDOWS</button><div><span>TRACE STATUS</span><div class="readout" data-status="idle">CALIBRATE REMOTE CURSOR · CLOSE THE INTERCEPTOR</div></div><button type="button" class="fd-submit">${clean(state.submit_label)}</button></footer>${helpers.cheatPanelTemplate()}</section>`;
    renderWindows();
    const desktop = document.querySelector(".fd-desktop");
    desktop.addEventListener("pointerdown", pointerDown);
    desktop.addEventListener("pointermove", pointerMove);
    desktop.addEventListener("pointerup", pointerUp);
    desktop.addEventListener("pointercancel", pointerUp);
    document.querySelector(".fd-reset").addEventListener("click", resetDesktop);
    document.querySelector(".fd-submit").addEventListener("click", submit);
    helpers.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.fake_desktop_automation_inversion = {rootSelector: ".fake-desktop-captcha", render};
})();
