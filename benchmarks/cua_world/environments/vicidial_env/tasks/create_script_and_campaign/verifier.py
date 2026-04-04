#!/usr/bin/env python3
"""
Verifier for create_script_and_campaign task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_text(text):
    """Normalize whitespace for comparison."""
    if not text:
        return ""
    # Replace multiple newlines/spaces with single space
    return " ".join(text.split())

def verify_create_script_and_campaign(traj, env_info, task_info):
    """
    Verify the Vicidial script and campaign creation.
    
    Scoring Criteria:
    - Script Created (20 pts)
    - Script Text Exact Matches (30 pts)
    - Campaign Created (20 pts)
    - Campaign Active (10 pts)
    - Campaign Linked to Script (20 pts)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    script_data = result.get("script_data")
    campaign_data = result.get("campaign_data")
    
    # Check 1: Script Creation (20 pts)
    if script_data and script_data.get("id") == "SENATE_V1":
        score += 20
        feedback.append("Script 'SENATE_V1' created.")
        
        # Check 2: Script Text (30 pts)
        # We need strict checking for variables, but lenient for whitespace
        actual_text = script_data.get("text", "")
        # The expected variables must appear exactly
        required_vars = ["--A--first_name--B--", "--A--last_name--B--", "--A--state--B--"]
        vars_missing = [v for v in required_vars if v not in actual_text]
        
        if not vars_missing:
            # Check content roughly
            normalized_actual = normalize_text(actual_text)
            expected_snippet = "on behalf of the Senator's office"
            if expected_snippet in normalized_actual:
                score += 30
                feedback.append("Script text and variables are correct.")
            else:
                score += 15
                feedback.append("Script variables correct, but body text seems wrong.")
        else:
            feedback.append(f"Script missing required variables: {', '.join(vars_missing)}")
    else:
        feedback.append("Script 'SENATE_V1' NOT found.")

    # Check 3: Campaign Creation (20 pts)
    if campaign_data and campaign_data.get("id") == "SENATE_OPS":
        score += 20
        feedback.append("Campaign 'SENATE_OPS' created.")
        
        # Check 4: Campaign Active (10 pts)
        if campaign_data.get("active") == "Y":
            score += 10
            feedback.append("Campaign is Active.")
        else:
            feedback.append("Campaign is NOT set to Active.")
            
        # Check 5: Script Linked (20 pts)
        # The field campaign_script usually stores the script_id
        linked_script = campaign_data.get("campaign_script", "")
        if linked_script == "SENATE_V1":
            score += 20
            feedback.append("Campaign correctly linked to Script.")
        else:
            feedback.append(f"Campaign linked to wrong script: '{linked_script}' (Expected: SENATE_V1)")
    else:
        feedback.append("Campaign 'SENATE_OPS' NOT found.")

    # Anti-gaming check
    if result.get("initial_script_count", 0) > 0 or result.get("initial_campaign_count", 0) > 0:
        score = 0
        feedback = ["Anti-gaming: Items existed before task start!"]

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }