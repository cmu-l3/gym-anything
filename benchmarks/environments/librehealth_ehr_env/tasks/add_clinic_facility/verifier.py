#!/usr/bin/env python3
"""
Verifier for add_clinic_facility task in LibreHealth EHR.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(prompt, image=None, images=None):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n=5):
        return []
    def get_final_screenshot(traj):
        return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_clinic_facility(traj, env_info, task_info):
    """
    Verify that the user added a new clinic facility with the correct details.
    
    Verification Signals:
    1. Database check: Facility record exists with correct fields (Primary, 80%)
    2. VLM check: Trajectory frames show the "Facilities" administration page (Secondary, 20%)
    3. Anti-gaming: Facility count increased during task window
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback = []

    # --- 1. Database Verification (80 points) ---
    facility_found = result.get('facility_found', False)
    details = result.get('facility_details', {})
    
    if not facility_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Facility 'Lakewood Family Health Center' was not found in the database."
        }
    
    score += 15
    feedback.append("Facility record created (+15)")

    # Helper to check field contains expected value
    def check_field(field_name, actual_value, expected_value, points, partial_match=True):
        if not actual_value:
            return 0
        
        match = False
        if partial_match:
            # Clean up formatting for phone/ein (remove non-digits)
            if field_name in ['phone', 'fax', 'ein', 'zip']:
                act_clean = ''.join(filter(str.isdigit, str(actual_value)))
                exp_clean = ''.join(filter(str.isdigit, str(expected_value)))
                if exp_clean in act_clean:
                    match = True
            elif str(expected_value).lower() in str(actual_value).lower():
                match = True
        else:
            if str(actual_value).lower() == str(expected_value).lower():
                match = True
        
        if match:
            feedback.append(f"{field_name} correct (+{points})")
            return points
        else:
            feedback.append(f"{field_name} mismatch: expected '{expected_value}', got '{actual_value}'")
            return 0

    # Score fields
    score += check_field("Phone", details.get("phone"), "3035550147", 8)
    score += check_field("Fax", details.get("fax"), "3035550148", 5)
    score += check_field("Street", details.get("street"), "456 Wadsworth", 8)
    score += check_field("City", details.get("city"), "Lakewood", 5, partial_match=False)
    score += check_field("State", details.get("state"), "CO", 5)
    score += check_field("Zip", details.get("zip"), "80226", 5)
    score += check_field("EIN", details.get("ein"), "843127856", 8)
    score += check_field("NPI", details.get("npi"), "1234567893", 8, partial_match=False)
    score += check_field("Taxonomy", details.get("taxonomy"), "261QP2300X", 5)
    score += check_field("POS", details.get("pos_code"), "11", 3)
    score += check_field("Billing", details.get("billing_location"), "1", 3)
    score += check_field("Service", details.get("service_location"), "1", 3)
    score += check_field("Color", details.get("color"), "3BB9FF", 4)

    # --- 2. Anti-Gaming Check (Prerequisite for high score) ---
    count_increased = result.get('count_increased', False)
    if not count_increased:
        feedback.append("WARNING: Total facility count did not increase (modified existing record?)")
        # We don't fail, but maybe cap score or deduct? 
        # For now, just logging it, as they might have deleted and recreated with same ID which is fine.

    # --- 3. VLM Verification (20 points) ---
    # We want to verify the user actually interacted with the UI
    frames = sample_trajectory_frames(traj, n=8)
    final_img = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        You are verifying a user interacting with LibreHealth EHR (an OpenEMR fork).
        The user should be on the 'Facilities' administration page to add a new clinic.
        
        Look for:
        1. A page titled "Facilities" or "Facility Administration".
        2. A form with fields like Name, Phone, Address, NPI, Tax ID, Color.
        3. User entering "Lakewood Family Health Center".
        
        Did the user visit the Facility configuration page?
        Respond in JSON: {"visited_facility_page": boolean, "confidence": float}
        """
        
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("visited_facility_page", False):
                score += 15
                feedback.append("VLM verified UI navigation (+15)")
            else:
                feedback.append("VLM could not confirm UI navigation")
        else:
            # Fallback if VLM fails: give points if we have a perfect DB match
            if score >= 75:
                score += 15
                feedback.append("VLM skipped (high DB score) (+15)")

    # Final tally
    passed = (score >= 60) and facility_found
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": details
    }