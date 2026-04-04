#!/usr/bin/env python3
"""
Verifier for bone_composition_analysis_report task.

Scoring Breakdown (100 pts):
1. Project file saved & valid (10 pts)
2. Report file saved (10 pts)
3. Files created during task (Anti-gaming) (10 pts)
4. Project contains "Compact Bone" mask (threshold check) (20 pts)
5. Project contains "Spongial Bone" mask (threshold check) (20 pts)
6. Report contains valid numeric volumes (10 pts)
7. Report contains correct calculated ratio (20 pts)

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bone_composition_analysis(traj, env_info, task_info):
    """
    Verify the bone composition analysis task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON from container
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task results: {e}"
        }

    score = 0
    feedback_parts = []
    
    # Metadata for verification ranges
    metadata = task_info.get("metadata", {})
    compact_cfg = metadata.get("compact_bone_preset", {"min_hu_lower_bound": 600, "max_hu_lower_bound": 1900})
    spongial_cfg = metadata.get("spongial_bone_preset", {"min_hu_lower_bound": 140, "max_hu_upper_bound": 700})

    # 1. File Existence and Validity (20 pts)
    if result.get("project_exists") and result.get("project_valid"):
        score += 10
        feedback_parts.append("Project file saved correctly")
    else:
        feedback_parts.append("Project file missing or invalid")

    if result.get("report_exists"):
        score += 10
        feedback_parts.append("Report file saved")
    else:
        feedback_parts.append("Report file missing")

    # 2. Anti-gaming (10 pts)
    if result.get("file_timestamps_valid"):
        score += 10
        feedback_parts.append("Files created during task session")
    else:
        feedback_parts.append("Files appear to be stale (pre-existing)")

    # 3. Mask Validation (40 pts)
    masks = result.get("masks", [])
    has_compact = False
    has_spongial = False
    
    for m in masks:
        t_min = m.get("threshold_min", -9999)
        t_max = m.get("threshold_max", 9999)
        
        # Check Compact Bone (Adult) ~ 662 to 1988
        # Allow some flexibility if user tweaked slightly, but must be in "Bone" territory
        if t_min >= compact_cfg["min_hu_lower_bound"] and t_max >= compact_cfg["max_hu_lower_bound"]:
            has_compact = True
            
        # Check Spongial Bone (Adult) ~ 148 to 661
        # It's softer bone, so lower range
        if t_min >= spongial_cfg["min_hu_lower_bound"] and t_max <= spongial_cfg["max_hu_upper_bound"]:
            has_spongial = True

    if has_compact:
        score += 20
        feedback_parts.append("Compact Bone mask verified")
    else:
        feedback_parts.append("Compact Bone mask missing or thresholds incorrect (expect min>600, max>1900)")

    if has_spongial:
        score += 20
        feedback_parts.append("Spongial Bone mask verified")
    else:
        feedback_parts.append("Spongial Bone mask missing or thresholds incorrect (expect min>140, max<700)")

    # 4. Report Content Validation (30 pts)
    extracted = result.get("extracted_volumes", {})
    vol_c = extracted.get("compact")
    vol_s = extracted.get("spongial")
    ratio = extracted.get("ratio")
    
    data_valid = False
    if vol_c is not None and vol_s is not None and vol_c > 10 and vol_s > 10:
        score += 10
        data_valid = True
        feedback_parts.append(f"Report contains valid volumes (C:{vol_c}, S:{vol_s})")
    else:
        feedback_parts.append("Report missing valid volume numbers")

    if data_valid and ratio is not None:
        # Check math: Ratio = Compact / Spongial
        # Allow 5% tolerance for rounding in report
        expected_ratio = vol_c / vol_s
        if abs(ratio - expected_ratio) / expected_ratio < 0.05:
            score += 20
            feedback_parts.append(f"Ratio calculation correct ({ratio})")
        else:
            feedback_parts.append(f"Ratio calculation incorrect (Reported: {ratio}, Expected: {expected_ratio:.2f})")
    elif data_valid:
        feedback_parts.append("Ratio missing from report")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }