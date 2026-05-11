# CUA-World Benchmark Visualizer

A terminal-themed, single-page UI for browsing the 13k+ tasks in CUA-World by
software, occupation, theme, intent, or natural-language search.

Lives at `extras/visualization/cua_world/visualizer/`. Reachable via the
`gym-anything-extras` dispatcher:

```bash
gym-anything-extras visualization cua_world visualizer index   # build index
gym-anything-extras visualization cua_world visualizer serve --open
```

## What it does

- **Tasks** (default tab) — single search box returns the most relevant tasks
  for any kind of query: software name, theme, domain, occupation, intent,
  informal phrasing, or quoted exact match. Results are scored as a hybrid of
  per-field BM25, dense cosine on `text-embedding-3-large` embeddings, and a
  log-GDP popularity prior. Diversification caps per-software duplicates.
- **Software** — all 247 envs, sorted by GDP / task count / name, each linking
  to its tasks.
- **Occupations** — all 22 SOC major groups + the most-cited specific
  occupations, with drill-down to the software and tasks each touches.
- **Insights** — GDP rollups: per-SOC totals, selection tier breakdown,
  top-software-by-GDP, task-kind / domain frequencies. All numbers come from
  the `scaling_cua2/run_pipeline.py` artifacts.

## Pipeline

The index is produced by five stages, each cacheable and idempotent:

1. **ingest** — walks `benchmarks/cua_world/environments/*` and emits one
   record per task (`data/raw_tasks.jsonl`). Pre-existing corrupt `task.json`
   files are recorded in `data/skipped.jsonl` and skipped; if more than 5% of
   tasks are unreadable the run hard-fails.
2. **map** — matches each env folder to a row in
   `scaling_cua_env_names/gym_anything_selected_products.csv` (or the broader
   `gdp_weighting/product_totals.csv`) using a hand-curated overrides file
   plus token-prefiltered fuzzy matching. Output: `data/env_to_product.json`.
3. **gdp_join** — attaches each task's GDP block (tier, total GDP, SOC major
   groups, top occupations, etc.) using the env→product mapping. Output:
   `data/tasks_with_gdp.jsonl`.
4. **enrich** — per task, calls `gpt-5.4-nano` with `reasoning_effort=medium`
   and a strict JSON schema to extract `intent`, `summary`, `occupations`,
   `soc_major_groups`, `domains`, `themes`, `informal_phrases`, `skills`,
   `synonyms`, `task_kind`, `complexity`, `is_long_horizon`. Tasks are batched
   5-per-request and run with concurrency=12. The cache (`data/cache/enrich.jsonl`)
   is content-addressable so re-runs are free; on validation drift the batch is
   retried up to 4 times then split to size-1 calls before giving up.
5. **embed** — embeds a normalized doc-string per task with
   `text-embedding-3-large` (3072-dim, stored as float16). Cache:
   `data/cache/embed.jsonl`. Output: `data/embeddings.f16.npy` +
   `data/embedding_ids.json`.
6. **build_index** — assembles `data/index.json`: per-task structured fields,
   per-env metadata, facets (SOC, OS, difficulty, kinds, domains, tiers).
   Embeddings stay separate as the .npy.

## Search scoring

```
score = 0.30 · cos(emb(q), emb(t))                       # semantic
      + 0.15 · BM25(q, software_name)
      + 0.10 · BM25(q, task_name + intent)
      + 0.10 · BM25(q, occupations + soc_major_groups)
      + 0.08 · BM25(q, domains + themes + informal_phrases)
      + 0.07 · BM25(q, raw_description)
      + 0.05 · BM25(q, skills + task_kind + synonyms)
      + 0.05 · popularity (log-normalized GDP)
× 1.5  multiplicative bonus when query is an exact substring of any field
```

Quoted queries (`"..."`) drop to a substring filter and skip non-matching docs
entirely. A per-software cap (default 3) prevents one env from dominating
results when its tasks are all relevant.

## Frontend

`web/index.html` + `web/style.css` + `web/app.js`. No framework. Terminal
theme: monospace JetBrains Mono throughout, traffic-light dot motif on every
card and panel, amber active border on the search box, soft pink for `from
"<env_id>"` lines, yellow stars, dark near-black background.

State lives in localStorage for liked tasks; everything else is server-driven.

## Tests

```bash
python -m pytest extras/visualization/cua_world/visualizer/tests -q
```

Tests synthesize a 2-env mini-corpus + tiny fake GDP CSVs, exercise every
stage end-to-end with monkeypatched LLM/embedding clients, then build a
`SearchIndex` and assert ordering, exact-match filtering, and per-env
diversification cap.

## Curating favorites

`data/favorites.json` is the single source of truth for the "Curated" rail
shown when the search box is empty. Edit it to change the list — each entry
is `{env_id, task_id, blurb}`.

## Configuration

| Env var | Default |
|---|---|
| `OPENAI_API_KEY` | (loaded from repo `.env`) |
| `GA_VIZ_GDP_DIR` | `/Users/pranjal/Developer/scaling_cua2/scaling_cua_env_names` |
| `GA_VIZ_GDP_OCC_CSV` | `/Users/pranjal/Developer/scaling_cua2/us_gdp_by_occupation_USD.csv` |

## Files

```
method.py                       — extras dispatcher entry
pipeline/
  paths.py                      — filesystem locations
  jsonio.py                     — sha-keyed JSONL cache helpers
  llm_client.py                 — OpenAI wrapper (chat + embeddings)
  ingest.py                     — Stage 1
  env_to_product.py             — env→product mapping
  gdp_join.py                   — Stage 2
  enrich.py                     — Stage 3 (gpt-5.4-nano)
  embed.py                      — Stage 4 (text-embedding-3-large)
  build_index.py                — Stage 5
server/
  search.py                     — hybrid search engine + non-search lookups
  app.py                        — Quart server (all API endpoints)
web/
  index.html / style.css / app.js
data/
  raw_tasks.jsonl               — ingest output
  tasks_with_gdp.jsonl          — gdp_join output
  tasks_enriched.jsonl          — enrich output
  embeddings.f16.npy            — embedding matrix (N × 3072)
  embedding_ids.json            — row order
  index.json                    — final searchable index
  favorites.json                — curated list (hand-edited)
  env_to_product.json           — env→product map
  skipped.jsonl                 — ingestion skips
  cache/enrich.jsonl            — enrichment cache
  cache/embed.jsonl             — embedding cache
tests/
  test_visualizer_contract.py
```
