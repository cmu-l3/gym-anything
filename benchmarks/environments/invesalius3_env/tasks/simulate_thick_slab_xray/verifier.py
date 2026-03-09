#!/usr/bin/env python3
"""
Verifier for simulate_thick_slab_xray task.

Criteria:
1. Files Exist & Created During Task (40 pts)
2. Valid PNG Format (10 pts)
3. VLM Visual Verification (50 pts)
   - Checks for "Thick Slab" effect (transparency/overlapping bone) vs Thin Slice.
   - Checks for correct Anatomical Orientation (Coronal vs Sagittal).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_thick_slab_export(traj, env_info, task_info):
    # 1. Setup & Copy Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    files = result_data.get("files", {})
    coronal_info = files.get("coronal", {})
    sagittal_info = files.get("sagittal", {})

    score = 0
    feedback = []
    
    # 2. File Verification (Programmatic) - Max 50 pts
    
    # Coronal File
    if coronal_info.get("exists") and coronal_info.get("created_during_task") and coronal_info.get("valid_png"):
        score += 20
        feedback.append("Coronal file created successfully.")
    elif not coronal_info.get("exists"):
        feedback.append("Coronal file missing.")
    elif not coronal_info.get("created_during_task"):
        feedback.append("Coronal file timestamp invalid (old file).")
    
    if coronal_info.get("size", 0) > 20000:
        score += 5
    else:
        feedback.append("Coronal file suspiciously small.")

    # Sagittal File
    if sagittal_info.get("exists") and sagittal_info.get("created_during_task") and sagittal_info.get("valid_png"):
        score += 20
        feedback.append("Sagittal file created successfully.")
    elif not sagittal_info.get("exists"):
        feedback.append("Sagittal file missing.")
    elif not sagittal_info.get("created_during_task"):
        feedback.append("Sagittal file timestamp invalid (old file).")
        
    if sagittal_info.get("size", 0) > 20000:
        score += 5
    else:
        feedback.append("Sagittal file suspiciously small.")

    # Stop if files don't exist to save VLM costs/errors
    if score < 40:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Files missing or invalid: " + " ".join(feedback)
        }

    # 3. VLM Verification (Visual) - Max 50 pts
    # We download the actual exported images to verify them.
    
    vlm_score = 0
    
    def check_image_content(remote_path, orientation):
        """Helper to copy image and query VLM"""
        local_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        local_img.close()
        try:
            copy_from_env(remote_path, local_img.name)
            
            prompt = f"""
            Analyze this medical image exported from InVesalius.
            Task Requirement: A '{orientation}' view of the skull with 'Thick Slab' rendering (simulating an X-ray).
            
            1. Orientation: Is this a {orientation} view? (Coronal = face-on/back-on; Sagittal = side profile).
            2. Rendering Style: Is this a 'Thick Slab' or X-ray-like projection showing overlapping internal structures/transparency? 
               (It should NOT be a standard thin CT slice which looks like a single cross-section with black voids).
            
            Respond in JSON:
            {{
                "is_correct_orientation": true/false,
                "is_thick_slab_effect": true/false,
                "explanation": "brief reasoning"
            }}
            """
            
            response = query_vlm(prompt=prompt, image=local_img.name)
            if response.get("success"):
                return response.get("parsed", {})
            return {}
        except Exception as e:
            logger.error(f"VLM check failed for {orientation}: {e}")
            return {}
        finally:
            if os.path.exists(local_img.name):
                os.unlink(local_img.name)

    # Verify Coronal
    coronal_res = check_image_content(coronal_info["path"], "Coronal")
    if coronal_res.get("is_correct_orientation"):
        vlm_score += 10
        feedback.append("VLM: Coronal orientation confirmed.")
    else:
        feedback.append(f"VLM: Coronal orientation incorrect ({coronal_res.get('explanation')}).")
        
    if coronal_res.get("is_thick_slab_effect"):
        vlm_score += 15
        feedback.append("VLM: Coronal thick-slab effect confirmed.")
    else:
        feedback.append(f"VLM: Coronal thick-slab effect missing ({coronal_res.get('explanation')}).")

    # Verify Sagittal
    sagittal_res = check_image_content(sagittal_info["path"], "Sagittal")
    if sagittal_res.get("is_correct_orientation"):
        vlm_score += 10
        feedback.append("VLM: Sagittal orientation confirmed.")
    else:
        feedback.append(f"VLM: Sagittal orientation incorrect ({sagittal_res.get('explanation')}).")
        
    if sagittal_res.get("is_thick_slab_effect"):
        vlm_score += 15
        feedback.append("VLM: Sagittal thick-slab effect confirmed.")
    else:
        feedback.append(f"VLM: Sagittal thick-slab effect missing ({sagittal_res.get('explanation')}).")

    total_score = score + vlm_score
    passed = total_score >= 70

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }