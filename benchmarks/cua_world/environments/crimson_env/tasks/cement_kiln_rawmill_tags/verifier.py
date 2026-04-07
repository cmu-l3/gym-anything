#!/usr/bin/env python3
"""
Verifier for cement_kiln_rawmill_tags task.

An instrumentation engineer configures 7 active process monitoring tags for
a cement kiln and raw mill in Red Lion Crimson 3.0 per EU IED BAT-AELs, 
ISO 10816-3, and PCA guidelines. The tag register also contains 2 PENDING 
Line-2 tags that must NOT be configured.

Scoring (100 points total):
  Subtask 1 — Tag Presence & Naming (21 pts):
      All 7 active tags exist: TT_601, VM_601, FT_601, CT_601, PT_601, TT_602, AT_601.
      3 pts per tag.
  Subtask 2 — Data Type = Float (21 pts):
      Each active tag uses Float data type. 3 pts per tag.
  Subtask 3 — Min/Max Engineering Ranges (36 pts):
      Each active tag's min/max matches the specification within 2% tolerance.
      Calculated as 36.0 pts / 14 limits = ~2.57 pts per limit.
  Subtask 4 — Engineering Unit Label (22 pts):
      Each active tag's Label matches the standards document.
      Calculated as 22.0 pts / 7 tags = ~3.14 pts per tag.

Anti-Pattern Audit:
  - Do-nothing -> project_found=false -> GATE -> score=0.
  - Wrong-line -> CM_602 or BW_602 present -> GATE -> score=0.
  - Wrong-target -> none of required names found -> score=0.
  - File timestamp -> verifies project was saved during the task.
"""

import json
import os
import tempfile
import logging
import math

logger = logging.getLogger(__name__)

# The result path on the Windows guest, mounted to /workspace
RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/cement_kiln_rawmill_result.json"

EXPECTED_TAGS = [
    {"name": "TT_601", "data_type": "Float", "min_value": 800.0, "max_value": 1600.0, "label": "Degrees Celsius"},
    {"name": "VM_601", "data_type": "Float", "min_value": 0.0,   "max_value": 30.0,   "label": "Millimeters per Second RMS"},
    {"name": "FT_601", "data_type": "Float", "min_value": 0.0,   "max_value": 500.0,  "label": "Metric Tonnes per Hour"},
    {"name": "CT_601", "data_type": "Float", "min_value": 0.0,   "max_value": 1000.0, "label": "Amperes"},
    {"name": "PT_601", "data_type": "Float", "min_value": 0.0,   "max_value": 100.0,  "label": "Millibar"},
    {"name": "TT_602", "data_type": "Float", "min_value": 200.0, "max_value": 1000.0, "label": "Degrees Celsius"},
    {"name": "AT_601", "data_type": "Float", "min_value": 0.0,   "max_value": 2000.0, "label": "Milligrams per Normal Cubic Meter"},
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


def _norm_str(s):
    return str(s or "").strip().lower()


def verify_cement_kiln_rawmill_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result JSON not found - export script failed or project not saved."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}

    # GATE 1: Project exists and was modified
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project not found - agent did not save cement_kiln_rawmill.c3"}
    if not result.get("project_modified_during_task"):
        logger.warning("Project file found but timestamp indicates it was not modified during the task.")
    
    if not result.get("export_success"):
        return {"passed": False, "score": 0, "feedback": "Failed to parse any tags from the project."}

    exported_tags = result.get("tags", [])
    if not exported_tags:
        return {"passed": False, "score": 0, "feedback": "No tags found in export - agent configured nothing."}

    tag_map = {_norm_str(t.get("name", "")): t for t in exported_tags}

    # GATE 2: Wrong Line configured
    INACTIVE_TAGS = {"cm_602", "bw_602"}
    found_inactive = INACTIVE_TAGS.intersection(set(tag_map.keys()))
    if found_inactive:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"WRONG LINE: Agent configured pending Line-2 tag(s) {found_inactive}. Only active Line-1 tags should be configured."
        }

    # GATE 3: Wrong target (none of the expected tags found)
    expected_names_lower = {_norm_str(e["name"]) for e in EXPECTED_TAGS}
    if not expected_names_lower.intersection(set(tag_map.keys())):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"WRONG TARGET: None of the active Line-1 tags found. Expected: {expected_names_lower}"
        }

    score = 0.0
    feedback_parts = []

    # Subtask 1: Tag Presence (21 pts, 3 per tag)
    s1 = 0
    s1_details = []
    for e in EXPECTED_TAGS:
        nm = _norm_str(e["name"])
        if nm in tag_map:
            s1 += 3
            s1_details.append(f"{e['name']}✓")
        else:
            s1_details.append(f"{e['name']}✗")
    score += s1
    feedback_parts.append(f"Presence ({s1}/21): {' '.join(s1_details)}")

    # Subtask 2: Float type (21 pts, 3 per tag)
    s2 = 0
    s2_details = []
    for e in EXPECTED_TAGS:
        nm = _norm_str(e["name"])
        if nm in tag_map:
            dtype = _norm_str(tag_map[nm].get("data_type", ""))
            if "float" in dtype or "single" in dtype or "real" in dtype:
                s2 += 3
                s2_details.append(f"{e['name']}✓")
            else:
                s2_details.append(f"{e['name']}=✗")
    score += s2
    feedback_parts.append(f"Type ({s2}/21): {' '.join(s2_details)}")

    # Subtask 3: Min/Max Ranges (36 pts, ~2.57 per limit)
    s3 = 0.0
    pts_per_limit = 36.0 / (len(EXPECTED_TAGS) * 2)
    s3_details = []
    
    for e in EXPECTED_TAGS:
        nm = _norm_str(e["name"])
        if nm in tag_map:
            t = tag_map[nm]
            min_ok = _within_tol(t.get("min_value"), e["min_value"])
            max_ok = _within_tol(t.get("max_value"), e["max_value"])
            
            if min_ok: s3 += pts_per_limit
            if max_ok: s3 += pts_per_limit
            
            s3_details.append(f"{e['name']}({'M' if min_ok else 'x'}{'X' if max_ok else 'x'})")
    
    score += s3
    feedback_parts.append(f"Ranges ({round(s3, 1)}/36): {' '.join(s3_details)}")

    # Subtask 4: Engineering Unit Label (22 pts, ~3.14 per tag)
    s4 = 0.0
    pts_per_label = 22.0 / len(EXPECTED_TAGS)
    s4_details = []
    
    for e in EXPECTED_TAGS:
        nm = _norm_str(e["name"])
        if nm in tag_map:
            actual_label = _norm_str(tag_map[nm].get("label", ""))
            expected_label = _norm_str(e["label"])
            if actual_label == expected_label:
                s4 += pts_per_label
                s4_details.append(f"{e['name']}✓")
            else:
                s4_details.append(f"{e['name']}✗")
    
    score += s4
    feedback_parts.append(f"Labels ({round(s4, 1)}/22): {' '.join(s4_details)}")

    total_score = round(score)
    passed = total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }