(() => {
  "use strict";

  const model = {
    state: null,
    phase: "ready",
    previewIndex: -1,
    phaseStartedAt: 0,
    performanceStartedAt: 0,
    transcript: [],
    held: new Map(),
    timer: 0,
    frame: 0,
    audio: null,
    submitting: false,
  };
  window.polyrhythmCustomsModel = model;

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  function clearRun() {
    if (model.timer) window.clearTimeout(model.timer);
    if (model.frame) window.cancelAnimationFrame(model.frame);
    model.timer = 0;
    model.frame = 0;
  }

  function laneById(laneId) {
    return (model.state?.lanes || []).find((lane) => lane.id === laneId);
  }

  function setupAudio() {
    if (model.audio) return;
    try {
      const AudioContext = window.AudioContext || window.webkitAudioContext;
      if (AudioContext) model.audio = new AudioContext();
    } catch (_error) {
      model.audio = null;
    }
  }

  function beep(laneId, duration = 0.09) {
    if (!model.audio) return;
    try {
      const index = (model.state.lanes || []).findIndex((lane) => lane.id === laneId);
      const oscillator = model.audio.createOscillator();
      const gain = model.audio.createGain();
      oscillator.type = index === 0 ? "triangle" : index === 1 ? "sine" : "square";
      oscillator.frequency.value = [330, 440, 550][Math.max(0, index)] || 440;
      gain.gain.setValueAtTime(0.0001, model.audio.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.08, model.audio.currentTime + 0.012);
      gain.gain.exponentialRampToValueAtTime(0.0001, model.audio.currentTime + Math.max(0.05, duration));
      oscillator.connect(gain).connect(model.audio.destination);
      oscillator.start();
      oscillator.stop(model.audio.currentTime + Math.max(0.06, duration) + 0.02);
    } catch (_error) {
      // Visual pulses are the authoritative preview; audio is optional.
    }
  }

  function scoreMarkup(activeLaneId) {
    const duration = Number(model.state.settings.performance_ms);
    return (model.state.lanes || []).map((lane, laneIndex) => {
      const active = lane.id === activeLaneId;
      const notes = (model.state.score || []).filter((note) => note.lane === lane.id);
      const noteMarkup = active ? notes.map((note) => {
        const left = Number(note.start_ms) * 100 / duration;
        const width = Math.max(1.4, Number(note.duration_ms) * 100 / duration);
        return `<i class="rhythm-score-note" data-note-id="${clean(note.id)}" data-kind="${clean(note.kind)}" data-chord="${note.chord_id ? "true" : "false"}" style="left:${left.toFixed(3)}%;width:${width.toFixed(3)}%"><b></b></i>`;
      }).join("") : '<div class="rhythm-sealed-score"><i></i><i></i><i></i><span>SEALED</span></div>';
      return `<div class="rhythm-score-lane" data-lane="${clean(lane.id)}" data-index="${laneIndex}" data-active="${active}">
        <header><span>${clean(lane.glyph)}</span><b>LANE ${lane.key}</b><i>${clean(lane.label)}</i></header>
        <div class="rhythm-score-track">${noteMarkup}</div>
      </div>`;
    }).join("");
  }

  function updatePhase(label, sublabel) {
    const labelNode = document.querySelector(".rhythm-phase-label");
    const subNode = document.querySelector(".rhythm-phase-sub");
    if (labelNode) labelNode.textContent = label;
    if (subNode) subNode.textContent = sublabel;
  }

  function pulseLane(laneId, active) {
    const pad = document.querySelector(`.rhythm-pad[data-lane="${laneId}"]`);
    if (pad) pad.dataset.pressed = active ? "true" : "false";
  }

  function drawPreview(helpers) {
    if (model.phase !== "preview") return;
    const laneIndex = Number(model.state.preview_order[model.previewIndex]);
    const lane = model.state.lanes[laneIndex];
    const scale = Number(model.state.settings.preview_scale);
    const elapsed = performance.now() - model.phaseStartedAt;
    const normalized = elapsed / scale;
    const duration = Number(model.state.settings.performance_ms);
    const scanhead = document.querySelector(".rhythm-scanhead");
    if (scanhead) scanhead.style.left = `${Math.min(100, normalized * 100 / duration)}%`;
    const notes = (model.state.score || []).filter((note) => note.lane === lane.id);
    let laneActive = false;
    notes.forEach((note) => {
      const active = normalized >= Number(note.start_ms) && normalized <= Number(note.start_ms) + Number(note.duration_ms);
      const node = document.querySelector(`.rhythm-score-note[data-note-id="${note.id}"]`);
      if (node) node.dataset.playing = active ? "true" : "false";
      if (active) laneActive = true;
      if (active && node?.dataset.sounded !== "true") {
        node.dataset.sounded = "true";
        beep(lane.id, Math.max(.08, Number(note.duration_ms) * scale / 1000));
      }
    });
    pulseLane(lane.id, laneActive);
    const progress = document.querySelector(".rhythm-phase-progress i");
    if (progress) progress.style.transform = `scaleX(${Math.min(1, normalized / duration)})`;
    model.frame = requestAnimationFrame(() => drawPreview(helpers));
  }

  function runPreview(index, helpers) {
    clearRun();
    if (index >= model.state.preview_order.length) {
      beginCountdown(helpers);
      return;
    }
    model.phase = "preview";
    model.previewIndex = index;
    const laneIndex = Number(model.state.preview_order[index]);
    const lane = model.state.lanes[laneIndex];
    model.phaseStartedAt = performance.now();
    const board = document.querySelector(".rhythm-score-board");
    if (board) {
      board.dataset.hidden = "false";
      board.innerHTML = `<div class="rhythm-score-lanes">${scoreMarkup(lane.id)}</div><i class="rhythm-scanhead"></i>`;
    }
    updatePhase(`PREVIEW ${index + 1}/3 · LANE ${lane.key} ONLY`, `${lane.label} manifest · remember taps, bars, and shared stamps`);
    helpers.setReadout(`OBSERVE LANE ${lane.key} · INPUT LOCKED`, "pending");
    drawPreview(helpers);
    const duration = Number(model.state.settings.performance_ms) * Number(model.state.settings.preview_scale);
    model.timer = window.setTimeout(() => {
      pulseLane(lane.id, false);
      runPreview(index + 1, helpers);
    }, duration + Number(model.state.settings.preview_gap_ms));
  }

  function beginCountdown(helpers) {
    clearRun();
    model.phase = "countdown";
    const board = document.querySelector(".rhythm-score-board");
    if (board) {
      board.dataset.hidden = "true";
      board.innerHTML = '<div class="rhythm-seal"><span>ALL THREE MANIFESTS SEALED</span><strong>3</strong><i>COMBINE FROM MEMORY</i></div>';
    }
    let count = 3;
    const step = Number(model.state.settings.countdown_ms) / 3;
    const advance = () => {
      const node = document.querySelector(".rhythm-seal strong");
      if (node) node.textContent = String(count);
      updatePhase("COMBINED CLEARANCE INCOMING", `${count} · hands on A / S / D`);
      if (count <= 0) {
        beginPerformance(helpers);
        return;
      }
      count -= 1;
      model.timer = window.setTimeout(advance, step);
    };
    advance();
  }

  function recordEvent(laneId, type, source) {
    if (model.phase !== "performance" || model.submitting) return;
    const now = performance.now();
    if (type === "down") {
      if (model.held.has(laneId)) return;
      model.held.set(laneId, source);
      pulseLane(laneId, true);
      beep(laneId, .13);
    } else {
      if (!model.held.has(laneId)) return;
      model.held.delete(laneId);
      pulseLane(laneId, false);
    }
    model.transcript.push({
      seq: model.transcript.length,
      lane: laneId,
      type,
      t_ms: Number((now - model.performanceStartedAt).toFixed(2)),
      source,
    });
    const count = document.querySelector(".rhythm-event-count");
    if (count) count.textContent = String(model.transcript.length).padStart(2, "0");
  }

  function drawPerformance(helpers) {
    if (model.phase !== "performance") return;
    const elapsed = performance.now() - model.performanceStartedAt;
    const duration = Number(model.state.settings.performance_ms);
    const progress = Math.min(1, elapsed / duration);
    const meter = document.querySelector(".rhythm-performance-meter i");
    if (meter) meter.style.transform = `scaleX(${progress})`;
    const clock = document.querySelector(".rhythm-performance-clock");
    if (clock) clock.textContent = `${Math.max(0, (duration - elapsed) / 1000).toFixed(1)}s`;
    if (elapsed < duration) model.frame = requestAnimationFrame(() => drawPerformance(helpers));
  }

  function beginPerformance(helpers) {
    clearRun();
    model.phase = "performance";
    model.transcript = [];
    model.held.clear();
    model.performanceStartedAt = performance.now();
    const shell = document.querySelector(".polyrhythm-customs-captcha");
    if (shell) shell.dataset.phase = "performance";
    const board = document.querySelector(".rhythm-score-board");
    if (board) board.innerHTML = '<div class="rhythm-performance-void"><span>MANIFEST HIDDEN</span><strong>PERFORM THE COMBINED SCORE</strong><i>taps · holds · simultaneous stamps</i></div>';
    updatePhase("LIVE COMBINED INSPECTION", "A / S / D · keydown and release are both recorded");
    helpers.setReadout("PERFORM NOW · START WINDOW ±230ms", "idle");
    drawPerformance(helpers);
    model.timer = window.setTimeout(() => endPerformance(helpers), Number(model.state.settings.performance_ms) + 260);
  }

  function endPerformance(helpers) {
    if (model.phase !== "performance" || model.submitting) return;
    [...model.held.entries()].forEach(([laneId, source]) => recordEvent(laneId, "up", source));
    model.phase = "grading";
    submitPerformance(helpers);
  }

  async function submitPerformance(helpers) {
    if (model.submitting || !model.state) return;
    clearRun();
    model.submitting = true;
    helpers.setReadout("ALIGNING THREE MANIFESTS…", "pending");
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify({
          mechanic_id: model.state.mechanic_id,
          task_id: model.state.task_id,
          challenge_id: model.state.challenge_id,
          transcript: model.transcript,
        }),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.phase = "pass";
        const shell = document.querySelector(".polyrhythm-customs-captcha");
        if (shell) shell.dataset.terminal = "pass";
        const stamp = document.querySelector(".rhythm-terminal-stamp");
        if (stamp) stamp.innerHTML = '<span>POLYRHYTHM ACCEPTED</span><strong>PASS</strong><i>THREE LANES / ONE CLEARANCE</i>';
        helpers.setReadout("PASS · COMBINED PERFORMANCE VERIFIED", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await helpers.render(outcome.state);
        const shell = document.querySelector(".polyrhythm-customs-captcha");
        if (shell) shell.dataset.freshFailure = "true";
        helpers.setReadout("FAIL · FRESH MANIFESTS ISSUED", "error");
      } else {
        model.submitting = false;
        model.phase = "ready";
        helpers.setReadout("FAIL · NO PERFORMANCE GRADE", "error");
      }
    } catch (_error) {
      model.submitting = false;
      model.phase = "ready";
      helpers.setReadout("FAIL · CUSTOMS LINK OFFLINE", "error");
    }
  }

  function startTrial(helpers) {
    if (model.submitting || model.phase === "pass") return;
    clearRun();
    setupAudio();
    model.transcript = [];
    model.held.clear();
    document.querySelector(".rhythm-start-curtain")?.setAttribute("data-open", "true");
    document.querySelector(".polyrhythm-customs-captcha")?.setAttribute("data-phase", "preview");
    document.querySelectorAll(".rhythm-pad").forEach((pad) => { pad.dataset.pressed = "false"; });
    runPreview(0, helpers);
  }

  async function render(state, helpers) {
    clearRun();
    document.body.dataset.mechanic = "polyrhythm-customs";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model.state = state;
    model.phase = "ready";
    model.previewIndex = -1;
    model.transcript = [];
    model.held.clear();
    model.submitting = false;
    helpers.app.innerHTML = `
      <section class="polyrhythm-customs-captcha" data-challenge-id="${clean(state.challenge_id)}" data-phase="ready">
        <div class="rhythm-grain"></div>
        <header class="rhythm-head">
          <div><span>PORT OF ENTRY / SONIC DECLARATIONS</span><h1>${clean(state.prompt)}</h1></div>
          <aside><span>FORM PR-3</span><b>3 LANES</b><i>ACCURACY ≥ ${state.rules.pass_accuracy_percent}%</i></aside>
        </header>
        <main class="rhythm-main">
          <section class="rhythm-manifest">
            <header><div><span class="rhythm-phase-label">MANIFESTS SEALED</span><b class="rhythm-phase-sub">Press begin to inspect each lane separately</b></div><div class="rhythm-passport-mark">PR<br><i>03</i></div></header>
            <div class="rhythm-score-board" data-hidden="false"><div class="rhythm-ready-seal"><span>SEQUENTIAL PREVIEW</span><strong>① ② ③</strong><i>THEN COMBINE FROM MEMORY</i></div></div>
            <div class="rhythm-phase-progress"><i></i></div>
          </section>
          <aside class="rhythm-rules">
            <div class="rhythm-rule-card"><span>01</span><b>WATCH SEPARATELY</b><p>Only one lane is revealed at a time. Long bars must be held.</p></div>
            <div class="rhythm-rule-card"><span>02</span><b>PERFORM TOGETHER</b><p>When the score vanishes, interleave all three lanes. Shared marks are chords.</p></div>
            <div class="rhythm-tolerance-card"><span>INSPECTION TOLERANCE</span><dl><div><dt>START</dt><dd>±${state.rules.start_window_ms}ms</dd></div><div><dt>HOLD</dt><dd>±${state.rules.duration_tolerance_ms}ms</dd></div><div><dt>CHORD</dt><dd>${state.rules.chord_window_ms}ms</dd></div></dl></div>
          </aside>
        </main>
        <section class="rhythm-console">
          <div class="rhythm-pad-bank">
            ${(state.lanes || []).map((lane, index) => `<button type="button" class="rhythm-pad" data-lane="${clean(lane.id)}" data-key="${clean(lane.key)}" data-index="${index}" data-pressed="false"><i>${clean(lane.glyph)}</i><strong>${clean(lane.key)}</strong><span>${clean(lane.label)}</span><b></b></button>`).join("")}
          </div>
          <div class="rhythm-live-panel"><span>EVENTS <b class="rhythm-event-count">00</b></span><div class="rhythm-performance-meter"><i></i></div><strong class="rhythm-performance-clock">—</strong></div>
          <button type="button" class="rhythm-certify-now">CERTIFY NOW</button>
          <button type="button" class="rhythm-replay">REPLAY WHOLE TRIAL</button>
        </section>
        <footer class="rhythm-foot"><div class="readout" data-status="idle">READY · AUDIO OPTIONAL / VISUAL PULSES AUTHORITATIVE</div><span>KEYDOWN + KEYUP RECORDED · A / S / D</span></footer>
        <div class="rhythm-terminal-stamp"></div>
        <div class="rhythm-start-curtain"><div><span>POLYRHYTHM CUSTOMS</span><strong>DECLARE<br>YOUR RHYTHM</strong><p>Three officers will reveal their stamps one lane at a time. Then every manifest disappears.</p><button type="button" class="rhythm-start">BEGIN INSPECTION</button></div></div>
        ${helpers.cheatPanelTemplate()}
      </section>`;

    const keyToLane = Object.fromEntries((state.lanes || []).map((lane) => [String(lane.key).toLowerCase(), lane.id]));
    const shell = document.querySelector(".polyrhythm-customs-captcha");
    shell.addEventListener("keydown", (event) => {
      if (event.repeat) return;
      const laneId = keyToLane[String(event.key).toLowerCase()];
      if (!laneId) return;
      event.preventDefault();
      recordEvent(laneId, "down", "keyboard");
    });
    shell.addEventListener("keyup", (event) => {
      const laneId = keyToLane[String(event.key).toLowerCase()];
      if (!laneId) return;
      event.preventDefault();
      recordEvent(laneId, "up", "keyboard");
    });
    shell.setAttribute("tabindex", "0");
    document.querySelector(".rhythm-start").addEventListener("click", () => { shell.focus(); startTrial(helpers); });
    document.querySelector(".rhythm-replay").addEventListener("click", () => { shell.focus(); startTrial(helpers); });
    document.querySelector(".rhythm-certify-now").addEventListener("click", () => {
      if (model.phase === "performance") endPerformance(helpers);
    });
    document.querySelectorAll(".rhythm-pad").forEach((pad) => {
      pad.addEventListener("pointerdown", (event) => {
        event.preventDefault();
        pad.setPointerCapture?.(event.pointerId);
        recordEvent(String(pad.dataset.lane), "down", "pointer");
      });
      const release = (event) => {
        event.preventDefault();
        recordEvent(String(pad.dataset.lane), "up", "pointer");
      };
      pad.addEventListener("pointerup", release);
      pad.addEventListener("pointercancel", release);
    });
    helpers.installCheatPanel();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.polyrhythm_customs = {rootSelector: ".polyrhythm-customs-captcha", render};
})();
