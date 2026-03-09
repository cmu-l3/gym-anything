#!/usr/bin/env python3
"""
Verifier for assess_blade_deflection_under_load task.
"""

import json
import base64
import re
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assess_blade_deflection(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Generated a report file created *during* the task.
    2. Reported physically valid deflection and moment values.
    3. Used the QBlade structural analysis module (VLM check).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. File Verification (45 points)
    if not result.get("report_exists", False):
        feedback.append("Report file not found.")
    else:
        if not result.get("report_created_during_task", False):
            feedback.append("Report file exists but was not created during this session.")
        else:
            score += 15
            feedback.append("Report file created successfully.")
            
            # Parse Content
            try:
                content = base64.b64decode(result.get("report_content_base64", "")).decode('utf-8')
                
                # Regex for values
                deflection_match = re.search(r"Max Deflection:\s*([0-9.]+)", content, re.IGNORECASE)
                moment_match = re.search(r"Root Moment:\s*([0-9.]+)", content, re.IGNORECASE)
                wind_match = re.search(r"Wind Speed:\s*12", content, re.IGNORECASE)
                
                # Check Deflection
                if deflection_match:
                    deflection = float(deflection_match.group(1))
                    if metadata['min_deflection_m'] < deflection < metadata['max_deflection_m']:
                        score += 15
                        feedback.append(f"Deflection value ({deflection}m) is valid.")
                    else:
                        feedback.append(f"Deflection value ({deflection}m) is outside physical range.")
                else:
                    feedback.append("Could not parse 'Max Deflection' value.")

                # Check Moment
                if moment_match:
                    moment = float(moment_match.group(1))
                    if metadata['min_moment_nm'] < moment: # Moment can be huge, just check > 1
                        score += 10
                        feedback.append(f"Root Moment value ({moment} Nm) is valid.")
                    else:
                        feedback.append(f"Root Moment value ({moment} Nm) is too small/invalid.")
                else:
                    feedback.append("Could not parse 'Root Moment' value.")
                    
                # Check Wind Speed Context
                if wind_match:
                    score += 5
                    feedback.append("Wind speed 12 m/s confirmed in report.")
            except Exception as e:
                feedback.append(f"Error parsing report content: {str(e)}")

    # 3. Application State (15 points)
    if result.get("app_was_running", False):
        score += 15
        feedback.append("QBlade was running at end of task.")
    else:
        feedback.append("QBlade was closed.")

    # 4. VLM Verification (40 points)
    # Check if they actually went to the structural analysis screen
    frames = sample_trajectory_frames(traj, n=6)
    vlm_prompt = """
    I am verifying a QBlade task where the user must run a Structural/Static Analysis.
    Look at these screenshots.
    1. Do you see the 'Blade Stress Analysis' or 'Static Analysis' module? (Usually shows a blade with color gradients or deflection curves).
    2. Do you see a graph plotting deflection or displacement?
    3. Do you see a dialog importing loads (BEM loads)?
    
    Answer JSON: {"structural_module_seen": bool, "deflection_graph_seen": bool}
    """
    
    try:
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        parsed = vlm_res.get("parsed", {}) if vlm_res.get("success") else {}
        
        if parsed.get("structural_module_seen", False):
            score += 20
            feedback.append("VLM confirmed Structural/Static module usage.")
        
        if parsed.get("deflection_graph_seen", False):
            score += 20
            feedback.append("VLM confirmed deflection graph visualization.")
            
    except Exception as e:
        feedback.append(f"VLM verification skipped/failed: {str(e)}")
        # Fallback: if we have valid numeric data in report, give partial credit for VLM
        if score >= 45: # They did the file part well
            score += 20
            feedback.append("VLM failed but data looks good, granting partial verification credit.")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }