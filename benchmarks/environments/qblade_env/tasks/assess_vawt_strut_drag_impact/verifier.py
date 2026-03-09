#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_strut_impact_assessment(traj, env_info, task_info):
    """
    Verify the VAWT strut drag assessment task.
    
    Criteria:
    1. Project file exists and is fresh (20 pts).
    2. Report file exists and contains readable data (20 pts).
    3. Reported physics are consistent (Strutted < Baseline) (20 pts).
    4. Reported values are within realistic ranges (20 pts).
    5. VLM: Trajectory shows use of VAWT Design or DMS Simulation (20 pts).
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # --- Load Result JSON ---
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
    
    # --- Criterion 1: Project File (20 pts) ---
    if result.get('project_exists', False):
        size = result.get('project_size_bytes', 0)
        if size > 1000: # Valid QBlade projects are usually > several KB
            score += 20
            feedback.append("Project file saved successfully.")
        else:
            score += 10
            feedback.append("Project file saved but seems too small.")
    else:
        feedback.append("Project file not found.")

    # --- Criterion 2 & 3 & 4: Report Analysis (60 pts total) ---
    report_exists = result.get('report_exists', False)
    content = result.get('report_content', "")
    
    baseline = 0.0
    strutted = 0.0
    
    if report_exists and content:
        score += 20
        feedback.append("Report file created.")
        
        # Parse values using regex
        # Look for numbers associated with "Baseline" and "Strutted"
        try:
            # Flexible regex to catch: "Baseline Max Cp: 0.45" or "Baseline: 0.45"
            base_match = re.search(r"Baseline.*?([\d\.]+)", content, re.IGNORECASE)
            strut_match = re.search(r"Strutted.*?([\d\.]+)", content, re.IGNORECASE)
            
            if base_match and strut_match:
                baseline = float(base_match.group(1))
                strutted = float(strut_match.group(1))
                
                # Check Physics Logic (Struts ADD drag -> Cp should DECREASE)
                if strutted < baseline:
                    score += 20
                    feedback.append("Reported physics correct (Strutted Cp < Baseline Cp).")
                else:
                    feedback.append(f"Physics error: Strutted Cp ({strutted}) >= Baseline Cp ({baseline}).")

                # Check Realistic Ranges
                min_base = metadata.get('min_cp_baseline', 0.30)
                max_base = metadata.get('max_cp_baseline', 0.55)
                
                if min_base <= baseline <= max_base:
                    if 0 < strutted < baseline:
                        score += 20
                        feedback.append("Cp values are within realistic engineering ranges.")
                    else:
                        score += 10
                        feedback.append("Baseline valid, but strutted Cp questionable.")
                else:
                    feedback.append(f"Baseline Cp {baseline} outside expected range ({min_base}-{max_base}).")
                    
            else:
                feedback.append("Could not parse Cp values from report.")
        except ValueError:
            feedback.append("Error parsing numeric values from report.")
    else:
        feedback.append("Report file not found or empty.")

    # --- Criterion 5: VLM Trajectory Verification (20 pts) ---
    # We want to see the VAWT module or graphs, confirming work was done
    trajectory_images = sample_trajectory_frames(traj, 5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review these screenshots of QBlade software.
    I am looking for evidence that a user performed a VAWT (Vertical Axis Wind Turbine) simulation.
    
    Look for:
    1. A "VAWT Rotor Design" screen (showing a turbine with vertical blades).
    2. A "DMS Simulation" or "BEM Simulation" screen (showing graphs/curves).
    3. Any graphs plotting Cp vs TSR (Power Coefficient vs Tip Speed Ratio).
    
    Answer JSON:
    {
        "vawt_design_visible": true/false,
        "graphs_visible": true/false,
        "confidence": "high/medium/low"
    }
    """
    
    try:
        if trajectory_images:
            vlm_res = query_vlm(images=trajectory_images + [final_img], prompt=vlm_prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('vawt_design_visible') or parsed.get('graphs_visible'):
                    score += 20
                    feedback.append("Visual evidence of simulation workflow found.")
                else:
                    feedback.append("No visual evidence of VAWT design or simulation found.")
            else:
                # Fallback if VLM fails: pass if file checks were perfect
                if score >= 80:
                    score += 20
                    feedback.append("VLM skipped, trusting file evidence.")
        else:
             feedback.append("No trajectory frames available for verification.")
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        # Fallback
        if score >= 80:
             score += 20

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }