#!/usr/bin/env python3
"""
Verifier for configure_head_plot_widget task.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_head_plot_widget(traj, env_info, task_info):
    """
    Verifies that the agent configured the Head Plot widget correctly.
    
    Scoring Criteria:
    1. Screenshot file created (10 pts)
    2. File validity (size > 50KB, created during task) (10 pts)
    3. Application running at end (10 pts)
    4. VLM Verification (70 pts):
       - Identifies Head Plot widget (circular topographic map)
       - Identifies Time Series widget
       - Confirms active data (waveforms/colors)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}
    
    score = 0
    feedback_parts = []
    
    # --- Step 1: Check File-based Evidence (JSON from export_result.sh) ---
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Score file existence
    if result.get('output_exists', False):
        score += 10
        feedback_parts.append("Screenshot file created.")
        
        # Score file validity
        is_fresh = result.get('file_created_during_task', False)
        size = result.get('output_size_bytes', 0)
        
        if is_fresh and size > 50000: # >50KB
            score += 10
            feedback_parts.append("Screenshot is valid (newly created and sufficient size).")
        else:
            feedback_parts.append(f"Screenshot invalid (Fresh: {is_fresh}, Size: {size} bytes).")
    else:
        feedback_parts.append("Screenshot file NOT found.")
        
    # Score App State
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("OpenBCI GUI is running.")
    else:
        feedback_parts.append("OpenBCI GUI was closed.")

    # --- Step 2: VLM Verification ---
    # We analyze the trajectory to ensure the workflow was followed and the final state is correct.
    # We use the final screenshot from the framework (traj) rather than the one the agent saved,
    # to prevent the agent from just downloading a fake image.
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    if not final_frame or not query_vlm:
        feedback_parts.append("VLM verification unavailable.")
    else:
        prompt = """
        You are verifying an OpenBCI GUI task. 
        The user was asked to:
        1. Load an EEG playback file.
        2. Configure a Top/Bottom layout.
        3. Show 'Time Series' in the top widget.
        4. Show 'Head Plot' in the bottom widget.
        5. Run the session.

        Examine the provided screenshots (chronological order).
        
        Answer the following in JSON format:
        {
            "head_plot_visible": boolean, // Is a circular topographic head map visible?
            "time_series_visible": boolean, // Are EEG waveforms visible?
            "layout_correct": boolean, // Is it a split view (2 widgets)?
            "data_active": boolean, // Does the head plot have colors/activity (not just empty outline)?
            "workflow_followed": boolean // Do the frames show the user navigating menus to set this up?
        }
        """
        
        try:
            vlm_response = query_vlm(images=frames + [final_frame], prompt=prompt)
            analysis = vlm_response.get('parsed', {})
            
            # Score VLM components (Max 70)
            vlm_score = 0
            
            if analysis.get('head_plot_visible', False):
                vlm_score += 25
                feedback_parts.append("Head Plot widget detected.")
            else:
                feedback_parts.append("Head Plot widget NOT detected.")
                
            if analysis.get('time_series_visible', False):
                vlm_score += 15
                feedback_parts.append("Time Series widget detected.")
                
            if analysis.get('data_active', False):
                vlm_score += 15
                feedback_parts.append("Data appears active/streaming.")
                
            if analysis.get('layout_correct', False):
                vlm_score += 10
                feedback_parts.append("Layout appears correct.")
                
            if analysis.get('workflow_followed', False):
                vlm_score += 5
                feedback_parts.append("Workflow progression verified.")
                
            score += vlm_score
            
        except Exception as e:
            feedback_parts.append(f"VLM analysis error: {e}")

    # --- Final Decision ---
    passed = score >= 60 and result.get('output_exists', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }