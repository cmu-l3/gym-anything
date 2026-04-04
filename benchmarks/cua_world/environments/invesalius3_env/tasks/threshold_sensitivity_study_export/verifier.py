#!/usr/bin/env python3
"""
Verifier for threshold_sensitivity_study_export task.

Scoring (100 points total):
1. Files Existence & Validity (45 pts):
   - Each valid binary STL file = 15 points (3 * 15 = 45)
   
2. Geometric Sensitivity Logic (40 pts):
   - Lower threshold means MORE tissue included (bone + noise/soft tissue)
   - Higher threshold means LESS tissue (dense bone only)
   - Therefore, Triangle Count (200HU) > Triangle Count (400HU) > Triangle Count (600HU)
   - Checks:
     - 200HU > 400HU: 20 pts
     - 400HU > 600HU: 20 pts

3. Anti-Gaming (15 pts):
   - Files created during task session: 5 pts
   - Files are distinct (not copies): 10 pts

Pass Threshold: 85 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_threshold_sensitivity(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    # Retrieve result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/threshold_study_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not read result file: {e}"
        }

    score = 0
    feedback_parts = []
    
    files = result.get("files", {})
    f200 = files.get("200HU", {})
    f400 = files.get("400HU", {})
    f600 = files.get("600HU", {})
    
    # 1. Existence and Validity Check
    valid_count = 0
    for label, info in [("200HU", f200), ("400HU", f400), ("600HU", f600)]:
        if info.get("exists") and info.get("is_binary_stl") and info.get("triangle_count", 0) > 1000:
            valid_count += 1
            score += 15
        else:
            if not info.get("exists"):
                feedback_parts.append(f"Missing {label}")
            elif not info.get("is_binary_stl"):
                feedback_parts.append(f"Invalid STL format for {label}")
            else:
                feedback_parts.append(f"Empty/Trivial mesh for {label}")
                
    if valid_count == 3:
        feedback_parts.append("All 3 files exist and are valid STLs")

    # 2. Geometric Logic Check
    # Lower threshold = More volume = More triangles
    tc200 = f200.get("triangle_count", 0)
    tc400 = f400.get("triangle_count", 0)
    tc600 = f600.get("triangle_count", 0)
    
    # Check 200 vs 400
    # We require a significant difference (>1000 triangles) to ensure they aren't just renamed copies
    if valid_count >= 2 and tc200 > (tc400 + 1000):
        score += 20
        feedback_parts.append("Correct sensitivity: 200HU model larger than 400HU")
    elif valid_count >= 2:
        feedback_parts.append(f"Sensitivity logic failed: 200HU ({tc200}) not significantly > 400HU ({tc400})")
        
    # Check 400 vs 600
    if valid_count >= 3 and tc400 > (tc600 + 1000):
        score += 20
        feedback_parts.append("Correct sensitivity: 400HU model larger than 600HU")
    elif valid_count >= 3:
        feedback_parts.append(f"Sensitivity logic failed: 400HU ({tc400}) not significantly > 600HU ({tc600})")

    # 3. Anti-Gaming
    # Check distinctness explicitly (in case they copied the file but the counts were close enough to fail logic but pass existence)
    if tc200 == tc400 or tc400 == tc600 or tc200 == tc600:
        feedback_parts.append("Warning: Identical files detected (gaming attempt?)")
    else:
        score += 10
        
    # Check timestamps
    if result.get("timestamp_check_passed", False):
        score += 5
    else:
        feedback_parts.append("File modification times pre-date task start")

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "triangles_200": tc200,
            "triangles_400": tc400,
            "triangles_600": tc600
        }
    }