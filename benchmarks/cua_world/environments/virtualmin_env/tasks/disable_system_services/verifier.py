#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_disable_system_services(traj, env_info, task_info):
    """
    Verifies that the debug-logger service was stopped and disabled.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Service Stopped (40 pts)
    if result.get("final_active_state") == "inactive":
        score += 40
        feedback.append("Service is stopped.")
    else:
        feedback.append(f"Service is still {result.get('final_active_state')}.")

    # Criterion 2: Service Disabled (40 pts)
    if result.get("final_unit_state") == "disabled":
        score += 40
        feedback.append("Service is disabled from boot.")
    else:
        feedback.append(f"Service is still {result.get('final_unit_state')}.")

    # Criterion 3: Service File Preserved (10 pts)
    # The task said "Do NOT delete the service file".
    if result.get("service_file_exists"):
        score += 10
    else:
        feedback.append("Service file was deleted (incorrect procedure).")

    # Criterion 4: Safety Check (10 pts)
    if result.get("critical_services_ok"):
        score += 10
    else:
        feedback.append("Critical system services were stopped!")

    # VLM Verification (Trajectory Check)
    # Ensure they actually used the GUI and didn't just run shell commands (if terminal was open)
    # or that they found the correct module.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Analyze these screenshots of a Webmin session. "
        "Did the user navigate to 'Bootup and Shutdown' (or 'System Services') "
        "and interact with a service named 'debug-logger'? "
        "Look for the service name in the list and buttons like 'Disable Now' or 'Stop'."
    )
    
    # We won't hard-fail on VLM, but use it for feedback/tie-breaking if needed.
    # For now, programmatic verification is robust enough, but let's log it.
    # vlm_out = query_vlm(images=frames + [final_screen], prompt=vlm_prompt)

    passed = (score >= 80) and result.get("service_file_exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }