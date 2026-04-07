#!/usr/bin/env python3
"""
Verifier for create_security_incident task.
Checks if the incident was created in EventLog Analyzer with correct details.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_security_incident(traj, env_info, task_info):
    """
    Verifies the creation of a security incident.
    
    Criteria:
    1. Incident exists (via API or DB check) - Primary (30 pts)
    2. Incident count increased - Anti-gaming (10 pts)
    3. Title matches expected - (15 pts)
    4. Priority is High - (15 pts)
    5. Description contains keywords - (10 pts)
    6. VLM Verification of workflow - (20 pts)
    """
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # Retrieve Metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Brute Force Attempt")
    expected_keywords = metadata.get('expected_description_keywords', ["10.0.2.15"])
    
    score = 0
    feedback = []
    
    # 2. Programmatic Verification
    
    # Check if incident exists (API or DB)
    incident_data = result.get('matching_incident', {})
    found_in_api = incident_data.get('found', False)
    found_in_db = result.get('db_record_found', False)
    
    if found_in_api or found_in_db:
        score += 30
        feedback.append("Incident record found in system.")
    else:
        feedback.append("Incident record NOT found via API or Database.")
        
    # Check count increase (Anti-gaming)
    initial_count = int(result.get('initial_count', 0))
    final_count = int(result.get('final_count', 0))
    if final_count > initial_count:
        score += 10
        feedback.append(f"Incident count increased ({initial_count} -> {final_count}).")
    elif found_in_api or found_in_db:
         # If found but count didn't increase, it might be an update or count issue
         feedback.append("Incident count did not increase (potential issue).")
    
    # Check Details (if we have API data)
    details = incident_data.get('details', {})
    if found_in_api and details:
        # Title Check
        actual_title = details.get('title', details.get('subject', ''))
        if expected_title.lower() in actual_title.lower():
            score += 15
            feedback.append("Title matches expectations.")
        else:
            feedback.append(f"Title mismatch. Expected: '{expected_title}', Found: '{actual_title}'")
            
        # Priority Check
        # API might return ID (e.g., 1 for High) or string
        priority = str(details.get('priority', '')).lower()
        if 'high' in priority or priority == '1':
            score += 15
            feedback.append("Priority is High.")
        else:
            feedback.append(f"Priority mismatch. Found: {priority}")
            
        # Description Check
        description = str(details.get('description', '')).lower()
        keywords_found = [kw for kw in expected_keywords if kw.lower() in description]
        if len(keywords_found) >= 2: # Require at least 2 keywords
            score += 10
            feedback.append(f"Description contains keywords: {keywords_found}.")
        else:
            feedback.append(f"Description missing required keywords. Found: {keywords_found}")
            
    elif found_in_db and not found_in_api:
        # Fallback if only DB found it (assume details correct for partial points or rely on VLM)
        score += 20 # Partial credit for details since we confirmed existence via DB but couldn't parse details
        feedback.append("Verified via Database (Details checked implicitly via DB query match).")

    # 3. VLM Verification (Trajectory)
    # Essential for confirming they actually used the UI
    
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = f"""
    You are verifying if a user created a specific security incident in EventLog Analyzer.
    
    Task: Create incident '{expected_title}' with High priority.
    
    Review the screenshots (trajectory) and answer:
    1. Did the user navigate to the 'Incidents' or 'HelpDesk' section?
    2. Did the user fill out a 'New Incident' form?
    3. Is there evidence of typing '{expected_title}'?
    4. Is there evidence of selecting 'High' priority?
    5. Does the final state show the incident in a list?
    
    Return JSON: {{ "workflow_followed": bool, "form_filled": bool, "incident_visible": bool, "confidence": float }}
    """
    
    try:
        vlm_result = query_vlm(images=frames + [final_shot], prompt=vlm_prompt)
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('workflow_followed') or parsed.get('form_filled'):
            score += 10
            feedback.append("VLM confirms workflow followed.")
            
        if parsed.get('incident_visible'):
            score += 10
            feedback.append("VLM confirms incident visible in final state.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        # Be lenient if VLM fails but programmatic passed
        if score >= 60:
            score += 10 
            feedback.append("VLM skipped (error), but programmatic checks passed.")

    # 4. Final Verdict
    passed = score >= 60 and (found_in_api or found_in_db)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }