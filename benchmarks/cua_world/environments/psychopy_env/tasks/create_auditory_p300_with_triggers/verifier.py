#!/usr/bin/env python3
"""
Verifier for create_auditory_p300_with_triggers task.

Criteria:
1. Files exist (Experiment and CSV).
2. Conditions file has valid probability (approx 80% standard, 20% target).
3. Conditions file contains correct triggers (10, 20).
4. Experiment has Sound and ParallelPort components.
5. Parallel Port is synchronized with Sound (start times match).
6. Parallel Port address is correct (0x0378).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_auditory_p300_with_triggers(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/p300_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback_parts = []
    
    # 1. File Existence (10 pts)
    if result.get("exp_exists") and result.get("cond_exists"):
        score += 10
        feedback_parts.append("Files created")
    else:
        feedback_parts.append("Missing experiment or conditions file")

    # 2. Conditions File Logic (30 pts)
    # Probability Check (20 pts)
    ratio = result.get("standard_ratio", 0)
    # Allow range 0.75 - 0.85 (e.g., 4/5 is 0.8)
    if 0.75 <= ratio <= 0.85:
        score += 20
        feedback_parts.append("Conditions: Correct 80/20 ratio")
    elif result.get("total_trials", 0) > 0:
        feedback_parts.append(f"Conditions: Incorrect ratio ({ratio:.2f})")
    else:
        feedback_parts.append("Conditions: Empty file")

    # Trigger Values (10 pts)
    triggers = result.get("trigger_values", [])
    if 10 in triggers and 20 in triggers:
        score += 10
        feedback_parts.append("Conditions: Correct triggers (10, 20)")
    else:
        feedback_parts.append(f"Conditions: Missing triggers 10/20 (found {list(set(triggers))})")

    # 3. Experiment Structure (60 pts)
    # Components (20 pts)
    if result.get("has_sound"):
        score += 10
    else:
        feedback_parts.append("Missing Sound component")
        
    if result.get("has_parallel_port"):
        score += 10
    else:
        feedback_parts.append("Missing ParallelPort component")

    # Configuration (40 pts)
    if result.get("sync_correct"):
        score += 15
        feedback_parts.append("Sync: Port starts with Sound")
    elif result.get("has_parallel_port"):
        feedback_parts.append("Sync: Port timing mismatch")

    addr = str(result.get("port_address", ""))
    if "0378" in addr:
        score += 10
        feedback_parts.append("Port: Address correct")
    elif result.get("has_parallel_port"):
        feedback_parts.append(f"Port: Wrong address ({addr})")

    if result.get("port_data_variable"):
        score += 10
        feedback_parts.append("Port: Data uses variable")
    elif result.get("has_parallel_port"):
        feedback_parts.append("Port: Data hardcoded (should use variable)")
        
    if result.get("loop_references_csv"):
        score += 5
        feedback_parts.append("Loop: Links to CSV")

    passed = score >= 70 and result.get("has_parallel_port") and result.get("sync_correct")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }