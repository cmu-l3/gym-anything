"""Filesystem locations and config knobs for the visualizer pipeline.

All paths are derived from the repo root so the pipeline runs from any cwd.
GDP data path is overridable via env var since it lives outside the repo.
"""

from __future__ import annotations

import os
from pathlib import Path


def _find_repo_root() -> Path:
    here = Path(__file__).resolve()
    for ancestor in here.parents:
        if (ancestor / "src" / "gym_anything").is_dir() and (ancestor / "extras").is_dir():
            return ancestor
    raise RuntimeError(
        "Could not locate gym-anything repo root from "
        f"{here}. Expected an ancestor with src/gym_anything/ and extras/."
    )


REPO_ROOT = _find_repo_root()
ENV_DIR = REPO_ROOT / "benchmarks" / "cua_world" / "environments"

VISUALIZER_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = VISUALIZER_ROOT / "data"
CACHE_DIR = DATA_DIR / "cache"
WEB_DIR = VISUALIZER_ROOT / "web"

DATA_DIR.mkdir(parents=True, exist_ok=True)
CACHE_DIR.mkdir(parents=True, exist_ok=True)

RAW_TASKS = DATA_DIR / "raw_tasks.jsonl"
TASKS_WITH_GDP = DATA_DIR / "tasks_with_gdp.jsonl"
TASKS_ENRICHED = DATA_DIR / "tasks_enriched.jsonl"
ENRICH_CACHE = CACHE_DIR / "enrich.jsonl"
EMBED_CACHE = CACHE_DIR / "embed.jsonl"
EMBEDDINGS_NPY = DATA_DIR / "embeddings.f16.npy"
EMBEDDING_IDS = DATA_DIR / "embedding_ids.json"
INDEX_JSON = DATA_DIR / "index.json"
ENV_PRODUCT_MAP = DATA_DIR / "env_to_product.json"
FAVORITES = DATA_DIR / "favorites.json"


def gdp_dir() -> Path:
    override = os.environ.get("GA_VIZ_GDP_DIR")
    if override:
        return Path(override).resolve()
    return Path("/Users/pranjal/Developer/scaling_cua2/scaling_cua_env_names").resolve()


def gdp_occupation_csv() -> Path:
    override = os.environ.get("GA_VIZ_GDP_OCC_CSV")
    if override:
        return Path(override).resolve()
    return Path("/Users/pranjal/Developer/scaling_cua2/us_gdp_by_occupation_USD.csv").resolve()
