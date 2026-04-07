#!/usr/bin/env python3
"""
Verifier for configure_calibrated_monitor task.

Checks:
1. Monitor profile 'LabView' exists in PsychoPy database.
2. Monitor physical specs match requirements (Width=53.5, Dist=57, Res=1920x1080).
3. Experiment file exists and links to 'LabView' monitor.
4. Experiment contains a Grating with correct 'deg' units and size/sf parameters.
"""

import json
import tempfile
import os
import logging
import ast

logger = logging.getLogger(__name__)

def verify_configure_calibrated_monitor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    
    # Tolerances
    TARGET_WIDTH = metadata.get('target_width', 53.5)
    TARGET_DISTANCE = metadata.get('target_distance', 57.0)
    TOLERANCE = 0.2
    
    score = 0
    feedback_parts = []
    
    # Load result
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/task_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)
            
    # 1. Monitor Profile Existence (20 pts)
    if result.get("monitor_found"):
        score += 20
        feedback_parts.append("Monitor 'LabView' profile created.")
    else:
        feedback_parts.append("Monitor 'LabView' not found in configuration.")
        # If monitor doesn't exist, we can't check its specs
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 2. Monitor Specs (30 pts)
    # Width
    width = result.get("monitor_width", 0)
    if abs(width - TARGET_WIDTH) <= TOLERANCE:
        score += 15
        feedback_parts.append(f"Width correct ({width}cm).")
    else:
        feedback_parts.append(f"Width incorrect (found {width}cm, expected {TARGET_WIDTH}cm).")
        
    # Distance
    dist = result.get("monitor_distance", 0)
    if abs(dist - TARGET_DISTANCE) <= TOLERANCE:
        score += 15
        feedback_parts.append(f"Distance correct ({dist}cm).")
    else:
        feedback_parts.append(f"Distance incorrect (found {dist}cm, expected {TARGET_DISTANCE}cm).")
        
    # Resolution (Soft check, usually defaults strictly)
    res = result.get("monitor_resolution", [0, 0])
    if res == [1920, 1080]:
        feedback_parts.append("Resolution matches.")
    else:
        feedback_parts.append(f"Resolution mismatch (found {res}).")

    # 3. Experiment Settings (50 pts)
    if result.get("exp_file_exists"):
        # Link check (10 pts)
        mon_link = result.get("exp_monitor_link", "")
        if mon_link == "LabView":
            score += 10
            feedback_parts.append("Experiment linked to LabView monitor.")
        else:
            feedback_parts.append(f"Experiment monitor set to '{mon_link}' instead of 'LabView'.")
            
        # Units check (20 pts) - CRITICAL for this task
        units = result.get("stim_units", "")
        # units can be explicitly 'deg' or use window settings. 
        # Task requires setting it on the stimulus or window. The export script checks stimulus.
        if units == "deg":
            score += 20
            feedback_parts.append("Stimulus units set to degrees.")
        else:
            feedback_parts.append(f"Stimulus units incorrect (found '{units}', expected 'deg').")
            
        # Size/SF check (20 pts)
        size_str = str(result.get("stim_size", ""))
        sf_str = str(result.get("stim_sf", ""))
        
        # Parse size string (e.g. "(4.0, 4.0)" or "[4, 4]")
        size_correct = False
        try:
            # Simple string checks for common formats
            if "4" in size_str:
                size_correct = True
        except: 
            pass
            
        if size_correct:
            score += 10
            feedback_parts.append("Stimulus size appears correct.")
        else:
            feedback_parts.append(f"Stimulus size incorrect ({size_str}).")
            
        if "2" in sf_str:
            score += 10
            feedback_parts.append("Spatial frequency appears correct.")
        else:
            feedback_parts.append(f"Spatial frequency incorrect ({sf_str}).")
            
    else:
        feedback_parts.append("Experiment file visual_angle_test.psyexp not found.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }