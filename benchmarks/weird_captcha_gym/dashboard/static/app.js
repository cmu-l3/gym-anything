const config = Object.freeze({
  mode: "local",
  catalogUrl: "/api/catalog",
  companionUrl: "",
  ...(window.CAPTCHA_BENCH_CONFIG || {}),
});
const companionTokenKey = `captcha-bench-companion-token:${config.companionUrl || "same-origin"}`;

const state = {
  catalog: null,
  reviews: null,
  system: null,
  sessions: [],
  evaluations: [],
  companion: {
    connected: config.mode === "local",
    status: config.mode === "local" ? "connected" : "checking",
    error: "",
    token: config.mode === "shared" ? localStorage.getItem(companionTokenKey) || "" : "",
    lastAttempt: 0,
  },
  route: {name: "observatory", id: null},
  filters: {query: "", group: "All", stage: "built", review: "all", view: "grid"},
  reviewFilters: {query: "", status: "pending"},
  environmentReturn: "environments",
  gallery: {},
  expandedLogs: new Set(),
  previousSessionStatus: new Map(),
};

const app = document.getElementById("app");
const modalRoot = document.getElementById("modal-root");
const toastStack = document.getElementById("toast-stack");

const arrowIcon = `<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12h14M13 6l6 6-6 6"/></svg>`;
const searchIcon = `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="6.5"/><path d="m16 16 4 4"/></svg>`;
const gridIcon = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="4" y="4" width="6" height="6"/><rect x="14" y="4" width="6" height="6"/><rect x="4" y="14" width="6" height="6"/><rect x="14" y="14" width="6" height="6"/></svg>`;
const listIcon = `<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M5 6h14M5 12h14M5 18h14"/></svg>`;

function escapeHtml(value) {
  return String(value == null ? "" : value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(Number(value || 0));
}

function formatBytes(value) {
  const bytes = Number(value || 0);
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(bytes > 10240 ? 0 : 1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(bytes > 100 * 1024 * 1024 ? 0 : 1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

function titleCase(value) {
  return String(value || "").replaceAll("_", " ").replaceAll("-", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function elapsedLabel(seconds) {
  const value = Number(seconds || 0);
  if (value < 60) return `${value}s`;
  const minutes = Math.floor(value / 60);
  return `${minutes}m ${String(value % 60).padStart(2, "0")}s`;
}

function statusColor(status) {
  return {
    running: "#d7ff54",
    booting: "#63dbec",
    queued: "#63dbec",
    stopping: "#ffc857",
    stopped: "#747a73",
    failed: "#ff654f",
    completed: "#9be7a4",
    preview: "#a99eff",
    canceling: "#ffc857",
    canceled: "#747a73",
  }[status] || "#8a9189";
}

function reviewFor(environmentId) {
  return state.reviews?.items?.[environmentId] || {
    environment_id: environmentId,
    status: "pending",
    note: "",
    created_at: null,
    updated_at: null,
    history: [],
  };
}

function reviewStatusLabel(status) {
  return {pending: "Pending review", looks_good: "Looks good · hands-on pending", approved: "Approved", revision_requested: "Needs revision"}[status] || "Pending review";
}

function reviewStatusShort(status) {
  return {pending: "Pending", looks_good: "Looks good", approved: "Approved", revision_requested: "Revise"}[status] || "Pending";
}

function reviewStatusColor(status) {
  return {pending: "#848b83", looks_good: "#63dbec", approved: "#d7ff54", revision_requested: "#ff654f"}[status] || "#848b83";
}

function reviewTimestamp(value) {
  if (!value) return "Not reviewed yet";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "Saved";
  return new Intl.DateTimeFormat("en-US", {month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit"}).format(date);
}

async function api(path, options = {}) {
  const base = String(config.companionUrl || "").replace(/\/$/, "");
  const url = base ? `${base}${path.startsWith("/") ? path : `/${path}`}` : path;
  const headers = {...(options.headers || {})};
  if (options.body != null) headers["content-type"] = headers["content-type"] || "application/json";
  if (config.mode === "shared" && state.companion.token) headers["X-Captcha-Bench-Token"] = state.companion.token;
  const response = await fetch(url, {
    ...options,
    mode: base ? "cors" : "same-origin",
    headers,
  });
  let payload = {};
  try { payload = await response.json(); } catch (_error) {}
  if (!response.ok) {
    const error = new Error(payload.error || `${response.status} ${response.statusText}`);
    error.status = response.status;
    throw error;
  }
  return payload;
}

async function loadCatalog() {
  const response = await fetch(config.catalogUrl, {headers: {accept: "application/json"}});
  if (!response.ok) throw new Error(`catalog unavailable (${response.status})`);
  return response.json();
}

function emptyReviewSnapshot(catalog) {
  const total = catalog.environments.filter((environment) => environment.stage === "built").length;
  return {
    version: 1,
    updated_at: null,
    statuses: ["pending", "looks_good", "approved", "revision_requested"],
    stats: {total, reviewed: 0, decided: 0, pending: total, hands_on_pending: total, looks_good: 0, approved: 0, revision_requested: 0},
    items: {},
  };
}

function toast(title, message = "", tone = "success", duration = 5200) {
  const colors = {success: "#d7ff54", error: "#ff654f", info: "#63dbec", warn: "#ffc857"};
  const node = document.createElement("div");
  node.className = "toast";
  node.style.setProperty("--toast-color", colors[tone] || colors.info);
  node.innerHTML = `<div><b>${escapeHtml(title)}</b>${message ? `<span>${escapeHtml(message)}</span>` : ""}</div><button type="button" aria-label="Dismiss">×</button>`;
  node.querySelector("button").addEventListener("click", () => node.remove());
  toastStack.appendChild(node);
  window.setTimeout(() => node.remove(), duration);
}

function parseRoute() {
  const parts = (location.hash.replace(/^#\/?/, "") || "observatory").split("/").filter(Boolean);
  if (parts[0] === "environment" && parts[1]) return {name: "environment", id: decodeURIComponent(parts[1])};
  if (["observatory", "environments", "reviews", "sessions", "evaluations"].includes(parts[0])) return {name: parts[0], id: null};
  return {name: "observatory", id: null};
}

function navigate(route) {
  location.hash = route.startsWith("#") ? route : `#/${route.replace(/^\//, "")}`;
}

function setChrome(active, label) {
  document.querySelectorAll("[data-nav]").forEach((link) => link.classList.toggle("is-active", link.dataset.nav === active));
  const breadcrumb = document.getElementById("breadcrumb");
  breadcrumb.innerHTML = `<span>WEIRD CAPTCHA GYM</span><b>${escapeHtml(label.toUpperCase())}</b>`;
  document.body.classList.remove("nav-open");
}

function updateCounts() {
  if (state.catalog) document.getElementById("nav-environment-count").textContent = state.catalog.stats.total;
  const reviewCount = document.getElementById("nav-review-count");
  if (reviewCount && state.reviews) reviewCount.textContent = formatNumber(state.reviews.stats.hands_on_pending ?? state.reviews.stats.pending);
  const liveCount = state.sessions.filter((session) => ["queued", "booting", "running", "stopping"].includes(session.status)).length;
  const node = document.getElementById("nav-session-count");
  node.textContent = liveCount;
  node.classList.toggle("has-live", liveCount > 0);
  const runner = document.getElementById("runner-name");
  const kicker = document.getElementById("runner-kicker");
  const status = document.querySelector(".companion-status");
  if (runner) runner.textContent = state.companion.connected ? state.system?.runner || "connected" : config.mode === "shared" ? "pair companion" : "offline";
  if (kicker) kicker.textContent = config.mode === "shared" ? "LOCAL COMPANION" : "LOCAL RUNNER";
  if (status) status.dataset.connection = state.companion.connected ? "connected" : state.companion.status;
}

function coverMarkup(environment, className = "") {
  if (environment.cover) return `<img class="${className}" src="${escapeHtml(environment.cover)}" alt="${escapeHtml(environment.title)} screenshot" loading="lazy">`;
  return `<div class="generative-cover ${className}" style="--accent:${escapeHtml(environment.accent)}"><span>${escapeHtml(environment.stage)} / NO EVIDENCE</span></div>`;
}

function environmentCard(environment, index = 0) {
  const stageLabel = environment.stage === "built" ? "built" : environment.stage;
  const review = reviewFor(environment.id);
  const reviewStamp = environment.stage === "built"
    ? `<span class="card-review" data-review-status="${escapeHtml(review.status)}" style="--review-color:${reviewStatusColor(review.status)}"><i></i>${escapeHtml(reviewStatusShort(review.status))}</span>`
    : "";
  const launch = environment.stage === "built" && environment.launchable
    ? `<button class="quick-launch" type="button" data-quick-launch="${escapeHtml(environment.id)}" title="Open locally in browser" aria-label="Open ${escapeHtml(environment.title)} locally in browser">${arrowIcon}</button>`
    : "";
  return `
    <article class="environment-card" role="button" tabindex="0" data-open-env="${escapeHtml(environment.id)}" style="--accent:${escapeHtml(environment.accent)}">
      <div class="card-media">
        ${coverMarkup(environment)}
        <span class="card-index">${String(index + 1).padStart(2, "0")}</span>
        <span class="card-stage"><i></i>${escapeHtml(stageLabel)}</span>
        ${reviewStamp}
      </div>
      <div class="card-content">
        <div class="card-overline"><span>${escapeHtml(environment.group)}</span><span>${escapeHtml(environment.difficulty)}</span></div>
        <h3>${escapeHtml(environment.title)}</h3>
        <p>${escapeHtml(environment.summary)}</p>
        <div class="tag-row">${environment.axes.slice(0, 3).map((axis) => `<span class="tag">${escapeHtml(axis)}</span>`).join("")}</div>
        <div class="card-footer">
          <span class="human-state">${escapeHtml(environment.human_status)}</span>
          ${launch}
        </div>
      </div>
    </article>`;
}

function renderRail(environments) {
  return `<div class="environment-rail">${environments.map((environment, index) => environmentCard(environment, index)).join("")}</div>`;
}

function renderObservatory() {
  setChrome("observatory", "Interaction observatory");
  const catalog = state.catalog;
  const byId = Object.fromEntries(catalog.environments.map((environment) => [environment.mechanic_id, environment]));
  const featured = [byId.motion_only_ghost_jigsaw, byId.domino_autopsy, byId.funeral_ritual].filter(Boolean);
  const firstPack = catalog.environments.filter((environment) => environment.group === "Interaction I");
  const secondPack = catalog.environments.filter((environment) => environment.group === "Interaction II");
  const thirdPack = catalog.environments.filter((environment) => environment.group === "Interaction III");
  const fourthPack = catalog.environments.filter((environment) => environment.group === "Interaction IV");
  const fifthPack = catalog.environments.filter((environment) => environment.group === "Interaction V");
  const sixthPack = catalog.environments.filter((environment) => environment.group === "Interaction VI");
  app.innerHTML = `
    <div class="page observatory-page">
      <section class="observatory-hero">
        <div class="hero-copy">
          <p class="eyebrow">Interaction-first visual evaluation</p>
          <h1 class="display-title">A screenshot<br>should <em>not</em><br>be enough.</h1>
          <p class="hero-description">An evolving field collection of strange visual puzzles built to measure motion, memory, timing, active perception, physical reasoning, and recovery in computer-use agents.</p>
          <div class="hero-actions">
            <button class="button button-acid" type="button" data-action="open-launch-picker"><span>Launch a specimen</span>${arrowIcon}</button>
            <button class="button button-ghost" type="button" data-action="browse-environments">Browse all ${catalog.stats.total}</button>
          </div>
        </div>
        <div class="specimen-stack" aria-label="Featured puzzle screenshots">
          ${featured.map((environment) => `
            <figure class="specimen-card" data-open-env="${escapeHtml(environment.id)}" style="--specimen-accent:${escapeHtml(environment.accent)}">
              ${coverMarkup(environment)}
              <figcaption><span><b>${escapeHtml(environment.title)}</b>${escapeHtml(environment.axes[0])}</span><i></i></figcaption>
            </figure>`).join("")}
        </div>
      </section>

      <section class="stats-ribbon" aria-label="Benchmark statistics">
        <div class="stat-cell"><b>${formatNumber(catalog.stats.built)}</b><span>working designs</span></div>
        <div class="stat-cell"><b>${formatNumber(catalog.stats.evidence_frames)}</b><span>evidence frames</span></div>
        <div class="stat-cell"><b>${formatNumber(catalog.stats.browser_verified)}</b><span>script-verified</span></div>
        <div class="stat-cell"><b>${formatNumber(catalog.stats.human_touched)}</b><span>human-touched</span></div>
      </section>

      <section>
        <div class="section-heading"><div><p class="eyebrow">Collection 01</p><h2>Perception under motion</h2></div><p>Five puzzles where every action changes what can be known: motion fields, cursor search, parallel timers, moving keys, and transient symbols.</p></div>
        ${renderRail(firstPack)}
      </section>

      <section>
        <div class="section-heading"><div><p class="eyebrow">Collection 02</p><h2>Worlds that push back</h2></div><p>Five long-loop mechanics built around actual physics, consequences, occlusion, implicit ritual, and continuous navigation.</p></div>
        ${renderRail(secondPack)}
      </section>

      <section class="interaction-pack-collection">
        <div class="section-heading"><div><p class="eyebrow">Collection 03 · Built interaction pack</p><h2>Things you must probe</h2></div><p>Five working designs where the answer appears only through causal experimentation, temporal tracking, cursor exploration, or calibrated motion.</p></div>
        ${renderRail(thirdPack)}
      </section>

      <section class="interaction-pack-collection">
        <div class="section-heading"><div><p class="eyebrow">Collection 04 · Built interaction pack</p><h2>Things that fight back</h2></div><p>Five working designs built around prediction, viewport control, physical assembly, divided attention, and iterative machine feedback.</p></div>
        ${renderRail(fourthPack)}
      </section>

      <section class="interaction-pack-collection">
        <div class="section-heading"><div><p class="eyebrow">Collection 05 · Built interaction pack</p><h2>Reality is an input device</h2></div><p>Five working worlds where photographs, projections, recorded actions, recursive scale, and forced perspective rewrite the space the agent must operate.</p></div>
        ${renderRail(fifthPack)}
      </section>

      <section class="interaction-pack-collection">
        <div class="section-heading"><div><p class="eyebrow">Collection 06 · Built interaction pack</p><h2>Machines you must inhabit</h2></div><p>Five working embodied tests built from active 3D sensing, volumetric reconstruction, multi-camera teleoperation, deformable physics, and portal coordinate frames.</p></div>
        ${renderRail(sixthPack)}
      </section>

      <section class="principle-band">
        <h2>Difficulty must live in the interaction.</h2>
        <blockquote>“Make the strange behavior real, not animated theater. A green test suite proves the harness; a human run proves usability; only agent experiments prove benchmark value.”<footer>Field note / 2026-07-10</footer></blockquote>
      </section>
    </div>`;
}

function filteredEnvironments() {
  const query = state.filters.query.trim().toLowerCase();
  return state.catalog.environments.filter((environment) => {
    const groupMatch = state.filters.group === "All" || environment.group === state.filters.group;
    const stageMatch = state.filters.stage === "all" || environment.stage === state.filters.stage;
    const reviewMatch = state.filters.review === "all" || (environment.stage === "built" && reviewFor(environment.id).status === state.filters.review);
    const haystack = [environment.title, environment.summary, environment.mechanic_id, environment.group, ...environment.axes].join(" ").toLowerCase();
    return groupMatch && stageMatch && reviewMatch && (!query || haystack.includes(query));
  });
}

function environmentGridMarkup(environments) {
  return environments.length
    ? environments.map((environment, index) => environmentCard(environment, index)).join("")
    : `<div class="empty-catalog"><b>No strange machines found.</b><span>Try a wider search or stage filter.</span></div>`;
}

function refreshEnvironmentCatalog({rebuild = true} = {}) {
  const grid = document.getElementById("environment-grid");
  if (!grid) return;
  const filtered = filteredEnvironments();
  if (rebuild) grid.innerHTML = environmentGridMarkup(filtered);
  grid.classList.toggle("is-compact", state.filters.view === "compact");
  const count = document.querySelector(".catalog-count");
  if (count) count.textContent = `${filtered.length} / ${state.catalog.stats.total}`;
  document.querySelectorAll("[data-filter-group]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.filterGroup === state.filters.group);
  });
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.view === state.filters.view);
  });
  const stage = document.getElementById("stage-filter");
  if (stage && stage.value !== state.filters.stage) stage.value = state.filters.stage;
  const review = document.getElementById("review-filter");
  if (review && review.value !== state.filters.review) review.value = state.filters.review;
}

function renderEnvironments() {
  setChrome("environments", "Environment collection");
  const filtered = filteredEnvironments();
  const groupButtons = ["All", ...state.catalog.groups.map((group) => group.name)];
  app.innerHTML = `
    <div class="page environments-page">
      <header class="page-head">
        <div><p class="eyebrow">Environment collection</p><h1 class="page-title">Strange machines,<br>ready to disturb.</h1><p class="page-copy">Every working card comes from a real environment, task, verifier, and evidence run. Human approval is tracked separately, so a green scripted solve never silently becomes a usability claim.</p></div>
        <div class="page-head-actions"><button class="button button-acid" type="button" data-action="open-launch-picker">Quick launch ${arrowIcon}</button></div>
      </header>
      <div class="catalog-toolbar">
        <label class="search-field">${searchIcon}<input id="environment-search" type="search" value="${escapeHtml(state.filters.query)}" placeholder="Search motion, physics, memory…" aria-label="Search environments"></label>
        <select class="filter-select" id="stage-filter" aria-label="Filter by stage">
          <option value="all" ${state.filters.stage === "all" ? "selected" : ""}>All stages</option>
          <option value="built" ${state.filters.stage === "built" ? "selected" : ""}>Built designs</option>
          <option value="rejected" ${state.filters.stage === "rejected" ? "selected" : ""}>Archive</option>
        </select>
        <select class="filter-select" id="review-filter" aria-label="Filter by human review">
          <option value="all" ${state.filters.review === "all" ? "selected" : ""}>All reviews</option>
          <option value="pending" ${state.filters.review === "pending" ? "selected" : ""}>Pending review</option>
          <option value="looks_good" ${state.filters.review === "looks_good" ? "selected" : ""}>Looks good · untested</option>
          <option value="approved" ${state.filters.review === "approved" ? "selected" : ""}>Approved</option>
          <option value="revision_requested" ${state.filters.review === "revision_requested" ? "selected" : ""}>Needs revision</option>
        </select>
        <div class="view-toggle" aria-label="Catalog view"><button type="button" data-view="grid" class="${state.filters.view === "grid" ? "is-active" : ""}" aria-label="Grid view">${gridIcon}</button><button type="button" data-view="compact" class="${state.filters.view === "compact" ? "is-active" : ""}" aria-label="Wide card view">${listIcon}</button></div>
      </div>
      <div class="filter-pills">${groupButtons.map((group) => `<button class="filter-pill ${state.filters.group === group ? "is-active" : ""}" type="button" data-filter-group="${escapeHtml(group)}">${escapeHtml(group)}</button>`).join("")}<span class="catalog-count">${filtered.length} / ${state.catalog.stats.total}</span></div>
      <section class="environment-grid ${state.filters.view === "compact" ? "is-compact" : ""}" id="environment-grid">
        ${environmentGridMarkup(filtered)}
      </section>
    </div>`;
}

function filteredReviewEnvironments() {
  const query = state.reviewFilters.query.trim().toLowerCase();
  const rank = {revision_requested: 0, looks_good: 1, pending: 2, approved: 3};
  return state.catalog.environments
    .filter((environment) => environment.stage === "built")
    .filter((environment) => {
      const review = reviewFor(environment.id);
      const statusMatch = state.reviewFilters.status === "all" || review.status === state.reviewFilters.status;
      const haystack = [environment.title, environment.summary, environment.mechanic_id, environment.group, review.note, ...environment.axes].join(" ").toLowerCase();
      return statusMatch && (!query || haystack.includes(query));
    })
    .sort((first, second) => rank[reviewFor(first.id).status] - rank[reviewFor(second.id).status] || first.order - second.order || first.title.localeCompare(second.title));
}

function reviewQueueGridMarkup() {
  const environments = filteredReviewEnvironments();
  return environments.length
    ? environments.map((environment, index) => environmentCard(environment, index)).join("")
    : `<div class="empty-catalog review-empty"><b>Nothing in this lane.</b><span>Change the review filter or search another mechanic.</span></div>`;
}

function refreshReviewQueue() {
  const grid = document.getElementById("review-grid");
  if (!grid) return;
  grid.innerHTML = reviewQueueGridMarkup();
  document.querySelectorAll("[data-review-filter]").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.reviewFilter === state.reviewFilters.status);
  });
  const count = document.getElementById("review-result-count");
  if (count) count.textContent = `${filteredReviewEnvironments().length} shown`;
}

function renderReviewQueue() {
  setChrome("reviews", "Human review queue");
  const stats = state.reviews.stats;
  const progress = stats.total ? Math.round(stats.decided / stats.total * 100) : 0;
  app.innerHTML = `
    <div class="page reviews-page">
      <header class="page-head review-page-head">
        <div><p class="eyebrow">Human acceptance gate</p><h1 class="page-title">The human gets<br>the final say.</h1><p class="page-copy">Use “Looks good” for a design or solution-film screening. Approve only after hands-on play through the local browser or VNC surface. Scripted verification, screening, and human acceptance remain separate records.</p></div>
        <div class="review-ledger-stamp"><small>HANDS-ON LEDGER</small><b>${stats.decided} / ${stats.total}</b><span>${progress}% decided</span></div>
      </header>
      <section class="review-summary" aria-label="Review statistics">
        <button class="${state.reviewFilters.status === "all" ? "is-active" : ""}" type="button" data-review-filter="all"><small>Reviewable</small><b>${stats.total}</b><span>built environments</span></button>
        <button class="${state.reviewFilters.status === "pending" ? "is-active" : ""}" type="button" data-review-filter="pending"><small>Unscreened</small><b>${stats.pending}</b><span>no review recorded</span></button>
        <button class="${state.reviewFilters.status === "looks_good" ? "is-active" : ""}" type="button" data-review-filter="looks_good"><small>Looks good</small><b>${stats.looks_good}</b><span>hands-on still pending</span></button>
        <button class="${state.reviewFilters.status === "approved" ? "is-active" : ""}" type="button" data-review-filter="approved"><small>Approved</small><b>${stats.approved}</b><span>interaction accepted</span></button>
        <button class="${state.reviewFilters.status === "revision_requested" ? "is-active" : ""}" type="button" data-review-filter="revision_requested"><small>Needs revision</small><b>${stats.revision_requested}</b><span>feedback recorded</span></button>
      </section>
      <div class="review-progress" aria-label="${progress}% reviewed"><i style="width:${progress}%"></i></div>
      <div class="review-queue-note"><span>DECISIONS PERSIST LOCALLY</span><code>${escapeHtml(state.system.review_path || "environment-reviews.json")}</code></div>
      <div class="review-toolbar">
        <label class="search-field">${searchIcon}<input id="review-search" type="search" value="${escapeHtml(state.reviewFilters.query)}" placeholder="Search the acceptance queue…" aria-label="Search review queue"></label>
        <div class="review-filter-tabs" aria-label="Filter review queue">
          ${[["all", "All"], ["pending", "Unscreened"], ["looks_good", "Looks good"], ["approved", "Approved"], ["revision_requested", "Needs revision"]].map(([status, label]) => `<button class="${state.reviewFilters.status === status ? "is-active" : ""}" type="button" data-review-filter="${status}">${label}</button>`).join("")}
        </div>
        <span id="review-result-count">${filteredReviewEnvironments().length} shown</span>
      </div>
      <section class="environment-grid review-grid" id="review-grid">${reviewQueueGridMarkup()}</section>
    </div>`;
}

function findEnvironment(id) {
  return state.catalog.environments.find((environment) => environment.id === id || environment.mechanic_id === id);
}

function detailHero(environment, selectedIndex) {
  const selected = environment.screenshots[selectedIndex] || environment.screenshots[0];
  if (!selected) return `<div class="hero-frame">${coverMarkup(environment)}</div>`;
  return `<div class="hero-frame"><img src="${escapeHtml(selected.url)}" alt="${escapeHtml(environment.title)} evidence: ${escapeHtml(selected.name)}"><div class="hero-frame-label"><span>EVIDENCE FRAME ${String(selectedIndex + 1).padStart(2, "0")}</span><span>${escapeHtml(selected.name)}</span></div></div>`;
}

function solutionVideoMarkup(environment) {
  const video = environment.solution_video;
  if (!video) return "";
  const duration = Number.isFinite(Number(video.duration_seconds)) ? `${Number(video.duration_seconds).toFixed(1)} s` : "recorded run";
  const resolution = video.width && video.height ? `${video.width} × ${video.height}` : "native capture";
  const sources = [
    video.mp4_url ? `<source src="${escapeHtml(video.mp4_url)}" type="video/mp4">` : "",
    video.webm_url ? `<source src="${escapeHtml(video.webm_url)}" type="video/webm">` : "",
  ].join("");
  return `<details class="solution-reel" data-solution-video="${escapeHtml(environment.mechanic_id)}">
    <summary>
      <span class="solution-reel-number">S/${String(environment.order).padStart(2, "0")}</span>
      <span class="solution-reel-title"><small>Spoiler · verified solution film</small><b>Open the successful run</b></span>
      <span class="solution-reel-facts"><i class="${video.verified ? "is-verified" : ""}"></i>${escapeHtml(duration)} · ${escapeHtml(resolution)}</span>
      <span class="solution-reel-toggle" aria-hidden="true">＋</span>
    </summary>
    <div class="solution-reel-body">
      <div class="solution-reel-stage">
        <video controls preload="metadata" playsinline ${environment.cover ? `poster="${escapeHtml(environment.cover)}"` : ""} aria-label="${escapeHtml(environment.title)} verified solution">
          ${sources}
          Your browser cannot play this solution recording.
        </video>
        <div class="solution-reel-perf"><span>SERVER</span><span>DIRECT</span><span>VERIFIER</span><b>${video.verified ? "3 / 3 PASS" : "ARCHIVED"}</b></div>
      </div>
      <div class="solution-reel-notes">
        <div><small>Operator transcript</small><p>${escapeHtml(video.approach)}</p></div>
        <dl><div><dt>Evidence set</dt><dd>${escapeHtml(video.evidence_set)}</dd></div><div><dt>Codec</dt><dd>${escapeHtml(String(video.codec || "recorded"))}</dd></div><div><dt>Captured</dt><dd>${escapeHtml(reviewTimestamp(video.generated_at))}</dd></div></dl>
        <a href="${escapeHtml(video.manifest_url)}" target="_blank" rel="noreferrer">OPEN MACHINE MANIFEST ↗</a>
      </div>
    </div>
  </details>`;
}

function selectDetailFrame(environmentId, selectedIndex) {
  const environment = findEnvironment(environmentId);
  if (!environment || !environment.screenshots[selectedIndex]) return;
  state.gallery[environment.id] = selectedIndex;
  const hero = document.getElementById("detail-hero");
  if (hero) hero.innerHTML = detailHero(environment, selectedIndex);
  document.querySelectorAll(`[data-gallery-environment="${CSS.escape(environment.id)}"]`).forEach((button) => {
    button.classList.toggle("is-active", Number(button.dataset.galleryIndex) === selectedIndex);
  });
}

function reviewHistoryMarkup(review) {
  const history = [...(review.history || [])].reverse().slice(0, 4);
  if (!history.length) return `<div class="review-history-empty">No decisions recorded yet.</div>`;
  return `<ol class="review-history">${history.map((entry) => `<li style="--review-color:${reviewStatusColor(entry.status)}"><i></i><div><b>${escapeHtml(reviewStatusLabel(entry.status))}</b><span>${escapeHtml(reviewTimestamp(entry.created_at))}</span>${entry.note ? `<p>${escapeHtml(entry.note)}</p>` : ""}</div></li>`).join("")}</ol>`;
}

function reviewDeskMarkup(environment) {
  const review = reviewFor(environment.id);
  const stamp = {pending: "UNREVIEWED", looks_good: "PROMISING", approved: "APPROVED", revision_requested: "REVISE"}[review.status] || "UNREVIEWED";
  const choices = [
    ["approved", "✓", "Approve", "Interaction is acceptable"],
    ["looks_good", "◐", "Looks good", "Film/design checked · hands-on pending"],
    ["revision_requested", "↺", "Request revision", "Record what must change"],
    ["pending", "○", "Leave pending", "Return it to the queue"],
  ];
  return `<section class="review-desk" id="review-desk" data-review-status="${escapeHtml(review.status)}" style="--review-color:${reviewStatusColor(review.status)}">
    <header><div><small>Human review ledger</small><h3>Make the call</h3></div><span class="review-status-badge"><i></i>${escapeHtml(reviewStatusLabel(review.status))}</span></header>
    <div class="review-stamp" aria-hidden="true">${stamp}</div>
    <p class="review-intro">A film/design screening may be marked “Looks good.” Play the specimen locally or in VNC before approval. Neither state replaces the scripted verifier.</p>
    <form id="environment-review-form" data-environment="${escapeHtml(environment.id)}">
      <input type="hidden" name="status" value="${escapeHtml(review.status)}">
      <div class="review-choice-grid" role="group" aria-label="Review decision">
        ${choices.map(([status, glyph, label, detail]) => `<button class="review-choice ${review.status === status ? "is-active" : ""}" type="button" data-review-choice="${status}" aria-pressed="${review.status === status}"><i>${glyph}</i><span><b>${label}</b><small>${detail}</small></span></button>`).join("")}
      </div>
      <label class="review-note-field"><span>Review note <em>${review.status === "revision_requested" ? "required" : "optional"}</em></span><textarea name="note" maxlength="5000" ${review.status === "revision_requested" ? "required" : ""} placeholder="${review.status === "revision_requested" ? "Describe the exact interaction, feedback, physics, or usability change needed…" : "Record anything your future self should remember…"}">${escapeHtml(review.note)}</textarea><small><b data-review-note-count>${review.note.length}</b> / 5000</small></label>
      <div class="review-form-foot"><span>${escapeHtml(reviewTimestamp(review.updated_at))}</span><button class="button button-acid" type="submit">Save review ${arrowIcon}</button></div>
    </form>
    <details class="review-history-wrap" ${review.history?.length ? "" : "open"}><summary>Decision history <b>${review.history?.length || 0}</b></summary>${reviewHistoryMarkup(review)}</details>
  </section>`;
}

function renderEnvironmentDetail(environmentId) {
  const environment = findEnvironment(environmentId);
  if (!environment) {
    navigate("environments");
    return;
  }
  setChrome("environments", environment.title);
  const selectedIndex = Math.min(state.gallery[environment.id] || 0, Math.max(0, environment.screenshots.length - 1));
  const task = environment.tasks[0] || {};
  const validation = environment.validation || {};
  const review = reviewFor(environment.id);
  const archived = environment.stage === "rejected";
  const returnToReviews = state.environmentReturn === "reviews";
  const serverFeedback = validation.server_grade?.feedback || (validation.ok ? "Browser evidence present" : archived ? "Rejected infrastructure pilot" : "Not yet verified");
  const headerActions = environment.stage === "built" && environment.launchable
    ? `<div class="detail-actions"><button class="button button-review" type="button" data-action="open-review-desk" style="--review-color:${reviewStatusColor(review.status)}">Review · ${escapeHtml(reviewStatusShort(review.status))}</button><button class="button button-ghost" type="button" data-open-eval="${escapeHtml(environment.id)}">Evaluate</button><button class="button button-acid" type="button" data-config-launch="${escapeHtml(environment.id)}">Launch locally ${arrowIcon}</button></div>`
    : `<div class="archive-chip"><i></i>REJECTED INFRASTRUCTURE PILOT</div>`;
  const consoleMarkup = archived
    ? `<aside class="launch-console archive-console">
        <div class="launch-console-head"><span>Archive dossier</span><h3>Preserved, not runnable</h3></div>
        <div class="launch-console-body">
          <div class="console-row"><span>Collection</span><b>${escapeHtml(environment.group)}</b></div>
          <div class="console-row"><span>Source seeds</span><b>${environment.source_anchors.length}</b></div>
          <div class="console-row"><span>Historical surface</span><b>mouse / keyboard</b></div>
          <div class="console-row"><span>Disposition</span><b>tutorial-like pilot</b></div>
          <div class="archive-mark">ARCHIVE ONLY · EXCLUDED FROM BUILT CORPUS</div>
          <p class="console-note">This folder is retained as infrastructure history. It is not a benchmark candidate and is excluded from launch and evaluation pickers.</p>
        </div>
      </aside>`
    : `<aside class="launch-console">
        <div class="launch-console-head"><span>Runtime console</span><h3>Open the specimen</h3></div>
        <div class="launch-console-body">
          <div class="console-row"><span>Runner</span><b>${escapeHtml(state.system.runner)}</b></div>
          <div class="console-row"><span>Resolution</span><b>1280 × 720</b></div>
          <div class="console-row"><span>Tasks</span><b>${environment.task_count}</b></div>
          <div class="console-row"><span>Evidence</span><b>${environment.screenshots.length} frames</b></div>
          <div class="console-row"><span>Difficulty</span><b>${escapeHtml(environment.difficulty)}</b></div>
          ${validation.ok ? `<div class="validation-mark">WIRING REPLAY PASSED · HUMAN REVIEW PENDING</div>` : ""}
          <div class="console-actions"><button class="button button-acid button-wide" type="button" data-quick-launch="${escapeHtml(environment.id)}">One-click browser play ${arrowIcon}</button><button class="button button-ghost button-wide" type="button" data-config-launch="${escapeHtml(environment.id)}">Browser / VNC options</button><button class="button button-ghost button-wide" type="button" data-open-eval="${escapeHtml(environment.id)}">Prepare evaluation</button></div>
          <p class="console-note">Browser play starts the real task UI and grader on localhost. The launch dialog also preserves the isolated Gym-Anything VNC workflow.</p>
        </div>
      </aside>`;
  app.innerHTML = `
    <div class="page detail-page" style="--detail-accent:${escapeHtml(environment.accent)}">
      <button class="detail-back" type="button" data-action="${returnToReviews ? "back-to-reviews" : "back-to-environments"}">← ${returnToReviews ? "BACK TO REVIEW QUEUE" : "BACK TO COLLECTION"}</button>
      <header class="detail-header">
        <div><p class="eyebrow">${escapeHtml(environment.group)} / ${escapeHtml(environment.stage)}</p><h1 class="detail-title">${escapeHtml(environment.title)}</h1></div>
        ${headerActions}
      </header>
      <div class="detail-layout">
        <div class="detail-visual">
          <div id="detail-hero">${detailHero(environment, selectedIndex)}</div>
          ${environment.screenshots.length ? `<div class="filmstrip">${environment.screenshots.map((shot, index) => `<button type="button" class="${index === selectedIndex ? "is-active" : ""}" data-gallery-index="${index}" data-gallery-environment="${escapeHtml(environment.id)}" aria-label="View ${escapeHtml(shot.name)}"><img src="${escapeHtml(shot.url)}" alt="" loading="lazy"></button>`).join("")}</div>` : ""}

          ${solutionVideoMarkup(environment)}

          <div class="detail-copy-grid">
            <section><h2>What makes it difficult</h2><p>${escapeHtml(environment.summary)}</p><div class="tag-row" style="margin-top:18px">${environment.axes.map((axis) => `<span class="tag">${escapeHtml(axis)}</span>`).join("")}</div></section>
            <aside class="instruction-card"><small>Agent-visible instruction</small><blockquote>${escapeHtml(environment.instruction || "No instruction recorded.")}</blockquote></aside>
          </div>

          ${environment.known_limitations?.length ? `<aside class="fidelity-note"><div><small>Known fidelity boundary</small><b>Do not mistake this verifier for open-world judgment.</b></div><p>${environment.known_limitations.map((limitation) => escapeHtml(limitation)).join(" ")}</p></aside>` : ""}

          <section class="detail-section"><h2>Environment contract</h2><div class="contract-list">
            <div class="contract-item"><small>Task identity</small><b>${escapeHtml(task.id || "No task yet")}</b></div>
            <div class="contract-item"><small>Interaction surface</small><b>Screenshot + mouse / keyboard</b></div>
            <div class="contract-item"><small>Validation</small><b>${escapeHtml(serverFeedback)}</b></div>
            <div class="contract-item"><small>Human test state</small><b>${escapeHtml(titleCase(environment.human_status))}</b></div>
            <div class="contract-item"><small>Acceptance review</small><b id="detail-review-state" style="color:${reviewStatusColor(review.status)}">${escapeHtml(reviewStatusLabel(review.status))}</b></div>
            <div class="contract-item"><small>Source anchor</small><b>${escapeHtml(environment.source_anchors[0] || "Internal incubator")}</b></div>
            <div class="contract-item"><small>Environment spec</small><b>${escapeHtml(environment.spec_id)}</b></div>
          </div></section>
        </div>

        <div class="detail-side">${consoleMarkup}${environment.stage === "built" ? reviewDeskMarkup(environment) : ""}</div>
      </div>
    </div>`;
}

function sessionStatusLabel(status) {
  return {queued: "queued", booting: "booting", running: "live", stopping: "stopping", stopped: "stopped", failed: "failed"}[status] || status;
}

function sessionCard(session) {
  const info = session.session || {};
  const active = ["queued", "booting", "running", "stopping"].includes(session.status);
  const running = session.status === "running";
  const browserSession = session.kind === "browser";
  const address = running
    ? browserSession ? info.browser_url : info.vnc_port ? `localhost::${info.vnc_port}` : session.phase_message
    : session.phase_message;
  const connectionLabel = running ? browserSession ? "Local browser URL" : "TigerVNC address" : active ? "Runner state" : "Final state";
  const logsExpanded = state.expandedLogs.has(session.id);
  return `<article class="session-card" data-session-id="${escapeHtml(session.id)}" data-status="${escapeHtml(session.status)}" style="--status-color:${statusColor(session.status)}">
    <div class="session-main">
      <div><div class="session-title-row"><i class="session-beacon"></i><h3>${escapeHtml(session.title)}</h3><span class="status-pill" style="--status-color:${statusColor(session.status)}">${escapeHtml(sessionStatusLabel(session.status))}</span></div><p class="session-meta">${escapeHtml(session.task_id)} · seed ${session.seed}<span data-session-uptime>${session.uptime_seconds != null ? ` · ${elapsedLabel(session.uptime_seconds)}` : ""}</span></p></div>
      <div class="session-connection"><small>${connectionLabel}</small><code>${escapeHtml(address)}</code>${running && info.vnc_password ? `<small>Password · ${escapeHtml(info.vnc_password)}</small>` : ""}</div>
      <div class="session-actions">
        ${session.status === "running" ? `<button class="button button-acid button-small" type="button" data-open-session="${session.id}" data-session-kind="${escapeHtml(session.kind)}">${browserSession ? "Open puzzle" : "Open VNC"}</button><button class="button button-ghost button-small" type="button" data-copy="${escapeHtml(address)}">Copy</button>` : ""}
        <button class="button button-ghost button-small" type="button" data-toggle-logs="${session.id}">${logsExpanded ? "Hide" : "Logs"}</button>
        ${active ? `<button class="button button-danger button-small" type="button" data-stop-session="${session.id}">Stop</button>` : ""}
      </div>
    </div>
    <div class="session-progress"><i></i></div>
    ${logsExpanded ? `<pre class="session-logs" data-session-logs>${escapeHtml((session.logs || []).join("\n") || "Waiting for runner output…")}</pre>` : ""}
  </article>`;
}

function sessionCounts() {
  return {
    active: state.sessions.filter((session) => ["queued", "booting", "running", "stopping"].includes(session.status)).length,
    ready: state.sessions.filter((session) => session.status === "running").length,
    browser: state.sessions.filter((session) => session.status === "running" && session.kind === "browser").length,
    stopped: state.sessions.filter((session) => ["stopped", "failed"].includes(session.status)).length,
  };
}

function sessionListSignature() {
  return JSON.stringify(state.sessions.map((session) => [
    session.id,
    session.kind,
    session.status,
    session.phase_message,
    session.task_id,
    session.seed,
    session.viewer_opened,
    session.session,
    state.expandedLogs.has(session.id),
  ]));
}

function sessionListMarkup() {
  return state.sessions.length
    ? state.sessions.map(sessionCard).join("")
    : `<div class="empty-state"><div class="empty-state-mark"></div><h2>No specimens are awake.</h2><p>Launch any built environment directly in your browser, or choose an isolated VNC guest from the launch dialog.</p><button class="button button-acid" type="button" data-action="open-launch-picker">Choose an environment</button></div>`;
}

function syncLogElement(element, text) {
  if (!element || element.textContent === text) return;
  const followTail = element.scrollHeight - element.scrollTop - element.clientHeight < 18;
  const previousTop = element.scrollTop;
  element.textContent = text;
  element.scrollTop = followTail ? element.scrollHeight : previousTop;
}

function refreshSessionsPage({forceList = false} = {}) {
  const page = document.querySelector(".sessions-page");
  const list = document.getElementById("session-list");
  if (!page || !list) return;
  const counts = sessionCounts();
  document.getElementById("session-active-count").textContent = counts.active;
  document.getElementById("session-ready-count").textContent = counts.ready;
  const readyNote = document.getElementById("session-ready-note");
  if (readyNote) readyNote.textContent = `${counts.browser} browser · ${Math.max(0, counts.ready - counts.browser)} VNC`;
  document.getElementById("session-history-count").textContent = state.sessions.length;
  document.getElementById("session-history-note").textContent = `${counts.stopped} completed / failed`;

  const signature = sessionListSignature();
  if (forceList || list.dataset.signature !== signature) {
    list.innerHTML = sessionListMarkup();
    list.dataset.signature = signature;
  }
  state.sessions.forEach((session) => {
    const card = list.querySelector(`[data-session-id="${CSS.escape(session.id)}"]`);
    if (!card) return;
    const uptime = card.querySelector("[data-session-uptime]");
    if (uptime) uptime.textContent = session.uptime_seconds != null ? ` · ${elapsedLabel(session.uptime_seconds)}` : "";
    syncLogElement(card.querySelector("[data-session-logs]"), (session.logs || []).join("\n") || "Waiting for runner output…");
  });
}

function renderSessions() {
  setChrome("sessions", "Live sessions");
  const counts = sessionCounts();
  app.innerHTML = `<div class="page sessions-page">
    <header class="page-head"><div><p class="eyebrow">Runtime control</p><h1 class="page-title">Live specimens.</h1><p class="page-copy">Open puzzles as ordinary localhost browser apps, or boot an isolated Gym-Anything guest for VNC inspection. Every process stays on this computer.</p></div><div class="page-head-actions"><button class="button button-acid" type="button" data-action="open-launch-picker">New local session ${arrowIcon}</button></div></header>
    <section class="summary-cards"><div class="summary-card"><small>Active sessions</small><b id="session-active-count">${counts.active}</b><span>booting or live</span></div><div class="summary-card"><small>Ready now</small><b id="session-ready-count">${counts.ready}</b><span id="session-ready-note">${counts.browser} browser · ${Math.max(0, counts.ready - counts.browser)} VNC</span></div><div class="summary-card"><small>Runner</small><b style="font-size:25px">${escapeHtml(state.system.runner)}</b><span>local execution backend</span></div><div class="summary-card"><small>Session history</small><b id="session-history-count">${state.sessions.length}</b><span id="session-history-note">${counts.stopped} completed / failed</span></div></section>
    <section class="session-list" id="session-list">${sessionListMarkup()}</section>
  </div>`;
  document.getElementById("session-list").dataset.signature = sessionListSignature();
}

function evaluationRow(job) {
  const expanded = state.expandedLogs.has(`eval-${job.id}`);
  return `<div class="eval-row" data-evaluation-id="${escapeHtml(job.id)}">
    <div class="eval-name"><b>${escapeHtml(job.title)}</b><small>${escapeHtml(job.task_id)}</small></div>
    <div class="eval-model">${escapeHtml(job.agent)}</div>
    <div class="eval-model">${escapeHtml(job.model)}</div>
    <div><span class="status-pill" style="--status-color:${statusColor(job.status)}">${escapeHtml(job.status)}</span></div>
    <div><button class="button button-ghost button-small" type="button" data-toggle-eval="${job.id}">${expanded ? "Hide" : "Inspect"}</button></div>
    ${expanded ? `<pre class="eval-command" data-evaluation-logs>${escapeHtml(evaluationLogText(job))}</pre>` : ""}
  </div>`;
}

function evaluationLogText(job) {
  return `${job.command}${job.logs?.length > 1 ? `\n\n${job.logs.slice(1).join("\n")}` : ""}`;
}

function evaluationCounts() {
  return {
    active: state.evaluations.filter((job) => ["queued", "running", "canceling"].includes(job.status)).length,
    complete: state.evaluations.filter((job) => job.status === "completed").length,
    previews: state.evaluations.filter((job) => job.status === "preview").length,
  };
}

function evaluationListSignature() {
  return JSON.stringify(state.evaluations.map((job) => [
    job.id,
    job.status,
    job.returncode,
    job.completed_at,
    job.title,
    job.task_id,
    job.agent,
    job.model,
    job.command,
    state.expandedLogs.has(`eval-${job.id}`),
  ]));
}

function evaluationListMarkup() {
  return state.evaluations.length
    ? `<section class="eval-table"><div class="eval-row eval-head"><div>Environment</div><div>Agent</div><div>Model</div><div>Status</div><div>Details</div></div>${state.evaluations.map(evaluationRow).join("")}</section>`
    : `<div class="empty-state"><div class="empty-state-mark"></div><h2>No evaluation runs yet.</h2><p>Prepare a command preview first. When the agent, model endpoint, and credentials are ready, disable preview mode to execute the exact same job.</p><button class="button button-acid" type="button" data-action="open-eval-picker">Prepare first evaluation</button></div>`;
}

function refreshEvaluationsPage({forceList = false} = {}) {
  const page = document.querySelector(".evaluations-page");
  const list = document.getElementById("evaluation-list");
  if (!page || !list) return;
  const counts = evaluationCounts();
  document.getElementById("evaluation-active-count").textContent = counts.active;
  document.getElementById("evaluation-complete-count").textContent = counts.complete;
  document.getElementById("evaluation-preview-count").textContent = counts.previews;
  document.getElementById("evaluation-total-count").textContent = state.evaluations.length;

  const signature = evaluationListSignature();
  if (forceList || list.dataset.signature !== signature) {
    list.innerHTML = evaluationListMarkup();
    list.dataset.signature = signature;
  }
  state.evaluations.forEach((job) => {
    const row = list.querySelector(`[data-evaluation-id="${CSS.escape(job.id)}"]`);
    syncLogElement(row?.querySelector("[data-evaluation-logs]"), evaluationLogText(job));
  });
}

function renderEvaluations() {
  setChrome("evaluations", "Evaluations");
  const counts = evaluationCounts();
  app.innerHTML = `<div class="page evaluations-page">
    <header class="page-head"><div><p class="eyebrow">Model evaluation</p><h1 class="page-title">Run the machines<br>against machines.</h1><p class="page-copy">The same environment identity drives human VNC inspection and agent evaluation. Preview mode is safe by default; executing a run uses the existing Gym-Anything benchmark CLI and your configured model credentials.</p></div><div class="page-head-actions"><button class="button button-acid" type="button" data-action="open-eval-picker">New evaluation ${arrowIcon}</button></div></header>
    <section class="summary-cards"><div class="summary-card"><small>Active evals</small><b id="evaluation-active-count">${counts.active}</b><span>running or queued</span></div><div class="summary-card"><small>Successful</small><b id="evaluation-complete-count">${counts.complete}</b><span>completed with code 0</span></div><div class="summary-card"><small>Command previews</small><b id="evaluation-preview-count">${counts.previews}</b><span>no model calls made</span></div><div class="summary-card"><small>Total jobs</small><b id="evaluation-total-count">${state.evaluations.length}</b><span>this dashboard process</span></div></section>
    <div id="evaluation-list">${evaluationListMarkup()}</div>
  </div>`;
  document.getElementById("evaluation-list").dataset.signature = evaluationListSignature();
}

function render() {
  if (!state.catalog || !state.reviews || !state.system) return;
  state.route = parseRoute();
  if (state.route.name === "observatory") renderObservatory();
  else if (state.route.name === "environments") renderEnvironments();
  else if (state.route.name === "reviews") renderReviewQueue();
  else if (state.route.name === "environment") renderEnvironmentDetail(state.route.id);
  else if (state.route.name === "sessions") renderSessions();
  else if (state.route.name === "evaluations") renderEvaluations();
  updateCounts();
  window.scrollTo({top: 0, behavior: "instant"});
}

function modalShell(content, className = "") {
  modalRoot.innerHTML = `<div class="modal-backdrop" data-action="close-modal"><section class="modal ${className}" role="dialog" aria-modal="true">${content}</section></div>`;
}

function closeModal() {
  modalRoot.innerHTML = "";
}

function companionCommand() {
  const origin = location.origin === "null" ? "null" : location.origin;
  return `PYTHONPATH=src python benchmarks/weird_captcha_gym/dashboard/server.py --companion --allow-origin ${origin}`;
}

function openCompanionDialog() {
  const connected = state.companion.connected;
  const statusCopy = connected
    ? `Connected to ${escapeHtml(config.companionUrl || "this dashboard server")}. Launches, reviews, VNC sessions, and evaluations run on this computer.`
    : `Start the loopback-only helper from a CAPTCHA Bench checkout, then paste the pairing key printed in that terminal. This frontend stores it in this browser and sends it only to the localhost companion. If your browser asks for Local Network Access, choose Allow.`;
  modalShell(`<header class="modal-head"><div><small>Local execution boundary</small><h2>${connected ? "Companion connected" : "Pair this computer"}</h2></div><button class="modal-close" type="button" data-action="close-modal" aria-label="Close">×</button></header><div class="modal-body companion-dialog">
    <div class="modal-callout">${statusCopy}</div>
    <div class="companion-endpoint"><small>LOOPBACK ENDPOINT</small><code>${escapeHtml(config.companionUrl || location.origin)}</code><span class="status-pill" style="--status-color:${connected ? "#d7ff54" : "#ffc857"}">${connected ? "connected" : escapeHtml(state.companion.status)}</span></div>
    ${config.mode === "shared" ? `<div class="companion-command"><small>RUN FROM THE REPOSITORY ROOT</small><code>${escapeHtml(companionCommand())}</code><button class="button button-ghost button-small" type="button" data-copy="${escapeHtml(companionCommand())}">Copy command</button></div>
    <form id="companion-form" class="companion-pair-form"><div class="form-field"><label for="companion-token">Pairing key</label><input id="companion-token" name="token" value="${escapeHtml(state.companion.token)}" autocomplete="off" spellcheck="false" placeholder="Paste the key printed by the companion"></div><div class="modal-actions"><button class="button button-ghost" type="button" data-action="forget-companion">Forget key</button><button class="button button-acid" type="submit">${connected ? "Reconnect" : "Connect companion"} ${arrowIcon}</button></div></form>` : `<div class="companion-command"><small>LOCAL DASHBOARD MODE</small><p>This page and its execution API already share one localhost origin; no pairing key is needed.</p></div>`}
    ${state.companion.error ? `<p class="companion-error">${escapeHtml(state.companion.error)}</p>` : ""}
  </div>`);
}

function ensureCompanion() {
  if (state.companion.connected) return true;
  openCompanionDialog();
  return false;
}

async function connectCompanion({interactive = false} = {}) {
  state.companion.lastAttempt = Date.now();
  state.companion.status = "checking";
  state.companion.error = "";
  updateCounts();
  try {
    await api("/api/health");
    const [reviews, system, sessions, evaluations] = await Promise.all([
      api("/api/reviews"),
      api("/api/system"),
      api("/api/sessions"),
      api("/api/evaluations"),
    ]);
    state.reviews = reviews;
    state.system = system;
    state.sessions = sessions.sessions || [];
    state.evaluations = evaluations.evaluations || [];
    state.companion.connected = true;
    state.companion.status = "connected";
    state.sessions.forEach((session) => state.previousSessionStatus.set(session.id, session.status));
    updateCounts();
    if (interactive) {
      closeModal();
      render();
      toast("Local companion connected", "Launches and controls now operate on this computer.", "success");
    }
    return true;
  } catch (error) {
    state.companion.connected = false;
    state.companion.status = error.status === 401 ? "pairing required" : "offline";
    state.companion.error = error.status === 401
      ? "The pairing key was rejected. Copy the exact key from the companion terminal."
      : `Could not reach the local companion: ${error.message}`;
    updateCounts();
    if (interactive) openCompanionDialog();
    return false;
  }
}

function openLaunchDialog(environment) {
  if (!ensureCompanion()) return;
  const taskOptions = environment.tasks.map((task) => `<option value="${escapeHtml(task.id)}">${escapeHtml(task.id)}</option>`).join("");
  modalShell(`<header class="modal-head"><div><small>Launch environment</small><h2>${escapeHtml(environment.title)}</h2></div><button class="modal-close" type="button" data-action="close-modal" aria-label="Close">×</button></header><form class="modal-body" id="launch-form" data-environment="${escapeHtml(environment.id)}">
    <div class="modal-callout">Browser mode starts the task's real local UI and grader immediately on localhost. VNC mode keeps the existing isolated ${escapeHtml(state.system.runner.toUpperCase())} workflow for runner-faithful inspection.</div>
    <div class="form-grid">
      <div class="form-field is-wide"><label for="launch-task">Task</label><select id="launch-task" name="task_id">${taskOptions}</select></div>
      <div class="form-field is-wide"><label for="launch-mode">Launch mode</label><select id="launch-mode" name="mode"><option value="browser" selected>Local browser · instant</option><option value="vnc">Isolated VNC guest · ${escapeHtml(state.system.runner)}</option></select></div>
      <div class="form-field"><label for="launch-seed">Seed</label><input id="launch-seed" name="seed" type="number" min="0" max="2147483647" value="${Math.floor(Math.random() * 1_000_000)}"></div>
      <div class="form-field"><label>Runner</label><input value="${escapeHtml(state.system.runner)}" disabled></div>
    </div>
    <div class="switch-row" style="margin-top:17px"><div class="switch-copy"><b>Open automatically</b><span>The companion opens the browser tab or VNC viewer as soon as the selected runtime is ready.</span></div><label class="switch"><input name="auto_open" type="checkbox" checked><i></i></label></div>
    <div class="modal-actions"><button class="button button-ghost" type="button" data-action="close-modal">Cancel</button><button class="button button-acid" type="submit">Launch specimen ${arrowIcon}</button></div>
  </form>`);
}

function openEvalDialog(environment) {
  if (!ensureCompanion()) return;
  const taskOptions = environment.tasks.map((task) => `<option value="${escapeHtml(task.id)}">${escapeHtml(task.id)}</option>`).join("");
  const agentOptions = state.system.agents.map((agent) => `<option value="${escapeHtml(agent)}" ${agent === "Qwen3VLAgent" ? "selected" : ""}>${escapeHtml(agent)}</option>`).join("");
  modalShell(`<header class="modal-head"><div><small>Evaluation job</small><h2>${escapeHtml(environment.title)}</h2></div><button class="modal-close" type="button" data-action="close-modal" aria-label="Close">×</button></header><form class="modal-body" id="eval-form" data-environment="${escapeHtml(environment.id)}">
    <div class="modal-callout">Preview mode generates the exact command without starting a VM or calling a model. Disable it only when the selected agent's provider credentials are configured.</div>
    <div class="form-grid">
      <div class="form-field is-wide"><label for="eval-task">Task</label><select id="eval-task" name="task_id">${taskOptions}</select></div>
      <div class="form-field"><label for="eval-agent">Agent</label><select id="eval-agent" name="agent">${agentOptions}</select></div>
      <div class="form-field"><label for="eval-model">Model</label><input id="eval-model" name="model" value="qwen3-vl" autocomplete="off"></div>
      <div class="form-field"><label for="eval-steps">Max steps</label><input id="eval-steps" name="steps" type="number" min="1" max="1000" value="50"></div>
      <div class="form-field"><label for="eval-seed">Seed</label><input id="eval-seed" name="seed" type="number" min="0" value="42"></div>
      <div class="form-field is-wide"><label for="eval-experiment">Experiment name</label><input id="eval-experiment" name="experiment" value="captcha-hub-${new Date().toISOString().slice(0, 10).replaceAll("-", "")}" autocomplete="off"></div>
    </div>
    <div class="switch-row" style="margin-top:17px"><div class="switch-copy"><b>Preview command only</b><span>Recommended until the model endpoint and API credentials are ready. No evaluation process will start.</span></div><label class="switch"><input name="preview_only" type="checkbox" checked><i></i></label></div>
    <div class="switch-row"><div class="switch-copy"><b>Use runner fast I/O</b><span>Enable the runner-native screenshot and input path for lower interaction latency.</span></div><label class="switch"><input name="fast_io" type="checkbox"><i></i></label></div>
    <div class="modal-actions"><button class="button button-ghost" type="button" data-action="close-modal">Cancel</button><button class="button button-acid" type="submit">Prepare evaluation ${arrowIcon}</button></div>
  </form>`);
}

function openLaunchPicker() {
  openCommandPalette("launch");
}

function openEvalPicker() {
  openCommandPalette("eval");
}

function openCommandPalette(mode = "browse") {
  const built = state.catalog.environments.filter((environment) => environment.stage === "built");
  modalShell(`<section class="command-palette"><div class="palette-search"><input id="palette-input" type="search" placeholder="Find motion, physics, memory…" autocomplete="off" aria-label="Search environment catalog"></div><div class="palette-results" id="palette-results">${paletteItems(built, mode)}</div></section>`, "command-palette");
  const input = document.getElementById("palette-input");
  input.focus();
  input.addEventListener("input", () => {
    const query = input.value.trim().toLowerCase();
    const matches = built.filter((environment) => [environment.title, environment.summary, ...environment.axes].join(" ").toLowerCase().includes(query));
    document.getElementById("palette-results").innerHTML = paletteItems(matches, mode);
  });
}

function paletteItems(environments, mode) {
  if (!environments.length) return `<div class="empty-catalog" style="min-height:160px"><b>No matches.</b></div>`;
  return environments.map((environment) => `<button class="palette-item" type="button" data-palette-mode="${mode}" data-palette-environment="${escapeHtml(environment.id)}"><span class="palette-thumb">${coverMarkup(environment)}</span><span><b>${escapeHtml(environment.title)}</b><span>${escapeHtml(environment.axes.join(" · "))}</span></span><em>${mode === "launch" ? "launch ↗" : mode === "eval" ? "evaluate ↗" : "open ↗"}</em></button>`).join("");
}

async function quickLaunch(environmentId) {
  const environment = findEnvironment(environmentId);
  if (!environment || !environment.tasks.length) return;
  if (!ensureCompanion()) return;
  toast("Local launch requested", `${environment.title} is preparing in your browser.`, "info");
  try {
    const session = await api("/api/sessions", {method: "POST", body: JSON.stringify({environment_id: environment.id, task_id: environment.tasks[0].id, seed: Math.floor(Math.random() * 1_000_000), mode: "browser", auto_open: true})});
    state.sessions.unshift(session);
    updateCounts();
    navigate("sessions");
  } catch (error) {
    toast("Could not launch", error.message, "error");
  }
}

async function submitLaunch(form) {
  const button = form.querySelector('[type="submit"]');
  button.disabled = true;
  button.textContent = "Starting…";
  const data = new FormData(form);
  try {
    const mode = String(data.get("mode") || "browser");
    const session = await api("/api/sessions", {method: "POST", body: JSON.stringify({environment_id: form.dataset.environment, task_id: data.get("task_id"), seed: Number(data.get("seed")), mode, auto_open: data.get("auto_open") === "on"})});
    state.sessions.unshift(session);
    closeModal();
    toast("Environment queued", mode === "browser" ? "A local browser tab will open when the puzzle is ready." : "TigerVNC will open when the guest is ready.", "success");
    if (parseRoute().name === "sessions") refreshSessionsPage({forceList: true});
    else navigate("sessions");
  } catch (error) {
    button.disabled = false;
    button.innerHTML = `Launch specimen ${arrowIcon}`;
    toast("Could not launch", error.message, "error");
  }
}

async function submitEvaluation(form) {
  if (!ensureCompanion()) return;
  const button = form.querySelector('[type="submit"]');
  button.disabled = true;
  button.textContent = "Preparing…";
  const data = new FormData(form);
  const payload = {
    environment_id: form.dataset.environment,
    task_id: data.get("task_id"),
    agent: data.get("agent"),
    model: data.get("model"),
    steps: Number(data.get("steps")),
    seed: Number(data.get("seed")),
    experiment: data.get("experiment"),
    preview_only: data.get("preview_only") === "on",
    fast_io: data.get("fast_io") === "on",
  };
  try {
    const job = await api("/api/evaluations", {method: "POST", body: JSON.stringify(payload)});
    state.evaluations.unshift(job);
    state.expandedLogs.add(`eval-${job.id}`);
    closeModal();
    toast(job.status === "preview" ? "Command preview ready" : "Evaluation started", job.status === "preview" ? "No VM or model call was made." : `${job.agent} is now running.`, job.status === "preview" ? "info" : "success");
    if (parseRoute().name === "evaluations") refreshEvaluationsPage({forceList: true});
    else navigate("evaluations");
  } catch (error) {
    button.disabled = false;
    button.innerHTML = `Prepare evaluation ${arrowIcon}`;
    toast("Could not prepare evaluation", error.message, "error");
  }
}

function selectReviewChoice(button) {
  const form = button.closest("form");
  const desk = button.closest(".review-desk");
  if (!form || !desk) return;
  const status = button.dataset.reviewChoice;
  const hidden = form.querySelector('[name="status"]');
  const textarea = form.querySelector('[name="note"]');
  hidden.value = status;
  desk.dataset.reviewStatus = status;
  desk.style.setProperty("--review-color", reviewStatusColor(status));
  desk.classList.add("is-dirty");
  form.querySelectorAll("[data-review-choice]").forEach((choice) => {
    const active = choice.dataset.reviewChoice === status;
    choice.classList.toggle("is-active", active);
    choice.setAttribute("aria-pressed", String(active));
  });
  const badge = desk.querySelector(".review-status-badge");
  if (badge) badge.innerHTML = `<i></i>${escapeHtml(reviewStatusLabel(status))}`;
  const stamp = desk.querySelector(".review-stamp");
  if (stamp) stamp.textContent = {pending: "UNREVIEWED", looks_good: "PROMISING", approved: "APPROVED", revision_requested: "REVISE"}[status];
  const requirement = desk.querySelector(".review-note-field em");
  if (requirement) requirement.textContent = status === "revision_requested" ? "required" : "optional";
  textarea.required = status === "revision_requested";
  textarea.placeholder = status === "revision_requested"
    ? "Describe the exact interaction, feedback, physics, or usability change needed…"
    : "Record anything your future self should remember…";
  textarea.setCustomValidity("");
  const saved = desk.querySelector(".review-form-foot span");
  if (saved) saved.textContent = "Unsaved decision";
}

async function submitEnvironmentReview(form) {
  if (!ensureCompanion()) return;
  const environment = findEnvironment(form.dataset.environment);
  if (!environment) return;
  const data = new FormData(form);
  const status = String(data.get("status") || "pending");
  const note = String(data.get("note") || "").trim();
  const textarea = form.querySelector('[name="note"]');
  if (status === "revision_requested" && !note) {
    textarea.setCustomValidity("Describe the revision you want before saving.");
    textarea.reportValidity();
    return;
  }
  textarea.setCustomValidity("");
  const button = form.querySelector('[type="submit"]');
  button.disabled = true;
  button.textContent = "Saving decision…";
  try {
    const response = await api(`/api/reviews/${encodeURIComponent(environment.id)}`, {
      method: "POST",
      body: JSON.stringify({status, note}),
    });
    state.reviews.items[environment.id] = response.review;
    state.reviews.stats = response.stats;
    updateCounts();
    const contract = document.getElementById("detail-review-state");
    if (contract) {
      contract.textContent = reviewStatusLabel(response.review.status);
      contract.style.color = reviewStatusColor(response.review.status);
    }
    const reviewButton = document.querySelector('[data-action="open-review-desk"]');
    if (reviewButton) {
      reviewButton.textContent = `Review · ${reviewStatusShort(response.review.status)}`;
      reviewButton.style.setProperty("--review-color", reviewStatusColor(response.review.status));
    }
    const desk = document.getElementById("review-desk");
    if (desk) desk.outerHTML = reviewDeskMarkup(environment);
    const tone = response.review.status === "revision_requested" ? "warn" : response.review.status === "approved" ? "success" : "info";
    toast(reviewStatusLabel(response.review.status), response.review.status === "revision_requested" ? "Revision feedback is now in the human review ledger." : `${environment.title} review saved.`, tone);
  } catch (error) {
    button.disabled = false;
    button.innerHTML = `Save review ${arrowIcon}`;
    toast("Could not save review", error.message, "error");
  }
}

async function pollJobs() {
  if (!state.companion.connected) {
    if (Date.now() - state.companion.lastAttempt > 5000 && (config.mode === "local" || state.companion.token)) {
      if (await connectCompanion()) render();
    }
    return;
  }
  try {
    const [sessionPayload, evaluationPayload] = await Promise.all([api("/api/sessions"), api("/api/evaluations")]);
    const nextSessions = sessionPayload.sessions || [];
    nextSessions.forEach((session) => {
      const previous = state.previousSessionStatus.get(session.id);
      if (previous && previous !== "running" && session.status === "running") {
        const destination = session.kind === "browser" ? session.session?.browser_url : `localhost::${session.session?.vnc_port}`;
        toast(session.kind === "browser" ? "Browser puzzle is ready" : "VNC is ready", `${session.title} is live at ${destination}.`, "success", 7000);
      }
      if (previous && !["failed", "stopped"].includes(previous) && session.status === "failed") toast("Environment failed", session.phase_message, "error", 7500);
      state.previousSessionStatus.set(session.id, session.status);
    });
    state.sessions = nextSessions;
    state.evaluations = evaluationPayload.evaluations || [];
    updateCounts();
    const route = parseRoute();
    if (route.name === "sessions") refreshSessionsPage();
    if (route.name === "evaluations") refreshEvaluationsPage();
  } catch (_error) {
    // A transient poll error should not replace the current UI.
  }
}

document.addEventListener("click", async (event) => {
  const target = event.target.closest("button, [data-open-env], [data-nav], [data-action]");
  if (!target) return;
  if (target.dataset.reviewChoice) { selectReviewChoice(target); return; }
  if (target.dataset.reviewFilter) { state.reviewFilters.status = target.dataset.reviewFilter; refreshReviewQueue(); return; }
  if (target.dataset.quickLaunch) { event.stopPropagation(); await quickLaunch(target.dataset.quickLaunch); return; }
  if (target.dataset.configLaunch) { const environment = findEnvironment(target.dataset.configLaunch); if (environment) openLaunchDialog(environment); return; }
  if (target.dataset.openEval) { const environment = findEnvironment(target.dataset.openEval); if (environment) openEvalDialog(environment); return; }
  if (target.dataset.openSession) {
    const browserSession = target.dataset.sessionKind === "browser";
    try { await api(`/api/sessions/${target.dataset.openSession}/open`, {method: "POST", body: "{}"}); toast(browserSession ? "Opening local puzzle" : "Opening TigerVNC", browserSession ? "The task is opening in your default browser." : "Use the password from the session card.", "success"); } catch (error) { toast("Could not open session", error.message, "error"); }
    return;
  }
  if (target.dataset.stopSession) {
    try { await api(`/api/sessions/${target.dataset.stopSession}/stop`, {method: "POST", body: "{}"}); toast("Stopping environment", "The local process and its loopback ports are being cleaned up.", "warn"); await pollJobs(); } catch (error) { toast("Could not stop", error.message, "error"); }
    return;
  }
  if (target.dataset.toggleLogs) {
    state.expandedLogs.has(target.dataset.toggleLogs) ? state.expandedLogs.delete(target.dataset.toggleLogs) : state.expandedLogs.add(target.dataset.toggleLogs);
    refreshSessionsPage({forceList: true}); return;
  }
  if (target.dataset.toggleEval) {
    const key = `eval-${target.dataset.toggleEval}`;
    state.expandedLogs.has(key) ? state.expandedLogs.delete(key) : state.expandedLogs.add(key);
    refreshEvaluationsPage({forceList: true}); return;
  }
  if (target.dataset.copy) {
    try { await navigator.clipboard.writeText(target.dataset.copy); toast("Copied", target.dataset.copy, "info"); } catch (_error) { toast("Copy unavailable", target.dataset.copy, "warn"); }
    return;
  }
  if (target.dataset.galleryIndex != null) {
    selectDetailFrame(target.dataset.galleryEnvironment, Number(target.dataset.galleryIndex)); return;
  }
  if (target.dataset.filterGroup) {
    state.filters.group = target.dataset.filterGroup;
    const stageStillMatches = state.filters.group === "All" || state.filters.stage === "all" || state.catalog.environments.some((environment) => environment.group === state.filters.group && environment.stage === state.filters.stage);
    if (!stageStillMatches) state.filters.stage = "all";
    refreshEnvironmentCatalog(); return;
  }
  if (target.dataset.view) { state.filters.view = target.dataset.view; refreshEnvironmentCatalog({rebuild: false}); return; }
  if (target.dataset.paletteEnvironment) {
    const environment = findEnvironment(target.dataset.paletteEnvironment);
    const mode = target.dataset.paletteMode;
    closeModal();
    if (mode === "launch") openLaunchDialog(environment);
    else if (mode === "eval") openEvalDialog(environment);
    else navigate(`environment/${environment.id}`);
    return;
  }
  if (target.dataset.action) {
    const action = target.dataset.action;
    if (action === "close-modal") {
      if (event.target.classList.contains("modal-backdrop") || target.classList.contains("modal-close") || target.closest("form")) closeModal();
    } else if (action === "open-companion") openCompanionDialog();
    else if (action === "forget-companion") {
      localStorage.removeItem(companionTokenKey);
      state.companion.token = "";
      state.companion.connected = false;
      state.companion.status = "pairing required";
      state.companion.error = "";
      openCompanionDialog();
      updateCounts();
    } else if (action === "open-launch-picker") {
      if (ensureCompanion()) openLaunchPicker();
    }
    else if (action === "open-eval-picker") {
      if (ensureCompanion()) openEvalPicker();
    }
    else if (action === "browse-environments" || action === "back-to-environments") navigate("environments");
    else if (action === "back-to-reviews") navigate("reviews");
    else if (action === "open-review-desk") document.getElementById("review-desk")?.scrollIntoView({behavior: "smooth", block: "start"});
    return;
  }
  if (target.dataset.openEnv) {
    state.environmentReturn = parseRoute().name === "reviews" ? "reviews" : "environments";
    navigate(`environment/${target.dataset.openEnv}`);
  }
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") { event.preventDefault(); openCommandPalette("browse"); }
  if (event.key === "Escape" && modalRoot.innerHTML) closeModal();
  const card = event.target.closest('[data-open-env][role="button"]');
  if (card && ["Enter", " "].includes(event.key)) { event.preventDefault(); navigate(`environment/${card.dataset.openEnv}`); }
});

document.addEventListener("input", (event) => {
  if (event.target.id === "environment-search") {
    state.filters.query = event.target.value;
    refreshEnvironmentCatalog();
  }
  if (event.target.id === "review-search") {
    state.reviewFilters.query = event.target.value;
    refreshReviewQueue();
  }
  if (event.target.matches('#environment-review-form [name="note"]')) {
    event.target.setCustomValidity("");
    const count = event.target.closest("form")?.querySelector("[data-review-note-count]");
    if (count) count.textContent = event.target.value.length;
  }
});

document.addEventListener("change", (event) => {
  if (event.target.id === "stage-filter") { state.filters.stage = event.target.value; refreshEnvironmentCatalog(); }
  if (event.target.id === "review-filter") { state.filters.review = event.target.value; refreshEnvironmentCatalog(); }
});

document.addEventListener("submit", (event) => {
  if (event.target.id === "launch-form") { event.preventDefault(); submitLaunch(event.target); }
  if (event.target.id === "eval-form") { event.preventDefault(); submitEvaluation(event.target); }
  if (event.target.id === "companion-form") {
    event.preventDefault();
    state.companion.token = String(new FormData(event.target).get("token") || "").trim();
    if (state.companion.token) localStorage.setItem(companionTokenKey, state.companion.token);
    else localStorage.removeItem(companionTokenKey);
    connectCompanion({interactive: true});
  }
  if (event.target.id === "environment-review-form") { event.preventDefault(); submitEnvironmentReview(event.target); }
});

document.getElementById("global-search-button").addEventListener("click", () => openCommandPalette("browse"));
document.querySelector(".mobile-nav-toggle").addEventListener("click", () => document.body.classList.toggle("nav-open"));
window.addEventListener("hashchange", render);

async function init() {
  try {
    state.catalog = await loadCatalog();
    state.reviews = emptyReviewSnapshot(state.catalog);
    state.system = {runner: "offline", agents: [], platform: "local", repo_root: "Companion not connected", review_path: "Companion not connected"};
    await connectCompanion();
    if (!location.hash) history.replaceState(null, "", "#/observatory");
    render();
    window.setInterval(pollJobs, 1600);
  } catch (error) {
    app.innerHTML = `<section class="loading-screen"><p style="color:#ff8f7e">Dashboard failed to initialize: ${escapeHtml(error.message)}</p></section>`;
  }
}

init();
