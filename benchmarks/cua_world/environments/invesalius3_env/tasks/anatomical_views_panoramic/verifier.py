#!/usr/bin/env python3
"""
Verifier for anatomical_views_panoramic task.

Criteria:
1. Files exist and are valid PNGs (30 pts)
2. Files were created during the task (15 pts)
3. Files are distinct (not copies of each other) (10 pts)
4. VLM Verification of content (45 pts):
   - Frontalis shows Anterior view
   - Lateralis shows Right Lateral view
   - Basilaris shows Inferior view
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_anatomical_views(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_files = metadata.get('files', [])
    
    score = 0
    feedback_parts = []
    
    # --- Load programmatic results ---
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}

    files_info = result.get("files", {})
    
    # Map keys to paths for VLM
    key_map = {
        "frontalis": "/home/ga/Documents/norma_frontalis.png",
        "lateralis": "/home/ga/Documents/norma_lateralis.png",
        "basilaris": "/home/ga/Documents/norma_basilaris.png"
    }

    # --- Criterion 1 & 2: File Existence, Validity & Timestamps (45 pts total) ---
    files_found = 0
    valid_files_count = 0
    
    for key, path in key_map.items():
        f_info = files_info.get(key, {})
        view_name = key.capitalize()
        
        if f_info.get("exists"):
            files_found += 1
            if f_info.get("valid_png") and f_info.get("size_bytes", 0) > 30000: # >30KB
                if f_info.get("created_during_task"):
                    score += 15 # 15 pts per valid file created during task
                    valid_files_count += 1
                    feedback_parts.append(f"{view_name}: OK")
                else:
                    score += 5 # Partial credit if file exists but old (unlikely given setup cleans it)
                    feedback_parts.append(f"{view_name}: Old file")
            else:
                feedback_parts.append(f"{view_name}: Invalid/Empty")
        else:
            feedback_parts.append(f"{view_name}: Missing")

    # --- Criterion 3: Distinct Files (10 pts) ---
    if valid_files_count >= 2:
        if result.get("distinct_files", True):
            score += 10
            feedback_parts.append("Files are distinct")
        else:
            feedback_parts.append("Warning: Files are identical copies")

    # --- Criterion 4: VLM Visual Verification (45 pts) ---
    # We will copy the generated PNGs to host to verify their content
    # This is more accurate than checking trajectory for this specific "export" task
    
    vlm_score = 0
    vlm_passed_count = 0
    
    for key, path in key_map.items():
        f_info = files_info.get(key, {})
        if not f_info.get("exists") or not f_info.get("valid_png"):
            continue
            
        # Copy image to host
        try:
            local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            local_img.close()
            copy_from_env(path, local_img.name)
            
            # Define specific prompts per view
            prompts = {
                "frontalis": "Does this image show the FRONT view of a human skull (face forward)? Look for eye sockets (orbits) and nasal cavity facing the camera. Answer YES or NO.",
                "lateralis": "Does this image show the SIDE (lateral) view of a human skull? Look for the profile view. Answer YES or NO.",
                "basilaris": "Does this image show the BOTTOM (base) view of a human skull? Look for the foramen magnum (large hole) or teeth arch from below. Answer YES or NO."
            }
            
            vlm_resp = query_vlm(
                prompt=f"Task: Verify anatomical view.\n{prompts[key]}",
                image=local_img.name
            )
            
            if os.path.exists(local_img.name):
                os.unlink(local_img.name)
                
            if vlm_resp.get("success"):
                # Basic parsing of YES/NO
                content = vlm_resp.get("content", "").upper()
                if "YES" in content:
                    vlm_score += 15
                    vlm_passed_count += 1
                    feedback_parts.append(f"{key} visual check: PASS")
                else:
                    feedback_parts.append(f"{key} visual check: FAIL")
            else:
                # If VLM fails, give partial benefit of doubt if file size is substantial (heuristic)
                # But safer to just log error
                feedback_parts.append(f"{key} visual check: Error")

        except Exception as e:
            feedback_parts.append(f"Verification error for {key}: {str(e)}")

    score += vlm_score

    # Final tally
    passed = (score >= 60) and (valid_files_count >= 2) and (vlm_passed_count >= 1)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "valid_files": valid_files_count,
            "distinct": result.get("distinct_files"),
            "vlm_matches": vlm_passed_count
        }
    }