#!/usr/bin/env python3
"""
Verifier for block_inbound_spam_numbers task.

Criteria:
1. Filter Phone Group 'SPAMBLOCK' created.
2. Filter Phone Group Name contains "Blocked Spammers".
3. Phone number '2025550188' added to the group.
4. DID '8885550100' configured to use GROUP filtering.
5. DID linked to 'SPAMBLOCK'.
6. DID action set to 'HANGUP'.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_block_inbound_spam_numbers(traj, env_info, task_info):
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
    feedback_parts = []
    
    # 1. Filter Group Exists (20 pts)
    if result.get('group_exists'):
        score += 20
        feedback_parts.append("Filter Group 'SPAMBLOCK' created")
    else:
        feedback_parts.append("Filter Group 'SPAMBLOCK' NOT found")

    # 2. Group Name (10 pts)
    # Check if name contains "Blocked Spammers" (case insensitive)
    group_name = result.get('group_name', '')
    if "blocked spammers" in group_name.lower():
        score += 10
        feedback_parts.append("Group name correct")
    else:
        feedback_parts.append(f"Group name incorrect or missing ('{group_name}')")

    # 3. Number Added (30 pts)
    if result.get('number_added'):
        score += 30
        feedback_parts.append("Spam number added to group")
    else:
        feedback_parts.append("Spam number NOT found in group")

    # 4. DID Filter Enabled (20 pts)
    # filter_inbound_number should be 'GROUP'
    did_status = result.get('did_filter_status', '')
    if did_status == 'GROUP':
        score += 20
        feedback_parts.append("DID filtering set to GROUP")
    else:
        feedback_parts.append(f"DID filtering not enabled (Status: {did_status})")

    # 5. DID Group Linked (10 pts)
    did_group = result.get('did_filter_group', '')
    if did_group == 'SPAMBLOCK':
        score += 10
        feedback_parts.append("DID linked to SPAMBLOCK")
    else:
        feedback_parts.append(f"DID linked to wrong group ('{did_group}')")

    # 6. DID Action Correct (10 pts)
    did_action = result.get('did_action', '')
    if did_action == 'HANGUP':
        score += 10
        feedback_parts.append("DID action set to HANGUP")
    else:
        feedback_parts.append(f"DID action incorrect ('{did_action}')")

    # Pass Threshold: 70 points
    # Must have created group and added number to minimally pass if DID part failed partialy,
    # or fully configured DID.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }