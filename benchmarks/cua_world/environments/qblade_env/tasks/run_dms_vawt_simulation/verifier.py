#!/usr/bin/env python3
"""
Verifier for run_dms_vawt_simulation task.
Uses file validation and VLM trajectory analysis.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_run_dms_vawt_simulation(traj, env_info, task_info):
    """
    Verify DMS simulation task.
    
    Criteria:
    1. Output file exists and was created during task (30 pts)
    2. Output file contains DMS markers (confirmation of correct module use) (20 pts)
    3. Output file size is reasonable (>5KB) (10 pts)
    4. VLM Trajectory:
       - Visited DMS module (15 pts)
       - Configured/Ran simulation (15 pts)
       - Final plot visible (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load file-based results
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
    feedback = []

    # --- File Verification ---
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 30
        feedback.append("Project file saved successfully.")
    else:
        feedback.append("Project file output missing or not saved during task.")

    if result.get('contains_dms_data'):
        score += 20
        feedback.append("Project file contains DMS simulation data.")
    else:
        feedback.append("Project file does not appear to contain DMS data.")

    if result.get('output_size_bytes', 0) > 5000:
        score += 10
        feedback.append("Project file size is valid.")
    else:
        feedback.append("Project file is suspiciously small.")

    # --- VLM Verification ---
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames
    
    if not all_frames:
        feedback.append("No screenshots available for VLM verification.")
    else:
        prompt = """
        You are verifying a user task in QBlade (Wind Turbine Simulation Software).
        The user was supposed to:
        1. Go to the DMS (Double Multiple Streamtube) Rotor Simulation module.
        2. Run a simulation for a Vertical Axis Wind Turbine (VAWT).
        3. See a plot of Cp (Power Coefficient) vs Lambda/TSR.
        
        Look at these screenshots of the user's workflow.
        
        Q1: Do you see the DMS simulation interface? (Look for 'DMS', 'Double Multiple Streamtube', or VAWT-specific controls).
        Q2: Do you see a simulation result plot (curved line graph, usually Cp vs Lambda)?
        Q3: Is there a 'Save Project' dialog or evidence of saving?
        
        Return JSON:
        {
            "dms_interface_seen": true/false,
            "result_plot_seen": true/false,
            "saving_seen": true/false,
            "confidence": 0-10
        }
        """
        
        try:
            vlm_resp = query_vlm(images=all_frames, prompt=prompt)
            vlm_data = vlm_resp.get('parsed', {})
            
            if vlm_data.get('dms_interface_seen'):
                score += 15
                feedback.append("VLM confirmed DMS interface usage.")
            
            if vlm_data.get('result_plot_seen'):
                score += 15
                feedback.append("VLM confirmed simulation result plot.")
            
            if vlm_data.get('saving_seen'):
                score += 10
                feedback.append("VLM confirmed file saving action.")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback.append("Visual verification skipped due to error.")

    # --- Final Scoring ---
    # Need at least 60 points + file existence for pass
    passed = (score >= 60) and result.get('output_exists') and result.get('file_created_during_task')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }