#!/usr/bin/env python3
"""
Verifier for visualize_cranial_cross_section task.

Verification Strategy:
1. Programmatic: Check if /home/ga/Documents/skull_cross_section.png exists, is a PNG, and was created during the task.
2. VLM: Analyze the image content to ensure it shows a 3D skull with a cut plane applied (cross-section visible).
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_visualize_cranial_cross_section(traj, env_info, task_info):
    """
    Verify that the agent created a screenshot showing a cut 3D skull model.
    """
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Verification infrastructure missing (copy_from_env or query_vlm)"}

    # 1. Retrieve JSON result from container
    try:
        tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_json.close()
        copy_from_env("/tmp/task_result.json", tmp_json.name)
        with open(tmp_json.name) as f:
            result = json.load(f)
        os.unlink(tmp_json.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task status: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Validity (40 pts) ---
    file_valid = False
    if result.get("file_exists"):
        if result.get("is_png"):
            if result.get("created_during_task"):
                if result.get("file_size_bytes", 0) > 10240: # > 10KB
                    score += 40
                    file_valid = True
                    feedback_parts.append("Valid PNG screenshot exported")
                else:
                    feedback_parts.append("File too small to be a valid screenshot")
            else:
                feedback_parts.append("File timestamp indicates it was not created during this task")
        else:
            feedback_parts.append("File exists but is not a valid PNG")
    else:
        feedback_parts.append("Output file not found")

    # If file is missing or invalid, we can check the system screenshot as a fallback for partial credit,
    # but the task explicitly asked to *export* the file.
    if not file_valid:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # --- Criterion 2: Visual Analysis (60 pts) ---
    # Retrieve the actual image file to send to VLM
    try:
        tmp_img = tempfile.NamedTemporaryFile(delete=False, suffix=".png")
        tmp_img.close()
        copy_from_env(result["output_path"], tmp_img.name)
        
        # Define VLM Prompt
        prompt = """
        Analyze this screenshot from a medical software (InVesalius).
        
        I am looking for a 3D reconstruction of a skull that has been SLICED or CUT open using a clipping plane tool.
        
        Please answer the following with Yes or No:
        1. Is there a 3D model of a skull (or bone structure) visible?
        2. Is the model cut/sliced/clipped (i.e., is part of it removed to show the inside)?
        3. Can you see the internal bone structure or cross-section (the cut edge)?
        4. Is the cut roughly sagittal (splitting left/right)?
        
        Return JSON: {"skull_visible": bool, "is_cut": bool, "internal_structure_visible": bool, "sagittal_cut": bool}
        """
        
        vlm_response = query_vlm(prompt=prompt, image=tmp_img.name)
        os.unlink(tmp_img.name)
        
        if vlm_response.get("success"):
            analysis = vlm_response.get("parsed", {})
            
            # Scoring VLM results
            if analysis.get("skull_visible"):
                score += 10
            else:
                feedback_parts.append("No skull model detected")
                
            if analysis.get("is_cut"):
                score += 25
                feedback_parts.append("Cut plane applied")
            else:
                feedback_parts.append("Model appears solid/uncut")
                
            if analysis.get("internal_structure_visible"):
                score += 15
                feedback_parts.append("Internal structure visible")
                
            if analysis.get("sagittal_cut"):
                score += 10
                feedback_parts.append("Sagittal orientation correct")
            else:
                feedback_parts.append("Cut orientation might not be sagittal (minor issue)")
                
        else:
            feedback_parts.append("VLM analysis failed")
            
    except Exception as e:
        feedback_parts.append(f"Failed to process image for VLM: {e}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }