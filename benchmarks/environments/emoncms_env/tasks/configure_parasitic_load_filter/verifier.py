#!/usr/bin/env python3
"""
Verifier for configure_parasitic_load_filter task.

Verifies:
1. Feed creation (20 pts)
2. Functional logic (Test A - Clamping) (40 pts)
3. Functional logic (Test B - Subtraction) (40 pts)

Uses functional testing results exported from the container.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parasitic_load_filter(traj, env_info, task_info):
    """
    Verify the parasitic load filter configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # Criterion 1: Feed exists (20 pts)
    if result.get("feed_exists"):
        score += 20
        feedback_parts.append("Feed 'workshop_production_load' created.")
    else:
        feedback_parts.append("Feed 'workshop_production_load' NOT created.")
        return {"passed": False, "score": 0, "feedback": "Task failed: Target feed was not created."}

    # Helper for float comparison
    def check_val(actual_str, expected, tolerance=0.5):
        try:
            val = float(actual_str)
            return abs(val - expected) <= tolerance, val
        except (ValueError, TypeError):
            return False, actual_str

    # Criterion 2: Test A (Clamping logic) (40 pts)
    # Input 40 -> Output should be 0 (40 - 45 = -5 -> clamped to 0)
    test_a = result.get("test_a", {})
    passed_a, val_a = check_val(test_a.get("actual"), test_a.get("expected"))
    
    if passed_a:
        score += 40
        feedback_parts.append("Zero-clamping logic verified (Input 40 -> 0).")
    else:
        feedback_parts.append(f"Zero-clamping logic failed: Input 40 resulted in {val_a} (Expected 0). Check order of operations (subtract then allow positive).")

    # Criterion 3: Test B (Subtraction logic) (40 pts)
    # Input 145 -> Output should be 100 (145 - 45 = 100)
    test_b = result.get("test_b", {})
    passed_b, val_b = check_val(test_b.get("actual"), test_b.get("expected"))
    
    if passed_b:
        score += 40
        feedback_parts.append("Subtraction logic verified (Input 145 -> 100).")
    else:
        feedback_parts.append(f"Subtraction logic failed: Input 145 resulted in {val_b} (Expected 100). Check offset value (-45).")

    # Final verdict
    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }