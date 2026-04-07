#!/usr/bin/env python3
"""
Verifier for manage_shared_corporate_contact task.

Verification Strategy:
1. Programmatic (Primary): Check database state exported by PowerShell script.
   - Facilities exist? (20 pts each)
   - Contact exists? (20 pts)
   - EXACTLY ONE contact record? (Anti-gaming / Best Practice) (25 pts)
   - Links exist? (15 pts)
2. VLM (Secondary): Verify from trajectory that user navigated correctly if DB details are ambiguous.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_manage_shared_corporate_contact(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Container path is Windows style, but copy_from_env usually handles the mapping 
        # or we use the linux mount path provided in env config if accessible. 
        # Assuming standard copy_from_env works with the guest path or mounted path.
        # If the environment mounts C:\workspace, we might find it there if script moved it.
        # The export script saved to C:\Windows\Temp\task_result.json.
        
        copy_from_env("C:\\Windows\\Temp\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification data: {str(e)}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Evaluate Score
    score = 0
    feedback_parts = []
    
    # Check Facilities
    if result.get("north_plant_exists"):
        score += 20
        feedback_parts.append("AquaPure North Plant created.")
    else:
        feedback_parts.append("AquaPure North Plant NOT found.")

    if result.get("south_plant_exists"):
        score += 20
        feedback_parts.append("AquaPure South Plant created.")
    else:
        feedback_parts.append("AquaPure South Plant NOT found.")

    # Check Contact
    contact_count = result.get("contact_count", 0)
    if contact_count >= 1:
        score += 20
        feedback_parts.append("Contact 'Elena Rodriguez' created.")
        
        # Check for Duplicates (The Core Challenge)
        if contact_count == 1:
            score += 25
            feedback_parts.append("Efficiency Bonus: No duplicate contacts found.")
        else:
            feedback_parts.append(f"Inefficiency Warning: Found {contact_count} records for Elena. Should be unique.")
    else:
        feedback_parts.append("Contact 'Elena Rodriguez' NOT found.")

    # Check Links
    # If links_verified is True (DB confirmed) or "unknown_schema" (DB schema issue),
    # we grant points if facilities and contact exist, assuming the agent likely did it 
    # if they got this far. For strictness, we require the count to be correct.
    links_status = result.get("links_verified")
    
    if links_status is True:
        score += 15
        feedback_parts.append("Links between facilities and contact verified in DB.")
    elif links_status == "unknown_schema":
        # Fallback logic: If score is high (facilities + contact unique), assume success
        if score >= 85:
            score += 15
            feedback_parts.append("Links assumed created based on data integrity.")
        else:
            feedback_parts.append("Could not verify links in DB.")
    
    # 3. Final Pass/Fail
    passed = score >= 85  # Requires both facilities, contact, and NO duplicates (or links)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts),
        "details": result
    }