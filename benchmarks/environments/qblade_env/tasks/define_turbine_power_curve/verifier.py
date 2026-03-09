#!/usr/bin/env python3
"""
Verifier for QBlade Turbine Power Curve Task.

Checks:
1. Project file saved, reasonable size, created during task.
2. Report file saved with plausible physical values for NREL 5MW turbine.
3. VLM trajectory verification of the power curve graph.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("verifier")

def verify_turbine_power_curve(traj, env_info, task_info):
    """
    Verify the turbine simulation task.
    """
    # 1. Setup access to container files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy functionality missing"}

    # 2. Retrieve metadata constraints
    metadata = task_info.get('metadata', {})
    ranges = metadata.get('ranges', {})
    
    # 3. Load the result JSON exported from the container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task results: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # --- Check 1: Project File (30 pts) ---
    proj = result.get('project_file', {})
    if proj.get('exists'):
        if proj.get('modified_during_task'):
            # Size check: A project with a full turbine sim is usually > 50KB-100KB
            if proj.get('size_bytes', 0) > 50000:
                score += 30
                feedback.append("Project file saved correctly with data.")
            else:
                score += 15
                feedback.append(f"Project file saved but seems small ({proj.get('size_bytes')} bytes). Simulation data might be missing.")
        else:
            feedback.append("Project file exists but was not modified during the task (anti-gaming).")
    else:
        feedback.append("Project file (.wpa) not found.")

    # --- Check 2: Report Content (40 pts) ---
    report = result.get('report_file', {})
    if report.get('exists') and report.get('modified_during_task'):
        content = report.get('content_snippet', '')
        
        # Extract numbers using regex
        # Look for floating point numbers
        numbers = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", content)]
        
        valid_power = False
        valid_cp = False
        valid_speed = False
        
        # Heuristic check for plausible values
        # NREL 5MW is ~5000 kW (or 5 MW)
        # Cp max is usually ~0.45 - 0.50
        # Rated speed is ~11.4 m/s
        
        for n in numbers:
            # Check Power (kW or MW)
            if (ranges['max_power_kw_min'] <= n <= ranges['max_power_kw_max']) or (1.0 <= n <= 10.0): # 1-10 MW
                valid_power = True
            
            # Check Cp
            if ranges['max_cp_min'] <= n <= ranges['max_cp_max']:
                valid_cp = True
                
            # Check Rated Speed
            if ranges['rated_speed_min'] <= n <= ranges['rated_speed_max']:
                valid_speed = True
        
        report_score = 10 # Base for existence
        if valid_power: report_score += 10
        if valid_cp: report_score += 10
        if valid_speed: report_score += 10
        
        score += report_score
        feedback.append(f"Report analysis: Power={'OK' if valid_power else '?'}, Cp={'OK' if valid_cp else '?'}, Speed={'OK' if valid_speed else '?'}.")
    else:
        feedback.append("Report file missing or not modified.")

    # --- Check 3: VLM Verification (30 pts) ---
    # We want to check if they actually generated the graph
    
    # Import VLM utils provided by framework
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if not frames:
        feedback.append("No screenshots available for visual verification.")
    else:
        prompt = (
            "You are verifying a QBlade wind turbine simulation task. "
            "Look for the following in these screenshots:\n"
            "1. The 'Turbine BEM Simulation' module (or similar interface).\n"
            "2. A Power Curve graph (Line graph showing Power vs Wind Speed). usually S-shaped or ramping up then flat.\n"
            "3. Any dialog showing simulation parameters (Cut-in, Cut-out).\n\n"
            "Does the agent appear to have successfully generated a power curve graph?"
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            # Assuming VLM returns simple structure or we parse the text
            # For this template, we assume the VLM returns a boolean 'yes/no' or similar in text
            # Ideally the framework parses this into structured data.
            # We will use a keyword heuristic on the raw response if parsed isn't specific
            response_text = str(vlm_res).lower()
            
            if "yes" in response_text or "true" in response_text:
                score += 30
                feedback.append("Visual verification passed: Power curve graph detected.")
            else:
                feedback.append("Visual verification inconclusive or failed.")
        else:
            # Fallback if VLM fails: check if app was running and we have partial score
            if result.get('app_running') and score > 40:
                score += 10
                feedback.append("VLM unavailable, adding fallback points for running app.")

    # Final Evaluation
    passed = score >= 60 and result.get('project_file', {}).get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }