#!/usr/bin/env python3
"""
Verifier for design_badge_with_host_field task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_badge_with_host_field(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verifies that the agent:
    1. Created the proof screenshot showing the badge.
    2. The screenshot visually contains "Host: Bob Manager".
    3. The visitor record exists in the database (grep check).
    """
    
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
    
    # Load result JSON
    result = {}
    with tempfile.NamedTemporaryFile(suffix=".json") as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            tmp_json.seek(0)
            result = json.load(tmp_json)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

    # Load Proof Screenshot
    proof_path = result.get("proof_path", "")
    proof_img_path = None
    
    if result.get("proof_exists"):
        with tempfile.NamedTemporaryFile(delete=False, suffix=".png") as tmp_img:
            try:
                copy_from_env(proof_path, tmp_img.name)
                proof_img_path = tmp_img.name
            except Exception as e:
                logger.warning(f"Could not copy proof image: {e}")

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Criterion A: Database Record (30 pts)
    # Checks if "Alice Verifier" and "Bob Manager" were found in the MDB file
    if result.get("visitor_found_in_db"):
        score += 20
        feedback.append("Visitor record found in database.")
    else:
        feedback.append("Visitor record NOT found in database.")
        
    if result.get("host_found_in_db"):
        score += 10
        feedback.append("Host record found in database.")

    # Criterion B: Proof File Existence (10 pts)
    if result.get("proof_created_during_task"):
        score += 10
        feedback.append("Proof screenshot created.")
    elif result.get("proof_exists"):
        score += 5
        feedback.append("Proof screenshot exists but timestamp is old.")
    else:
        feedback.append("Proof screenshot missing.")

    # Criterion C: Template Modification (10 pts)
    # Heuristic: Did any file in the template directories change?
    if result.get("template_modified"):
        score += 10
        feedback.append("Template files modified.")
    else:
        feedback.append("No template file modification detected (might be cached or memory-only).")

    # Criterion D: Visual Verification (50 pts)
    # This is the most critical part. We check the content of the proof screenshot.
    vlm_passed = False
    if proof_img_path and query_vlm:
        prompt = (
            "Analyze this image. It should be a screenshot of a visitor management software showing a badge preview.\n"
            "1. Is there a badge or print preview visible?\n"
            "2. Does the badge text clearly read 'Host: Bob Manager' or similar (e.g. 'Host Name: Bob Manager')?\n"
            "3. Is 'Bob Manager' part of the badge design, not just a UI field elsewhere?\n"
            "Return JSON: {\"is_preview\": bool, \"host_text_visible\": bool, \"correct_name\": bool}"
        )
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=proof_img_path)
            parsed = vlm_response.get("parsed", {})
            
            if parsed.get("is_preview"):
                score += 10
                feedback.append("VLM confirmed badge preview visibility.")
                
                if parsed.get("host_text_visible") and parsed.get("correct_name"):
                    score += 40
                    vlm_passed = True
                    feedback.append("VLM confirmed 'Host: Bob Manager' on badge.")
                else:
                    feedback.append("VLM could not find 'Host: Bob Manager' on the badge.")
            else:
                feedback.append("VLM did not detect a valid badge preview.")
        except Exception as e:
            feedback.append(f"VLM analysis failed: {e}")
    else:
        feedback.append("Skipping VLM check (image or tool missing).")

    # Cleanup
    if proof_img_path and os.path.exists(proof_img_path):
        os.unlink(proof_img_path)

    # Final Pass Determination
    # Must have the visual proof correct OR (Database correct + Template modified + Proof exists)
    # We set threshold at 70, which effectively requires the VLM check to pass partially or full DB success
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }