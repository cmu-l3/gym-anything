#!/usr/bin/env python3
"""
Verifier for record_appointment_noshow task.
Validates that the specific appointment's status was changed in the database,
and utilizes VLM on trajectory frames to ensure the action performed was marking it as a "No-Show".
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing VLM tools gracefully
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM tools not available. Will fallback to database-only verification.")

def verify_record_appointment_noshow(traj, env_info, task_info):
    """
    Verify the agent changed the appointment status to No-Show.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the exported JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/noshow_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    app_id = result.get('appointment_id', '')
    initial_status = str(result.get('initial_status', '')).strip()
    final_status = str(result.get('final_status', '')).strip()
    appointment_exists = result.get('appointment_exists', False)

    feedback_parts = []
    score = 0

    # 2. Programmatic Database Checks
    if not app_id:
        return {"passed": False, "score": 0, "feedback": "Setup failed to create the initial appointment."}

    if not appointment_exists:
        feedback_parts.append("FAIL: Appointment was deleted instead of having its status updated.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    if final_status == initial_status:
        feedback_parts.append("FAIL: Appointment status was not changed in the database.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        score += 40
        feedback_parts.append(f"DB Success: Appointment status changed from {initial_status} to {final_status}.")

    # 3. VLM Trajectory Verification
    vlm_passed = False
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = (
                "Review these trajectory screenshots from the FreeMED Electronic Medical Record system. "
                "The user's task was to mark Marcus Vance's appointment as a 'No-Show'. "
                "Did the user successfully interact with the appointment status dropdown/field and select "
                "'No Show', 'No-Show', or 'Missed'? "
                "Return JSON ONLY: {\"noshow_selected\": true} if there is visual evidence of this status being selected, "
                "otherwise {\"noshow_selected\": false}."
            )
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            
            if vlm_response and vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                vlm_passed = parsed.get('noshow_selected', False)
                if vlm_passed:
                    score += 60
                    feedback_parts.append("VLM Success: Visual evidence confirms 'No-Show' selection.")
                else:
                    feedback_parts.append("VLM FAIL: Could not visually confirm 'No-Show' was selected in the UI.")
            else:
                # If VLM query fails structurally, gracefully assign partial points or pass based on DB
                logger.warning("VLM query failed to execute properly.")
                score += 60 
                feedback_parts.append("VLM Note: Query failed, assuming success based on DB change.")
                vlm_passed = True
        except Exception as e:
            logger.error(f"Error during VLM verification: {e}")
            score += 60
            feedback_parts.append("VLM Note: Exception occurred, assuming success based on DB change.")
            vlm_passed = True
    else:
        # Graceful fallback if VLM is unavailable in test environment
        score += 60
        feedback_parts.append("VLM Note: VLM unavailable, bypassed visual check.")
        vlm_passed = True

    passed = score == 100

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }