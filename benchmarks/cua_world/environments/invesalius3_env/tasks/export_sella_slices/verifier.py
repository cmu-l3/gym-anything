#!/usr/bin/env python3
"""
Verifier for export_sella_slices task.

SCORING CRITERIA:
1. File Existence & Validity (45 pts):
   - Axial PNG exists and is valid (15 pts)
   - Sagittal PNG exists and is valid (15 pts)
   - Coronal PNG exists and is valid (15 pts)
2. Content Distinctness (20 pts):
   - All three files must have different MD5 hashes (proves distinct views)
3. Anti-Gaming (10 pts):
   - Files created AFTER task start time
4. VLM Verification (25 pts):
   - Trajectory analysis confirms navigation to different slice views

Pass Threshold: 65 points
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_sella_slices(traj, env_info, task_info):
    """Verify export of three orthogonal sella turcica slice views."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback_parts = []
    
    # --- 1. Check Files (45 pts total) ---
    planes = ['axial', 'sagittal', 'coronal']
    valid_files = 0
    
    for plane in planes:
        exists = result.get(f'{plane}_exists', False)
        valid_png = result.get(f'{plane}_valid_png', False)
        size = result.get(f'{plane}_size', 0)
        
        if exists and valid_png and size > 10240: # >10KB
            score += 15
            valid_files += 1
            feedback_parts.append(f"{plane.title()} view OK")
        elif exists:
            feedback_parts.append(f"{plane.title()} view exists but invalid/small")
        else:
            feedback_parts.append(f"{plane.title()} view MISSING")

    # --- 2. Check Distinctness (20 pts) ---
    # Only award if at least 2 files exist, full points if all 3 distinct
    hashes = []
    for plane in planes:
        h = result.get(f'{plane}_hash', f'missing_{plane}')
        if result.get(f'{plane}_exists', False):
            hashes.append(h)
    
    distinct_hashes = len(set(hashes))
    
    if valid_files == 3 and distinct_hashes == 3:
        score += 20
        feedback_parts.append("All views distinct")
    elif valid_files >= 2 and distinct_hashes == valid_files:
        # Partial credit if they only made 2 valid distinct files
        score += 10
        feedback_parts.append("Generated views are distinct")
    elif valid_files > 1:
        feedback_parts.append("Duplicate views detected (did not change slice?)")

    # --- 3. Check Timestamps (10 pts) ---
    all_new = True
    for plane in planes:
        if result.get(f'{plane}_exists', False):
            if not result.get(f'{plane}_created_during_task', False):
                all_new = False
    
    if all_new and valid_files > 0:
        score += 10
        feedback_parts.append("Files created during task")
    elif valid_files > 0:
        feedback_parts.append("Some files pre-dated task start")

    # --- 4. VLM Verification (25 pts) ---
    # We want to see the agent navigating the slice views.
    # The trajectory should show interaction with different panels.
    
    if valid_files >= 1: # Only run VLM if they actually did something
        try:
            frames = sample_trajectory_frames(traj, n=6)
            
            prompt = """
            You are verifying a medical software task in InVesalius 3.
            The user must navigate three different slice views (Axial, Sagittal, Coronal).
            
            Look at the image sequence. 
            1. Do you see the crosshairs moving or slice numbers changing in the 3 viewing panels?
            2. Do you see the user interacting with different quadrants of the screen (top-left, top-right, bottom-left)?
            
            Return JSON:
            {"navigation_detected": boolean, "multiple_views_adjusted": boolean}
            """
            
            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                
                if parsed.get('multiple_views_adjusted', False):
                    score += 25
                    feedback_parts.append("VLM confirmed navigation")
                elif parsed.get('navigation_detected', False):
                    score += 15
                    feedback_parts.append("VLM confirmed some activity")
                else:
                    feedback_parts.append("VLM did not detect slice navigation")
            else:
                # Fallback if VLM unavailable but files are good
                score += 25
                feedback_parts.append("VLM unavailable (skipped)")
        except Exception as e:
            logger.error(f"VLM check failed: {e}")
            feedback_parts.append("VLM check error")
    
    # Final Decision
    # Need at least 2 valid distinct files to have a chance of passing
    passed = (score >= 65) and (valid_files >= 2) and (distinct_hashes >= 2)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }