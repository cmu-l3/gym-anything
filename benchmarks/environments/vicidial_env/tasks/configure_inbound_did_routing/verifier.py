#!/usr/bin/env python3
"""
Verifier for configure_inbound_did_routing task.

Verifies that:
1. An Inbound Group 'GREENFIELD_SUP' was created with correct settings.
2. A DID '8005559247' was created with correct settings.
3. The DID is correctly routed to the Inbound Group.
4. Records were created during the task (anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inbound_did_routing(traj, env_info, task_info):
    """
    Verify In-Group and DID configuration in Vicidial.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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

    score = 0
    max_score = 100
    feedback_parts = []
    
    ingroup = result.get('ingroup', {})
    did = result.get('did', {})
    stats = result.get('stats', {})

    # --- Verify In-Group (50 points) ---
    if ingroup.get('exists'):
        score += 15
        feedback_parts.append("In-Group created")
        
        # Name (10 pts)
        if ingroup.get('group_name') == 'Greenfield Insurance Support':
            score += 10
        else:
            feedback_parts.append(f"In-Group name mismatch: {ingroup.get('group_name')}")

        # Active (5 pts)
        if ingroup.get('active') == 'Y':
            score += 5
        else:
            feedback_parts.append("In-Group not active")

        # Routing Logic (10 pts)
        if ingroup.get('next_agent_call') == 'longest_wait_all':
            score += 10
        else:
            feedback_parts.append(f"In-Group routing mismatch: {ingroup.get('next_agent_call')}")

        # Priority (5 pts)
        try:
            if int(ingroup.get('queue_priority', 0)) == 99:
                score += 5
            else:
                feedback_parts.append(f"Priority mismatch: {ingroup.get('queue_priority')}")
        except:
            feedback_parts.append("Invalid priority format")

        # Color (5 pts)
        if ingroup.get('group_color') == '#009900':
            score += 5
        else:
            feedback_parts.append("Color mismatch")

    else:
        feedback_parts.append("In-Group 'GREENFIELD_SUP' NOT found")

    # --- Verify DID (50 points) ---
    if did.get('exists'):
        score += 15
        feedback_parts.append("DID created")

        # Description (10 pts)
        if did.get('description') == 'Greenfield Main Support':
            score += 10
        else:
            feedback_parts.append("DID description mismatch")

        # Route Type (5 pts)
        if did.get('route') == 'IN_GROUP':
            score += 5
        else:
            feedback_parts.append(f"DID route mismatch: {did.get('route')}")

        # Linkage (15 pts) - CRITICAL
        if did.get('group_id') == 'GREENFIELD_SUP':
            score += 15
            feedback_parts.append("DID correctly linked to In-Group")
        else:
            feedback_parts.append(f"DID linked to wrong group: {did.get('group_id')}")

        # Active (5 pts)
        if did.get('active') == 'Y':
            score += 5
        else:
            feedback_parts.append("DID not active")
            
    else:
        feedback_parts.append("DID '8005559247' NOT found")

    # --- Anti-Gaming Checks ---
    # We expect positive count diffs if the agent created them.
    # If counts didn't change but records exist, they might be pre-existing (though setup clears them).
    if ingroup.get('exists') and stats.get('ingroup_count_diff', 0) <= 0:
        feedback_parts.append("Warning: In-Group count did not increase")
    
    if did.get('exists') and stats.get('did_count_diff', 0) <= 0:
        feedback_parts.append("Warning: DID count did not increase")

    # --- Pass Logic ---
    # Must have both objects created to pass
    passed = (score >= 65) and ingroup.get('exists') and did.get('exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }