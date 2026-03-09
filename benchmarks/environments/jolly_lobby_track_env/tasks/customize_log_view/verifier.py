#!/usr/bin/env python3
"""
Verifier for customize_log_view task in Jolly Lobby Track.

Verification Strategy:
1. VLM Analysis of Final Screenshot:
   - Check if the Visitor Log/Activity grid is visible.
   - Verify specific column headers are present: First Name, Last Name, Company, Time In.
   - Verify specific column headers are ABSENT: Email.
2. VLM Trajectory Analysis:
   - Confirm the agent opened a "Column Selection", "View Settings", or right-click context menu.
   - Confirm interaction with the "Email" option (unchecking/removing it).

Pass Threshold: 80/100 points
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

# Mock imports for the hypothetical framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback for development/testing without the framework
    def get_final_screenshot(traj): return traj.get('final_screenshot')
    def sample_trajectory_frames(traj, n): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_log_view(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the visitor log columns were correctly customized.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata
    metadata = task_info.get('metadata', {})
    required_cols = metadata.get('required_columns', ["First Name", "Last Name", "Company", "Time In"])
    forbidden_cols = metadata.get('forbidden_columns', ["Email"])

    # Load basic result info from container
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # Basic checks
    if not result.get('app_was_running', False):
        return {"passed": False, "score": 0, "feedback": "Lobby Track was not running at the end of the task."}

    # VLM Verification
    final_screenshot = get_final_screenshot(traj)
    trajectory_frames = sample_trajectory_frames(traj, n=5)
    
    if not final_screenshot:
        return {"passed": False, "score": 0, "feedback": "No final screenshot available for verification."}

    # 1. Verify Final State (Visible Columns)
    final_state_prompt = f"""
    You are verifying a UI customization task in a visitor management software.
    Look at the 'Visitor Log' or data grid in the screenshot.
    
    1. Are the following column headers VISIBLE in the grid?
       {', '.join(required_cols)}
       (Note: 'Time In' might be labeled 'Sign In Time' or 'Check In')
    
    2. Is the 'Email' column header VISIBLE? (It should be HIDDEN/REMOVED).
    
    3. Is the grid populated with data (not empty)?
    
    Respond in JSON:
    {{
        "visible_columns": ["col1", "col2", ...],
        "missing_required_columns": ["col_name", ...],
        "email_column_visible": true/false,
        "grid_has_data": true/false,
        "reasoning": "..."
    }}
    """
    
    vlm_final = query_vlm(prompt=final_state_prompt, images=[final_screenshot])
    
    if not vlm_final.get("success"):
        return {"passed": False, "score": 0, "feedback": "VLM analysis failed on final screenshot."}
        
    final_analysis = vlm_final.get("parsed", {})
    
    # 2. Verify Process (Trajectory)
    process_prompt = """
    Analyze these frames showing the user's workflow.
    Did the user open a menu to customize columns?
    Look for:
    - Right-clicking on a table header
    - A 'Select Columns' or 'Field Selection' dialog box
    - A 'View' menu
    - Unchecking/removing 'Email'
    
    Respond in JSON:
    {{
        "customization_menu_opened": true/false,
        "email_unchecked_or_removed": true/false,
        "reasoning": "..."
    }}
    """
    
    vlm_process = query_vlm(prompt=process_prompt, images=trajectory_frames)
    process_analysis = vlm_process.get("parsed", {}) if vlm_process.get("success") else {}

    # Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: App Running (10 pts)
    score += 10
    
    # Criterion 2: Navigation/Process (20 pts)
    if process_analysis.get("customization_menu_opened", False):
        score += 20
        feedback.append("Correctly accessed column customization settings.")
    else:
        feedback.append("Could not confirm usage of column customization menu.")

    # Criterion 3: Required Columns Visible (40 pts)
    missing_req = final_analysis.get("missing_required_columns", [])
    if not missing_req:
        score += 40
        feedback.append("All required columns are visible.")
    else:
        # Partial credit
        present_count = len(required_cols) - len(missing_req)
        points_per_col = 40 / len(required_cols)
        score += int(present_count * points_per_col)
        feedback.append(f"Missing required columns: {', '.join(missing_req)}.")

    # Criterion 4: Email Column Hidden (30 pts)
    if not final_analysis.get("email_column_visible", True):
        score += 30
        feedback.append("Email column successfully hidden.")
    else:
        feedback.append("Email column is still visible (FAILED constraint).")

    # Anti-gaming: Data check
    if not final_analysis.get("grid_has_data", True):
        score = min(score, 50) # Cap score if they just cleared the view or app is broken
        feedback.append("Warning: Visitor grid appears empty or broken.")

    # Final Pass/Fail
    # Must hide email AND show most columns to pass
    passed = score >= 80 and not final_analysis.get("email_column_visible", True)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "final_analysis": final_analysis,
            "process_analysis": process_analysis
        }
    }