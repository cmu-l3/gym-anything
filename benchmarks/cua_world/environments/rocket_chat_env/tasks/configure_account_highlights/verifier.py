#!/usr/bin/env python3
"""
Verifier for configure_account_highlights task.

Checks if the user's account preferences in Rocket.Chat contain the specific
highlight keywords: "error", "critical", "deploy".
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_account_highlights(traj, env_info, task_info):
    """
    Verify that the user configured the highlight words correctly.
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

    # Check API success
    if not result.get("api_success"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to verify settings via Rocket.Chat API (authentication failed during export)."
        }

    # Normalize highlights data
    # The API might return a list of strings ["error", "critical"] or a list of objects.
    # It usually returns a list of strings for keywords.
    raw_highlights = result.get("highlights", [])
    
    # Ensure we have a list of strings to check
    current_keywords = []
    if isinstance(raw_highlights, list):
        # Filter for strings only
        current_keywords = [str(x).lower().strip() for x in raw_highlights if isinstance(x, str)]
    elif isinstance(raw_highlights, str):
        # Sometimes returned as comma-separated string if legacy
        current_keywords = [x.strip().lower() for x in raw_highlights.split(',') if x.strip()]

    target_keywords = task_info.get('metadata', {}).get('target_keywords', ["error", "critical", "deploy"])
    
    score = 0
    feedback_parts = []
    missing_words = []

    # Scoring: 20 points for getting to the menu (implied by having any new keywords), 
    # plus points for each correct keyword.
    
    # Base points for successful retrieval implies system is working
    score += 10 

    for target in target_keywords:
        target_lower = target.lower()
        # loose matching
        found = False
        for current in current_keywords:
            if target_lower == current:
                found = True
                break
        
        if found:
            score += 30  # 3 keywords * 30 = 90
            feedback_parts.append(f"Keyword '{target}' set correctly.")
        else:
            missing_words.append(target)

    if missing_words:
        feedback_parts.append(f"Missing keywords: {', '.join(missing_words)}.")
    else:
        feedback_parts.append("All keywords configured successfully.")

    # Deduct for extra garbage if strictly checking (optional, keeping lenient for now)
    
    total_score = min(100, score) # Cap at 100
    passed = (len(missing_words) == 0)

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " ".join(feedback_parts)
    }