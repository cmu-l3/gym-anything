#!/usr/bin/env python3
"""
Verifier for pediatric_simulation_profile task.

Verifies:
1. Programmatic: Devices created, app launched, report content (file checks).
2. Visual (VLM): Checks if specific numeric values (125, 28) appear on the screen,
   confirming the agent actually configured the simulation parameters.
"""

import json
import os
import tempfile
import re
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_pediatric_profile(traj, env_info, task_info):
    # 1. Setup & Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

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
    metadata = task_info.get('metadata', {})
    
    # Expected values
    exp_hr = str(metadata.get('expected_hr', 125))
    exp_rr = str(metadata.get('expected_rr', 28))
    exp_rate = str(metadata.get('expected_infusion_rate', 10))

    # --- Criteria 1: Simulation Infrastructure (30 pts) ---
    if result.get('monitor_created', False):
        score += 10
        feedback.append("Multiparameter Monitor created.")
    else:
        feedback.append("FAIL: Multiparameter Monitor not found.")

    if result.get('pump_created', False):
        score += 10
        feedback.append("Infusion Pump created.")
    else:
        feedback.append("FAIL: Infusion Pump not found.")

    if result.get('app_launched', False):
        score += 10
        feedback.append("Vital Signs app launched.")
    else:
        feedback.append("FAIL: Vital Signs app not found.")

    # --- Criteria 2: Reporting & Evidence File (20 pts) ---
    report_content = result.get('report_content', "")
    if result.get('report_exists', False):
        score += 10
        feedback.append("Configuration report created.")
        
        # Check report content for numbers
        found_values = []
        if re.search(fr"\b{exp_hr}\b", report_content): found_values.append("HR")
        if re.search(fr"\b{exp_rr}\b", report_content): found_values.append("RR")
        if re.search(fr"\b{exp_rate}\b", report_content): found_values.append("Rate")
        
        if len(found_values) >= 2: # Found at least 2 of the specific numbers
            score += 10
            feedback.append(f"Report correctly lists configured values: {', '.join(found_values)}.")
        else:
            feedback.append(f"Report missing specific target values ({exp_hr}, {exp_rr}, {exp_rate}).")
    else:
        feedback.append("FAIL: Configuration report missing.")

    if result.get('evidence_exists', False):
        score += 5 # Bonus 5 for following instruction to take screenshot
        feedback.append("Agent-generated evidence screenshot found.")

    # --- Criteria 3: VLM Visual Verification of Parameters (45 pts) ---
    # This is the core check: Did they actually change the numbers?
    final_img = get_final_screenshot(traj)
    if final_img:
        prompt = f"""
        Analyze this screen of a medical dashboard. 
        I am looking for specific vital sign values:
        1. Heart Rate: {exp_hr}
        2. Respiratory Rate: {exp_rr}
        
        Can you see the number '{exp_hr}' clearly displayed (likely green or red)?
        Can you see the number '{exp_rr}' clearly displayed (likely white or yellow)?
        
        Answer JSON: {{ "hr_visible": true/false, "rr_visible": true/false }}
        """
        
        vlm_res = query_vlm(prompt=prompt, image=final_img)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            hr_vis = parsed.get('hr_visible', False)
            rr_vis = parsed.get('rr_visible', False)
            
            if hr_vis:
                score += 25
                feedback.append(f"VLM verified Heart Rate {exp_hr} is active on screen.")
            else:
                feedback.append(f"VLM could NOT find Heart Rate {exp_hr} on screen.")
                
            if rr_vis:
                score += 20
                feedback.append(f"VLM verified Resp Rate {exp_rr} is active on screen.")
            else:
                feedback.append(f"VLM could NOT find Resp Rate {exp_rr} on screen.")
        else:
            feedback.append("VLM analysis failed.")
    else:
        feedback.append("No final screenshot available for VLM analysis.")

    # --- Final Scoring ---
    passed = score >= 60 and result.get('monitor_created', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }