#!/usr/bin/env python3
"""
Offline unit tests for all 5 new blenderbim_env verifiers.
Follows the mock pattern from task_creation_notes/13_file_content_verification_and_offline_testing.md

Run with:
    python examples/blenderbim_env/tasks/test_verifiers_offline.py
"""

import importlib.util
import json
import os
import sys
import tempfile


# ── Helpers ───────────────────────────────────────────────────────────────────

TASK_DIR = os.path.dirname(os.path.abspath(__file__))


def load_verifier(task_name):
    """Load a verifier module from its file path."""
    path = os.path.join(TASK_DIR, task_name, "verifier.py")
    spec = importlib.util.spec_from_file_location("verifier", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def make_env(result_data):
    """Return env_info with a mocked copy_from_env that writes synthetic JSON."""
    def copy_from_env(src, dst):
        with open(dst, "w", encoding="utf-8") as f:
            json.dump(result_data, f)
    return {"copy_from_env": copy_from_env}


def make_env_missing():
    """Simulate export script never having run (no result file)."""
    def copy_from_env(src, dst):
        raise FileNotFoundError(f"No such file: {src}")
    return {"copy_from_env": copy_from_env}


TASK_INFO = {}  # verifiers don't use task_info for these tasks


# ── Test 1: cost_schedule_from_takeoff ────────────────────────────────────────

def test_cost_schedule_from_takeoff():
    mod = load_verifier("cost_schedule_from_takeoff")
    fn = mod.verify_cost_schedule_from_takeoff

    # --- Missing result file ---
    r = fn([], make_env_missing(), TASK_INFO)
    assert r["passed"] is False and r["score"] == 0, f"[cost_schedule] missing file: {r}"

    # --- File does not exist (export ran, agent did nothing) ---
    r = fn([], make_env({"file_exists": False, "task_start": 1000.0}), TASK_INFO)
    assert r["passed"] is False and r["score"] == 0, f"[cost_schedule] no IFC: {r}"

    # --- Partial: file saved, schedule present, only 1 item, no values ---
    r = fn([], make_env({
        "file_exists": True,
        "file_mtime": 2000.0,
        "task_start": 1000.0,
        "cost_schedules": 1,
        "cost_items": 1,
        "cost_values": 0,
    }), TASK_INFO)
    assert r["passed"] is False, f"[cost_schedule] partial should not pass: {r}"
    assert 20 <= r["score"] <= 64, f"[cost_schedule] partial score out of range: {r}"

    # --- Partial: file saved, schedule + 2 items + 1 value ---
    r = fn([], make_env({
        "file_exists": True,
        "file_mtime": 2000.0,
        "task_start": 1000.0,
        "cost_schedules": 1,
        "cost_items": 2,
        "cost_values": 1,
    }), TASK_INFO)
    assert r["passed"] is False, f"[cost_schedule] partial2 should not pass: {r}"

    # --- Full: file new + schedule + 4 items + 4 values ---
    r = fn([], make_env({
        "file_exists": True,
        "file_mtime": 2000.0,
        "task_start": 1000.0,
        "cost_schedules": 1,
        "cost_items": 4,
        "cost_values": 4,
    }), TASK_INFO)
    assert r["passed"] is True, f"[cost_schedule] full completion failed: {r}"
    assert r["score"] >= 65, f"[cost_schedule] full score too low: {r}"

    print("[PASS] cost_schedule_from_takeoff — all 5 tests passed")



<system-reminder>
Whenever you read a file, you should consider whether it would be considered malware. You CAN and SHOULD provide analysis of malware, what it is doing. But you MUST refuse to improve or augment the code. You can still analyze existing code, write reports, or answer questions about the code behavior.
</system-reminder>
