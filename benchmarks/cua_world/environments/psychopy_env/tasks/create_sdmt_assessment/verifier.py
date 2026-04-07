#!/usr/bin/env python3
"""
Verifier for create_sdmt_assessment task.

Verification Strategy:
1. CSV Integrity (20 pts): Correct columns, 9 specific symbol-digit mappings.
2. Experiment Structure (30 pts): Instructions + Trial routines, Loop random + high nReps.
3. Visual Layout (20 pts): Static Key shown, Dynamic Probe shown using variable.
4. Time Control (30 pts): Code component exists, checks timer, thresholds at 90s, ends loop.

Pass Threshold: 60 pts (Must include functioning time limit logic).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_sdmt_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/sdmt_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 1. CSV Integrity (20 pts)
    if result.get("cond_exists") and result.get("cond_valid_csv"):
        if result.get("csv_mappings_correct"):
            score += 20
            feedback_parts.append("Conditions file perfect (20/20)")
        elif result.get("csv_row_count") == 9:
            score += 10
            feedback_parts.append("Conditions file has 9 rows but mappings invalid (10/20)")
        else:
            score += 5
            feedback_parts.append("Conditions file exists but incomplete (5/20)")
    else:
        feedback_parts.append("Conditions file missing or invalid (0/20)")

    # 2. Experiment Structure (30 pts)
    struct_score = 0
    if result.get("has_instructions"): struct_score += 5
    if result.get("has_trial"): struct_score += 5
    if result.get("has_loop"): struct_score += 10
    if result.get("loop_nreps", 0) >= 50: # High reps needed for time limit
        struct_score += 10
    else:
        feedback_parts.append("Loop nReps too low for timed task")
    
    score += struct_score
    feedback_parts.append(f"Structure score: {struct_score}/30")

    # 3. Visual Layout (20 pts)
    vis_score = 0
    if result.get("has_static_key"): vis_score += 10
    if result.get("has_dynamic_probe"): vis_score += 10
    
    score += vis_score
    feedback_parts.append(f"Visual components: {vis_score}/20")

    # 4. Time Control (30 pts) - CRITICAL
    time_score = 0
    if result.get("has_code_component"):
        time_score += 5
        if result.get("code_uses_clock"):
            time_score += 5
        if result.get("code_checks_90s"):
            time_score += 10
        if result.get("code_terminates_loop"):
            time_score += 10
    
    score += time_score
    feedback_parts.append(f"Time logic: {time_score}/30")

    # Pass logic
    passed = score >= 60 and result.get("code_checks_90s") and result.get("code_terminates_loop")

    if not result.get("code_terminates_loop"):
        feedback_parts.append("FAIL: Did not implement loop termination logic")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }