#!/usr/bin/env python3
"""
Verifier for activate_emergency_closure task in Vicidial.

Checks:
1. Call Time 'FORCE_CLOSE' exists and is set to 0 start/stop (closed).
2. Inbound Group 'CS_QUEUE' is linked to 'FORCE_CLOSE'.
3. Inbound Group 'CS_QUEUE' has correct after-hours action (MESSAGE) and filename.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_activate_emergency_closure(traj, env_info, task_info):
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

    # Extract data
    call_time = result.get('call_time', {})
    inbound_group = result.get('inbound_group', {})
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Call Time Creation (20 pts)
    if call_time.get('exists'):
        score += 20
        feedback_parts.append("Call Time 'FORCE_CLOSE' created")
        
        # 2. Verify Call Time Settings (20 pts)
        # Expecting 0 for both to ensure it's never open
        try:
            start = int(call_time.get('ct_default_start', -1))
            stop = int(call_time.get('ct_default_stop', -1))
            
            if start == 0 and stop == 0:
                score += 20
                feedback_parts.append("Call Time correctly configured (0/0)")
            else:
                feedback_parts.append(f"Call Time start/stop incorrect (found {start}/{stop}, expected 0/0)")
        except ValueError:
            feedback_parts.append("Call Time values invalid")
    else:
        feedback_parts.append("Call Time 'FORCE_CLOSE' NOT found")

    # 3. Verify Inbound Group Linkage (20 pts)
    if inbound_group.get('exists'):
        actual_ct = inbound_group.get('call_time_id', '')
        if actual_ct == 'FORCE_CLOSE':
            score += 20
            feedback_parts.append("Inbound Group linked to FORCE_CLOSE")
        else:
            feedback_parts.append(f"Inbound Group linked to wrong time: '{actual_ct}'")
            
        # 4. Verify Action Configuration (20 pts)
        action = inbound_group.get('after_hours_action', '')
        if action == 'MESSAGE':
            score += 20
            feedback_parts.append("After Hours Action set to MESSAGE")
        else:
            feedback_parts.append(f"After Hours Action incorrect: '{action}'")
            
        # 5. Verify Audio Configuration (20 pts)
        # Filename might have .wav extension or not in DB depending on how it was entered, 
        # but usually stored without if selected from dropdown. We accept containing "vm-goodbye".
        audio = inbound_group.get('after_hours_message_filename', '')
        if 'vm-goodbye' in audio:
            score += 20
            feedback_parts.append("Audio message set correctly")
        else:
            feedback_parts.append(f"Audio message incorrect: '{audio}'")
    else:
        feedback_parts.append("Inbound Group 'CS_QUEUE' not found (critical error)")

    # Final check
    passed = score >= 80  # Must allow minor tolerance but key steps must be done
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }