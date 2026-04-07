#!/usr/bin/env python3
"""
Verifier for configure_ganglion_visual_montage task.

Verification Logic:
1. Primary: VLM analysis of the final screenshot (trajectory frames optional but helpful).
   - Check if the Head Plot widget is visible.
   - Check if exactly 4 nodes are active (Ganglion mode).
   - Check if the active nodes are at the back/bottom of the head (Visual Cortex: O1, O2, P3, P4).
2. Secondary: Check if app is running.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ganglion_montage(traj, env_info, task_info):
    """
    Verify that the agent configured the Head Plot for Ganglion (4ch) on Visual Cortex.
    """
    score = 0
    feedback_parts = []
    
    # 1. Check basic app state
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env missing"}

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

    if not result.get('app_running', False):
        return {"passed": False, "score": 0, "feedback": "OpenBCI GUI was not running at the end of the task."}
    
    score += 10
    feedback_parts.append("App running")

    # 2. VLM Verification
    # We need to verify: 
    # A) 4 Channels (Ganglion)
    # B) Location is Posterior (Visual Cortex)
    
    final_img = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=3)
    
    if not final_img:
        return {"passed": False, "score": score, "feedback": "No screenshots available for verification."}

    prompt = """
    You are verifying an OpenBCI GUI task. The user was supposed to:
    1. Start a session in 'Ganglion' mode (4 channels).
    2. Open the 'Head Plot' widget settings.
    3. Remap the electrodes to the Visual Cortex (Back of the head).

    Analyze the final screenshot provided.
    
    Look at the 'Head Plot' widget (circular head map, usually on the right).
    1. How many glowing/colored nodes are active on the head map? (Ignore grey/inactive dots).
    2. Where are these active nodes located?
       - Anterior/Front (Top of circle)
       - Central (Middle of circle)
       - Posterior/Back (Bottom of circle)
    
    For a PASS:
    - There must be exactly 4 active nodes (Ganglion mode).
    - The nodes must be clustered at the BOTTOM (Posterior) of the circle.
    
    If the nodes are at the TOP (Frontal), the user failed to remap them.
    If there are 8 or 16 nodes, the user failed to select Ganglion mode.

    Return JSON:
    {
        "head_plot_visible": boolean,
        "approx_active_node_count": number,
        "node_location": "anterior" | "central" | "posterior" | "mixed",
        "ganglion_mode_correct": boolean,
        "visual_cortex_mapping_correct": boolean,
        "reasoning": "string"
    }
    """

    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=frames + [final_img]
        )
        
        analysis = vlm_response.get('parsed', {})
        logger.info(f"VLM Analysis: {analysis}")

        # Score based on VLM analysis
        if analysis.get('head_plot_visible', False):
            score += 10
            feedback_parts.append("Head plot visible")
        
        # Check Channel Count (Ganglion = 4)
        node_count = analysis.get('approx_active_node_count', 0)
        # Allow slight VLM counting error (e.g., 3-5 is likely intended as 4)
        if 3 <= node_count <= 5 or analysis.get('ganglion_mode_correct'):
            score += 30
            feedback_parts.append("Ganglion (4ch) mode confirmed")
        elif node_count >= 6:
            feedback_parts.append(f"Too many channels ({node_count}), looks like 8ch/16ch mode")
        
        # Check Mapping (Posterior)
        if analysis.get('visual_cortex_mapping_correct') or analysis.get('node_location') == 'posterior':
            score += 50
            feedback_parts.append("Visual cortex (posterior) mapping confirmed")
        elif analysis.get('node_location') == 'anterior':
            feedback_parts.append("Electrodes still in default Frontal position")
        
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("Visual verification failed due to internal error")

    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }