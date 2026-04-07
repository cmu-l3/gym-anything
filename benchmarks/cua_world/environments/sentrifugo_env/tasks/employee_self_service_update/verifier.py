#!/usr/bin/env python3
"""
Verifier for employee_self_service_update task.

Uses multi-signal verification:
1. Database values (address, phone, name)
2. Database raw dump fallback (for string matches in JSON blobs)
3. File system checking (new uploads after start timestamp)
4. VLM Trajectory (checking file dialog and Self-Service UI navigation)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def build_vlm_prompt():
    return """Examine these trajectory screenshots from an agent completing a task in the Sentrifugo HRMS application.

Verify if the following actions were performed during the workflow:
1. Did the agent navigate to the 'Self Service' or 'Profile' section within Sentrifugo? (Look for employee profile details, personal data tabs, or Self Service headers).
2. Did the agent trigger an OS file upload dialog or interact with a file picker window to select the profile picture?

Respond in JSON format:
{
    "navigated_to_self_service": true/false,
    "triggered_file_upload": true/false,
    "reasoning": "Brief explanation of what is visible in the frames that supports these conclusions"
}"""

def verify_employee_self_service_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db = result.get('db', {})
    dump = result.get('dump', {})
    uploads = result.get('uploads', {})

    score = 0
    feedback_parts = []

    # 1. Address Check (20 pts)
    if db.get('address', 0) > 0 or dump.get('address', 0) > 0:
        score += 20
        feedback_parts.append("Address successfully updated/submitted (20/20)")
    else:
        feedback_parts.append("Address missing (0/20)")

    # 2. Emergency Contact Phone (15 pts)
    if db.get('phone', 0) > 0 or dump.get('phone', 0) > 0:
        score += 15
        feedback_parts.append("Emergency contact phone found (15/15)")
    else:
        feedback_parts.append("Emergency contact phone missing (0/15)")

    # 3. Dependent / Name Check (25 pts)
    # The name "Eleanor Vance-Kim" is used for both a dependent and an emergency contact
    # We expect it to appear twice, or at least once if partially completed.
    name_count = db.get('dependent', 0) + db.get('emergency_contact', 0) + db.get('pending_name', 0)
    dump_name_count = dump.get('name', 0)

    if name_count >= 2 or dump_name_count >= 2:
        score += 25
        feedback_parts.append("Dependent & Contact names found in system (25/25)")
    elif name_count == 1 or dump_name_count == 1:
        score += 12
        feedback_parts.append("Only partial Dependent/Contact names found (12/25)")
    else:
        feedback_parts.append("Dependent/Contact names missing (0/25)")

    # 4. Profile Picture Upload Check via File System (20 pts)
    # Proves file was uploaded during the task (anti-gaming via start timestamp)
    if uploads.get('new_images', 0) > 0:
        score += 20
        feedback_parts.append("Profile picture upload detected via filesystem (20/20)")
    else:
        feedback_parts.append("No profile picture upload detected (0/20)")

    # 5. VLM Trajectory Verification (20 pts)
    vlm_score = 0
    try:
        if 'query_vlm' in env_info and traj:
            from gym_anything.vlm import sample_trajectory_frames
            
            # Sample evenly across trajectory to catch dialog popups
            frames = sample_trajectory_frames(traj, n=6)
            if frames:
                prompt = build_vlm_prompt()
                vlm_result = env_info['query_vlm'](prompt=prompt, images=frames)
                
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    nav_ss = parsed.get('navigated_to_self_service', False)
                    upload_dialog = parsed.get('triggered_file_upload', False)
                    
                    if nav_ss:
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed Self-Service navigation (+10)")
                    if upload_dialog:
                        vlm_score += 10
                        feedback_parts.append("VLM confirmed file upload dialog usage (+10)")
                    if not nav_ss and not upload_dialog:
                        feedback_parts.append("VLM did not detect required UI interactions (0/20)")
                else:
                    feedback_parts.append(f"VLM query failed: {vlm_result.get('error')} (0/20)")
            else:
                feedback_parts.append("No trajectory frames available for VLM (0/20)")
        else:
            feedback_parts.append("VLM or trajectory unavailable (0/20)")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM error: {e} (0/20)")

    score += vlm_score

    # Passing threshold is 60/100
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }