/* Static-mode search engine: JS port of server/search.py.

   Loads:
     index.json                  — payload from build_index.py
     embeddings_bge.f16.bin      — flat little-endian float16, shape (N, dim)
     embedding_ids_bge.json      — row order

   Provides one global: window.staticIndex (a StaticIndex instance), with:
     search(query, opts)         → matches /api/search shape
     getTask(envId, taskId)      → matches /api/task
     listSoftware(sort)          → matches /api/software
     getSoftware(envId)          → matches /api/software/<env>
     listOccupations()           → matches /api/occupations
     getOccupation(key)          → matches /api/occupations/<key>
     insights()                  → matches /api/insights
     meta, facets                — direct attrs

   Cosine semantic ranking is added asynchronously when the bge model is ready
   (loaded lazily by embed_loader.js on first search interaction).
*/

(() => {
  const TOKEN_RE = /[A-Za-z0-9]+/g;

  function tokenize(text) {
    if (!text) return [];
    const out = [];
    const matches = String(text).toLowerCase().matchAll(TOKEN_RE);
    for (const m of matches) out.push(m[0]);
    return out;
  }

  function joinFields(...parts) {
    const out = [];
    for (const p of parts) {
      if (p == null) continue;
      if (Array.isArray(p)) for (const x of p) out.push(String(x));
      else out.push(String(p));
    }
    return out.join(" ");
  }

  // -------------------- BM25 field --------------------

  class BM25Field {
    constructor(name, docs) {
      this.name = name;
      this.nDocs = docs.length;
      this.docLens = new Float32Array(this.nDocs);
      let totalLen = 0;
      for (let i = 0; i < this.nDocs; i++) {
        this.docLens[i] = docs[i].length;
        totalLen += docs[i].length;
      }
      this.avgLen = this.nDocs > 0 ? totalLen / this.nDocs : 0;

      // Build inverted postings: token -> { docIdx: Int32Array, tfs: Int32Array }.
      const perTokenIdx = new Map();
      const perTokenTf = new Map();
      for (let i = 0; i < this.nDocs; i++) {
        const doc = docs[i];
        if (!doc.length) continue;
        const tfLocal = new Map();
        for (const tok of doc) tfLocal.set(tok, (tfLocal.get(tok) || 0) + 1);
        for (const [tok, tf] of tfLocal) {
          let arr = perTokenIdx.get(tok);
          if (!arr) {
            arr = [];
            perTokenIdx.set(tok, arr);
            perTokenTf.set(tok, []);
          }
          arr.push(i);
          perTokenTf.get(tok).push(tf);
        }
      }
      this.postings = new Map();
      for (const [tok, idxArr] of perTokenIdx) {
        this.postings.set(tok, {
          docIdx: new Int32Array(idxArr),
          tfs: new Int32Array(perTokenTf.get(tok)),
        });
      }
    }

    score(queryTokens, k1 = 1.4, b = 0.75) {
      const scores = new Float32Array(this.nDocs);
      if (!queryTokens.length || !this.nDocs || !this.avgLen) return scores;
      const seen = new Set();
      for (const tok of queryTokens) {
        if (seen.has(tok)) continue;
        seen.add(tok);
        const posting = this.postings.get(tok);
        if (!posting) continue;
        const df = posting.docIdx.length;
        const idf = Math.log((this.nDocs - df + 0.5) / (df + 0.5) + 1.0);
        for (let j = 0; j < posting.docIdx.length; j++) {
          const docI = posting.docIdx[j];
          const tf = posting.tfs[j];
          const denom = tf + k1 * (1 - b + b * (this.docLens[docI] / this.avgLen));
          scores[docI] += (idf * (tf * (k1 + 1))) / denom;
        }
      }
      return scores;
    }
  }

  // -------------------- Float16 decode --------------------

  // IEEE 754 half-precision -> float32. Browsers don't natively expose
  // Float16Array yet (Stage 3 proposal), so we decode on load.
  function decodeHalfToFloat32(uint16) {
    const out = new Float32Array(uint16.length);
    for (let i = 0; i < uint16.length; i++) {
      const h = uint16[i];
      const sign = (h & 0x8000) >> 15;
      const exponent = (h & 0x7C00) >> 10;
      const fraction = h & 0x03FF;
      let val;
      if (exponent === 0) {
        val = (fraction === 0) ? 0 : Math.pow(2, -14) * (fraction / 1024);
      } else if (exponent === 31) {
        val = fraction === 0 ? Infinity : NaN;
      } else {
        val = Math.pow(2, exponent - 15) * (1 + fraction / 1024);
      }
      out[i] = sign ? -val : val;
    }
    return out;
  }

  // -------------------- Static Index --------------------

  const WEIGHTS = {
    sem: 0.55, name: 0.07, intent: 0.06, occ: 0.05, dom: 0.05,
    desc: 0.04, skill: 0.03, pop: 0.03, coverage: 0.18, exact_boost: 1.4,
  };
  const BM25_FIELD_CAP = 6.0;

  class StaticIndex {
    constructor(payload, embeddings, embeddingIds) {
      this.payload = payload;
      this.tasks = payload.tasks;
      this.envs = payload.envs;
      this.facets = payload.facets;
      this.meta = payload.meta;
      this.embeddings = embeddings;            // Float32Array, length n*dim
      this.embeddingIds = embeddingIds;
      this.dim = payload.meta.embedding_dim;

      // Sanity: row order alignment.
      if (this.tasks.length !== embeddingIds.length) {
        throw new Error(`tasks (${this.tasks.length}) != embedding ids (${embeddingIds.length})`);
      }
      for (let i = 0; i < this.tasks.length; i++) {
        if (this.tasks[i].env_id !== embeddingIds[i].env_id ||
            this.tasks[i].task_id !== embeddingIds[i].task_id) {
          throw new Error(`row ${i} id mismatch between index.json and embedding_ids`);
        }
      }
      if (embeddings.length !== this.tasks.length * this.dim) {
        throw new Error(`embeddings size ${embeddings.length} != ${this.tasks.length}*${this.dim}`);
      }

      this._popularity = new Float32Array(this.tasks.length);
      for (let i = 0; i < this.tasks.length; i++) this._popularity[i] = this.tasks[i].popularity || 0;

      this._byPair = new Map();
      this.tasks.forEach((t, i) => this._byPair.set(`${t.env_id}|${t.task_id}`, i));

      this._buildFields();
      this._queryEmbedCache = new Map();   // q -> Float32Array

      this.embedFn = null;        // set by embed_loader once model is ready
      this.embedReadyP = null;    // promise resolved when model loaded
    }

    _buildFields() {
      const n = this.tasks.length;
      const fName = new Array(n);
      const fIntent = new Array(n);
      const fOcc = new Array(n);
      const fDom = new Array(n);
      const fDesc = new Array(n);
      const fSkill = new Array(n);
      this._exactCorpus = new Array(n);

      for (let i = 0; i < n; i++) {
        const t = this.tasks[i];
        const env = this.envs[t.env_id] || {};
        fName[i] = tokenize(joinFields(t.product, t.env_id, env.description, env.categories, env.tags));
        fIntent[i] = tokenize(joinFields(t.task_name, t.intent, t.summary));
        fOcc[i] = tokenize(joinFields(t.occupations, t.soc_major_groups));
        fDom[i] = tokenize(joinFields(t.domains, t.themes, t.informal_phrases));
        fDesc[i] = tokenize(t.raw_description || "");
        fSkill[i] = tokenize(joinFields(t.skills, t.task_kind, t.synonyms));
        this._exactCorpus[i] = [
          t.product, t.task_name, t.intent, t.summary,
          (t.themes || []).join(" "),
          (t.informal_phrases || []).join(" "),
          t.raw_description,
          (t.occupations || []).join(" "),
          (t.soc_major_groups || []).join(" "),
          (t.domains || []).join(" "),
          t.env_id, t.task_id,
        ].map(x => (x || "")).join(" ").toLowerCase();
      }

      this._fieldName = new BM25Field("name", fName);
      this._fieldIntent = new BM25Field("intent", fIntent);
      this._fieldOcc = new BM25Field("occ", fOcc);
      this._fieldDom = new BM25Field("dom", fDom);
      this._fieldDesc = new BM25Field("desc", fDesc);
      this._fieldSkill = new BM25Field("skill", fSkill);
    }

    setEmbedFn(fn) { this.embedFn = fn; }
    setEmbedReadyP(p) { this.embedReadyP = p; }

    async _queryEmbedding(query) {
      if (this._queryEmbedCache.has(query)) return this._queryEmbedCache.get(query);
      if (!this.embedFn) return null;
      const v = await this.embedFn(query);
      const arr = (v instanceof Float32Array) ? v : new Float32Array(v);
      // Normalize defensively (matches corpus normalization).
      let norm = 0;
      for (let i = 0; i < arr.length; i++) norm += arr[i] * arr[i];
      norm = Math.sqrt(norm) || 1.0;
      for (let i = 0; i < arr.length; i++) arr[i] /= norm;
      this._queryEmbedCache.set(query, arr);
      // Bound cache.
      if (this._queryEmbedCache.size > 1024) {
        const firstKey = this._queryEmbedCache.keys().next().value;
        this._queryEmbedCache.delete(firstKey);
      }
      return arr;
    }

    _scaleBM25(scores) {
      const out = new Float32Array(scores.length);
      const cap = BM25_FIELD_CAP;
      for (let i = 0; i < scores.length; i++) {
        const v = scores[i] / cap;
        out[i] = v > 1 ? 1 : v;
      }
      return out;
    }

    _coverage(queryTokens) {
      const n = this.tasks.length;
      const out = new Float32Array(n);
      const unique = Array.from(new Set(queryTokens));
      if (!unique.length) return out;
      const fields = [this._fieldName, this._fieldIntent, this._fieldOcc,
                      this._fieldDom, this._fieldDesc, this._fieldSkill];
      const present = new Uint8Array(n * unique.length);
      const idf = new Float32Array(unique.length);
      for (let j = 0; j < unique.length; j++) {
        const tok = unique[j];
        const docSet = new Set();
        for (const fld of fields) {
          const posting = fld.postings.get(tok);
          if (!posting) continue;
          for (let k = 0; k < posting.docIdx.length; k++) {
            const di = posting.docIdx[k];
            docSet.add(di);
            present[di * unique.length + j] = 1;
          }
        }
        const df = docSet.size;
        idf[j] = Math.log((n - df + 0.5) / (df + 0.5) + 1.0);
      }
      let totalIdf = 0;
      for (let j = 0; j < unique.length; j++) totalIdf += idf[j];
      if (totalIdf <= 0) return out;
      for (let i = 0; i < n; i++) {
        let s = 0;
        for (let j = 0; j < unique.length; j++) {
          if (present[i * unique.length + j]) s += idf[j];
        }
        out[i] = s / totalIdf;
      }
      return out;
    }

    _cosineAll(qv) {
      const n = this.tasks.length, dim = this.dim;
      const out = new Float32Array(n);
      const E = this.embeddings;
      for (let i = 0; i < n; i++) {
        let s = 0;
        const off = i * dim;
        for (let d = 0; d < dim; d++) s += E[off + d] * qv[d];
        out[i] = s > 0 ? (s < 1 ? s : 1) : 0;
      }
      return out;
    }

    async search(query, opts = {}) {
      query = (query || "").trim();
      const w = Object.assign({}, WEIGHTS, opts.weights || {});
      let exact = !!opts.exact;
      const topk = Math.max(1, Math.min(opts.topk || 30, 200));
      const diversify = opts.diversify !== false;
      const perEnvCap = opts.per_env_cap || 3;

      if (!exact && query.length >= 2 && query.startsWith('"') && query.endsWith('"')) {
        query = query.slice(1, -1).trim();
        exact = true;
      }

      const n = this.tasks.length;
      if (n === 0) return { results: [], total: 0, query, exact };

      let mask = new Uint8Array(n);
      mask.fill(1);
      const apply = (predicate) => {
        for (let i = 0; i < n; i++) if (mask[i] && !predicate(this.tasks[i])) mask[i] = 0;
      };
      if (opts.filter_soc) apply(t => (t.soc_major_groups || []).includes(opts.filter_soc));
      if (opts.filter_os) apply(t => t.os_type === opts.filter_os);
      if (opts.filter_difficulty) apply(t => (t.difficulty || "") === opts.filter_difficulty);
      if (opts.filter_kind) apply(t => t.task_kind === opts.filter_kind);
      if (opts.filter_long_horizon != null) apply(t => !!t.is_long_horizon === !!opts.filter_long_horizon);
      if (opts.filter_env) apply(t => t.env_id === opts.filter_env);
      if (opts.filter_product) apply(t => (t.product || "") === opts.filter_product);
      if (opts.filter_split) {
        if (opts.filter_split === "long_horizon") apply(t => !!t.is_long_horizon);
        else apply(t => (t.split || "") === opts.filter_split);
      }

      if (exact && query) {
        const ql = query.toLowerCase();
        for (let i = 0; i < n; i++) if (mask[i] && !this._exactCorpus[i].includes(ql)) mask[i] = 0;
      }

      let anyMask = false;
      for (let i = 0; i < n; i++) if (mask[i]) { anyMask = true; break; }
      if (!anyMask) return { results: [], total: 0, query, exact };

      // Empty-query: rank by popularity within mask.
      if (!query) {
        const order = [];
        for (let i = 0; i < n; i++) if (mask[i]) order.push(i);
        order.sort((a, b) => this._popularity[b] - this._popularity[a]);
        return this._materialize(order.slice(0, Math.max(topk * 4, 100)),
                                 topk, query, exact, diversify, perEnvCap, null);
      }

      const qTokens = tokenize(query);
      const sName = this._scaleBM25(this._fieldName.score(qTokens));
      const sIntent = this._scaleBM25(this._fieldIntent.score(qTokens));
      const sOcc = this._scaleBM25(this._fieldOcc.score(qTokens));
      const sDom = this._scaleBM25(this._fieldDom.score(qTokens));
      const sDesc = this._scaleBM25(this._fieldDesc.score(qTokens));
      const sSkill = this._scaleBM25(this._fieldSkill.score(qTokens));
      const sCov = this._coverage(qTokens);

      // Semantic — only when the model is loaded.
      let sSem = null;
      if (this.embedFn) {
        try {
          const qv = await this._queryEmbedding(query);
          if (qv) sSem = this._cosineAll(qv);
        } catch (e) {
          console.warn("query embedding failed:", e);
        }
      }

      const score = new Float32Array(n);
      for (let i = 0; i < n; i++) {
        if (!mask[i]) { score[i] = -1; continue; }
        let s = w.name * sName[i]
              + w.intent * sIntent[i]
              + w.occ * sOcc[i]
              + w.dom * sDom[i]
              + w.desc * sDesc[i]
              + w.skill * sSkill[i]
              + w.coverage * sCov[i]
              + w.pop * this._popularity[i];
        if (sSem) s += w.sem * sSem[i];
        score[i] = s;
      }

      const ql = query.toLowerCase();
      if (ql) {
        for (let i = 0; i < n; i++) {
          if (score[i] >= 0 && this._exactCorpus[i].includes(ql)) score[i] *= w.exact_boost;
        }
      }

      const order = [];
      for (let i = 0; i < n; i++) if (score[i] >= 0) order.push(i);
      order.sort((a, b) => score[b] - score[a]);
      const trimmed = order.slice(0, Math.max(topk * 4, 100));
      return this._materialize(trimmed, topk, query, exact, diversify, perEnvCap, score);
    }

    _materialize(order, topk, query, exact, diversify, perEnvCap, scores) {
      const results = [];
      const perEnv = new Map();
      const ql = (query || "").toLowerCase();
      for (const idx of order) {
        const t = this.tasks[idx];
        if (diversify) {
          const c = perEnv.get(t.env_id) || 0;
          if (c >= perEnvCap) continue;
          perEnv.set(t.env_id, c + 1);
        }
        const scoreVal = scores ? scores[idx] : null;
        results.push({
          id: idx,
          env_id: t.env_id, task_id: t.task_id,
          product: t.product, task_name: t.task_name,
          intent: t.intent, summary: t.summary,
          task_kind: t.task_kind, complexity: t.complexity,
          is_long_horizon: t.is_long_horizon, difficulty: t.difficulty || null,
          os_type: t.os_type, tier: t.tier,
          soc_major_groups: t.soc_major_groups, domains: t.domains,
          occupations: t.occupations, themes: t.themes,
          informal_phrases: t.informal_phrases, popularity: t.popularity,
          score: scoreVal, highlights: ql ? this._highlights(t, ql) : [],
        });
        if (results.length >= topk) break;
      }
      return { results, total: results.length, query, exact };
    }

    _highlights(task, ql) {
      const out = [];
      const stringFields = ["intent", "summary", "task_name", "product"];
      for (const f of stringFields) {
        if ((task[f] || "").toLowerCase().includes(ql)) out.push(f);
      }
      const arrFields = ["themes", "informal_phrases", "occupations", "soc_major_groups", "domains"];
      for (const f of arrFields) {
        const items = task[f] || [];
        if (items.some(x => String(x).toLowerCase().includes(ql))) out.push(f);
      }
      return out;
    }

    // ---- Lookups powering the other tabs ----

    getTask(envId, taskId) {
      const i = this._byPair.get(`${envId}|${taskId}`);
      return i == null ? null : this.tasks[i];
    }

    listSoftware(sort = "gdp") {
      const groups = new Map();
      for (const env of Object.values(this.envs)) {
        const key = env.product || env.env_id;
        const ex = groups.get(key);
        if (!ex) {
          groups.set(key, {
            key, product: env.product || null, primary_env_id: env.env_id,
            env_ids: [env.env_id], tier: env.tier, in_selected: !!env.in_selected,
            total_gdp_usd: env.total_gdp_usd, categories: [...(env.categories || [])],
            soc_major_groups: [...(env.soc_major_groups || [])], os_type: env.os_type,
            trainability: env.trainability, pricing: env.pricing,
            os_platforms: [...(env.os_platforms || [])], description: env.description,
            task_count: env.task_count || 0, popularity: env.popularity || 0,
            top_occupations: [...(env.top_occupations || [])],
          });
        } else {
          ex.env_ids.push(env.env_id);
          ex.task_count += env.task_count || 0;
          if (!ex.in_selected && env.in_selected) {
            ex.in_selected = true;
            ex.tier = env.tier || ex.tier;
            ex.total_gdp_usd = env.total_gdp_usd || ex.total_gdp_usd;
            ex.primary_env_id = env.env_id;
            if ((env.categories || []).length) ex.categories = [...env.categories];
            if ((env.soc_major_groups || []).length) ex.soc_major_groups = [...env.soc_major_groups];
            if ((env.top_occupations || []).length) ex.top_occupations = [...env.top_occupations];
          }
          if (!ex.description && env.description) ex.description = env.description;
        }
      }
      const items = Array.from(groups.values());
      if (sort === "gdp") items.sort((a, b) => (b.total_gdp_usd || 0) - (a.total_gdp_usd || 0));
      else if (sort === "name") items.sort((a, b) => (a.product || a.primary_env_id || "").toLowerCase().localeCompare((b.product || b.primary_env_id || "").toLowerCase()));
      else if (sort === "tasks") items.sort((a, b) => b.task_count - a.task_count);
      return items;
    }

    getSoftware(envId) {
      const env = this.envs[envId];
      if (!env) return null;
      const tasks = this.tasks.filter(t => t.env_id === envId);
      return { env, tasks };
    }

    listOccupations() {
      const bySoc = new Map();
      const occCounter = new Map();
      for (const t of this.tasks) {
        for (const soc of (t.soc_major_groups || [])) {
          let v = bySoc.get(soc);
          if (!v) { v = { task_count: 0, envs: new Set() }; bySoc.set(soc, v); }
          v.task_count += 1;
          v.envs.add(t.env_id);
        }
        for (const occ of (t.occupations || [])) occCounter.set(occ, (occCounter.get(occ) || 0) + 1);
      }
      const groups = Array.from(bySoc.entries()).map(([key, v]) => ({
        key, task_count: v.task_count, env_count: v.envs.size,
      })).sort((a, b) => b.task_count - a.task_count);
      const top = Array.from(occCounter.entries()).map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count).slice(0, 120);
      return { soc_groups: groups, top_occupations: top };
    }

    getOccupation(key) {
      const isSoc = (this.facets.soc_major_groups || []).some(s => s.key === key);
      const matched = [];
      const envs = new Map();
      for (let i = 0; i < this.tasks.length; i++) {
        const t = this.tasks[i];
        const hit = isSoc ? (t.soc_major_groups || []).includes(key)
                          : (t.occupations || []).includes(key);
        if (hit) {
          matched.push(i);
          envs.set(t.env_id, (envs.get(t.env_id) || 0) + 1);
        }
      }
      matched.sort((a, b) => {
        const da = this.tasks[a], db = this.tasks[b];
        return (db.popularity || 0) - (da.popularity || 0)
            || (db.complexity || 0) - (da.complexity || 0);
      });
      const envSummary = Array.from(envs.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 40)
        .map(([env_id, ct]) => {
          const e = this.envs[env_id] || {};
          return {
            env_id, product: e.product || null,
            task_count: ct, total_gdp_usd: e.total_gdp_usd || null,
            tier: e.tier || null,
          };
        });
      return {
        key, is_soc_group: isSoc,
        envs: envSummary,
        tasks: matched.slice(0, 120).map(i => this.tasks[i]),
      };
    }

    insights() {
      const envs = Object.values(this.envs).slice().sort(
        (a, b) => (b.total_gdp_usd || 0) - (a.total_gdp_usd || 0));
      const topSoftware = envs.slice(0, 50).map(e => ({
        env_id: e.env_id, product: e.product || null, tier: e.tier || null,
        total_gdp_usd: e.total_gdp_usd || null,
        task_count: e.task_count || 0,
        categories: (e.categories || []).slice(0, 3),
        in_selected: !!e.in_selected,
      }));
      const tierDist = new Map();
      const gdpPerTier = new Map();
      for (const e of envs) {
        const t = e.tier; if (!t) continue;
        tierDist.set(t, (tierDist.get(t) || 0) + 1);
        gdpPerTier.set(t, (gdpPerTier.get(t) || 0) + (e.total_gdp_usd || 0));
      }
      const perSoc = new Map();
      for (const e of envs) {
        for (const s of (e.soc_major_groups || [])) {
          let v = perSoc.get(s);
          if (!v) { v = { key: s, env_count: 0, task_count: 0, total_gdp_usd: 0 }; perSoc.set(s, v); }
          v.env_count += 1;
          v.task_count += (e.task_count || 0);
          v.total_gdp_usd += (e.total_gdp_usd || 0);
        }
      }
      const socRollup = Array.from(perSoc.values()).sort((a, b) => b.total_gdp_usd - a.total_gdp_usd);
      const totalGdp = envs.reduce((s, e) => s + (e.total_gdp_usd || 0), 0);
      return {
        n_tasks: this.meta.n_tasks, n_envs: this.meta.n_envs,
        total_attributed_gdp_usd: totalGdp,
        tiers: Array.from(tierDist.entries())
          .sort((a, b) => b[1] - a[1])
          .map(([tier, env_count]) => ({ tier, env_count, total_gdp_usd: gdpPerTier.get(tier) || 0 })),
        soc_rollup: socRollup,
        top_software: topSoftware,
        task_kinds: this.facets.task_kinds, domains: (this.facets.domains || []).slice(0, 30),
      };
    }
  }

  // -------------------- bootstrap --------------------

  async function loadStaticIndex(dataRoot = "data") {
    const [payload, embeddingIds, embeddingsBuf] = await Promise.all([
      fetch(`${dataRoot}/index.json`).then(r => r.json()),
      fetch(`${dataRoot}/embedding_ids_bge.json`).then(r => r.json()),
      fetch(`${dataRoot}/embeddings_bge.f16.bin`).then(r => r.arrayBuffer()),
    ]);
    // Override the embedding_dim in the meta to match the bge matrix.
    const dim = embeddingsBuf.byteLength / 2 / payload.tasks.length;
    if (!Number.isInteger(dim) || dim <= 0) {
      throw new Error(`bad bge embedding shape: bytes=${embeddingsBuf.byteLength}, tasks=${payload.tasks.length}`);
    }
    payload.meta.embedding_dim = dim;
    payload.meta.embedding_model = "BAAI/bge-small-en-v1.5";
    const halfArr = new Uint16Array(embeddingsBuf);
    const embeddings = decodeHalfToFloat32(halfArr);
    return new StaticIndex(payload, embeddings, embeddingIds);
  }

  window.loadStaticIndex = loadStaticIndex;
})();
