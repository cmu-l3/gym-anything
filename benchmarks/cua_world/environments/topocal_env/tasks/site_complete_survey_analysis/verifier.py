#!/usr/bin/env python3
"""
Verifier for site_complete_survey_analysis task.

Scoring (total 100 pts, pass threshold 60):

  Deliverable A — DXF export:
    20 pts — SiteAnalysis_ElPaso.dxf exists AND is new
    15 pts — DXF has LWPOLYLINE entities (contour lines present)

  Deliverable D — Written analysis report:
    30 pts — SiteAnalysis.txt exists, is new, and has >= 8 lines
    35 pts — report contains elevation statistics AND volume references
              (partial credit available for each sub-element)
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


def verify_site_complete_survey_analysis(traj, env_info, task_info):
    score = 0
    feedback_parts = []

    result_path = (
        task_info.get("metadata", {}).get("result_file")
        or "C:\\Users\\Docker\\site_complete_survey_analysis_result.json"
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

    # ══ Deliverable A: DXF export ══

    # ── A1: DXF exists and is new (20 pts) ──
    dxf_exists = bool(result.get("dxf_exists"))
    dxf_new    = dxf_exists and is_new(result.get("dxf_mod_time", ""))
    dxf_size   = int(result.get("dxf_size_bytes") or 0)

    if dxf_exists and dxf_new:
        score += 20
        feedback_parts.append("PASS(20): SiteAnalysis_ElPaso.dxf exists and is newer than task start")
    elif dxf_exists:
        score += 8
        feedback_parts.append("PARTIAL(8): DXF exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): SiteAnalysis_ElPaso.dxf not found")

    # ── A2: DXF has contour lines (15 pts) ──
    lw_count  = int(result.get("dxf_lwpoly_count") or 0)
    has_curvas = bool(result.get("dxf_has_curvas"))

    if lw_count >= 10:
        score += 15
        feedback_parts.append(f"PASS(15): DXF has {lw_count} LWPOLYLINE contour entities")
    elif lw_count >= 3:
        score += 8
        feedback_parts.append(f"PARTIAL(8): DXF has only {lw_count} LWPOLYLINE entities")
    elif has_curvas or (dxf_exists and dxf_size > 1000):
        score += 4
        feedback_parts.append("PARTIAL(4): DXF has CURVAS reference but few contour entities")
    else:
        feedback_parts.append("FAIL(0): DXF lacks contour line entities")

    # ══ Deliverable D: Written analysis report ══

    rep_exists = bool(result.get("report_exists"))
    rep_new    = rep_exists and is_new(result.get("report_mod_time", ""))
    rep_lines  = int(result.get("report_lines") or 0)

    raw_content = result.get("report_content", "") or ""
    content = raw_content.replace("\\n", "\n").replace("\\t", "\t")
    content_lower = content.lower()

    # ── D1: Report exists, is new, has content (30 pts) ──
    if rep_exists and rep_new and rep_lines >= 8:
        score += 30
        feedback_parts.append(f"PASS(30): SiteAnalysis.txt exists, new, {rep_lines} lines")
    elif rep_exists and rep_new and rep_lines >= 4:
        score += 18
        feedback_parts.append(f"PARTIAL(18): SiteAnalysis.txt is new but only {rep_lines} lines")
    elif rep_exists and rep_new:
        score += 10
        feedback_parts.append(f"PARTIAL(10): SiteAnalysis.txt is new but almost empty ({rep_lines} lines)")
    elif rep_exists:
        score += 8
        feedback_parts.append("PARTIAL(8): SiteAnalysis.txt exists but may predate task start")
    else:
        feedback_parts.append("FAIL(0): SiteAnalysis.txt not found")

    # ── D2: Report contains elevation statistics and volume data (35 pts) ──
    # Sub-criterion: elevation stats (17 pts max)
    elev_keywords = ["elevation", "elevacion", "elevación", "altura", "altitud",
                     "min", "max", "mean", "media", "promedio"]
    has_elev_keyword = any(kw in content_lower for kw in elev_keywords)
    has_numbers = len(re.findall(r"\b\d{3,4}(?:[.,]\d+)?\b", content)) >= 3  # >=3 four-digit numbers (elevations)

    # Sub-criterion: volume data (18 pts max)
    vol_keywords = ["volume", "volumen", "cut", "corte", "fill", "relleno",
                    "m3", "m³", "cubic", "cubico", "cúbico"]
    has_vol_keyword = any(kw in content_lower for kw in vol_keywords)

    if has_elev_keyword and has_numbers and has_vol_keyword:
        score += 35
        feedback_parts.append("PASS(35): report has elevation statistics AND volume data")
    elif has_elev_keyword and has_numbers:
        score += 20
        feedback_parts.append("PARTIAL(20): report has elevation stats but no volume analysis")
    elif has_vol_keyword and has_numbers:
        score += 18
        feedback_parts.append("PARTIAL(18): report has volume data but elevation stats incomplete")
    elif has_numbers:
        score += 10
        feedback_parts.append("PARTIAL(10): report has numeric values but incomplete analysis")
    elif rep_exists and rep_lines >= 5:
        score += 5
        feedback_parts.append("PARTIAL(5): report has content but lacks numerical analysis")
    else:
        feedback_parts.append("FAIL(0): report lacks elevation/volume numerical content")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
