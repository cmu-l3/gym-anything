#!/usr/bin/env python3
"""
Verifier for Consolidate Host Records task.
Uses VLM to inspect the agent's screenshot for data correctness.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_host_records(traj, env_info, task_info):
    """
    Verifies that the agent consolidated two duplicate host records into one.
    
    Criteria:
    1. Agent screenshot exists (10 pts)
    2. Database was modified (indicating save) (10 pts)
    3. VLM: Screenshot shows exactly ONE record for 'Sarah Jones' (40 pts)
    4. VLM: The record contains BOTH email 's.jones@example.com' AND phone '555-0199' (40 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Screenshot Existence (10 pts)
    if result.get("screenshot_exists"):
        score += 10
        feedback_parts.append("Screenshot created")
    else:
        return {"passed": False, "score": 0, "feedback": "No confirmation screenshot found at /home/ga/consolidated_host_result.png"}

    # 2. Check DB Modification (10 pts)
    if result.get("db_modified"):
        score += 10
        feedback_parts.append("Database updated")
    else:
        feedback_parts.append("Warning: Database file timestamp did not change")

    # 3 & 4. VLM Verification (80 pts)
    # Copy the agent's screenshot for VLM
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    try:
        copy_from_env("/tmp/agent_proof.png", temp_img.name)
        
        # VLM Prompt
        prompt = (
            "This screenshot shows a list of hosts or employees in Jolly Lobby Track software. "
            "Please analyze the records for 'Sarah Jones'.\n"
            "1. How many records are there for 'Sarah Jones'? (Should be exactly 1)\n"
            "2. Does the record show the email 's.jones@example.com'?\n"
            "3. Does the record show the phone number '555-0199'?\n"
            "Reply with JSON: {\"count\": <number>, \"has_email\": <bool>, \"has_phone\": <bool>}"
        )
        
        vlm_response = query_vlm(
            prompt=prompt,
            image=temp_img.name
        )
        
        if vlm_response.get("success"):
            data = vlm_response.get("parsed", {})
            
            # Criterion 3: Single Record (40 pts)
            count = data.get("count", 0)
            if count == 1:
                score += 40
                feedback_parts.append("Duplicates successfully removed (single record found)")
            else:
                feedback_parts.append(f"Failed: Found {count} records for Sarah Jones (expected 1)")
            
            # Criterion 4: Data Merged (40 pts)
            has_email = data.get("has_email", False)
            has_phone = data.get("has_phone", False)
            
            if has_email and has_phone:
                score += 40
                feedback_parts.append("Data merged successfully (both Email and Phone present)")
            elif has_email:
                score += 20
                feedback_parts.append("Partial success: Email present, Phone missing")
            elif has_phone:
                score += 20
                feedback_parts.append("Partial success: Phone present, Email missing")
            else:
                feedback_parts.append("Failed: Merged record missing both Email and Phone")
        else:
            feedback_parts.append("VLM verification failed to parse screenshot")
            
    except Exception as e:
        feedback_parts.append(f"Error during verification: {e}")
    finally:
        if os.path.exists(temp_img.name):
            os.unlink(temp_img.name)

    passed = (score >= 90)
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }