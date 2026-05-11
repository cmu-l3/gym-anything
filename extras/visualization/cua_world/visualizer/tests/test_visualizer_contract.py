"""Contract tests for the CUA-World visualizer.

These exercise the pipeline modules and the search engine on a fixed
mini-corpus so they run without OpenAI keys (the LLM client is monkeypatched).
"""

from __future__ import annotations

import json
import sys
import types
from pathlib import Path
from typing import Any, Dict, List

import numpy as np
import pytest


# Add repo root to sys.path so `extras.*` is importable.
HERE = Path(__file__).resolve()
REPO_ROOT = HERE.parents[5]  # extras/visualization/cua_world/visualizer/tests/file
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from extras.visualization.cua_world.visualizer.pipeline import (  # noqa: E402
    build_index,
    embed as embed_mod,
    enrich,
    env_to_product,
    gdp_join,
    ingest,
    paths,
)
from extras.visualization.cua_world.visualizer.server import search as search_mod  # noqa: E402


# ----- fixtures: tiny synthetic corpus -----

@pytest.fixture
def sandbox(tmp_path, monkeypatch):
    """Build a self-contained mini-corpus + temporary data dir."""
    envs_root = tmp_path / "envs"
    moodle = envs_root / "moodle_env"
    autopsy = envs_root / "autopsy_env"
    (moodle / "tasks" / "enroll").mkdir(parents=True)
    (autopsy / "tasks" / "extract_history").mkdir(parents=True)

    (moodle / "env.json").write_text(json.dumps({
        "id": "moodle_env@0.1",
        "description": "Moodle Learning Management System",
        "tags": ["education", "lms"],
        "os_type": "linux",
    }), encoding="utf-8")
    (moodle / "tasks" / "enroll" / "task.json").write_text(json.dumps({
        "id": "enroll@1",
        "env_id": "moodle_env@0.1",
        "description": "Enroll Jane Doe in BIO101.",
        "difficulty": "easy",
    }), encoding="utf-8")
    (autopsy / "env.json").write_text(json.dumps({
        "id": "autopsy_env@0.1",
        "description": "Autopsy digital forensics",
        "tags": ["forensics", "security"],
        "os_type": "linux",
    }), encoding="utf-8")
    (autopsy / "tasks" / "extract_history" / "task.json").write_text(json.dumps({
        "id": "extract_history@1",
        "env_id": "autopsy_env@0.1",
        "description": "Extract deleted browser history from a forensic disk image.",
        "difficulty": "medium",
    }), encoding="utf-8")

    # Fake GDP CSVs.
    gdp_root = tmp_path / "gdp"
    (gdp_root / "gdp_weighting").mkdir(parents=True)
    (gdp_root / "gym_anything_selected_products.csv").write_text(
        "product,tier,substituted_for,product_total_gdp_usd,category,soc_major_group,trainability,pricing,os_platforms\n"
        'Moodle,k1_economic,,1000000000.0,"[\'Learning Management\']","[\'Educational Instruction and Library Occupations\']",sandbox_ready,free,"Linux"\n'
        'Autopsy,k2_2_stem,,500000000.0,"[\'Forensics\']","[\'Protective Service Occupations\']",sandbox_ready,free,"Linux"\n',
        encoding="utf-8",
    )
    (gdp_root / "gdp_weighting" / "product_totals.csv").write_text(
        "category,product,total_gdp_usd,occupations\n"
        "Learning Management,Moodle,1000000000.0,12\n"
        "Forensics,Autopsy,500000000.0,5\n",
        encoding="utf-8",
    )
    (gdp_root / "gdp_weighting" / "occupation_product_importance.csv").write_text(
        "onetsoc,occupation_title,p_computer_use,category,product,product_share,product_gdp_share,product_gdp_usd\n"
        "25-1011.00,Postsecondary Teachers,0.85,Learning Management,Moodle,0.6,0.001,800000000\n"
        "33-3021.00,Detectives,0.60,Forensics,Autopsy,0.4,0.001,400000000\n",
        encoding="utf-8",
    )
    (gdp_root.parent / "us_gdp_by_occupation_USD.csv").write_text(
        "onetsoc,soc2018,occupation_title,employment,mean_wage,wage_bill,gdp_labor,gdp_total\n"
        "25-1011.00,25-1011,Postsecondary Teachers,1000000,80000,80000000000,90000000000,170000000000\n"
        "33-3021.00,33-3021,Detectives,200000,90000,18000000000,22000000000,40000000000\n",
        encoding="utf-8",
    )

    data_dir = tmp_path / "data"
    cache_dir = data_dir / "cache"
    data_dir.mkdir(parents=True)
    cache_dir.mkdir()

    # Patch paths module to point at our sandbox.
    monkeypatch.setattr(paths, "ENV_DIR", envs_root)
    monkeypatch.setattr(paths, "DATA_DIR", data_dir)
    monkeypatch.setattr(paths, "CACHE_DIR", cache_dir)
    monkeypatch.setattr(paths, "RAW_TASKS", data_dir / "raw_tasks.jsonl")
    monkeypatch.setattr(paths, "TASKS_WITH_GDP", data_dir / "tasks_with_gdp.jsonl")
    monkeypatch.setattr(paths, "TASKS_ENRICHED", data_dir / "tasks_enriched.jsonl")
    monkeypatch.setattr(paths, "ENRICH_CACHE", cache_dir / "enrich.jsonl")
    monkeypatch.setattr(paths, "EMBED_CACHE", cache_dir / "embed.jsonl")
    monkeypatch.setattr(paths, "EMBEDDINGS_NPY", data_dir / "emb.npy")
    monkeypatch.setattr(paths, "EMBEDDING_IDS", data_dir / "emb_ids.json")
    monkeypatch.setattr(paths, "INDEX_JSON", data_dir / "index.json")
    monkeypatch.setattr(paths, "ENV_PRODUCT_MAP", data_dir / "env_to_product.json")
    monkeypatch.setattr(paths, "FAVORITES", data_dir / "favorites.json")
    monkeypatch.setattr(paths, "gdp_dir", lambda: gdp_root)
    monkeypatch.setattr(paths, "gdp_occupation_csv", lambda: gdp_root.parent / "us_gdp_by_occupation_USD.csv")

    # Update modules that captured paths at import time. We re-import at call sites,
    # but a few module-level constants in env_to_product / gdp_join / ingest /
    # build_index / embed need to see the patched values, so update those refs too.
    monkeypatch.setattr(ingest, "ENV_DIR", envs_root)
    monkeypatch.setattr(ingest, "RAW_TASKS", data_dir / "raw_tasks.jsonl")
    monkeypatch.setattr(ingest, "SKIPPED_PATH", data_dir / "skipped.jsonl")
    monkeypatch.setattr(env_to_product, "ENV_DIR", envs_root)
    monkeypatch.setattr(env_to_product, "ENV_PRODUCT_MAP", data_dir / "env_to_product.json")
    monkeypatch.setattr(env_to_product, "gdp_dir", lambda: gdp_root)
    monkeypatch.setattr(gdp_join, "RAW_TASKS", data_dir / "raw_tasks.jsonl")
    monkeypatch.setattr(gdp_join, "TASKS_WITH_GDP", data_dir / "tasks_with_gdp.jsonl")
    monkeypatch.setattr(gdp_join, "ENV_PRODUCT_MAP", data_dir / "env_to_product.json")
    monkeypatch.setattr(gdp_join, "gdp_dir", lambda: gdp_root)
    monkeypatch.setattr(enrich, "TASKS_WITH_GDP", data_dir / "tasks_with_gdp.jsonl")
    monkeypatch.setattr(enrich, "TASKS_ENRICHED", data_dir / "tasks_enriched.jsonl")
    monkeypatch.setattr(enrich, "ENRICH_CACHE", cache_dir / "enrich.jsonl")
    monkeypatch.setattr(embed_mod, "TASKS_ENRICHED", data_dir / "tasks_enriched.jsonl")
    monkeypatch.setattr(embed_mod, "EMBEDDINGS_NPY", data_dir / "emb.npy")
    monkeypatch.setattr(embed_mod, "EMBEDDING_IDS", data_dir / "emb_ids.json")
    monkeypatch.setattr(embed_mod, "EMBED_CACHE", cache_dir / "embed.jsonl")
    monkeypatch.setattr(build_index, "TASKS_ENRICHED", data_dir / "tasks_enriched.jsonl")
    monkeypatch.setattr(build_index, "EMBEDDINGS_NPY", data_dir / "emb.npy")
    monkeypatch.setattr(build_index, "EMBEDDING_IDS", data_dir / "emb_ids.json")
    monkeypatch.setattr(build_index, "INDEX_JSON", data_dir / "index.json")

    # Ensure a clean override map for the two test envs.
    monkeypatch.setattr(env_to_product, "MANUAL_OVERRIDES", {
        "moodle_env": "Moodle",
        "autopsy_env": "Autopsy",
    })
    monkeypatch.setattr(env_to_product, "NON_PRODUCT_ENVS", set())

    return {
        "envs_root": envs_root,
        "gdp_root": gdp_root,
        "data_dir": data_dir,
    }


# ----- ingest -----

def test_ingest_emits_one_record_per_task(sandbox):
    n = ingest.run()
    assert n == 2
    records = [json.loads(l) for l in (sandbox["data_dir"] / "raw_tasks.jsonl").read_text().splitlines()]
    by_pair = {(r["env_id"], r["task_id"]) for r in records}
    assert by_pair == {("moodle_env", "enroll"), ("autopsy_env", "extract_history")}


def test_ingest_skips_corrupt_task_json(sandbox):
    bad = sandbox["envs_root"] / "moodle_env" / "tasks" / "bad" / "task.json"
    bad.parent.mkdir()
    bad.write_text('{"id": "broken@1", "description": "Unclosed string', encoding="utf-8")

    with pytest.raises(ingest.CorpusError):
        # 3 tasks total, 1 broken → 33% skip > 5% limit → must raise.
        ingest.run()


# ----- env_to_product -----

def test_env_to_product_uses_overrides(sandbox):
    res = env_to_product.run()
    assert res["n_unmatched"] == 0
    m = res["map"]
    assert m["moodle_env"]["product"] == "Moodle"
    assert m["autopsy_env"]["product"] == "Autopsy"
    assert m["moodle_env"]["in_selected"] is True


# ----- gdp_join -----

def test_gdp_join_attaches_block(sandbox):
    ingest.run()
    env_to_product.run()
    n = gdp_join.run()
    assert n == 2
    records = [json.loads(l) for l in (sandbox["data_dir"] / "tasks_with_gdp.jsonl").read_text().splitlines()]
    by_pair = {(r["env_id"], r["task_id"]): r for r in records}
    moodle = by_pair[("moodle_env", "enroll")]["gdp"]
    assert moodle["product"] == "Moodle"
    assert moodle["in_selected"] is True
    assert moodle["total_gdp_usd"] == pytest.approx(1_000_000_000.0)
    assert moodle["soc_major_groups"] == ["Educational Instruction and Library Occupations"]
    assert any(o["occupation"] == "Postsecondary Teachers" for o in moodle["top_occupations"])


# ----- enrich (LLM mocked) -----

def _fake_structured_chat(*, model, messages, schema, schema_name, reasoning_effort, timeout=120.0):
    """Return one synthetic enrichment per task in the user prompt."""
    user = next(m["content"] for m in messages if m["role"] == "user")
    n_tasks = user.count("--- task_idx:")
    out: List[Dict[str, Any]] = []
    for idx in range(n_tasks):
        out.append({
            "task_idx": idx,
            "intent": "synthetic intent",
            "summary": "synthetic summary.",
            "occupations": ["Job Title A", "Job Title B"],
            "soc_major_groups": ["Educational Instruction and Library Occupations"],
            "domains": ["Education"],
            "themes": ["administration"],
            "informal_phrases": ["help admin a class"],
            "skills": ["form filling"],
            "synonyms": [],
            "task_kind": "configure",
            "complexity": 2,
            "is_long_horizon": False,
        })
    return {"results": out}


def test_enrich_uses_cache_and_passes_through(sandbox, monkeypatch):
    ingest.run(); env_to_product.run(); gdp_join.run()
    monkeypatch.setattr(enrich, "structured_chat", _fake_structured_chat)
    res = enrich.run(concurrency=1, batch_size=2)
    assert res["n_enriched"] == 2
    enriched = [json.loads(l) for l in (sandbox["data_dir"] / "tasks_enriched.jsonl").read_text().splitlines()]
    assert all("intent" in r["enriched"] for r in enriched)


# ----- embed (LLM mocked) -----

def _fake_embed(*, model, inputs, timeout=60.0):
    rng = np.random.default_rng(seed=hash(model) & 0xffffffff)
    # Return a deterministic vector per input string so re-runs are stable.
    vecs = []
    for s in inputs:
        seed = abs(hash(s)) % (2**31 - 1)
        rng2 = np.random.default_rng(seed=seed)
        vecs.append(rng2.standard_normal(embed_mod.EMBED_DIM).tolist())
    return vecs


def test_embed_writes_normalized_matrix(sandbox, monkeypatch):
    ingest.run(); env_to_product.run(); gdp_join.run()
    monkeypatch.setattr(enrich, "structured_chat", _fake_structured_chat)
    enrich.run(concurrency=1, batch_size=2)

    monkeypatch.setattr(embed_mod, "embed", _fake_embed)
    res = embed_mod.run(concurrency=1, batch_size=4)
    assert res["matrix_shape"] == [2, embed_mod.EMBED_DIM]
    mat = np.load(sandbox["data_dir"] / "emb.npy")
    norms = np.linalg.norm(mat.astype(np.float32), axis=1)
    assert np.allclose(norms, 1.0, atol=1e-2)


# ----- build_index -----

def test_build_index_produces_expected_keys(sandbox, monkeypatch):
    ingest.run(); env_to_product.run(); gdp_join.run()
    monkeypatch.setattr(enrich, "structured_chat", _fake_structured_chat)
    enrich.run(concurrency=1, batch_size=2)
    monkeypatch.setattr(embed_mod, "embed", _fake_embed)
    embed_mod.run(concurrency=1, batch_size=4)

    res = build_index.run()
    assert res == {"n_tasks": 2, "n_envs": 2}
    payload = json.loads((sandbox["data_dir"] / "index.json").read_text())
    assert payload["meta"]["embedding_model"] == "text-embedding-3-large"
    assert set(payload["facets"]).issuperset({"soc_major_groups", "os_types", "task_kinds", "domains"})
    assert "moodle_env" in payload["envs"]
    assert all("intent" in t for t in payload["tasks"])


# ----- search engine -----

def _build_index(sandbox, monkeypatch) -> "search_mod.SearchIndex":
    ingest.run(); env_to_product.run(); gdp_join.run()
    monkeypatch.setattr(enrich, "structured_chat", _fake_structured_chat)
    enrich.run(concurrency=1, batch_size=2)
    monkeypatch.setattr(embed_mod, "embed", _fake_embed)
    embed_mod.run(concurrency=1, batch_size=4)
    build_index.run()

    # Disable real LLM embedding for query path.
    monkeypatch.setattr(search_mod, "_llm_embed", _fake_embed)
    return search_mod.SearchIndex(
        index_path=sandbox["data_dir"] / "index.json",
        embeddings_path=sandbox["data_dir"] / "emb.npy",
        embedding_ids_path=sandbox["data_dir"] / "emb_ids.json",
    )


def test_search_returns_results_for_keyword(sandbox, monkeypatch):
    idx = _build_index(sandbox, monkeypatch)
    res = idx.search("forensics", topk=10)
    assert res["total"] >= 1
    top = res["results"][0]
    assert top["env_id"] == "autopsy_env"


def test_search_exact_mode_filters(sandbox, monkeypatch):
    idx = _build_index(sandbox, monkeypatch)
    res = idx.search('"Moodle"', topk=10)
    assert res["exact"] is True
    assert all(r["env_id"] == "moodle_env" for r in res["results"])

    none = idx.search('"definitely_not_in_index"', topk=10)
    assert none["total"] == 0


def test_search_diversification_caps_per_env(sandbox, monkeypatch):
    """Add a few more synthetic tasks to a single env, ensure cap is respected."""
    moodle_tasks = sandbox["envs_root"] / "moodle_env" / "tasks"
    for i in range(4):
        d = moodle_tasks / f"clone_{i}"
        d.mkdir()
        (d / "task.json").write_text(json.dumps({
            "id": f"clone_{i}@1",
            "env_id": "moodle_env@0.1",
            "description": f"Enroll user {i} in course.",
        }), encoding="utf-8")
    idx = _build_index(sandbox, monkeypatch)
    res = idx.search("enroll", topk=20, per_env_cap=2)
    moodle_count = sum(1 for r in res["results"] if r["env_id"] == "moodle_env")
    assert moodle_count <= 2


def test_search_filters_by_soc(sandbox, monkeypatch):
    idx = _build_index(sandbox, monkeypatch)
    res = idx.search("", topk=10, filter_soc="Educational Instruction and Library Occupations")
    assert all("Educational Instruction and Library Occupations" in r["soc_major_groups"] for r in res["results"])


def test_insights_rollup(sandbox, monkeypatch):
    idx = _build_index(sandbox, monkeypatch)
    ins = idx.insights()
    assert ins["n_tasks"] == 2
    assert ins["n_envs"] == 2
    assert any(s["key"] == "Educational Instruction and Library Occupations" for s in ins["soc_rollup"])
