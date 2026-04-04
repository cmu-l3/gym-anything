#!/usr/bin/env python3
"""
Verifier for Create Location task in Bahmni/OpenMRS.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_location(traj, env_info, task_info):
    """
    Verify that the 'Pediatrics Ward' location was created correctly in OpenMRS.
    
    Criteria:
    1. Location exists in OpenMRS database (40 pts)
    2. Description matches 'Ward for pediatric inpatient care' (20 pts)
    3. Tagged as 'Visit Location' (15 pts)
    4. Location count increased (Anti-gaming) (10 pts)
    5. Location is active/not retired (5 pts)
    6. VLM confirms Admin UI interaction (10 pts)
    
    Pass Threshold: 60 points AND Location Exists
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "Pediatrics Ward")
    expected_desc = metadata.get('expected_description', "Ward for pediatric inpatient care")
    expected_tag = metadata.get('expected_tag', "Visit Location")

    # 1. Load Result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    loc_details = result.get('location_details', {})
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    found = loc_details.get('found', False)

    # Criterion 1: Location Exists (40 pts)
    if found:
        # Check name exact match
        actual_name = loc_details.get('name', '')
        if actual_name == expected_name:
            score += 40
            feedback_parts.append(f"Location '{actual_name}' created successfully")
        else:
            # Partial credit if name is close (e.g., "Pediatrics")
            score += 10
            feedback_parts.append(f"Location found but name mismatch: '{actual_name}' vs '{expected_name}'")
    else:
        feedback_parts.append("Location 'Pediatrics Ward' NOT found")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts),
            "details": {"reason": "Location not created"}
        }

    # Criterion 2: Description (20 pts)
    actual_desc = loc_details.get('description', '')
    if actual_desc and expected_desc.lower() in actual_desc.lower():
        score += 20
        feedback_parts.append("Description correct")
    elif actual_desc:
        score += 5
        feedback_parts.append(f"Description mismatch: '{actual_desc}'")
    else:
        feedback_parts.append("Description missing")

    # Criterion 3: Tags (15 pts)
    tags = loc_details.get('tags', [])
    if any(expected_tag.lower() in t.lower() for t in tags):
        score += 15
        feedback_parts.append(f"Tag '{expected_tag}' present")
    else:
        feedback_parts.append(f"Tag '{expected_tag}' missing (Found: {tags})")

    # Criterion 4: Count Increased (10 pts)
    if final_count > initial_count:
        score += 10
        feedback_parts.append("Location count increased")
    else:
        feedback_parts.append("Location count did not increase (Anti-gaming check failed)")

    # Criterion 5: Not Retired (5 pts)
    if not loc_details.get('retired', False):
        score += 5
        feedback_parts.append("Location is active")
    else:
        feedback_parts.append("Location is retired/voided")

    # Criterion 6: VLM Verification (10 pts)
    # Check if agent actually visited the Admin UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
        
        if frames:
            prompt = (
                "Review these screenshots of a user creating a hospital location. "
                "1. Do you see the OpenMRS Administration page (legacy UI with green header)? "
                "2. Do you see a form for 'Add Location' or 'Manage Locations'? "
                "3. Is 'Pediatrics Ward' visible in any list? "
                "Return JSON: {'admin_ui_seen': bool, 'location_form_seen': bool}"
            )
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get('parsed', {})
                if parsed.get('admin_ui_seen') or parsed.get('location_form_seen'):
                    vlm_score = 10
                    feedback_parts.append("Visual verification passed (Admin UI seen)")
                else:
                    feedback_parts.append("Visual verification failed (Admin UI not clearly visible)")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                
    score += vlm_score

    passed = (score >= 60) and found and (loc_details.get('name') == expected_name)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": loc_details
    }