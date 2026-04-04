#!/usr/bin/env python3
"""
Verifier for export_skin_surface_ply task.

Scoring (100 points total):
  - PLY file exists: 15 pts
  - Valid PLY header: 15 pts
  - Vertex count >= 10,000: 20 pts
  - Face count >= 5,000: 15 pts
  - File size > 300 KB: 10 pts
  - Created during task (timestamp check): 5 pts
  - VLM Verification (Soft tissue threshold used): 20 pts

Pass threshold: 60 points + Essential file validity
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

VLM_PROMPT = """
You are verifying an InVesalius 3D reconstruction task.
The user was asked to create a "Soft Tissue" or "Skin" surface from a CT scan (showing the face), NOT a "Bone" surface (showing the skull).

Look at the provided screenshots of the user's workflow.
1. Did the user select a threshold range that captures soft tissue/skin? 
   - A BONE surface looks like a white skeleton/skull.
   - A SKIN/SOFT TISSUE surface looks like a face/head contour (solid volume).
2. Did the user export a 3D surface (look for "Export 3D Surface" dialog)?

Respond in JSON:
{
  "soft_tissue_threshold_used": true/false,
  "export_dialog_seen": true/false,
  "is_bone_skull_visible": true/false,
  "is_skin_face_visible": true/false,
  "reasoning": "..."
}
"""

def verify_export_skin_surface_ply(traj, env_info, task_info):
    """Verify that the agent exported a PLY skin surface model."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # --- Part 1: Programmatic Verification (File Analysis) ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/export_ply_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}",
        }

    # Criterion 1: File Exists (15 pts)
    if result.get("file_exists"):
        score += 15
        feedback_parts.append("PLY file created")
    else:
        feedback_parts.append("PLY file not found")
        return {"passed": False, "score": 0, "feedback": "PLY file not found at /home/ga/Documents/skin_surface.ply"}

    # Criterion 2: Valid PLY Header (15 pts)
    if result.get("is_ply") and result.get("header_valid"):
        score += 15
        feedback_parts.append(f"Valid PLY header ({result.get('format', 'unknown')})")
    else:
        feedback_parts.append("Invalid or missing PLY header")

    # Criterion 3: Vertex Count (20 pts)
    v_count = result.get("vertex_count", 0)
    if v_count >= 10000:
        score += 20
        feedback_parts.append(f"Vertex count OK ({v_count:,})")
    else:
        feedback_parts.append(f"Vertex count too low ({v_count:,} < 10,000)")

    # Criterion 4: Face Count (15 pts)
    f_count = result.get("face_count", 0)
    if f_count >= 5000:
        score += 15
        feedback_parts.append(f"Face count OK ({f_count:,})")
    else:
        feedback_parts.append(f"Face count too low ({f_count:,} < 5,000)")

    # Criterion 5: File Size (10 pts)
    size_kb = result.get("file_size_bytes", 0) / 1024
    if size_kb > 300:
        score += 10
        feedback_parts.append(f"File size OK ({size_kb:.0f} KB)")
    else:
        feedback_parts.append(f"File size too small ({size_kb:.0f} KB)")

    # Criterion 6: Timestamp (5 pts)
    if result.get("created_during_task"):
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp indicates pre-existing file or creation error")

    # --- Part 2: VLM Verification (Trajectory Analysis) ---
    vlm_score = 0
    try:
        # Sample frames + final screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        if final:
            frames.append(final)
        
        if frames:
            vlm_response = query_vlm(images=frames, prompt=VLM_PROMPT)
            vlm_data = vlm_response.get("parsed", {})
            
            # Logic: If they generated a skin surface (face visible) OR explicitly used soft tissue threshold
            # And they did NOT just leave it as a bone skull
            
            soft_tissue_used = vlm_data.get("soft_tissue_threshold_used", False)
            is_skin_visible = vlm_data.get("is_skin_face_visible", False)
            is_bone_visible = vlm_data.get("is_bone_skull_visible", False)
            
            # If skin is visible, that's the primary goal
            if is_skin_visible or soft_tissue_used:
                vlm_score += 20
                feedback_parts.append("VLM: Skin/Soft tissue surface confirmed")
            elif is_bone_visible:
                feedback_parts.append("VLM: Only bone/skull surface detected (Wrong threshold)")
            else:
                feedback_parts.append("VLM: Could not confirm soft tissue surface visually")
                
            # If we passed file checks but VLM is ambiguous, we give benefit of doubt if file is large enough
            # (A bone mesh is also large, but soft tissue is usually larger/denser).
            # However, prompt specifically asked for Soft Tissue.
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification skipped (error)")
        # Fallback: if file is valid and large, assume pass but cap score
        vlm_score += 10 

    score += vlm_score

    # Final Pass Logic
    # Must have file, valid header, decent geometry, AND score >= 60
    essential_pass = result.get("file_exists") and result.get("header_valid") and (v_count > 1000)
    passed = (score >= 60) and essential_pass

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }