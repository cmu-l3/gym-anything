#!/usr/bin/env python3
"""
Verifier for probe_hu_density_report task.

Verifies that the agent probed plausible Hounsfield Units (HU) for:
1. Cortical Bone (High density, >150 HU)
2. Air (Low density, <-100 HU)
3. Soft Tissue (Medium density, -10 to 120 HU)

Anti-gaming:
- Checks file modification time
- Ensures values are mutually distinct (prevents copying same number)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_probe_hu_density_report(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # Load metadata ranges
    metadata = task_info.get("metadata", {})
    ranges = metadata.get("ranges", {
        "cortical_bone": {"min": 150, "max": 3071},
        "air": {"min": -1050, "max": -100},
        "soft_tissue": {"min": -10, "max": 120}
    })

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON from container
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
            "feedback": f"Could not retrieve task result: {e}"
        }

    # 1. File Existence & Creation Time (20 pts)
    if not result.get("file_exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Report file /home/ga/Documents/hu_density_report.txt not found."
        }
    
    score += 10
    feedback_parts.append("File exists")

    if result.get("file_created_during_task"):
        score += 10
        feedback_parts.append("Created during task")
    else:
        feedback_parts.append("WARNING: File timestamp suggests it was pre-existing")

    # 2. Content Parsing (20 pts)
    values = result.get("parsed_values", {})
    required_keys = ["cortical_bone", "air", "soft_tissue"]
    
    missing_keys = [k for k in required_keys if k not in values]
    
    if not missing_keys:
        score += 20
        feedback_parts.append("All format labels found")
    else:
        score += int(20 * (len(values) / 3))
        feedback_parts.append(f"Missing labels: {', '.join(missing_keys)}")

    # 3. Value Range Verification (50 pts total)
    # 15 pts for Bone, 15 for Air, 20 for Soft Tissue
    
    # Bone Check
    bone_val = values.get("cortical_bone")
    if bone_val is not None:
        rmin, rmax = ranges["cortical_bone"]["min"], ranges["cortical_bone"]["max"]
        if rmin <= bone_val <= rmax:
            score += 15
            feedback_parts.append(f"Bone HU valid ({bone_val})")
        else:
            feedback_parts.append(f"Bone HU {bone_val} out of range [{rmin}, {rmax}]")
    
    # Air Check
    air_val = values.get("air")
    if air_val is not None:
        rmin, rmax = ranges["air"]["min"], ranges["air"]["max"]
        if rmin <= air_val <= rmax:
            score += 15
            feedback_parts.append(f"Air HU valid ({air_val})")
        else:
            feedback_parts.append(f"Air HU {air_val} out of range [{rmin}, {rmax}]")

    # Soft Tissue Check
    soft_val = values.get("soft_tissue")
    if soft_val is not None:
        rmin, rmax = ranges["soft_tissue"]["min"], ranges["soft_tissue"]["max"]
        if rmin <= soft_val <= rmax:
            score += 20
            feedback_parts.append(f"Soft Tissue HU valid ({soft_val})")
        else:
            feedback_parts.append(f"Soft Tissue HU {soft_val} out of range [{rmin}, {rmax}]")

    # 4. Anti-Gaming: Distinct Values (10 pts)
    # Prevents agent from guessing one safe number (e.g. 0) for all fields
    valid_vals = [v for v in [bone_val, air_val, soft_val] if v is not None]
    if len(valid_vals) >= 2:
        # Check if values are distinct (difference > 5 HU)
        is_distinct = True
        sorted_vals = sorted(valid_vals)
        for i in range(len(sorted_vals) - 1):
            if abs(sorted_vals[i] - sorted_vals[i+1]) < 5:
                is_distinct = False
                break
        
        if is_distinct:
            score += 10
            feedback_parts.append("Values distinct")
        else:
            feedback_parts.append("Values too similar (anti-gaming check failed)")
    elif len(valid_vals) < 2:
        # Not enough values to compare
        pass

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "parsed": values,
            "ranges": ranges
        }
    }