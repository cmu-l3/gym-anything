#!/usr/bin/env python3
"""Verifier for oilgas_flow_measurement_tags task.

A SCADA automation engineer configures the 6 *active* W-201 wellsite measurement
tags in Red Lion Crimson 3.0 per AGA-3 flow measurement standards (2012),
API MPMS Ch 14.3, and OSHA H2S limits.  The tag register also lists 2 INACTIVE
W-202 tags (FT_202, PT_202) that must NOT be configured.

Scoring (100 points total):
  Subtask 1 — Active Tag Presence & Naming (24 pts):
      All 6 W-201 tags present: FT_201, PT_201, TT_201, DP_201, AT_201, FQ_201.
      4 pts per tag.
  Subtask 2 — Data Type = Float (18 pts):
      Each active tag uses Float.  3 pts per tag.
  Subtask 3 — Min/Max Engineering Ranges (36 pts):
      Each tag's min/max matches AGA-3/API spec within 2 %.
      6 pts per tag (3 per limit).
  Subtask 4 — Engineering Unit Label (22 pts):
      Each tag's Label matches the standards document.  ~3 pts per tag.

Pass threshold: 70 / 100.

Anti-Pattern Audit:
  Do-nothing → no project → project_found=false → GATE → score=0.  ✓
  Wrong-wellsite → FT_202 or PT_202 configured → GATE → score=0.  ✓
  Wrong-target → none of 6 required W-201 names found → score=0.  ✓
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/oilgas_flow_result.json"

EXPECTED_TAGS = [
    {"name": "FT_201", "data_type": "Float", "min_value": 0.0,   "max_value": 10.0,    "label": "Million Std Cubic Feet per Day"},
    {"name": "PT_201", "data_type": "Float", "min_value": 0.0,   "max_value": 1500.0,  "label": "Pounds per Sq Inch Absolute"},
    {"name": "TT_201", "data_type": "Float", "min_value": -40.0, "max_value": 200.0,   "label": "Degrees Fahrenheit"},
    {"name": "DP_201", "data_type": "Float", "min_value": 0.0,   "max_value": 250.0,   "label": "Inches Water Column"},
    {"name": "AT_201", "data_type": "Float", "min_value": 0.0,   "max_value": 100.0,   "label": "Parts per Million"},
    {"name": "FQ_201", "data_type": "Float", "min_value": 0.0,   "max_value": 999999.0,"label": "Thousand Standard Cubic Feet"},
]

TOLERANCE_PCT = 2.0


def _within_tol(actual, expected, tol=TOLERANCE_PCT):
    if actual is None or expected is None:
        return False
    try:
        a, e = float(actual), float(expected)
    except (TypeError, ValueError):
        return False
    if e == 0.0:
        return abs(a) < 1e-6
    return abs(a - e) / abs(e) * 100.0 <= tol


def _norm_type(s):
    return str(s or "").strip().lower()


def verify_oilgas_flow_measurement_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found – project was not saved or export failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # GATE 1: do-nothing invariant
    if not result.get("project_found"):
        return {"passed": False, "score": 0,
                "feedback": "Project not found – agent did not save the project"}
    if not result.get("export_success"):
        return {"passed": False, "score": 0,
                "feedback": "Export Tags failed – project may be empty"}

    exported = result.get("tags", [])
    if not exported:
        return {"passed": False, "score": 0,
                "feedback": "No tags found in export – agent configured nothing"}

    tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported}

    # GATE 2: wrong-wellsite — agent configured inactive W-202 tags
    INACTIVE_TAGS = {"FT_202", "PT_202"}
    found_inactive = INACTIVE_TAGS & set(tag_map.keys())
    if found_inactive:
        return {"passed": False, "score": 0,
                "feedback": ("WRONG WELLSITE: agent configured inactive W-202 tag(s) "
                             f"{sorted(found_inactive)} which must not be configured. "
                             "Only active W-201 tags should be configured.")}

    # GATE 3: wrong-target
    required_upper = {e["name"].upper() for e in EXPECTED_TAGS}
    if not (required_upper & set(tag_map.keys())):
        return {"passed": False, "score": 0,
                "feedback": (f"WRONG TARGET: none of {sorted(required_upper)} found; "
                             f"got {sorted(tag_map.keys())}")}

    score = 0
    parts = []

    # Subtask 1: presence (24 pts, 4/tag)
    s1 = sum(4 for e in EXPECTED_TAGS if e["name"].upper() in tag_map)
    score += s1
    missing = [e["name"] for e in EXPECTED_TAGS if e["name"].upper() not in tag_map]
    parts.append(f"S1-Tags({s1}/24){' missing:'+','.join(missing) if missing else ''}")

    # Subtask 2: Float data type (18 pts, 3/tag)
    s2 = 0
    s2_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm not in tag_map:
            continue
        t = _norm_type(tag_map[nm].get("data_type", ""))
        if "float" in t or "single" in t or "real" in t:
            s2 += 3
            s2_det.append(f"{e['name']}✓")
        else:
            s2_det.append(f"{e['name']}={t or '?'}")
    score += s2
    parts.append(f"S2-Float({s2}/18): {' '.join(s2_det)}")

    # Subtask 3: min/max ranges (36 pts, 6/tag = 3 per limit)
    s3 = 0
    s3_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm not in tag_map:
            continue
        row = tag_map[nm]
        min_ok = _within_tol(row.get("min_value"), e["min_value"])
        max_ok = _within_tol(row.get("max_value"), e["max_value"])
        pts = (3 if min_ok else 0) + (3 if max_ok else 0)
        s3 += pts
        min_detail = "ok" if min_ok else "{}!={}".format(row.get("min_value", "?"), e["min_value"])
        max_detail = "ok" if max_ok else "{}!={}".format(row.get("max_value", "?"), e["max_value"])
        s3_det.append("{}(min={},max={})".format(e["name"], min_detail, max_detail))
    score += s3
    parts.append(f"S3-MinMax({s3}/36): {' '.join(s3_det)}")

    # Subtask 4: engineering unit label (22 pts ~3-4/tag, distribute evenly)
    label_pts_each = 22 // len(EXPECTED_TAGS)  # 3 pts each, remainder ignored for simplicity
    s4 = 0
    s4_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm not in tag_map:
            continue
        row = tag_map[nm]
        lbl = str(row.get("label", "") or row.get("unit", "") or "").strip()
        if lbl.lower() == e["label"].lower():
            s4 += label_pts_each
            s4_det.append(f"{e['name']}✓")
        else:
            s4_det.append(f"{e['name']}='{lbl}'≠'{e['label']}'")
    # Clamp to 22 max
    s4 = min(s4, 22)
    score += s4
    parts.append(f"S4-Label({s4}/22): {' '.join(s4_det)}")

    # Clamp total
    score = min(score, 100)
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(parts),
    }
