#!/usr/bin/env python3
"""
Verifier for verify_gui_api_hr_peak task.

Criteria:
1. Python script exists and uses vitaldb (20 pts)
2. Report file exists and follows format (10 pts)
3. API Computed Peak matches Ground Truth (30 pts)
4. GUI Observed Peak is within tolerance of Ground Truth (20 pts)
5. Screenshot exists (10 pts)
6. VitalDB library was installed (10 pts)
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_gui_api_hr_peak(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata defaults (Case 6 Ground Truth ~105 BPM typically, but varies by segment. 
    # The setup script tries to calc dynamic truth, we use metadata as fallback).
    metadata = task_info.get('metadata', {})
    fallback_gt = metadata.get('ground_truth_peak_hr', 105.0) 
    tolerance = metadata.get('tolerance_bpm', 2.0)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. VitalDB Library Installed (10 pts)
    if result.get('lib_installed', False):
        score += 10
        feedback.append("Library 'vitaldb' installed.")
    else:
        feedback.append("Library 'vitaldb' NOT detected.")

    # 2. Script Analysis (20 pts)
    script_content = result.get('script_content', "")
    if result.get('script_exists', False):
        if "vitaldb" in script_content and "Solar8000/HR" in script_content:
            score += 20
            feedback.append("Python script valid.")
        else:
            score += 10
            feedback.append("Python script exists but missing keywords.")
    else:
        feedback.append("Python script missing.")

    # 3. Screenshot (10 pts)
    if result.get('screenshot_exists', False):
        score += 10
        feedback.append("Screenshot provided.")
    else:
        feedback.append("Screenshot missing.")

    # 4. Report & Values (10 pts for report + 50 pts for accuracy)
    report_content = result.get('report_content', "")
    ground_truth = fallback_gt
    
    # Try to use dynamically calculated ground truth from agent env
    try:
        calc_gt = float(result.get('ground_truth_calc', 0))
        if calc_gt > 50: # Sanity check
            ground_truth = calc_gt
    except:
        pass

    api_val = None
    gui_val = None
    
    if result.get('report_exists', False):
        score += 10
        feedback.append("Report file exists.")
        
        # Parse Report
        # Expected: "GUI Observed Peak: 105", "API Computed Peak: 105.2"
        gui_match = re.search(r"GUI.*?:\s*([\d\.]+)", report_content, re.IGNORECASE)
        api_match = re.search(r"API.*?:\s*([\d\.]+)", report_content, re.IGNORECASE)
        
        if gui_match:
            try:
                gui_val = float(gui_match.group(1))
            except: pass
            
        if api_match:
            try:
                api_val = float(api_match.group(1))
            except: pass
            
        # Verify API Value (30 pts)
        # API should be exact matching
        if api_val is not None:
            if abs(api_val - ground_truth) < 0.01:
                score += 30
                feedback.append(f"API value accurate ({api_val}).")
            else:
                feedback.append(f"API value incorrect (Expected {ground_truth}, Got {api_val}).")
        else:
            feedback.append("Could not parse API value.")

        # Verify GUI Value (20 pts)
        # GUI allows tolerance
        if gui_val is not None:
            if abs(gui_val - ground_truth) <= tolerance:
                score += 20
                feedback.append(f"GUI value accurate ({gui_val}).")
            else:
                feedback.append(f"GUI value outside tolerance (Expected ~{ground_truth}, Got {gui_val}).")
        else:
            feedback.append("Could not parse GUI value.")
            
    else:
        feedback.append("Report file missing.")

    # Pass Threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }