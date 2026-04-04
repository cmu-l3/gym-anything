#!/usr/bin/env python3
import json
import os
import re
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_rotor_study(traj, env_info, task_info):
    """
    Verifies the Rotor Tip Loss Correction Study task.
    
    Criteria:
    1. Report file exists and contains valid BEM data (Max Cp, CT).
    2. Physics Check: Cp without tip loss > Cp with tip loss.
    3. Project file exists and is not empty.
    4. VLM: Confirms QBlade graphs were generated during workflow.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

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
    
    # 2. File Verification (40 points)
    report_content = result.get("report_content", "")
    report_exists = result.get("report_exists", False)
    project_exists = result.get("project_exists", False)
    project_size = result.get("project_size", 0)
    
    # Report File Check
    if report_exists and result.get("report_created_during_task", False):
        score += 10
        feedback.append("Report file created.")
    elif report_exists:
        score += 5
        feedback.append("Report file exists but timestamp is old.")
    else:
        feedback.append("Report file missing.")
        
    # Project File Check
    if project_exists and project_size > 1024: # >1KB
        score += 10
        feedback.append("Project file saved.")
        if result.get("project_created_during_task", False):
            score += 5 # Bonus for timestamp
    else:
        feedback.append("Project file missing or empty.")

    # 3. Content Analysis (Physics & Data) (40 points)
    # Extract values using regex
    # Looking for patterns like "Max Cp = 0.45" or similar
    # We are flexible with formatting but need to distinguish ON vs OFF
    
    cp_values = re.findall(r"Cp.*?=.*?([0-9]*\.?[0-9]+)", report_content, re.IGNORECASE)
    
    cp_on = None
    cp_off = None
    
    # Try to heuristically identify values if explicit labels aren't strictly standard
    # But description asked for specific format.
    # Let's look for blocks.
    
    lower_content = report_content.lower()
    
    try:
        if "with tip loss" in lower_content and "without tip loss" in lower_content:
            # Split the text
            parts = lower_content.split("without tip loss")
            part_on = parts[0]
            part_off = parts[1]
            
            # Find first number after "Max Cp" in each part
            match_on = re.search(r"max cp.*?([0-9]*\.?[0-9]+)", part_on)
            match_off = re.search(r"max cp.*?([0-9]*\.?[0-9]+)", part_off)
            
            if match_on and match_off:
                cp_on = float(match_on.group(1))
                cp_off = float(match_off.group(1))
                
                feedback.append(f"Found Cp values: ON={cp_on}, OFF={cp_off}")
                
                # Check ranges (Betz limit ~0.59)
                if 0.05 < cp_on < 0.60 and 0.05 < cp_off < 0.60:
                    score += 10
                    feedback.append("Cp values are within physical range.")
                else:
                    feedback.append("Cp values are unrealistic (outside 0.05-0.60).")

                # Physics Check: Tip loss reduces power, so OFF > ON
                if cp_off > cp_on:
                    score += 20
                    feedback.append("Physics Check Passed: Cp(NoLoss) > Cp(WithLoss).")
                    
                    # Check delta significance
                    delta_percent = ((cp_off - cp_on) / cp_on) * 100
                    if delta_percent > 1.0:
                        score += 10
                        feedback.append(f"Significant difference detected ({delta_percent:.1f}%).")
                else:
                    feedback.append("Physics Check Failed: Tip loss correction should reduce Cp.")
            else:
                feedback.append("Could not parse Max Cp values from report.")
        else:
            feedback.append("Report missing required sections ('With Tip Loss', 'Without Tip Loss').")
    except Exception as e:
        feedback.append(f"Error parsing report content: {str(e)}")

    # 4. VLM Verification (20 points)
    # Ensure they actually ran the sim and didn't just guess numbers
    frames = sample_trajectory_frames(traj, n=5)
    final_shot = get_final_screenshot(traj)
    
    # Analyze trajectory
    vlm_prompt = """
    Review these screenshots of the QBlade wind turbine software.
    I am looking for evidence that a BEM simulation was performed.
    
    Look for:
    1. A graph showing curves (usually Power Coefficient Cp vs TSR).
    2. Multiple curves plotted on the same graph (e.g., comparing two runs).
    3. The QBlade 'Simulation' or 'BEM' module being active.
    
    Return JSON:
    {
        "bem_graphs_visible": true/false,
        "multiple_curves_visible": true/false,
        "qblade_simulation_module_active": true/false
    }
    """
    
    vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("bem_graphs_visible"):
            score += 10
            feedback.append("VLM confirmed BEM graphs are visible.")
        if parsed.get("multiple_curves_visible"):
            score += 10
            feedback.append("VLM confirmed multiple simulation curves.")
    else:
        feedback.append("VLM analysis failed or inconclusive.")

    # 5. Final Pass Determination
    # Must have physics check passed AND score >= 60
    physics_passed = (cp_on is not None and cp_off is not None and cp_off > cp_on)
    passed = (score >= 60) and physics_passed
    
    if not physics_passed:
        feedback.append("CRITICAL: Physics check failed (Cp OFF must be > Cp ON).")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }