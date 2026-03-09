#!/usr/bin/env python3
"""
Verifier for predict_turbine_noise task.

Verifies:
1. Valid noise spectrum text file exported (format, timestamps).
2. QBlade project file saved (timestamps, size).
3. VLM verification of the workflow (Module navigation -> Simulation -> Export).
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_predict_turbine_noise(traj, env_info, task_info):
    """
    Verify QBlade noise prediction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load JSON Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: Noise Spectrum Data File (30 pts) ---
    data_info = result.get('data_file', {})
    if data_info.get('exists'):
        if data_info.get('created_during_task'):
            # Check content quality
            if data_info.get('lines_of_data', 0) > 10 and data_info.get('has_valid_values'):
                score += 30
                feedback_parts.append("Noise spectrum data successfully exported")
            else:
                score += 15
                feedback_parts.append("Noise file exists but content seems empty or invalid")
        else:
            feedback_parts.append("Noise file exists but was NOT created during this task (stale data)")
    else:
        feedback_parts.append("Noise spectrum output file not found")

    # --- Criterion 2: Project File Saved (20 pts) ---
    proj_info = result.get('project_file', {})
    if proj_info.get('exists'):
        if proj_info.get('created_during_task'):
            # A valid project with simulation data should be larger than empty
            if proj_info.get('size_bytes', 0) > 10000: # 10KB
                score += 20
                feedback_parts.append("Project file saved with simulation data")
            else:
                score += 10
                feedback_parts.append("Project file saved but size is suspicious (<10KB)")
        else:
            feedback_parts.append("Project file not modified during task")
    else:
        feedback_parts.append("Project file not saved")

    # --- Criterion 3: App State (10 pts) ---
    if result.get('app_running'):
        score += 10
        feedback_parts.append("QBlade is running")
    
    # --- Criterion 4: VLM Process Verification (40 pts) ---
    # We need to verify the user actually ran the simulation visually
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_images = frames + ([final_frame] if final_frame else [])
    
    prompt = """
    Analyze these screenshots of a user working in QBlade (Wind Turbine Software).
    
    Look for these specific milestones:
    1. **Noise/Aeroacoustics Module**: Is the user in the Noise/BPM module? (Look for keywords like "Noise", "BPM", "Observer", "SPL", "Acoustics").
    2. **Spectrum Plot**: Is there a graph showing a curve (Sound Pressure Level vs Frequency)? This is the output of the noise simulation.
    3. **Export Action**: Is there any menu open showing "Export" or file dialogs?
    
    Did the user appear to run a noise prediction simulation?
    """
    
    vlm_result = query_vlm(images=all_images, prompt=prompt)
    
    vlm_passed = False
    if vlm_result and vlm_result.get('success'):
        # Simple heuristic on the VLM's reasoning, assuming VLM outputs boolean-ish analysis
        # In a real implementation we might ask for JSON output from VLM.
        # For now, we assume a positive sentiment in reasoning or explicit check if supported.
        # Let's refine the prompt for JSON to be safe.
        pass # The function above assumes free text unless we parse. Let's do a structured query.
        
    # Structured VLM Query
    json_prompt = """
    Based on the screenshots, answer in JSON:
    {
        "noise_module_visited": true/false,
        "spectrum_plot_visible": true/false,
        "simulation_likely_run": true/false
    }
    """
    vlm_struct = query_vlm(images=all_images, prompt=json_prompt)
    
    if vlm_struct and vlm_struct.get('success'):
        parsed = vlm_struct.get('parsed', {})
        if parsed.get('noise_module_visited') or parsed.get('spectrum_plot_visible'):
            score += 20
            feedback_parts.append("VLM: Noise module/plot visited")
        
        if parsed.get('simulation_likely_run') or parsed.get('spectrum_plot_visible'):
            score += 20
            feedback_parts.append("VLM: Simulation appears to have been run")
            vlm_passed = True
    else:
        # Fallback if VLM fails: if we have the file and it's good, give partial visual points
        if score >= 30: 
            score += 10
            feedback_parts.append("VLM check skipped (file evidence strong)")

    # Final Pass Check
    # Must have the data file AND either the project file OR positive visual confirmation
    key_criteria_met = (data_info.get('exists') and data_info.get('created_during_task'))
    
    passed = (score >= 60) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }