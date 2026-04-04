#!/usr/bin/env python3
"""
Verifier for Shading Correction Segmentation task.

Criteria:
1. Output files (mask.png, count.csv) exist and created during task. (30 pts)
2. Particle count > 50 (Indicates successful shading correction; uncorrected is ~40). (40 pts)
3. VLM Verification of Mask: Checks if corner particles are visible/segmented. (30 pts)
"""

import json
import os
import tempfile
import logging
import shutil

# Import VLM utils from the environment framework
try:
    from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Fallback/stub for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None
    def sample_trajectory_frames(traj, n=1):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_shading_correction(traj, env_info, task_info):
    """
    Verifies the shading correction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing."}

    # 1. Retrieve JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/shading_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence & Anti-Gaming (30 pts) ---
    mask_exists = result_data.get('mask_exists', False)
    mask_fresh = result_data.get('mask_created_during_task', False)
    csv_exists = result_data.get('csv_exists', False)
    csv_fresh = result_data.get('csv_created_during_task', False)

    if mask_exists and mask_fresh:
        score += 15
        feedback.append("Mask image created.")
    elif mask_exists:
        score += 5
        feedback.append("Mask image exists but has old timestamp.")
    else:
        feedback.append("Mask image missing.")

    if csv_exists and csv_fresh:
        score += 15
        feedback.append("Measurement CSV created.")
    elif csv_exists:
        score += 5
        feedback.append("Measurement CSV exists but has old timestamp.")
    else:
        feedback.append("Measurement CSV missing.")

    # --- Criterion 2: Particle Count (40 pts) ---
    # Uncorrected image typically yields ~40-45 particles with standard auto-threshold.
    # Corrected image yields ~60-65.
    count = result_data.get('particle_count', 0)
    
    if count >= 50:
        score += 40
        feedback.append(f"Particle count is healthy ({count} > 50). Shading likely corrected.")
    elif count >= 1:
        # Partial credit if they found something but likely missed the corners
        score += 10
        feedback.append(f"Particle count is low ({count} < 50). Likely failed to correct shading in corners.")
    else:
        feedback.append("No particles detected.")

    # --- Criterion 3: Visual Verification (30 pts) ---
    # Retrieve the mask image to check if corners are populated
    mask_local_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    vlm_passed = False
    
    if mask_exists:
        try:
            copy_from_env(result_data.get('mask_path', ''), mask_local_path)
            
            # VLM Prompt
            prompt = (
                "This is a binary segmentation mask from a microscopy image. "
                "The original image had dark corners (vignetting). "
                "Check if the segmentation succeeded in the corners. "
                "Are there white blobs visible near the corners of the image, or are the corners completely black? "
                "Answer yes if corner blobs are visible."
            )
            
            vlm_response = query_vlm(prompt=prompt, image=mask_local_path)
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                # Assuming VLM returns unstructured text, we might parse boolean or rely on 'parsed' 
                # if the framework supports structured output. 
                # For this generic implementation, we assume we get a boolean or confidence.
                # Adjust based on specific VLM utility implementation.
                
                # Simple keyword check if structured parsing isn't guaranteed
                answer_text = str(vlm_response).lower()
                if "yes" in answer_text or "visible" in answer_text:
                    score += 30
                    vlm_passed = True
                    feedback.append("VLM confirms particles detected in corners.")
                else:
                    feedback.append("VLM did not clearly see corner particles.")
            else:
                feedback.append("VLM verification failed to run.")
                
        except Exception as e:
            feedback.append(f"Could not retrieve mask for verification: {e}")
        finally:
            if os.path.exists(mask_local_path):
                os.unlink(mask_local_path)
    else:
        feedback.append("Cannot perform visual verification (mask missing).")

    # Final Pass Decision
    # Need reasonable score AND count > 50
    passed = (score >= 70) and (count >= 50)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": {
            "particle_count": count,
            "mask_verification": vlm_passed
        }
    }