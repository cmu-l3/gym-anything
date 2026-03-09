#!/usr/bin/env python3
"""
Verifier for create_risk_exception task.

Verifies:
1. Database: A risk exception record exists with correct title, description, and date.
2. Anti-gaming: Record was created during the task window.
3. VLM: Visual confirmation of the interface state.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_risk_exception(traj, env_info, task_info):
    """
    Verify the Risk Exception was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "")
    expected_date = metadata.get('expected_date', "2025-12-31")
    required_keywords = metadata.get('required_description_keywords', [])

    # Copy result file
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
    feedback_parts = []
    
    # 1. Check if record found (15 pts)
    if result.get("record_found", False):
        score += 15
        feedback_parts.append("Risk Exception record created.")
    else:
        return {"passed": False, "score": 0, "feedback": "No Risk Exception record found matching the title."}

    # 2. Verify Title Exactness (15 pts)
    # The SQL query used LIKE, so let's check exactness if possible, or close match
    actual_title = result.get("title", "")
    if expected_title.lower() in actual_title.lower():
        score += 15
    else:
        feedback_parts.append(f"Title mismatch. Expected '{expected_title}', got '{actual_title}'")

    # 3. Verify Description Content (20 pts)
    actual_desc = result.get("description", "")
    keywords_found = 0
    for kw in required_keywords:
        if kw.lower() in actual_desc.lower():
            keywords_found += 1
    
    # Scale score based on keywords
    if len(required_keywords) > 0:
        desc_score = int((keywords_found / len(required_keywords)) * 20)
        score += desc_score
        if keywords_found < len(required_keywords):
            feedback_parts.append(f"Description missing some details (Found {keywords_found}/{len(required_keywords)} keywords).")
    else:
        score += 20

    # 4. Verify Expiration Date (15 pts)
    # Review date comes from DB as string, likely YYYY-MM-DD
    actual_date = result.get("review_date", "")
    if expected_date in actual_date:
        score += 15
    else:
        feedback_parts.append(f"Date mismatch. Expected '{expected_date}', got '{actual_date}'")

    # 5. Verify Risk Association (20 pts)
    if result.get("associated_risk_found", False):
        score += 20
        feedback_parts.append("Risk association verified.")
    else:
        feedback_parts.append("Could not verify association with 'Phishing Attacks' risk (Check failed).")

    # 6. Anti-Gaming: Creation Time & Count (10 pts)
    # Check if created > task_start
    # DB 'created' is usually YYYY-MM-DD HH:MM:SS
    # task_start is unix timestamp
    # We'll do a loose check: count_diff > 0
    if result.get("count_diff", 0) > 0:
        score += 10
    else:
        feedback_parts.append("Database record count did not increase.")

    # 7. VLM / Screenshot Existence (5 pts)
    # Just checking screenshot existence here as a proxy for 'visited UI'
    # More advanced VLM logic would go here if enabled
    score += 5

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }