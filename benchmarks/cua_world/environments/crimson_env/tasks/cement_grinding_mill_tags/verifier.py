#!/usr/bin/env python3
"""Verifier for cement_grinding_mill_tags task.

A controls engineer configures 6 active cement grinding monitoring tags in 
Red Lion Crimson 3.0 per ISO 10816-3 and ASTM C150. The register also contains
2 inactive tags (VRM-2) that must be filtered out.

Scoring (100 points total):
  Subtask 1 — Active Tag Presence & Naming (24 pts):
      6 required tags: DP_601, TT_601, VB_601, FT_601, SS_601, BL_601. (4 pts each)
  Subtask 2 — Data Type = Float (18 pts): (3 pts each)
  Subtask 3 — Min/Max Engineering Ranges (36 pts): (6 pts each)
  Subtask 4 — Engineering Unit Label (22 pts): (~3-4 pts each)

Pass threshold: 70 / 100.

Anti-Pattern Audit:
  - Do-nothing -> Project missing -> GATE 1 -> score=0.
  - No Judgment -> Configures DP_602 or TT_602 -> GATE 2 -> score=0.
  - UI Automation Fallback -> If UI export fails, falls back to parsing binary
    strings from `.c3`. Cannot verify parameters, but anti-gaming and partial 
    presence scoring (S1) is maintained perfectly.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/cement_grinding_result.json"

EXPECTED_TAGS = [
    {"name": "DP_601", "data_type": "Float", "min_value": 0.0, "max_value": 120.0, "label": "Millibar"},
    {"name": "TT_601", "data_type": "Float", "min_value": 50.0, "max_value": 150.0, "label": "Degrees Celsius"},
    {"name": "VB_601", "data_type": "Float", "min_value": 0.0, "max_value": 30.0, "label": "Millimeters per Second"},
    {"name": "FT_601", "data_type": "Float", "min_value": 0.0, "max_value": 500.0, "label": "Metric Tons per Hour"},
    {"name": "SS_601", "data_type": "Float", "min_value": 0.0, "max_value": 2000.0, "label": "Revolutions per Minute"},
    {"name": "BL_601", "data_type": "Float", "min_value": 2000.0, "max_value": 6000.0, "label": "Square Centimeters per Gram"},
]

INACTIVE_TAGS = {"DP_602", "TT_602"}
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


def verify_cement_grinding_mill_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env unavailable."}

    # Extract JSON results from Container
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
        return {"passed": False, "score": 0, "feedback": "Result file not found – project not saved."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result JSON: {e}"}

    # GATE 1: Project saved
    if not result.get("project_found", False):
        return {"passed": False, "score": 0, "feedback": "Project not found – agent did not save the project."}

    # Determine tags present either via CSV Export or Binary Strings fallback
    export_success = result.get("export_success", False)
    binary_strings = [s.upper() for s in result.get("binary_strings", [])]
    
    if export_success:
        exported_tags = result.get("tags", [])
        tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported_tags}
        found_names = set(tag_map.keys())
    else:
        # Fallback to binary string analysis if UI script failed
        tag_map = {}
        found_names = set(binary_strings)

    # GATE 2: Wrong Mill (Did the agent blindly copy the offline VRM-2 tags?)
    found_inactive = INACTIVE_TAGS & found_names
    if found_inactive:
        return {
            "passed": False, 
            "score": 0,
            "feedback": f"WRONG MILL: Agent configured inactive VRM-2 tag(s) {sorted(found_inactive)}. "
                        "Agent failed to use judgment to exclude offline equipment."
        }

    # GATE 3: Wrong Target (Did they configure ANY of the correct tags?)
    required_upper = {e["name"].upper() for e in EXPECTED_TAGS}
    if not (required_upper & found_names):
        return {"passed": False, "score": 0, "feedback": "WRONG TARGET: No required VRM-1 tags found in project."}

    score = 0
    feedback_parts = []

    # S1: Presence & Naming (24 pts)
    s1_score = 0
    for e in EXPECTED_TAGS:
        if e["name"].upper() in found_names:
            s1_score += 4
    score += s1_score
    feedback_parts.append(f"S1-Presence({s1_score}/24)")

    # S2-S4: Parameter verification (Requires successful export)
    if export_success:
        # S2: Float Data Type (18 pts)
        s2_score = 0
        for e in EXPECTED_TAGS:
            nm = e["name"].upper()
            if nm in tag_map:
                t = _norm_str(tag_map[nm].get("data_type", ""))
                if any(x in t for x in ["float", "real", "single"]):
                    s2_score += 3
        score += s2_score
        feedback_parts.append(f"S2-Type({s2_score}/18)")

        # S3: Min/Max Ranges (36 pts)
        s3_score = 0
        for e in EXPECTED_TAGS:
            nm = e["name"].upper()
            if nm in tag_map:
                tag = tag_map[nm]
                if _within_tol(tag.get("min_value"), e["min_value"]): s3_score += 3
                if _within_tol(tag.get("max_value"), e["max_value"]): s3_score += 3
        score += s3_score
        feedback_parts.append(f"S3-Ranges({s3_score}/36)")

        # S4: Unit Label (22 pts)
        s4_score = 0
        for e in EXPECTED_TAGS:
            nm = e["name"].upper()
            if nm in tag_map:
                lbl = _norm_str(tag_map[nm].get("label", ""))
                expected_lbl = _norm_str(e["label"])
                # Permissive substring matching for units
                if expected_lbl in lbl or lbl in expected_lbl:
                    s4_score += 3.66 # Scaling to ~22 pts for 6 tags
        s4_score = min(22, round(s4_score))
        score += s4_score
        feedback_parts.append(f"S4-Labels({s4_score}/22)")
    else:
        feedback_parts.append("UI Export Failed. Parameters (S2-S4) could not be verified. Scored based on binary presence only.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }