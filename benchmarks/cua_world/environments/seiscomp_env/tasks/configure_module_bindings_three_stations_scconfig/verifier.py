#!/usr/bin/env python3
"""Verifier for configure_module_bindings_three_stations_scconfig task.

A network operator must configure scautopick and scamp module bindings for three
seismic stations (GE.GSI, GE.BKB, GE.SANI) using scconfig, writing the
configuration to the SeisComP station key files.

Scoring:
  Up to 50 pts: scautopick binding for all 3 stations (≈17 pts each)
  Up to 30 pts: scamp binding for all 3 stations (≈10 pts each)
  20 pts: Both modules configured on ALL 3 stations (full configuration bonus)

Wrong-target guard: Total binding count must exceed initial baseline count.
"""

import json
import os
import tempfile


def verify_configure_module_bindings_three_stations_scconfig(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    task_name = "configure_module_bindings_three_stations_scconfig"
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

    initial_scautopick = int(result.get("initial_scautopick_count", 0))
    initial_scamp = int(result.get("initial_scamp_count", 0))
    scautopick_count = int(result.get("scautopick_station_count", 0))
    scamp_count = int(result.get("scamp_station_count", 0))

    gsi_scautopick = _bool(result.get("gsi_has_scautopick", False))
    gsi_scamp = _bool(result.get("gsi_has_scamp", False))
    bkb_scautopick = _bool(result.get("bkb_has_scautopick", False))
    bkb_scamp = _bool(result.get("bkb_has_scamp", False))
    sani_scautopick = _bool(result.get("sani_has_scautopick", False))
    sani_scamp = _bool(result.get("sani_has_scamp", False))

    # ── Wrong-target guard ────────────────────────────────────────────────────
    total_new = (scautopick_count - initial_scautopick) + (scamp_count - initial_scamp)
    if total_new <= 0 and scautopick_count == 0 and scamp_count == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": (
                "No module bindings found for GE.GSI, GE.BKB, or GE.SANI. "
                "Open scconfig → Bindings panel → select each station → "
                "add 'scautopick' and 'scamp' bindings → Save and Update."
            ),
        }

    score = 0
    parts = []

    # ── Criterion 1 (50 pts): scautopick bindings for all 3 stations ─────────
    # 50 pts total: 17 pts per station (rounded)
    scautopick_pts = 0
    station_scautopick_status = []
    for sta, has_binding in [("GE.GSI", gsi_scautopick), ("GE.BKB", bkb_scautopick), ("GE.SANI", sani_scautopick)]:
        if has_binding:
            scautopick_pts += 17
            station_scautopick_status.append(f"{sta}:✓")
        else:
            station_scautopick_status.append(f"{sta}:✗")
    # Bonus for all 3 (avoids rounding to 51)
    if scautopick_count == 3:
        scautopick_pts = 50
    score += scautopick_pts
    parts.append(
        f"scautopick bindings: {', '.join(station_scautopick_status)} "
        f"({scautopick_pts}/50)"
    )

    # ── Criterion 2 (30 pts): scamp bindings for all 3 stations ──────────────
    # 30 pts total: 10 pts per station
    scamp_pts = 0
    station_scamp_status = []
    for sta, has_binding in [("GE.GSI", gsi_scamp), ("GE.BKB", bkb_scamp), ("GE.SANI", sani_scamp)]:
        if has_binding:
            scamp_pts += 10
            station_scamp_status.append(f"{sta}:✓")
        else:
            station_scamp_status.append(f"{sta}:✗")
    score += scamp_pts
    parts.append(
        f"scamp bindings: {', '.join(station_scamp_status)} "
        f"({scamp_pts}/30)"
    )

    # ── Criterion 3 (20 pts): Full configuration bonus ───────────────────────
    all_configured = (
        gsi_scautopick and gsi_scamp
        and bkb_scautopick and bkb_scamp
        and sani_scautopick and sani_scamp
    )
    if all_configured:
        score += 20
        parts.append(
            "All 3 stations have both scautopick and scamp bindings — full configuration (20/20)"
        )
    else:
        missing = []
        if not (gsi_scautopick and gsi_scamp):
            missing.append("GE.GSI")
        if not (bkb_scautopick and bkb_scamp):
            missing.append("GE.BKB")
        if not (sani_scautopick and sani_scamp):
            missing.append("GE.SANI")
        parts.append(
            f"Incomplete: {', '.join(missing)} still missing one or both module bindings (0/20)"
        )

    passed = score >= 60
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(parts),
    }
