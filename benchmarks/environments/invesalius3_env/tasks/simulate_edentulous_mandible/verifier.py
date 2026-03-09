#!/usr/bin/env python3
"""
Verifier for simulate_edentulous_mandible task.

Criteria:
1. STL file exists and was created during task.
2. STL file has realistic volume (not empty, not full block) and sufficient triangles.
3. PNG screenshot exists.
4. VLM Verification: Visual confirmation that lower anterior teeth are removed.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simulate_edentulous_mandible(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 1. STL Verification (40 pts)
    stl = result.get("stl_file", {})
    analysis = result.get("stl_analysis", {})
    
    if stl.get("exists") and stl.get("created_during_task"):
        score += 20
        feedback.append("STL file created.")
        
        # Geometric check
        tris = analysis.get("triangles", 0)
        vol = analysis.get("volume", 0)
        
        # Skull volume usually 300k-500k mm^3. 
        # Check for non-trivial mesh (>10k tris) and non-zero volume
        if tris > 10000:
            score += 10
            feedback.append(f"Mesh complexity good ({tris} triangles).")
        else:
            feedback.append(f"Mesh too simple ({tris} triangles).")
            
        if vol > 50000: # Minimal valid skull volume
            score += 10
            feedback.append(f"Mesh volume realistic ({int(vol)} mm3).")
        else:
            feedback.append(f"Mesh volume suspicious ({int(vol)} mm3).")
    else:
        feedback.append("STL file missing or not created during task.")

    # 2. Screenshot Verification (10 pts)
    png = result.get("png_file", {})
    png_path = task_info["metadata"]["png_output_path"]
    
    if png.get("exists") and png.get("created_during_task"):
        score += 10
        feedback.append("Screenshot exported.")
        
        # We need to pull the specific screenshot for VLM if possible, 
        # or rely on the final screenshot if the agent left it on screen.
        # But better to check the *exported* screenshot if we can access it via trajectory or copy.
        # Framework usually provides trajectory. The agent was asked to export a specific view.
        # We will use the VLM on the *exported* image if we can, otherwise the final state.
        # Note: 'traj' contains standard frames. To verify the SPECIFIC exported file content,
        # we would need to download it.
        # STRATEGY: We will copy the exported PNG from the env to a temp file and feed THAT to VLM.
        
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        try:
            copy_from_env(png_path, temp_img.name)
            vlm_image = temp_img.name
        except:
            vlm_image = None
            feedback.append("Could not retrieve exported screenshot for VLM.")
    else:
        feedback.append("Exported screenshot missing.")
        vlm_image = None

    # Fallback to final screenshot if exported one is missing/unreadable, 
    # but strictly we want to verify the specific view they saved.
    if not vlm_image:
        vlm_image = get_final_screenshot(traj)

    # 3. VLM Verification (50 pts)
    if vlm_image:
        prompt = (
            "This is a 3D medical visualization of a skull. "
            "Task: The user should have digitally removed/erased the lower front teeth (incisors/canines). "
            "Look at the lower jaw (mandible). "
            "1. Is the bone of the lower jaw visible and intact? "
            "2. Are the lower front teeth MISSING, leaving a gap or smooth gumline? "
            "Respond JSON: {'jaw_intact': bool, 'teeth_missing': bool, 'confidence': float}"
        )
        
        vlm_res = query_vlm(image=vlm_image, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("jaw_intact") and parsed.get("teeth_missing"):
                score += 50
                feedback.append("VLM confirms lower anterior teeth are removed and jaw is intact.")
            elif not parsed.get("jaw_intact"):
                feedback.append("VLM indicates jaw bone might be missing/damaged.")
            elif not parsed.get("teeth_missing"):
                feedback.append("VLM sees teeth still present.")
        else:
            feedback.append("VLM analysis failed.")
            # Fallback: if VLM fails technically, give partial credit if file checks passed well
            if score >= 40: score += 10 
    else:
        feedback.append("No image available for visual verification.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }