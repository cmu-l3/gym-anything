#!/usr/bin/env python3
"""
Verifier for print_visitor_badge task.

Verifies:
1. Output file (PDF or PNG) exists in /home/ga/Documents/
2. File was created AFTER task start (anti-gaming)
3. File is not empty
4. VLM verifies the badge content (Visitor Name: Margaret Chen) in the output file or screenshot
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_visitor_badge(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('visitor_name', "Margaret Chen")
    
    # Copy Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    passed = False

    # 1. File Existence & Timestamp Check (40 points)
    pdf_ok = result.get('pdf_exists') and result.get('pdf_created_during_task') and result.get('pdf_size', 0) > 1000
    png_ok = result.get('png_exists') and result.get('png_created_during_task') and result.get('png_size', 0) > 5000

    if pdf_ok:
        score += 40
        feedback.append("PDF badge file created successfully.")
    elif png_ok:
        score += 30 # Slightly less for screenshot method
        feedback.append("Badge preview screenshot created successfully.")
    else:
        feedback.append("No valid output file created during task window.")
        return {"passed": False, "score": 0, "feedback": " ".join(feedback)}

    # 2. VLM Verification (60 points)
    # We verify the content of the generated file OR the final screen state
    
    # Try to get the output image itself if it's a PNG
    image_to_verify = None
    
    if png_ok:
        # If they made a PNG, verify that specific file
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env("/home/ga/Documents/visitor_badge_preview.png", temp_img.name)
            image_to_verify = temp_img.name
        except Exception:
            logger.warning("Could not copy output PNG, falling back to final screenshot")

    # If no output image loaded, use final screenshot
    if not image_to_verify:
        image_to_verify = get_final_screenshot(traj)

    if image_to_verify:
        prompt = f"""
        Analyze this image. It should show a Visitor Badge or a Print Preview window for 'Jolly Lobby Track'.
        
        I am looking for:
        1. The name "{expected_name}" or "Margaret" or "Chen".
        2. A badge layout (photo placeholder, company name, barcode, etc.).
        3. The text "Nextera Consulting" (optional but good).
        
        Return JSON:
        {{
            "has_visitor_name": true/false,
            "has_badge_layout": true/false,
            "company_visible": true/false,
            "confidence": 0-10
        }}
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=image_to_verify)
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            
            if parsed.get('has_visitor_name'):
                score += 40
                feedback.append(f"VLM confirmed visitor name '{expected_name}' is visible.")
            else:
                feedback.append(f"VLM could NOT find name '{expected_name}' in the output.")
                
            if parsed.get('has_badge_layout'):
                score += 20
                feedback.append("VLM confirmed badge layout.")
        else:
            feedback.append("VLM verification failed to run.")
            
        # Clean up temp image if we made one
        if png_ok and image_to_verify != get_final_screenshot(traj):
            try:
                os.unlink(image_to_verify)
            except:
                pass

    # Final Pass Determination
    # Must have file (40) + Name visible (40) = 80 min for full pass
    # Threshold 60 allows for partial VLM confidence or minor issues
    if score >= 60:
        passed = True
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }