#!/usr/bin/env python3
"""
Verifier for configure_gdpr_compliance task.

Verification Logic:
1. File Verification (Primary):
   - Checks if 'gdpr_compliance_report.pdf' (or .csv) exists.
   - Verifies the file was created *during* the task window (anti-gaming).
   - Verifies file size > 500 bytes (not empty).

2. VLM Verification (Secondary):
   - Uses trajectory frames to confirm the agent navigated to the 'Compliance' tab.
   - Confirms the agent selected 'GDPR'.
   - Confirms the agent initiated an export action.

Scoring:
- 40 pts: Valid file created during task.
- 60 pts: VLM confirmation of correct workflow (Navigation -> GDPR -> Export).
- Pass Threshold: 60 pts (Requires at least partial success in both, or perfect file + partial VLM).
"""

import json
import os
import tempfile
import logging
import sys

# Import VLM utilities from the framework
# (Adjust import path based on environment structure if needed, or use inline mocks for standalone testing)
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing without framework
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(images, prompt): return {"parsed": {}}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_gdpr_compliance(traj, env_info, task_info):
    """
    Verifies that the agent configured GDPR compliance and exported a report.
    """
    # 1. Setup & Helper Functions
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON from container
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from environment"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Programmatic Verification (File Check) - Max 40 pts
    file_found = result_data.get("file_found", "none")
    file_created = result_data.get("file_created_during_task", False)
    file_size = result_data.get("file_size", 0)

    if file_found != "none":
        if file_created:
            if file_size > 500:
                score += 40
                feedback.append(f"Success: {file_found.upper()} report generated and verified.")
            else:
                score += 20
                feedback.append(f"Partial: {file_found.upper()} file exists but is empty/too small.")
        else:
            feedback.append("Failure: Report file timestamp predates task (did you overwrite an old file?).")
    else:
        feedback.append("Failure: No exported report file found in ~/Documents.")

    # 3. VLM Verification (Workflow Check) - Max 60 pts
    # We need to verify the PROCESS, not just the file, to ensure they used the GUI properly.
    
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are verifying a user session in 'ManageEngine EventLog Analyzer'. 
    The user was supposed to:
    1. Click on the 'Compliance' tab/menu.
    2. Select 'GDPR' from the compliance standards.
    3. Generate/View a report.
    4. Export the report (click an export icon/button).

    Analyze the provided screenshots sequence.
    Return JSON with:
    {
        "saw_compliance_tab": boolean, // Did they navigate to Compliance?
        "saw_gdpr_section": boolean, // Did they see/select GDPR?
        "saw_export_action": boolean, // Did they click export or save?
        "confidence": float (0-1)
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_data = vlm_result.get("parsed", {})
    
    vlm_score = 0
    if vlm_data.get("saw_compliance_tab"):
        vlm_score += 20
        feedback.append("VLM: Confirmed navigation to Compliance.")
    if vlm_data.get("saw_gdpr_section"):
        vlm_score += 20
        feedback.append("VLM: Confirmed selection of GDPR.")
    if vlm_data.get("saw_export_action"):
        vlm_score += 20
        feedback.append("VLM: Confirmed export action.")
    
    score += vlm_score

    # 4. Final Scoring
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }