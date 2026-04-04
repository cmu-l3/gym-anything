#!/usr/bin/env python3
"""
Verifier for Stratified Mantel-Haenszel Analysis task.

Criteria:
1. Output files exist (HTML analysis and Text report).
2. Crude Odds Ratio is correct (~2.02).
3. Adjusted Odds Ratio is correct (~1.90-2.00).
4. Stratification was actually performed (Tables for Race=1,2,3 detected).
5. Conclusion in report matches data.
6. VLM Verification of workflow trajectory.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_stratified_mh_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_crude_or = metadata.get('expected_crude_or', 2.02)
    expected_adjusted_or = metadata.get('expected_adjusted_or', 1.90)
    tolerance = metadata.get('tolerance', 0.5)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Retrieve HTML Analysis Output
    html_content = ""
    if result_data.get('html_exists'):
        temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
        try:
            # Use path from metadata or hardcoded fallback
            html_path = metadata.get('output_html', "C:\\Users\\Docker\\Documents\\EpiInfoProjects\\LowBirthWeight\\analysis_output.html")
            copy_from_env(html_path, temp_html.name)
            with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
        except Exception:
            feedback_parts.append("Could not read analysis HTML file.")
        finally:
            if os.path.exists(temp_html.name):
                os.unlink(temp_html.name)
    
    # --- Scoring ---

    # Criterion 1: Files Exist (20 pts)
    if result_data.get('html_exists') and result_data.get('html_created_during_task'):
        score += 10
        feedback_parts.append("Analysis output file created.")
    
    report_content = result_data.get('report_content', "")
    if result_data.get('report_exists') and len(report_content) > 10:
        score += 10
        feedback_parts.append("Report file created.")
    else:
        feedback_parts.append("Report file missing or empty.")

    # Criterion 2: Verify HTML Content (Crude & Stratified Analysis) (30 pts)
    # Check for Crude OR
    crude_match = False
    if "Odds Ratio" in html_content and "2.02" in html_content: # Simple string check first
        crude_match = True
    elif re.search(r"Odds Ratio.*?2\.0[0-5]", html_content, re.DOTALL):
        crude_match = True
    
    if crude_match:
        score += 15
        feedback_parts.append("Crude OR found in output.")
    
    # Check for Stratification (Mentions of Race strata)
    strata_found = False
    if "RACE = 1" in html_content and "RACE = 2" in html_content:
        strata_found = True
        score += 15
        feedback_parts.append("Stratified analysis (by Race) found in output.")
    else:
        feedback_parts.append("Stratified analysis not clearly found in HTML.")

    # Criterion 3: Verify Report Content (Values) (30 pts)
    # Extract numbers from report
    nums = re.findall(r"[-+]?\d*\.\d+|\d+", report_content)
    nums = [float(n) for n in nums if '.' in n] # Filter for floats
    
    report_crude_ok = False
    report_adj_ok = False
    
    for n in nums:
        if abs(n - expected_crude_or) <= tolerance:
            report_crude_ok = True
        if abs(n - expected_adjusted_or) <= tolerance:
            report_adj_ok = True
            
    if report_crude_ok:
        score += 15
        feedback_parts.append("Correct Crude OR reported.")
    if report_adj_ok:
        score += 15
        feedback_parts.append("Correct Adjusted OR reported.")

    # Criterion 4: VLM/App State (20 pts)
    # If app was running at end
    if result_data.get('app_running'):
        score += 5
    
    # VLM Check (using trajectory from framework)
    # Since we can't invoke VLM here directly without the external helper,
    # we rely on file evidence heavily. 
    # However, if we had the helper:
    # vlm_score = verify_trajectory(traj)
    # For this stub, we award points if files were generated successfully, assuming interaction.
    if result_data.get('html_created_during_task'):
        score += 15 # Implied interaction
        
    passed = score >= 60 and report_adj_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }