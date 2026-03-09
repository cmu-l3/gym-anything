#!/usr/bin/env python3
"""
Verifier for audit_fleet_compliance_script task.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_fleet_compliance_script(traj, env_info, task_info):
    """
    Verify the agent wrote a working Django script to audit fleet compliance.
    
    Scoring:
    - Script file exists and looks valid (10)
    - Report file exists (10)
    - Report header present (5)
    - Total aircraft count matches DB (15)
    - Compliant count matches DB (20)
    - Non-compliant count matches DB (15)
    - Detail lines present (approx matching total count) (10)
    - Anti-gaming: Files created during task (5)
    - VLM: Verified coding/execution workflow (10)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    script = result.get('script', {})
    report = result.get('report', {})
    report_data = report.get('data', {})
    gt = result.get('ground_truth', {})
    
    # --- Check 1: Script File (10 pts) ---
    if script.get('exists'):
        if script.get('valid_content'):
            score += 10
            feedback.append("Script file exists with valid Django imports.")
        else:
            score += 5
            feedback.append("Script file exists but content check failed (missing imports?).")
    else:
        feedback.append("Script file '/home/ga/fleet_compliance_audit.py' not found.")
        
    # --- Check 2: Report File Existence (10 pts) ---
    if report.get('exists'):
        score += 10
        feedback.append("Report file generated.")
    else:
        feedback.append("Report file '/home/ga/fleet_compliance_report.txt' not found.")
        
    # --- Check 3: Report Structure (5 pts) ---
    if report_data.get('header_present'):
        score += 5
        feedback.append("Report header found.")
    else:
        feedback.append("Report missing 'COMPLIANCE' header.")
        
    # --- Check 4: Data Accuracy (50 pts total) ---
    # Total Count (15)
    agent_total = report_data.get('total_found')
    gt_total = gt.get('total', -1)
    
    if agent_total is not None and agent_total == gt_total:
        score += 15
        feedback.append(f"Total count matches ({agent_total}).")
    else:
        feedback.append(f"Total count mismatch (Agent: {agent_total}, Actual: {gt_total}).")
        
    # Compliant Count (20) - Allow +/- 1 tolerance for race conditions/parsing
    agent_comp = report_data.get('compliant_found')
    gt_comp = gt.get('compliant', -1)
    
    if agent_comp is not None and abs(agent_comp - gt_comp) <= 1:
        score += 20
        feedback.append(f"Compliant count matches ({agent_comp}).")
    elif agent_comp is not None:
        feedback.append(f"Compliant count incorrect (Agent: {agent_comp}, Actual: {gt_comp}).")
    else:
        feedback.append("Compliant count not found in report.")
        
    # Non-Compliant Count (15)
    agent_non = report_data.get('non_compliant_found')
    gt_non = gt.get('non_compliant', -1)
    
    if agent_non is not None and abs(agent_non - gt_non) <= 1:
        score += 15
        feedback.append(f"Non-compliant count matches ({agent_non}).")
    else:
        feedback.append(f"Non-compliant count incorrect (Agent: {agent_non}, Actual: {gt_non}).")
        
    # --- Check 5: Detail Lines (10 pts) ---
    # Expected detail lines should be roughly equal to total aircraft
    detail_lines = report_data.get('detail_lines_count', 0)
    if detail_lines >= max(1, gt_total - 2): # Allow slight parsing error
        score += 10
        feedback.append(f"Detail lines present ({detail_lines}).")
    else:
        feedback.append(f"Insufficient detail lines found ({detail_lines}, expected approx {gt_total}).")
        
    # --- Check 6: Anti-Gaming (5 pts) ---
    if script.get('created_during_task') and report.get('created_during_task'):
        score += 5
        feedback.append("Files verified as created during task session.")
    else:
        feedback.append("Timestamp check failed: Files may pre-date task start.")
        
    # --- Check 7: VLM Trajectory (10 pts) ---
    # We want to see evidence of coding (terminal/editor) and execution
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = """
        Review these screenshots of a user performing a scripting task.
        Look for:
        1. Code editing: A text editor or terminal open with Python code (look for 'import django', 'Aircraft', etc.).
        2. Execution: Running the script in a terminal (e.g., 'python fleet_compliance_audit.py').
        
        Return JSON:
        {
            "saw_coding": true/false,
            "saw_execution": true/false
        }
        """
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('saw_coding'):
                score += 5
                feedback.append("VLM verified coding activity.")
            if parsed.get('saw_execution'):
                score += 5
                feedback.append("VLM verified script execution.")
    else:
        # Fallback if VLM unavailable, give benefit of doubt if script exists and is correct
        if score >= 60:
            score += 10
            feedback.append("VLM skipped (passed logic checks).")
            
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }