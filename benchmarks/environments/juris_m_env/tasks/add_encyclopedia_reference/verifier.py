#!/usr/bin/env python3
"""
Verifier for add_encyclopedia_reference task.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_encyclopedia_reference(traj, env_info, task_info):
    """
    Verify the agent added the Encyclopedia Article correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "Adverse Possession")
    expected_pub_title = metadata.get('expected_pub_title', "American Jurisprudence")
    expected_series = metadata.get('expected_series', "2d")
    expected_volume = metadata.get('expected_volume', "3")
    expected_publisher = metadata.get('expected_publisher', "West")
    expected_date = metadata.get('expected_date', "2023")
    expected_pages = metadata.get('expected_pages', "120-145")
    expected_author_last = metadata.get('expected_author_last', "Smith")
    expected_author_first = metadata.get('expected_author_first', "John")

    # Load result
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

    if not result.get('item_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No item with title 'Adverse Possession' was found in the library."
        }

    data = result.get('data', {})
    fields = data.get('fields', {})
    creators = data.get('creators', [])
    item_type_id = data.get('itemTypeID')
    
    score = 0
    feedback_parts = []
    
    # 1. Check Item Type (Encyclopedia Article is typically 14)
    # Even if ID varies slightly by version, it should separate it from standard Book (7) or Case (9).
    # We award points if it's 14.
    if item_type_id == 14:
        score += 20
        feedback_parts.append("Correct Item Type (Encyclopedia Article)")
    else:
        feedback_parts.append(f"Incorrect Item Type ID: {item_type_id} (Expected Encyclopedia Article)")

    # 2. Check Fields
    # Title (already checked by query, but verify exact match)
    if fields.get('title') == expected_title:
        score += 15
        feedback_parts.append("Title match")
    else:
        feedback_parts.append(f"Title mismatch: {fields.get('title')}")

    # Encyclopedia Title (publicationTitle)
    if expected_pub_title in fields.get('publicationTitle', ''):
        score += 15
        feedback_parts.append("Encyclopedia Title match")
    else:
        feedback_parts.append(f"Encyclopedia Title mismatch or missing: {fields.get('publicationTitle')}")

    # Series
    if fields.get('series') == expected_series:
        score += 15
        feedback_parts.append("Series match")
    else:
        feedback_parts.append(f"Series mismatch: {fields.get('series')}")

    # Volume
    if str(fields.get('volume', '')) == expected_volume:
        score += 15
        feedback_parts.append("Volume match")
    else:
        feedback_parts.append(f"Volume mismatch: {fields.get('volume')}")

    # Publisher & Date & Pages (10 pts total)
    minor_fields_score = 0
    if expected_publisher in fields.get('publisher', ''):
        minor_fields_score += 4
    if str(fields.get('date', '')) == expected_date:
        minor_fields_score += 3
    if fields.get('pages') == expected_pages:
        minor_fields_score += 3
    
    score += minor_fields_score
    if minor_fields_score == 10:
        feedback_parts.append("Publisher/Date/Pages correct")
    else:
        feedback_parts.append(f"Publisher/Date/Pages partial ({minor_fields_score}/10)")

    # 3. Creator
    author_found = False
    for c in creators:
        if c.get('lastName') == expected_author_last and c.get('firstName') == expected_author_first:
            author_found = True
            break
    
    if author_found:
        score += 10
        feedback_parts.append("Author match")
    else:
        feedback_parts.append("Author mismatch or missing")

    # Anti-gaming check (simple date check)
    # We could parse dateAdded, but usually if it exists and matches fields, it's the one.
    # The setup script deletes pre-existing ones, so finding one implies creation.
    
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }