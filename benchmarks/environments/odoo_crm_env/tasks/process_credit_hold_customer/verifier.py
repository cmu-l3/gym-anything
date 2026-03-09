#!/usr/bin/env python3
"""
Verifier for process_credit_hold_customer task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_credit_hold_customer(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Created 'Credit Issues' lost reason
    2. Created 'Credit Hold' tag
    3. Tagged 'Gemini Furniture' with 'Credit Hold'
    4. Marked 'Gemini - Office Chairs' as lost with 'Credit Issues' reason
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for script errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Export script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    # 1. Lost Reason Created (20 pts)
    if result.get("lost_reason_created"):
        score += 20
        feedback_parts.append("✅ Lost Reason 'Credit Issues' created")
    else:
        feedback_parts.append("❌ Lost Reason 'Credit Issues' NOT found")

    # 2. Tag Created (20 pts)
    if result.get("tag_created"):
        score += 20
        feedback_parts.append("✅ Tag 'Credit Hold' created")
    else:
        feedback_parts.append("❌ Tag 'Credit Hold' NOT found")

    # 3. Partner Tagged (20 pts)
    if result.get("partner_tagged"):
        score += 20
        feedback_parts.append("✅ Customer tagged with 'Credit Hold'")
    else:
        feedback_parts.append("❌ Customer 'Gemini Furniture' does NOT have the 'Credit Hold' tag")

    # 4. Opportunity Lost (20 pts)
    if result.get("opportunity_lost"):
        score += 20
        feedback_parts.append("✅ Opportunity marked as Lost")
    else:
        feedback_parts.append("❌ Opportunity 'Gemini - Office Chairs' is still Active (not Lost)")

    # 5. Correct Reason Used (20 pts)
    if result.get("opportunity_reason_correct"):
        score += 20
        feedback_parts.append("✅ Correct lost reason applied to opportunity")
    elif result.get("opportunity_lost"):
        feedback_parts.append("❌ Wrong lost reason applied (expected 'Credit Issues')")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }