#!/usr/bin/env python3
"""
Verifier for configure_table_columns task.

Verification Strategy:
1. Basic Checks: App running, screenshot exists.
2. VLM Verification (Primary): 
   - Check final screenshot for "Verification" and "Priority" column headers.
   - Check that SRS document is active.
3. VLM Trajectory (Secondary):
   - Verify agent interacted with column configuration (dialog or context menu).
"""

import json
import os
import logging
import tempfile
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt to verify the final state columns
FINAL_STATE_PROMPT = """
Examine this screenshot of the ReqView application.
1. Is the "SRS" document currently open (look for "SRS" in the tab or highlighted in the left tree)?
2. Look at the requirements table headers. Do you see a column labeled "Verification" (or "Verif")?
3. Do you see a column labeled "Priority"?
4. Are there requirement rows visible in the table?

Respond in JSON format:
{
    "srs_open": true/false,
    "verification_column_visible": true/false,
    "priority_column_visible": true/false,
    "table_content_visible": true/false,
    "visible_columns": ["list", "of", "columns", "seen"]
}
"""

# Prompt to verify the workflow/process
TRAJECTORY_PROMPT = """
Review these frames of the user's workflow in ReqView.
Did the user perform the following actions?
1. Right-click on a table header?
2. Open a "Select Columns" or configuration dialog?
3. Interact with checkboxes to enable columns?

Respond in JSON format:
{
    "opened_column_dialog": true/false,
    "interacted_with_headers": true/false,
    "description": "brief description of actions observed"
}
"""

def verify_configure_table_columns(traj, env_info, task_info):
    """Verify that Verification and Priority columns were configured to be visible."""
    
    # 1. Setup and retrieve basic result info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Read result JSON from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: App was running (10 pts)
    if result_data.get('app_was_running', False):
        score += 10
    else:
        feedback_parts.append("ReqView was not running at end of task")

    # 2. VLM Analysis - Final State (60 pts total)
    final_img = get_final_screenshot(traj)
    if not final_img:
        return {"passed": False, "score": score, "feedback": "No final screenshot available for verification"}

    vlm_state = query_vlm(
        prompt=FINAL_STATE_PROMPT,
        images=[final_img],
        model="gpt-4o" 
    )

    if not vlm_state.get('success'):
        feedback_parts.append("VLM verification failed to process screenshot")
    else:
        state_data = vlm_state.get('parsed', {})
        
        # Criterion: SRS Open (10 pts)
        if state_data.get('srs_open', False):
            score += 10
            feedback_parts.append("SRS document open")
        else:
            feedback_parts.append("SRS document not visible")

        # Criterion: Verification Column (25 pts)
        if state_data.get('verification_column_visible', False):
            score += 25
            feedback_parts.append("Verification column visible")
        else:
            feedback_parts.append("Verification column missing")

        # Criterion: Priority Column (25 pts)
        if state_data.get('priority_column_visible', False):
            score += 25
            feedback_parts.append("Priority column visible")
        else:
            feedback_parts.append("Priority column missing")

    # 3. VLM Analysis - Trajectory/Process (30 pts)
    # This ensures they didn't just start with a state that happened to have them,
    # or verifies they actually performed the configuration task.
    frames = sample_trajectory_frames(traj, n=6)
    vlm_traj = query_vlm(
        prompt=TRAJECTORY_PROMPT,
        images=frames,
        model="gpt-4o"
    )
    
    if vlm_traj.get('success'):
        traj_data = vlm_traj.get('parsed', {})
        if traj_data.get('opened_column_dialog', False) or traj_data.get('interacted_with_headers', False):
            score += 30
            feedback_parts.append("Column configuration workflow detected")
        else:
            feedback_parts.append("No column configuration interaction detected (did you perform the steps?)")
    
    # Final Scoring
    # Pass threshold: 60 pts (Need at least both columns visible + app running, or one column + trajectory)
    passed = score >= 60 and result_data.get('app_was_running', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_state": vlm_state.get('parsed'),
            "vlm_traj": vlm_traj.get('parsed'),
            "app_running": result_data.get('app_was_running')
        }
    }