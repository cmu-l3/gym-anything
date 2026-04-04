#!/usr/bin/env python3
"""
Verifier for create_idef0_function_model task.

Verification Strategy:
1. File Validation (20 pts):
   - Check if .eddx and .png files exist and were created during the task.
   - Check file sizes to ensure they aren't empty.

2. VLM Spatial & Content Verification (80 pts):
   - Uses the exported PNG (or final screenshot if PNG missing) to verify IDEF0 strict rules.
   - Checks for:
     - Central Box: "Process Customer Order"
     - Inputs (Left): "Purchase Order"
     - Controls (Top): "Credit Policy", "Inventory Rules"
     - Outputs (Right): "Confirmed Invoice", "Pick List"
     - Mechanisms (Bottom): "Order Management System", "Sales Associate"
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utils provided by the framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs):
        return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_idef0_function_model(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_eddx_path = metadata.get('expected_eddx_path')
    expected_png_path = metadata.get('expected_png_path')

    # ============================================================
    # 1. Retrieve Task Result JSON
    # ============================================================
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # ============================================================
    # 2. Score File Artifacts (20 points)
    # ============================================================
    score = 0
    feedback_parts = []
    
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_valid_time = result_data.get('eddx_created_during_task', False)
    eddx_size = result_data.get('eddx_size_bytes', 0)
    
    png_exists = result_data.get('png_exists', False)
    png_valid_time = result_data.get('png_created_during_task', False)
    png_size = result_data.get('png_size_bytes', 0)

    # Score EDDX
    if eddx_exists and eddx_size > 2000: # Empty template is usually ~2KB, content adds size
        if eddx_valid_time:
            score += 10
            feedback_parts.append("Valid .eddx file created.")
        else:
            score += 5
            feedback_parts.append("Warning: .eddx file timestamp is suspect (pre-existing?).")
    else:
        feedback_parts.append("Missing or empty .eddx file.")

    # Score PNG
    image_to_verify = None
    
    # Try to retrieve the exported PNG for VLM analysis
    if png_exists and png_size > 5000:
        if png_valid_time:
            score += 10
            feedback_parts.append("Valid .png export created.")
        else:
            score += 5
            feedback_parts.append("Warning: .png file timestamp is suspect.")
            
        # Download the PNG for VLM
        temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(expected_png_path, temp_png.name)
            image_to_verify = temp_png.name
        except Exception:
            logger.warning("Could not copy exported PNG, falling back to screenshot.")
    else:
        feedback_parts.append("Missing or empty .png export.")

    # Fallback to final screenshot if export failed
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)
        if image_to_verify:
            feedback_parts.append("Using final screenshot for verification.")
        else:
            feedback_parts.append("No image available for verification.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ============================================================
    # 3. VLM Verification of IDEF0 Rules (80 points)
    # ============================================================
    
    vlm_prompt = """
    You are an expert Systems Analyst verifying an IDEF0 Context Diagram (Node A-0).
    The diagram should have a central box labeled 'Process Customer Order' and arrows connecting to specific sides.

    Please analyze the image and check for the following STRICT requirements:

    1. CENTRAL_FUNCTION: Is there a main box labeled "Process Customer Order"?
    2. INPUTS (LEFT): Is there an arrow labeled "Purchase Order" entering the box from the LEFT side?
    3. CONTROLS (TOP): Are there arrows labeled "Credit Policy" AND "Inventory Rules" entering the box from the TOP side?
    4. OUTPUTS (RIGHT): Are there arrows labeled "Confirmed Invoice" AND "Pick List" exiting the box to the RIGHT side?
    5. MECHANISMS (BOTTOM): Are there arrows labeled "Order Management System" AND "Sales Associate" entering the box from the BOTTOM side?
    6. TITLE: Is the text "Node A-0: Order Processing Context" visible?

    Respond in JSON format:
    {
        "central_box_correct": boolean,
        "input_left_correct": boolean,
        "controls_top_correct": boolean,
        "outputs_right_correct": boolean,
        "mechanisms_bottom_correct": boolean,
        "title_present": boolean,
        "missing_items": ["list", "of", "missing", "labels"],
        "spatial_errors": ["description of wrong arrow directions"]
    }
    """

    vlm_response = query_vlm(prompt=vlm_prompt, image=image_to_verify)
    
    if vlm_response.get("success"):
        analysis = vlm_response.get("parsed", {})
        
        # Scoring based on VLM analysis
        # Central Box (10 pts)
        if analysis.get("central_box_correct"):
            score += 10
        else:
            feedback_parts.append("Central function box missing or mislabeled.")

        # Inputs (Left) (15 pts)
        if analysis.get("input_left_correct"):
            score += 15
        else:
            feedback_parts.append("Input 'Purchase Order' missing or not on LEFT.")

        # Controls (Top) (15 pts)
        if analysis.get("controls_top_correct"):
            score += 15
        else:
            feedback_parts.append("Controls (Credit/Inventory) missing or not on TOP.")

        # Outputs (Right) (15 pts)
        if analysis.get("outputs_right_correct"):
            score += 15
        else:
            feedback_parts.append("Outputs (Invoice/Pick List) missing or not on RIGHT.")

        # Mechanisms (Bottom) (15 pts)
        if analysis.get("mechanisms_bottom_correct"):
            score += 15
        else:
            feedback_parts.append("Mechanisms (OMS/Sales) missing or not on BOTTOM.")

        # Title (10 pts)
        if analysis.get("title_present"):
            score += 10
        else:
            feedback_parts.append("Title missing.")
            
        # Add VLM observations to feedback
        if analysis.get("missing_items"):
            feedback_parts.append(f"Missing items: {', '.join(analysis['missing_items'])}")
        if analysis.get("spatial_errors"):
            feedback_parts.append(f"Spatial errors: {', '.join(analysis['spatial_errors'])}")
            
    else:
        feedback_parts.append(f"VLM verification failed: {vlm_response.get('error')}")

    # Cleanup temp image
    if image_to_verify and os.path.exists(image_to_verify) and image_to_verify != get_final_screenshot(traj):
        try:
            os.unlink(image_to_verify)
        except:
            pass

    # ============================================================
    # 4. Final Result
    # ============================================================
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }