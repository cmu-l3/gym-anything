#!/usr/bin/env python3
"""
Verifier for configure_campaign_blended_inbound task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_campaign_blended_inbound(traj, env_info, task_info):
    """
    Verifies that the agent enabled blended mode on the campaign and linked the inbound group.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract values
    allow_closers = result.get("allow_closers_value", "").strip()
    linkage_count = int(result.get("linkage_count", 0))
    app_running = result.get("app_running", False)

    score = 0
    feedback_parts = []
    
    # Criteria 1: App Running (10 pts)
    if app_running:
        score += 10
    else:
        feedback_parts.append("Firefox was closed")

    # Criteria 2: Blended Mode Enabled (45 pts)
    # The database value 'Y' means enabled
    if allow_closers == 'Y':
        score += 45
        feedback_parts.append("Blended mode enabled successfully")
    elif allow_closers == 'N':
        feedback_parts.append("Blended mode NOT enabled (allow_closers is still 'N')")
    else:
        feedback_parts.append(f"Unknown blended state: {allow_closers}")

    # Criteria 3: Linkage Created (45 pts)
    if linkage_count >= 1:
        score += 45
        feedback_parts.append("Inbound group linked successfully")
    else:
        feedback_parts.append("Inbound group NOT linked to campaign")

    # Determine Success
    # Must have both main criteria met (allow_closers=Y AND linkage exists)
    passed = (allow_closers == 'Y' and linkage_count >= 1)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }