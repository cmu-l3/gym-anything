"""Stage 5: Assemble the searchable index from enriched tasks + embeddings.

Also injects the paper-canonical long-horizon flag (and train/test split
membership) by reading `benchmarks/cua_world/splits/<env>_split.json`. The
`is_long_horizon` shown to users is the paper's curated 201-task list, NOT the
LLM-estimated flag (we keep that as `is_long_horizon_llm`).

Output: data/index.json — a single self-contained file the server loads.

Schema:
    {
        "meta": {
            "n_tasks": int,
            "n_envs": int,
            "embedding_model": str,
            "embedding_dim": int,
            "popularity_max_log_gdp": float,
        },
        "facets": {
            "soc_major_groups": [...],
            "os_types": [...],
            "difficulties": [...],
            "tiers": [...],
            "task_kinds": [...],
            "domains": [...],   # top 50 by frequency
        },
        "envs": {
            "<env_id>": {
                "env_id", "product", "in_selected", "tier",
                "total_gdp_usd", "categories", "soc_major_groups",
                "trainability", "pricing", "os_platforms", "os_type",
                "tags", "description", "task_count",
                "top_occupations": [...]
            }, ...
        },
        "tasks": [
            {
                "id": int,                # row index — matches embedding row
                "env_id", "task_id",
                "product", "in_selected", "tier", "os_type", "difficulty",
                "task_name",
                "intent", "summary", "task_kind", "complexity",
                "is_long_horizon",
                "occupations", "soc_major_groups", "domains", "themes",
                "informal_phrases", "skills", "synonyms",
                "popularity": float,
                "raw_description": str  # truncated, for highlighting
            }, ...
        ]
    }

We do NOT inline embeddings into JSON — they stay as a separate .npy.
"""

from __future__ import annotations

import json
import logging
import math
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Dict, List, Optional

import numpy as np

from .jsonio import read_jsonl
from .paths import EMBEDDING_IDS, EMBEDDINGS_NPY, INDEX_JSON, TASKS_ENRICHED

logger = logging.getLogger(__name__)


def _short(s: Any, n: int = 1200) -> str:
    s = str(s or "").strip()
    return s if len(s) <= n else s[:n] + "…"


def _load_split_membership() -> Dict[str, Dict[str, Any]]:
    """For each (env_id, task_id), return {'long_horizon': bool, 'split': 'train'|'test'|None}.

    Reads benchmarks/cua_world/splits/<env>_split.json which the paper uses as
    the canonical source of train/test/long_horizon membership. The env_id is
    derived from each split file's `env_folder` basename, with a couple of
    fallbacks for legacy naming.
    """
    from .paths import REPO_ROOT

    splits_root = REPO_ROOT / "benchmarks" / "cua_world" / "splits"
    out: Dict[str, Dict[str, Any]] = {}
    if not splits_root.is_dir():
        logger.warning("splits dir missing at %s; long-horizon flag will be unset.", splits_root)
        return out

    for split_file in splits_root.glob("*_split.json"):
        try:
            data = json.loads(split_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            logger.warning("invalid split file: %s", split_file)
            continue

        # Candidate env-ids — handles all the naming variants in the corpus.
        bn = Path(data.get("env_folder", "")).name
        stem = split_file.stem.replace("_split", "")
        stem_env = stem if stem.endswith(("_env", "_envb")) else f"{stem}_env"
        candidates = {x for x in (bn, stem, stem_env) if x}

        train = set(data.get("train_tasks") or [])
        test = set(data.get("test_tasks") or [])
        long_set = set((data.get("additional_splits") or {}).get("long_horizon") or [])

        for tid in train | test | long_set:
            for env_id in candidates:
                key = f"{env_id}|{tid}"
                cur = out.setdefault(key, {"split": None, "long_horizon": False})
                if tid in long_set:
                    cur["long_horizon"] = True
                if tid in train:
                    cur["split"] = "train"
                elif tid in test:
                    cur["split"] = "test"
    return out


def _popularity(gdp_usd: Optional[float], max_log_gdp: float) -> float:
    if not gdp_usd or gdp_usd <= 0 or max_log_gdp <= 0:
        return 0.0
    return min(1.0, math.log10(gdp_usd) / max_log_gdp)


def run(
    *,
    enriched_path: Optional[Path] = None,
    embeddings_path: Optional[Path] = None,
    embedding_ids_path: Optional[Path] = None,
    output_path: Optional[Path] = None,
) -> Dict[str, Any]:
    if enriched_path is None:
        enriched_path = TASKS_ENRICHED
    if embeddings_path is None:
        embeddings_path = EMBEDDINGS_NPY
    if embedding_ids_path is None:
        embedding_ids_path = EMBEDDING_IDS
    if output_path is None:
        output_path = INDEX_JSON
    if not enriched_path.is_file():
        raise RuntimeError(f"missing enriched: {enriched_path}")
    if not embeddings_path.is_file():
        raise RuntimeError(f"missing embeddings: {embeddings_path}")
    if not embedding_ids_path.is_file():
        raise RuntimeError(f"missing embedding ids: {embedding_ids_path}")

    records: List[Dict[str, Any]] = list(read_jsonl(enriched_path))
    embedding_ids: List[Dict[str, str]] = json.loads(
        embedding_ids_path.read_text(encoding="utf-8")
    )
    if len(records) != len(embedding_ids):
        raise RuntimeError(
            f"record/embedding count mismatch: {len(records)} vs {len(embedding_ids)}"
        )
    matrix = np.load(embeddings_path)
    if matrix.shape[0] != len(records):
        raise RuntimeError(
            f"embedding matrix rows {matrix.shape[0]} != enriched rows {len(records)}"
        )

    # Sanity: embedding ids must align with record order.
    for i, (rec, eid) in enumerate(zip(records, embedding_ids)):
        if rec["env_id"] != eid["env_id"] or rec["task_id"] != eid["task_id"]:
            raise RuntimeError(
                f"row {i} id mismatch: enriched={rec['env_id']}/{rec['task_id']} embed={eid['env_id']}/{eid['task_id']}"
            )

    # Load the paper's canonical train/test/long_horizon split membership.
    split_membership = _load_split_membership()
    n_long = sum(1 for v in split_membership.values() if v["long_horizon"])
    logger.info("Loaded split membership for %d (env|task) keys; %d marked long_horizon.",
                len(split_membership), n_long)

    # First pass: per-env aggregation + popularity normalization base.
    envs_meta: Dict[str, Dict[str, Any]] = {}
    log_gdps: List[float] = []
    for rec in records:
        gdp = rec.get("gdp") or {}
        gdp_usd = gdp.get("total_gdp_usd")
        if gdp_usd and gdp_usd > 0:
            log_gdps.append(math.log10(gdp_usd))
    max_log_gdp = max(log_gdps) if log_gdps else 1.0

    for rec in records:
        env_id = rec["env_id"]
        env_spec = rec.get("env_spec") or {}
        gdp = rec.get("gdp") or {}
        if env_id in envs_meta:
            envs_meta[env_id]["task_count"] += 1
            continue
        envs_meta[env_id] = {
            "env_id": env_id,
            "product": gdp.get("product"),
            "in_selected": bool(gdp.get("in_selected")),
            "tier": gdp.get("tier"),
            "total_gdp_usd": gdp.get("total_gdp_usd"),
            "categories": gdp.get("categories", []),
            "soc_major_groups": gdp.get("soc_major_groups", []),
            "trainability": gdp.get("trainability"),
            "pricing": gdp.get("pricing"),
            "os_platforms": gdp.get("os_platforms", []),
            "top_occupations": gdp.get("top_occupations", [])[:10],
            "os_type": env_spec.get("os_type"),
            "tags": env_spec.get("tags") or [],
            "description": _short(env_spec.get("description"), 600),
            "task_count": 1,
            "popularity": _popularity(gdp.get("total_gdp_usd"), max_log_gdp),
        }

    # Second pass: per-task records.
    tasks: List[Dict[str, Any]] = []
    soc_counter: Counter = Counter()
    domain_counter: Counter = Counter()
    kind_counter: Counter = Counter()
    diff_counter: Counter = Counter()
    os_counter: Counter = Counter()
    tier_counter: Counter = Counter()

    for i, rec in enumerate(records):
        env_id = rec["env_id"]
        task_id = rec["task_id"]
        env_spec = rec.get("env_spec") or {}
        task_spec = rec.get("task_spec") or {}
        gdp = rec.get("gdp") or {}
        e = rec.get("enriched") or {}

        task_name = task_spec.get("name") or task_id.replace("_", " ").title()
        product = gdp.get("product") or env_id
        os_type = env_spec.get("os_type") or "linux"
        difficulty = task_spec.get("difficulty")
        tier = gdp.get("tier")

        popularity = _popularity(gdp.get("total_gdp_usd"), max_log_gdp)

        membership = split_membership.get(f"{env_id}|{task_id}", {"split": None, "long_horizon": False})

        item: Dict[str, Any] = {
            "id": i,
            "env_id": env_id,
            "task_id": task_id,
            "product": product,
            "in_selected": bool(gdp.get("in_selected")),
            "tier": tier,
            "os_type": os_type,
            "difficulty": difficulty,
            "task_name": task_name,
            "intent": e.get("intent", ""),
            "summary": e.get("summary", ""),
            "task_kind": e.get("task_kind", "other"),
            "complexity": e.get("complexity", 3),
            # Paper-canonical long-horizon flag (from splits/<env>_split.json).
            "is_long_horizon": bool(membership["long_horizon"]),
            # LLM's estimated long-horizon flag, kept for transparency.
            "is_long_horizon_llm": bool(e.get("is_long_horizon")),
            "split": membership["split"],
            "occupations": e.get("occupations", []),
            "soc_major_groups": e.get("soc_major_groups", []),
            "domains": e.get("domains", []),
            "themes": e.get("themes", []),
            "informal_phrases": e.get("informal_phrases", []),
            "skills": e.get("skills", []),
            "synonyms": e.get("synonyms", []),
            "popularity": popularity,
            "raw_description": _short(task_spec.get("description"), 1200),
        }
        tasks.append(item)

        for soc in item["soc_major_groups"]:
            soc_counter[soc] += 1
        for d in item["domains"]:
            domain_counter[d] += 1
        kind_counter[item["task_kind"]] += 1
        if difficulty:
            diff_counter[difficulty] += 1
        os_counter[os_type] += 1
        if tier:
            tier_counter[tier] += 1

    n_long = sum(1 for t in tasks if t["is_long_horizon"])
    n_train = sum(1 for t in tasks if t["split"] == "train")
    n_test = sum(1 for t in tasks if t["split"] == "test")
    facets = {
        "soc_major_groups": [
            {"key": k, "count": v} for k, v in soc_counter.most_common()
        ],
        "os_types": [{"key": k, "count": v} for k, v in os_counter.most_common()],
        "difficulties": [{"key": k, "count": v} for k, v in diff_counter.most_common()],
        "tiers": [{"key": k, "count": v} for k, v in tier_counter.most_common()],
        "task_kinds": [{"key": k, "count": v} for k, v in kind_counter.most_common()],
        "domains": [{"key": k, "count": v} for k, v in domain_counter.most_common(60)],
        "splits": [
            {"key": "train", "count": n_train},
            {"key": "test", "count": n_test},
            {"key": "long_horizon", "count": n_long},
        ],
    }

    payload = {
        "meta": {
            "n_tasks": len(tasks),
            "n_envs": len(envs_meta),
            "embedding_model": "text-embedding-3-large",
            "embedding_dim": int(matrix.shape[1]),
            "popularity_max_log_gdp": max_log_gdp,
        },
        "facets": facets,
        "envs": envs_meta,
        "tasks": tasks,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(payload), encoding="utf-8")
    logger.info(
        "Index: %d tasks across %d envs → %s (%.1f MB)",
        len(tasks), len(envs_meta), output_path,
        output_path.stat().st_size / 1024 / 1024,
    )
    return {"n_tasks": len(tasks), "n_envs": len(envs_meta)}


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(json.dumps(run(), indent=2))
