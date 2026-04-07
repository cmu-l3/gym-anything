#!/usr/bin/env python3
"""
Verifier for Add Facility task in FreeMED.

Uses copy_from_env to read pre-exported verification data from the container.
Also uses VLM to verify that the agent interacted with the UI to complete the task.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_facility(traj, env_info, task_info):
    """
    Verify that the expected facility was added to FreeMED.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('facility_name', 'Riverside Family Health Center')
    expected_street = metadata.get('street', '2450 River Road')
    expected_city = metadata.get('city', 'Springfield')
    expected_state = metadata.get('state', 'IL')
    expected_zip = metadata.get('zip_code', '62704')
    expected_phone = metadata.get('phone', '2175550198')

    try:
        # 1. Retrieve the exported JSON from the container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/add_facility_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        initial_count = result.get('initial_count', 0)
        current_count = result.get('current_count', 0)
        raw_row = result.get('raw_row', '').lower()

        logger.info(f"Counts: Initial={initial_count}, Current={current_count}")
        logger.info(f"Raw Row: {raw_row}")

        # Anti-gaming: Ensure count increased
        newly_added = current_count > initial_count
        
        # Check Database Fields
        if not raw_row:
            feedback_parts.append("No facility record containing 'Riverside' found in database")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        score += 35
        feedback_parts.append("Facility record exists in DB")
        
        if "riverside" in raw_row and "family" in raw_row:
            score += 15
            feedback_parts.append("Name is correct")
        else:
            feedback_parts.append("Name mismatch")
            
        if "2450" in raw_row and "river" in raw_row:
            score += 15
            feedback_parts.append("Street address is correct")
        else:
            feedback_parts.append("Street address mismatch")
            
        if expected_city.lower() in raw_row and expected_state.lower() in raw_row and expected_zip in raw_row:
            score += 20
            feedback_parts.append("City/State/Zip are correct")
        else:
            feedback_parts.append("City/State/Zip mismatch")
            
        if expected_phone in raw_row or "217-555-0198" in raw_row or "(217) 555-0198" in raw_row:
            score += 15
            feedback_parts.append("Phone number is correct")
        else:
            feedback_parts.append("Phone number mismatch")

        # 2. Trajectory VLM Verification (Anti-SQL Injection Check)
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=4)
                final_frame = get_final_screenshot(traj)
                
                if frames and final_frame:
                    vlm_prompt = """
                    Review the progression of screenshots from a user interacting with the FreeMED application.
                    Did the user navigate the web interface to add a new Practice Facility (Riverside Family Health Center)?
                    Look for evidence of form filling, clicking menus related to configuration/facilities, and a save action.
                    Respond in JSON format:
                    {"used_ui": true/false, "confidence": "high/medium/low", "reason": "brief explanation"}
                    """
                    vlm_response = query_vlm(images=frames + [final_frame], prompt=vlm_prompt)
                    
                    if vlm_response.get("success"):
                        vlm_parsed = vlm_response.get("parsed", {})
                        if vlm_parsed.get("used_ui"):
                            feedback_parts.append("VLM verified UI interaction")
                        else:
                            score = min(score, 50)  # Penalize if VLM thinks they didn't use the UI
                            feedback_parts.append(f"VLM UI check failed: {vlm_parsed.get('reason', 'Unknown')}")
            except Exception as e:
                logger.warning(f"VLM verification skipped/failed: {e}")

        # Final Evaluation
        key_criteria_met = score >= 85 and newly_added
        passed = key_criteria_met
        
        if not newly_added and score > 0:
            passed = False
            feedback_parts.append("FAIL: Record found but facility count did not increase (Anti-gaming check)")
            score = 0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error in verifier: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verifier exception: {str(e)}"}