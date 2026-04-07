#!/usr/bin/env python3
"""Verifier for food_pasteurization_tags task.

A food safety engineer configures 5 CCP monitoring tags for an HTST pasteurization
line in Red Lion Crimson 3.0, following FDA Grade A Pasteurized Milk Ordinance (PMO)
2023 and 21 CFR Part 131.

Scoring (100 points total):
  Subtask 1 — Tag Presence & Naming (25 pts):
      All 5 required tags exist: TT_501, FT_501, PT_501, TT_502, FQ_501.
      5 pts per tag.
  Subtask 2 — Data Type = Float (20 pts):
      Each tag uses Float data type.  4 pts per tag.
  Subtask 3 — Min/Max Engineering Ranges (30 pts):
      Each tag's min/max matches the FDA PMO specification within 2 %.
      6 pts per tag (3 per limit).
  Subtask 4 — Engineering Unit Label (25 pts):
      Each tag's Label matches the PMO document.
      5 pts per tag.

Pass threshold: 70 / 100.

Anti-Pattern 4 Audit:
  Do-nothing → no project → project_found=false → GATE → score=0.  ✓
  Wrong-target → none of required names found → score=0.  ✓

Note on CCP criticality: TT_501 Alarm 1 threshold 161.0°F is the FDA PMO critical
limit. The verifier treats it like any other alarm value (within 2 % tolerance),
but this threshold has regulatory significance in the real-world scenario.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/food_pasteurization_result.json"

EXPECTED_TAGS = [
    {"name": "TT_501", "data_type": "Float", "min_value": 140.0, "max_value": 200.0,    "label": "Degrees Fahrenheit"},
    {"name": "FT_501", "data_type": "Float", "min_value": 0.0,   "max_value": 500.0,    "label": "Gallons per Minute"},
    {"name": "PT_501", "data_type": "Float", "min_value": 0.0,   "max_value": 100.0,    "label": "Pounds per Square Inch"},
    {"name": "TT_502", "data_type": "Float", "min_value": 100.0, "max_value": 200.0,    "label": "Degrees Fahrenheit"},
    {"name": "FQ_501", "data_type": "Float", "min_value": 0.0,   "max_value": 999999.0, "label": "Gallons"},
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


def verify_food_pasteurization_tags(traj, env_info, task_info):
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

    required_upper = {e["name"].upper() for e in EXPECTED_TAGS}
    if not (required_upper & set(tag_map.keys())):
        return {"passed": False, "score": 0,
                "feedback": (f"WRONG TARGET: none of {sorted(required_upper)} found; "
                             f"got {sorted(tag_map.keys())}")}

    score = 0
    parts = []

    # Subtask 1: Tag presence (25 pts, 5/tag)
    s1 = 0
    s1_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            s1 += 5
            s1_det.append(f"{e['name']}✓")
        else:
            s1_det.append(f"{e['name']}✗")
    score += s1
    parts.append(f"S1-Tags({s1}/25): {' '.join(s1_det)}")

    # Subtask 2: Float type (20 pts, 4/tag)
    s2 = 0
    s2_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm not in tag_map:
            continue
        t = _norm_type(tag_map[nm].get("data_type", ""))
        if "float" in t or "single" in t or "real" in t:
            s2 += 4
            s2_det.append(f"{e['name']}✓")
        else:
            s2_det.append(f"{e['name']}={t or '?'}")
    score += s2
    parts.append(f"S2-Float({s2}/20): {' '.join(s2_det)}")

    # Subtask 3: Min/Max ranges (30 pts, 6/tag)
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
    parts.append(f"S3-MinMax({s3}/30): {' '.join(s3_det)}")

    # Subtask 4: Engineering unit label (25 pts, 5/tag)
    s4 = 0
    s4_det = []
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm not in tag_map:
            continue
        row = tag_map[nm]
        lbl = str(row.get("label", "") or row.get("unit", "") or "").strip()
        if lbl.lower() == e["label"].lower():
            s4 += 5
            s4_det.append(f"{e['name']}✓")
        else:
            s4_det.append(f"{e['name']}='{lbl}'≠'{e['label']}'")
    score += s4
    parts.append(f"S4-Label({s4}/25): {' '.join(s4_det)}")

    score = min(score, 100)
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(parts),
    }
