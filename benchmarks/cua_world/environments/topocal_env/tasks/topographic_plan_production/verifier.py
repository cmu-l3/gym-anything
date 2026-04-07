#!/usr/bin/env python3
"""
Verifier for topographic_plan_production task.

Scoring (total 100 pts, pass threshold 60):
  30 pts — ClearCreek_TopoMap.dxf exists AND was created after task start
  25 pts — DXF contains LWPOLYLINE entities (contour lines present)
  20 pts — DXF contains POINT entities (survey points exported)
  25 pts — ClearCreek.top project file exists and is new
"""

import json
import os
import tempfile
from datetime import datetime, timezone


def _parse_dt(s):
    if not s:
        return None
    try:
        return datetime.fromisoformat(s.strip().replace("Z", "+00:00"))
    except Exception:
        return None


def verify_topographic_plan_production(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = (
        task_info.get("metadata", {}).get("result_file")
        or "C:\\Users\\Docker\\topographic_plan_production_result.json"
    )

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        env_info["copy_from_env"](result_path, tmp.name)
    except Exception as exc:
        return {"passed": False, "score": 0,
                "feedback": f"Could not retrieve result file: {exc}"}

    try:
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as exc:
        return {"passed": False, "score": 0,
                "feedback": f"Result JSON invalid: {exc}"}
    finally:
        os.unlink(tmp.name)

    start_dt = _parse_dt(result.get("start_time", ""))

    def is_new(mod_time_str):
        mod_dt = _parse_dt(mod_time_str)
        if not mod_dt or not start_dt:
            return False
        if mod_dt.tzinfo is None:
            mod_dt = mod_dt.replace(tzinfo=timezone.utc)
        sd = start_dt.replace(tzinfo=timezone.utc) if start_dt.tzinfo is None else start_dt
        return mod_dt > sd

    # ── Criterion 1: DXF exists and is new (30 pts) ──
    dxf_exists = bool(result.get("dxf_exists"))
    dxf_new    = dxf_exists and is_new(result.get("dxf_mod_time", ""))
    dxf_size   = int(result.get("dxf_size_bytes") or 0)

    if dxf_exists and dxf_new:
        score += 30
        feedback_parts.append("PASS(30): ClearCreek_TopoMap.dxf exists and is newer than task start")
    elif dxf_exists:
        score += 12
        feedback_parts.append("PARTIAL(12): DXF exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): ClearCreek_TopoMap.dxf not found")

    # ── Criterion 2: DXF has LWPOLYLINE entities (contour lines) (25 pts) ──
    lw_count = int(result.get("dxf_lwpoly_count") or 0)
    has_curvas = bool(result.get("dxf_has_curvas"))

    if lw_count >= 10:
        score += 25
        feedback_parts.append(f"PASS(25): DXF has {lw_count} LWPOLYLINE entities (contours)")
    elif lw_count >= 3:
        score += 12
        feedback_parts.append(f"PARTIAL(12): DXF has {lw_count} LWPOLYLINE entities (few contours)")
    elif has_curvas and dxf_size > 500:
        score += 6
        feedback_parts.append("PARTIAL(6): DXF has CURVAS layer but few/no LWPOLYLINE entities")
    elif dxf_exists and dxf_size > 2000:
        score += 4
        feedback_parts.append(f"PARTIAL(4): DXF exists ({dxf_size}B) but no recognisable contour data")
    else:
        feedback_parts.append("FAIL(0): DXF has no LWPOLYLINE contour entities")

    # ── Criterion 3: DXF has POINT entities (survey points exported) (20 pts) ──
    pt_count = int(result.get("dxf_point_count") or 0)
    has_puntos = bool(result.get("dxf_has_puntos"))

    if pt_count >= 50:
        score += 20
        feedback_parts.append(f"PASS(20): DXF has {pt_count} POINT entities (survey points)")
    elif pt_count >= 10:
        score += 10
        feedback_parts.append(f"PARTIAL(10): DXF has {pt_count} POINT entities (expected ~200)")
    elif has_puntos or (dxf_exists and dxf_size > 5000):
        score += 5
        feedback_parts.append("PARTIAL(5): DXF has PUNTOS layer or large size but few POINT entities")
    else:
        feedback_parts.append("FAIL(0): DXF lacks POINT entities (survey points not exported)")

    # ── Criterion 4: TopoCal .top project file saved (25 pts) ──
    top_exists = bool(result.get("top_exists"))
    top_new    = top_exists and is_new(result.get("top_mod_time", ""))
    top_size   = int(result.get("top_size_bytes") or 0)

    if top_exists and top_new:
        score += 25
        feedback_parts.append(f"PASS(25): ClearCreek.top project file saved ({top_size} bytes)")
    elif top_exists:
        score += 10
        feedback_parts.append("PARTIAL(10): .top file exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): ClearCreek.top project file not found")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
