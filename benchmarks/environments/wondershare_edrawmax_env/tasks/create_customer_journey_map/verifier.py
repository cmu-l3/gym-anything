#!/usr/bin/env python3
"""
Verifier for create_customer_journey_map task.

Verifies that:
1. Agent created and saved an EDDX file of sufficient size/complexity.
2. Agent exported a PNG file of sufficient size.
3. VLM: Diagram contains "Customer Journey" title.
4. VLM: Diagram contains multiple phases (columns).
5. VLM: Diagram uses color coding (green/yellow/red).
6. VLM: Workflow progression is visible in trajectory.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_customer_journey_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # =========================================================
    # 1. Retrieve Programmatic Evidence
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to read verification data from environment"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # =========================================================
    # 2. Programmatic Scoring (50 points max)
    # =========================================================
    score = 0
    feedback_parts = []
    
    # EDDX checks
    eddx_exists = result_data.get('eddx_exists', False)
    eddx_size = int(result_data.get('eddx_size_bytes', 0))
    eddx_fresh = result_data.get('eddx_created_during_task', False)
    
    if eddx_exists:
        if eddx_size > 10000: # 10KB
            score += 15
            feedback_parts.append("EDDX file saved with valid size")
        else:
            feedback_parts.append(f"EDDX file too small ({eddx_size} bytes)")
    else:
        feedback_parts.append("EDDX file missing")

    if eddx_fresh:
        score += 5
        feedback_parts.append("EDDX file created during task")

    # PNG checks
    png_exists = result_data.get('png_exists', False)
    png_size = int(result_data.get('png_size_bytes', 0))
    png_fresh = result_data.get('png_created_during_task', False)
    png_width = int(result_data.get('png_width', 0))
    png_height = int(result_data.get('png_height', 0))

    if png_exists:
        if png_size > 50000: # 50KB
            score += 15
            feedback_parts.append("PNG export saved with valid size")
        else:
            feedback_parts.append(f"PNG export too small ({png_size} bytes)")
        
        if png_width > 800 and png_height > 400:
            score += 10
            feedback_parts.append("PNG dimensions reasonable")
    else:
        feedback_parts.append("PNG export missing")

    if png_fresh:
        score += 5
        feedback_parts.append("PNG file created during task")

    # =========================================================
    # 3. VLM Verification (50 points max)
    # =========================================================
    
    # Get trajectory frames for workflow analysis
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    # Also try to retrieve the actual exported PNG for clearer analysis if it exists
    exported_png_local = None
    if png_exists and png_size > 0:
        try:
            temp_png = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/home/ga/Diagrams/customer_journey_map.png", temp_png.name)
            exported_png_local = temp_png.name
        except Exception as e:
            logger.warning(f"Could not retrieve exported PNG for VLM: {e}")

    # Use exported PNG if available (better quality), otherwise fallback to final screenshot
    verification_image = exported_png_local if exported_png_local else final_screenshot
    
    vlm_prompt = """
    You are evaluating an AI agent's performance in creating a Customer Journey Map diagram in EdrawMax.
    
    Please analyze the provided image (the final diagram or screenshot) and the trajectory frames.
    
    Criteria to check:
    1. TITLE_VISIBLE: Is the text "Customer Journey" or similar visible as a main title?
    2. MULTIPLE_PHASES: Are there at least 4 distinct columns or sections representing phases (e.g., Awareness, Consideration, Purchase, etc.)?
    3. COLOR_CODING: Is there purposeful use of Red, Yellow/Orange, and Green colors to indicate emotional states?
    4. DIAGRAM_COMPLEXITY: Is this a substantial diagram with text and shapes, not just a blank or default template?
    
    Respond in JSON format:
    {
        "title_visible": true/false,
        "multiple_phases": true/false,
        "color_coding": true/false,
        "complexity_ok": true/false,
        "reasoning": "brief explanation"
    }
    """
    
    # We pass the verification image as the primary image, and frames as context if supported
    # Assuming query_vlm supports 'images' list
    images_to_send = frames + [verification_image] if verification_image else frames

    vlm_score = 0
    try:
        vlm_response = query_vlm(prompt=vlm_prompt, images=images_to_send)
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("title_visible", False):
                vlm_score += 10
                feedback_parts.append("VLM: Title visible")
            
            if parsed.get("multiple_phases", False):
                vlm_score += 15
                feedback_parts.append("VLM: Multiple phases detected")
                
            if parsed.get("color_coding", False):
                vlm_score += 15
                feedback_parts.append("VLM: Color coding detected")
                
            if parsed.get("complexity_ok", False):
                vlm_score += 10
                feedback_parts.append("VLM: Diagram complexity sufficient")
            
            feedback_parts.append(f"VLM reasoning: {parsed.get('reasoning', 'None')}")
        else:
            feedback_parts.append("VLM verification failed to process")
    except Exception as e:
        logger.error(f"VLM query exception: {e}")
        feedback_parts.append(f"VLM error: {str(e)}")
    finally:
        if exported_png_local and os.path.exists(exported_png_local):
            os.unlink(exported_png_local)

    total_score = score + vlm_score
    passed = total_score >= 70
    
    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback_parts)
    }