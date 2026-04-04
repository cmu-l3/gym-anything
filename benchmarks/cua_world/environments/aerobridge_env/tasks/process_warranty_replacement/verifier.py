#!/usr/bin/env python3
"""
Verifier for process_warranty_replacement task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_warranty_replacement(traj, env_info, task_info):
    """
    Verifies that the warranty replacement process was handled correctly:
    1. Old aircraft (SH-CRASH-001) is marked as WRITE-OFF.
    2. New aircraft (SH-REPL-002) exists.
    3. New aircraft has the CORRECT Operator and Manufacturer (copied from old).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/warranty_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Old Aircraft Decommissioning (20 pts)
    crashed_renamed = result.get("crashed_renamed", False)
    crashed_status = str(result.get("crashed_status", "")).lower()
    
    if crashed_renamed:
        score += 20
        feedback_parts.append("✓ Old aircraft renamed with [WRITE-OFF] (+20)")
    else:
        feedback_parts.append("✗ Old aircraft registration not updated with [WRITE-OFF]")

    # Check status (bonus/alternative verification of decommissioning)
    # If status is 'inactive' or '0' or 'false'
    if crashed_status in ['inactive', '0', 'false', 'draft', 'retired']:
        score += 10
        feedback_parts.append("✓ Old aircraft status set to inactive/retired (+10)")
    
    # 2. Check New Aircraft Creation (20 pts)
    if result.get("replacement_found"):
        score += 20
        feedback_parts.append("✓ Replacement aircraft SH-REPL-002 created (+20)")
    else:
        feedback_parts.append("✗ Replacement aircraft SH-REPL-002 not found")
        # Critical failure if replacement not made, but we continue to show full feedback
    
    # 3. Data Integrity Check (CRITICAL) (50 pts total)
    # The agent had to look these up. They weren't in the prompt.
    
    expected_op = result.get("expected_operator")
    actual_op = result.get("replacement_operator")
    
    if actual_op == expected_op:
        score += 25
        feedback_parts.append(f"✓ Operator correctly set to '{actual_op}' (+25)")
    else:
        feedback_parts.append(f"✗ Operator incorrect. Expected '{expected_op}', got '{actual_op}'")

    expected_mfr = result.get("expected_manufacturer")
    actual_mfr = result.get("replacement_manufacturer")
    
    if actual_mfr == expected_mfr:
        score += 25
        feedback_parts.append(f"✓ Manufacturer correctly set to '{actual_mfr}' (+25)")
    else:
        feedback_parts.append(f"✗ Manufacturer incorrect. Expected '{expected_mfr}', got '{actual_mfr}'")

    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: Needs decent decommissioning AND correct data
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }