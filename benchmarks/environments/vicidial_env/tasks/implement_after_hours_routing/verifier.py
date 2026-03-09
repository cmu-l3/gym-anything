#!/usr/bin/env python3
"""
Verifier for implement_after_hours_routing task.

Verifies:
1. Call Time 'PRISUP_HRS' created with correct hours (M-F 9-6).
2. Call Time is closed on weekends.
3. Inbound Group 'PRISUP' is linked to 'PRISUP_HRS'.
4. Inbound Group 'PRISUP' has After Hours Action = VOICEMAIL.
5. Inbound Group 'PRISUP' has After Hours Voicemail = 1000.
"""

import json
import logging
import os
import tempfile
import sys

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_after_hours_routing(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    
    # 1. Verify Call Time Creation (25 pts)
    ct = result.get("call_time", {})
    if ct.get("exists"):
        score += 15
        feedback_parts.append("Call Time 'PRISUP_HRS' created")
        
        # Check M-F Hours (0900 - 1800)
        # Vicidial stores as '0900' or '900' sometimes, usually fixed width '0900'
        start = str(ct.get("default_start", "0")).zfill(4)
        stop = str(ct.get("default_stop", "0")).zfill(4)
        
        if start == "0900" and stop == "1800":
            score += 10
            feedback_parts.append("M-F hours correct (0900-1800)")
        else:
            feedback_parts.append(f"M-F hours incorrect (Found: {start}-{stop}, Expected: 0900-1800)")
            
        # Check Weekend (Closed) (10 pts)
        # Closed usually means start=stop or start=2400/stop=2400
        sat_start = str(ct.get("saturday_start", "0"))
        sat_stop = str(ct.get("saturday_stop", "0"))
        sun_start = str(ct.get("sunday_start", "0"))
        sun_stop = str(ct.get("sunday_stop", "0"))
        
        # Logic: If start==stop, it's effectively 0 duration. Or if marked 2400.
        is_sat_closed = (sat_start == sat_stop) or (sat_start == "2400")
        is_sun_closed = (sun_start == sun_stop) or (sun_start == "2400")
        
        if is_sat_closed and is_sun_closed:
            score += 10
            feedback_parts.append("Weekend hours correct (Closed)")
        else:
            feedback_parts.append(f"Weekend not fully closed (Sat: {sat_start}-{sat_stop}, Sun: {sun_start}-{sun_stop})")
            
    else:
        feedback_parts.append("Call Time 'PRISUP_HRS' NOT found")

    # 2. Verify Inbound Group Configuration (55 pts)
    grp = result.get("inbound_group", {})
    if grp.get("exists"):
        # Linkage (20 pts)
        if grp.get("call_time_id") == "PRISUP_HRS":
            score += 20
            feedback_parts.append("Group linked to correct Call Time")
        else:
            feedback_parts.append(f"Group linked to wrong Call Time: {grp.get('call_time_id')}")
            
        # Action (15 pts)
        if grp.get("action") == "VOICEMAIL":
            score += 15
            feedback_parts.append("After-hours action correct (VOICEMAIL)")
        else:
            feedback_parts.append(f"After-hours action incorrect: {grp.get('action')}")
            
        # Voicemail Box (10 pts)
        if str(grp.get("voicemail")) == "1000":
            score += 10
            feedback_parts.append("Voicemail box correct (1000)")
        else:
            feedback_parts.append(f"Voicemail box incorrect: {grp.get('voicemail')}")
            
        # Message (10 pts)
        if grp.get("message") == "vm-goodbye":
            score += 10
            feedback_parts.append("Message correct (vm-goodbye)")
        else:
            feedback_parts.append(f"Message incorrect: {grp.get('message')}")
            
    else:
        feedback_parts.append("Inbound Group 'PRISUP' NOT found (Critical Error)")

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }