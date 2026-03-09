#!/usr/bin/env python3
"""
Verifier for create_patient_identifier_type task.

Checks:
1. Identifier Type exists (searched by loose name match).
2. Exact Name matches "National Health ID".
3. Description contains key terms.
4. Count of identifier types increased (Anti-gaming).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_patient_identifier_type(traj, env_info, task_info):
    """
    Verify that the National Health ID identifier type was created correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', "National Health ID")
    # Keywords: Unique, National, Health, Ministry, Exchange
    expected_keywords = metadata.get('expected_description_keywords', 
                                   ["unique", "national", "health", "ministry", "exchange"])

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

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Extract data
    found = result.get("found", False)
    target_name = result.get("target_name", "")
    target_desc = result.get("target_description", "") or ""
    initial_count = int(result.get("initial_count", 0))
    current_count = int(result.get("current_count", 0))
    is_retired = result.get("is_retired", False)

    # 1. Existence Check (40 pts)
    if found and not is_retired:
        score += 40
        feedback_parts.append("Identifier Type created")
    elif found and is_retired:
        score += 10
        feedback_parts.append("Identifier Type created but is retired")
    else:
        feedback_parts.append("Identifier Type NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Exact Name Check (20 pts)
    if target_name.strip() == expected_name:
        score += 20
        feedback_parts.append("Name matches exactly")
    elif target_name.strip().lower() == expected_name.lower():
        score += 10
        feedback_parts.append(f"Name match case-insensitive ('{target_name}')")
    else:
        feedback_parts.append(f"Name mismatch ('{target_name}')")

    # 3. Description Check (25 pts)
    # Check for presence of keywords
    desc_lower = target_desc.lower()
    keywords_found = [kw for kw in expected_keywords if kw.lower() in desc_lower]
    keyword_count = len(keywords_found)
    
    if keyword_count >= 3:
        score += 25
        feedback_parts.append(f"Description valid ({keyword_count} keywords)")
    elif keyword_count >= 1:
        score += 10
        feedback_parts.append(f"Description partial ({keyword_count} keywords)")
    else:
        feedback_parts.append("Description missing/generic")

    # 4. Anti-Gaming: Count Increased (15 pts)
    # Ensures the agent actually created something new rather than finding an old one
    # (Though setup_task.sh tries to delete old ones, this is a safety net)
    if current_count > initial_count:
        score += 15
        feedback_parts.append("Count increased verified")
    else:
        feedback_parts.append("No increase in total identifier types count")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "target_name": target_name,
            "target_desc": target_desc,
            "keywords_found": keywords_found,
            "count_delta": current_count - initial_count
        }
    }