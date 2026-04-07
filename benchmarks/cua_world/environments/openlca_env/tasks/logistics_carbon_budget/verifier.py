#!/usr/bin/env python3
import json
import os
import base64
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_logistics_carbon_budget(traj, env_info, task_info):
    """
    Verifies the logistics optimization task.
    
    Scoring Criteria:
    1. Parameter 'distance_km' defined in DB (20 pts)
    2. Process 'Distribution Leg' created (15 pts)
    3. Formula using 'distance_km' exists in exchanges (15 pts)
    4. Text file exported with distance value (10 pts)
    5. CSV result exported (10 pts)
    6. Calculated GWP is within target range 49.0 - 51.0 (20 pts)
    7. VLM: Evidence of iterative calculation or parameter adjustment (10 pts)
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Database Verification (Structural)
    if result.get("param_found", False):
        score += 20
        feedback.append("Global parameter 'distance_km' created.")
    else:
        feedback.append("Failed: Parameter 'distance_km' not found in database.")

    if result.get("process_found", False):
        score += 15
        feedback.append("Process 'Distribution Leg' created.")
    else:
        feedback.append("Failed: Target process not found.")

    if result.get("exchange_formula_found", False):
        score += 15
        feedback.append("Transport exchange uses parameter formula.")
    else:
        feedback.append("Failed: No exchange found using the 'distance_km' formula.")

    # 3. Result File Verification
    # Check Text File (Distance)
    txt_val_str = result.get("txt_value", "").strip()
    distance_val = 0.0
    try:
        if txt_val_str:
            distance_val = float(txt_val_str)
            score += 10
            feedback.append(f"Distance file exported: {distance_val} km")
        else:
            feedback.append("Distance text file missing or empty.")
    except ValueError:
        feedback.append(f"Distance text file invalid: {txt_val_str}")

    # Check CSV (GWP Target)
    gwp_found = False
    gwp_val = 0.0
    
    if result.get("csv_exists", False):
        score += 10
        feedback.append("LCIA result CSV exported.")
        
        # Decode content
        try:
            content = base64.b64decode(result.get("csv_content_b64", "")).decode('utf-8', errors='ignore')
            # Naive parsing for GWP value ~ 50.0
            # Look for lines containing "Global warming" or "GWP" and a number near 50
            lines = content.split('\n')
            for line in lines:
                if "global warming" in line.lower() or "gwp" in line.lower() or "climate change" in line.lower():
                    # Extract numbers
                    import re
                    nums = re.findall(r"[-+]?\d*\.\d+|\d+", line)
                    for n in nums:
                        try:
                            val = float(n)
                            # Logic: GWP for 500km * 0.5t is unlikely to be exactly 50 without tuning
                            # We are looking for the *result* of the optimization.
                            # If the user optimized correctly, this value should be near 50.
                            if 40.0 < val < 60.0: # Broad search range
                                gwp_val = val
                                gwp_found = True
                                break
                        except:
                            continue
                if gwp_found: break
        except Exception as e:
            feedback.append(f"Error parsing CSV: {e}")

    # 4. Target Verification
    # Check if the text file distance value aligns with the parameter in DB
    # And check if that distance likely yields the target GWP.
    # Note: We can't easily re-run the simulation, so we trust the export if it matches the target.
    
    target_met = False
    if gwp_found:
        if 49.0 <= gwp_val <= 51.0:
            score += 20
            target_met = True
            feedback.append(f"Target GWP achieved: {gwp_val:.2f} kg CO2e")
        else:
            feedback.append(f"GWP result {gwp_val:.2f} is outside target range (49.0-51.0).")
    elif distance_val > 0:
        # Fallback: if CSV parsing failed, check if the DB parameter value is reasonable.
        # Approx factor for truck is ~0.1 kg CO2e / t*km (very rough estimate)
        # Target = 50 kg. Load = 0.5 t. 
        # 50 = 0.5 * dist * factor
        # This is hard to verify without the exact factor.
        # We will rely on the CSV check primarily.
        feedback.append("Could not verify GWP from CSV.")

    # 5. VLM Verification (Trajectory)
    # Check for evidence of iteration (running calculation multiple times)
    frames = sample_trajectory_frames(traj, 5)
    final_img = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze these screenshots of a user working in OpenLCA.
    The task involves iteratively adjusting a parameter 'distance_km' to reach a specific GWP result (50 kg CO2e).
    
    Look for:
    1. A 'Parameters' tab or list showing 'distance_km'.
    2. A 'Calculation results' window showing Global Warming Potential.
    3. Evidence of multiple calculations (e.g. changing a value and re-running).
    
    Does the user appear to be modeling a transport process or adjusting parameters?
    """
    
    vlm_res = query_vlm(prompt=vlm_prompt, images=frames + [final_img])
    vlm_passed = False
    if vlm_res and vlm_res.get('success'):
        # Just check for positive sentiment/confirmation in text
        # Real implementation would parse JSON, here we assume manual grading or simple keyword check
        resp = vlm_res.get('response', '').lower()
        if "parameter" in resp or "calculation" in resp:
            score += 10
            vlm_passed = True
            feedback.append("VLM confirmed modeling activity.")
    
    # Final Pass Determination
    # Must have created the parameter, process, and got close to the target
    passed = (result.get("param_found") and 
              result.get("process_found") and 
              (target_met or (gwp_found and 48.0 <= gwp_val <= 52.0))) # Slightly looser tolerance for pass
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }