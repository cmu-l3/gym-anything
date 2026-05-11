"""Hybrid search engine: BM25-by-field + dense cosine + popularity prior.

Loaded once on server startup. Single-process, all-in-memory.

  score(task, q) =
       w_sem    * cosine(emb(q), emb(task))
     + w_name   * BM25(q, software_name)
     + w_intent * BM25(q, task_name + intent)
     + w_occ    * BM25(q, occupations + soc_major_groups)
     + w_dom    * BM25(q, domains + themes + informal_phrases)
     + w_desc   * BM25(q, raw_description)
     + w_skill  * BM25(q, skills + task_kind + synonyms)
     + w_pop    * popularity (log-normalized GDP)
     × exact-match boost (multiplicative, when query in any field as substring)

Exact mode (query wrapped in "..."): drops any task that doesn't contain the
unwrapped substring in any field.

Diversification: per-software cap (default 3 per env) on the final ranked list,
selected greedily so high-quality matches still surface even when one env
dominates the raw scores.
"""

from __future__ import annotations

import json
import logging
import math
import re
import threading
from collections import Counter
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

logger = logging.getLogger(__name__)


# Re-export so tests can monkeypatch via search.embed
from ..pipeline.llm_client import embed as _llm_embed  # noqa: E402
from ..pipeline.paths import EMBEDDING_IDS, EMBEDDINGS_NPY, INDEX_JSON  # noqa: E402


WEIGHTS: Dict[str, float] = {
    # Semantic dominates — cosine on text-embedding-3-large is the most
    # discriminating signal we have. BM25 fields catch hard lexical matches
    # the embedding might miss but should not OVERRIDE good semantic matches.
    "sem": 0.55,
    "name": 0.07,
    "intent": 0.06,
    "occ": 0.05,
    "dom": 0.05,
    "desc": 0.04,
    "skill": 0.03,
    "pop": 0.03,
    "coverage": 0.18,    # IDF-weighted fraction of query tokens present in the doc
    "exact_boost": 1.4,  # multiplicative when query is a substring of any field
}

# BM25 parameters. Scores are NOT per-field-max normalized — that destroys
# magnitude. Instead each field is scaled by BM25_FIELD_CAP (typical strong
# match for one query token).
BM25_K1 = 1.4
BM25_B = 0.75
BM25_FIELD_CAP = 6.0


_TOKEN_RE = re.compile(r"[A-Za-z0-9]+")


def tokenize(text: str) -> List[str]:
    return [t.lower() for t in _TOKEN_RE.findall(text or "")]


def _join(*parts: Any) -> str:
    flat: List[str] = []
    for p in parts:
        if p is None:
            continue
        if isinstance(p, list):
            flat.extend(str(x) for x in p)
        else:
            flat.append(str(p))
    return " ".join(flat)


class _Field:
    """Per-field BM25 index using inverted postings.

    `postings[token]` is a tuple (doc_indices: int32 ndarray, tfs: int32 ndarray).
    Scoring iterates only the docs containing each query token.
    """

    __slots__ = ("name", "doc_lens", "avg_len", "df", "n_docs", "postings")

    def __init__(self, name: str, docs: List[List[str]]):
        self.name = name
        self.n_docs = len(docs)
        self.doc_lens = np.asarray([len(d) for d in docs], dtype=np.float32)
        self.avg_len = float(self.doc_lens.mean()) if self.n_docs else 0.0

        # Build per-token postings.
        per_token_idx: Dict[str, List[int]] = {}
        per_token_tf: Dict[str, List[int]] = {}
        for i, doc in enumerate(docs):
            if not doc:
                continue
            tf_local: Dict[str, int] = {}
            for tok in doc:
                tf_local[tok] = tf_local.get(tok, 0) + 1
            for tok, tf in tf_local.items():
                per_token_idx.setdefault(tok, []).append(i)
                per_token_tf.setdefault(tok, []).append(tf)
        self.postings: Dict[str, Tuple[np.ndarray, np.ndarray]] = {
            tok: (
                np.asarray(per_token_idx[tok], dtype=np.int32),
                np.asarray(per_token_tf[tok], dtype=np.int32),
            )
            for tok in per_token_idx
        }
        self.df: Dict[str, int] = {tok: len(idx) for tok, (idx, _) in self.postings.items()}

    def score(self, query_tokens: List[str], k1: float = BM25_K1, b: float = BM25_B) -> np.ndarray:
        if not query_tokens or self.n_docs == 0 or self.avg_len == 0:
            return np.zeros(self.n_docs, dtype=np.float32)
        scores = np.zeros(self.n_docs, dtype=np.float32)
        seen_tokens = set()
        for tok in query_tokens:
            if tok in seen_tokens:
                continue
            seen_tokens.add(tok)
            posting = self.postings.get(tok)
            if posting is None:
                continue
            doc_idx, tfs = posting
            df = doc_idx.shape[0]
            idf = math.log((self.n_docs - df + 0.5) / (df + 0.5) + 1.0)
            tfs_f = tfs.astype(np.float32)
            denom = tfs_f + k1 * (1 - b + b * (self.doc_lens[doc_idx] / self.avg_len))
            contrib = idf * (tfs_f * (k1 + 1)) / denom
            scores[doc_idx] += contrib
        return scores


class SearchIndex:
    """Loaded index, ready for queries."""

    def __init__(self, index_path: Path = INDEX_JSON,
                 embeddings_path: Path = EMBEDDINGS_NPY,
                 embedding_ids_path: Path = EMBEDDING_IDS):
        if not index_path.is_file():
            raise RuntimeError(f"missing index: {index_path}")
        if not embeddings_path.is_file():
            raise RuntimeError(f"missing embeddings: {embeddings_path}")
        self.index_path = index_path
        self.embeddings_path = embeddings_path
        self.payload: Dict[str, Any] = json.loads(index_path.read_text(encoding="utf-8"))
        self.tasks: List[Dict[str, Any]] = self.payload["tasks"]
        self.envs: Dict[str, Dict[str, Any]] = self.payload["envs"]
        self.facets: Dict[str, Any] = self.payload["facets"]
        self.meta: Dict[str, Any] = self.payload["meta"]

        # Embedding matrix (already L2-normalized in build_index.py).
        mat = np.load(embeddings_path)
        if mat.shape[0] != len(self.tasks):
            raise RuntimeError(
                f"embedding rows {mat.shape[0]} != tasks {len(self.tasks)}"
            )
        self.embeddings = mat.astype(np.float32)

        self._build_fields()
        # Lookup helpers
        self._by_pair: Dict[Tuple[str, str], int] = {
            (t["env_id"], t["task_id"]): i for i, t in enumerate(self.tasks)
        }
        # Cache of recent query embeddings.
        self._query_embed_lock = threading.Lock()
        self._query_embed_cache: Dict[str, np.ndarray] = {}

    def _build_fields(self) -> None:
        n = len(self.tasks)
        f_name: List[List[str]] = [[]] * n
        f_intent: List[List[str]] = [[]] * n
        f_occ: List[List[str]] = [[]] * n
        f_dom: List[List[str]] = [[]] * n
        f_desc: List[List[str]] = [[]] * n
        f_skill: List[List[str]] = [[]] * n
        f_full: List[str] = [""] * n  # for exact-substring mode

        # Allocating fresh lists since the [[]] * n trick aliases.
        f_name = [[] for _ in range(n)]
        f_intent = [[] for _ in range(n)]
        f_occ = [[] for _ in range(n)]
        f_dom = [[] for _ in range(n)]
        f_desc = [[] for _ in range(n)]
        f_skill = [[] for _ in range(n)]

        for i, t in enumerate(self.tasks):
            env_meta = self.envs.get(t["env_id"], {})
            f_name[i] = tokenize(_join(
                t["product"], t["env_id"], env_meta.get("description"),
                env_meta.get("categories"), env_meta.get("tags"),
            ))
            f_intent[i] = tokenize(_join(t["task_name"], t["intent"], t["summary"]))
            f_occ[i] = tokenize(_join(t["occupations"], t["soc_major_groups"]))
            f_dom[i] = tokenize(_join(t["domains"], t["themes"], t["informal_phrases"]))
            f_desc[i] = tokenize(t["raw_description"])
            f_skill[i] = tokenize(_join(t["skills"], t["task_kind"], t["synonyms"]))
            f_full[i] = " ".join([
                t["product"] or "", t["task_name"] or "", t["intent"] or "",
                t["summary"] or "", " ".join(t.get("themes", [])),
                " ".join(t.get("informal_phrases", [])),
                t["raw_description"] or "",
                " ".join(t.get("occupations", [])),
                " ".join(t.get("soc_major_groups", [])),
                " ".join(t.get("domains", [])),
                t["env_id"] or "", t["task_id"] or "",
            ]).lower()

        self._field_name = _Field("name", f_name)
        self._field_intent = _Field("intent", f_intent)
        self._field_occ = _Field("occ", f_occ)
        self._field_dom = _Field("dom", f_dom)
        self._field_desc = _Field("desc", f_desc)
        self._field_skill = _Field("skill", f_skill)
        self._exact_corpus = f_full
        self._popularity = np.asarray([t["popularity"] for t in self.tasks], dtype=np.float32)

    def _query_embedding(self, query: str) -> np.ndarray:
        with self._query_embed_lock:
            cached = self._query_embed_cache.get(query)
            if cached is not None:
                return cached
        vecs = _llm_embed(model=self.meta.get("embedding_model", "text-embedding-3-large"), inputs=[query])
        v = np.asarray(vecs[0], dtype=np.float32)
        n = float(np.linalg.norm(v))
        if n > 0:
            v = v / n
        with self._query_embed_lock:
            self._query_embed_cache[query] = v
            # Bound the cache.
            if len(self._query_embed_cache) > 4096:
                # Drop oldest 1k entries
                for k in list(self._query_embed_cache)[:1024]:
                    self._query_embed_cache.pop(k, None)
        return v

    @staticmethod
    def _scale_bm25(scores: np.ndarray) -> np.ndarray:
        """Clamp BM25 scores to [0, 1] using a fixed cap so weak matches stay weak."""
        if not len(scores):
            return scores
        return np.minimum(scores / BM25_FIELD_CAP, 1.0)

    def _coverage(self, query_tokens: List[str]) -> np.ndarray:
        """For each doc, IDF-weighted fraction of unique query tokens present.

        Equally weighting tokens means rare ones (e.g. "chip") count the same
        as common ones (e.g. "design"). That lets a doc with many hits on the
        common token score as well as a doc that actually contains the rare
        one. We weight by IDF so rare tokens dominate.

        IDF is computed using the union of postings across all fields — a
        token is "in the doc" if any field contains it.
        """
        n = len(self.tasks)
        unique_q = list({t for t in query_tokens})
        if not unique_q:
            return np.zeros(n, dtype=np.float32)
        fields = (self._field_name, self._field_intent, self._field_occ,
                  self._field_dom, self._field_desc, self._field_skill)
        present = np.zeros((n, len(unique_q)), dtype=np.bool_)
        idf = np.zeros(len(unique_q), dtype=np.float32)
        for j, tok in enumerate(unique_q):
            doc_set: set = set()
            for fld in fields:
                posting = fld.postings.get(tok)
                if posting is None:
                    continue
                doc_idx, _ = posting
                doc_set.update(int(x) for x in doc_idx)
                present[doc_idx, j] = True
            df = len(doc_set)
            # Add-half smoothing so OOV tokens still get a non-zero IDF.
            idf[j] = math.log((n - df + 0.5) / (df + 0.5) + 1.0)
        # Weighted coverage: sum(idf * present) / sum(idf), per doc.
        total_idf = float(idf.sum())
        if total_idf <= 0:
            return np.zeros(n, dtype=np.float32)
        weighted = (present.astype(np.float32) * idf).sum(axis=1) / total_idf
        return weighted.astype(np.float32)

    def search(
        self,
        query: str,
        *,
        topk: int = 30,
        exact: bool = False,
        diversify: bool = True,
        per_env_cap: int = 3,
        weights: Optional[Dict[str, float]] = None,
        filter_soc: Optional[str] = None,
        filter_os: Optional[str] = None,
        filter_difficulty: Optional[str] = None,
        filter_kind: Optional[str] = None,
        filter_long_horizon: Optional[bool] = None,
        filter_env: Optional[str] = None,
        filter_product: Optional[str] = None,
        filter_split: Optional[str] = None,
    ) -> Dict[str, Any]:
        query = (query or "").strip()
        weights = {**WEIGHTS, **(weights or {})}

        # Detect quoted exact-match.
        if not exact and len(query) >= 2 and query.startswith('"') and query.endswith('"'):
            query = query[1:-1].strip()
            exact = True

        n = len(self.tasks)
        if n == 0:
            return {"results": [], "total": 0, "query": query}

        # Filter mask.
        mask = np.ones(n, dtype=bool)
        if filter_soc:
            mask &= np.array([filter_soc in t["soc_major_groups"] for t in self.tasks])
        if filter_os:
            mask &= np.array([t["os_type"] == filter_os for t in self.tasks])
        if filter_difficulty:
            mask &= np.array([(t.get("difficulty") or "") == filter_difficulty for t in self.tasks])
        if filter_kind:
            mask &= np.array([t["task_kind"] == filter_kind for t in self.tasks])
        if filter_long_horizon is not None:
            mask &= np.array([bool(t["is_long_horizon"]) == filter_long_horizon for t in self.tasks])
        if filter_env:
            mask &= np.array([t["env_id"] == filter_env for t in self.tasks])
        if filter_product:
            mask &= np.array([(t.get("product") or "") == filter_product for t in self.tasks])
        if filter_split:
            if filter_split == "long_horizon":
                mask &= np.array([bool(t.get("is_long_horizon")) for t in self.tasks])
            else:
                mask &= np.array([(t.get("split") or "") == filter_split for t in self.tasks])

        # Exact-substring filter.
        if exact and query:
            ql = query.lower()
            mask &= np.array([ql in c for c in self._exact_corpus])

        if not mask.any():
            return {"results": [], "total": 0, "query": query, "exact": exact}

        if not query:
            # Empty query: rank by popularity (with filters applied).
            scored = self._popularity.copy()
            scored[~mask] = -1.0
            order = np.argsort(-scored)
            order = [int(i) for i in order if scored[i] >= 0]
            return self._materialize(order, topk, query, exact, diversify, per_env_cap)

        q_tokens = tokenize(query)

        # BM25 per field — fixed-cap scaling, NOT per-field max-normalize.
        s_name = self._scale_bm25(self._field_name.score(q_tokens))
        s_intent = self._scale_bm25(self._field_intent.score(q_tokens))
        s_occ = self._scale_bm25(self._field_occ.score(q_tokens))
        s_dom = self._scale_bm25(self._field_dom.score(q_tokens))
        s_desc = self._scale_bm25(self._field_desc.score(q_tokens))
        s_skill = self._scale_bm25(self._field_skill.score(q_tokens))

        # Semantic — raw cosine (already L2-normalized embeddings, dot = cosine
        # in [-1, 1]). Negatives are uninformative for retrieval; clamp at 0 so
        # they don't pull the total down.
        try:
            qv = self._query_embedding(query)
        except Exception as exc:
            logger.warning("query embedding failed (%s); semantic disabled", exc)
            qv = None

        if qv is not None:
            s_sem = (self.embeddings @ qv).astype(np.float32)
            s_sem = np.clip(s_sem, 0.0, 1.0)
        else:
            s_sem = np.zeros(n, dtype=np.float32)

        # Token-coverage: fraction of unique query tokens present in the doc.
        s_cov = self._coverage(q_tokens)

        # Final score.
        score = (
            weights["sem"] * s_sem
            + weights["name"] * s_name
            + weights["intent"] * s_intent
            + weights["occ"] * s_occ
            + weights["dom"] * s_dom
            + weights["desc"] * s_desc
            + weights["skill"] * s_skill
            + weights["coverage"] * s_cov
            + weights["pop"] * self._popularity
        )

        # Exact-match multiplicative boost on docs that contain the unquoted query as a substring.
        ql = query.lower()
        if ql:
            contains = np.array([ql in c for c in self._exact_corpus])
            score = np.where(contains, score * weights["exact_boost"], score)

        score[~mask] = -1.0
        order = np.argsort(-score)
        order = [int(i) for i in order if score[i] >= 0][:max(topk * 4, 100)]
        return self._materialize(order, topk, query, exact, diversify, per_env_cap, scores=score)

    def _materialize(
        self,
        order: List[int],
        topk: int,
        query: str,
        exact: bool,
        diversify: bool,
        per_env_cap: int,
        *,
        scores: Optional[np.ndarray] = None,
    ) -> Dict[str, Any]:
        results: List[Dict[str, Any]] = []
        per_env: Counter = Counter()
        ql = query.lower() if query else ""
        for idx in order:
            t = self.tasks[idx]
            if diversify:
                if per_env[t["env_id"]] >= per_env_cap:
                    continue
            per_env[t["env_id"]] += 1
            score_val = float(scores[idx]) if scores is not None else None
            results.append({
                "id": idx,
                "env_id": t["env_id"],
                "task_id": t["task_id"],
                "product": t["product"],
                "task_name": t["task_name"],
                "intent": t["intent"],
                "summary": t["summary"],
                "task_kind": t["task_kind"],
                "complexity": t["complexity"],
                "is_long_horizon": t["is_long_horizon"],
                "difficulty": t.get("difficulty"),
                "os_type": t["os_type"],
                "tier": t["tier"],
                "soc_major_groups": t["soc_major_groups"],
                "domains": t["domains"],
                "occupations": t["occupations"],
                "themes": t["themes"],
                "informal_phrases": t["informal_phrases"],
                "popularity": t["popularity"],
                "score": score_val,
                "highlights": _highlights(t, ql) if ql else [],
            })
            if len(results) >= topk:
                break
        return {
            "results": results,
            "total": len(results),
            "query": query,
            "exact": exact,
        }

    # ---- non-search lookups powering the other tabs ----

    def get_task(self, env_id: str, task_id: str) -> Optional[Dict[str, Any]]:
        i = self._by_pair.get((env_id, task_id))
        if i is None:
            return None
        return self.tasks[i]

    def list_software(self, *, sort: str = "gdp") -> List[Dict[str, Any]]:
        """Group envs that map to the same product into one card.

        e.g. microsoft_excel_env + microsoft_excel_2010_env both → "Microsoft
        Excel". GDP isn't summed (it's an attribute of the product, not the
        env). Task counts are summed across env variants.
        """
        groups: Dict[str, Dict[str, Any]] = {}
        for env in self.envs.values():
            key = env.get("product") or env["env_id"]
            existing = groups.get(key)
            if existing is None:
                groups[key] = {
                    "key": key,
                    "product": env.get("product"),
                    "primary_env_id": env["env_id"],
                    "env_ids": [env["env_id"]],
                    "tier": env.get("tier"),
                    "in_selected": env.get("in_selected"),
                    "total_gdp_usd": env.get("total_gdp_usd"),
                    "categories": list(env.get("categories", [])),
                    "soc_major_groups": list(env.get("soc_major_groups", [])),
                    "os_type": env.get("os_type"),
                    "trainability": env.get("trainability"),
                    "pricing": env.get("pricing"),
                    "os_platforms": list(env.get("os_platforms", [])),
                    "description": env.get("description"),
                    "task_count": env.get("task_count", 0),
                    "popularity": env.get("popularity", 0.0),
                    "top_occupations": list(env.get("top_occupations", [])),
                }
            else:
                existing["env_ids"].append(env["env_id"])
                existing["task_count"] += env.get("task_count", 0)
                # Prefer the rich (selected, with GDP) variant when one is.
                if not existing.get("in_selected") and env.get("in_selected"):
                    existing["in_selected"] = True
                    existing["tier"] = env.get("tier") or existing["tier"]
                    existing["total_gdp_usd"] = env.get("total_gdp_usd") or existing["total_gdp_usd"]
                    existing["primary_env_id"] = env["env_id"]
                    existing["categories"] = list(env.get("categories", [])) or existing["categories"]
                    existing["soc_major_groups"] = list(env.get("soc_major_groups", [])) or existing["soc_major_groups"]
                    existing["top_occupations"] = list(env.get("top_occupations", [])) or existing["top_occupations"]
                if not existing["description"] and env.get("description"):
                    existing["description"] = env["description"]

        items = list(groups.values())
        if sort == "gdp":
            items.sort(key=lambda x: -(x.get("total_gdp_usd") or 0))
        elif sort == "name":
            items.sort(key=lambda x: (x.get("product") or x["primary_env_id"]).lower())
        elif sort == "tasks":
            items.sort(key=lambda x: -x.get("task_count", 0))
        return items

    def get_software(self, env_id: str) -> Optional[Dict[str, Any]]:
        env = self.envs.get(env_id)
        if env is None:
            return None
        tasks = [t for t in self.tasks if t["env_id"] == env_id]
        return {"env": env, "tasks": tasks}

    def list_occupations(self) -> Dict[str, Any]:
        """Aggregate by SOC major group + occupation strings observed."""
        by_soc: Dict[str, Dict[str, Any]] = {}
        occ_counter: Counter = Counter()
        for t in self.tasks:
            for soc in t["soc_major_groups"]:
                by_soc.setdefault(soc, {"key": soc, "task_count": 0, "envs": set()})
                by_soc[soc]["task_count"] += 1
                by_soc[soc]["envs"].add(t["env_id"])
            for occ in t["occupations"]:
                occ_counter[occ] += 1
        groups = []
        for soc, v in by_soc.items():
            groups.append({
                "key": soc,
                "task_count": v["task_count"],
                "env_count": len(v["envs"]),
            })
        groups.sort(key=lambda g: -g["task_count"])
        return {
            "soc_groups": groups,
            "top_occupations": [
                {"name": k, "count": v} for k, v in occ_counter.most_common(120)
            ],
        }

    def get_occupation(self, key: str) -> Dict[str, Any]:
        """Drill-down: matches against soc major group, then occupation strings."""
        is_soc = any(soc["key"] == key for soc in self.facets["soc_major_groups"])
        envs: Counter = Counter()
        matched_tasks: List[int] = []
        for i, t in enumerate(self.tasks):
            hit = (
                key in t["soc_major_groups"]
                if is_soc
                else key in t["occupations"]
            )
            if hit:
                matched_tasks.append(i)
                envs[t["env_id"]] += 1

        # Sort tasks by popularity prior + complexity.
        matched_tasks.sort(
            key=lambda i: (-self.tasks[i]["popularity"], -self.tasks[i]["complexity"])
        )
        envs_summary: List[Dict[str, Any]] = []
        for env_id, ct in envs.most_common(40):
            env = self.envs.get(env_id, {})
            envs_summary.append({
                "env_id": env_id,
                "product": env.get("product"),
                "task_count": ct,
                "total_gdp_usd": env.get("total_gdp_usd"),
                "tier": env.get("tier"),
            })

        return {
            "key": key,
            "is_soc_group": is_soc,
            "envs": envs_summary,
            "tasks": [self.tasks[i] for i in matched_tasks[:120]],
        }

    def insights(self) -> Dict[str, Any]:
        """GDP rollups for the Insights tab."""
        # Top software by GDP.
        envs = sorted(
            self.envs.values(),
            key=lambda x: -(x.get("total_gdp_usd") or 0),
        )
        top_software = [
            {
                "env_id": e["env_id"],
                "product": e["product"],
                "tier": e["tier"],
                "total_gdp_usd": e["total_gdp_usd"],
                "task_count": e["task_count"],
                "categories": e["categories"][:3],
                "in_selected": e["in_selected"],
            }
            for e in envs[:50]
        ]

        # Tier distribution.
        tier_dist = Counter()
        gdp_per_tier: Dict[str, float] = {}
        for e in self.envs.values():
            t = e.get("tier")
            if not t:
                continue
            tier_dist[t] += 1
            gdp_per_tier[t] = gdp_per_tier.get(t, 0.0) + (e.get("total_gdp_usd") or 0.0)

        # Per-SOC totals (using env-level soc_major_groups).
        per_soc: Dict[str, Dict[str, Any]] = {}
        for e in self.envs.values():
            for soc in e.get("soc_major_groups", []):
                d = per_soc.setdefault(soc, {"key": soc, "env_count": 0, "task_count": 0, "total_gdp_usd": 0.0})
                d["env_count"] += 1
                d["task_count"] += e.get("task_count", 0)
                d["total_gdp_usd"] += (e.get("total_gdp_usd") or 0.0)
        soc_rollup = sorted(per_soc.values(), key=lambda x: -x["total_gdp_usd"])

        # Total tracked GDP.
        total_gdp = sum((e.get("total_gdp_usd") or 0.0) for e in self.envs.values())

        return {
            "n_tasks": self.meta.get("n_tasks"),
            "n_envs": self.meta.get("n_envs"),
            "total_attributed_gdp_usd": total_gdp,
            "tiers": [
                {"tier": k, "env_count": v, "total_gdp_usd": gdp_per_tier.get(k, 0.0)}
                for k, v in tier_dist.most_common()
            ],
            "soc_rollup": soc_rollup,
            "top_software": top_software,
            "task_kinds": self.facets["task_kinds"],
            "domains": self.facets["domains"][:30],
        }


def _highlights(task: Dict[str, Any], ql: str) -> List[str]:
    """Find which fields contained the query substring (for UI badges)."""
    if not ql:
        return []
    out: List[str] = []
    for field in ("intent", "summary", "task_name", "product"):
        if ql in (task.get(field) or "").lower():
            out.append(field)
    for field in ("themes", "informal_phrases", "occupations", "soc_major_groups", "domains"):
        items = task.get(field) or []
        if any(ql in str(x).lower() for x in items):
            out.append(field)
    return out


@lru_cache(maxsize=1)
def get_index() -> SearchIndex:
    """Module-level singleton."""
    return SearchIndex()
