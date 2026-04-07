#!/usr/bin/env python3
"""
Verifier for view_approach_plate task.
Tests if the agent downloaded approach plates and viewed the KSFO airport diagram.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_view_approach_plate(traj, env_info, task_info):
    """
    Verify the agent downloaded plates and viewed KSFO.
    
    Scoring:
    - 30 pts: Programmatic check - Plate data files were downloaded (anti-gaming)
    - 70 pts: Visual check - Final screen shows KSFO plate and trajectory shows download steps
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # 1. Retrieve JSON result from device
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve verification data"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    # === CRITERION 1: DOWNLOAD VERIFICATION (30 pts) ===
    # Check if files were actually downloaded (anti-gaming)
    files_downloaded = result_data.get('plate_files_downloaded', False)
    file_count = result_data.get('new_file_count', 0)
    
    if files_downloaded and file_count > 0:
        score += 30
        feedback_parts.append(f"✓ Plate data downloaded ({file_count} new files)")
    else:
        feedback_parts.append("✗ No new plate data files found (Download step failed)")
        
    # === CRITERION 2: APP STATE (5 pts) ===
    if result_data.get('app_running', False):
        score += 5
        feedback_parts.append("✓ App is running")
    else:
        feedback_parts.append("✗ App is not running")

    # === CRITERION 3: VLM VISUAL VERIFICATION (65 pts) ===
    # We need to verify:
    # 1. Did they visit the download manager? (Trajectory)
    # 2. Is the final screen showing a KSFO plate? (Final Screenshot)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if not final_shot:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | ✗ No screenshots available"
        }
        
    # VLM Query
    prompt = """
    You are evaluating an agent using an Aviation GPS app (Avare).
    The goal is to: 
    1. Go to Download Manager and download 'Plates' for San Francisco.
    2. Go to the Plates viewer and open the KSFO (San Francisco Intl) Airport Diagram or Approach Plate.

    Review the sequence of images (trajectory) and the final image.
    
    Answer the following questions JSON format:
    {
        "download_manager_visited": boolean, // Do intermediate frames show the Download/Map lists?
        "plates_viewer_open": boolean, // Is the final screen showing a document/chart viewer?
        "ksfo_visible": boolean, // Can you see "KSFO", "SFO", or "SAN FRANCISCO" text on the final plate?
        "is_plate_or_diagram": boolean, // Does the final image look like an aviation chart/diagram (black/white lines, runways)?
        "reasoning": "string"
    }
    """
    
    try:
        vlm_response = query_vlm(
            prompt=prompt,
            images=frames + [final_shot]
        )
        
        analysis = vlm_response.get('parsed', {})
        logger.info(f"VLM Analysis: {analysis}")
        
        # Scoring based on VLM
        
        # 1. Trajectory check (15 pts)
        if analysis.get('download_manager_visited', False):
            score += 15
            feedback_parts.append("✓ Visited Download Manager")
        else:
            feedback_parts.append("? Could not confirm Download Manager visit visually")
            
        # 2. Final state check (50 pts)
        if analysis.get('plates_viewer_open', False) and analysis.get('is_plate_or_diagram', False):
            if analysis.get('ksfo_visible', False):
                score += 50
                feedback_parts.append("✓ KSFO Plate displayed correctly")
            else:
                score += 20
                feedback_parts.append("⚠ Plate viewer open, but cannot confirm it is KSFO")
        else:
            feedback_parts.append("✗ Final screen does not show a plate/diagram")
            
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("⚠ Visual verification failed due to system error")
        # Fallback: if files downloaded, give partial credit, but can't pass without visual
        
    # Final determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }