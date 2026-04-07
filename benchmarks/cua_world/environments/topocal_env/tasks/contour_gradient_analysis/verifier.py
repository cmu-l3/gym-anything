#!/usr/bin/env python3
"""
Verifier for contour_gradient_analysis task.

Scoring (total 100 pts, pass threshold 60):
  30 pts — contour_map.dxf exists AND was created after task start
  20 pts — DXF contains at least 10 LWPOLYLINE entities (actual contour lines)
  25 pts — slope_analysis.txt exists and is newer than task start
  25 pts — slope_analysis.txt mentions gradient/slope with a numeric value
"""

import json
import re
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


def verify_contour_gradient_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = (
        task_info.get("metadata", {}).get("result_file")
        or "C:\\Users\\Docker\\contour_gradient_analysis_result.json"
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
                "feedback": f"Result JSON is invalid: {exc}"}
    finally:
        os.unlink(tmp.name)

    start_dt = _parse_dt(result.get("start_time", ""))

    def is_new(mod_time_str):
        """Return True if mod_time is after task start."""
        mod_dt = _parse_dt(mod_time_str)
        if not mod_dt or not start_dt:
            return False
        if mod_dt.tzinfo is None:
            mod_dt = mod_dt.replace(tzinfo=timezone.utc)
        if start_dt.tzinfo is None:
            s = start_dt.replace(tzinfo=timezone.utc)
        else:
            s = start_dt
        return mod_dt > s

    # ── Criterion 1: DXF exists and is new (30 pts) ──
    dxf_exists  = bool(result.get("dxf_exists"))
    dxf_new     = dxf_exists and is_new(result.get("dxf_mod_time", ""))
    dxf_size    = int(result.get("dxf_size_bytes") or 0)

    if dxf_exists and dxf_new:
        score += 30
        feedback_parts.append("PASS(30): contour_map.dxf exists and is newer than task start")
    elif dxf_exists:
        score += 12
        feedback_parts.append("PARTIAL(12): contour_map.dxf exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): contour_map.dxf not found")

    # ── Criterion 2: DXF has LWPOLYLINE entities — real contour lines (20 pts) ──
    lwpoly_count = int(result.get("dxf_lwpoly_count") or 0)
    if lwpoly_count >= 20:
        score += 20
        feedback_parts.append(f"PASS(20): DXF has {lwpoly_count} LWPOLYLINE entities")
    elif lwpoly_count >= 5:
        score += 10
        feedback_parts.append(f"PARTIAL(10): DXF has only {lwpoly_count} LWPOLYLINE entities (need >= 20)")
    elif dxf_exists and dxf_size > 1000:
        # DXF may use POLYLINE instead of LWPOLYLINE (older format)
        score += 5
        feedback_parts.append(f"PARTIAL(5): DXF exists ({dxf_size} bytes) but few/no LWPOLYLINE entities")
    else:
        feedback_parts.append(f"FAIL(0): DXF has {lwpoly_count} LWPOLYLINE entities")

    # ── Criterion 3: slope_analysis.txt exists and is new (25 pts) ──
    rep_exists = bool(result.get("report_exists"))
    rep_new    = rep_exists and is_new(result.get("report_mod_time", ""))
    rep_lines  = int(result.get("report_lines") or 0)

    if rep_exists and rep_new:
        score += 25
        feedback_parts.append(f"PASS(25): slope_analysis.txt exists, new, {rep_lines} lines")
    elif rep_exists:
        score += 10
        feedback_parts.append("PARTIAL(10): slope_analysis.txt exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): slope_analysis.txt not found")

    # ── Criterion 4: report has numeric gradient/slope content (25 pts) ──
    raw = result.get("report_content", "") or ""
    content = raw.replace("\\n", "\n").replace("\\t", "\t")
    content_lower = content.lower()

    slope_keywords = ["slope", "gradient", "pendiente", "inclinacion", "inclinación",
                      "%", "steep", "empinado", "suave", "grade"]
    has_slope_keyword = any(kw in content_lower for kw in slope_keywords)
    has_number = bool(re.search(r"\d+(?:[.,]\d+)?", content))

    if has_slope_keyword and has_number:
        score += 25
        feedback_parts.append("PASS(25): slope_analysis.txt mentions slope/gradient with numeric values")
    elif has_slope_keyword or has_number:
        score += 10
        feedback_parts.append("PARTIAL(10): slope_analysis.txt has slope keyword OR numbers but not both")
    elif rep_exists and rep_lines >= 3:
        score += 5
        feedback_parts.append("PARTIAL(5): slope_analysis.txt has content but lacks slope analysis")
    else:
        feedback_parts.append("FAIL(0): slope_analysis.txt empty or lacks slope/gradient content")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
