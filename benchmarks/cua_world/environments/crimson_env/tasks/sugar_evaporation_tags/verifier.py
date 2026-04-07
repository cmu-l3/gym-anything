#!/usr/bin/env python3
"""Verifier for sugar_evaporation_tags task.

An instrumentation engineer configures 6 active Evaporation Train-A SCADA tags in
Red Lion Crimson 3.0 per ICUMSA/BMA standards. The tag register also contains 3
inactive Train-B tags that must be ignored. Furthermore, the agent must resolve
two intentional specification conflicts by relying on the authoritative standards doc.

Scoring (100 points total):
  Subtask 1 — Active Tag Presence & Naming (24 pts): 4 pts per Train-A tag.
  Subtask 2 — Data Type = Float (18 pts): 3 pts per Train-A tag.
  Subtask 3 — Min/Max/Alarm Engineering Ranges (36 pts):
      Each tag's numeric parameters match the standards document within 2%.
      Robustly checks if the 4 expected numbers are present in the tag's row.
      1.5 pts per correct limit number found (4 numbers * 1.5 = 6 pts/tag).
  Subtask 4 — Engineering Unit Label (22 pts):
      Each tag's Label matches the text in the standards document.

Pass threshold: 70 / 100.

Anti-Pattern Audit:
  Do-nothing -> no project -> project_found=false -> score=0.
  Not created during session -> file_created_during_task=false -> score=0.
  Wrong-train -> TT_602, BX_602, VP_602 configured -> score=0.
  Wrong-target -> none of required Train-A names found -> score=0.
  No conflict resolution -> Using CSV values instead of standards -> loses S3 points.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/sugar_evaporation_result.json"

EXPECTED_TAGS = [
    {"name": "TT_601", "nums": [80.0, 130.0, 95.0, 120.0], "label": "Degrees Celsius"},
    {"name": "BX_601", "nums": [0.0, 80.0, 60.0, 72.0], "label": "Degrees Brix"},
    {"name": "VP_601", "nums": [-101.3, 0.0, -95.0, -50.0], "label": "Kilopascals Gauge"},
    {"name": "FT_601", "nums": [0.0, 500.0, 50.0, 400.0], "label": "Cubic Meters per Hour"},
    {"name": "PH_601", "nums": [0.0, 14.0, 6.80, 7.50], "label": "pH Units"},
    {"name": "LT_601", "nums": [0.0, 100.0, 25.0, 85.0], "label": "Percent Level"}
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


def verify_sugar_evaporation_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_path = tmp.name
    tmp.close()
    
    try:
        copy_from_env(RESULT_PATH, tmp_path)
        with open(tmp_path, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        if os.path.exists(tmp_path): os.unlink(tmp_path)
        return {"passed": False, "score": 0, "feedback": "Result file not found – project was not saved or export script failed"}
    finally:
        if os.path.exists(tmp_path): os.unlink(tmp_path)

    # GATE 1: Anti-gaming / Do-nothing
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project not found – agent did not save the project"}
    if not result.get("file_created_during_task", True):
        return {"passed": False, "score": 0, "feedback": "Project file exists but was not created/modified during this task session."}
    if not result.get("export_success"):
        return {"passed": False, "score": 0, "feedback": "Export Tags failed – project may be empty or corrupted"}

    exported = result.get("tags", [])
    if not exported:
        return {"passed": False, "score": 0, "feedback": "No tags found in export – agent configured nothing"}

    tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported}

    # GATE 2: Wrong-Train
    INACTIVE_TAGS = {"TT_602", "BX_602", "VP_602"}
    found_inactive = INACTIVE_TAGS & set(tag_map.keys())
    if found_inactive:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"WRONG TRAIN: agent configured inactive Train-B tag(s) {sorted(found_inactive)}. Only active Train-A tags should be configured."
        }

    # GATE 3: Wrong-Target
    required_upper = {e["name"].upper() for e in EXPECTED_TAGS}
    if not (required_upper & set(tag_map.keys())):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"WRONG TARGET: None of the required Train-A tags found. Found: {list(tag_map.keys())}"
        }

    score = 0
    parts = []

    # Subtask 1: Tag presence (24 pts)
    s1 = sum(4 for e in EXPECTED_TAGS if e["name"].upper() in tag_map)
    score += s1
    parts.append(f"S1-Presence({s1}/24)")

    # Subtask 2: Float type (18 pts)
    s2 = 0
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            raw = str(tag_map[nm].get("raw_line", "")).lower()
            dt = str(tag_map[nm].get("data_type", "")).lower()
            if "float" in raw or "real" in raw or "float" in dt or "single" in dt:
                s2 += 3
    score += s2
    parts.append(f"S2-Float({s2}/18)")

    # Subtask 3: Min/Max/Alarms (36 pts)
    # Robust numeric check against all numbers extracted from the tag's row
    s3 = 0
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            actual_nums = tag_map[nm].get("all_numbers", [])
            expected_nums = e["nums"]
            tag_s3 = 0
            for en in expected_nums:
                found = False
                for an in actual_nums:
                    if _within_tol(an, en):
                        found = True
                        break
                if found:
                    tag_s3 += 1.5
            s3 += tag_s3
    
    score += int(s3)
    parts.append(f"S3-Ranges({int(s3)}/36)")

    # Subtask 4: Labels (22 pts)
    s4_count = 0
    for e in EXPECTED_TAGS:
        nm = e["name"].upper()
        if nm in tag_map:
            raw = str(tag_map[nm].get("raw_line", "")).lower()
            expected_label = e["label"].lower().replace(" ", "")
            raw_nospace = raw.replace(" ", "")
            if expected_label in raw_nospace or e["label"].lower() in raw:
                s4_count += 1
    
    s4 = int(round((s4_count / 6.0) * 22))
    score += s4
    parts.append(f"S4-Labels({s4}/22)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }