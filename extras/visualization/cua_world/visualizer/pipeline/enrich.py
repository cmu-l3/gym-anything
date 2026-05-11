"""Stage 3: LLM enrichment via OpenAI gpt-5.4-nano (reasoning_effort=medium).

Per task we ask the model for a structured JSON record:

    intent, summary, occupations, soc_major_groups, domains, themes,
    informal_phrases, skills, synonyms, task_kind, complexity, is_long_horizon

Tasks are batched (default 5 per request) to keep token usage reasonable while
still giving each task its own structured slot. We index the model's output by
`task_idx` so we can recover the per-task records even if the order shifts.

Caching is content-addressable: every task gets a sha computed from its
(env_id, task_id, intent_doc) and only un-cached tasks are sent. The cache
file is JSONL, append-only, so partial runs survive interruption.

Concurrency: a thread pool runs N batches in parallel. Hard-fails if any task
remains unenriched after retries; the user said no fallbacks.
"""

from __future__ import annotations

import json
import logging
import sys
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

from .jsonio import append_jsonl, load_cache, read_jsonl, sha256_of, write_jsonl
from .llm_client import structured_chat
from .paths import ENRICH_CACHE, TASKS_ENRICHED, TASKS_WITH_GDP

logger = logging.getLogger(__name__)


ENRICH_MODEL = "gpt-5.4-nano"
REASONING_EFFORT = "medium"
BATCH_SIZE = 5
CONCURRENCY = 8


# 22 SOC major groups — given to the model so it picks from a closed vocabulary.
SOC_MAJOR_GROUPS = [
    "Management Occupations",
    "Business and Financial Operations Occupations",
    "Computer and Mathematical Occupations",
    "Architecture and Engineering Occupations",
    "Life, Physical, and Social Science Occupations",
    "Community and Social Service Occupations",
    "Legal Occupations",
    "Educational Instruction and Library Occupations",
    "Arts, Design, Entertainment, Sports, and Media Occupations",
    "Healthcare Practitioners and Technical Occupations",
    "Healthcare Support Occupations",
    "Protective Service Occupations",
    "Food Preparation and Serving Related Occupations",
    "Building and Grounds Cleaning and Maintenance Occupations",
    "Personal Care and Service Occupations",
    "Sales and Related Occupations",
    "Office and Administrative Support Occupations",
    "Farming, Fishing, and Forestry Occupations",
    "Construction and Extraction Occupations",
    "Installation, Maintenance, and Repair Occupations",
    "Production Occupations",
    "Transportation and Material Moving Occupations",
]


TASK_KINDS = [
    "configure",
    "create",
    "analyze",
    "report",
    "debug",
    "navigate",
    "extract",
    "import",
    "export",
    "integrate",
    "admin",
    "monitor",
    "secure",
    "model",
    "design",
    "other",
]


SCHEMA: Dict[str, Any] = {
    "type": "object",
    "properties": {
        "results": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "task_idx": {"type": "integer"},
                    "intent": {"type": "string"},
                    "summary": {"type": "string"},
                    "occupations": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 8,
                    },
                    "soc_major_groups": {
                        "type": "array",
                        "items": {"type": "string", "enum": SOC_MAJOR_GROUPS},
                        "maxItems": 4,
                    },
                    "domains": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 6,
                    },
                    "themes": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 8,
                    },
                    "informal_phrases": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 6,
                    },
                    "skills": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 8,
                    },
                    "synonyms": {
                        "type": "array",
                        "items": {"type": "string"},
                        "maxItems": 8,
                    },
                    "task_kind": {"type": "string", "enum": TASK_KINDS},
                    "complexity": {"type": "integer", "minimum": 1, "maximum": 5},
                    "is_long_horizon": {"type": "boolean"},
                },
                "required": [
                    "task_idx",
                    "intent",
                    "summary",
                    "occupations",
                    "soc_major_groups",
                    "domains",
                    "themes",
                    "informal_phrases",
                    "skills",
                    "synonyms",
                    "task_kind",
                    "complexity",
                    "is_long_horizon",
                ],
                "additionalProperties": False,
            },
        }
    },
    "required": ["results"],
    "additionalProperties": False,
}


SYSTEM_PROMPT = (
    "You are a metadata enrichment system for a benchmark of computer-use agent tasks. "
    "Each input task tells an AI agent to do something inside a real piece of software. "
    "For each task, return a JSON object with the fields listed in the schema. Be concrete "
    "and concise; avoid restating the description verbatim. The `intent` field is one short "
    "imperative sentence. The `summary` field is 1-2 plain-English sentences. "
    "`informal_phrases` are casual queries a non-expert would use to search for this kind "
    "of task (e.g. 'help with admin stuff', 'analyze a CT scan'). "
    "`themes` are short topical tags (e.g. 'patient records', 'circuit design'). "
    "`occupations` are concrete US job titles relevant to the task. "
    "`soc_major_groups` MUST come from the provided enum (the U.S. SOC 22 major groups). "
    "Use the GDP-grounded occupation hints provided as a strong prior, but feel free to "
    "narrow them based on the actual task description. `is_long_horizon` is true if the "
    "task likely needs more than ~30 agent steps."
)


def _short(s: Any, n: int = 800) -> str:
    s = str(s or "").strip()
    return s if len(s) <= n else s[:n] + "…"


def _build_user_prompt(batch: List[Dict[str, Any]]) -> str:
    """Render the batched task descriptions as a numbered list."""
    lines: List[str] = []
    lines.append("Enrich each of the following tasks. Return one result per task indexed by task_idx.")
    lines.append("")
    for idx, rec in enumerate(batch):
        env = rec["env_id"]
        task_id = rec["task_id"]
        env_spec = rec.get("env_spec") or {}
        task_spec = rec.get("task_spec") or {}
        gdp = rec.get("gdp") or {}

        software_name = gdp.get("product") or env_spec.get("description") or env
        env_desc = _short(env_spec.get("description"), 250)
        task_desc = _short(task_spec.get("description") or task_spec.get("name"), 1200)
        difficulty = task_spec.get("difficulty") or "—"
        env_categories = gdp.get("categories") or []
        soc_hint = gdp.get("soc_major_groups") or []
        top_occs = [o.get("occupation") for o in (gdp.get("top_occupations") or [])][:6]
        os_hint = env_spec.get("os_type") or "linux"
        env_tags = env_spec.get("tags") or []

        lines.append(f"--- task_idx: {idx} ---")
        lines.append(f"env_id: {env}")
        lines.append(f"task_id: {task_id}")
        lines.append(f"software: {software_name}")
        if env_desc:
            lines.append(f"software_description: {env_desc}")
        if env_categories:
            lines.append(f"software_categories: {', '.join(env_categories[:5])}")
        if env_tags:
            lines.append(f"env_tags: {', '.join(map(str, env_tags[:8]))}")
        lines.append(f"os: {os_hint}")
        lines.append(f"difficulty: {difficulty}")
        if soc_hint:
            lines.append(f"gdp_soc_hint: {', '.join(soc_hint[:6])}")
        if top_occs:
            lines.append(f"gdp_top_occupations: {', '.join(o for o in top_occs if o)}")
        lines.append("task_description:")
        lines.append(task_desc)
        lines.append("")
    return "\n".join(lines)


def _enrich_key(rec: Dict[str, Any]) -> str:
    """Stable cache key per task. Includes everything the model sees."""
    payload = {
        "env_id": rec["env_id"],
        "task_id": rec["task_id"],
        "task_desc": (rec.get("task_spec") or {}).get("description") or "",
        "task_name": (rec.get("task_spec") or {}).get("name") or "",
        "env_desc": (rec.get("env_spec") or {}).get("description") or "",
        "model": ENRICH_MODEL,
        "effort": REASONING_EFFORT,
    }
    return sha256_of(payload)


def _validate_result(item: Dict[str, Any]) -> None:
    required = SCHEMA["properties"]["results"]["items"]["required"]
    for k in required:
        if k not in item:
            raise RuntimeError(f"missing required field: {k}")
    if not isinstance(item["intent"], str) or not item["intent"].strip():
        raise RuntimeError("empty intent")


def _enrich_batch_once(batch: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Single attempt: prompt → parse → validate → return per-task records."""
    user_prompt = _build_user_prompt(batch)
    response = structured_chat(
        model=ENRICH_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        schema=SCHEMA,
        schema_name="task_enrichment_batch",
        reasoning_effort=REASONING_EFFORT,
    )
    items = response.get("results") or []
    if not isinstance(items, list) or len(items) != len(batch):
        raise RuntimeError(
            f"expected {len(batch)} results, got {len(items) if isinstance(items, list) else 'not-a-list'}"
        )
    by_idx: Dict[int, Dict[str, Any]] = {}
    for item in items:
        _validate_result(item)
        by_idx[int(item["task_idx"])] = item
    if set(by_idx.keys()) != set(range(len(batch))):
        raise RuntimeError(
            f"task_idx mismatch: got {sorted(by_idx)} expected {list(range(len(batch)))}"
        )

    out: List[Dict[str, Any]] = []
    for idx, rec in enumerate(batch):
        item = dict(by_idx[idx])
        item.pop("task_idx", None)
        out.append({
            "key": _enrich_key(rec),
            "env_id": rec["env_id"],
            "task_id": rec["task_id"],
            "enriched": item,
        })
    return out


def _enrich_batch(batch: List[Dict[str, Any]], *, max_attempts: int = 4) -> List[Dict[str, Any]]:
    """Wrap _enrich_batch_once with retries for occasional schema/parse drift.

    The OpenAI SDK already retries network/5xx/rate-limit. This layer retries
    when the model returns a malformed shape (rare, but it happens). On the
    final attempt we drop to batch-size=1 for the failing batch to maximise the
    odds of a clean response. If even single-task calls keep failing, we give
    up and raise so the caller can decide.
    """
    last_exc: Optional[BaseException] = None
    for attempt in range(max_attempts):
        try:
            return _enrich_batch_once(batch)
        except Exception as exc:
            last_exc = exc
            logger.warning(
                "enrich batch attempt %d/%d failed for [%s]: %s",
                attempt + 1, max_attempts,
                ", ".join(f"{r['env_id']}/{r['task_id']}" for r in batch),
                exc,
            )

    # Last resort: fan out to size-1 calls. Same model, same effort, just smaller.
    logger.warning("falling back to size-1 calls for failing batch (%d tasks).", len(batch))
    out: List[Dict[str, Any]] = []
    for rec in batch:
        for sub_attempt in range(max_attempts):
            try:
                out.extend(_enrich_batch_once([rec]))
                break
            except Exception as exc:
                last_exc = exc
                logger.warning(
                    "size-1 attempt %d/%d failed for %s/%s: %s",
                    sub_attempt + 1, max_attempts,
                    rec["env_id"], rec["task_id"], exc,
                )
        else:
            raise RuntimeError(
                f"could not enrich {rec['env_id']}/{rec['task_id']} "
                f"after {max_attempts} batch + {max_attempts} solo attempts; last: {last_exc}"
            ) from last_exc
    return out


def _iter_chunks(seq: List[Any], n: int) -> Iterable[List[Any]]:
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def run(
    *,
    input_path: Optional[Path] = None,
    output_path: Optional[Path] = None,
    cache_path: Optional[Path] = None,
    batch_size: int = BATCH_SIZE,
    concurrency: int = CONCURRENCY,
    limit: Optional[int] = None,
    only_envs: Optional[List[str]] = None,
) -> Dict[str, Any]:
    if input_path is None:
        input_path = TASKS_WITH_GDP
    if output_path is None:
        output_path = TASKS_ENRICHED
    if cache_path is None:
        cache_path = ENRICH_CACHE
    if not input_path.is_file():
        raise RuntimeError(f"missing input: {input_path}. Run gdp_join first.")

    all_records: List[Dict[str, Any]] = list(read_jsonl(input_path))
    if only_envs:
        wanted = set(only_envs)
        all_records = [r for r in all_records if r["env_id"] in wanted]
    if limit is not None:
        all_records = all_records[:limit]

    cache: Dict[str, Dict[str, Any]] = load_cache(cache_path, key="key")
    logger.info("Enrichment cache: %d entries.", len(cache))

    todo: List[Dict[str, Any]] = []
    for rec in all_records:
        k = _enrich_key(rec)
        if k not in cache:
            todo.append(rec)
    logger.info(
        "Enrichment plan: %d total tasks, %d cached, %d to enrich (~%d batches × concurrency=%d, model=%s, effort=%s).",
        len(all_records), len(all_records) - len(todo), len(todo),
        (len(todo) + batch_size - 1) // batch_size, concurrency, ENRICH_MODEL, REASONING_EFFORT,
    )

    cache_lock = threading.Lock()
    n_done = 0
    n_total = len(todo)
    progress_step = max(1, n_total // 50)

    def _process(batch: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        return _enrich_batch(batch)

    if todo:
        batches = list(_iter_chunks(todo, batch_size))
        pool = ThreadPoolExecutor(max_workers=concurrency)
        try:
            futures = {pool.submit(_process, b): b for b in batches}
            try:
                for fut in as_completed(futures):
                    batch = futures[fut]
                    try:
                        enriched_items = fut.result()
                    except Exception as exc:
                        ids = ", ".join(r["env_id"] + "/" + r["task_id"] for r in batch)
                        raise RuntimeError(
                            f"enrichment failed for batch [{ids}]: {exc}"
                        ) from exc
                    with cache_lock:
                        for item in enriched_items:
                            cache[item["key"]] = item
                            append_jsonl(cache_path, item)
                        n_done += len(enriched_items)
                        # Progress on every batch: small, frequent updates.
                        msg = f"  enriched {n_done}/{n_total} ({100*n_done/n_total:.1f}%)"
                        sys.stderr.write("\r" + msg + " " * 8)
                        sys.stderr.flush()
            except BaseException:
                # Stop accepting new work and don't wait for in-flight ones.
                for f in futures:
                    f.cancel()
                raise
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
        sys.stderr.write("\n")

    # Now stitch together: every input task must end up in output_path.
    out_records: List[Dict[str, Any]] = []
    missing: List[Tuple[str, str]] = []
    for rec in all_records:
        k = _enrich_key(rec)
        item = cache.get(k)
        if item is None:
            missing.append((rec["env_id"], rec["task_id"]))
            continue
        rec_out = dict(rec)
        rec_out["enriched"] = item["enriched"]
        out_records.append(rec_out)
    if missing:
        raise RuntimeError(
            f"{len(missing)} tasks did not get enriched (first 5: {missing[:5]}). Refusing to proceed."
        )

    write_jsonl(output_path, out_records)
    logger.info("Enriched %d tasks → %s", len(out_records), output_path)
    return {
        "n_total": len(all_records),
        "n_enriched": len(out_records),
        "n_cached_before": len(all_records) - n_total,
        "n_called": n_total,
    }


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    res = run()
    print(json.dumps(res, indent=2))
