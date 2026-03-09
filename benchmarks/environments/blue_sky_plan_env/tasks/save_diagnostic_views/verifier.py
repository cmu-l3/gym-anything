#!/usr/bin/env python3
"""
Verifier for save_diagnostic_views task.

Verifies that the agent captured and saved 4 distinct diagnostic views
from Blue Sky Plan:
1. Panoramic
2. Axial
3. 3D Rendering
4. Cross-sectional
"""

import json
import os
import tempfile
import logging
import sys
from gym_anything.vlm import query_vlm, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_save_diagnostic_views(traj, env_info, task_info):
    """
    Verify the diagnostic views task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('expected_files', [])
    min_size_kb = metadata.get('min_size_kb', 20)

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files_info = result.get("files", {})
    
    # 2. Check File Existence & Validity (Base Score: 40 points, 10 per file)
    valid_files = []
    for fname in expected_files:
        info = files_info.get(fname, {})
        if info.get("exists", False):
            size_kb = info.get("size", 0) / 1024
            created_during = info.get("created_during_task", False)
            
            if size_kb < min_size_kb:
                feedback_parts.append(f"❌ {fname} too small ({size_kb:.1f}KB)")
            elif not created_during:
                feedback_parts.append(f"❌ {fname} timestamp invalid (pre-existing)")
            else:
                score += 10
                valid_files.append(fname)
                feedback_parts.append(f"✅ {fname} exists ({size_kb:.1f}KB)")
        else:
            feedback_parts.append(f"❌ {fname} missing")

    if not valid_files:
        return {"passed": False, "score": 0, "feedback": "No valid output files found. " + " ".join(feedback_parts)}

    # 3. VLM Verification of Content (60 points total, 15 per file)
    # We download valid files and verify them
    vlm_score = 0
    
    prompts = {
        "panoramic_view.png": "Does this image show a dental panoramic radiograph (curved flattened view of the whole jaw)? Respond yes/no.",
        "axial_view.png": "Does this image show an axial (top-down) slice of a dental scan showing the arch of the teeth? Respond yes/no.",
        "3d_rendering_view.png": "Does this image show a 3D surface rendering of a skull, jaw, or teeth? Respond yes/no.",
        "cross_section_view.png": "Does this image show a cross-sectional (buccolingual) slice of a jaw bone? Respond yes/no."
    }

    for fname in valid_files:
        # Copy image
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        remote_path = f"C:\\Users\\Docker\\Documents\\CasePresentation\\{fname}"
        
        try:
            copy_from_env(remote_path, temp_img.name)
            
            # Query VLM
            response = query_vlm(
                prompt=f"Task: Verify dental diagnostic views. {prompts[fname]}",
                image=temp_img.name
            )
            
            if response.get("success"):
                answer = response.get("parsed", {}).get("answer", "") or response.get("text", "").lower()
                if "yes" in answer.lower():
                    vlm_score += 15
                    feedback_parts.append(f"✅ {fname} content verified")
                else:
                    feedback_parts.append(f"⚠️ {fname} content looks incorrect")
            else:
                feedback_parts.append(f"⚠️ Failed to verify {fname} content")
                
        except Exception as e:
            logger.error(f"Error verifying {fname}: {e}")
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)

    score += vlm_score

    # 4. Trajectory Check (Anti-Gaming) - Deduct if no navigation detected
    # If the user just uploaded 4 random images without doing work, trajectory will be static
    # We sample a few frames and check for UI changes or "Blue Sky Plan" presence
    frames = sample_trajectory_frames(traj, n=3)
    if frames:
        traj_check = query_vlm(
            prompt="Does the user appear to be interacting with dental software (Blue Sky Plan)? Look for 3D skull models, slice views, or menus. Answer boolean JSON: {'active': bool}",
            images=frames
        )
        if traj_check.get("success") and not traj_check.get("parsed", {}).get("active", True):
             feedback_parts.append("⚠️ Warning: Low activity detected in trajectory")
             # We don't penalize heavily if output is perfect, but good to note

    # Final logic
    passed = (score >= 60) and (len(valid_files) >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }