/* CUA-World visualizer — frontend.

   No framework. State lives in `state`; tabs are simple show/hide.
   API surface is documented in server/app.py. Search is debounced; semantic
   query embeddings are cached server-side.
*/

const $  = (sel, root) => (root || document).querySelector(sel);
const $$ = (sel, root) => Array.from((root || document).querySelectorAll(sel));

const state = {
  query: "",
  exact: false,
  filters: { soc: null, os: null, kind: null, long_horizon: null, split: null },
  envFilter: null,
  productFilter: null,
  facets: null,
  meta: null,
  favorites: { items: [] },
  abortCtrl: null,
  searchSeq: 0,
  occActive: null,
  softwareSort: "gdp",
  softwareFilter: "",
  softwareItems: [],
  liked: new Set(JSON.parse(localStorage.getItem("cuaw_liked") || "[]")),
};

function persistLiked() {
  localStorage.setItem("cuaw_liked", JSON.stringify(Array.from(state.liked)));
}

/* -------------------- helpers -------------------- */

function escHtml(s) {
  return String(s == null ? "" : s).replace(/[&<>"']/g, m => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[m]);
}

function highlight(text, q) {
  text = escHtml(text);
  if (!q) return text;
  const safe = q.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return text.replace(new RegExp(safe, "gi"), m => `<mark>${escHtml(m)}</mark>`);
}

function fmtUsd(n) {
  if (!n || n <= 0) return "—";
  const abs = Math.abs(n);
  if (abs >= 1e12) return "$" + (n / 1e12).toFixed(2) + "T";
  if (abs >= 1e9)  return "$" + (n / 1e9).toFixed(2) + "B";
  if (abs >= 1e6)  return "$" + (n / 1e6).toFixed(1) + "M";
  return "$" + n.toFixed(0);
}

function debounce(fn, ms) {
  let t = null;
  return (...args) => {
    if (t) clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}

function copyToClipboard(text) {
  if (navigator.clipboard) navigator.clipboard.writeText(text);
}

function tagInitials(name) {
  if (!name) return "?";
  return name.split(/\s+/).slice(0, 2).map(w => w[0] || "").join("").toUpperCase();
}

function colorForString(s) {
  let h = 0; s = String(s || "");
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return `hsl(${h % 360} 60% 38%)`;
}

/* -------------------- API -------------------- */

async function api(path, params) {
  // Static-mode dispatches to a local in-memory adapter so the same UI works
  // when the page is served from a CDN with no backend.
  if (window.STATIC_MODE && window.staticApi) {
    return window.staticApi(path, params || {});
  }
  const url = new URL(path, location.origin);
  if (params) for (const [k, v] of Object.entries(params)) {
    if (v == null || v === "") continue;
    url.searchParams.set(k, v);
  }
  const r = await fetch(url, { method: "GET" });
  if (!r.ok) throw new Error(`${url.pathname} → ${r.status}`);
  return r.json();
}

/* -------------------- tab switching -------------------- */

function setTab(tab) {
  $$(".tab-pane").forEach(p => p.classList.remove("active"));
  $$(".tab-btn").forEach(b => b.classList.toggle("active", b.dataset.tab === tab));
  const pane = document.getElementById("tab-" + tab);
  if (pane) pane.classList.add("active");
  history.replaceState(null, "", "#" + tab);
  if (tab === "software" && !state.softwareItems.length) loadSoftware();
  if (tab === "occupations") loadOccupations();
  if (tab === "insights") loadInsights();
  window.scrollTo({ top: 0, behavior: "instant" });
}

/* -------------------- card rendering -------------------- */

function complexityDots(n) {
  const cap = Math.max(1, Math.min(5, n || 0));
  const dots = [];
  for (let i = 1; i <= 5; i++) {
    dots.push(`<i class="${i <= cap ? "on" : ""}"></i>`);
  }
  return `<span class="complexity">${dots.join("")}</span>`;
}

function renderCard(t, q) {
  const product = t.product || t.env_id;
  const kind = t.task_kind || "task";
  const soc = (t.soc_major_groups || [])[0];
  const id = `${t.env_id}/${t.task_id}`;
  const isLiked = state.liked.has(id);

  const badges = [];
  if (soc) badges.push(`<span class="badge soc" title="SOC major group">${escHtml(soc.split(/[, ]/).slice(0, 3).join(" "))}</span>`);
  badges.push(`<span class="badge kind">${escHtml(kind)}</span>`);
  if (t.os_type && t.os_type !== "linux") badges.push(`<span class="badge os">${escHtml(t.os_type)}</span>`);
  if (t.is_long_horizon) badges.push(`<span class="badge long">long-horizon</span>`);
  if (t.tier) badges.push(`<span class="badge tier">${escHtml(t.tier)}</span>`);

  const score = t.score != null ? t.score : null;
  const scoreLabel = score != null ? score.toFixed(2) : (state.liked.has(id) ? "★" : "");

  return `
    <div class="card" data-env="${escHtml(t.env_id)}" data-task="${escHtml(t.task_id)}">
      <div class="card-title-bar">
        <span class="dots"><i></i><i></i><i></i></span>
        <span class="card-title">
          <span class="file-stem">${highlight(t.task_id, q)}</span><span class="file-ext">.json</span>
        </span>
        ${scoreLabel ? `<span class="card-score">★ ${escHtml(scoreLabel)}</span>` : ""}
      </div>
      <div class="card-body">
        <div class="card-from">
          <span class="icon-bubble" style="background:${colorForString(product)}">${escHtml(tagInitials(product))}</span>
          <span><span class="from-key">from</span> <span class="from-val">"${highlight(t.env_id, q)}"</span></span>
        </div>
        <div class="card-intent">${highlight(t.intent || t.summary || "", q)}</div>
        <div class="card-meta">${badges.join("")}</div>
      </div>
      <div class="card-foot">
        ${complexityDots(t.complexity)}
        <span>${escHtml((t.domains || [])[0] || "")}</span>
        <button class="heart ${isLiked ? "on" : ""}" data-fav="${escHtml(id)}" title="favorite">${isLiked ? "♥" : "♡"}</button>
      </div>
    </div>
  `;
}

/* -------------------- favorites -------------------- */

async function loadFavorites() {
  const data = await api("/api/favorites");
  state.favorites = data;
  const blurb = $("#fav-blurb");
  blurb.textContent = data.blurb ? `// ${data.blurb}` : "";
  const grid = $("#favorites-grid");
  if (!data.items.length) {
    grid.innerHTML = `<div style="color:var(--text-3); padding:1rem;">No curated favorites yet. Edit <code>data/favorites.json</code>.</div>`;
    return;
  }
  // Use the same card markup but score field becomes ★.
  grid.innerHTML = data.items.filter(i => !i.missing).map(i => renderCard({
    env_id: i.env_id, task_id: i.task_id,
    product: i.product, task_name: i.task_name,
    intent: i.blurb || i.intent, summary: i.summary,
    task_kind: i.task_kind, complexity: i.complexity,
    is_long_horizon: i.is_long_horizon,
    soc_major_groups: i.soc_major_groups || [],
    domains: [], occupations: [], themes: [],
    score: null,
  })).join("");
  attachCardEvents(grid);
}

/* -------------------- search -------------------- */

const triggerSearch = debounce(_runSearch, 250);

function setQuery(q, opts = {}) {
  state.query = q;
  $("#q").value = q;
  if (opts.now) _runSearch();
  else triggerSearch();
}

async function _runSearch() {
  const q = state.query.trim();
  const seq = ++state.searchSeq;

  const favSection = $("#favorites-section");
  const resSection = $("#results-section");
  const anyFilter = state.filters.soc || state.filters.os || state.filters.kind
                 || state.filters.long_horizon != null || state.filters.split
                 || state.envFilter || state.productFilter;
  if (!q && !anyFilter) {
    favSection.hidden = false;
    resSection.hidden = true;
    return;
  }
  favSection.hidden = true;
  resSection.hidden = false;
  const grid = $("#results-grid");
  grid.innerHTML = `<div style="color:var(--text-3); padding:1rem;">searching…</div>`;

  let exact = state.exact;
  let qSent = q;
  // Allow inline "..." even without the toggle.
  if (q.length >= 2 && q.startsWith('"') && q.endsWith('"')) {
    qSent = q.slice(1, -1);
    exact = true;
  }

  let data;
  const envOrProduct = state.envFilter || state.productFilter;
  try {
    data = await api("/api/search", {
      q: qSent,
      topk: 60,
      exact: exact ? 1 : 0,
      diversify: envOrProduct ? 0 : 1,
      per_env_cap: envOrProduct ? 999 : 4,
      env: state.envFilter || null,
      product: state.productFilter || null,
      split: state.filters.split || null,
      soc: state.filters.soc,
      os: state.filters.os,
      kind: state.filters.kind,
      long_horizon: state.filters.long_horizon,
    });
  } catch (e) {
    if (seq !== state.searchSeq) return;
    grid.innerHTML = `<div style="color:var(--red); padding:1rem;">search failed: ${escHtml(String(e))}</div>`;
    return;
  }
  if (seq !== state.searchSeq) return;

  $("#results-label").textContent = qSent || "(empty)";
  $("#results-count").textContent = `${data.total} result${data.total === 1 ? "" : "s"}${exact ? " · exact" : ""}`;
  if (!data.results.length) {
    grid.innerHTML = `<div style="color:var(--text-3); padding:1rem;">no matches. try a different keyword, or remove a filter.</div>`;
    return;
  }
  grid.innerHTML = data.results.map(t => renderCard(t, qSent)).join("");
  attachCardEvents(grid);
}

function attachCardEvents(root) {
  $$(".card", root).forEach(card => {
    card.addEventListener("click", (e) => {
      if (e.target.closest(".heart")) return;
      const env = card.dataset.env, task = card.dataset.task;
      openTask(env, task);
    });
  });
  $$(".heart", root).forEach(h => {
    h.addEventListener("click", (e) => {
      e.stopPropagation();
      const id = h.dataset.fav;
      if (state.liked.has(id)) state.liked.delete(id); else state.liked.add(id);
      h.classList.toggle("on", state.liked.has(id));
      h.textContent = state.liked.has(id) ? "♥" : "♡";
      persistLiked();
    });
  });
}

/* -------------------- filters / chips -------------------- */

function buildChip(label, count, opts) {
  const cls = ["chip"];
  if (opts.active) cls.push("active");
  return `<button class="${cls.join(" ")}" data-key="${escHtml(opts.key)}" data-group="${escHtml(opts.group)}">
    ${label ? `<span class="chip-label">${escHtml(label)}</span>` : ""}
    ${escHtml(opts.text)}
    ${count != null ? `<span class="chip-count">${count}</span>` : ""}
  </button>`;
}

function renderFilters() {
  const f = state.facets || {};
  const top = (xs, k) => (xs || []).slice(0, k);

  // Env- or product-pinned indicator (shown when navigating from Software/Occupations).
  let envChip = "";
  if (state.envFilter) {
    envChip =
      `<span class="chip-label">env</span>` +
      `<button class="chip active" data-key="${escHtml(state.envFilter)}" data-group="env">
         ${escHtml(state.envFilter)} <span class="chip-count">×</span>
       </button>`;
  } else if (state.productFilter) {
    envChip =
      `<span class="chip-label">product</span>` +
      `<button class="chip active" data-key="${escHtml(state.productFilter)}" data-group="product">
         ${escHtml(state.productFilter)} <span class="chip-count">×</span>
       </button>`;
  }

  const socEl = $("#filter-soc");
  socEl.innerHTML = envChip + `<span class="chip-label">soc</span>` +
    top(f.soc_major_groups, 5).map(s => buildChip(null, s.count, {
      key: s.key, group: "soc", text: s.key.replace(" Occupations", ""),
      active: state.filters.soc === s.key,
    })).join("");

  const osEl = $("#filter-os");
  osEl.innerHTML = `<span class="chip-label">os</span>` +
    (f.os_types || []).slice(0, 4).map(s => buildChip(null, s.count, {
      key: s.key, group: "os", text: s.key, active: state.filters.os === s.key,
    })).join("");

  const kindEl = $("#filter-kind");
  kindEl.innerHTML = `<span class="chip-label">kind</span>` +
    (f.task_kinds || []).slice(0, 8).map(s => buildChip(null, s.count, {
      key: s.key, group: "kind", text: s.key, active: state.filters.kind === s.key,
    })).join("");

  const flagsEl = $("#filter-flags");
  flagsEl.innerHTML =
    `<span class="chip-label">flags</span>` +
    buildChip(null, null, { key: "long", group: "flags", text: "long-horizon",
      active: state.filters.long_horizon === true }) +
    buildChip(null, null, { key: "fav", group: "flags", text: "★ liked",
      active: false /* one-shot button, not a sticky filter */ });

  $$(".chip", $(".filter-row")).forEach(c => {
    c.addEventListener("click", () => {
      const grp = c.dataset.group, key = c.dataset.key;
      if (grp === "env") {
        state.envFilter = null;
      } else if (grp === "product") {
        state.productFilter = null;
      } else if (grp === "flags") {
        if (key === "long") {
          state.filters.long_horizon = state.filters.long_horizon === true ? null : true;
        } else if (key === "fav") {
          state.envFilter = null;
          setQuery("", { now: true });
          return;
        }
      } else if (state.filters[grp] === key) {
        state.filters[grp] = null;
      } else {
        state.filters[grp] = key;
      }
      renderFilters();
      _runSearch();
    });
  });
}

/* -------------------- task modal -------------------- */

async function openTask(envId, taskId) {
  const modal = $("#task-modal");
  modal.hidden = false;
  document.body.style.overflow = "hidden";
  $("#modal-body").innerHTML = `<div style="color:var(--text-3);">loading…</div>`;
  $("#modal-title").textContent = `${envId}/${taskId}.json`;

  let data;
  try {
    data = await api(`/api/task/${encodeURIComponent(envId)}/${encodeURIComponent(taskId)}`);
  } catch (e) {
    $("#modal-body").innerHTML = `<div style="color:var(--red);">${escHtml(String(e))}</div>`;
    return;
  }
  const t = data.task, env = data.env;
  const cmd = `gym-anything run ${envId} --task ${taskId} -i --open-vnc`;
  const occList = (t.occupations || []).slice(0, 8).map(o => `<span class="badge">${escHtml(o)}</span>`).join("");
  const socList = (t.soc_major_groups || []).map(o => `<span class="badge">${escHtml(o)}</span>`).join("");
  const themes  = (t.themes || []).map(o => `<span class="badge">${escHtml(o)}</span>`).join("");
  const skills  = (t.skills || []).map(o => `<span class="badge">${escHtml(o)}</span>`).join("");
  const informs = (t.informal_phrases || []).map(o => `<span class="badge">"${escHtml(o)}"</span>`).join("");
  const topOccs = (env.top_occupations || []).slice(0, 6)
      .map(o => `<span class="badge">${escHtml(o.occupation)} · ${o.share_pct.toFixed(1)}%</span>`).join("");

  const LLM_TAG = `<span class="occ-source-tag warn" title="Generated post-hoc by gpt-5.4-nano during visualizer indexing. Not part of CUA-World, not curated, quality varies.">LLM · post-hoc · not in CUA-World</span>`;
  const SOC_TAG = `<span class="occ-source-tag" title="22 BLS SOC major groups (real taxonomy). The set picked for this task is gpt-5.4-nano's classification from that closed enum.">SOC · LLM-classified</span>`;
  const CATALOG_TAG = `<span class="occ-source-tag ok" title="From the GDP-grounded selection catalog (BLS-derived). Real attribution, not LLM-generated.">catalog</span>`;
  const VERBATIM_TAG = `<span class="occ-source-tag ok" title="The original task.json description from the CUA-World corpus, verbatim.">task.json verbatim</span>`;
  $("#modal-body").innerHTML = `
    <div class="modal-section">
      <h4>Intent ${LLM_TAG}</h4>
      <p>${escHtml(t.intent)}</p>
      <p style="color:var(--text-2);">${escHtml(t.summary)}</p>
    </div>
    <div class="modal-section">
      <h4>Run command</h4>
      <div class="modal-cmd"><span class="prompt">$</span> ${escHtml(cmd)}
        <button onclick="this.previousElementSibling; navigator.clipboard.writeText('${cmd.replace(/'/g, "\\'")}'); this.textContent='copied!'; setTimeout(()=>this.textContent='copy', 1200);">copy</button>
      </div>
    </div>
    <div class="modal-section">
      <dl class="modal-grid">
        <dt>software</dt><dd>${escHtml(t.product)}</dd>
        <dt>env_id</dt><dd>${escHtml(t.env_id)}</dd>
        <dt>os</dt><dd>${escHtml(t.os_type || "—")}</dd>
        <dt>difficulty</dt><dd>${escHtml(t.difficulty || "—")} · complexity ${t.complexity}/5${t.is_long_horizon ? " · long-horizon" : ""}</dd>
        <dt>kind</dt><dd>${escHtml(t.task_kind)}</dd>
        <dt>tier</dt><dd>${escHtml(t.tier || "—")}</dd>
        <dt>GDP</dt><dd>${env.total_gdp_usd ? fmtUsd(env.total_gdp_usd) : "—"}</dd>
      </dl>
    </div>
    <div class="modal-section">
      <h4>SOC major groups ${SOC_TAG}</h4>
      <div class="badges">${socList || '<span class="badge">none</span>'}</div>
    </div>
    <div class="modal-section">
      <h4>Occupations ${LLM_TAG}</h4>
      <div class="badges">${occList || '<span class="badge">none</span>'}</div>
    </div>
    <div class="modal-section">
      <h4>Themes / informal phrasings ${LLM_TAG}</h4>
      <div class="badges">${themes}</div>
      <div class="badges" style="margin-top:6px;">${informs}</div>
    </div>
    <div class="modal-section">
      <h4>Skills ${LLM_TAG}</h4>
      <div class="badges">${skills}</div>
    </div>
    <div class="modal-section">
      <h4>GDP — top occupations for this software ${CATALOG_TAG}</h4>
      <div class="badges">${topOccs || '<span class="badge">no GDP attribution</span>'}</div>
    </div>
    <div class="modal-section">
      <h4>Original task description ${VERBATIM_TAG}</h4>
      <div class="body-text">${escHtml(t.raw_description)}</div>
    </div>
  `;
}

function closeModal() {
  $("#task-modal").hidden = true;
  document.body.style.overflow = "";
}

/* -------------------- software tab -------------------- */

async function loadSoftware() {
  const grid = $("#software-list");
  grid.innerHTML = `<div style="color:var(--text-3); padding:1rem;">loading…</div>`;
  const data = await api("/api/software", { sort: state.softwareSort });
  state.softwareItems = data.items;
  renderSoftware();
}

function renderSoftware() {
  const grid = $("#software-list");
  const f = state.softwareFilter.toLowerCase();
  const items = state.softwareItems.filter(it => {
    if (!f) return true;
    const haystack = [it.product, it.primary_env_id, ...(it.env_ids || []),
                      ...(it.categories || [])];
    return haystack.some(s => String(s || "").toLowerCase().includes(f));
  });
  if (!items.length) {
    grid.innerHTML = `<div style="color:var(--text-3); padding:1rem;">no software matches.</div>`;
    return;
  }
  grid.innerHTML = items.map(it => {
    const name = it.product || it.primary_env_id;
    const variantCount = (it.env_ids || []).length;
    const variantHint = variantCount > 1
      ? `<span class="sw-variant" title="${escHtml(it.env_ids.join(', '))}">+${variantCount - 1} variant${variantCount > 2 ? 's' : ''}</span>`
      : "";
    return `
    <div class="sw-card" data-product="${escHtml(it.product || '')}" data-env="${escHtml(it.primary_env_id)}">
      <div class="sw-name">
        <span class="icon-bubble" style="background:${colorForString(name)};">${escHtml(tagInitials(name))}</span>
        <span>${escHtml(name)}</span>
        ${it.tier ? `<span class="sw-tier">${escHtml(it.tier)}</span>` : ""}
        ${variantHint}
      </div>
      <div class="sw-stats">
        <span><span class="sw-stat-num">${it.task_count}</span> tasks</span>
        <span>·</span>
        <span><span class="sw-stat-num">${fmtUsd(it.total_gdp_usd)}</span> GDP</span>
        ${it.os_type ? `<span>·</span><span>${escHtml(it.os_type)}</span>` : ""}
      </div>
      <div class="sw-meta">${escHtml(it.description || "")}</div>
      <div class="sw-cats">
        ${(it.categories || []).slice(0, 3).map(c => `<span class="badge">${escHtml(c)}</span>`).join("")}
      </div>
    </div>
  `;
  }).join("");
  $$(".sw-card", grid).forEach(c => {
    c.addEventListener("click", () => openSoftware(c.dataset.product || c.dataset.env, !!c.dataset.product));
  });
}

async function openSoftware(key, isProduct = false) {
  // Switch to tasks tab, filtered to this env (or product, when grouped).
  setTab("tasks");
  state.filters.soc = state.filters.os = state.filters.kind = null;
  state.filters.long_horizon = null;
  if (isProduct) {
    state.productFilter = key;
    state.envFilter = null;
  } else {
    state.envFilter = key;
    state.productFilter = null;
  }
  renderFilters();
  setQuery("", { now: true });
}

/* -------------------- occupations tab -------------------- */

async function loadOccupations() {
  if (state.occLoaded) return;
  state.occLoaded = true;
  const data = await api("/api/occupations");
  $("#soc-list").innerHTML = data.soc_groups.map(g => `
    <div class="occ-item" data-key="${escHtml(g.key)}" data-soc="1">
      <span class="occ-name">${escHtml(g.key.replace(" Occupations", ""))}</span>
      <span class="occ-count">${g.task_count}</span>
    </div>
  `).join("");
  $("#occ-list").innerHTML = data.top_occupations.map(o => `
    <div class="occ-item" data-key="${escHtml(o.name)}" data-soc="0">
      <span class="occ-name">${escHtml(o.name)}</span>
      <span class="occ-count">${o.count}</span>
    </div>
  `).join("");
  $$(".occ-item", $("#tab-occupations")).forEach(it => {
    it.addEventListener("click", () => loadOccupationDetail(it.dataset.key));
  });
}

async function loadOccupationDetail(key) {
  $$(".occ-item", $("#tab-occupations")).forEach(i => i.classList.toggle("active", i.dataset.key === key));
  const detail = $("#occ-detail");
  detail.innerHTML = `<div style="color:var(--text-3);">loading…</div>`;
  const data = await api(`/api/occupations/${encodeURIComponent(key)}`);
  state.occActive = key;
  detail.innerHTML = `
    <h3>${escHtml(key)} <span style="font-size:0.74rem; color:var(--text-3); font-weight:400;">${data.is_soc_group ? "SOC major group" : "occupation"}</span></h3>
    <div class="occ-summary">${data.envs.length} software · ${data.tasks.length} tasks (showing top)</div>
    <div class="occ-section-h">Software (top by task count)</div>
    <div class="occ-envs">
      ${data.envs.slice(0, 24).map(e => `
        <div class="occ-env" data-env="${escHtml(e.env_id)}">
          <span class="name">${escHtml(e.product || e.env_id)}</span>
          <span class="meta">${e.task_count} tasks · ${fmtUsd(e.total_gdp_usd)}${e.tier ? " · " + escHtml(e.tier) : ""}</span>
        </div>
      `).join("")}
    </div>
    <div class="occ-section-h">Tasks</div>
    <div class="occ-tasks">
      ${data.tasks.slice(0, 24).map(t => `
        <div class="occ-task" data-env="${escHtml(t.env_id)}" data-task="${escHtml(t.task_id)}">
          <div>${escHtml(t.intent || t.task_name)}</div>
          <div class="occ-task-meta">${escHtml(t.product || t.env_id)} · ${escHtml(t.task_kind)} · complexity ${t.complexity}/5${t.is_long_horizon ? " · long" : ""}</div>
        </div>
      `).join("")}
    </div>
  `;
  $$(".occ-env", detail).forEach(c => c.addEventListener("click", () => openSoftware(c.dataset.env)));
  $$(".occ-task", detail).forEach(c => c.addEventListener("click", () => openTask(c.dataset.env, c.dataset.task)));
}

/* -------------------- insights tab -------------------- */

async function loadInsights() {
  if (state.insightsLoaded) return;
  state.insightsLoaded = true;
  const body = $("#insights-body");
  body.innerHTML = `<div style="color:var(--text-3);">loading…</div>`;
  const d = await api("/api/insights");

  const maxSocGdp = Math.max(...d.soc_rollup.map(s => s.total_gdp_usd), 1);
  const socBars = d.soc_rollup.map(s => `
    <div class="bar-row">
      <span class="bar-label" data-occ="${escHtml(s.key)}">${escHtml(s.key.replace(" Occupations", ""))}</span>
      <div class="bar-track"><div class="bar-fill" style="width:${(100 * s.total_gdp_usd / maxSocGdp).toFixed(1)}%"></div></div>
      <span class="bar-num">${fmtUsd(s.total_gdp_usd)} · ${s.task_count}t</span>
    </div>
  `).join("");

  const maxTierGdp = Math.max(...d.tiers.map(t => t.total_gdp_usd), 1);
  const tierBars = d.tiers.map(t => `
    <div class="bar-row">
      <span class="bar-label">${escHtml(t.tier)}</span>
      <div class="bar-track"><div class="bar-fill" style="width:${(100 * t.total_gdp_usd / maxTierGdp).toFixed(1)}%"></div></div>
      <span class="bar-num">${fmtUsd(t.total_gdp_usd)} · ${t.env_count} envs</span>
    </div>
  `).join("");

  const maxKind = Math.max(...d.task_kinds.map(k => k.count), 1);
  const kindBars = d.task_kinds.map(k => `
    <div class="bar-row">
      <span class="bar-label">${escHtml(k.key)}</span>
      <div class="bar-track"><div class="bar-fill" style="width:${(100 * k.count / maxKind).toFixed(1)}%"></div></div>
      <span class="bar-num">${k.count}</span>
    </div>
  `).join("");

  const maxDom = Math.max(...d.domains.map(k => k.count), 1);
  const domBars = d.domains.map(k => `
    <div class="bar-row">
      <span class="bar-label">${escHtml(k.key)}</span>
      <div class="bar-track"><div class="bar-fill" style="width:${(100 * k.count / maxDom).toFixed(1)}%"></div></div>
      <span class="bar-num">${k.count}</span>
    </div>
  `).join("");

  const topSoftware = d.top_software.slice(0, 12).map(s => `
    <div class="sw-card" data-env="${escHtml(s.env_id)}">
      <div class="sw-name">
        <span>${escHtml(s.product || s.env_id)}</span>
        ${s.tier ? `<span class="sw-tier">${escHtml(s.tier)}</span>` : ""}
      </div>
      <div class="sw-stats">
        <span><span class="sw-stat-num">${fmtUsd(s.total_gdp_usd)}</span> GDP</span>
        <span>·</span>
        <span><span class="sw-stat-num">${s.task_count}</span> tasks</span>
      </div>
      <div class="sw-cats">
        ${(s.categories || []).slice(0, 2).map(c => `<span class="badge">${escHtml(c)}</span>`).join("")}
      </div>
    </div>
  `).join("");

  body.innerHTML = `
    <div class="insights-grid">
      <div class="metric-card">
        <span class="metric-label">tasks indexed</span>
        <span class="metric-num">${d.n_tasks.toLocaleString()}</span>
        <span class="metric-detail">across ${d.n_envs} software</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">attributed GDP</span>
        <span class="metric-num">${fmtUsd(d.total_attributed_gdp_usd)}</span>
        <span class="metric-detail">U.S. labor GDP grounded</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">SOC coverage</span>
        <span class="metric-num">${d.soc_rollup.length}/22</span>
        <span class="metric-detail">major occupation groups</span>
      </div>
      <div class="metric-card">
        <span class="metric-label">embedding model</span>
        <span class="metric-num" style="font-size:1rem;">text-embedding-3-large</span>
        <span class="metric-detail">+ gpt-5.4-nano enrichment</span>
      </div>
    </div>

    <h3 style="color:var(--accent-2); margin: 1.4rem 0 0.4rem 0; font-size:0.9rem;">// SOC major groups by attributed GDP</h3>
    <div class="bar-chart">${socBars}</div>

    <h3 style="color:var(--accent-2); margin: 1.4rem 0 0.4rem 0; font-size:0.9rem;">// Selection tiers</h3>
    <div class="bar-chart">${tierBars}</div>

    <h3 style="color:var(--accent-2); margin: 1.4rem 0 0.4rem 0; font-size:0.9rem;">// Top software by GDP</h3>
    <div class="sw-grid" style="margin-top:0.5rem;">${topSoftware}</div>

    <h3 style="color:var(--accent-2); margin: 1.4rem 0 0.4rem 0; font-size:0.9rem;">// Task kinds</h3>
    <div class="bar-chart">${kindBars}</div>

    <h3 style="color:var(--accent-2); margin: 1.4rem 0 0.4rem 0; font-size:0.9rem;">// Top domains</h3>
    <div class="bar-chart">${domBars}</div>
  `;

  $$(".bar-label[data-occ]", body).forEach(el => {
    el.addEventListener("click", () => {
      setTab("occupations");
      loadOccupations().then(() => loadOccupationDetail(el.dataset.occ));
    });
  });
  $$(".sw-card", body).forEach(c => c.addEventListener("click", () => openSoftware(c.dataset.env)));
}

/* -------------------- bootstrap -------------------- */

function initTheme() {
  // Precedence:
  //   1. User has manually toggled before → respect localStorage choice.
  //   2. Otherwise → follow OS `prefers-color-scheme`.
  // If the user toggles, the choice is saved and OS changes are ignored.
  // If the user never toggles, the page follows the OS live (e.g. macOS
  // auto-switch at sunset will flip the page too).
  const mq = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)");
  const saved = localStorage.getItem("cuaw_theme");
  const initial = saved || (mq && mq.matches ? "dark" : "light");
  document.documentElement.setAttribute("data-theme", initial);

  const btn = $("#theme-toggle");
  const setIcon = (s) => { if (btn) btn.textContent = s === "dark" ? "◐" : "◑"; };
  setIcon(initial);

  if (btn) btn.addEventListener("click", () => {
    const cur = document.documentElement.getAttribute("data-theme") || "dark";
    const next = cur === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    localStorage.setItem("cuaw_theme", next);
    setIcon(next);
  });

  if (mq && !saved) {
    const handler = (e) => {
      // Only follow OS while the user hasn't made an explicit choice.
      if (localStorage.getItem("cuaw_theme")) return;
      const next = e.matches ? "dark" : "light";
      document.documentElement.setAttribute("data-theme", next);
      setIcon(next);
    };
    // Modern API; addEventListener is the right shape on current browsers.
    if (mq.addEventListener) mq.addEventListener("change", handler);
    else mq.addListener(handler);
  }
}


async function init() {
  initTheme();
  // tab nav
  $$(".tab-btn").forEach(b => b.addEventListener("click", () => setTab(b.dataset.tab)));

  // Static-mode: lazy-load the in-browser embedding model on first search
  // interaction. While it's loading we serve BM25-only results; when it's
  // ready we re-run the active query so semantic ranking folds in.
  if (window.STATIC_MODE && window.embedLoader) {
    let warmupStarted = false;
    const startWarmup = () => {
      if (warmupStarted) return;
      warmupStarted = true;
      window.embedLoader.warmup().then(() => {
        if (state.query) _runSearch();   // re-rank with semantic
      }).catch(() => {});
    };
    $("#q").addEventListener("focus", startWarmup, { once: true });
    $("#q").addEventListener("input", startWarmup, { once: true });
  }

  // search input
  const qIn = $("#q");
  qIn.addEventListener("input", () => { state.query = qIn.value; triggerSearch(); });
  qIn.addEventListener("keydown", (e) => {
    if (e.key === "Escape") { qIn.value = ""; state.query = ""; _runSearch(); }
  });
  $("#exact-toggle").addEventListener("click", () => {
    state.exact = !state.exact;
    $("#exact-toggle").style.color = state.exact ? "var(--accent-2)" : "";
    _runSearch();
  });
  $("#clear-btn").addEventListener("click", () => {
    qIn.value = ""; state.query = "";
    state.filters = { soc: null, os: null, kind: null, long_horizon: null, split: null };
    state.envFilter = null; state.productFilter = null;
    state.exact = false; $("#exact-toggle").style.color = "";
    renderFilters();
    _runSearch();
  });

  // global keyboard
  document.addEventListener("keydown", (e) => {
    if (e.key === "/" && document.activeElement !== qIn && !$("#task-modal").hidden === false) {
      e.preventDefault(); qIn.focus(); qIn.select();
    } else if (e.key === "Escape") {
      if (!$("#task-modal").hidden) closeModal();
    }
  });

  // modal
  $("#modal-close").addEventListener("click", closeModal);
  $(".modal-overlay").addEventListener("click", closeModal);

  // floaters
  $("#cd-top").addEventListener("click", () => window.scrollTo({ top: 0, behavior: "smooth" }));
  window.addEventListener("scroll", () => {
    $("#cd-top").hidden = window.scrollY < 600;
  });

  // software tab
  $("#sw-q").addEventListener("input", debounce((e) => {
    state.softwareFilter = e.target.value; renderSoftware();
  }, 100));
  $("#sw-sort").addEventListener("change", (e) => {
    state.softwareSort = e.target.value;
    state.softwareItems = []; loadSoftware();
  });

  // initial
  try {
    const meta = await api("/api/meta");
    state.meta = meta.meta; state.facets = meta.facets;
    $("#meta-summary").textContent = `${meta.meta.n_tasks.toLocaleString()} tasks · ${meta.meta.n_envs} software · ${meta.meta.embedding_model}`;
    renderFilters();
    await loadFavorites();
  } catch (e) {
    $("#favorites-grid").innerHTML = `<div style="color:var(--red); padding:1rem;">failed to load index: ${escHtml(String(e))}. Did you run the indexing pipeline?</div>`;
  }

  const hash = (location.hash || "#tasks").slice(1);
  setTab(["tasks","software","occupations","insights"].includes(hash) ? hash : "tasks");
}

document.addEventListener("DOMContentLoaded", init);
