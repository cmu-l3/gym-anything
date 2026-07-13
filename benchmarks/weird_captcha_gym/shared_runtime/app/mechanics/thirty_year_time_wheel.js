(() => {
  "use strict";

  const COMPONENTS = ["day", "month", "year"];
  const MONTHS = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
  const model = {
    state: null,
    current: null,
    target: null,
    events: [],
    rotations: {day: 0, month: 0, year: 0},
    drag: null,
    coast: null,
    coastTimer: null,
    coverage: new Set(),
    coastDetents: 0,
    qualifyingBrakes: 0,
    busy: false,
    terminal: false,
    helpers: null,
  };

  function clean(value) {
    return String(value == null ? "" : value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  }

  const cloneDate = (date) => ({year: Number(date.year), month: Number(date.month), day: Number(date.day)});
  const sameDate = (first, second) => first.year === second.year && first.month === second.month && first.day === second.day;

  function daysInMonth(year, month) {
    return new Date(Date.UTC(year, month, 0)).getUTCDate();
  }

  function stepDate(date, component, direction) {
    const minimum = Number(model.state.year_range.minimum);
    const maximum = Number(model.state.year_range.maximum);
    if (component === "day") {
      const length = daysInMonth(date.year, date.month);
      return {...date, day: ((date.day - 1 + direction) % length + length) % length + 1};
    }
    if (component === "month") {
      const ordinal = Math.max(minimum * 12, Math.min(maximum * 12 + 11, date.year * 12 + date.month - 1 + direction));
      const year = Math.floor(ordinal / 12);
      const month = (ordinal % 12) + 1;
      return {year, month, day: Math.min(date.day, daysInMonth(year, month))};
    }
    if (component === "year") {
      const year = Math.max(minimum, Math.min(maximum, date.year + direction));
      return {year, month: date.month, day: Math.min(date.day, daysInMonth(year, date.month))};
    }
    return date;
  }

  function dateCode(date) {
    return `${String(date.year).padStart(4, "0")}-${String(date.month).padStart(2, "0")}-${String(date.day).padStart(2, "0")}`;
  }

  function dateDisplay(date) {
    return `${String(date.day).padStart(2, "0")} ${MONTHS[date.month - 1]} ${date.year}`;
  }

  function record(type, details = {}) {
    const event = {
      sequence: model.events.length + 1,
      type,
      ...details,
      date_after: cloneDate(model.current),
    };
    model.events.push(event);
    return event;
  }

  function normalAngle(delta) {
    while (delta > Math.PI) delta -= Math.PI * 2;
    while (delta < -Math.PI) delta += Math.PI * 2;
    return delta;
  }

  function pointerAngle(event, rect) {
    return Math.atan2(event.clientY - (rect.top + rect.height / 2), event.clientX - (rect.left + rect.width / 2));
  }

  function ringForPointer(event, rect) {
    const dx = event.clientX - (rect.left + rect.width / 2);
    const dy = event.clientY - (rect.top + rect.height / 2);
    const radius = Math.hypot(dx, dy);
    if (radius >= 154 && radius <= 218) return "day";
    if (radius >= 105 && radius < 154) return "month";
    if (radius >= 55 && radius < 105) return "year";
    return null;
  }

  function ringMarkup(component, count, labeler) {
    return Array.from({length: count}, (_, index) => {
      const angle = (index / count) * 360;
      return `<i style="--tick-angle:${angle}deg"><b>${clean(labeler(index))}</b></i>`;
    }).join("");
  }

  function recentMarkup() {
    const relevant = model.events.filter((event) => ["detent", "brake", "lock"].includes(event.type)).slice(-7).reverse();
    if (!relevant.length) return '<li><b>000</b><span>CHRONOMETER AT REST</span><i>—</i></li>';
    return relevant.map((event) => {
      let label = event.type.toUpperCase();
      let detail = "—";
      if (event.type === "detent") {
        label = `${event.source === "coast" ? "COAST" : "HAND"} / ${event.component.toUpperCase()}`;
        detail = event.direction > 0 ? "+1" : "−1";
      } else if (event.type === "brake") {
        label = event.effective ? `BRAKE / ${String(event.component).toUpperCase()}` : "BRAKE / IDLE";
        detail = event.effective ? `STOP ${event.remaining_before}` : "0";
      } else if (event.type === "lock") detail = "LOCK";
      return `<li><b>${String(event.sequence).padStart(3, "0")}</b><span>${label}</span><i>${detail}</i></li>`;
    }).join("");
  }

  function paintRings() {
    COMPONENTS.forEach((component) => {
      const node = document.querySelector(`.time-ring[data-component="${component}"]`);
      if (!node) return;
      const residual = model.drag?.component === component ? model.drag.accumulator * 180 / Math.PI : 0;
      node.style.transform = `rotate(${model.rotations[component] + residual}deg)`;
    });
  }

  function updatePanels() {
    const current = document.getElementById("time-current-date");
    const currentCode = document.getElementById("time-current-code");
    const monthLength = document.getElementById("time-month-length");
    const tape = document.getElementById("time-tape");
    const momentum = document.getElementById("time-momentum");
    const brake = document.getElementById("time-brake");
    const lock = document.getElementById("time-lock");
    if (current) current.textContent = dateDisplay(model.current);
    if (currentCode) currentCode.textContent = dateCode(model.current);
    if (monthLength) monthLength.textContent = `${daysInMonth(model.current.year, model.current.month)} DAYS`;
    if (tape) tape.innerHTML = recentMarkup();
    if (momentum) {
      momentum.dataset.active = model.coast ? "true" : "false";
      momentum.innerHTML = model.coast
        ? `<b>${model.coast.component.toUpperCase()}</b><span>${model.coast.direction > 0 ? "CLOCKWISE" : "COUNTER"}</span><i>${model.coast.remaining} DETENTS</i>`
        : "<b>REST</b><span>NO MOMENTUM</span><i>0 DETENTS</i>";
    }
    if (brake) brake.classList.toggle("is-live", Boolean(model.coast));
    COMPONENTS.forEach((component) => {
      const lamp = document.querySelector(`[data-ring-proof="${component}"]`);
      lamp?.classList.toggle("is-lit", model.coverage.has(component));
    });
    document.querySelector('[data-proof="coast"]')?.classList.toggle("is-lit", model.coastDetents > 0);
    document.querySelector('[data-proof="brake"]')?.classList.toggle("is-lit", model.qualifyingBrakes > 0);
    const ready = sameDate(model.current, model.target)
      && model.coverage.size === 3
      && model.coastDetents > 0
      && model.qualifyingBrakes > 0
      && !model.coast;
    if (lock) lock.classList.toggle("is-ready", ready);
    paintRings();
  }

  function applyDetent(component, direction, source) {
    model.current = stepDate(model.current, component, direction);
    model.rotations[component] += direction * Number(model.state.detent_degrees || 12);
    if (source === "drag") model.coverage.add(component);
    if (source === "coast") model.coastDetents += 1;
    record("detent", {source, component, direction});
    updatePanels();
    const dial = document.querySelector(".time-wheel-dial");
    dial?.classList.remove("is-ticking");
    void dial?.offsetWidth;
    dial?.classList.add("is-ticking");
  }

  function stopCoastTimer() {
    if (model.coastTimer) window.clearInterval(model.coastTimer);
    model.coastTimer = null;
  }

  function startInertia(component, direction, velocity) {
    const roundedVelocity = Math.round(velocity * 1000) / 1000;
    const maximum = Number(model.state.inertia.maximum_detents || 10);
    const budget = Math.max(2, Math.min(maximum, Math.round(Math.abs(roundedVelocity) * 1.3)));
    model.coast = {component, direction, remaining: budget, applied: 0};
    record("inertia_start", {component, direction, velocity_rad_s: roundedVelocity, budget});
    updatePanels();
    model.helpers.setReadout(`${component.toUpperCase()} RING COASTING · CATCH IT`, "pending");
    stopCoastTimer();
    model.coastTimer = window.setInterval(() => {
      if (!model.coast || model.terminal) {
        stopCoastTimer();
        return;
      }
      const active = model.coast;
      applyDetent(active.component, active.direction, "coast");
      active.remaining -= 1;
      active.applied += 1;
      updatePanels();
      if (active.remaining <= 0) {
        record("inertia_stop", {component: active.component, reason: "friction"});
        model.coast = null;
        stopCoastTimer();
        updatePanels();
        model.helpers.setReadout("FRICTION STOP · MOMENTUM SPENT", "idle");
      }
    }, Number(model.state.inertia.tick_ms || 90));
  }

  function beginDrag(event) {
    if (model.busy || model.terminal || model.coast || model.drag) return;
    document.querySelector(".time-verdict-fail")?.remove();
    document.querySelector(".time-wheel-captcha")?.classList.remove("is-fresh-fail");
    const dial = event.currentTarget;
    const rect = dial.getBoundingClientRect();
    const component = ringForPointer(event, rect);
    if (!component) {
      model.helpers.setReadout("GRAB ONE OF THE THREE BRASS RINGS", "error");
      return;
    }
    event.preventDefault();
    dial.setPointerCapture(event.pointerId);
    model.drag = {
      pointerId: event.pointerId,
      component,
      lastAngle: pointerAngle(event, rect),
      lastTime: performance.now(),
      accumulator: 0,
      detents: 0,
      lastDirection: 0,
      velocities: [],
    };
    record("drag_start", {component});
    dial.dataset.dragging = component;
    model.helpers.setReadout(`${component.toUpperCase()} RING GRIPPED`, "idle");
    updatePanels();
  }

  function moveDrag(event) {
    if (!model.drag || event.pointerId !== model.drag.pointerId) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const now = performance.now();
    const angle = pointerAngle(event, rect);
    const delta = normalAngle(angle - model.drag.lastAngle);
    const elapsed = Math.max(1, now - model.drag.lastTime);
    model.drag.lastAngle = angle;
    model.drag.lastTime = now;
    if (Math.abs(delta) > 1.1) return;
    model.drag.accumulator += delta;
    model.drag.velocities.push({value: delta / (elapsed / 1000), at: now});
    model.drag.velocities = model.drag.velocities.filter((sample) => now - sample.at <= 180).slice(-8);
    const detent = Number(model.state.detent_degrees || 12) * Math.PI / 180;
    while (Math.abs(model.drag.accumulator) >= detent) {
      const direction = model.drag.accumulator > 0 ? 1 : -1;
      model.drag.accumulator -= direction * detent;
      model.drag.detents += 1;
      model.drag.lastDirection = direction;
      applyDetent(model.drag.component, direction, "drag");
    }
    paintRings();
  }

  function endDrag(event) {
    if (!model.drag || event.pointerId !== model.drag.pointerId) return;
    const drag = model.drag;
    event.currentTarget.releasePointerCapture?.(event.pointerId);
    event.currentTarget.dataset.dragging = "";
    model.drag = null;
    record("drag_end", {component: drag.component, drag_detents: drag.detents});
    paintRings();
    const recent = drag.velocities.filter((sample) => performance.now() - sample.at <= 180);
    const average = recent.length ? recent.reduce((sum, sample) => sum + sample.value, 0) / recent.length : 0;
    const threshold = Number(model.state.inertia.minimum_velocity_rad_s || 0.8);
    if (drag.detents > 0 && drag.lastDirection && Math.abs(average) >= threshold) {
      const velocity = drag.lastDirection * Math.abs(average);
      startInertia(drag.component, drag.lastDirection, velocity);
    } else {
      updatePanels();
      model.helpers.setReadout(`${drag.component.toUpperCase()} RING SET · NO COAST`, "idle");
    }
  }

  function brakeMomentum() {
    if (model.busy || model.terminal) return;
    if (model.coast) {
      const stopped = model.coast;
      stopCoastTimer();
      record("brake", {
        effective: true,
        component: stopped.component,
        remaining_before: stopped.remaining,
      });
      if (stopped.applied >= 1) model.qualifyingBrakes += 1;
      model.coast = null;
      updatePanels();
      model.helpers.setReadout(`BRAKE CAUGHT ${stopped.component.toUpperCase()} · ${stopped.remaining} DETENTS SAVED`, "passed");
    } else {
      record("brake", {effective: false, component: null, remaining_before: 0});
      updatePanels();
      model.helpers.setReadout("BRAKE PRESSED · RINGS ALREADY STILL", "idle");
    }
  }

  function resetWheel() {
    if (model.busy) return;
    stopCoastTimer();
    model.current = cloneDate(model.state.initial_date);
    model.target = cloneDate(model.state.target_date);
    model.events = [];
    model.rotations = {
      day: Number(model.state.ring_offsets.day || 0),
      month: Number(model.state.ring_offsets.month || 0),
      year: Number(model.state.ring_offsets.year || 0),
    };
    model.drag = null;
    model.coast = null;
    model.coverage = new Set();
    model.coastDetents = 0;
    model.qualifyingBrakes = 0;
    model.terminal = false;
    document.querySelector(".time-wheel-captcha")?.classList.remove("is-pass");
    document.querySelectorAll(".time-verdict").forEach((node) => node.remove());
    updatePanels();
    model.helpers.setReadout("CHRONOMETER REWOUND · PROOF CLEARED", "idle");
  }

  async function lockWheel() {
    if (model.busy || model.terminal) return;
    if (model.coast || model.drag) {
      model.helpers.setReadout("BRAKE ALL MOTION BEFORE LOCK", "error");
      return;
    }
    record("lock");
    model.busy = true;
    model.terminal = true;
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    model.helpers.setReadout("CHECKING ALMANAC TRANSCRIPT…", "pending");
    const payload = {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      final_date: cloneDate(model.current),
      completed: sameDate(model.current, model.target),
    };
    try {
      const response = await fetch("/result", {
        method: "POST",
        headers: {"content-type": "application/json"},
        body: JSON.stringify(payload),
      });
      const outcome = await response.json();
      if (outcome.passed === true) {
        document.querySelector(".time-wheel-captcha")?.classList.add("is-pass");
        document.querySelector(".time-wheel-captcha")?.insertAdjacentHTML("beforeend", '<div class="time-verdict time-verdict-pass"><small>CALENDAR SYNCHRONIZED</small><strong>PASS</strong></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".time-wheel-captcha");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", '<div class="time-verdict time-verdict-fail"><small>LOCK REJECTED · FRESH CALENDAR</small><strong>FAIL</strong></div>');
        model.helpers.setReadout("FAIL · CHRONOMETER REISSUED", "error");
        window.setTimeout(() => document.querySelector(".time-verdict-fail")?.remove(), 1700);
      } else {
        model.events.pop();
        model.busy = false;
        model.terminal = false;
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
        model.helpers.setReadout("FAIL · NO ALMANAC GRADE", "error");
      }
    } catch (_error) {
      model.events.pop();
      model.busy = false;
      model.terminal = false;
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      model.helpers.setReadout("FAIL · CHRONOMETER OFFLINE", "error");
    }
  }

  async function render(state, helpers) {
    stopCoastTimer();
    document.body.dataset.mechanic = "thirty-year-time-wheel";
    document.body.dataset.timePalette = String(state.palette || "orrery");
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    Object.assign(model, {
      state,
      current: cloneDate(state.initial_date),
      target: cloneDate(state.target_date),
      events: [],
      rotations: {
        day: Number(state.ring_offsets.day || 0),
        month: Number(state.ring_offsets.month || 0),
        year: Number(state.ring_offsets.year || 0),
      },
      drag: null,
      coast: null,
      coastTimer: null,
      coverage: new Set(),
      coastDetents: 0,
      qualifyingBrakes: 0,
      busy: false,
      terminal: false,
      helpers,
    });
    helpers.app.innerHTML = `
      <section class="time-wheel-captcha" data-challenge-id="${clean(state.challenge_id)}">
        <header class="time-head">
          <div class="time-title"><span>PERPETUAL ALMANAC / 30-YEAR CLEARANCE</span><h1>${clean(state.prompt)}</h1></div>
          <div class="time-target-plaque"><small>TARGET CALENDAR</small><strong>${dateDisplay(model.target)}</strong><i>${dateCode(model.target)}</i></div>
        </header>
        <main class="time-workbench">
          <section class="time-dial-stage">
            <div class="time-dial-caption"><span>DRAG BRASS · RELEASE TO COAST</span><b>${state.year_range.minimum}—${state.year_range.maximum}</b></div>
            <div class="time-wheel-dial" id="time-wheel-dial" aria-label="three concentric calendar rings">
              <div class="time-ring time-ring-day" data-component="day">${ringMarkup("day", 31, (index) => index % 5 === 0 ? String(index + 1) : "")}</div>
              <div class="time-ring time-ring-month" data-component="month">${ringMarkup("month", 12, (index) => MONTHS[index])}</div>
              <div class="time-ring time-ring-year" data-component="year">${ringMarkup("year", 30, (index) => index % 5 === 0 ? String(state.year_range.minimum + index).slice(-2) : "")}</div>
              <div class="time-date-aperture"><small>LOCK DATE</small><strong id="time-current-date">${dateDisplay(model.current)}</strong><i id="time-current-code">${dateCode(model.current)}</i><em id="time-month-length">${daysInMonth(model.current.year, model.current.month)} DAYS</em></div>
              <div class="time-index-needle"></div>
            </div>
            <div class="time-ring-legend"><span><i></i>OUTER / DAY</span><span><i></i>MIDDLE / MONTH</span><span><i></i>INNER / YEAR</span></div>
          </section>
          <aside class="time-console">
            <div class="time-console-title"><span>MOMENTUM ESCAPEMENT</span><i>MECHANICAL</i></div>
            <div class="time-momentum" id="time-momentum" data-active="false"><b>REST</b><span>NO MOMENTUM</span><i>0 DETENTS</i></div>
            <button type="button" class="time-brake" id="time-brake"><span>Ⅱ</span><b>BRAKE</b><small>CATCH THE COASTING RING</small></button>
            <div class="time-proof-grid">
              <span data-ring-proof="day"><i></i>DAY HAND</span>
              <span data-ring-proof="month"><i></i>MONTH HAND</span>
              <span data-ring-proof="year"><i></i>YEAR HAND</span>
              <span data-proof="coast"><i></i>COAST SEEN</span>
              <span data-proof="brake"><i></i>BRAKE CAUGHT</span>
            </div>
            <div class="time-rule-card"><b>CALENDAR LAW</b><p>Month lengths are real. Leap years count. Month and year changes clamp impossible days.</p></div>
            <ol class="time-tape" id="time-tape">${recentMarkup()}</ol>
          </aside>
        </main>
        <footer class="time-foot">
          <button type="button" class="time-reset" id="time-reset">↺ REWIND ALL</button>
          <div class="readout" data-status="idle">THREE RINGS · ONE COAST · ONE BRAKE</div>
          <button type="button" class="time-lock" id="time-lock">${clean(state.submit_label || "LOCK CHRONOMETER")}</button>
        </footer>
        ${helpers.cheatPanelTemplate()}
      </section>`;
    const dial = document.getElementById("time-wheel-dial");
    dial?.addEventListener("pointerdown", beginDrag);
    dial?.addEventListener("pointermove", moveDrag);
    dial?.addEventListener("pointerup", endDrag);
    dial?.addEventListener("pointercancel", endDrag);
    document.getElementById("time-brake")?.addEventListener("click", brakeMomentum);
    document.getElementById("time-reset")?.addEventListener("click", resetWheel);
    document.getElementById("time-lock")?.addEventListener("click", lockWheel);
    updatePanels();
    helpers.installCheatPanel();
    window.thirtyYearTimeWheelModel = model;
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.thirty_year_time_wheel = {
    rootSelector: ".time-wheel-captcha",
    render,
  };
})();
