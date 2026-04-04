#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import math
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_size_rotor_for_5kw_output(traj, env_info, task_info):
    """
    Verifies the iterative rotor sizing task.
    
    Criteria:
    1. Project file exists and is modified (10 pts)
    2. Simulation export exists (10 pts)
    3. Simulation output shows Power within tolerance (4950-5050 W) (35 pts)
    4. Result text file exists and reports a radius (10 pts)
    5. Reported radius is physically plausible (2.2m - 3.2m) (10 pts)
    6. VLM Check: Visual evidence of iteration or simulation (25 pts)
    """
    
    # 1. Setup and load data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_power = metadata.get('target_power_watts', 5000)
    tolerance = metadata.get('tolerance_watts', 50)
    
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
    
    # 2. Check Artifacts (Project File) - 10 pts
    project = result.get('project', {})
    if project.get('exists') and project.get('size', 0) > 1000:
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file missing or empty.")

    # 3. Check Simulation Export & Power Value - 10 + 35 pts
    sim = result.get('simulation', {})
    power_valid = False
    
    if sim.get('exists'):
        score += 10
        feedback.append("Simulation export found.")
        
        # Parse content
        content_b64 = sim.get('content_b64', '')
        try:
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Strategy: Look for the numeric value of Power. 
            # QBlade exports often have columns. We look for the last line of data.
            # Or we look for a regex pattern like P = 5000 or similar if it's a summary.
            # Assuming tabular data, we look for numbers near 5000.
            
            # Simple heuristic: extract all floats
            floats = [float(x) for x in re.findall(r"-?\d+\.?\d*", content)]
            
            # Find the value closest to 5000 that looks like power
            # (Assuming wind speed 10 and TSR 6 are also in there, 5000 is distinct enough)
            closest_power = 0
            min_diff = float('inf')
            
            for val in floats:
                # Filter out obvious non-power values (like TSR=6 or Wind=10)
                if 2000 < val < 8000: 
                    diff = abs(val - target_power)
                    if diff < min_diff:
                        min_diff = diff
                        closest_power = val
            
            if min_diff <= tolerance:
                score += 35
                power_valid = True
                feedback.append(f"Simulation result {closest_power:.2f} W is within target range ({target_power} +/- {tolerance} W).")
            elif min_diff < 1000:
                # Partial credit if they tried but missed tolerance
                score += 15
                feedback.append(f"Simulation result {closest_power:.2f} W is outside strict tolerance.")
            else:
                feedback.append("Could not find a power value near 5000 W in the simulation export.")
                
        except Exception as e:
            feedback.append(f"Error parsing simulation file: {str(e)}")
    else:
        feedback.append("Simulation export file missing.")

    # 4. Check Result Text & Radius Plausibility - 10 + 10 pts
    txt = result.get('result_text', {})
    radius_valid = False
    
    if txt.get('exists'):
        content = txt.get('content', '')
        # Regex for "Final Radius: X.XX m"
        match = re.search(r"Final Radius:?\s*([\d\.]+)", content, re.IGNORECASE)
        if match:
            score += 10
            feedback.append("Radius reported in text file.")
            
            radius = float(match.group(1))
            min_r = metadata.get('min_plausible_radius', 2.2)
            max_r = metadata.get('max_plausible_radius', 3.2)
            
            if min_r <= radius <= max_r:
                score += 10
                radius_valid = True
                feedback.append(f"Reported radius {radius}m is physically plausible.")
            else:
                feedback.append(f"Reported radius {radius}m is outside plausible range ({min_r}-{max_r}m).")
        else:
            feedback.append("Result text file exists but could not parse radius.")
    else:
        feedback.append("Result summary text file missing.")

    # 5. VLM Verification - 25 pts
    # We want to see evidence of iteration (running sim multiple times) or specific blade scaling UI
    vlm_score = 0
    frames = sample_trajectory_frames(traj, n=8)
    
    if not frames:
         feedback.append("No video frames available for visual verification.")
    else:
        prompt = """
        You are verifying a QBlade wind turbine design task. 
        The user must size a rotor to hit exactly 5kW. This requires iteration.
        
        Look at these screenshots of the user's workflow. 
        I am looking for:
        1. "BEM Simulation" or "Multi-Parameter BEM" windows.
        2. "Blade Design" or "Scale Blade" dialogs.
        3. Graphs showing Power vs TSR or text results showing Power values.
        
        Did the user appear to run simulations and edit the blade design?
        Return JSON: {"evidence_found": boolean, "confidence": float, "reasoning": string}
        """
        
        try:
            vlm_res = query_vlm(prompt=prompt, images=frames)
            
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('evidence_found', False):
                    vlm_score = 25
                    feedback.append("Visual evidence of simulation/design workflow found.")
                else:
                    feedback.append("VLM did not clearly see simulation workflow.")
            else:
                feedback.append("VLM analysis failed.")
                
        except Exception as e:
            feedback.append(f"VLM error: {str(e)}")
            
    score += vlm_score

    # Final Pass Logic
    # Must have hit the power target (Primary Goal) AND have decent total score
    passed = power_valid and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }