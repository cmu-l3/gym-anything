#!/usr/bin/env python3
"""
Verifier for create_helical_lead_screw task.

Verifies:
1. Files (FCStd, STEP) exist and were created during the task.
2. Geometric properties (Volume, Bounding Box) match a lead screw:
   - Volume should be LESS than a solid cylinder (material removed).
   - Bounding box should match 12x50mm.
3. VLM verification of the workflow (Helix creation).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_helical_lead_screw(traj, env_info, task_info):
    """
    Verify the lead screw creation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # ----------------------------------------------------------------
    # 1. Retrieve Result JSON from Container
    # ----------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ----------------------------------------------------------------
    # 2. Score Calculation
    # ----------------------------------------------------------------
    score = 0
    feedback = []
    
    # Files exist (Max 25 pts)
    if result.get('fcstd_exists'):
        score += 15
        feedback.append("FCStd file created.")
    else:
        feedback.append("FCStd file missing.")
        
    if result.get('step_exists'):
        score += 10
        feedback.append("STEP export created.")
    
    # Anti-gaming check
    if not result.get('file_created_during_task'):
        feedback.append("Warning: File timestamp check failed (files pre-dated task?).")
        score = 0 # Fail immediately if cheating detected
        return {"passed": False, "score": 0, "feedback": "Files were not created during the task session."}

    # Geometric Analysis (Max 45 pts)
    geo = result.get('geometry', {})
    
    # Volume Check
    # Cylinder vol ~ 5655 mm3. Screw should be ~4000-5500 depending on thread depth.
    # It MUST be less than 5650 (implies material was removed).
    vol = geo.get('volume', 0)
    min_vol = metadata.get('min_volume_mm3', 3500)
    max_vol = metadata.get('max_volume_mm3', 5600)
    
    if vol > 0:
        if min_vol < vol < max_vol:
            score += 20
            feedback.append(f"Volume ({vol:.1f} mm³) is within expected range for a lead screw.")
        elif vol >= max_vol and vol < 5700:
            # Likely just a cylinder, no cut
            score += 5
            feedback.append(f"Volume ({vol:.1f} mm³) suggests a plain cylinder (no thread groove cut).")
        else:
            feedback.append(f"Volume ({vol:.1f} mm³) is outside reasonable range.")
    else:
        feedback.append("Model volume is zero or unreadable.")

    # Dimensions Check (12mm dia x 50mm len)
    # Allow loose tolerance because bounding box depends on orientation
    # We look for one dim ~50 and two dims ~12
    dims = sorted([geo.get('bbox_x', 0), geo.get('bbox_y', 0), geo.get('bbox_z', 0)])
    
    # Smallest two should be ~12 (diameter)
    dia_ok = (10 <= dims[0] <= 14) and (10 <= dims[1] <= 14)
    # Largest should be ~50 (length)
    len_ok = (45 <= dims[2] <= 55)
    
    if dia_ok and len_ok:
        score += 15
        feedback.append("Model dimensions match specifications (12x50mm).")
    elif len_ok:
        score += 5
        feedback.append("Model length is correct, but diameter is off.")
    else:
        feedback.append(f"Model dimensions incorrect: {dims}")
        
    # Feature Check
    if geo.get('has_helix'):
        score += 10
        feedback.append("Helix feature detected in file.")

    # ----------------------------------------------------------------
    # 3. VLM Verification (Max 30 pts)
    # ----------------------------------------------------------------
    # We use trajectory to ensure they didn't just python-script a cylinder
    # and to verify the helix visually.
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a FreeCAD user session.
        The user is supposed to model a "helical lead screw" (a threaded rod).
        
        Look for:
        1. Creation of a helix or spiral path (yellow or white spiral line).
        2. Use of a "Sweep" operation or "Boolean Cut".
        3. The final model looking like a screw (cylindrical with a groove).
        
        Answer JSON:
        {
            "helix_tool_used": boolean,
            "final_model_looks_like_screw": boolean,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames + [final_img], prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('helix_tool_used'):
                vlm_score += 15
            if parsed.get('final_model_looks_like_screw'):
                vlm_score += 15
                
            feedback.append(f"VLM Analysis: {json.dumps(parsed)}")
        except Exception as e:
            feedback.append(f"VLM check failed: {str(e)}")
            # Fallback: if geometry was perfect, give partial VLM points
            if score >= 60:
                vlm_score = 15
    
    score += vlm_score

    # ----------------------------------------------------------------
    # Final Decision
    # ----------------------------------------------------------------
    # Pass if score >= 60 AND file exists AND volume check confirms groove
    passed = (score >= 60) and result.get('fcstd_exists') and (vol < 5650)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }