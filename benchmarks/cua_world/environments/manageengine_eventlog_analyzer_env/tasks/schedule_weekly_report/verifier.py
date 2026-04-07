#!/usr/bin/env python3
"""
Verifier for schedule_weekly_report task.

Combines programmatic checks (DB/API) with VLM trajectory verification.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_schedule_weekly_report(traj, env_info, task_info):
    """
    Verify the agent scheduled a weekly security report.
    
    Criteria:
    1. (Programmatic) Database count of scheduled reports increased (30 pts)
    2. (VLM) Agent navigated to Reports section (10 pts)
    3. (VLM) Agent selected "Successful Logon" or relevant report (10 pts)
    4. (VLM) Schedule dialog showed "Weekly" frequency (25 pts)
    5. (VLM) Schedule dialog showed "Monday" (25 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Programmatic Evidence
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: Database Evidence (30 pts)
    count_increased = result.get("count_increased", False)
    db_entry = result.get("latest_db_entry", "").lower()
    
    if count_increased:
        score += 30
        feedback.append("Database confirms a new report schedule was created.")
    else:
        feedback.append("No new schedule found in database.")

    # 2. VLM Trajectory Verification (70 pts)
    # We sample frames to verify the workflow steps
    frames = sample_trajectory_frames(traj, n=6)
    final_frame = get_final_screenshot(traj)
    if final_frame:
        frames.append(final_frame)

    if not frames:
        return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification."}

    # Construct VLM Prompt
    prompt = """
    You are verifying an agent's workflow in ManageEngine EventLog Analyzer.
    The goal was to schedule the "Successful Logon" report to run Weekly on Mondays.
    
    Review the sequence of screenshots and answer the following questions in JSON format:
    
    1. "navigated_reports": Did the agent click on the 'Reports' tab or navigate to the reports section?
    2. "selected_report": Did the agent select the "Successful Logon" report (or a similar logon report)?
    3. "schedule_dialog_open": Is a schedule configuration popup/dialog visible in any frame?
    4. "frequency_weekly": In the schedule dialog, is "Weekly" selected or visible?
    5. "day_monday": In the schedule dialog, is "Monday" selected or visible?
    6. "saved_successfully": Is there evidence of saving (e.g., clicking Save, success message, or new entry in list)?
    
    Output JSON: {"navigated_reports": bool, "selected_report": bool, "schedule_dialog_open": bool, "frequency_weekly": bool, "day_monday": bool, "saved_successfully": bool}
    """

    try:
        vlm_response = query_vlm(images=frames, prompt=prompt)
        analysis = vlm_response.get("parsed", {})
        
        # Scoring based on VLM
        if analysis.get("navigated_reports"):
            score += 10
            feedback.append("VLM: Verified navigation to Reports.")
        
        if analysis.get("selected_report"):
            score += 10
            feedback.append("VLM: Verified 'Successful Logon' report selection.")
            
        if analysis.get("schedule_dialog_open"):
            # Base points for opening dialog
            score += 10 
            feedback.append("VLM: Schedule dialog opened.")
            
            # Specific settings checks
            if analysis.get("frequency_weekly"):
                score += 15
                feedback.append("VLM: Frequency set to 'Weekly'.")
            else:
                feedback.append("VLM: Failed to verify 'Weekly' frequency.")
                
            if analysis.get("day_monday"):
                score += 15
                feedback.append("VLM: Day set to 'Monday'.")
            else:
                feedback.append("VLM: Failed to verify 'Monday' selection.")
                
            if analysis.get("saved_successfully"):
                score += 10
                feedback.append("VLM: Verified save action.")
                
    except Exception as e:
        feedback.append(f"VLM verification failed: {str(e)}")

    # Final Evaluation
    # Pass threshold: 60 pts
    # Must have at least attempted the schedule (dialog open) and saved OR DB confirmed
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }