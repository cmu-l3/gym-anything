#!/usr/bin/env python3
"""
Verifier for virtual_craniotomy_planning task.

Scoring (100 pts total):
1. Files Exist (20 pts)
2. Main Skull Validity (30 pts)
   - Triangle count > 100k
   - Created during task
3. Bone Flap Validity (30 pts)
   - Triangle count 2k - 80k
   - Created during task
4. VLM / Anti-Gaming (20 pts)
   - VLM confirms Manual Edition usage or separated parts
   - Files are distinct (not identical copies)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def verify_virtual_craniotomy(traj, env_info, task_info):
    """
    Verify the virtual craniotomy task.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_skull_tris = metadata.get("min_skull_triangles", 100000)
    min_flap_tris = metadata.get("min_flap_triangles", 2000)
    max_flap_tris = metadata.get("max_flap_triangles", 80000)

    # 1. Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result JSON: {str(e)}"
        }

    skull = result.get("skull", {})
    flap = result.get("flap", {})
    
    score = 0
    feedback_parts = []

    # --- Criterion 1: Files Exist (20 pts) ---
    files_exist_score = 0
    if skull.get("exists"):
        files_exist_score += 10
    else:
        feedback_parts.append("Missing skull_with_defect.stl")
        
    if flap.get("exists"):
        files_exist_score += 10
    else:
        feedback_parts.append("Missing bone_flap.stl")
        
    score += files_exist_score
    if files_exist_score > 0:
        feedback_parts.append(f"Files exist check: {files_exist_score}/20 pts")

    # --- Criterion 2: Main Skull Validity (30 pts) ---
    skull_score = 0
    skull_tris = skull.get("triangles", 0)
    
    if skull.get("exists") and skull.get("valid"):
        if skull_tris > min_skull_tris:
            skull_score += 20
            feedback_parts.append(f"Skull geometry valid ({skull_tris} tris)")
        else:
            feedback_parts.append(f"Skull too simple ({skull_tris} < {min_skull_tris})")
            
        if skull.get("created_during_task"):
            skull_score += 10
        else:
            feedback_parts.append("Skull file timestamp check failed (stale file)")
    
    score += skull_score

    # --- Criterion 3: Bone Flap Validity (30 pts) ---
    flap_score = 0
    flap_tris = flap.get("triangles", 0)
    
    if flap.get("exists") and flap.get("valid"):
        if min_flap_tris <= flap_tris <= max_flap_tris:
            flap_score += 20
            feedback_parts.append(f"Flap geometry valid ({flap_tris} tris)")
        else:
            feedback_parts.append(f"Flap size invalid ({flap_tris} tris, expected {min_flap_tris}-{max_flap_tris})")
            
        if flap.get("created_during_task"):
            flap_score += 10
        else:
            feedback_parts.append("Flap file timestamp check failed")

    score += flap_score

    # --- Criterion 4: Distinctness & VLM (20 pts) ---
    bonus_score = 0
    
    # Check distinctness
    if skull_tris > 0 and flap_tris > 0:
        # They shouldn't be identical (allow 1% tolerance just in case, but usually distinct)
        if abs(skull_tris - flap_tris) > 100:
            bonus_score += 5
            feedback_parts.append("Files are distinct meshes")
        else:
            feedback_parts.append("Files appear identical (triangles match)")

    # VLM Verification
    vlm_prompt = """
    Check these screenshots of InVesalius usage.
    Did the user perform manual editing on the skull?
    Look for:
    1. The 'Manual Edition' or 'Slice Editor' tab being active.
    2. Usage of 'Eraser' tool or drawing on the slices.
    3. A visible hole or gap created in the 3D skull model or slice views.
    
    Reply JSON: {"manual_editing_seen": bool, "hole_visible": bool}
    """
    
    # We query VLM if we have minimal file success, to confirm process
    if score >= 40:
        try:
            frames = sample_trajectory_frames(traj, 4)
            final_scr = get_final_screenshot(traj)
            if frames and final_scr:
                vlm_res = query_vlm(frames + [final_scr], vlm_prompt)
                parsed = vlm_res.get("parsed", {})
                
                if parsed.get("manual_editing_seen") or parsed.get("hole_visible"):
                    bonus_score += 15
                    feedback_parts.append("VLM confirmed manual editing/hole creation")
                else:
                    feedback_parts.append("VLM did not see manual editing steps")
            else:
                # If no images, we can't verify process, but grant partial points if files look great
                if score >= 70:
                    bonus_score += 5 # Benefit of doubt for robust file output
                    feedback_parts.append("No VLM images, verifying by file metrics only")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            if score >= 70: bonus_score += 5

    score += bonus_score

    # Final logic
    # Must have both valid files to pass
    passed = (skull_score >= 20) and (flap_score >= 20) and (score >= 70)

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }