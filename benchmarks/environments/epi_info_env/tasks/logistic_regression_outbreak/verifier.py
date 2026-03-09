#!/usr/bin/env python3
"""
Verifier for logistic_regression_outbreak task.

VERIFICATION STRATEGY:
1. File Verification: Check existence and creation time of HTML output and text report.
2. Content Verification: 
   - HTML: Must contain "Logistic Regression" and "Odds Ratio".
   - Report: Must identify "Vanilla" (ice cream) and report OR > 5.0.
3. VLM Verification: Use trajectory to confirm user interaction with Epi Info Analysis module.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_logistic_regression(traj, env_info, task_info):
    """
    Verify logistic regression task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: The export script saves to C:\Temp\task_result.json in the container
        # copy_from_env handles the path mapping logic
        copy_from_env("C:\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Analyze HTML Output (30 points)
    html_exists = result.get('html_exists', False)
    html_fresh = result.get('html_created_during_task', False)
    html_snippet = result.get('html_snippet', "").lower()
    
    if html_exists and html_fresh:
        score += 10
        feedback_parts.append("Regression output file created.")
        
        # Check content keywords
        if "logistic" in html_snippet and "odds ratio" in html_snippet:
            score += 20
            feedback_parts.append("Output contains logistic regression results.")
        elif "regression" in html_snippet:
            score += 10
            feedback_parts.append("Output appears to be a regression analysis.")
        else:
            feedback_parts.append("Output file content unclear.")
    elif html_exists:
        score += 5
        feedback_parts.append("Output file exists but was not created during task (stale?).")
    else:
        feedback_parts.append("Logistic regression HTML output not found.")

    # 3. Analyze Report Content (40 points)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "").lower()
    
    if report_exists:
        score += 10
        feedback_parts.append("Summary report created.")
        
        # Check for key findings
        # Expecting 'vanilla' and high odds ratio
        if "vanilla" in report_content:
            score += 10
            feedback_parts.append("Report correctly identifies Vanilla ice cream.")
            
            # Extract number to check OR magnitude
            # Look for numbers near "vanilla" or "OR"
            # Simple check: is there a number > 5.0?
            numbers = [float(s) for s in re.findall(r'-?\d+\.?\d*', report_content)]
            high_or_found = any(n > 5.0 and n < 100.0 for n in numbers)
            
            if high_or_found:
                score += 20
                feedback_parts.append("Reported Odds Ratio seems valid (> 5.0).")
            else:
                score += 5
                feedback_parts.append("Reported statistics may be incorrect (expected OR > 5.0).")
        else:
            feedback_parts.append("Report failed to identify 'Vanilla' as the key risk factor.")
    else:
        feedback_parts.append("Summary report not found.")

    # 4. VLM Verification (30 points)
    # Check if agent actually used the software interface
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots of Epi Info 7 software usage.
        1. Is the 'Classic Analysis' or 'Visual Dashboard' window visible?
        2. Is there a command output window showing statistical results?
        3. Do you see a 'Logistic Regression' or 'LOGISTIC' command being executed or displayed?
        
        Reply with JSON: {"analysis_module_visible": bool, "regression_command_seen": bool}
        """
        
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('analysis_module_visible', False):
            score += 15
            feedback_parts.append("VLM confirmed Analysis module usage.")
            if parsed.get('regression_command_seen', False):
                score += 15
                feedback_parts.append("VLM confirmed Logistic Regression command.")
        else:
            feedback_parts.append("VLM could not verify software usage.")
    else:
        # Fallback if no frames (should not happen in real run)
        feedback_parts.append("No trajectory frames for VLM verification.")

    # 5. Final Scoring
    # Pass threshold: 60 points + Key output
    passed = score >= 60 and html_exists and "vanilla" in report_content
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }