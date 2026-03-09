#!/usr/bin/env python3
"""
Verifier for VAWT Self-Start Assessment Task.

Evaluates:
1. File Creation: Checks if .wpa project and .txt report were created during task.
2. Content Validation: Parses the report for physically plausible values (Solidity, Cp).
3. VLM Verification: Uses trajectory to verify the workflow (Polar extrapolation, VAWT design, Simulation).
"""

import json
import os
import re
import math
import tempfile
import logging
from typing import Dict, Any, List

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils from framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback for testing/standalone
    def query_vlm(**kwargs):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5):
        return []

def verify_vawt_self_start(traj, env_info, task_info):
    """
    Main verification entry point.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # 1. Load results from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    project_exists = result_data.get('project_exists', False)
    project_valid_time = result_data.get('project_created_during_task', False)
    project_size = result_data.get('project_size_bytes', 0)
    
    report_exists = result_data.get('report_exists', False)
    report_valid_time = result_data.get('report_created_during_task', False)
    report_content = result_data.get('report_content', "")

    metadata = task_info.get('metadata', {})
    ranges = metadata.get('physics_ranges', {})

    score = 0
    feedback = []

    # --- CRITERION 1: Project File (30 pts) ---
    if project_exists and project_valid_time and project_size > 1000:
        score += 30
        feedback.append("Project file saved successfully.")
    elif project_exists:
        score += 10
        feedback.append("Project file exists but timestamp/size is suspicious.")
    else:
        feedback.append("Project file not found.")

    # --- CRITERION 2: Report Existence (10 pts) ---
    if report_exists and report_valid_time:
        score += 10
        feedback.append("Report file created.")
    else:
        feedback.append("Report file missing.")

    # --- CRITERION 3: Report Content Parsing (30 pts) ---
    # Expected Solidity: N*c / (2*pi*R) = 3*0.2 / (2*pi*1.5) = 0.6 / 9.4247 ≈ 0.06366
    expected_solidity = 0.06366
    
    parsed_values = parse_report(report_content)
    
    # Check Solidity
    solidity = parsed_values.get('solidity')
    if solidity is not None:
        if 0.05 <= solidity <= 0.08:
            score += 10
            feedback.append(f"Solidity calculated correctly ({solidity}).")
        else:
            feedback.append(f"Solidity value {solidity} is outside expected range (approx 0.064).")
    else:
        feedback.append("Could not parse solidity from report.")

    # Check Max Cp (Physical plausibility)
    cp_max = parsed_values.get('cp_max')
    if cp_max is not None:
        if ranges.get('cp_max_min', 0.1) <= cp_max <= ranges.get('cp_max_max', 0.55):
            score += 10
            feedback.append(f"Max Cp value ({cp_max}) is physically plausible.")
        else:
            feedback.append(f"Max Cp {cp_max} seems unrealistic for this rotor.")
    else:
        feedback.append("Could not parse Max Cp from report.")

    # Check Self-Starting Assessment presence
    if parsed_values.get('assessment_found'):
        score += 10
        feedback.append("Self-starting assessment provided.")
    else:
        feedback.append("Self-starting assessment (YES/NO) missing.")

    # --- CRITERION 4: VLM Trajectory Verification (30 pts) ---
    # We check the trajectory frames for evidence of the QBlade workflow
    vlm_score = 0
    vlm_feedback = ""
    
    frames = sample_trajectory_frames(traj, n=5)
    
    if frames:
        prompt = """
        You are verifying a user's workflow in the wind turbine software QBlade.
        Look at these screenshots and identify if the following steps were performed:
        
        1. **Airfoil/Polar Generation**: Is there a screen showing airfoil curves (polar diagrams) or the "XFoil Direct Design" module? Crucially, is there a 360-degree extrapolation visible (a polar that goes all the way around 360 degrees)?
        2. **VAWT Rotor Design**: Is there a screen showing a Vertical Axis Wind Turbine (looks like an eggbeater or H-rotor, vertical blades)?
        3. **DMS Simulation**: Is there a simulation graph showing Power Coefficient (Cp) vs Tip Speed Ratio (TSR/Lambda)?
        
        Return JSON:
        {
            "polar_extrapolation_visible": boolean,
            "vawt_rotor_visible": boolean,
            "simulation_graph_visible": boolean,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            analysis = vlm_res.get('parsed', {})
            
            if analysis.get('vawt_rotor_visible'):
                vlm_score += 10
                vlm_feedback += "VAWT rotor design detected. "
            else:
                vlm_feedback += "VAWT rotor design NOT detected. "
                
            if analysis.get('simulation_graph_visible'):
                vlm_score += 10
                vlm_feedback += "Simulation results detected. "
            else:
                vlm_feedback += "Simulation results NOT detected. "
                
            if analysis.get('polar_extrapolation_visible'):
                vlm_score += 10
                vlm_feedback += "Polar extrapolation detected. "
            else:
                vlm_feedback += "Polar extrapolation NOT detected. "
        else:
            # Fallback if VLM fails: give partial credit if files exist
            logger.warning("VLM query failed, falling back to file heuristics")
            if project_exists and report_exists:
                vlm_score = 15
                vlm_feedback = "VLM failed; partial credit based on files."
    else:
        vlm_feedback = "No trajectory frames available for VLM."

    score += vlm_score
    feedback.append(f"Visual Verification: {vlm_feedback}")

    # Final Result
    passed = (score >= 60) and project_exists and report_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }

def parse_report(content: str) -> Dict[str, Any]:
    """
    Parses the student report text file for key values.
    """
    result = {
        'assessment_found': False,
        'solidity': None,
        'cp_max': None,
        'opt_tsr': None
    }
    
    if not content:
        return result

    # Normalize content
    content_lower = content.lower()
    
    # Check for YES/NO assessment
    if "yes" in content_lower or "no" in content_lower:
        result['assessment_found'] = True
        
    # Extract Solidity (look for number after 'solidity')
    # Regex looks for "solidity" followed by optional delimiters and a float
    sol_match = re.search(r'solidity.*:?\s*([0-9]*\.?[0-9]+)', content_lower)
    if sol_match:
        try:
            result['solidity'] = float(sol_match.group(1))
        except ValueError:
            pass

    # Extract Cp
    cp_match = re.search(r'cp.*:?\s*([0-9]*\.?[0-9]+)', content_lower)
    if cp_match:
        try:
            val = float(cp_match.group(1))
            # Filter out TSR values if they got confused (Cp usually < 1)
            if val < 1.0: 
                result['cp_max'] = val
        except ValueError:
            pass
            
    return result