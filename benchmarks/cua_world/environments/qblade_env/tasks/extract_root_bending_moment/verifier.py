#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_root_moment(traj, env_info, task_info):
    """
    Verifies the extract_root_bending_moment task.
    
    Criteria:
    1. Report file exists and contains a valid integer.
    2. Value is within a physically plausible range for the specified blade.
    3. VLM verifies the QBlade workflow (Airfoil -> Blade -> BEM -> Graph).
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
    metadata = task_info.get('metadata', {})
    min_val = metadata.get('min_expected_moment', 20000)
    max_val = metadata.get('max_expected_moment', 60000)

    # 1. Read Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Check File Existence & Timestamp (20 pts)
    if result.get('report_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Report file created.")
    elif result.get('report_exists'):
        score += 10
        feedback.append("Report file exists but timestamp check failed.")
    else:
        feedback.append("Report file not found.")

    # 3. Check Value (40 pts)
    reported_val_str = result.get('report_content', "")
    try:
        # cleanup string
        clean_val = ''.join(filter(lambda x: x.isdigit() or x == '.', reported_val_str))
        val = float(clean_val)
        
        if min_val <= val <= max_val:
            score += 40
            feedback.append(f"Value {val} is within acceptable range ({min_val}-{max_val}).")
        elif val > 0:
            score += 10
            feedback.append(f"Value {val} is numeric but outside expected range ({min_val}-{max_val}).")
        else:
            feedback.append(f"Value {val} is not a positive number.")
            
    except ValueError:
        feedback.append(f"Could not parse numeric value from report: '{reported_val_str}'")

    # 4. VLM Trajectory Verification (40 pts)
    # We check for key stages: Blade Design, Simulation, and Graph Result
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    if not all_frames:
        feedback.append("No screenshots available for visual verification.")
    else:
        prompt = """
        Analyze these screenshots of a user using QBlade (wind turbine software).
        Check for the following steps:
        1. Blade Design: A rectangular blade (constant width) visible in 3D view or design table.
        2. Simulation: A 'BEM Simulation' or 'Wind Speed Sweep' dialog or progress bar.
        3. Results: A 2D line graph plotting data (curves).
        
        Answer with JSON:
        {
            "blade_design_visible": true/false,
            "simulation_run": true/false,
            "graph_visible": true/false,
            "reasoning": "..."
        }
        """
        
        vlm_resp = query_vlm(images=all_frames, prompt=prompt)
        
        if vlm_resp and vlm_resp.get('success'):
            analysis = vlm_resp.get('parsed', {})
            
            # Workflow scoring
            vlm_score = 0
            if analysis.get('blade_design_visible'): vlm_score += 10
            if analysis.get('simulation_run'): vlm_score += 10
            if analysis.get('graph_visible'): vlm_score += 20
            
            score += vlm_score
            feedback.append(f"Visual Analysis: {analysis.get('reasoning')}")
        else:
            feedback.append("Visual analysis failed or inconclusive.")

    # Pass logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }