#!/usr/bin/env python3
"""
Verifier for configure_alert_whitelist task.

Criteria:
1. Verification file exists and contains the correct IP (172.16.0.50).
2. Verification file was created AFTER task start (anti-gaming).
3. (Optional but high value) IP address found in database configuration (Ground Truth).
4. VLM Trajectory confirms navigation to Correlation/Whitelist section.
"""

import json
import os
import tempfile
import logging
import time

# Import VLM utils from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_alert_whitelist(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get('metadata', {})
    target_ip = metadata.get('target_ip', '172.16.0.50')
    target_desc = metadata.get('target_description', 'Authorized_Nessus_Scanner')

    score = 0
    feedback = []
    
    # 1. Check Verification File (30 points)
    # Checks if file exists, has content, and was created during task
    file_exists = result.get('file_exists', False)
    file_content = result.get('file_content', '')
    file_timestamp = result.get('file_timestamp', 0)
    task_start = result.get('task_start_time', 0)

    if file_exists:
        if file_timestamp > task_start:
            if target_ip in file_content:
                score += 30
                feedback.append("Verification file created with correct IP.")
            else:
                score += 15
                feedback.append("Verification file created, but IP address missing/wrong.")
        else:
            feedback.append("Verification file timestamp indicates it wasn't created during this session.")
    else:
        feedback.append("Verification file not found.")

    # 2. Check Database Evidence (40 points)
    # Checks if the IP is actually present in the system config
    db_match = result.get('db_match_found', False)
    if db_match:
        score += 40
        feedback.append("Configuration confirmed in database (Ground Truth).")
    else:
        # If DB check failed, we rely more heavily on VLM
        feedback.append("IP address not found in backend database tables.")

    # 3. VLM Verification (30 points)
    # Verify the UI interaction using trajectory frames
    frames = sample_trajectory_frames(traj, n=5)
    final_frame = get_final_screenshot(traj)
    
    if frames and final_frame:
        # Prompt for VLM to look for Correlation/Whitelist UI and the specific IP
        vlm_prompt = f"""
        You are verifying a task in ManageEngine EventLog Analyzer.
        The user must:
        1. Navigate to 'Correlation' or 'Settings' > 'Whitelist'.
        2. Enter the IP '{target_ip}' into a form.
        3. Save the configuration.

        Review the screenshots.
        - Do you see the 'Correlation' or 'Whitelist' menu/tab?
        - Do you see the IP '{target_ip}' being typed or displayed in a list?
        - Do you see a success message or the saved entry?

        Answer in JSON: {{ "navigated_correctly": bool, "ip_entered": bool, "entry_saved": bool }}
        """
        
        vlm_response = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            vlm_score = 0
            if parsed.get("navigated_correctly"): vlm_score += 10
            if parsed.get("ip_entered"): vlm_score += 10
            if parsed.get("entry_saved"): vlm_score += 10
            
            score += vlm_score
            feedback.append(f"VLM Analysis: {vlm_score}/30 points.")
        else:
            feedback.append("VLM analysis failed.")
            # Fallback: if file was correct and DB failed (maybe schema diff), give partial credit based on file
            if file_exists and target_ip in file_content:
                score += 10
                feedback.append("VLM unavailable, adding fallback points for correct file.")

    # Final Pass/Fail logic
    # Must have either DB confirmation OR (File + VLM High Confidence)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }