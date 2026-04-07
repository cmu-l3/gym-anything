#!/usr/bin/env python3
"""
Verifier for EBR Zero-Downtime Deployment task.
Scores based on edition setup, logic isolation, and final cutover state.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ebr_deployment(traj, env_info, task_info):
    """
    Verifies that the agent correctly implemented Edition-Based Redefinition.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_base = metadata.get('expected_base_value', 1000)
    expected_v2 = metadata.get('expected_v2_value', 2400)

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Check HR Editions Enabled (10 pts)
    if result.get("hr_editions_enabled"):
        score += 10
        feedback_parts.append("HR user edition-enabled")
    else:
        feedback_parts.append("HR user NOT edition-enabled")

    # 2. Check Edition Existence (10 pts)
    editions = result.get("editions_list", [])
    if "RELEASE_V2" in editions:
        score += 10
        feedback_parts.append("Edition RELEASE_V2 created")
    else:
        feedback_parts.append("Edition RELEASE_V2 missing")

    # 3. Check Base Logic (20 pts)
    base_res = result.get("base_logic_result")
    if base_res == expected_base:
        score += 20
        feedback_parts.append(f"Base logic correct ({base_res})")
    else:
        feedback_parts.append(f"Base logic incorrect (Expected {expected_base}, Got {base_res})")

    # 4. Check Patch Logic (20 pts)
    v2_res = result.get("v2_logic_result")
    if v2_res == expected_v2:
        score += 20
        feedback_parts.append(f"Patch logic correct ({v2_res})")
    else:
        feedback_parts.append(f"Patch logic incorrect (Expected {expected_v2}, Got {v2_res})")

    # 5. Check Isolation (15 pts)
    # Isolation means they are DIFFERENT and CORRECT simultaneously
    if result.get("isolation_success"):
        score += 15
        feedback_parts.append("Editions successfully isolated")
    elif base_res == v2_res and base_res is not None:
         feedback_parts.append("Logic not isolated (both editions return same value)")

    # 6. Check Cutover / Default Edition (10 pts)
    default_ed = result.get("default_edition")
    default_res = result.get("default_conn_result")
    
    if default_ed == 'RELEASE_V2':
        score += 10
        feedback_parts.append("Default edition switched to RELEASE_V2")
    else:
        feedback_parts.append(f"Default edition is {default_ed} (Expected RELEASE_V2)")
        
    # Check if default connection returns new value (implicit cutover check)
    if default_res == expected_v2:
        # Bonus/Confirmation (already covered by score, but good for feedback)
        pass

    # 7. Check Report File (5 pts)
    if result.get("report_file_exists") == "true":
        score += 5
        feedback_parts.append("Validation report found")
    else:
        feedback_parts.append("Validation report missing")

    passed = (score >= 65) and result.get("isolation_success", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }