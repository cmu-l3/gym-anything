#!/usr/bin/env python3
"""
Verifier for QBlade Camber Effect L/D Study task.
Checks report content for physical plausibility and workflow completion.
"""

import json
import base64
import re
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_camber_effect_ld_study(traj, env_info, task_info):
    """
    Verifies the camber study task.
    
    Criteria:
    1. Report file exists and follows structure.
    2. All 4 required airfoils (0015, 2415, 4415, 6415) are listed.
    3. Reported L/D max values are physically plausible for Re=500k.
    4. "Best Airfoil" conclusion is consistent with the data provided.
    5. Project file exists and is not empty.
    6. VLM confirms UI workflow (Analysis/Polars view visited).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: Copy function missing"}

    metadata = task_info.get('metadata', {})
    physics_ranges = metadata.get('physics_ranges', {})
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 2. Verify Project File (20 points)
    proj_info = result_data.get('project', {})
    if proj_info.get('exists') and proj_info.get('created_during_task'):
        if proj_info.get('size_bytes', 0) > 5000: # 5KB min for non-empty project
            score += 20
            feedback.append("Project file saved correctly.")
        else:
            score += 5
            feedback.append("Project file saved but appears too small (empty?).")
    else:
        feedback.append("Project file not found or not created during task.")

    # 3. Verify Report Content (60 points)
    report_info = result_data.get('report', {})
    if not report_info.get('exists'):
        return {"passed": False, "score": score, "feedback": "Report file missing. " + " ".join(feedback)}

    try:
        content_b64 = report_info.get('content_b64', "")
        report_text = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to decode report: {str(e)}"}

    # Parse Report
    airfoils_found = {}
    lines = report_text.splitlines()
    best_airfoil_claim = None
    
    # Regex for lines like "NACA 2415: L/D_max = 85.5, ..."
    # Allow flexible formatting
    pattern = re.compile(r"NACA\s*(\d{4}).*L/D.*[=:]\s*([0-9.]+)", re.IGNORECASE)
    
    for line in lines:
        match = pattern.search(line)
        if match:
            code = match.group(1)
            val = float(match.group(2))
            airfoils_found[code] = val
        
        if "BEST" in line.upper() and "NACA" in line.upper():
            # Try to extract the code of the best airfoil
            best_match = re.search(r"NACA\s*(\d{4})", line, re.IGNORECASE)
            if best_match:
                best_airfoil_claim = best_match.group(1)

    # Check existence of required airfoils (10 pts)
    required = ["0015", "2415", "4415", "6415"]
    missing = [req for req in required if req not in airfoils_found]
    
    if not missing:
        score += 10
        feedback.append("All 4 airfoils reported.")
    else:
        feedback.append(f"Missing airfoils in report: {', '.join(missing)}.")

    # Check Physical Plausibility (30 pts)
    # L/D max at Re=500k usually: 0015(~40-50), 2415(~60-80), 4415(~80-100), 6415(~70-90)
    plausible_count = 0
    for code, val in airfoils_found.items():
        if code in physics_ranges:
            r = physics_ranges[code]
            if r['min'] <= val <= r['max']:
                plausible_count += 1
            else:
                feedback.append(f"NACA {code} value {val} out of expected range ({r['min']}-{r['max']}).")
    
    if len(airfoils_found) > 0:
        score += int(30 * (plausible_count / len(airfoils_found)))
        if plausible_count == len(airfoils_found):
            feedback.append("All reported values are physically plausible.")

    # Check Conclusion Consistency (10 pts)
    if best_airfoil_claim:
        # Find the max value in the reported data
        if airfoils_found:
            max_code = max(airfoils_found, key=airfoils_found.get)
            if best_airfoil_claim == max_code:
                score += 10
                feedback.append(f"Correctly identified {best_airfoil_claim} as having highest L/D.")
            else:
                feedback.append(f"Claimed BEST is {best_airfoil_claim}, but data shows {max_code} is higher.")
        else:
            feedback.append("Cannot verify best airfoil (no data parsed).")
    
    # Check Physics Logic (10 pts) - Cambered should beat Symmetric
    # Specifically, 4415 or 6415 is usually best at this Re
    if best_airfoil_claim in ["4415", "6415"]:
        score += 10
        feedback.append("Conclusion matches aerodynamic theory (cambered airfoil wins).")
    elif best_airfoil_claim == "0015":
        feedback.append("NACA 0015 is unlikely to be the best for L/D at this Re.")

    # 4. VLM Verification (20 points)
    # Sample trajectory to ensure they actually ran the simulation
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "These are screenshots of QBlade software during a task. "
            "The user should be generating airfoils and running XFOIL analysis. "
            "Look for: 1. A 'NACA Generator' or airfoil shape. "
            "2. A 'Direct Analysis' or 'XFOIL' view with polar graphs (curves). "
            "Do you see evidence of aerodynamic analysis graphs?"
        )
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_res.get('success', False):
                # Basic heuristic: if the model replies positively about graphs/analysis
                analysis_text = vlm_res.get('text', '').lower()
                if "yes" in analysis_text or "graph" in analysis_text or "polar" in analysis_text or "curve" in analysis_text:
                    score += 20
                    feedback.append("Visual evidence of analysis found.")
                else:
                    feedback.append("No visual evidence of XFOIL analysis found in screenshots.")
            else:
                # If VLM fails, we give partial credit if file output is very good
                if score >= 60: 
                    score += 20
                    feedback.append("VLM unavailable, trusting file output.")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            if score >= 60: score += 20 # Graceful fallback
    else:
        feedback.append("No trajectory frames available for visual verification.")

    # Final tally
    passed = score >= 60 and report_info.get('exists') and not missing
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }