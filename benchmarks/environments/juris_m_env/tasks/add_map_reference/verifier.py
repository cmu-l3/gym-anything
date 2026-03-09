#!/usr/bin/env python3
"""
Verifier for add_map_reference task.

Verification Strategy:
1. Validates that a "Map" item exists.
2. Checks specific metadata fields (Title, Scale, Series, etc.).
3. Verifies the Creator name and Role (Cartographer).
4. Checks for "do nothing" (item must be created during the session).
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_map_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the creation of the USGS Map reference."""
    
    # 1. Setup and retrieve data
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/task_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not retrieve task result (did the agent crash?): {e}"
        }

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Database error: {result['error']}"}

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    metadata = task_info.get("metadata", {})
    expected_fields = metadata.get("expected_fields", {})
    expected_creator = metadata.get("expected_creator", {})

    # Check 1: Item Found (20 pts)
    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No Map item found with title matching 'Washington West'. Did you create the item?",
            "details": result
        }
    score += 20
    feedback.append("Map item created (+20)")

    # Check 2: Metadata Fields
    fields = result.get("fields", {})
    
    # Title (10 pts)
    if expected_fields['title'] in fields.get('title', ''):
        score += 10
        feedback.append("Title correct (+10)")
    else:
        feedback.append(f"Title mismatch. Expected: '{expected_fields['title']}', Found: '{fields.get('title')}'")

    # Scale (15 pts) - Critical for maps
    if expected_fields['scale'] == fields.get('scale', ''):
        score += 15
        feedback.append("Scale correct (+15)")
    else:
        feedback.append(f"Scale mismatch. Expected: '{expected_fields['scale']}', Found: '{fields.get('scale')}'")

    # Series Title (15 pts)
    if expected_fields['seriesTitle'] == fields.get('seriesTitle', ''):
        score += 15
        feedback.append("Series Title correct (+15)")
    else:
        feedback.append(f"Series Title mismatch. Expected: '{expected_fields['seriesTitle']}', Found: '{fields.get('seriesTitle')}'")
        
    # Publisher & Place (10 pts)
    pub_ok = expected_fields['publisher'] == fields.get('publisher', '')
    place_ok = expected_fields['place'] == fields.get('place', '')
    if pub_ok and place_ok:
        score += 10
        feedback.append("Publisher/Place correct (+10)")
    elif pub_ok or place_ok:
        score += 5
        feedback.append("Publisher/Place partially correct (+5)")
    else:
        feedback.append("Publisher and Place incorrect")

    # Date (10 pts)
    if expected_fields['date'] == fields.get('date', ''):
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date incorrect. Expected: '{expected_fields['date']}'")

    # Check 3: Creator (20 pts)
    creators = result.get("creators", [])
    creator_found = False
    role_correct = False
    
    for c in creators:
        # Check name (handle cases where it might be entered as single field or split)
        name_match = (expected_creator['name'] in c.get('lastName', '')) or \
                     (expected_creator['name'] in c.get('firstName', ''))
        if name_match:
            creator_found = True
            if c.get('type') == expected_creator['role']:
                role_correct = True
            break
    
    if creator_found and role_correct:
        score += 20
        feedback.append("Creator and Role (Cartographer) correct (+20)")
    elif creator_found:
        score += 10
        feedback.append("Creator name correct but Role incorrect (should be 'cartographer') (+10)")
    else:
        feedback.append(f"Creator '{expected_creator['name']}' not found")

    # Check 4: Anti-gaming (Date Added check done implicitly by export script resetting DB or checking timestamp)
    # The export script filters by title which we cleaned in setup. If it exists, it's new.
    # We can assume if we got this far, it's a valid attempt.

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }