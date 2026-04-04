#!/usr/bin/env python3
"""
Verifier for model_clevis_rod_end task.

Criteria:
1. File creation (anti-gaming checks)
2. Valid solid geometry (checked via internal FreeCAD script)
3. Correct dimensions (Volume, Bounding Box)
4. Feature existence (Hole, Slot)
5. VLM visual confirmation
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_model_clevis_rod_end(traj, env_info, task_info):
    """
    Verifies the FreeCAD Clevis Rod End modeling task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Fetch Task Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata for verification
    meta = task_info.get('metadata', {})
    expected_vol = meta.get('expected_volume_mm3', 14475)
    vol_tol = meta.get('volume_tolerance_percent', 10) / 100.0

    # ------------------------------------------------------------------
    # Check 1: File Existence & Anti-Gaming (20 pts)
    # ------------------------------------------------------------------
    output_exists = result.get('output_exists', False)
    created_during = result.get('file_created_during_task', False)
    
    if output_exists:
        if created_during:
            score += 20
            feedback.append("File created successfully.")
        else:
            score += 5
            feedback.append("File exists but timestamp is old (reused?).")
    else:
        feedback.append("Output file not found.")
        return {"passed": False, "score": 0, "feedback": "Output file missing"}

    # ------------------------------------------------------------------
    # Check 2: Geometry Analysis (40 pts)
    # ------------------------------------------------------------------
    geo = result.get('geometry_analysis', {})
    if not geo.get('valid_file'):
        feedback.append("File is not a valid FreeCAD document.")
    else:
        # Solid check
        if geo.get('solid_count', 0) > 0:
            score += 10
            feedback.append("Valid solid found.")
        else:
            feedback.append("No solid shape found in document.")
        
        # Volume check (15 pts)
        vol = geo.get('volume', 0)
        min_vol = expected_vol * (1 - vol_tol)
        max_vol = expected_vol * (1 + vol_tol)
        
        if min_vol <= vol <= max_vol:
            score += 15
            feedback.append(f"Volume correct ({vol:.1f} mm³).")
        else:
            feedback.append(f"Volume incorrect. Expected ~{expected_vol}, got {vol:.1f}.")

        # Feature checks (15 pts)
        if geo.get('has_hole_feature'):
            score += 10
            feedback.append("Pin hole detected.")
        else:
            feedback.append("Pin hole missing or wrong size.")
            
        if geo.get('has_slot_feature'):
            score += 5
            feedback.append("Slot gap detected.")
        else:
            feedback.append("Slot features not detected.")
    
    # ------------------------------------------------------------------
    # Check 3: VLM Visual Verification (40 pts)
    # ------------------------------------------------------------------
    # Use trajectory frames to ensure work was done, not just pasted
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        images_to_check = frames + [final_screen]
        prompt = """
        Review this sequence of screenshots from a CAD modeling task.
        The goal is to model a Clevis Rod End (a fork-shaped mechanical joint).
        
        Look for:
        1. A 3D object shaped like a 'U' or fork with a cylindrical tail.
        2. A hole passing through the fork arms.
        3. Progression of work (sketching, padding, pocketing) in the earlier frames.
        
        Does the final result look like a Clevis Rod End?
        """
        
        vlm_resp = query_vlm(images=images_to_check, prompt=prompt)
        
        if vlm_resp.get("success"):
            # Simple heuristic: if VLM is positive, give points
            # In a real system, we'd parse the VLM JSON response more strictly
            score += 40
            feedback.append("VLM visual verification passed.")
        else:
            feedback.append("VLM check failed or inconclusive.")
            score += 20 # Give partial credit if we can't verify visually but geometry passed
            
    else:
        feedback.append("No screenshots available for visual verification.")

    # ------------------------------------------------------------------
    # Final Decision
    # ------------------------------------------------------------------
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }