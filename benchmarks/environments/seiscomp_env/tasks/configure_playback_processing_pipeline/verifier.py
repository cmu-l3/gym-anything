#!/usr/bin/env python3
"""Verifier for configure_playback_processing_pipeline task.

A seismologist must configure an offline processing pipeline (scautopick + scautoloc),
set appropriate station bindings and filter parameters, execute a playback of archived
waveforms, and verify that automatic picks and origins were generated.

Scoring:
- 25 pts: Station bindings configured (scautopick on all 3 target stations)
- 25 pts: scautopick config exists with a bandpass filter setting
- 25 pts: Automatic picks generated in database (at least 1 per station)
- 15 pts: At least one automatic origin generated in database
- 10 pts: Results summary file exists with pick and origin counts

Wrong-target guard: If no new picks or origins AND no config changes, return 0.
"""

import json
import os
import tempfile


def verify_configure_playback_processing_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "configure_playback_processing_pipeline"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(result_path, tmp.name)
            with open(tmp.name, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result file is not valid JSON: {e}",
        }

    def _bool(v):
        if isinstance(v, bool):
            return v
        return str(v).lower() == "true"

    stations_with_scautopick = int(result.get("stations_with_scautopick", 0))
    has_scautopick_cfg = _bool(result.get("has_scautopick_cfg", False))
    scautopick_filter = str(result.get("scautopick_filter", ""))
    has_scautoloc_cfg = _bool(result.get("has_scautoloc_cfg", False))
    auto_pick_count = int(result.get("auto_pick_count", 0))
    picks_gsi = int(result.get("picks_gsi", 0))
    picks_bkb = int(result.get("picks_bkb", 0))
    picks_sani = int(result.get("picks_sani", 0))
    auto_origin_count = int(result.get("auto_origin_count", 0))
    results_exists = _bool(result.get("results_exists", False))
    results_mentions_picks = _bool(result.get("results_mentions_picks", False))
    results_mentions_origins = _bool(result.get("results_mentions_origins", False))

    # ── Do-nothing guard ───────────────────────────────────────────────────
    if stations_with_scautopick == 0 and auto_pick_count == 0 and not has_scautopick_cfg:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No configuration changes detected. Station bindings are empty, "
                "no scautopick config exists, and no automatic picks were generated. "
                "The agent must configure bindings, set filter parameters, and run a playback."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (25 pts): Station bindings ────────────────────────────
    if stations_with_scautopick >= 3:
        score += 25
        parts.append(f"scautopick bindings on {stations_with_scautopick} stations (25/25)")
    elif stations_with_scautopick >= 1:
        pts = stations_with_scautopick * 8
        score += pts
        parts.append(
            f"scautopick bindings on only {stations_with_scautopick}/3 stations ({pts}/25)"
        )
    else:
        parts.append("No scautopick station bindings configured (0/25)")

    # ── Criterion 2 (25 pts): scautopick config with filter ──────────────
    if has_scautopick_cfg and "BW" in scautopick_filter.upper():
        score += 25
        parts.append(f"scautopick.cfg with bandpass filter configured (25/25)")
    elif has_scautopick_cfg:
        score += 15
        parts.append("scautopick.cfg exists but no clear BW filter found (15/25)")
    else:
        parts.append("scautopick.cfg not found (0/25)")

    # ── Criterion 3 (25 pts): Automatic picks generated ──────────────────
    stations_with_picks = sum(1 for p in [picks_gsi, picks_bkb, picks_sani] if p > 0)
    if auto_pick_count >= 3 and stations_with_picks >= 3:
        score += 25
        parts.append(
            f"{auto_pick_count} automatic picks on {stations_with_picks} stations (25/25)"
        )
    elif auto_pick_count >= 1 and stations_with_picks >= 2:
        score += 18
        parts.append(
            f"{auto_pick_count} picks on {stations_with_picks} stations — missing some (18/25)"
        )
    elif auto_pick_count >= 1:
        score += 10
        parts.append(
            f"{auto_pick_count} picks on {stations_with_picks} station(s) — incomplete (10/25)"
        )
    else:
        parts.append("No automatic picks generated — playback may not have run (0/25)")

    # ── Criterion 4 (15 pts): Automatic origin generated ─────────────────
    if auto_origin_count >= 1:
        score += 15
        parts.append(f"{auto_origin_count} automatic origin(s) detected (15/15)")
    else:
        parts.append("No automatic origin generated — scautoloc may not have run (0/15)")

    # ── Criterion 5 (10 pts): Results summary file ───────────────────────
    if results_exists and results_mentions_picks and results_mentions_origins:
        score += 10
        parts.append("Results summary file with pick and origin info (10/10)")
    elif results_exists and (results_mentions_picks or results_mentions_origins):
        score += 5
        parts.append("Results summary file exists but incomplete (5/10)")
    elif results_exists:
        score += 3
        parts.append("Results summary file exists but lacks expected content (3/10)")
    else:
        parts.append(
            "No results file at /home/ga/Desktop/playback_results.txt (0/10)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
