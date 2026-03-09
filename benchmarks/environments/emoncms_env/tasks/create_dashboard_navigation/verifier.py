#!/usr/bin/env python3
"""
Verifier for Create Dashboard Navigation Task
"""

import json
import os
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard_navigation(traj, env_info, task_info):
    """
    Verifies that the Facility Overview dashboard contains links to the specific 
    detail dashboards.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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

    # 2. Extract Data
    content_str = result.get("dashboard_content", "")
    target_ids = result.get("target_ids", {})
    
    hvac_id = str(target_ids.get("hvac", "99999"))
    lighting_id = str(target_ids.get("lighting", "99999"))
    solar_id = str(target_ids.get("solar", "99999"))
    landing_id = str(result.get("landing_dashboard_id", "0"))

    # 3. Decode Content (it might be double encoded or just a JSON string)
    # The content is a JSON array of widgets. We are looking for text/html properties.
    # To be robust, we will search the raw string for the link patterns.
    
    # Emoncms dashboard links typically look like:
    # "dashboard/view?id=X" or "dashboard/view?id=X"
    # The user might enter relative or absolute paths.
    
    score = 0
    feedback = []
    
    # Check if content is empty (initial state was [])
    if not content_str or content_str == "[]":
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dashboard content is empty. No widgets were added."
        }

    score += 10
    feedback.append("Dashboard content modified.")

    # Helper to check for ID links
    def check_link(name, target_id):
        # Regex patterns to catch various ways to link
        # 1. /dashboard/view?id=ID
        # 2. dashboard/view?id=ID
        # 3. ?id=ID (unlikely but possible in some contexts)
        # We also need to handle HTML entities if they were escaped (e.g. &id=)
        
        # Look for the ID appearing in a link-like context
        pattern = r'id=' + re.escape(target_id) + r'(?!\d)' # ID followed by non-digit
        
        if re.search(pattern, content_str):
            return True
        return False

    # Check HVAC
    if check_link("HVAC", hvac_id):
        score += 30
        feedback.append(f"Link to HVAC Detail (ID {hvac_id}) found.")
    else:
        feedback.append(f"Missing link to HVAC Detail (ID {hvac_id}).")

    # Check Lighting
    if check_link("Lighting", lighting_id):
        score += 30
        feedback.append(f"Link to Lighting Detail (ID {lighting_id}) found.")
    else:
        feedback.append(f"Missing link to Lighting Detail (ID {lighting_id}).")

    # Check Solar
    if check_link("Solar", solar_id):
        score += 30
        feedback.append(f"Link to Solar Detail (ID {solar_id}) found.")
    else:
        feedback.append(f"Missing link to Solar Detail (ID {solar_id}).")

    # Verify self-reference avoidance (optional, but good practice)
    if check_link("Self", landing_id):
        feedback.append("Warning: Link points to the dashboard itself.")
    
    # Final Pass Logic
    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }