const state = {
  catalog: null,
  reviews: null,
  atlas: null,
  system: null,
  sessions: [],
  evaluations: [],
  route: {name: "observatory", id: null},
  filters: {query: "", group: "All", stage: "built", review: "all", view: "grid"},
  reviewFilters: {query: "", status: "pending"},
  environmentReturn: "environments",
  atlasFilters: {query: "", decision: "all", status: "all", type: "all", view: "designs", sort: "curated", instanceSource: "all", family: "all", recordType: "all"},
  atlasCompare: new Set(),
  atlasSpecimenDetails: new Map(),
  atlasInstanceDetails: new Map(),
  atlasInstanceCache: new Map(),
  atlasInstancePage: null,
  atlasInstanceSignature: "",
  atlasInstanceRequest: 0,
  atlasSearchTimer: null,
  atlasSourceDetails: new Map(),
  atlasArtifactPages: new Map(),
  atlasSourceKinds: new Map(),
  gallery: {},
  expandedLogs: new Set(),
  previousSessionStatus: new Map(),
};

try {
  state.atlasCompare = new Set(JSON.parse(localStorage.getItem("captcha-atlas-compare") || "[]"));
} catch (_error) {
  state.atlasCompare = new Set();
}

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
  const response = await fetch(path, {
    ...options,
    headers: {"content-type": "application/json", ...(options.headers || {})},
  });
  let payload = {};
  try { payload = await response.json(); } catch (_error) {}
  if (!response.ok) throw new Error(payload.error || `${response.status} ${response.statusText}`);
  return payload;
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
  if (parts[0] === "atlas" && ["item", "design", "variant", "specimen"].includes(parts[1]) && parts[2]) return {name: "atlas-item", id: decodeURIComponent(parts.slice(2).join("/"))};
  if (parts[0] === "atlas" && parts[1] === "instance" && parts[2]) return {name: "atlas-instance", id: decodeURIComponent(parts.slice(2).join("/"))};
  if (parts[0] === "atlas" && parts[1] === "source" && parts[2]) return {name: "atlas-source", id: decodeURIComponent(parts.slice(2).join("/"))};
  if (["observatory", "environments", "reviews", "atlas", "sessions", "evaluations"].includes(parts[0])) return {name: parts[0], id: null};
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
  if (state.atlas) document.getElementById("nav-atlas-count").textContent = formatNumber(state.atlas.stats.catalog_records);
  const reviewCount = document.getElementById("nav-review-count");
  if (reviewCount && state.reviews) reviewCount.textContent = formatNumber(state.reviews.stats.hands_on_pending ?? state.reviews.stats.pending);
  const liveCount = state.sessions.filter((session) => ["queued", "booting", "running", "stopping"].includes(session.status)).length;
  const node = document.getElementById("nav-session-count");
  node.textContent = liveCount;
  node.classList.toggle("has-live", liveCount > 0);
  if (state.system) document.getElementById("runner-name").textContent = state.system.runner;
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
    ? `<button class="quick-launch" type="button" data-quick-launch="${escapeHtml(environment.id)}" title="Launch in TigerVNC" aria-label="Launch ${escapeHtml(environment.title)} in TigerVNC">${arrowIcon}</button>`
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
  const atlasPreview = (state.atlas.featured_instances || []).slice(0, 3);
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

      <section class="atlas-home-portal">
        <div><p class="eyebrow">The upstream corpus</p><h2>You should choose<br>what gets built next.</h2><p>${formatNumber(state.atlas.stats.designs)} reusable designs, ${formatNumber(state.atlas.stats.variants)} source variants, ${formatNumber(state.atlas.stats.instances)} concrete challenge records, and ${state.atlas.stats.sources} source dossiers now live in the Survey Atlas—with personal shortlisting and provenance intact.</p><button class="button button-acid" type="button" data-action="browse-atlas">Enter the evidence room ${arrowIcon}</button></div>
        <div class="atlas-home-stack">${atlasPreview.map((instance, index) => `<button type="button" data-open-atlas-instance="${escapeHtml(instance.id)}" style="--stack-index:${index}"><img src="${escapeHtml(instance.cover)}" alt="${escapeHtml(instance.title)}"><span><small>${escapeHtml(instance.family_title)} / ${escapeHtml(instance.source_label)}</small><b>${escapeHtml(instance.title)}</b></span></button>`).join("")}</div>
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
        <div><p class="eyebrow">Human acceptance gate</p><h1 class="page-title">The human gets<br>the final say.</h1><p class="page-copy">Use “Looks good” for a design or solution-film screening. Approve only after hands-on play in VNC. Scripted verification, screening, and human acceptance remain separate records.</p></div>
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
    <p class="review-intro">A film/design screening may be marked “Looks good.” Run the specimen in VNC before approval. Neither state replaces the scripted verifier.</p>
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
    ? `<div class="detail-actions"><button class="button button-review" type="button" data-action="open-review-desk" style="--review-color:${reviewStatusColor(review.status)}">Review · ${escapeHtml(reviewStatusShort(review.status))}</button><button class="button button-ghost" type="button" data-open-eval="${escapeHtml(environment.id)}">Evaluate</button><button class="button button-acid" type="button" data-config-launch="${escapeHtml(environment.id)}">Launch in VNC ${arrowIcon}</button></div>`
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
          <div class="console-actions"><button class="button button-acid button-wide" type="button" data-quick-launch="${escapeHtml(environment.id)}">One-click TigerVNC ${arrowIcon}</button><button class="button button-ghost button-wide" type="button" data-config-launch="${escapeHtml(environment.id)}">Configure launch</button><button class="button button-ghost button-wide" type="button" data-open-eval="${escapeHtml(environment.id)}">Prepare evaluation</button></div>
          <p class="console-note">The dashboard boots the real Gym-Anything environment. TigerVNC opens automatically once the runner publishes its forwarded port.</p>
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

function atlasDecisionLabel(decision) {
  return {unreviewed: "Unreviewed", shortlisted: "Shortlist", maybe: "Maybe", rejected: "Reject"}[decision] || titleCase(decision);
}

function atlasDecisionColor(decision) {
  return {unreviewed: "#848b83", shortlisted: "#d7ff54", maybe: "#ffc857", rejected: "#ff705c"}[decision] || "#848b83";
}

function atlasLayerItems(layer = state.atlasFilters.view) {
  if (layer === "designs") return state.atlas?.designs || [];
  if (layer === "variants") return state.atlas?.variants || [];
  return [];
}

function findAtlasItem(id) {
  return state.atlas?.designs.find((item) => item.id === id)
    || state.atlas?.variants.find((item) => item.id === id)
    || state.atlasInstanceCache.get(id)
    || state.atlasInstanceDetails.get(id);
}

function findAtlasSource(slug) {
  return state.atlas?.sources.find((source) => source.slug === slug);
}

function atlasCoverMarkup(item, label = "") {
  if (item.cover) return `<img src="${escapeHtml(item.cover)}" alt="${escapeHtml(item.title)} research artifact" loading="lazy">`;
  const glyph = String(item.title || "?").trim().slice(0, 1).toUpperCase();
  return `<div class="atlas-blank-cover"><b>${escapeHtml(glyph)}</b><span>${escapeHtml(label || item.specimen_type_label || "SOURCE RECORD")}</span></div>`;
}

function atlasItemHaystack(item) {
  return [item.title, item.summary, item.source_label, item.specimen_type_label, item.category, item.action_type, item.grading, item.status, ...(item.tags || [])].join(" ").toLowerCase();
}

function filteredAtlasItems() {
  const query = state.atlasFilters.query.trim().toLowerCase();
  const items = atlasLayerItems().filter((item) => {
    const decision = item.curation?.decision || "unreviewed";
    const decisionMatch = state.atlasFilters.decision === "all" || decision === state.atlasFilters.decision || (state.atlasFilters.decision === "promoted" && item.curation?.promoted);
    const statusMatch = state.atlasFilters.status === "all" || item.status === state.atlasFilters.status;
    const typeMatch = state.atlasFilters.type === "all" || item.specimen_type === state.atlasFilters.type;
    return decisionMatch && statusMatch && typeMatch && (!query || atlasItemHaystack(item).includes(query));
  });
  const rank = {shortlisted: 0, maybe: 1, unreviewed: 2, rejected: 3};
  return items.sort((a, b) => {
    if (state.atlasFilters.sort === "title") return a.title.localeCompare(b.title);
    if (state.atlasFilters.sort === "source") return a.source_label.localeCompare(b.source_label) || a.title.localeCompare(b.title);
    if (state.atlasFilters.sort === "artifacts") return b.artifact_count - a.artifact_count || a.title.localeCompare(b.title);
    return Number(Boolean(b.curation?.promoted)) - Number(Boolean(a.curation?.promoted)) || rank[a.curation?.decision || "unreviewed"] - rank[b.curation?.decision || "unreviewed"];
  });
}

function filteredAtlasSources() {
  const query = state.atlasFilters.query.trim().toLowerCase();
  return state.atlas.sources.filter((source) => {
    const statusMatch = state.atlasFilters.status === "all" || source.status === state.atlasFilters.status;
    const haystack = [source.title, source.creator, source.summary, source.source_family_label, source.status_label, ...(source.artifact_types || []), ...(source.indexed_mechanics || []).map((item) => item.title)].join(" ").toLowerCase();
    return statusMatch && (!query || haystack.includes(query));
  }).sort((a, b) => state.atlasFilters.sort === "title" ? a.title.localeCompare(b.title) : state.atlasFilters.sort === "artifacts" ? b.artifact_total - a.artifact_total : b.instance_count - a.instance_count || b.variant_count - a.variant_count || a.title.localeCompare(b.title));
}

function atlasDecisionCounts(items) {
  const counts = {all: items.length, unreviewed: 0, shortlisted: 0, maybe: 0, rejected: 0, promoted: 0};
  items.forEach((item) => {
    counts[item.curation?.decision || "unreviewed"] += 1;
    if (item.curation?.promoted) counts.promoted += 1;
  });
  return counts;
}

function atlasItemCard(item, index) {
  const decision = item.curation?.decision || "unreviewed";
  const compared = state.atlasCompare.has(item.id);
  const prefix = item.layer === "design" ? "D" : "V";
  return `<article class="atlas-card ${item.curation?.promoted ? "is-promoted" : ""}" role="button" tabindex="0" data-open-atlas-item="${escapeHtml(item.id)}" style="--curation-color:${atlasDecisionColor(decision)}">
    <div class="atlas-card-media">${atlasCoverMarkup(item, item.layer === "design" ? "REUSABLE DESIGN" : "SOURCE VARIANT")}<span class="atlas-card-number">${prefix}${String(index + 1).padStart(3, "0")}</span><span class="atlas-card-decision"><i></i>${item.curation?.promoted ? "INCUBATOR" : escapeHtml(atlasDecisionLabel(decision))}</span><button class="atlas-compare-button ${compared ? "is-active" : ""}" type="button" data-atlas-compare="${escapeHtml(item.id)}" aria-label="${compared ? "Remove from" : "Add to"} comparison">${compared ? "✓" : "+"}</button></div>
    <div class="atlas-card-body"><div class="atlas-card-source"><span>${escapeHtml(item.source_label)}</span><b>${escapeHtml(item.seed_strength)}</b></div><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.summary)}</p><div class="tag-row">${(item.tags || []).slice(0, 3).map((tag) => `<span class="tag">${escapeHtml(titleCase(tag))}</span>`).join("")}</div><div class="atlas-card-foot"><span>${escapeHtml(item.specimen_type_label)}</span><span>${item.artifact_count} attached · ${item.related_environment_count} built links</span></div></div>
  </article>`;
}

function atlasInstanceCard(instance, index) {
  const decision = instance.curation?.decision || "unreviewed";
  return `<article class="atlas-card atlas-instance-card ${instance.curation?.promoted ? "is-promoted" : ""}" role="button" tabindex="0" data-open-atlas-instance="${escapeHtml(instance.id)}" style="--curation-color:${atlasDecisionColor(decision)}">
    <div class="atlas-card-media">${atlasCoverMarkup(instance, instance.record_type === "captured_example" ? "CAPTURED EXAMPLE" : "GROUND-TRUTH RECORD")}<span class="atlas-card-number">I${String(index + 1).padStart(4, "0")}</span><span class="atlas-card-decision"><i></i>${instance.ground_truth_status === "recorded" ? "ANSWER KEY" : "EVIDENCE ONLY"}</span></div>
    <div class="atlas-card-body"><div class="atlas-card-source"><span>${escapeHtml(instance.family_title)}</span><b>${escapeHtml(instance.dataset)}</b></div><h3>${escapeHtml(instance.title)}</h3><p>${escapeHtml(instance.prompt)}</p><div class="instance-answer-line"><span>${escapeHtml(instance.interaction)}</span><b>${instance.answer_preview ? `GT · ${escapeHtml(instance.answer_preview)}` : "NO LOCAL GROUND TRUTH"}</b></div><div class="atlas-card-foot"><span>${escapeHtml(instance.source_label)}</span><span>${instance.asset_count} visual assets</span></div></div>
  </article>`;
}

function atlasSourceCard(source, index) {
  return `<article class="atlas-card atlas-source-card" role="button" tabindex="0" data-open-atlas-source="${escapeHtml(source.slug)}"><div class="atlas-card-media">${atlasCoverMarkup(source, "SOURCE DOSSIER")}<span class="atlas-card-number">S${String(index + 1).padStart(2, "0")}</span><span class="atlas-card-decision source-status"><i></i>${escapeHtml(source.status_label)}</span></div><div class="atlas-card-body"><div class="atlas-card-source"><span>${escapeHtml(source.source_family_label)}</span><b>${formatNumber(source.artifact_total)} files</b></div><h3>${escapeHtml(source.title)}</h3><p>${escapeHtml(source.summary)}</p><div class="source-layer-counts"><span><b>${source.design_count}</b> designs</span><span><b>${source.variant_count}</b> variants</span><span><b>${formatNumber(source.instance_count)}</b> instances</span></div><div class="atlas-card-foot"><span>${escapeHtml(source.creator)}</span><span>${source.related_environment_count} built links</span></div></div></article>`;
}

function atlasInstanceFilterSignature() {
  return JSON.stringify([state.atlasFilters.query, state.atlasFilters.instanceSource, state.atlasFilters.family, state.atlasFilters.recordType, state.atlasFilters.decision]);
}

function atlasInstanceUrl(offset = 0) {
  const params = new URLSearchParams({query: state.atlasFilters.query, source: state.atlasFilters.instanceSource, family: state.atlasFilters.family, record_type: state.atlasFilters.recordType, decision: state.atlasFilters.decision, offset: String(offset), limit: "36"});
  return `/api/atlas/instances?${params}`;
}

async function loadAtlasInstances({append = false} = {}) {
  const request = ++state.atlasInstanceRequest;
  const signature = atlasInstanceFilterSignature();
  const offset = append ? (state.atlasInstancePage?.instances.length || 0) : 0;
  const grid = document.getElementById("atlas-grid");
  if (grid && !append) grid.innerHTML = `<div class="atlas-indexing"><div class="loading-orbit"><i></i><i></i><i></i></div><b>Querying concrete challenge records…</b><span>Ground truth stays on the server until a page is requested.</span></div>`;
  try {
    const page = await api(atlasInstanceUrl(offset));
    if (request !== state.atlasInstanceRequest || signature !== atlasInstanceFilterSignature()) return;
    page.instances.forEach((instance) => state.atlasInstanceCache.set(instance.id, instance));
    if (append && state.atlasInstancePage) {
      state.atlasInstancePage.instances.push(...page.instances);
      state.atlasInstancePage.has_more = page.has_more;
      state.atlasInstancePage.total = page.total;
    } else {
      state.atlasInstancePage = page;
      state.atlasInstanceSignature = signature;
    }
    refreshAtlasCatalog({skipLoad: true});
  } catch (error) {
    if (request === state.atlasInstanceRequest) {
      if (grid) grid.innerHTML = `<div class="empty-catalog"><b>Instance query failed.</b><span>${escapeHtml(error.message)}</span></div>`;
      toast("Could not query instances", error.message, "error");
    }
  }
}

function atlasGridMarkup() {
  if (state.atlasFilters.view === "sources") {
    const sources = filteredAtlasSources();
    return sources.length ? sources.map(atlasSourceCard).join("") : `<div class="empty-catalog"><b>No source dossiers found.</b><span>Widen the search or readiness filter.</span></div>`;
  }
  if (state.atlasFilters.view === "instances") {
    const page = state.atlasInstancePage;
    if (!page || state.atlasInstanceSignature !== atlasInstanceFilterSignature()) return `<div class="atlas-indexing"><div class="loading-orbit"><i></i><i></i><i></i></div><b>Querying concrete challenge records…</b></div>`;
    return page.instances.length ? page.instances.map(atlasInstanceCard).join("") : `<div class="empty-catalog"><b>No concrete records found.</b><span>Try a different family, source, or curation mark.</span></div>`;
  }
  const items = filteredAtlasItems();
  return items.length ? items.map(atlasItemCard).join("") : `<div class="empty-catalog"><b>No records found.</b><span>Widen the search or curation filters.</span></div>`;
}

function atlasCompareDockMarkup() {
  const selected = [...state.atlasCompare].map(findAtlasItem).filter(Boolean);
  if (!selected.length) return "";
  return `<aside class="atlas-compare-dock"><div><small>COMPARISON TRAY</small><b>${selected.length} / 3 records</b></div><div class="atlas-compare-thumbs">${selected.map((item) => `<span title="${escapeHtml(item.title)}">${item.cover ? `<img src="${escapeHtml(item.cover)}" alt="">` : escapeHtml(item.title.slice(0, 1))}</span>`).join("")}</div><button class="button button-acid button-small" type="button" data-action="open-atlas-compare">Compare</button><button class="atlas-dock-close" type="button" data-action="clear-atlas-compare" aria-label="Clear comparison">×</button></aside>`;
}

function refreshAtlasCatalog({skipLoad = false} = {}) {
  const grid = document.getElementById("atlas-grid");
  if (!grid) return;
  if (state.atlasFilters.view === "instances" && !skipLoad && state.atlasInstanceSignature !== atlasInstanceFilterSignature()) { loadAtlasInstances(); return; }
  grid.innerHTML = atlasGridMarkup();
  let total;
  let possible;
  if (state.atlasFilters.view === "sources") { total = filteredAtlasSources().length; possible = state.atlas.stats.sources; }
  else if (state.atlasFilters.view === "instances") { total = state.atlasInstancePage?.instances.length || 0; possible = state.atlasInstancePage?.total ?? state.atlas.stats.instances; }
  else { total = filteredAtlasItems().length; possible = atlasLayerItems().length; }
  const count = document.getElementById("atlas-result-count");
  if (count) count.textContent = state.atlasFilters.view === "instances" ? `${formatNumber(total)} loaded / ${formatNumber(possible)}` : `${formatNumber(total)} / ${formatNumber(possible)}`;
  const loadRoot = document.getElementById("atlas-instance-load-root");
  if (loadRoot) loadRoot.innerHTML = state.atlasInstancePage?.has_more ? `<button class="button button-ghost button-wide" type="button" data-action="load-more-atlas-instances">Load 36 more records</button>` : "";
  document.querySelectorAll("[data-atlas-decision-filter]").forEach((button) => button.classList.toggle("is-active", button.dataset.atlasDecisionFilter === state.atlasFilters.decision));
  const dock = document.getElementById("atlas-dock-root");
  if (dock) dock.innerHTML = atlasCompareDockMarkup();
}

function atlasFamilyOptions() {
  const source = state.atlasFilters.instanceSource;
  const merged = new Map();
  state.atlas.instance_families.filter((item) => source === "all" || item.source_slug === source).forEach((item) => {
    const previous = merged.get(item.family) || {family: item.family, family_title: item.family_title, count: 0};
    previous.count += item.count;
    merged.set(item.family, previous);
  });
  return [...merged.values()].sort((a, b) => a.family_title.localeCompare(b.family_title));
}

function atlasFilterToolbar() {
  const view = state.atlasFilters.view;
  const search = `<label class="search-field">${searchIcon}<input id="atlas-search" type="search" value="${escapeHtml(state.atlasFilters.query)}" placeholder="Search prompt, interaction, family, source…" aria-label="Search Survey Atlas"></label>`;
  if (view === "instances") {
    const families = atlasFamilyOptions();
    return `${search}<select class="filter-select" id="atlas-instance-source" aria-label="Filter instance source"><option value="all">All instance sources</option>${state.atlas.instance_sources.map((source) => `<option value="${escapeHtml(source.slug)}" ${state.atlasFilters.instanceSource === source.slug ? "selected" : ""}>${escapeHtml(source.title)} · ${source.count}</option>`).join("")}</select><select class="filter-select" id="atlas-instance-family" aria-label="Filter puzzle family"><option value="all">All puzzle families</option>${families.map((family) => `<option value="${escapeHtml(family.family)}" ${state.atlasFilters.family === family.family ? "selected" : ""}>${escapeHtml(family.family_title)} · ${family.count}</option>`).join("")}</select><select class="filter-select" id="atlas-record-type"><option value="all">Ground truth + captures</option><option value="ground_truth_challenge" ${state.atlasFilters.recordType === "ground_truth_challenge" ? "selected" : ""}>Ground-truth challenges</option><option value="captured_example" ${state.atlasFilters.recordType === "captured_example" ? "selected" : ""}>Captured examples</option></select>`;
  }
  const readiness = `<select class="filter-select" id="atlas-status-filter" aria-label="Filter source readiness"><option value="all">All readiness</option>${state.atlas.statuses.map((status) => `<option value="${escapeHtml(status)}" ${state.atlasFilters.status === status ? "selected" : ""}>${escapeHtml(titleCase(status))}</option>`).join("")}</select>`;
  const types = [...new Set(atlasLayerItems().map((item) => item.specimen_type))].sort();
  const type = ["designs", "variants"].includes(view) ? `<select class="filter-select" id="atlas-type-filter"><option value="all">All record types</option>${types.map((value) => `<option value="${escapeHtml(value)}" ${state.atlasFilters.type === value ? "selected" : ""}>${escapeHtml(titleCase(value))}</option>`).join("")}</select>` : "";
  const sort = `<select class="filter-select" id="atlas-sort"><option value="curated" ${state.atlasFilters.sort === "curated" ? "selected" : ""}>Curator order</option><option value="artifacts" ${state.atlasFilters.sort === "artifacts" ? "selected" : ""}>Most evidence</option><option value="source" ${state.atlasFilters.sort === "source" ? "selected" : ""}>By source</option><option value="title" ${state.atlasFilters.sort === "title" ? "selected" : ""}>A–Z</option></select>`;
  return `${search}${readiness}${type}${sort}`;
}

function renderAtlas() {
  setChrome("atlas", "Survey Atlas");
  if (!state.atlas.available) { app.innerHTML = `<div class="page atlas-page"><div class="empty-state"><h2>Research corpus not found.</h2><p>The Atlas expects the sibling research/collection directory.</p></div></div>`; return; }
  const view = state.atlasFilters.view;
  const layer = view === "instances" ? state.atlas.layer_curation.instances : view === "designs" ? state.atlas.layer_curation.designs : state.atlas.layer_curation.variants;
  const localCounts = ["designs", "variants"].includes(view) ? atlasDecisionCounts(atlasLayerItems()) : null;
  const layerTotal = view === "instances" ? state.atlas.stats.instances : atlasLayerItems().length;
  const counts = localCounts || {all: layerTotal, unreviewed: layerTotal - (layer?.reviewed || 0), shortlisted: layer?.shortlisted || 0, maybe: layer?.maybe || 0, rejected: layer?.rejected || 0, promoted: layer?.promoted || 0};
  const decisionFilters = [["all", "All"], ["unreviewed", "Unreviewed"], ["shortlisted", "Shortlist"], ["maybe", "Maybe"], ["rejected", "Rejected"], ["promoted", "Incubator"]];
  const note = view === "designs" ? "Cross-source abstractions: the reusable interaction idea, deduplicated across the survey." : view === "variants" ? "Named levels, generators, components, and families exactly evidenced by an individual source." : view === "instances" ? `${formatNumber(state.atlas.stats.ground_truth_instances)} answer-key records plus ${state.atlas.stats.captured_examples} real ViRC examples whose local answers are unavailable.` : "Every collected source, including files that do not yet resolve to an enumerated mechanic.";
  app.innerHTML = `<div class="page atlas-page">
    <header class="atlas-hero"><div class="atlas-hero-copy"><p class="eyebrow">Survey evidence / four honest layers</p><h1>The evidence<br><em>room.</em></h1><p>The old 211-card wall mixed abstractions with source implementations and hid thousands of assets underneath them. This index keeps each level separate—so a texture is never mislabeled as a CAPTCHA and an advertised count never becomes a fabricated card.</p><div class="hero-actions"><button class="button button-acid" type="button" data-action="random-atlas-record">Surprise me ${arrowIcon}</button><button class="button button-ghost" type="button" data-atlas-view="instances">Open concrete records</button></div></div><div class="atlas-ledger atlas-layer-ledger" aria-label="Atlas layer statistics"><span>AUDITED FIELD LEDGER / JUL 2026</span><div><b>${formatNumber(state.atlas.stats.designs)}</b><small>reusable designs</small></div><div><b>${formatNumber(state.atlas.stats.variants)}</b><small>source variants</small></div><div><b>${formatNumber(state.atlas.stats.instances)}</b><small>concrete records</small></div><div><b>${formatNumber(state.atlas.stats.sources)}</b><small>source dossiers</small></div></div></header>
    <section class="atlas-audit-strip"><div><small>Browseable records</small><b>${formatNumber(state.atlas.stats.catalog_records)}</b></div><div><small>All provenance files</small><b>${formatNumber(state.atlas.stats.files)}</b></div><div><small>Image assets, including cells + pieces</small><b>${formatNumber(state.atlas.stats.visual_assets)}</b></div><p><b>Counting rule.</b> ${formatNumber(state.atlas.stats.instances)} means challenge-level records, not every image file. The remaining assets stay attached to their parent record or source dossier.</p></section>
    <section class="atlas-lifecycle"><span>01 · SURVEY</span><i></i><span>02 · YOUR SHORTLIST</span><i></i><span>03 · INCUBATOR</span><i></i><span>04 · BUILT + EVALUATED</span></section>
    <section class="atlas-workbench"><div class="atlas-view-switch atlas-view-switch-four"><button type="button" data-atlas-view="designs" class="${view === "designs" ? "is-active" : ""}"><b>${state.atlas.stats.designs}</b><span>Designs</span></button><button type="button" data-atlas-view="variants" class="${view === "variants" ? "is-active" : ""}"><b>${state.atlas.stats.variants}</b><span>Source variants</span></button><button type="button" data-atlas-view="instances" class="${view === "instances" ? "is-active" : ""}"><b>${formatNumber(state.atlas.stats.instances)}</b><span>Concrete instances</span></button><button type="button" data-atlas-view="sources" class="${view === "sources" ? "is-active" : ""}"><b>${state.atlas.stats.sources}</b><span>Source dossiers</span></button></div>
      <p class="atlas-layer-definition"><span>${String(["designs", "variants", "instances", "sources"].indexOf(view) + 1).padStart(2, "0")}</span>${escapeHtml(note)}</p><div class="atlas-toolbar">${atlasFilterToolbar()}</div>
      ${view === "sources" ? `<div class="filter-pills"><span class="atlas-source-note">Dossiers preserve the complete provenance archive, including non-visual code and metadata.</span><span class="catalog-count" id="atlas-result-count">${filteredAtlasSources().length} / ${state.atlas.stats.sources}</span></div>` : `<div class="filter-pills atlas-decision-pills">${decisionFilters.map(([value, label]) => `<button class="filter-pill ${state.atlasFilters.decision === value ? "is-active" : ""}" type="button" data-atlas-decision-filter="${value}">${label} <b>${formatNumber(counts[value])}</b></button>`).join("")}<span class="catalog-count" id="atlas-result-count">${view === "instances" ? "querying…" : `${filteredAtlasItems().length} / ${layerTotal}`}</span></div>`}
      <div class="atlas-grid ${view === "instances" ? "atlas-instance-grid" : ""}" id="atlas-grid">${atlasGridMarkup()}</div><div id="atlas-instance-load-root"></div>
    </section><div id="atlas-dock-root">${atlasCompareDockMarkup()}</div></div>`;
  if (view === "instances" && state.atlasInstanceSignature !== atlasInstanceFilterSignature()) loadAtlasInstances();
  else if (view === "instances") refreshAtlasCatalog({skipLoad: true});
}

function artifactMarkup(artifact) {
  const label = `<div class="artifact-label"><span>${escapeHtml(artifact.kind)} · ${formatBytes(artifact.size_bytes)}</span><b>${escapeHtml(artifact.name)}</b><small>${escapeHtml(artifact.path)}</small></div>`;
  if (artifact.kind === "image") return `<a class="artifact-tile is-visual" href="${escapeHtml(artifact.url)}" target="_blank" rel="noreferrer"><img src="${escapeHtml(artifact.url)}" alt="${escapeHtml(artifact.name)}" loading="lazy">${label}</a>`;
  if (artifact.kind === "video") return `<article class="artifact-tile is-visual"><video controls preload="metadata" src="${escapeHtml(artifact.url)}"></video>${label}<a href="${escapeHtml(artifact.url)}" target="_blank" rel="noreferrer">OPEN FILE ↗</a></article>`;
  if (artifact.kind === "audio") return `<article class="artifact-tile is-audio"><div class="artifact-wave"><i></i><i></i><i></i><i></i><i></i></div><audio controls preload="none" src="${escapeHtml(artifact.url)}"></audio>${label}</article>`;
  if (artifact.kind === "document") return `<a class="artifact-tile is-document" href="${escapeHtml(artifact.url)}" target="_blank" rel="noreferrer"><div class="artifact-file-glyph">PDF</div>${label}</a>`;
  return `<a class="artifact-tile is-text" href="${escapeHtml(artifact.url)}" target="_blank" rel="noreferrer"><span class="artifact-file-glyph">${escapeHtml(artifact.kind === "code" ? "</>" : artifact.kind.slice(0, 4).toUpperCase())}</span>${artifact.excerpt ? `<pre>${escapeHtml(artifact.excerpt)}</pre>` : ""}${label}</a>`;
}

function researchNotesMarkup(value) {
  const lines = String(value || "").split(/\r?\n/);
  let html = "";
  let listOpen = false;
  const closeList = () => { if (listOpen) { html += "</ul>"; listOpen = false; } };
  lines.forEach((line) => {
    const heading = line.match(/^(#{1,3})\s+(.+)/);
    const bullet = line.match(/^\s*-\s+(.+)/);
    if (heading) { closeList(); const level = Math.min(4, heading[1].length + 1); html += `<h${level}>${escapeHtml(heading[2])}</h${level}>`; }
    else if (bullet) { if (!listOpen) { html += "<ul>"; listOpen = true; } html += `<li>${escapeHtml(bullet[1])}</li>`; }
    else if (!line.trim()) closeList();
    else { closeList(); html += `<p>${escapeHtml(line)}</p>`; }
  });
  closeList();
  return html || "<p>No extraction note recorded.</p>";
}

function atlasCurationPanel(specimen) {
  const curation = specimen.curation || {decision: "unreviewed", note: "", promoted: false};
  return `<aside class="atlas-curator-panel" id="atlas-curator-panel" style="--curation-color:${atlasDecisionColor(curation.decision)}">
    <div class="curator-panel-head"><span>YOUR FIELD MARK</span><h2>${curation.promoted ? "In the incubator queue" : atlasDecisionLabel(curation.decision)}</h2><p>Stored locally with this research corpus.</p></div>
    <div class="curation-decisions">${["shortlisted", "maybe", "rejected", "unreviewed"].map((decision) => `<button type="button" class="${curation.decision === decision ? "is-active" : ""}" data-atlas-decision="${decision}" data-atlas-item="${escapeHtml(specimen.id)}"><i style="--decision-color:${atlasDecisionColor(decision)}"></i>${atlasDecisionLabel(decision)}</button>`).join("")}</div>
    <form id="atlas-note-form" data-atlas-item="${escapeHtml(specimen.id)}"><label for="atlas-curator-note">Research note</label><textarea id="atlas-curator-note" name="note" maxlength="5000" placeholder="What is interesting? What should change before we build it?">${escapeHtml(curation.note)}</textarea><button class="button button-ghost button-wide" type="submit">Save field note</button></form>
    <button class="button ${curation.promoted ? "button-ghost" : "button-acid"} button-wide curator-promote" type="button" data-atlas-promote="${escapeHtml(specimen.id)}" data-promoted="${curation.promoted ? "true" : "false"}">${curation.promoted ? "Return to shortlist" : "Promote to incubator"} ${arrowIcon}</button>
    <p class="curator-honesty">Promotion creates a persistent build-queue marker. It does not fabricate an environment, task, verifier, or evidence run.</p>
  </aside>`;
}

function renderAtlasItem(specimenId) {
  const summary = findAtlasItem(specimenId);
  if (!summary) { navigate("atlas"); return; }
  setChrome("atlas", summary.title);
  const specimen = state.atlasSpecimenDetails.get(specimenId);
  if (!specimen) {
    app.innerHTML = `<div class="page atlas-detail-page"><button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button><div class="atlas-detail-loading"><div class="loading-orbit"><i></i><i></i><i></i></div><h1>${escapeHtml(summary.title)}</h1><p>Opening source dossier and attached evidence…</p></div></div>`;
    api(`/api/atlas/items/${encodeURIComponent(specimenId)}`).then((detail) => {
      state.atlasSpecimenDetails.set(specimenId, detail);
      const route = parseRoute();
      if (route.name === "atlas-item" && route.id === specimenId) renderAtlasItem(specimenId);
    }).catch((error) => toast("Could not open specimen", error.message, "error"));
    return;
  }
  const related = specimen.related_environments || [];
  const visuals = (specimen.artifacts || []).filter((artifact) => ["image", "video"].includes(artifact.kind));
  const primary = visuals[0];
  app.innerHTML = `<div class="page atlas-detail-page">
    <button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button>
    <header class="atlas-detail-head"><div><p class="eyebrow">${specimen.layer === "design" ? "Reusable design" : "Source variant"} / ${escapeHtml(specimen.specimen_type_label)}</p><h1>${escapeHtml(specimen.title)}</h1><p>${escapeHtml(specimen.source_label)}</p></div><div class="atlas-detail-head-actions"><button class="button button-ghost" type="button" data-atlas-compare="${escapeHtml(specimen.id)}">${state.atlasCompare.has(specimen.id) ? "Remove comparison" : "Add to compare"}</button>${specimen.sources?.length === 1 ? `<button class="button button-acid" type="button" data-open-atlas-source="${escapeHtml(specimen.sources[0].slug)}">Open source dossier ${arrowIcon}</button>` : ""}</div></header>
    <div class="atlas-detail-layout">
      <main class="atlas-detail-main">
        <section class="atlas-evidence-hero">${primary ? (primary.kind === "video" ? `<video controls preload="metadata" src="${escapeHtml(primary.url)}"></video>` : `<img src="${escapeHtml(primary.url)}" alt="${escapeHtml(specimen.title)} artifact">`) : atlasCoverMarkup(specimen)}<div class="evidence-stamp"><span>COLLECTED EVIDENCE</span><b>${specimen.artifacts.length} linked artifacts</b></div></section>
        <section class="atlas-mechanic-brief"><div><p class="eyebrow">Research extraction</p><h2>What the puzzle asks</h2><p>${escapeHtml(specimen.summary)}</p><div class="tag-row">${(specimen.tags || []).map((tag) => `<span class="tag">${escapeHtml(titleCase(tag))}</span>`).join("")}</div></div><div class="mechanic-contract"><span><small>Category</small><b>${escapeHtml(titleCase(specimen.category))}</b></span><span><small>Interaction</small><b>${escapeHtml(titleCase(specimen.action_type))}</b></span><span><small>Observed grading</small><b>${escapeHtml(titleCase(specimen.grading))}</b></span><span><small>Seed strength</small><b>${escapeHtml(titleCase(specimen.seed_strength))}</b></span></div></section>
        <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Attached material</p><h2>Evidence, not decoration.</h2></div><p>Every tile opens the locally collected file. Text and code are served safely as downloads; images, audio, video, and PDFs remain inspectable.</p></div><div class="artifact-grid">${(specimen.artifacts || []).map(artifactMarkup).join("") || `<div class="empty-catalog"><b>No item-specific artifact.</b><span>Open the source dossier to inspect its full archive.</span></div>`}</div></section>
        <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Benchmark lineage</p><h2>${related.length ? `${related.length} connected designs` : "No design committed yet"}</h2></div><p>Links are computed from explicit source anchors in environment metadata, never inferred from title similarity.</p></div>${related.length ? `<div class="atlas-related-grid">${related.map((environment) => `<button type="button" data-open-env="${escapeHtml(environment.id)}"><span>${environment.cover ? `<img src="${escapeHtml(environment.cover)}" alt="">` : ""}</span><div><small>${escapeHtml(environment.group)} / ${escapeHtml(environment.stage)}</small><b>${escapeHtml(environment.title)}</b><em>${escapeHtml((environment.axes || []).join(" · "))}</em></div>${arrowIcon}</button>`).join("")}</div>` : `<div class="atlas-unlinked">Untapped research territory. Shortlist it if the interaction deserves a benchmark treatment.</div>`}</section>
        <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Provenance chain</p><h2>${specimen.sources.length} source record${specimen.sources.length === 1 ? "" : "s"}</h2></div></div><div class="atlas-source-list">${specimen.sources.map((source) => `<button type="button" data-open-atlas-source="${escapeHtml(source.slug)}"><span>${source.cover ? `<img src="${escapeHtml(source.cover)}" alt="">` : ""}</span><div><small>${escapeHtml(source.status_label)} · ${formatNumber(source.artifact_total)} files</small><b>${escapeHtml(source.title)}</b><em>${escapeHtml(source.creator)}</em></div>${arrowIcon}</button>`).join("")}</div></section>
      </main>
      ${atlasCurationPanel(specimen)}
    </div>
    <div id="atlas-dock-root">${atlasCompareDockMarkup()}</div>
  </div>`;
}

function groundTruthMarkup(instance) {
  if (instance.ground_truth_status !== "recorded" || !instance.ground_truth) {
    return `<div class="ground-truth-missing"><b>No local answer key</b><p>This is a genuine captured survey example, but the public artifact bundle did not include its ground truth. The Atlas keeps that gap explicit.</p></div>`;
  }
  return `<div class="ground-truth-record"><div><span>RECORDED ANSWER CONTRACT</span><b>${instance.answer_preview ? escapeHtml(instance.answer_preview) : "Structured ground truth"}</b></div><pre>${escapeHtml(JSON.stringify(instance.ground_truth, null, 2))}</pre></div>`;
}

function renderAtlasInstance(instanceId) {
  const summary = findAtlasItem(instanceId);
  setChrome("atlas", summary?.title || "Concrete instance");
  const instance = state.atlasInstanceDetails.get(instanceId);
  if (!instance) {
    app.innerHTML = `<div class="page atlas-detail-page"><button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button><div class="atlas-detail-loading"><div class="loading-orbit"><i></i><i></i><i></i></div><h1>${escapeHtml(summary?.title || "Opening concrete record")}</h1><p>Resolving challenge assets and ground truth…</p></div></div>`;
    api(`/api/atlas/instances/${encodeURIComponent(instanceId)}`).then((detail) => {
      state.atlasInstanceDetails.set(instanceId, detail);
      state.atlasInstanceCache.set(instanceId, detail);
      const route = parseRoute();
      if (route.name === "atlas-instance" && route.id === instanceId) renderAtlasInstance(instanceId);
    }).catch((error) => { toast("Could not open instance", error.message, "error"); navigate("atlas"); });
    return;
  }
  const visuals = (instance.assets || []).filter((artifact) => ["image", "video"].includes(artifact.kind));
  const primary = visuals[0];
  app.innerHTML = `<div class="page atlas-detail-page atlas-instance-detail">
    <button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button>
    <header class="atlas-detail-head"><div><p class="eyebrow">Concrete instance / ${escapeHtml(instance.record_type === "captured_example" ? "evidence only" : "ground truth recorded")}</p><h1>${escapeHtml(instance.title)}</h1><p>${escapeHtml(instance.family_title)} · ${escapeHtml(instance.dataset)}</p></div><div class="atlas-detail-head-actions">${instance.variant ? `<button class="button button-ghost" type="button" data-open-atlas-item="${escapeHtml(instance.variant.id)}">Open parent variant</button>` : ""}<button class="button button-acid" type="button" data-open-atlas-source="${escapeHtml(instance.source_slug)}">Source dossier ${arrowIcon}</button></div></header>
    <div class="atlas-detail-layout"><main class="atlas-detail-main">
      <section class="atlas-evidence-hero">${primary ? (primary.kind === "video" ? `<video controls preload="metadata" src="${escapeHtml(primary.url)}"></video>` : `<img src="${escapeHtml(primary.url)}" alt="${escapeHtml(instance.title)}">`) : atlasCoverMarkup(instance, "NO COMPOSITE PREVIEW")}<div class="evidence-stamp"><span>${instance.ground_truth_status === "recorded" ? "CHALLENGE-LEVEL RECORD" : "CAPTURED SOURCE EVIDENCE"}</span><b>${instance.asset_count} linked visual asset${instance.asset_count === 1 ? "" : "s"}</b></div></section>
      <section class="instance-prompt-sheet"><p class="eyebrow">Exact recorded prompt</p><blockquote>${escapeHtml(instance.prompt)}</blockquote><p>${escapeHtml(instance.summary)}</p></section>
      <section class="atlas-mechanic-brief"><div><p class="eyebrow">Interaction contract</p><h2>${escapeHtml(instance.interaction)}</h2><p>This record is one concrete member of the ${escapeHtml(instance.family_title)} family. Its files remain grouped here instead of being counted as separate CAPTCHA specimens.</p></div><div class="mechanic-contract"><span><small>Record key</small><b>${escapeHtml(instance.record_key)}</b></span><span><small>Media</small><b>${escapeHtml(titleCase(instance.media_type))}</b></span><span><small>Ground truth</small><b>${escapeHtml(titleCase(instance.ground_truth_status))}</b></span><span><small>Provider</small><b>${escapeHtml(instance.dataset)}</b></span></div></section>
      <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Verifier evidence</p><h2>What the dataset knows</h2></div><p>Answers are shown because this is a benchmark-research catalog, not a deployed security challenge.</p></div>${groundTruthMarkup(instance)}</section>
      <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Instance assets</p><h2>${instance.assets.length} files compose this record</h2></div><p>A challenge can use a reference, multiple cells, moving pieces, or option images. Those are assets of one record—not extra instances.</p></div><div class="artifact-grid">${instance.assets.map(artifactMarkup).join("") || `<div class="empty-catalog"><b>No static preview asset.</b><span>The ground-truth record may describe a runtime-generated interaction.</span></div>`}</div></section>
      <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Provenance</p><h2>${escapeHtml(instance.source_label)}</h2></div></div><div class="atlas-source-list"><button type="button" data-open-atlas-source="${escapeHtml(instance.source_slug)}"><span>${instance.source?.cover ? `<img src="${escapeHtml(instance.source.cover)}" alt="">` : ""}</span><div><small>${escapeHtml(instance.source?.status_label || "source record")} · ${formatNumber(instance.source?.artifact_total || 0)} files</small><b>${escapeHtml(instance.source_label)}</b><em>${escapeHtml(instance.source?.creator || "")}</em></div>${arrowIcon}</button></div></section>
    </main>${atlasCurationPanel(instance)}</div>
  </div>`;
}

function renderAtlasSource(sourceSlug) {
  const summary = findAtlasSource(sourceSlug);
  if (!summary) { navigate("atlas"); return; }
  setChrome("atlas", summary.title);
  const detail = state.atlasSourceDetails.get(sourceSlug);
  const kind = state.atlasSourceKinds.get(sourceSlug) || "all";
  const pageKey = `${sourceSlug}:${kind}`;
  const artifactPage = state.atlasArtifactPages.get(pageKey);
  if (!detail || !artifactPage) {
    app.innerHTML = `<div class="page atlas-detail-page"><button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button><div class="atlas-detail-loading"><div class="loading-orbit"><i></i><i></i><i></i></div><h1>${escapeHtml(summary.title)}</h1><p>Indexing the local source archive…</p></div></div>`;
    Promise.all([
      detail ? Promise.resolve(detail) : api(`/api/atlas/sources/${encodeURIComponent(sourceSlug)}`),
      artifactPage ? Promise.resolve(artifactPage) : api(`/api/atlas/sources/${encodeURIComponent(sourceSlug)}/artifacts?kind=${encodeURIComponent(kind)}&limit=48`),
    ]).then(([nextDetail, nextPage]) => {
      state.atlasSourceDetails.set(sourceSlug, nextDetail);
      state.atlasArtifactPages.set(pageKey, nextPage);
      const route = parseRoute();
      if (route.name === "atlas-source" && route.id === sourceSlug) renderAtlasSource(sourceSlug);
    }).catch((error) => toast("Could not open source", error.message, "error"));
    return;
  }
  const kinds = ["all", ...state.atlas.artifact_kinds.filter((candidate) => detail.artifact_counts[candidate])];
  app.innerHTML = `<div class="page atlas-source-page">
    <button class="detail-back" type="button" data-action="back-to-atlas">← BACK TO ATLAS</button>
    <header class="source-dossier-head"><div><p class="eyebrow">Source dossier / ${escapeHtml(detail.status_label)}</p><h1>${escapeHtml(detail.title)}</h1><p>${escapeHtml(detail.summary)}</p></div><div class="source-record-stamp"><span>PROVENANCE RECORD</span><b>${formatNumber(detail.artifact_total)} files</b><small>${detail.designs.length} designs · ${detail.variants.length} variants · ${formatNumber(detail.instance_total)} instances</small>${detail.primary_url ? `<a class="button button-ghost button-small" href="${escapeHtml(detail.primary_url)}" target="_blank" rel="noreferrer">Original source ↗</a>` : ""}</div></header>
    <section class="source-facts"><div><small>Creator</small><b>${escapeHtml(detail.creator)}</b></div><div><small>Source family</small><b>${escapeHtml(detail.source_family_label)}</b></div><div><small>Collection state</small><b>${escapeHtml(detail.status_label)}</b></div><div><small>Artifact policy</small><b>${escapeHtml(titleCase(detail.artifact_policy))}</b></div><div><small>Known mechanic claim</small><b>${detail.mechanic_count_known ?? "Not recorded"}</b></div></section>
    <div class="source-dossier-layout"><main>
      <section class="atlas-detail-section source-artifacts"><div class="section-heading"><div><p class="eyebrow">Archive browser</p><h2>Collected artifacts</h2></div><p id="source-artifact-summary"><span>${artifactPage.artifacts.length}</span> of ${formatNumber(artifactPage.total)} ${kind === "all" ? "files" : kind + " files"} visible.</p></div><div class="artifact-kind-tabs">${kinds.map((candidate) => `<button type="button" class="${kind === candidate ? "is-active" : ""}" data-atlas-artifact-kind="${candidate}" data-atlas-source="${escapeHtml(sourceSlug)}">${titleCase(candidate)} <b>${candidate === "all" ? detail.artifact_total : detail.artifact_counts[candidate]}</b></button>`).join("")}</div><div class="artifact-grid" id="source-artifact-grid">${artifactPage.artifacts.map(artifactMarkup).join("")}</div><div id="artifact-load-root">${artifactPage.has_more ? `<button class="button button-ghost button-wide artifact-load-more" type="button" data-atlas-load-artifacts="${escapeHtml(sourceSlug)}">Load more evidence</button>` : ""}</div></section>
      <section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Mechanic layers</p><h2>${detail.designs.length} designs · ${detail.variants.length} variants</h2></div><p>Designs are cross-source abstractions. Variants are exact levels, components, generators, or families evidenced by this source.</p></div><div class="atlas-mini-specimens">${[...detail.designs, ...detail.variants].slice(0, 30).map((item) => `<button type="button" data-open-atlas-item="${escapeHtml(item.id)}"><span>${item.cover ? `<img src="${escapeHtml(item.cover)}" alt="">` : ""}</span><div><small>${escapeHtml(item.layer === "design" ? "Reusable design" : titleCase(item.specimen_type))}</small><b>${escapeHtml(item.title)}</b></div><i style="background:${atlasDecisionColor(item.curation.decision)}"></i></button>`).join("") || `<div class="empty-catalog"><b>No enumerated mechanic record.</b><span>The dossier remains searchable through its raw evidence.</span></div>`}</div>${detail.designs.length + detail.variants.length > 30 ? `<p class="source-overflow-note">${detail.designs.length + detail.variants.length - 30} additional linked records are searchable from the Atlas index.</p>` : ""}</section>
      ${detail.instance_total ? `<section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Concrete evidence</p><h2>${formatNumber(detail.instance_total)} challenge records</h2></div><p>Showing the first ${detail.instances.length}; use the instance browser for the complete paginated set.</p></div><div class="atlas-grid atlas-instance-grid">${detail.instances.map(atlasInstanceCard).join("")}</div>${detail.instance_total > detail.instances.length ? `<button class="button button-ghost button-wide source-open-instances" type="button" data-atlas-source-instances="${escapeHtml(sourceSlug)}">Browse all ${formatNumber(detail.instance_total)} from this source ${arrowIcon}</button>` : ""}</section>` : ""}
      ${detail.related_environments.length ? `<section class="atlas-detail-section"><div class="section-heading"><div><p class="eyebrow">Built descendants</p><h2>${detail.related_environments.length} benchmark links</h2></div></div><div class="atlas-related-grid">${detail.related_environments.map((environment) => `<button type="button" data-open-env="${escapeHtml(environment.id)}"><span>${environment.cover ? `<img src="${escapeHtml(environment.cover)}" alt="">` : ""}</span><div><small>${escapeHtml(environment.group)} / ${escapeHtml(environment.stage)}</small><b>${escapeHtml(environment.title)}</b></div>${arrowIcon}</button>`).join("")}</div></section>` : ""}
    </main><aside class="source-notes"><div class="source-notes-head"><span>EXTRACTION NOTES</span><small>${escapeHtml(sourceSlug)}/notes.md</small></div><div class="research-notes">${researchNotesMarkup(detail.notes)}</div></aside></div>
  </div>`;
}

async function updateAtlasCuration(itemId, changes) {
  const item = findAtlasItem(itemId);
  if (!item) return;
  const current = item.curation || {decision: "unreviewed", note: "", promoted: false};
  const noteField = document.getElementById("atlas-curator-note");
  const payload = {
    decision: changes.decision ?? current.decision,
    note: changes.note ?? noteField?.value ?? current.note,
    promoted: changes.promoted ?? current.promoted,
  };
  if (payload.decision !== "shortlisted" && changes.promoted == null) payload.promoted = false;
  try {
    const endpoint = item.layer === "instance" ? "instances" : "items";
    const response = await api(`/api/atlas/${endpoint}/${encodeURIComponent(itemId)}/curation`, {method: "POST", body: JSON.stringify(payload)});
    item.curation = response.curation;
    state.atlas.stats = response.stats;
    if (response.layer_curation) state.atlas.layer_curation = response.layer_curation;
    const detail = state.atlasSpecimenDetails.get(itemId);
    if (detail) detail.curation = response.curation;
    const instanceDetail = state.atlasInstanceDetails.get(itemId);
    if (instanceDetail) instanceDetail.curation = response.curation;
    state.atlasSourceDetails.forEach((source) => {
      [...(source.designs || []), ...(source.variants || []), ...(source.instances || [])].forEach((linked) => { if (linked.id === itemId) linked.curation = response.curation; });
    });
    toast(response.curation.promoted ? "Promoted to incubator" : "Field mark saved", `${item.title} · ${atlasDecisionLabel(response.curation.decision)}`, response.curation.decision === "rejected" ? "warn" : "success");
    const route = parseRoute();
    if (["atlas-item", "atlas-instance"].includes(route.name)) {
      const panel = document.getElementById("atlas-curator-panel");
      const full = detail || instanceDetail;
      if (panel && full) panel.outerHTML = atlasCurationPanel(full);
    }
    else refreshAtlasCatalog({skipLoad: state.atlasFilters.view === "instances"});
    updateCounts();
  } catch (error) {
    toast("Could not save curation", error.message, "error");
  }
}

function toggleAtlasCompare(itemId) {
  if (state.atlasCompare.has(itemId)) state.atlasCompare.delete(itemId);
  else if (state.atlasCompare.size >= 3) { toast("Comparison tray is full", "Remove one of the three specimens before adding another.", "warn"); return; }
  else state.atlasCompare.add(itemId);
  localStorage.setItem("captcha-atlas-compare", JSON.stringify([...state.atlasCompare]));
  refreshAtlasCompareUi();
}

function refreshAtlasCompareUi() {
  document.querySelectorAll("[data-atlas-compare]").forEach((button) => {
    const selected = state.atlasCompare.has(button.dataset.atlasCompare);
    if (button.classList.contains("atlas-compare-button")) {
      button.classList.toggle("is-active", selected);
      button.textContent = selected ? "✓" : "+";
      button.setAttribute("aria-label", `${selected ? "Remove from" : "Add to"} comparison`);
    } else {
      button.textContent = selected ? "Remove comparison" : "Add to compare";
    }
  });
  const dock = document.getElementById("atlas-dock-root");
  if (dock) dock.innerHTML = atlasCompareDockMarkup();
}

function openAtlasCompare() {
  const specimens = [...state.atlasCompare].map(findAtlasItem).filter(Boolean);
  if (!specimens.length) return;
  modalShell(`<header class="modal-head"><div><small>Evidence comparison</small><h2>${specimens.length} candidate records</h2></div><button class="modal-close" type="button" data-action="close-modal" aria-label="Close">×</button></header><div class="atlas-compare-grid" style="--compare-count:${specimens.length}">${specimens.map((item) => `<article><div class="compare-cover">${atlasCoverMarkup(item)}</div><small>${escapeHtml(item.source_label)}</small><h3>${escapeHtml(item.title)}</h3><p>${escapeHtml(item.summary || item.prompt)}</p><dl><div><dt>Layer</dt><dd>${escapeHtml(titleCase(item.layer))}</dd></div><div><dt>Interaction</dt><dd>${escapeHtml(titleCase(item.action_type || item.interaction))}</dd></div><div><dt>Evidence</dt><dd>${item.artifact_count ?? item.asset_count ?? 0} attached</dd></div><div><dt>Decision</dt><dd>${atlasDecisionLabel(item.curation?.decision || "unreviewed")}</dd></div></dl><button class="button button-ghost button-wide" type="button" ${item.layer === "instance" ? `data-open-atlas-instance="${escapeHtml(item.id)}"` : `data-open-atlas-item="${escapeHtml(item.id)}"`}>Open record ${arrowIcon}</button></article>`).join("")}</div>`, "atlas-compare-modal");
}

async function switchAtlasArtifactKind(sourceSlug, kind) {
  state.atlasSourceKinds.set(sourceSlug, kind);
  const key = `${sourceSlug}:${kind}`;
  if (!state.atlasArtifactPages.has(key)) {
    try { state.atlasArtifactPages.set(key, await api(`/api/atlas/sources/${encodeURIComponent(sourceSlug)}/artifacts?kind=${encodeURIComponent(kind)}&limit=48`)); }
    catch (error) { toast("Could not load artifacts", error.message, "error"); return; }
  }
  refreshAtlasSourceArtifacts(sourceSlug);
}

async function loadMoreAtlasArtifacts(sourceSlug) {
  const kind = state.atlasSourceKinds.get(sourceSlug) || "all";
  const key = `${sourceSlug}:${kind}`;
  const current = state.atlasArtifactPages.get(key);
  if (!current || !current.has_more) return;
  try {
    const next = await api(`/api/atlas/sources/${encodeURIComponent(sourceSlug)}/artifacts?kind=${encodeURIComponent(kind)}&offset=${current.artifacts.length}&limit=48`);
    current.artifacts.push(...next.artifacts);
    current.has_more = next.has_more;
    refreshAtlasSourceArtifacts(sourceSlug);
  } catch (error) {
    toast("Could not load more artifacts", error.message, "error");
  }
}

function refreshAtlasSourceArtifacts(sourceSlug) {
  const kind = state.atlasSourceKinds.get(sourceSlug) || "all";
  const current = state.atlasArtifactPages.get(`${sourceSlug}:${kind}`);
  if (!current) return;
  document.querySelectorAll("[data-atlas-artifact-kind]").forEach((button) => button.classList.toggle("is-active", button.dataset.atlasArtifactKind === kind));
  const summary = document.getElementById("source-artifact-summary");
  if (summary) summary.innerHTML = `<span>${current.artifacts.length}</span> of ${formatNumber(current.total)} ${kind === "all" ? "files" : `${escapeHtml(kind)} files`} visible.`;
  const grid = document.getElementById("source-artifact-grid");
  if (grid) grid.innerHTML = current.artifacts.map(artifactMarkup).join("");
  const loadRoot = document.getElementById("artifact-load-root");
  if (loadRoot) loadRoot.innerHTML = current.has_more ? `<button class="button button-ghost button-wide artifact-load-more" type="button" data-atlas-load-artifacts="${escapeHtml(sourceSlug)}">Load more evidence</button>` : "";
}

function sessionStatusLabel(status) {
  return {queued: "queued", booting: "booting", running: "live", stopping: "stopping", stopped: "stopped", failed: "failed"}[status] || status;
}

function sessionCard(session) {
  const info = session.session || {};
  const active = ["queued", "booting", "running", "stopping"].includes(session.status);
  const running = session.status === "running";
  const address = running && info.vnc_port ? `localhost::${info.vnc_port}` : session.phase_message;
  const connectionLabel = running ? "TigerVNC address" : active ? "Runner state" : "Final state";
  const logsExpanded = state.expandedLogs.has(session.id);
  return `<article class="session-card" data-session-id="${escapeHtml(session.id)}" data-status="${escapeHtml(session.status)}" style="--status-color:${statusColor(session.status)}">
    <div class="session-main">
      <div><div class="session-title-row"><i class="session-beacon"></i><h3>${escapeHtml(session.title)}</h3><span class="status-pill" style="--status-color:${statusColor(session.status)}">${escapeHtml(sessionStatusLabel(session.status))}</span></div><p class="session-meta">${escapeHtml(session.task_id)} · seed ${session.seed}<span data-session-uptime>${session.uptime_seconds != null ? ` · ${elapsedLabel(session.uptime_seconds)}` : ""}</span></p></div>
      <div class="session-connection"><small>${connectionLabel}</small><code>${escapeHtml(address)}</code>${running && info.vnc_password ? `<small>Password · ${escapeHtml(info.vnc_password)}</small>` : ""}</div>
      <div class="session-actions">
        ${session.status === "running" ? `<button class="button button-acid button-small" type="button" data-open-vnc="${session.id}">Open VNC</button><button class="button button-ghost button-small" type="button" data-copy="${escapeHtml(address)}">Copy</button>` : ""}
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
    stopped: state.sessions.filter((session) => ["stopped", "failed"].includes(session.status)).length,
  };
}

function sessionListSignature() {
  return JSON.stringify(state.sessions.map((session) => [
    session.id,
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
    : `<div class="empty-state"><div class="empty-state-mark"></div><h2>No machines are awake.</h2><p>Launch any built environment. The dashboard will boot its VM, wait for a stable VNC endpoint, and open TigerVNC automatically.</p><button class="button button-acid" type="button" data-action="open-launch-picker">Choose an environment</button></div>`;
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
    <header class="page-head"><div><p class="eyebrow">Runtime control</p><h1 class="page-title">Live specimens.</h1><p class="page-copy">Boot, inspect, reconnect, and stop real Gym-Anything environments. Session metadata comes directly from the runner—no guessed ports.</p></div><div class="page-head-actions"><button class="button button-acid" type="button" data-action="open-launch-picker">New VNC session ${arrowIcon}</button></div></header>
    <section class="summary-cards"><div class="summary-card"><small>Active sessions</small><b id="session-active-count">${counts.active}</b><span>booting or live</span></div><div class="summary-card"><small>VNC ready</small><b id="session-ready-count">${counts.ready}</b><span>viewer can attach</span></div><div class="summary-card"><small>Runner</small><b style="font-size:25px">${escapeHtml(state.system.runner)}</b><span>local execution backend</span></div><div class="summary-card"><small>Session history</small><b id="session-history-count">${state.sessions.length}</b><span id="session-history-note">${counts.stopped} completed / failed</span></div></section>
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
  if (!state.catalog || !state.reviews || !state.atlas || !state.system) return;
  state.route = parseRoute();
  if (state.route.name === "observatory") renderObservatory();
  else if (state.route.name === "environments") renderEnvironments();
  else if (state.route.name === "reviews") renderReviewQueue();
  else if (state.route.name === "environment") renderEnvironmentDetail(state.route.id);
  else if (state.route.name === "atlas") renderAtlas();
  else if (state.route.name === "atlas-item") renderAtlasItem(state.route.id);
  else if (state.route.name === "atlas-instance") renderAtlasInstance(state.route.id);
  else if (state.route.name === "atlas-source") renderAtlasSource(state.route.id);
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

function openLaunchDialog(environment) {
  const taskOptions = environment.tasks.map((task) => `<option value="${escapeHtml(task.id)}">${escapeHtml(task.id)}</option>`).join("");
  modalShell(`<header class="modal-head"><div><small>Launch environment</small><h2>${escapeHtml(environment.title)}</h2></div><button class="modal-close" type="button" data-action="close-modal" aria-label="Close">×</button></header><form class="modal-body" id="launch-form" data-environment="${escapeHtml(environment.id)}">
    <div class="modal-callout">This boots the actual ${escapeHtml(state.system.runner.toUpperCase())} environment. With auto-open enabled, TigerVNC appears as soon as the runner publishes a stable port.</div>
    <div class="form-grid">
      <div class="form-field is-wide"><label for="launch-task">Task</label><select id="launch-task" name="task_id">${taskOptions}</select></div>
      <div class="form-field"><label for="launch-seed">Seed</label><input id="launch-seed" name="seed" type="number" min="0" max="2147483647" value="${Math.floor(Math.random() * 1_000_000)}"></div>
      <div class="form-field"><label>Runner</label><input value="${escapeHtml(state.system.runner)}" disabled></div>
    </div>
    <div class="switch-row" style="margin-top:17px"><div class="switch-copy"><b>Open TigerVNC automatically</b><span>One click starts the environment; the viewer opens after boot without another action.</span></div><label class="switch"><input name="auto_open" type="checkbox" checked><i></i></label></div>
    <div class="modal-actions"><button class="button button-ghost" type="button" data-action="close-modal">Cancel</button><button class="button button-acid" type="submit">Launch specimen ${arrowIcon}</button></div>
  </form>`);
}

function openEvalDialog(environment) {
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
  toast("Launch requested", `${environment.title} is entering the boot queue.`, "info");
  try {
    const session = await api("/api/sessions", {method: "POST", body: JSON.stringify({environment_id: environment.id, task_id: environment.tasks[0].id, seed: Math.floor(Math.random() * 1_000_000), auto_open: true})});
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
    const session = await api("/api/sessions", {method: "POST", body: JSON.stringify({environment_id: form.dataset.environment, task_id: data.get("task_id"), seed: Number(data.get("seed")), auto_open: data.get("auto_open") === "on"})});
    state.sessions.unshift(session);
    closeModal();
    toast("Environment queued", "TigerVNC will open when the machine is ready.", "success");
    if (parseRoute().name === "sessions") refreshSessionsPage({forceList: true});
    else navigate("sessions");
  } catch (error) {
    button.disabled = false;
    button.innerHTML = `Launch specimen ${arrowIcon}`;
    toast("Could not launch", error.message, "error");
  }
}

async function submitEvaluation(form) {
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
  try {
    const [sessionPayload, evaluationPayload] = await Promise.all([api("/api/sessions"), api("/api/evaluations")]);
    const nextSessions = sessionPayload.sessions || [];
    nextSessions.forEach((session) => {
      const previous = state.previousSessionStatus.get(session.id);
      if (previous && previous !== "running" && session.status === "running") toast("VNC is ready", `${session.title} is live at localhost::${session.session?.vnc_port}.`, "success", 7000);
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
  const target = event.target.closest("button, [data-open-env], [data-open-atlas-item], [data-open-atlas-instance], [data-open-atlas-source], [data-nav], [data-action]");
  if (!target) return;
  if (target.dataset.reviewChoice) { selectReviewChoice(target); return; }
  if (target.dataset.reviewFilter) { state.reviewFilters.status = target.dataset.reviewFilter; refreshReviewQueue(); return; }
  if (target.dataset.atlasCompare) { event.stopPropagation(); toggleAtlasCompare(target.dataset.atlasCompare); return; }
  if (target.dataset.atlasDecision) { await updateAtlasCuration(target.dataset.atlasItem, {decision: target.dataset.atlasDecision}); return; }
  if (target.dataset.atlasPromote) { await updateAtlasCuration(target.dataset.atlasPromote, {decision: "shortlisted", promoted: target.dataset.promoted !== "true"}); return; }
  if (target.dataset.atlasDecisionFilter) { state.atlasFilters.decision = target.dataset.atlasDecisionFilter; refreshAtlasCatalog(); return; }
  if (target.dataset.atlasView) { state.atlasFilters.view = target.dataset.atlasView; state.atlasFilters.decision = "all"; state.atlasFilters.type = "all"; renderAtlas(); return; }
  if (target.dataset.atlasSourceInstances) { state.atlasFilters.view = "instances"; state.atlasFilters.instanceSource = target.dataset.atlasSourceInstances; state.atlasFilters.family = "all"; state.atlasFilters.query = ""; state.atlasInstanceSignature = ""; navigate("atlas"); return; }
  if (target.dataset.atlasArtifactKind) { await switchAtlasArtifactKind(target.dataset.atlasSource, target.dataset.atlasArtifactKind); return; }
  if (target.dataset.atlasLoadArtifacts) { await loadMoreAtlasArtifacts(target.dataset.atlasLoadArtifacts); return; }
  if (target.dataset.quickLaunch) { event.stopPropagation(); await quickLaunch(target.dataset.quickLaunch); return; }
  if (target.dataset.configLaunch) { const environment = findEnvironment(target.dataset.configLaunch); if (environment) openLaunchDialog(environment); return; }
  if (target.dataset.openEval) { const environment = findEnvironment(target.dataset.openEval); if (environment) openEvalDialog(environment); return; }
  if (target.dataset.openVnc) {
    try { await api(`/api/sessions/${target.dataset.openVnc}/open`, {method: "POST", body: "{}"}); toast("Opening TigerVNC", "Use password from the session card.", "success"); } catch (error) { toast("Could not open VNC", error.message, "error"); }
    return;
  }
  if (target.dataset.stopSession) {
    try { await api(`/api/sessions/${target.dataset.stopSession}/stop`, {method: "POST", body: "{}"}); toast("Stopping environment", "The VM and its forwarded ports are being cleaned up.", "warn"); await pollJobs(); } catch (error) { toast("Could not stop", error.message, "error"); }
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
  if (target.dataset.openAtlasItem) { closeModal(); navigate(`atlas/item/${encodeURIComponent(target.dataset.openAtlasItem)}`); return; }
  if (target.dataset.openAtlasInstance) { closeModal(); navigate(`atlas/instance/${encodeURIComponent(target.dataset.openAtlasInstance)}`); return; }
  if (target.dataset.openAtlasSource) { closeModal(); navigate(`atlas/source/${encodeURIComponent(target.dataset.openAtlasSource)}`); return; }
  if (target.dataset.action) {
    const action = target.dataset.action;
    if (action === "close-modal") {
      if (event.target.classList.contains("modal-backdrop") || target.classList.contains("modal-close") || target.closest("form")) closeModal();
    } else if (action === "open-launch-picker") openLaunchPicker();
    else if (action === "open-eval-picker") openEvalPicker();
    else if (action === "browse-environments" || action === "back-to-environments") navigate("environments");
    else if (action === "back-to-reviews") navigate("reviews");
    else if (action === "browse-atlas") navigate("atlas");
    else if (action === "back-to-atlas") navigate("atlas");
    else if (action === "open-review-desk") document.getElementById("review-desk")?.scrollIntoView({behavior: "smooth", block: "start"});
    else if (action === "random-atlas-record") {
      if (state.atlasFilters.view === "sources") {
        const candidates = filteredAtlasSources(); const source = candidates[Math.floor(Math.random() * candidates.length)]; if (source) navigate(`atlas/source/${encodeURIComponent(source.slug)}`);
      } else if (state.atlasFilters.view === "instances") {
        const candidates = state.atlasInstancePage?.instances || state.atlas.featured_instances; const instance = candidates[Math.floor(Math.random() * candidates.length)]; if (instance) navigate(`atlas/instance/${encodeURIComponent(instance.id)}`);
      } else {
        const candidates = filteredAtlasItems(); const item = candidates[Math.floor(Math.random() * candidates.length)]; if (item) navigate(`atlas/item/${encodeURIComponent(item.id)}`);
      }
    } else if (action === "load-more-atlas-instances") {
      await loadAtlasInstances({append: true});
    } else if (action === "open-atlas-compare") openAtlasCompare();
    else if (action === "clear-atlas-compare") {
      state.atlasCompare.clear();
      localStorage.removeItem("captcha-atlas-compare");
      const route = parseRoute();
      if (route.name === "atlas") refreshAtlasCatalog();
      else if (route.name === "atlas-item") renderAtlasItem(route.id);
    }
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
  const atlasCard = event.target.closest('[data-open-atlas-item][role="button"], [data-open-atlas-instance][role="button"], [data-open-atlas-source][role="button"]');
  if (atlasCard && ["Enter", " "].includes(event.key)) {
    event.preventDefault();
    if (atlasCard.dataset.openAtlasItem) navigate(`atlas/item/${encodeURIComponent(atlasCard.dataset.openAtlasItem)}`);
    else if (atlasCard.dataset.openAtlasInstance) navigate(`atlas/instance/${encodeURIComponent(atlasCard.dataset.openAtlasInstance)}`);
    else navigate(`atlas/source/${encodeURIComponent(atlasCard.dataset.openAtlasSource)}`);
  }
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
  if (event.target.id === "atlas-search") {
    state.atlasFilters.query = event.target.value;
    if (state.atlasFilters.view === "instances") {
      window.clearTimeout(state.atlasSearchTimer);
      state.atlasSearchTimer = window.setTimeout(() => { state.atlasInstanceSignature = ""; loadAtlasInstances(); }, 260);
    } else refreshAtlasCatalog();
  }
});

document.addEventListener("change", (event) => {
  if (event.target.id === "stage-filter") { state.filters.stage = event.target.value; refreshEnvironmentCatalog(); }
  if (event.target.id === "review-filter") { state.filters.review = event.target.value; refreshEnvironmentCatalog(); }
  if (event.target.id === "atlas-status-filter") { state.atlasFilters.status = event.target.value; refreshAtlasCatalog(); }
  if (event.target.id === "atlas-type-filter") { state.atlasFilters.type = event.target.value; refreshAtlasCatalog(); }
  if (event.target.id === "atlas-sort") { state.atlasFilters.sort = event.target.value; refreshAtlasCatalog(); }
  if (event.target.id === "atlas-instance-source") { state.atlasFilters.instanceSource = event.target.value; state.atlasFilters.family = "all"; state.atlasInstanceSignature = ""; renderAtlas(); }
  if (event.target.id === "atlas-instance-family") { state.atlasFilters.family = event.target.value; state.atlasInstanceSignature = ""; refreshAtlasCatalog(); }
  if (event.target.id === "atlas-record-type") { state.atlasFilters.recordType = event.target.value; state.atlasInstanceSignature = ""; refreshAtlasCatalog(); }
});

document.addEventListener("submit", (event) => {
  if (event.target.id === "launch-form") { event.preventDefault(); submitLaunch(event.target); }
  if (event.target.id === "eval-form") { event.preventDefault(); submitEvaluation(event.target); }
  if (event.target.id === "atlas-note-form") { event.preventDefault(); updateAtlasCuration(event.target.dataset.atlasItem, {note: new FormData(event.target).get("note")}); }
  if (event.target.id === "environment-review-form") { event.preventDefault(); submitEnvironmentReview(event.target); }
});

document.getElementById("global-search-button").addEventListener("click", () => openCommandPalette("browse"));
document.querySelector(".mobile-nav-toggle").addEventListener("click", () => document.body.classList.toggle("nav-open"));
window.addEventListener("hashchange", render);

async function init() {
  try {
    const [catalog, reviews, atlas, system, sessions, evaluations] = await Promise.all([
      api("/api/catalog"),
      api("/api/reviews"),
      api("/api/atlas"),
      api("/api/system"),
      api("/api/sessions"),
      api("/api/evaluations"),
    ]);
    state.catalog = catalog;
    state.reviews = reviews;
    state.atlas = atlas;
    state.system = system;
    state.sessions = sessions.sessions || [];
    state.evaluations = evaluations.evaluations || [];
    state.sessions.forEach((session) => state.previousSessionStatus.set(session.id, session.status));
    if (!location.hash) history.replaceState(null, "", "#/observatory");
    render();
    window.setInterval(pollJobs, 1600);
  } catch (error) {
    app.innerHTML = `<section class="loading-screen"><p style="color:#ff8f7e">Dashboard failed to initialize: ${escapeHtml(error.message)}</p></section>`;
  }
}

init();
