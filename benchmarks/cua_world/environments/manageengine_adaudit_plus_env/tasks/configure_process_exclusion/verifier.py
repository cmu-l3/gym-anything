#!/usr/bin/env python3
"""
Verifier for configure_process_exclusion task.

SCORING:
- 40 pts: Primary VLM verification (visual confirmation of exclusion list).
- 30 pts: Database/Log evidence (programmatic confirmation).
- 30 pts: VLM Context (Navigated to correct settings page).
"""

import json
import os
import tempfile
import logging
import sys

# Add parent directory to path to import vlm_utils if needed
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Import VLM utils if available in the environment, otherwise define stubs
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for when running outside the gym environment during testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_process_exclusion(traj, env_info, task_info):
    """
    Verifies that the process 'titan_backup.exe' was excluded in ADAudit Plus.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_process = metadata.get('target_process', 'titan_backup.exe')

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        # Note: Container path is Windows, but copy_from_env handles the path mapping
        # We need to use the path specified in export_result.ps1
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not retrieve task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Screenshot
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    screenshot_path = None
    try:
        copy_from_env("C:\\workspace\\task_final.png", temp_screenshot.name)
        screenshot_path = temp_screenshot.name
    except Exception as e:
        logger.warning(f"Could not retrieve final screenshot: {e}")
        # If agent didn't produce one, try framework's final screenshot
        screenshot_path = get_final_screenshot(traj)

    # --- SCORING CRITERIA ---
    score = 0
    feedback = []

    # Criterion A: Database/Log Evidence (30 pts)
    # If the export script found the entry in Postgres or Logs
    db_found = result_data.get('exclusion_found_in_db', False)
    log_found = result_data.get('log_evidence_found', False)
    
    if db_found:
        score += 30
        feedback.append("Database confirmed process exclusion record.")
    elif log_found:
        score += 15
        feedback.append("Found evidence of process configuration in logs (partial credit).")
    else:
        feedback.append("No programmatic evidence of exclusion found.")

    # Criterion B: VLM Verification (70 pts)
    # We verify if the screenshot shows the exclusion list with the target process
    vlm_score = 0
    if screenshot_path and os.path.exists(screenshot_path):
        prompt = f"""
        You are verifying a task in ManageEngine ADAudit Plus.
        The user was asked to exclude the process '{target_process}' from auditing.
        
        Look at the screenshot and answer:
        1. Is the 'Process Exclusion' or 'Exclude Processes' settings list visible?
        2. Is '{target_process}' visible in the list of excluded processes?
        3. Does the interface look like a 'Configuration' or 'Admin' page?
        
        Output JSON:
        {{
            "settings_visible": boolean,
            "process_listed": boolean,
            "page_context_correct": boolean
        }}
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=screenshot_path)
        
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("process_listed"):
                vlm_score += 50
                feedback.append(f"Visual confirmation: '{target_process}' is listed in exclusions.")
            else:
                feedback.append(f"Visual check failed: '{target_process}' not found in screenshot.")
                
            if parsed.get("settings_visible") or parsed.get("page_context_correct"):
                vlm_score += 20
                feedback.append("Correct settings page navigated.")
        else:
            feedback.append("VLM analysis failed.")
    else:
        feedback.append("No screenshot available for verification.")
    
    score += vlm_score

    # Final Pass Check
    # Must have either DB confirmation OR visual confirmation of the specific process
    passed = (score >= 70) and (db_found or (vlm_score >= 50))

    # Cleanup
    if screenshot_path and os.path.exists(screenshot_path):
        os.unlink(screenshot_path)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }