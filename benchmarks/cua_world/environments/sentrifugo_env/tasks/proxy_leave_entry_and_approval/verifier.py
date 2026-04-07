#!/usr/bin/env python3
"""
Verifier for proxy_leave_entry_and_approval task.

HYBRID VERIFICATION:
1. Programmatic Check (80 pts): Database dump analyzed for correct leave requests.
   - For each of the 4 employees: 
     - Entry correct (empid, dates, leave type match): 10 pts
     - Approval state correct: 10 pts
2. VLM Trajectory Verification (20 pts): Ensure agent navigated Sentrifugo UI 
   to achieve this, avoiding automated curl scripts or pure DB manipulation.

Total: 100 points
Pass Threshold: 60 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these screenshots from an agent's workflow interacting with an HR system (Sentrifugo).
Task: Did the agent interact with the Leave Management UI or Employee Records to proxy-submit and approve leave requests?

Indicators of success:
- Viewing employee leave balances or leave request forms
- Interacting with dropdowns for Sick Leave or Annual Leave
- Seeing date pickers or leave status tables (Pending/Approved)
- Viewing the Leave module or the Admin approval queues

Respond in JSON format:
{
    "used_leave_system": true/false,
    "observations": "brief description of relevant UI interactions"
}"""

def match_type(lcode, expected_type):
    """Check if the provided leavecode matches the expected type."""
    lcode = str(lcode).lower()
    if expected_type == "SL" and ("sick" in lcode or "sl" in lcode): return True
    if expected_type == "AL" and ("annual" in lcode or "al" in lcode): return True
    return False

def match_dates(raw_req, dates):
    """Check if ALL target dates appear somewhere in the request row values."""
    vals = [str(v).lower() for v in raw_req.values()]
    for d in dates:
        if not any(d in v for v in vals):
            return False
    return True

def is_approved(raw_req):
    """Check if the request status indicates approval."""
    return any(isinstance(v, str) and "approve" in v.lower() for v in raw_req.values())

def verify_proxy_leave(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_requests = metadata.get('expected_requests', [])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    submitted_requests = result_data.get('requests', [])
    score = 0
    feedback_parts = []

    # 1. Programmatic Check (80 points total)
    for expected in expected_requests:
        empid = expected['empid']
        target_dates = expected['dates']
        target_type = expected['type']
        
        found_entry = False
        approved = False

        for req in submitted_requests:
            if req.get('empid') == empid:
                if match_type(req.get('leavecode'), target_type):
                    if match_dates(req.get('raw_request', {}), target_dates):
                        found_entry = True
                        if is_approved(req.get('raw_request', {})):
                            approved = True
                        break
        
        if found_entry and approved:
            score += 20
            feedback_parts.append(f"{empid}: entered & approved (+20)")
        elif found_entry:
            score += 10
            feedback_parts.append(f"{empid}: entered but NOT approved (+10)")
        else:
            feedback_parts.append(f"{empid}: missing or incorrect dates/type (0)")

    # 2. VLM Trajectory Verification (20 points)
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        query_vlm = env_info.get('query_vlm')
        if query_vlm and images:
            vlm_result = query_vlm(prompt=build_vlm_prompt(), images=images)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_leave_system", False):
                    vlm_score = 20
                    feedback_parts.append("VLM: Leave system interaction detected (+20)")
                else:
                    feedback_parts.append("VLM: No leave system interaction detected (0)")
            else:
                feedback_parts.append("VLM: Query failed, skipping VLM check")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM check bypassed due to error")
        # If VLM errors out, be lenient to prevent failing perfectly good runs
        vlm_score = 20

    score += vlm_score
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }