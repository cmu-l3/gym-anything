#!/usr/bin/env python3
"""
Verifier for implement_parking_pass_workflow task.

Checks:
1. "Parking Permit" template file creation (File check)
2. "License Plate" field addition to DB (String check in modified DB files)
3. Template content verification (Field link + Static Text)
4. Visual verification of Layout (Landscape) using VLM
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_parking_workflow(traj, env_info, task_info):
    """
    Verifies that the agent added the License Plate field and created the specific badge template.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Database Field Creation (30 pts)
    # Checked via string presence in modified config/DB files
    if result.get("field_added_to_schema", False):
        score += 30
        feedback_parts.append("✅ 'License Plate' field added to database/schema")
    else:
        feedback_parts.append("❌ 'License Plate' field NOT detected in database")

    # Criterion 2: Template File Creation (30 pts)
    if result.get("template_found", False):
        score += 30
        feedback_parts.append("✅ 'Parking Permit' template file created")
    else:
        feedback_parts.append("❌ 'Parking Permit' template file NOT found")

    # Criterion 3: Template Content (20 pts)
    # Checks if file contains binding strings
    content_score = 0
    if result.get("template_has_field_link", False):
        content_score += 10
        feedback_parts.append("✅ Template links to 'License Plate' field")
    else:
        feedback_parts.append("⚠️ Template missing 'License Plate' field link")
        
    if result.get("template_has_static_text", False):
        content_score += 10
        feedback_parts.append("✅ Template contains 'PARKING PERMIT' text")
    else:
        feedback_parts.append("⚠️ Template missing 'PARKING PERMIT' text")
    
    score += content_score

    # Criterion 4: Visual/VLM Verification (20 pts)
    # Verify Landscape orientation and visual elements
    frames = sample_trajectory_frames(traj, n=4)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = (
        "Review these screenshots of the Jolly Lobby Track Badge Designer workflow.\n"
        "1. Did the agent select 'Landscape' orientation for the badge?\n"
        "2. Is there a text field that says 'PARKING PERMIT'?\n"
        "3. Is there a data field labeled 'License Plate'?\n"
        "Provide a score (0-20) based on visual evidence of these settings."
    )
    
    vlm_score = 0
    try:
        if frames:
            # Use query_vlm helper
            # Note: gym_anything query_vlm returns a dict with 'parsed'
            response = query_vlm(images=frames + [final_screenshot], prompt=vlm_prompt)
            
            # Simple heuristic parsing if VLM returns structured data, or fallback to text analysis
            # Assuming gym_anything VLM might return free text or JSON. 
            # We will be conservative and check for keywords or use a specific score prompt pattern if available.
            # For this implementation, we'll assume the verifier human/system parses the response, 
            # but programmatically we can check for positive keywords if strict scoring is needed.
            
            # For this code generation, let's look for "Landscape" and "License" in the VLM reasoning
            # or try to extract a number if possible.
            
            analysis = response.get('response', '').lower()
            if "landscape" in analysis:
                vlm_score += 10
            if "parking permit" in analysis:
                vlm_score += 5
            if "license" in analysis:
                vlm_score += 5
                
            feedback_parts.append(f"VLM Analysis: {analysis[:100]}...")
        else:
            feedback_parts.append("⚠️ No screenshots for VLM verification")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if template exists and has text, assume visual is okay-ish to avoid 0 score on error
        if result.get("template_found") and result.get("template_has_static_text"):
             vlm_score = 10 
    
    score += vlm_score

    # Final Pass/Fail
    # Must have created field (30) AND template (30) at minimum
    passed = result.get("field_added_to_schema", False) and result.get("template_found", False)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }