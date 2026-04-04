#!/usr/bin/env python3
"""
Verifier for add_incident_location task.

Checks:
1. Case data retrieved successfully.
2. Location object exists linked to the case.
3. Address fields match specific requirements (Reno, NV, 89595, etc.).
4. VLM verification for UI confirmation.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_incident_location(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_addr = metadata.get('expected_address', {})
    exp_street = expected_addr.get('street', '2500 East Second Street').lower()
    exp_city = expected_addr.get('city', 'Reno').lower()
    exp_zip = expected_addr.get('zip', '89595')
    
    score = 0
    feedback_parts = []
    
    # 1. Load JSON Result
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

    # 2. Analyze Programmatic Data (API)
    case_data = result.get('case_data', {})
    locations_data = result.get('locations_data', [])
    associations_data = result.get('associations_data', [])
    
    # Consolidate potential location sources
    found_locations = []
    
    # Source A: Embedded locations
    if isinstance(case_data, dict):
        if 'locations' in case_data and isinstance(case_data['locations'], list):
            found_locations.extend(case_data['locations'])
        if 'addresses' in case_data and isinstance(case_data['addresses'], list):
            found_locations.extend(case_data['addresses'])
            
    # Source B: Direct locations endpoint
    if isinstance(locations_data, list):
        found_locations.extend(locations_data)
        
    # Source C: Associations (might be just IDs, but sometimes full objects)
    if isinstance(associations_data, list):
        found_locations.extend(associations_data)

    # Search for the specific address
    address_match_score = 0
    best_match_details = []
    
    for loc in found_locations:
        # Flatten the dict to string for loose searching
        loc_str = str(loc).lower()
        
        current_match = 0
        details = []
        
        # Check Zip (High specificity)
        if exp_zip in loc_str:
            current_match += 30
            details.append("Zip code match")
        
        # Check City
        if exp_city in loc_str:
            current_match += 20
            details.append("City match")
            
        # Check Street (Partial)
        if "2500" in loc_str and "second" in loc_str:
            current_match += 30
            details.append("Street match")
            
        if current_match > address_match_score:
            address_match_score = current_match
            best_match_details = details

    if address_match_score > 0:
        score += address_match_score
        feedback_parts.append(f"Found location data: {', '.join(best_match_details)}")
    else:
        feedback_parts.append("No matching location found in API data")

    # 3. VLM Verification (Trajectory)
    # Even if API fails (maybe data hasn't synced or endpoint guess was wrong), 
    # visual evidence can provide partial credit.
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        images_to_check = frames + [final_screen]
        prompt = f"""
        Review these screenshots of a user working in ArkCase.
        Goal: Add a location/address to a case.
        Address to find: "{exp_street}", "{exp_city}", "{exp_zip}".
        
        Check for:
        1. Is the user in a "Locations" or "Addresses" section?
        2. Can you see the specific address text entered into fields?
        3. Is there a "Save" action or a saved record visible?
        
        Return JSON: {{ "address_visible": bool, "location_section_visible": bool, "saved_record_visible": bool }}
        """
        
        try:
            vlm_res = query_vlm(images=images_to_check, prompt=prompt)
            parsed = vlm_res.get('parsed', {})
            
            if parsed.get('location_section_visible'):
                score += 10
                feedback_parts.append("VLM: Navigated to Locations")
            
            if parsed.get('address_visible'):
                score += 10
                feedback_parts.append("VLM: Address entry visible")
                
            if parsed.get('saved_record_visible'):
                # If API failed but VLM sees it saved, give credit
                if address_match_score == 0:
                    score += 20
                    feedback_parts.append("VLM: Saved record visible (API check failed)")
                    
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Score Calculation
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }