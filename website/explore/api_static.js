/* Static-mode API adapter.

   Mirrors the URL→shape contract of server/app.py so web/app.js works
   unmodified when window.STATIC_MODE is true.

   This script must run after static_index.js (which exposes loadStaticIndex)
   and before web/app.js (which calls window.api).
*/

(() => {
  let indexP = null;
  let indexInstance = null;

  async function ensureIndex() {
    if (indexInstance) return indexInstance;
    if (!indexP) indexP = window.loadStaticIndex("data");
    indexInstance = await indexP;
    // Hand the embedding function to the index. This sets up an ASYNC
    // connection: search() will call indexInstance._queryEmbedding which
    // will await embedLoader.embed only if the model is loaded.
    if (window.embedLoader) {
      indexInstance.setEmbedFn(async (q) => {
        if (window.embedLoader.status !== "ready") return null;
        return window.embedLoader.embed(q);
      });
    }
    return indexInstance;
  }

  function _coerceBool(v) {
    if (v == null || v === "" || v === "any") return null;
    return v === "1" || v === 1 || v === "true" || v === true;
  }

  async function staticApi(path, params = {}) {
    const idx = await ensureIndex();
    if (path === "/api/meta") return { meta: idx.meta, facets: idx.facets };
    if (path === "/api/facets") return idx.facets;

    if (path === "/api/search") {
      const opts = {
        topk: parseInt(params.topk || "30", 10) || 30,
        exact: _coerceBool(params.exact) === true,
        diversify: _coerceBool(params.diversify) !== false,
        per_env_cap: parseInt(params.per_env_cap || "3", 10) || 3,
        filter_soc: params.soc || null,
        filter_os: params.os || null,
        filter_difficulty: params.difficulty || null,
        filter_kind: params.kind || null,
        filter_env: params.env || null,
        filter_product: params.product || null,
        filter_split: params.split || null,
        filter_long_horizon: _coerceBool(params.long_horizon),
      };
      return idx.search(params.q || "", opts);
    }

    const taskMatch = path.match(/^\/api\/task\/([^/]+)\/([^/]+)$/);
    if (taskMatch) {
      const envId = decodeURIComponent(taskMatch[1]);
      const taskId = decodeURIComponent(taskMatch[2]);
      const task = idx.getTask(envId, taskId);
      if (!task) return { error: "not_found" };
      return { task, env: idx.envs[envId] || {} };
    }

    if (path === "/api/favorites") {
      // Resolve favorites just like the server does.
      let payload;
      try {
        payload = await fetch("data/favorites.json").then(r => r.json());
      } catch (e) {
        return { items: [], blurb: "" };
      }
      const itemsIn = payload.items || [];
      const resolved = [];
      for (const entry of itemsIn) {
        const task = (entry.env_id && entry.task_id) ? idx.getTask(entry.env_id, entry.task_id) : null;
        if (!task) {
          resolved.push({ env_id: entry.env_id, task_id: entry.task_id, blurb: entry.blurb, missing: true });
          continue;
        }
        resolved.push({
          env_id: entry.env_id, task_id: entry.task_id, blurb: entry.blurb,
          task_name: task.task_name, product: task.product,
          intent: task.intent, summary: task.summary,
          soc_major_groups: task.soc_major_groups, is_long_horizon: task.is_long_horizon,
          complexity: task.complexity, task_kind: task.task_kind, missing: false,
        });
      }
      return { blurb: payload.blurb || "", items: resolved };
    }

    if (path === "/api/software") {
      const sort = params.sort || "gdp";
      const items = idx.listSoftware(sort);
      return { items, count: items.length };
    }

    const swMatch = path.match(/^\/api\/software\/([^/]+)$/);
    if (swMatch) {
      const envId = decodeURIComponent(swMatch[1]);
      const detail = idx.getSoftware(envId);
      return detail || { error: "not_found" };
    }

    if (path === "/api/occupations") return idx.listOccupations();

    const occMatch = path.match(/^\/api\/occupations\/(.+)$/);
    if (occMatch) {
      const key = decodeURIComponent(occMatch[1]);
      return idx.getOccupation(key);
    }

    if (path === "/api/insights") return idx.insights();

    return { error: "unknown_endpoint", path };
  }

  window.staticApi = staticApi;
})();
