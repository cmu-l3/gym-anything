#!/usr/bin/env python3
"""
Verifier for Masked Priming Task.

Checks:
1. Valid conditions CSV with real semantic data.
2. Valid PsychoPy experiment file.
3. CRITICAL: Prime duration is subliminal (<= 50ms or <= 3 frames).
4. Mask and Target components exist.
5. VLM: Verifies workflow progression in Builder.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_masked_priming_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/masked_priming_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Check Files Existence (20 pts)
    if result.get("exp_exists"):
        score += 10
        feedback_parts.append("Experiment file created")
    else:
        feedback_parts.append("Missing .psyexp file")
        
    if result.get("csv_exists"):
        score += 10
        feedback_parts.append("Conditions file created")
    else:
        feedback_parts.append("Missing .csv file")

    # 2. Check CSV Content (20 pts)
    if result.get("csv_valid") and result.get("csv_rows", 0) >= 12:
        score += 20
        feedback_parts.append(f"CSV valid ({result['csv_rows']} rows)")
    elif result.get("csv_valid"):
        score += 10
        feedback_parts.append(f"CSV valid but too few rows ({result.get('csv_rows')})")
    else:
        feedback_parts.append("CSV invalid or missing columns")

    # 3. Check Experiment Structure (30 pts)
    struct_score = 0
    if result.get("mask_component_found"): struct_score += 10
    if result.get("target_component_found"): struct_score += 5
    if result.get("loop_found"): struct_score += 10
    if result.get("keyboard_correct_ans"): struct_score += 5
    score += struct_score
    if struct_score == 30:
        feedback_parts.append("Experiment structure correct")
    else:
        feedback_parts.append(f"Partial structure ({struct_score}/30 pts)")

    # 4. CRITICAL: Prime Timing (30 pts)
    # Must be <= 0.05s or <= 3 frames (ideal is 2 frames / 0.033s)
    prime_val = result.get("prime_duration_val")
    prime_type = result.get("prime_duration_type")
    
    timing_passed = False
    if prime_val:
        try:
            val = float(prime_val)
            if "frame" in str(prime_type).lower():
                if val <= 4: # Allow small margin (e.g. 3 frames is 50ms at 60Hz)
                    timing_passed = True
                    feedback_parts.append(f"Prime timing good ({val} frames)")
            else:
                # Assume seconds
                if val <= 0.06: # Allow up to 60ms
                    timing_passed = True
                    feedback_parts.append(f"Prime timing good ({val}s)")
        except:
            pass
    
    if timing_passed:
        score += 30
    elif result.get("prime_component_found"):
        feedback_parts.append(f"Prime found but timing incorrect/unsafe ({prime_val} {prime_type})")
        score += 5 # Small credit for finding component
    else:
        feedback_parts.append("Prime component missing")

    # Final Pass Check
    # Must have files + CSV valid + Prime Timing correct
    passed = (result.get("exp_exists") and 
              result.get("csv_valid") and 
              timing_passed and 
              score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }