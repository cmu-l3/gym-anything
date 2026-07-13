(() => {
  "use strict";

  let model = null;
  let activeCleanup = null;

  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;");
  const round = (value) => Math.round(Number(value) * 1000) / 1000;

  function wrapPhase(value) {
    const steps = Number(model.state.qualification.phase_steps);
    return ((Number(value) % steps) + steps) % steps;
  }

  function circularDistance(first, second) {
    const steps = Number(model.state.qualification.phase_steps);
    const direct = Math.abs(wrapPhase(first) - wrapPhase(second));
    return Math.min(direct, steps - direct);
  }

  function nowMs() {
    return Math.round(performance.now() - model.startedAt);
  }

  function record(type, details = {}) {
    const event = {seq: model.events.length + 1, t_ms: nowMs(), type, ...details};
    model.events.push(event);
    return event;
  }

  function selectedLine() {
    return model.state.lines.find((line) => line.id === model.selectedLineId) || null;
  }

  function targetPhase(line, elapsedMs) {
    const drift = Number(line.drift_milli_steps_per_second) * Number(elapsedMs) / 1_000_000;
    return wrapPhase(-Number(line.phase_offset_steps) - drift);
  }

  function alignment(line, phase, skew, elapsedMs) {
    if (!line) return {residual: 9, locked: false, phaseError: 9, skewError: 9};
    const q = model.state.qualification;
    const phaseError = circularDistance(phase, targetPhase(line, elapsedMs));
    const skewError = Math.abs(Number(skew) + Number(line.skew_offset_steps));
    const phaseScale = Number(q.phase_tolerance_milli_steps) / 1000;
    const skewScale = Number(q.skew_tolerance_milli_steps) / 1000;
    const distortion = Number(line.distortion_milli) / 1000;
    const residual = Math.sqrt(
      (phaseError / phaseScale) ** 2
      + (skewError / skewScale) ** 2
      + distortion ** 2
    );
    return {residual, locked: residual <= 1, phaseError, skewError};
  }

  function trialElapsed() {
    return model.trial ? Math.max(0, performance.now() - model.trial.performanceStart) : 0;
  }

  function drawWave(context, values, color, width, shadow) {
    context.save();
    context.strokeStyle = color;
    context.lineWidth = width;
    context.shadowColor = color;
    context.shadowBlur = shadow;
    context.beginPath();
    values.forEach((value, index) => {
      const x = 28 + index / (values.length - 1) * 724;
      const y = 145 - value * 69;
      if (index) context.lineTo(x, y); else context.moveTo(x, y);
    });
    context.stroke();
    context.restore();
  }

  function drawScope(timestamp) {
    if (!model?.canvas) return;
    const context = model.context;
    const width = model.canvas.width;
    const height = model.canvas.height;
    context.clearRect(0, 0, width, height);
    const gradient = context.createRadialGradient(width * .5, height * .45, 20, width * .5, height * .45, width * .65);
    gradient.addColorStop(0, "#0c2927");
    gradient.addColorStop(1, "#03100f");
    context.fillStyle = gradient;
    context.fillRect(0, 0, width, height);
    context.strokeStyle = "rgba(118, 255, 224, .09)";
    context.lineWidth = 1;
    for (let x = 28; x <= 752; x += 45.25) { context.beginPath(); context.moveTo(x, 18); context.lineTo(x, 272); context.stroke(); }
    for (let y = 25; y <= 265; y += 30) { context.beginPath(); context.moveTo(18, y); context.lineTo(762, y); context.stroke(); }
    context.strokeStyle = "rgba(118, 255, 224, .28)";
    context.beginPath(); context.moveTo(18, 145); context.lineTo(762, 145); context.stroke();

    const line = selectedLine();
    const harmonic = Number(model.state.waveform.base_harmonic_milli) / 1000;
    const twist = Number(model.state.waveform.reference_twist_milli_radians) / 1000;
    const count = 150;
    const reference = [];
    const candidate = [];
    const elapsed = trialElapsed();
    const steps = Number(model.state.qualification.phase_steps);
    const drift = line ? Number(line.drift_milli_steps_per_second) * elapsed / 1_000_000 : 0;
    const effectivePhase = line ? (Number(line.phase_offset_steps) + Number(model.phase) + drift) / steps : 0;
    const effectiveSkew = line ? (Number(line.skew_offset_steps) + Number(model.skew)) * .22 : 0;
    const distortion = line ? Number(line.distortion_milli) / 1000 * Number(model.state.waveform.distortion_gain_milli) / 1000 : 0;
    for (let index = 0; index < count; index += 1) {
      const u = index / (count - 1) * 2.2;
      reference.push(Math.sin(Math.PI * 2 * u) * .72 + Math.sin(Math.PI * 4 * u + twist) * harmonic);
      if (line) {
        candidate.push(
          Math.sin(Math.PI * 2 * (u + effectivePhase)) * .72
          + Math.sin(Math.PI * 4 * (u + effectivePhase) + twist + effectiveSkew) * harmonic
          + Math.sin(Math.PI * 6 * u + Number(line.waveform_seed) * .013) * distortion
        );
      }
    }
    drawWave(context, reference, "#70f6dc", 3, 10);
    if (line) drawWave(context, candidate, "#ffb44f", 2.4, 8);

    const scanX = 28 + ((timestamp / 11) % 724);
    context.fillStyle = "rgba(255,255,255,.055)";
    context.fillRect(scanX, 18, 2, 254);
    context.fillStyle = "rgba(112,246,220,.72)";
    context.font = "700 10px Courier New";
    context.fillText("REFERENCE", 31, 35);
    context.fillStyle = "rgba(255,180,79,.82)";
    context.fillText(line ? `PATCH ${String(Number(line.slot) + 1).padStart(2, "0")}` : "NO LINE PATCHED", 31, 52);
    model.raf = requestAnimationFrame(drawScope);
  }

  function clearFreshFailure() {
    const root = document.querySelector(".wrong-number-captcha");
    root?.removeAttribute("data-fresh-failure");
    root?.querySelector(".wrong-fresh-stamp")?.remove();
  }

  function updateInterface() {
    if (!model) return;
    const line = selectedLine();
    const elapsed = trialElapsed();
    const result = alignment(line, model.phase, model.skew, elapsed);
    document.querySelectorAll(".wrong-line").forEach((button) => {
      button.dataset.selected = String(button.dataset.lineId === model.selectedLineId);
      button.disabled = Boolean(model.trial || model.submitting || model.terminal);
    });
    const phaseValue = document.getElementById("wrong-phase-value");
    const skewValue = document.getElementById("wrong-skew-value");
    if (phaseValue) phaseValue.textContent = String(model.phase).padStart(2, "0");
    if (skewValue) skewValue.textContent = `${model.skew > 0 ? "+" : ""}${model.skew}`;
    const meter = document.querySelector(".wrong-lock-meter i");
    if (meter) meter.style.width = `${Math.max(0, Math.min(100, (2.5 - result.residual) / 2.5 * 100))}%`;
    const status = document.querySelector(".wrong-lock-state");
    if (status) {
      status.dataset.locked = String(result.locked);
      status.textContent = !line ? "SELECT A JACK" : result.locked ? (model.trial ? "TRACKING DRIFT" : "TRACES COHERENT") : (model.trial ? "CORRECT NOW" : "TUNE THE OVERLAY");
    }
    const test = document.getElementById("wrong-test");
    if (test) {
      test.disabled = !line || Boolean(model.trial || model.submitting || model.terminal);
      test.textContent = model.trial ? "LOCK TEST RUNNING…" : model.state.submit_label;
    }
    const progress = document.querySelector(".wrong-trial-progress i");
    if (progress) progress.style.width = `${model.trial ? Math.min(100, elapsed / Number(model.state.qualification.trial_ms) * 100) : 0}%`;
    const attempts = document.querySelector(".wrong-attempt-count b");
    if (attempts) attempts.textContent = String(model.trialCount).padStart(2, "0");
  }

  function selectLine(lineId) {
    if (!model || model.trial || model.submitting || model.terminal || model.selectedLineId === lineId) return;
    clearFreshFailure();
    model.selectedLineId = lineId;
    record("line_select", {line_id: lineId});
    model.helpers.setReadout(`PATCH ${String(Number(selectedLine().slot) + 1).padStart(2, "0")} LIVE · ALIGN AMBER TO CYAN`, "idle");
    updateInterface();
  }

  function tune(control, value) {
    if (!model || model.submitting || model.terminal) return;
    clearFreshFailure();
    const parsed = Number(value);
    if (control === "phase" && parsed !== model.phase) model.phase = parsed;
    else if (control === "skew" && parsed !== model.skew) model.skew = parsed;
    else return;
    record("tune", {control, value: parsed});
    model.helpers.setReadout("TUNING LIVE OVERLAY", "idle");
    updateInterface();
  }

  function sampleTrial() {
    if (!model?.trial) return;
    const trial = model.trial;
    const elapsed = Math.round(performance.now() - trial.performanceStart);
    const line = selectedLine();
    const result = alignment(line, model.phase, model.skew, elapsed);
    record("trial_sample", {
      line_id: line.id,
      elapsed_ms: elapsed,
      phase: model.phase,
      skew: model.skew,
      locked: result.locked,
      residual_milli: Math.round(result.residual * 1000),
    });
    trial.samples += 1;
    if (result.locked) trial.lockedSamples += 1;
    trial.lockHistory.push(Boolean(result.locked));
    while (trial.lockHistory.length > Number(model.state.qualification.final_window_samples)) trial.lockHistory.shift();
    updateInterface();
    if (elapsed >= Number(model.state.qualification.trial_ms)) {
      const q = model.state.qualification;
      const finalLocked = trial.lockHistory.filter(Boolean).length;
      endTrial(trial.lockedSamples >= Number(q.minimum_lock_samples) && finalLocked >= Number(q.minimum_final_lock_samples));
    }
  }

  function startTrial() {
    const line = selectedLine();
    if (!model || !line || model.trial || model.submitting || model.terminal) return;
    clearFreshFailure();
    const started = record("trial_start", {line_id: line.id, phase: model.phase, skew: model.skew});
    model.trialCount += 1;
    model.trial = {
      startSeq: started.seq,
      performanceStart: performance.now(),
      samples: 0,
      lockedSamples: 0,
      lockHistory: [],
      timer: 0,
    };
    model.helpers.setReadout("LIVE LOCK TEST · KEEP THE TRACES COHERENT", "pending");
    updateInterface();
    sampleTrial();
    if (model.trial) model.trial.timer = window.setInterval(sampleTrial, Number(model.state.qualification.sample_ms));
  }

  function endTrial(success) {
    if (!model?.trial) return;
    const trial = model.trial;
    window.clearInterval(trial.timer);
    const line = selectedLine();
    record("trial_end", {
      line_id: line.id,
      passed_local: Boolean(success),
      sample_count: trial.samples,
      locked_sample_count: trial.lockedSamples,
      final_window_locked_samples: trial.lockHistory.filter(Boolean).length,
    });
    model.trial = null;
    if (success) {
      model.successfulTrialStartSeq = trial.startSeq;
      model.helpers.setReadout("CARRIER LOCKED · AUTHENTICATING…", "pending");
      submit(true);
    } else {
      model.helpers.setReadout("NO SUSTAINED LOCK · RETUNE OR TRY ANOTHER JACK", "error");
      updateInterface();
    }
  }

  async function submit(completed) {
    if (!model || model.submitting || model.terminal) return;
    model.submitting = true;
    const helpers = model.helpers;
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      completed: Boolean(completed),
      selected_line_id: model.selectedLineId,
      final_phase: model.phase,
      final_skew: model.skew,
      successful_trial_start_seq: model.successfulTrialStartSeq,
      trial_count: model.trialCount,
    };
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload)});
      const outcome = await response.json();
      if (outcome.passed === true) {
        model.terminal = true;
        document.querySelector(".wrong-number-captcha")?.setAttribute("data-terminal", "pass");
        document.querySelector(".wrong-number-captcha")?.insertAdjacentHTML("beforeend", '<div class="wrong-terminal"><span>AUTHORIZED CARRIER</span><strong>PASS</strong><i>PHASE LOCK HELD</i></div>');
        helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await render(outcome.state, helpers, {freshFailure: true});
        helpers.setReadout("FAIL · FRESH SWITCHBOARD ISSUED", "error");
      } else {
        model.submitting = false;
        helpers.setReadout("AUTHENTICATION UNAVAILABLE", "error");
        updateInterface();
      }
    } catch (_error) {
      model.submitting = false;
      helpers.setReadout("SWITCHBOARD LINK LOST", "error");
      updateInterface();
    }
  }

  async function render(state, helpers, options = {}) {
    if (activeCleanup) activeCleanup();
    document.body.dataset.mechanic = "wrong-number";
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    model = {
      state, helpers, startedAt: performance.now(), events: [], selectedLineId: null,
      phase: 0, skew: 0, trial: null, trialCount: 0,
      successfulTrialStartSeq: null, submitting: false, terminal: false,
      canvas: null, context: null, raf: 0,
    };
    window.wrongNumberPhaseLockModel = model;
    helpers.app.innerHTML = `
      <section class="wrong-number-captcha" data-challenge-id="${clean(state.challenge_id)}" ${options.freshFailure ? 'data-fresh-failure="true"' : ""}>
        ${options.freshFailure ? '<div class="wrong-fresh-stamp"><b>FAIL</b><span>FRESH CARRIERS PATCHED</span></div>' : ""}
        <header class="wrong-number-head">
          <div><span>ANALOG SWITCHBOARD / NIGHT DESK</span><h1>${clean(state.prompt)}</h1></div>
          <div class="wrong-head-mark"><i></i><b>PHASE<br>LOCK</b></div>
        </header>
        <main class="wrong-number-main">
          <aside class="wrong-line-rack">
            <header><span>INCOMING JACKS</span><b>${state.lines.length} LIVE</b></header>
            <div class="wrong-lines">${state.lines.map((line) => `<button type="button" class="wrong-line tone-${clean(line.tone)}" data-line-id="${clean(line.id)}" data-selected="false"><i></i><span>PATCH ${String(Number(line.slot) + 1).padStart(2, "0")}</span><b><em></em><em></em><em></em><em></em></b></button>`).join("")}</div>
            <p>Select a jack. Tune amber onto cyan, then keep correcting phase drift for the entire live test.</p>
          </aside>
          <section class="wrong-scope-bay">
            <div class="wrong-scope-shell"><canvas id="wrong-scope" width="780" height="290" aria-label="live reference and caller oscilloscope"></canvas><div class="wrong-scope-glass"></div></div>
            <div class="wrong-tuning-desk">
              <label><span>PHASE</span><input id="wrong-phase" type="range" min="0" max="${Number(state.qualification.phase_steps) - 1}" step="1" value="0"><b id="wrong-phase-value">00</b></label>
              <label><span>SHAPE</span><input id="wrong-skew" type="range" min="${Number(state.qualification.skew_min)}" max="${Number(state.qualification.skew_max)}" step="1" value="0"><b id="wrong-skew-value">0</b></label>
              <div class="wrong-lock-panel"><span class="wrong-lock-state" data-locked="false">SELECT A JACK</span><em class="wrong-lock-meter"><i></i></em><small>CYAN = REFERENCE · AMBER = PATCHED LINE</small></div>
              <button type="button" id="wrong-test" disabled>${clean(state.submit_label)}</button>
            </div>
            <div class="wrong-trial-strip"><span class="wrong-attempt-count">TESTS <b>00</b></span><em class="wrong-trial-progress"><i></i></em><b>THE CARRIER DRIFTS WHILE TESTING</b></div>
          </section>
        </main>
        <footer class="wrong-number-foot"><div class="readout" data-status="idle">SELECT AN INCOMING JACK</div><button type="button" id="wrong-abandon">REISSUE SWITCHBOARD</button></footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    model.canvas = document.getElementById("wrong-scope");
    model.context = model.canvas.getContext("2d");
    document.querySelectorAll(".wrong-line").forEach((button) => button.addEventListener("click", () => selectLine(button.dataset.lineId)));
    document.getElementById("wrong-phase")?.addEventListener("input", (event) => tune("phase", event.target.value));
    document.getElementById("wrong-skew")?.addEventListener("input", (event) => tune("skew", event.target.value));
    document.getElementById("wrong-test")?.addEventListener("click", startTrial);
    document.getElementById("wrong-abandon")?.addEventListener("click", () => submit(false));
    helpers.installCheatPanel();
    updateInterface();
    model.raf = requestAnimationFrame(drawScope);
    activeCleanup = () => {
      if (model?.trial?.timer) window.clearInterval(model.trial.timer);
      if (model?.raf) cancelAnimationFrame(model.raf);
    };
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.wrong_number = {rootSelector: ".wrong-number-captcha", render};
})();
