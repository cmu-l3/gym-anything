#!/usr/bin/env python3
"""
Verifier for Create Encounter Type task.

Verifies:
1. An Encounter Type named "Telehealth Consultation" exists via API (30 pts)
2. The description contains required keywords (20 pts)
3. It was created during the task session (anti-gaming) (15 pts)
4. VLM verifies the UI workflow (navigation + form submission) (35 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_encounter_type(traj, env_info, task_info):
    """
    Verify creation of the encounter type using API data and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Programmatic Verification (65 points total)
    
    # Check 1: Encounter Type Exists (30 pts)
    exists = result.get("encounter_type_exists", False)
    api_data = result.get("api_response", {})
    target_name = "Telehealth Consultation"
    
    # Find the specific object in the API response results
    found_obj = None
    if exists:
        results = api_data.get("results", [])
        for item in results:
            if item.get("name") == target_name:
                found_obj = item
                break
    
    if found_obj:
        score += 30
        feedback_parts.append(f"Encounter Type '{target_name}' created successfully")
    else:
        feedback_parts.append(f"Encounter Type '{target_name}' NOT found")
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Check 2: Created During Task (15 pts)
    # This prevents using a pre-existing state
    if result.get("created_during_task", False):
        score += 15
        feedback_parts.append("Created during current session")
    else:
        feedback_parts.append("WARNING: Object creation timestamp predates task start (stale data?)")

    # Check 3: Description Content (20 pts)
    # Description should contain "remote" and "consultation" (case insensitive)
    description = found_obj.get("description", "").lower()
    required_keywords = ["remote", "consultation"]
    keywords_met = sum(1 for k in required_keywords if k in description)
    
    if keywords_met == len(required_keywords):
        score += 20
        feedback_parts.append("Description contains required keywords")
    elif keywords_met > 0:
        score += 10
        feedback_parts.append("Description partially correct")
    else:
        feedback_parts.append(f"Description missing keywords (Found: '{description}')")

    # 3. VLM Verification (35 points total)
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_ss = get_final_screenshot(traj)
        if final_ss:
            frames.append(final_ss)
            
        prompt = """
        Review these screenshots of a user interacting with OpenMRS/Bahmni.
        
        I am looking for evidence of the following workflow:
        1. Navigation to the 'Administration' section.
        2. Accessing 'Manage Encounter Types'.
        3. Filling out a form to create a new Encounter Type.
        
        Answer JSON:
        {
            "navigated_admin": true/false,
            "accessed_encounter_types": true/false,
            "filled_form": true/false,
            "no_error_dialogs": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(images=frames, prompt=prompt)
            parsed = vlm_resp.get('parsed', {})
            
            # Navigation Scoring
            if parsed.get('navigated_admin', False) or parsed.get('accessed_encounter_types', False):
                score += 15
                feedback_parts.append("VLM confirmed admin navigation")
            
            # Form Action Scoring
            if parsed.get('filled_form', False):
                score += 15
                feedback_parts.append("VLM confirmed form interaction")
                
            # Error Check
            if parsed.get('no_error_dialogs', True):
                score += 5
            else:
                feedback_parts.append("VLM detected possible error dialogs")
                
        except Exception as e:
            logger.error(f"VLM verification failed: {e}")
            feedback_parts.append("VLM verification skipped (error)")
            # Grant partial fallback points if programmatic passed perfectly
            if score >= 65: 
                score += 20
                feedback_parts.append("Granted partial VLM fallback points")

    # Final Pass Logic
    # Pass threshold: 65 (Must have created the object + some description/timing/VLM points)
    passed = score >= 65 and found_obj is not None
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }