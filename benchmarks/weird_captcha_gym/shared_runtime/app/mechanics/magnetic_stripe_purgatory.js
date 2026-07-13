(() => {
  "use strict";

  // Public state carries only opaque profile tokens. These client thresholds
  // exist for immediate feedback; the server independently replays hidden
  // calibration values and ignores every client feedback label.
  const PROFILE_LIMITS = {
    quartz: {minimum_ms: 440, maximum_ms: 700, straightness_px: 15},
    pendulum: {minimum_ms: 700, maximum_ms: 1050, straightness_px: 17},
    glacier: {minimum_ms: 1050, maximum_ms: 1420, straightness_px: 19},
  };

  const model = {
    state: null,
    helpers: null,
    cardById: new Map(),
    readerById: new Map(),
    assignments: new Map(),
    cardLocations: {},
    readerCards: {},
    readerLocked: {},
    readerAttempts: {},
    readerFeedback: {},
    events: [],
    drag: null,
    swipe: null,
    invalidInsertions: 0,
    swipeAttempts: 0,
    resetCount: 0,
    auditCount: 0,
    busy: false,
    terminal: false,
  };

  const clean = (value) => String(value == null ? "" : value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
  const clone = (value) => JSON.parse(JSON.stringify(value));
  const clamp = (value, minimum, maximum) => Math.max(minimum, Math.min(maximum, value));

  function record(kind, details = {}) {
    const event = {sequence: model.events.length + 1, kind, ...details};
    model.events.push(event);
    return event;
  }

  function stagePoint(event) {
    const stage = document.getElementById("stripe-stage");
    const rect = stage.getBoundingClientRect();
    return [
      clamp(Math.round((event.clientX - rect.left) / rect.width * Number(model.state.stage.width)), 0, Number(model.state.stage.width)),
      clamp(Math.round((event.clientY - rect.top) / rect.height * Number(model.state.stage.height)), 0, Number(model.state.stage.height)),
    ];
  }

  function inside(point, rect) {
    return Number(rect.x) <= point[0] && point[0] <= Number(rect.x) + Number(rect.width)
      && Number(rect.y) <= point[1] && point[1] <= Number(rect.y) + Number(rect.height);
  }

  function readerAtSlot(point) {
    for (const reader of model.state.readers) {
      if (inside(point, reader.slot)) return String(reader.id);
    }
    return null;
  }

  function assignedReader(card) {
    return model.state.readers.find((reader) => reader.badge.code === card.badge.code)?.id || null;
  }

  function currentCardRect(cardId) {
    const card = model.cardById.get(cardId);
    const readerId = model.cardLocations[cardId];
    return readerId ? model.readerById.get(readerId).slot : card.initial_rect;
  }

  function percent(value, total) {
    return `${value / total * 100}%`;
  }

  function globalRectStyle(rect) {
    return `left:${percent(Number(rect.x), Number(model.state.stage.width))};top:${percent(Number(rect.y), Number(model.state.stage.height))};width:${percent(Number(rect.width), Number(model.state.stage.width))};height:${percent(Number(rect.height), Number(model.state.stage.height))}`;
  }

  function localRectStyle(rect, parent) {
    return `left:${percent(Number(rect.x) - Number(parent.x), Number(parent.width))};top:${percent(Number(rect.y) - Number(parent.y), Number(parent.height))};width:${percent(Number(rect.width), Number(parent.width))};height:${percent(Number(rect.height), Number(parent.height))}`;
  }

  function cardMarkup(card) {
    const rect = currentCardRect(String(card.id));
    const inserted = Boolean(model.cardLocations[card.id]);
    return `<article class="mag-card${inserted ? " is-inserted" : ""}" data-card-id="${clean(card.id)}" style="${globalRectStyle(rect)};--card-accent:${clean(card.badge.color)}">
      <span class="mag-card-stripe"></span><header><b>${clean(card.label)}</b><i>${clean(card.badge.symbol)} ${clean(card.badge.code)}</i></header><strong>${clean(card.account)}</strong><footer><span>${clean(card.holder)}</span><i>AUTHORIZED CALIBRATION</i></footer>
    </article>`;
  }

  function readerMarkup(reader) {
    const readerId = String(reader.id);
    const cardId = model.readerCards[readerId];
    const locked = model.readerLocked[readerId];
    const feedback = model.readerFeedback[readerId];
    const track = reader.track;
    const startX = track.direction === "ltr" ? Number(track.x_start) : Number(track.x_end);
    const handleStyle = `left:${percent(startX - Number(reader.rect.x), Number(reader.rect.width))};top:${percent(Number(track.y) - Number(reader.rect.y), Number(reader.rect.height))}`;
    const railRect = {x: Number(track.x_start), y: Number(track.y) - Number(track.lane_half_height), width: Number(track.x_end) - Number(track.x_start), height: Number(track.lane_half_height) * 2};
    const zones = reader.interference_zones.map((zone) => `<i class="stripe-static-zone" title="interference field" style="${localRectStyle(zone, reader.rect)}"></i>`).join("");
    return `<article class="stripe-reader${locked ? " is-locked" : ""}" data-reader-id="${clean(readerId)}" style="${globalRectStyle(reader.rect)};--reader-accent:${clean(reader.badge.color)}">
      <header><span><b>${clean(reader.label)}</b><i>${clean(reader.serial)}</i></span><strong>${clean(reader.badge.symbol)} ${clean(reader.badge.code)}</strong><em>${track.direction === "ltr" ? "SWIPE →" : "← SWIPE"}</em></header>
      <div class="stripe-slot${cardId ? " is-loaded" : ""}" style="${localRectStyle(reader.slot, reader.rect)}"><span>${cardId ? "CARD INSERTED" : "INSERT MATCHING CARD"}</span></div>
      <div class="stripe-rail" style="${localRectStyle(railRect, reader.rect)}"><i></i><span>${track.direction === "ltr" ? "START ▶" : "◀ START"}</span></div>${zones}
      ${cardId && !locked ? `<button type="button" class="stripe-handle" data-reader-id="${clean(readerId)}" data-card-id="${clean(cardId)}" style="${handleStyle}" aria-label="swipe ${clean(reader.label)}"><i></i></button>` : ""}
      <div class="stripe-feedback" data-feedback="${clean(feedback)}"><small>${model.readerAttempts[readerId]} ATTEMPT${model.readerAttempts[readerId] === 1 ? "" : "S"}</small><strong>${clean(feedback)}</strong></div>
      ${locked ? '<div class="stripe-lock"><span>✓</span><b>ACCEPTED</b></div>' : ""}
    </article>`;
  }

  function renderDesk() {
    const stage = document.getElementById("stripe-stage");
    if (!stage) return;
    stage.innerHTML = `<div class="stripe-rack"><span>UNPROCESSED CARDS</span><i>BADGE → READER</i></div>${model.state.readers.map(readerMarkup).join("")}${model.state.cards.map(cardMarkup).join("")}`;
    stage.querySelectorAll(".mag-card:not(.is-inserted)").forEach((card) => card.addEventListener("pointerdown", beginInsert));
    stage.querySelectorAll(".stripe-handle").forEach((handle) => handle.addEventListener("pointerdown", beginSwipe));
    updateSummary();
  }

  function beginInsert(event) {
    if (model.busy || model.terminal || model.drag || model.swipe) return;
    clearFreshFailure();
    event.preventDefault();
    const cardId = String(event.currentTarget.dataset.cardId);
    if (model.cardLocations[cardId]) return;
    const point = stagePoint(event);
    record("insert_down", {card_id: cardId, point, elapsed_ms: 0});
    model.drag = {pointerId: event.pointerId, cardId, startedAt: performance.now(), lastPoint: point, moves: 0};
    event.currentTarget.setPointerCapture?.(event.pointerId);
    event.currentTarget.classList.add("is-dragging");
    model.helpers.setReadout("CARD LIFTED · DROP INTO THE MATCHING BADGE SLOT", "pending");
  }

  function moveInsert(event) {
    if (!model.drag || event.pointerId !== model.drag.pointerId) return;
    const point = stagePoint(event);
    if (point[0] === model.drag.lastPoint[0] && point[1] === model.drag.lastPoint[1]) return;
    const elapsed = Math.max(0, Math.round(performance.now() - model.drag.startedAt));
    record("insert_move", {card_id: model.drag.cardId, point, elapsed_ms: elapsed});
    model.drag.lastPoint = point;
    model.drag.moves += 1;
    const card = model.cardById.get(model.drag.cardId);
    const node = document.querySelector(`.mag-card[data-card-id="${CSS.escape(model.drag.cardId)}"]`);
    if (node) {
      node.style.left = percent(point[0] - Number(card.initial_rect.width) / 2, Number(model.state.stage.width));
      node.style.top = percent(point[1] - Number(card.initial_rect.height) / 2, Number(model.state.stage.height));
    }
  }

  function endInsert(event) {
    if (!model.drag || event.pointerId !== model.drag.pointerId) return;
    const point = stagePoint(event);
    const duration = Math.max(Math.round(performance.now() - model.drag.startedAt), 0);
    const readerId = readerAtSlot(point);
    const cardId = model.drag.cardId;
    record("insert_up", {card_id: cardId, reader_id: readerId, point, duration_ms: duration, client_status: "IGNORED_BY_GRADER"});
    const card = model.cardById.get(cardId);
    const valid = readerId
      && assignedReader(card) === readerId
      && !model.readerCards[readerId]
      && model.drag.moves >= Number(model.state.requirements.minimum_insert_moves)
      && duration >= Number(model.state.requirements.minimum_insert_ms);
    if (valid) {
      model.cardLocations[cardId] = readerId;
      model.readerCards[readerId] = cardId;
      model.readerFeedback[readerId] = "READY TO SWIPE";
      model.helpers.setReadout("CARD SEATED · BEGIN AT THE ILLUMINATED ARROW", "passed");
    } else {
      model.invalidInsertions += 1;
      if (readerId) model.readerFeedback[readerId] = "WRONG CARD";
      model.helpers.setReadout(readerId ? "WRONG CARD · MATCH THE BADGE" : "BAD INSERT · CARD RETURNED TO RACK", "error");
    }
    model.drag = null;
    renderDesk();
  }

  function beginSwipe(event) {
    if (model.busy || model.terminal || model.drag || model.swipe) return;
    clearFreshFailure();
    event.preventDefault();
    const readerId = String(event.currentTarget.dataset.readerId);
    const cardId = String(event.currentTarget.dataset.cardId);
    const point = stagePoint(event);
    record("swipe_down", {reader_id: readerId, card_id: cardId, point, elapsed_ms: 0});
    model.swipe = {pointerId: event.pointerId, readerId, cardId, startedAt: performance.now(), lastPoint: point, points: [point]};
    event.currentTarget.setPointerCapture?.(event.pointerId);
    document.querySelector(`.stripe-reader[data-reader-id="${CSS.escape(readerId)}"]`)?.classList.add("is-swiping");
    model.helpers.setReadout("STRIPE LIVE · KEEP THE POINTER STRAIGHT AND MONOTONIC", "pending");
  }

  function moveSwipe(event) {
    if (!model.swipe || event.pointerId !== model.swipe.pointerId) return;
    const point = stagePoint(event);
    if (point[0] === model.swipe.lastPoint[0] && point[1] === model.swipe.lastPoint[1]) return;
    const elapsed = Math.max(0, Math.round(performance.now() - model.swipe.startedAt));
    record("swipe_move", {reader_id: model.swipe.readerId, card_id: model.swipe.cardId, point, elapsed_ms: elapsed});
    model.swipe.points.push(point);
    model.swipe.lastPoint = point;
    const reader = model.readerById.get(model.swipe.readerId);
    const handle = document.querySelector(`.stripe-handle[data-reader-id="${CSS.escape(model.swipe.readerId)}"]`);
    if (handle) {
      handle.style.left = percent(point[0] - Number(reader.rect.x), Number(reader.rect.width));
      handle.style.top = percent(point[1] - Number(reader.rect.y), Number(reader.rect.height));
    }
  }

  function zoneHit(point, zones) {
    return zones.some((zone) => inside(point, zone));
  }

  function evaluateSwipe(reader, points, duration) {
    const profile = PROFILE_LIMITS[reader.profile_token];
    const track = reader.track;
    const direction = track.direction;
    const expectedStart = direction === "ltr" ? Number(track.x_start) : Number(track.x_end);
    const expectedEnd = direction === "ltr" ? Number(track.x_end) : Number(track.x_start);
    const span = Math.abs(Number(track.x_end) - Number(track.x_start));
    const sign = direction === "ltr" ? 1 : -1;
    const coverage = Math.max(0, Math.min(1000, Math.round((points.at(-1)[0] - points[0][0]) * sign / span * 1000)));
    let maximumDeviation = 0;
    let maximumGap = 0;
    let backtrack = 0;
    for (let index = 0; index < points.length; index += 1) {
      maximumDeviation = Math.max(maximumDeviation, Math.abs(points[index][1] - Number(track.y)));
      if (index) {
        maximumGap = Math.max(maximumGap, Math.hypot(points[index][0] - points[index - 1][0], points[index][1] - points[index - 1][1]));
        const signed = (points[index][0] - points[index - 1][0]) * sign;
        if (signed < 0) backtrack += -signed;
      }
    }
    const bad = points.length - 1 < 14
      || Math.abs(points[0][0] - expectedStart) > span * .08
      || Math.abs(points.at(-1)[0] - expectedEnd) > span * .08
      || coverage < 920
      || maximumDeviation > profile.straightness_px
      || backtrack > 18
      || maximumGap > 58
      || points.some((point) => zoneHit(point, reader.interference_zones));
    if (bad) return "BAD READ";
    if (duration < profile.minimum_ms) return "TOO FAST";
    if (duration > profile.maximum_ms) return "TOO SLOW";
    return "ACCEPTED";
  }

  function endSwipe(event) {
    if (!model.swipe || event.pointerId !== model.swipe.pointerId) return;
    const point = stagePoint(event);
    const duration = Math.max(Math.round(performance.now() - model.swipe.startedAt), 0);
    record("swipe_up", {
      reader_id: model.swipe.readerId,
      card_id: model.swipe.cardId,
      point,
      duration_ms: duration,
      client_status: "IGNORED_BY_GRADER",
    });
    if (point[0] !== model.swipe.points.at(-1)[0] || point[1] !== model.swipe.points.at(-1)[1]) model.swipe.points.push(point);
    const readerId = model.swipe.readerId;
    const feedback = evaluateSwipe(model.readerById.get(readerId), model.swipe.points, duration);
    model.readerAttempts[readerId] += 1;
    model.swipeAttempts += 1;
    model.readerFeedback[readerId] = feedback;
    if (feedback === "ACCEPTED") {
      model.readerLocked[readerId] = true;
      model.helpers.setReadout("ACCEPTED · READER LOCKED", "passed");
    } else {
      model.helpers.setReadout(`${feedback} · RETRY THE SAME READER`, "error");
    }
    model.swipe = null;
    renderDesk();
  }

  function pointerMove(event) {
    if (model.drag) moveInsert(event);
    else if (model.swipe) moveSwipe(event);
  }

  function pointerUp(event) {
    if (model.drag) endInsert(event);
    else if (model.swipe) endSwipe(event);
  }

  function updateSummary() {
    const locked = Object.values(model.readerLocked).filter(Boolean).length;
    const lamps = document.getElementById("stripe-lamps");
    if (lamps) lamps.innerHTML = model.state.readers.map((reader) => `<i class="${model.readerLocked[reader.id] ? "is-lit" : ""}" style="--lamp:${clean(reader.badge.color)}"><span>${clean(reader.badge.symbol)}</span></i>`).join("");
    const count = document.getElementById("stripe-lock-count");
    if (count) count.textContent = `${locked} / 3 LOCKED`;
    const tape = document.getElementById("stripe-tape");
    if (tape) {
      const rows = model.state.readers.map((reader) => {
        const id = String(reader.id);
        return `<li><b>${clean(reader.label)}</b><span>${clean(model.readerFeedback[id])}</span><i>${model.readerAttempts[id]} TRY</i></li>`;
      });
      tape.innerHTML = rows.join("");
    }
  }

  function resetDesk() {
    if (model.busy || model.drag || model.swipe) return;
    clearFreshFailure();
    record("reset");
    model.resetCount += 1;
    initializeState(false);
    renderDesk();
    model.helpers.setReadout("DESK RESET · CARDS RETURNED · WINDOWS UNCHANGED", "idle");
  }

  function initializeState(resetGlobal = true) {
    model.cardLocations = Object.fromEntries(model.state.cards.map((card) => [String(card.id), null]));
    model.readerCards = Object.fromEntries(model.state.readers.map((reader) => [String(reader.id), null]));
    model.readerLocked = Object.fromEntries(model.state.readers.map((reader) => [String(reader.id), false]));
    model.readerAttempts = Object.fromEntries(model.state.readers.map((reader) => [String(reader.id), 0]));
    model.readerFeedback = Object.fromEntries(model.state.readers.map((reader) => [String(reader.id), "INSERT CARD"]));
    model.drag = null;
    model.swipe = null;
    model.invalidInsertions = 0;
    model.swipeAttempts = 0;
    model.auditCount = 0;
    model.terminal = false;
    if (resetGlobal) {
      model.events = [];
      model.resetCount = 0;
    }
  }

  function payload(completed) {
    return {
      mechanic_id: model.state.mechanic_id,
      task_id: model.state.task_id,
      challenge_id: model.state.challenge_id,
      events: model.events,
      card_locations: {...model.cardLocations},
      reader_states: Object.fromEntries(model.state.readers.map((reader) => {
        const id = String(reader.id);
        return [id, {card_id: model.readerCards[id], locked: model.readerLocked[id], attempts: model.readerAttempts[id]}];
      })),
      locked_count: Object.values(model.readerLocked).filter(Boolean).length,
      invalid_insertions: model.invalidInsertions,
      swipe_attempts: model.swipeAttempts,
      reset_count: model.resetCount,
      audit_count: model.auditCount,
      completed,
    };
  }

  async function auditDesk() {
    if (model.busy || model.terminal || model.drag || model.swipe) return;
    clearFreshFailure();
    record("audit");
    model.auditCount += 1;
    const completed = Object.values(model.readerLocked).every(Boolean);
    model.busy = true;
    model.terminal = true;
    document.querySelectorAll("button").forEach((button) => { button.disabled = true; });
    model.helpers.setReadout("REPLAYING CARD PATHS AND STRIPE TIMESTAMPS…", "pending");
    try {
      const response = await fetch("/result", {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(payload(completed))});
      const outcome = await response.json();
      if (outcome.passed === true) {
        const shell = document.querySelector(".stripe-purgatory");
        shell?.classList.add("is-pass");
        shell?.insertAdjacentHTML("beforeend", '<div class="stripe-verdict stripe-verdict-pass"><small>ALL THREE CALIBRATIONS REPLAYED</small><strong>CLEARED</strong><i>PASS</i></div>');
        model.helpers.setReadout("PASS", "passed");
      } else if (outcome.passed === false && outcome.state) {
        await model.helpers.render(outcome.state);
        const shell = document.querySelector(".stripe-purgatory");
        shell?.classList.add("is-fresh-fail");
        shell?.insertAdjacentHTML("beforeend", '<div class="stripe-verdict stripe-verdict-fail stripe-verdict-fresh"><small>INCOMPLETE CALIBRATION · FRESH DESK</small><strong>REJECTED</strong><i>FAIL</i></div>');
        model.helpers.setReadout("FAIL · INCOMPLETE AUDIT · FRESH DESK", "error");
        window.setTimeout(() => document.querySelector(".stripe-verdict-fresh")?.remove(), 1350);
      } else {
        model.busy = false;
        model.terminal = false;
        document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
        model.helpers.setReadout("FAIL · NO CALIBRATION GRADE", "error");
      }
    } catch (_error) {
      model.busy = false;
      model.terminal = false;
      document.querySelectorAll("button").forEach((button) => { button.disabled = false; });
      model.helpers.setReadout("FAIL · CALIBRATION DESK OFFLINE", "error");
    }
  }

  function clearFreshFailure() {
    document.querySelector(".stripe-purgatory")?.classList.remove("is-fresh-fail");
    document.querySelector(".stripe-verdict-fresh")?.remove();
  }

  async function render(state, helpers) {
    document.body.dataset.mechanic = "magnetic-stripe-purgatory";
    document.body.style.setProperty("--stripe-desk", state.palette.desk);
    document.body.style.setProperty("--stripe-ink", state.palette.ink);
    document.body.style.setProperty("--stripe-signal", state.palette.signal);
    document.body.style.setProperty("--stripe-warning", state.palette.warning);
    document.body.style.setProperty("--stripe-card", state.palette.card);
    document.body.dataset.cheatMode = helpers.isCheatMode() ? "true" : "false";
    Object.assign(model, {
      state,
      helpers,
      cardById: new Map(state.cards.map((card) => [String(card.id), card])),
      readerById: new Map(state.readers.map((reader) => [String(reader.id), reader])),
      assignments: new Map(),
      busy: false,
      terminal: false,
    });
    initializeState(true);
    helpers.app.innerHTML = `<section class="stripe-purgatory" data-challenge-id="${clean(state.challenge_id)}">
      <header class="stripe-head"><div><span>OFFICE OF HOSTILE PAYMENTS / CALIBRATION DESK 03</span><h1>${clean(state.prompt)}</h1></div><aside><small>CALIBRATION LAMPS</small><div id="stripe-lamps"></div><b id="stripe-lock-count">0 / 3 LOCKED</b></aside></header>
      <main class="stripe-workbench"><section class="stripe-stage" id="stripe-stage" aria-label="multi-reader magnetic stripe calibration desk"></section><div class="stripe-instruction"><span>MATCH THE BADGE</span><i>FOLLOW THE READER</i><b>LISTEN TO ITS VERDICT</b></div></main>
      <footer class="stripe-foot"><button type="button" id="stripe-reset">↺ RESET DESK</button><div><div class="readout" data-status="idle">INSERT THREE BADGE-MATCHED CARDS</div><ol id="stripe-tape"></ol></div><button type="button" id="stripe-audit">${clean(state.submit_label)}</button></footer>
      ${helpers.cheatPanelTemplate()}</section>`;
    renderDesk();
    document.getElementById("stripe-reset")?.addEventListener("click", resetDesk);
    document.getElementById("stripe-audit")?.addEventListener("click", auditDesk);
    window.addEventListener("pointermove", pointerMove);
    window.addEventListener("pointerup", pointerUp);
    window.addEventListener("pointercancel", pointerUp);
    helpers.installCheatPanel();
    window.magneticStripePurgatoryModel = model;
    updateSummary();
  }

  window.WeirdCaptchaMechanics = window.WeirdCaptchaMechanics || {};
  window.WeirdCaptchaMechanics.magnetic_stripe_purgatory = {rootSelector: ".stripe-purgatory", render};
})();
