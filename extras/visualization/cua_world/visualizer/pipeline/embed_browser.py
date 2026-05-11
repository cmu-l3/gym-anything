"""Re-embed enriched tasks with bge-small-en-v1.5 for in-browser semantic search.

Uses sentence-transformers locally (free, CPU-only) so the static site can do
semantic search without an OpenAI key. The same model identifier
(BAAI/bge-small-en-v1.5) is loaded in the browser via transformers.js using
the Xenova ONNX mirror.

Outputs:
    data/embeddings_bge.f16.bin     flat float16, shape (N, 384), L2-normalized
    data/embedding_ids_bge.json     list of {env_id, task_id} in row order

Caching is content-addressable (sha of model + doc string).
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np

from .embed import _doc_string  # reuse the doc-string composition
from .jsonio import append_jsonl, load_cache, read_jsonl, sha256_of
from .paths import CACHE_DIR, DATA_DIR, TASKS_ENRICHED

logger = logging.getLogger(__name__)


BGE_MODEL = "BAAI/bge-small-en-v1.5"
BGE_DIM = 384
BGE_BATCH = 64

EMBED_CACHE_BGE = CACHE_DIR / "embed_bge.jsonl"
EMBEDDINGS_BGE = DATA_DIR / "embeddings_bge.f16.bin"
EMBEDDING_IDS_BGE = DATA_DIR / "embedding_ids_bge.json"


def _key(doc: str) -> str:
    return sha256_of({"model": BGE_MODEL, "doc": doc})


def run(
    *,
    input_path: Optional[Path] = None,
    cache_path: Optional[Path] = None,
    matrix_path: Optional[Path] = None,
    ids_path: Optional[Path] = None,
    batch_size: int = BGE_BATCH,
    limit: Optional[int] = None,
) -> Dict[str, object]:
    if input_path is None:
        input_path = TASKS_ENRICHED
    if cache_path is None:
        cache_path = EMBED_CACHE_BGE
    if matrix_path is None:
        matrix_path = EMBEDDINGS_BGE
    if ids_path is None:
        ids_path = EMBEDDING_IDS_BGE
    if not input_path.is_file():
        raise RuntimeError(f"missing input: {input_path}. Run enrichment first.")

    records: List[Dict[str, object]] = list(read_jsonl(input_path))
    if limit is not None:
        records = records[:limit]

    docs: List[str] = [_doc_string(r) for r in records]
    keys: List[str] = [_key(d) for d in docs]

    cache = load_cache(cache_path, key="key")
    todo_idx = [i for i, k in enumerate(keys) if k not in cache]
    logger.info(
        "BGE embed plan: %d total, %d cached, %d to encode (model=%s, dim=%d, batch=%d).",
        len(records), len(records) - len(todo_idx), len(todo_idx), BGE_MODEL, BGE_DIM, batch_size,
    )

    if todo_idx:
        from sentence_transformers import SentenceTransformer  # imported lazily
        model = SentenceTransformer(BGE_MODEL)

        # bge models recommend a query prefix for asymmetric tasks; we use the
        # passage-side encoding (no prefix) for the corpus, and `query: ` prefix
        # for queries on the browser side. Matches what Xenova/bge-small-en-v1.5
        # exposes via transformers.js.
        n_done = 0
        n_total = len(todo_idx)
        for start in range(0, n_total, batch_size):
            sub_idx = todo_idx[start:start + batch_size]
            sub_docs = [docs[i] for i in sub_idx]
            sub_keys = [keys[i] for i in sub_idx]
            vecs = model.encode(
                sub_docs,
                batch_size=len(sub_docs),
                normalize_embeddings=True,
                show_progress_bar=False,
                convert_to_numpy=True,
            )
            if vecs.shape != (len(sub_docs), BGE_DIM):
                raise RuntimeError(
                    f"unexpected encode shape {vecs.shape}; expected ({len(sub_docs)}, {BGE_DIM})"
                )
            for k, v in zip(sub_keys, vecs):
                cache[k] = {"key": k, "vec": v.astype(np.float32).tolist()}
                append_jsonl(cache_path, {"key": k, "vec": v.astype(np.float32).tolist()})
            n_done += len(sub_idx)
            sys.stderr.write(
                f"\r  bge-encoded {n_done}/{n_total} ({100*n_done/n_total:.1f}%)"
            )
            sys.stderr.flush()
        sys.stderr.write("\n")

    # Materialize matrix in record order.
    matrix = np.zeros((len(records), BGE_DIM), dtype=np.float16)
    ids: List[Dict[str, str]] = []
    for i, (rec, k) in enumerate(zip(records, keys)):
        item = cache.get(k)
        if item is None:
            raise RuntimeError(f"missing bge embedding for {rec['env_id']}/{rec['task_id']}")
        matrix[i] = np.asarray(item["vec"], dtype=np.float16)
        ids.append({"env_id": str(rec["env_id"]), "task_id": str(rec["task_id"])})

    # Already L2-normalized by sentence-transformers (normalize_embeddings=True).
    # Re-normalize defensively after the float16 cast.
    norms = np.linalg.norm(matrix.astype(np.float32), axis=1, keepdims=True)
    norms = np.where(norms == 0, 1.0, norms)
    matrix = (matrix.astype(np.float32) / norms).astype(np.float16)

    matrix_path.parent.mkdir(parents=True, exist_ok=True)
    # Flat little-endian float16 bytes, easy to mmap from the browser as a
    # Uint16Array → Float16-style decode.
    matrix.astype("<f2").tofile(matrix_path)
    ids_path.write_text(json.dumps(ids), encoding="utf-8")
    logger.info(
        "Wrote %d × %d bge embeddings → %s (%.1f MB) ; ids → %s",
        matrix.shape[0], matrix.shape[1], matrix_path,
        matrix_path.stat().st_size / 1024 / 1024, ids_path,
    )
    return {
        "n_total": len(records),
        "n_called": len(todo_idx),
        "matrix_shape": list(matrix.shape),
        "model": BGE_MODEL,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    print(json.dumps(run(), indent=2))
