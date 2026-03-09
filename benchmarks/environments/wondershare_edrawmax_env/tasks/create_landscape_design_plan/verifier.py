#!/usr/bin/env python3
"""
Verifier for create_landscape_design_plan task.

Verification Strategy:
1. File Checks: Verify .eddx and .png exist, are recently created, and have non-trivial size.
2. VLM Verification: Analyze the exported PNG (or final screenshot) to confirm visual elements:
   - "Johnson Residence" title
   - Patio/Hardscape
   - Dining Furniture
   - Water Feature
   - Vegetation (Trees/Shrubs)
"""

import json
import os
import tempfile
import logging
import time

# Import standard libraries for VLM handling if available in environment
# (Simulated import for standalone validity)
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_landscape_design_plan(traj, env_info, task_info):
    """
    Verify the landscape design task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # --- Criterion 1: File Existence & Validity (30 pts) ---
    eddx_exists = result.get('eddx_exists', False)
    eddx_fresh = result.get('eddx_created_during_task', False)
    eddx_size = result.get('eddx_size', 0)
    
    png_exists = result.get('png_exists', False)
    png_fresh = result.get('png_created_during_task', False)
    png_size = result.get('png_size', 0)

    # Check EDDX
    if eddx_exists and eddx_fresh and eddx_size > 5000:
        score += 15
        feedback_parts.append(f"Editable file saved ({int(eddx_size/1024)}KB).")
    elif eddx_exists:
        score += 5
        feedback_parts.append("Editable file exists but may be stale or empty.")
    else:
        feedback_parts.append("Editable .eddx file NOT found.")

    # Check PNG
    if png_exists and png_fresh and png_size > 20000:
        score += 15
        feedback_parts.append(f"Image export successful ({int(png_size/1024)}KB).")
    elif png_exists:
        score += 5
        feedback_parts.append("Image file exists but may be stale or empty.")
    else:
        feedback_parts.append("Exported PNG file NOT found.")

    # --- Criterion 2: Visual Content Verification (70 pts) ---
    
    # Retrieve the PNG image for VLM analysis
    # If the agent didn't export the PNG, fallback to the final screenshot
    image_to_analyze = None
    
    if png_exists and png_size > 1000:
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result.get('png_path'), temp_png.name)
            image_to_analyze = temp_png.name
        except Exception as e:
            logger.warning(f"Failed to copy exported PNG: {e}")
    
    # Fallback to final screenshot if export failed
    if not image_to_analyze:
        image_to_analyze = get_final_screenshot(traj)
        if image_to_analyze:
            feedback_parts.append("Using final screenshot for verification (export missing).")
        else:
            feedback_parts.append("No image available for visual verification.")

    vlm_score = 0
    if image_to_analyze:
        prompt = """
        You are verifying a landscape design plan created in EdrawMax.
        Analyze the image and check for the presence of the following specific elements:
        
        1. TITLE: Text reading "Johnson Residence" (or similar).
        2. PATIO: A paved area or hardscape structure.
        3. DINING: A table with chairs (dining set).
        4. WATER: A pond, pool, or fountain (usually blue).
        5. VEGETATION: Trees, shrubs, or green plant symbols.
        6. LABELS: Text labels pointing to elements (e.g., "Patio", "Water", "Tree").

        Respond in JSON format:
        {
            "has_title": boolean,
            "has_patio": boolean,
            "has_dining_set": boolean,
            "has_water_feature": boolean,
            "has_vegetation": boolean,
            "has_labels": boolean,
            "description": "Brief description of what you see"
        }
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=image_to_analyze)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                
                # Scoring breakdown
                if parsed.get('has_title', False):
                    vlm_score += 10
                    feedback_parts.append("Title 'Johnson Residence' found.")
                
                if parsed.get('has_patio', False):
                    vlm_score += 10
                    feedback_parts.append("Patio detected.")
                    
                if parsed.get('has_dining_set', False):
                    vlm_score += 15
                    feedback_parts.append("Dining furniture detected.")
                    
                if parsed.get('has_water_feature', False):
                    vlm_score += 15
                    feedback_parts.append("Water feature detected.")
                    
                if parsed.get('has_vegetation', False):
                    vlm_score += 10
                    feedback_parts.append("Vegetation detected.")
                    
                if parsed.get('has_labels', False):
                    vlm_score += 10
                    feedback_parts.append("Labels detected.")
                    
            else:
                feedback_parts.append("Visual verification failed (VLM error).")
        except Exception as e:
            feedback_parts.append(f"Visual verification error: {str(e)}")
        finally:
            if temp_png and os.path.exists(temp_png.name):
                os.unlink(temp_png.name)

    score += vlm_score

    # Final Pass/Fail Check
    # Must have files (at least 15 pts there) and significant visual elements
    passed = (score >= 60) and (eddx_exists or png_exists)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }