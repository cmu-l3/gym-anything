#!/usr/bin/env python3
"""
Verifier for add_cle_presentation task.

Criteria:
1. Item exists with correct title (Required)
2. Item type is 'presentation' (Required)
3. Both presenters added correctly (First/Last names)
4. Metadata fields correct (Meeting Name, Place, Date, Genre, URL)
5. Item created *during* the task window (Anti-gaming)
"""

import os
import json
import logging
import tempfile
from datetime import datetime
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_cle_presentation(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    # 2. Initialization
    score = 0
    max_score = 100
    feedback_parts = []
    
    # 3. Check Basic Existence (Gatekeeper)
    if not result.get("item_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No item found with the title 'The Future of Legal Tech: AI and Ethics'. Ensure you typed the title exactly."
        }
    
    score += 10
    feedback_parts.append("Item found with correct title (+10)")

    # 4. Check Item Type (Presentation)
    # Zotero/Jurism type name for presentation is usually "presentation"
    item_type = result.get("item_type", "").lower()
    if item_type == "presentation":
        score += 20
        feedback_parts.append("Correct Item Type: Presentation (+20)")
    else:
        feedback_parts.append(f"Incorrect Item Type: Found '{item_type}', expected 'presentation'")

    # 5. Check Anti-Gaming (Timestamp)
    # Date format in Zotero DB is usually "YYYY-MM-DD HH:MM:SS"
    item_date_str = result.get("item_date_added")
    task_start_ts = result.get("task_start", 0)
    
    created_during_task = False
    if item_date_str:
        try:
            # Parse DB time (UTC usually)
            item_ts = datetime.strptime(item_date_str, "%Y-%m-%d %H:%M:%S").timestamp()
            # Allow slight clock skew, but generally item_ts should be > task_start
            if item_ts >= task_start_ts - 5: # 5s buffer
                created_during_task = True
        except ValueError:
            pass # Parsing failed
            
    if created_during_task:
        score += 10
        feedback_parts.append("Item created during task session (+10)")
    else:
        feedback_parts.append("Item timestamp indicates it was not created during this session (0)")

    # 6. Check Creators (Presenters)
    creators = result.get("creators", [])
    expected_creators = metadata.get("expected_creators", [])
    
    creators_found = 0
    for expected in expected_creators:
        match = False
        for c in creators:
            # Case insensitive match
            if (c.get("firstName", "").lower() == expected["first"].lower() and 
                c.get("lastName", "").lower() == expected["last"].lower()):
                match = True
                break
        if match:
            creators_found += 1
    
    if creators_found == 2:
        score += 20
        feedback_parts.append("Both presenters added correctly (+20)")
    elif creators_found == 1:
        score += 10
        feedback_parts.append("One presenter found, one missing (+10)")
    else:
        feedback_parts.append("No correct presenters found")

    # 7. Check Metadata Fields
    fields = result.get("fields", {})
    
    # Meeting Name
    # Note: DB field name might be 'publicationTitle' or 'meetingName' depending on mapping
    # For Presentation type, 'meetingName' is standard but sometimes maps to 'publicationTitle' in generic queries if not careful
    # The export script extracts by fieldName, which comes from the fields table. 
    # For presentations, field is 'meetingName'.
    meeting = fields.get("meetingName", "")
    if not meeting: 
        # Fallback if mapped differently
        meeting = fields.get("publicationTitle", "")
        
    if metadata.get("expected_meeting") in meeting:
        score += 10
        feedback_parts.append("Meeting Name correct (+10)")
    else:
        feedback_parts.append(f"Meeting Name incorrect/missing")

    # Genre / Type
    # In UI it's "Type", in DB it's often 'genre' or 'type' field
    genre = fields.get("genre", "")
    if not genre:
        genre = fields.get("type", "")
        
    if metadata.get("expected_genre").lower() in genre.lower():
        score += 10
        feedback_parts.append("Genre/Type correct (+10)")
    else:
        feedback_parts.append("Genre/Type incorrect")

    # Place
    if metadata.get("expected_place") in fields.get("place", ""):
        score += 10
        feedback_parts.append("Place correct (+10)")
    else:
        feedback_parts.append("Place incorrect")

    # Date
    if metadata.get("expected_date") in fields.get("date", ""):
        score += 5
        feedback_parts.append("Date correct (+5)")
    else:
        feedback_parts.append("Date incorrect")
        
    # URL
    if metadata.get("expected_url") in fields.get("url", ""):
        score += 5
        feedback_parts.append("URL correct (+5)")
    else:
        feedback_parts.append("URL incorrect")

    # 8. Final Result
    passed = score >= 80  # Threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "item_found": result.get("item_found"),
            "fields_captured": fields,
            "creators_captured": creators
        }
    }