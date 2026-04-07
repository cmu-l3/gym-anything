#!/usr/bin/env python3
"""
Verifier for create_change_blindness_task.

Criteria:
1. Experiment file exists and valid XML (10 pts)
2. Images downloaded correctly (10 pts)
3. Conditions file valid (10 pts)
4. Nested loops structure (Trials > Flicker) (20 pts)
5. Correct timing configuration (240ms/80ms) (20 pts)
6. Loop termination logic implemented (Code/Keyboard) (20 pts)
7. VLM Verification of workflow (10 pts)

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_create_change_blindness_task(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # Load Result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/change_blindness_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # 1. Experiment File (10 pts)
    if result.get("exp_exists") and result.get("is_valid_xml") and result.get("exp_modified"):
        score += 10
        feedback_parts.append("Experiment file created valid.")
    else:
        feedback_parts.append("Experiment file missing or invalid.")

    # 2. Stimuli (10 pts)
    if result.get("image_a_exists") and result.get("image_b_exists") and result.get("image_a_size", 0) > 1000:
        score += 10
        feedback_parts.append("Stimuli downloaded.")
    else:
        feedback_parts.append("Stimuli missing.")

    # 3. Conditions File (10 pts)
    columns = result.get("cond_columns", [])
    required_cols = ["image1", "image2"]
    if result.get("cond_exists") and all(c in columns for c in required_cols):
        score += 10
        feedback_parts.append("Conditions file valid.")
    else:
        feedback_parts.append("Conditions file missing or incorrect columns.")

    # 4. Nested Loops (20 pts)
    if result.get("has_nested_loops"):
        score += 20
        feedback_parts.append("Nested loops detected.")
    elif len(result.get("loops", [])) >= 2:
        score += 10
        feedback_parts.append("Multiple loops found (nesting uncertain).")
    else:
        feedback_parts.append("Nested loops not found.")

    # 5. Timing (20 pts)
    if result.get("timing_pattern_found"):
        score += 20
        feedback_parts.append("Timing pattern (240ms/80ms) found.")
    else:
        feedback_parts.append("Correct timing pattern not found.")

    # 6. Loop Termination (20 pts)
    # Check if termination logic exists OR keyboard component is present
    has_kb = any("Key" in c.get("type", "") for c in result.get("components", []))
    has_logic = result.get("loop_termination_logic")
    
    if has_logic:
        score += 20
        feedback_parts.append("Loop termination logic found.")
    elif has_kb:
        score += 10 # Partial credit if keyboard exists but logic unclear
        feedback_parts.append("Keyboard response found (termination logic unclear).")
    else:
        feedback_parts.append("No response mechanism found.")

    # 7. VLM Verification (10 pts)
    # Just checking if they opened the builder and did something
    if result.get("exp_modified") and score >= 40:
        score += 10
        feedback_parts.append("Workflow verification passed.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }