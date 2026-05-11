"""Stage 4: Compute embeddings for every enriched task.

Embedding model: text-embedding-3-large (3072-dim).

Each task is embedded as a single canonical doc string composed of the
software name + intent + summary + occupations + soc + domains + themes +
informal_phrases + skills + raw description. We store the matrix as float16
to halve disk; 13k × 3072 × 2 bytes ≈ 80 MB, fine to keep in memory.

Caching is content-addressable on the doc-string sha so re-runs are free.

Output:
    data/embeddings.f16.npy  (N, 3072)
    data/embedding_ids.json  list of task ids in row order
"""

from __future__ import annotations

import json
import logging
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np

from .jsonio import append_jsonl, load_cache, read_jsonl, sha256_of
from .llm_client import embed
from .paths import EMBED_CACHE, EMBEDDING_IDS, EMBEDDINGS_NPY, TASKS_ENRICHED

logger = logging.getLogger(__name__)


EMBED_MODEL = "text-embedding-3-large"
EMBED_DIM = 3072
EMBED_BATCH = 64
EMBED_CONCURRENCY = 8


def _doc_string(rec: Dict[str, object]) -> str:
    env_id = rec.get("env_id") or ""
    task_id = rec.get("task_id") or ""
    enriched = rec.get("enriched") or {}
    gdp = rec.get("gdp") or {}
    env_spec = rec.get("env_spec") or {}
    task_spec = rec.get("task_spec") or {}

    software = gdp.get("product") or env_id
    description = (task_spec.get("description") or "").strip()
    env_desc = (env_spec.get("description") or "").strip()
    parts: List[str] = []

    parts.append(f"software: {software}")
    if env_desc:
        parts.append(f"software_summary: {env_desc[:300]}")
    if enriched.get("intent"):
        parts.append(f"intent: {enriched['intent']}")
    if enriched.get("summary"):
        parts.append(f"summary: {enriched['summary']}")
    if enriched.get("occupations"):
        parts.append("occupations: " + ", ".join(enriched["occupations"]))
    if enriched.get("soc_major_groups"):
        parts.append("soc: " + ", ".join(enriched["soc_major_groups"]))
    if enriched.get("domains"):
        parts.append("domains: " + ", ".join(enriched["domains"]))
    if enriched.get("themes"):
        parts.append("themes: " + ", ".join(enriched["themes"]))
    if enriched.get("informal_phrases"):
        parts.append("informal: " + " | ".join(enriched["informal_phrases"]))
    if enriched.get("skills"):
        parts.append("skills: " + ", ".join(enriched["skills"]))
    parts.append(f"task: {task_id}")
    if description:
        parts.append("description: " + description[:1500])
    return "\n".join(parts)


def _embed_key(doc: str) -> str:
    return sha256_of({"model": EMBED_MODEL, "doc": doc})


def _iter_chunks(items: List[Tuple[str, str]], n: int):
    for i in range(0, len(items), n):
        yield items[i:i + n]


def run(
    *,
    input_path: Optional[Path] = None,
    cache_path: Optional[Path] = None,
    matrix_path: Optional[Path] = None,
    ids_path: Optional[Path] = None,
    batch_size: int = EMBED_BATCH,
    concurrency: int = EMBED_CONCURRENCY,
    limit: Optional[int] = None,
) -> Dict[str, object]:
    if input_path is None:
        input_path = TASKS_ENRICHED
    if cache_path is None:
        cache_path = EMBED_CACHE
    if matrix_path is None:
        matrix_path = EMBEDDINGS_NPY
    if ids_path is None:
        ids_path = EMBEDDING_IDS
    if not input_path.is_file():
        raise RuntimeError(f"missing input: {input_path}. Run enrichment first.")

    records: List[Dict[str, object]] = list(read_jsonl(input_path))
    if limit is not None:
        records = records[:limit]

    docs: List[str] = [_doc_string(r) for r in records]
    keys: List[str] = [_embed_key(d) for d in docs]

    cache = load_cache(cache_path, key="key")
    logger.info("Embed cache: %d entries.", len(cache))

    todo: List[Tuple[str, str]] = [
        (k, d) for k, d in zip(keys, docs) if k not in cache
    ]
    logger.info(
        "Embedding plan: %d total, %d cached, %d to embed (model=%s, batch=%d, concurrency=%d).",
        len(records), len(records) - len(todo), len(todo), EMBED_MODEL, batch_size, concurrency,
    )

    cache_lock = threading.Lock()
    n_done = 0
    n_total = len(todo)

    def _worker(chunk: List[Tuple[str, str]]) -> List[Tuple[str, List[float]]]:
        ks = [k for k, _ in chunk]
        ds = [d for _, d in chunk]
        vecs = embed(model=EMBED_MODEL, inputs=ds)
        if len(vecs) != len(ks):
            raise RuntimeError(
                f"embedding count mismatch: got {len(vecs)} expected {len(ks)}"
            )
        return list(zip(ks, vecs))

    if todo:
        chunks = list(_iter_chunks(todo, batch_size))
        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {pool.submit(_worker, c): c for c in chunks}
            for fut in as_completed(futures):
                chunk = futures[fut]
                try:
                    pairs = fut.result()
                except Exception as exc:
                    raise RuntimeError(f"embedding batch failed: {exc}") from exc
                with cache_lock:
                    for k, vec in pairs:
                        if len(vec) != EMBED_DIM:
                            raise RuntimeError(
                                f"unexpected embedding dim: got {len(vec)}, expected {EMBED_DIM}"
                            )
                        cache[k] = {"key": k, "vec": vec}
                        append_jsonl(cache_path, {"key": k, "vec": vec})
                    n_done += len(pairs)
                    sys.stderr.write(
                        f"\r  embedded {n_done}/{n_total} ({100*n_done/n_total:.1f}%)"
                    )
                    sys.stderr.flush()
        sys.stderr.write("\n")

    # Materialize the matrix in record order.
    matrix = np.zeros((len(records), EMBED_DIM), dtype=np.float16)
    ids: List[Dict[str, str]] = []
    for i, (rec, k) in enumerate(zip(records, keys)):
        item = cache.get(k)
        if item is None:
            raise RuntimeError(
                f"missing embedding for {rec['env_id']}/{rec['task_id']}; cache key {k}"
            )
        matrix[i] = np.asarray(item["vec"], dtype=np.float16)
        ids.append({"env_id": str(rec["env_id"]), "task_id": str(rec["task_id"])})

    # Normalize for cosine via dot product.
    norms = np.linalg.norm(matrix.astype(np.float32), axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    matrix = (matrix.astype(np.float32) / norms).astype(np.float16)

    matrix_path.parent.mkdir(parents=True, exist_ok=True)
    np.save(matrix_path, matrix)
    ids_path.write_text(json.dumps(ids), encoding="utf-8")
    logger.info(
        "Wrote %d × %d embeddings → %s ; ids → %s",
        matrix.shape[0], matrix.shape[1], matrix_path, ids_path,
    )
    return {
        "n_total": len(records),
        "n_called": n_total,
        "matrix_shape": list(matrix.shape),
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(json.dumps(run(), indent=2))
