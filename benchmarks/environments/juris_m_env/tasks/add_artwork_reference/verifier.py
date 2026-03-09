#!/usr/bin/env python3
"""
Verifier for add_artwork_reference task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_artwork_reference(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the user added the correct Artwork reference.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('target_title', "The Problem We All Live With")
    expected_artist_first = metadata.get('target_artist_first', "Norman")
    expected_artist_last = metadata.get('target_artist_last', "Rockwell")
    expected_date = metadata.get('target_date', "1964")
    expected_medium = metadata.get('target_medium', "Oil on canvas")
    expected_archive = metadata.get('target_archive', "Norman Rockwell Museum")
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check for basic errors
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Verification error: {result['error']}"}

    if not result.get('item_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not find an item with title '{expected_title}'. Please create it."
        }

    # Verify item details
    details = result.get('item_details', {})
    fields = details.get('fields', {})
    creators = details.get('creators', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Item Type (30 pts)
    type_name = details.get('typeName', '').lower()
    if type_name == 'artwork':
        score += 30
        feedback_parts.append("Correct Item Type (Artwork)")
    else:
        feedback_parts.append(f"Incorrect Item Type: found '{type_name}', expected 'artwork'")

    # 2. Title (20 pts) - Already filtered by title in export, but validating exact match
    # (The export script uses LOWER match, so strict case check could go here if we wanted, 
    # but exact case matching is typically handled by the 'found' check implicitly for user intent)
    score += 20
    feedback_parts.append("Correct Title")

    # 3. Artist (20 pts)
    artist_found = False
    for creator in creators:
        # Check name
        f_name = creator.get('firstName', '')
        l_name = creator.get('lastName', '')
        c_type = creator.get('creatorType', '')
        
        if expected_artist_last.lower() in l_name.lower() and expected_artist_first.lower() in f_name.lower():
            if c_type == 'artist':
                artist_found = True
                score += 20
                feedback_parts.append("Correct Artist (Name & Role)")
            else:
                score += 10 # Partial credit for right name, wrong role
                feedback_parts.append(f"Artist found but wrong role ('{c_type}' instead of 'artist')")
            break
    
    if not artist_found and score < 60: # Don't double penalize if partial credit given
        feedback_parts.append(f"Artist '{expected_artist_first} {expected_artist_last}' not found")

    # 4. Date (10 pts)
    date_val = fields.get('date', '')
    if expected_date in date_val:
        score += 10
        feedback_parts.append("Correct Date")
    else:
        feedback_parts.append(f"Incorrect/Missing Date (found '{date_val}')")

    # 5. Medium (10 pts)
    medium_val = fields.get('medium', '')
    if expected_medium.lower() in medium_val.lower():
        score += 10
        feedback_parts.append("Correct Medium")
    else:
        feedback_parts.append(f"Incorrect/Missing Medium (found '{medium_val}')")

    # 6. Archive (10 pts)
    # The field name in DB for 'Archive' in artwork type is usually 'repository' or 'archive'
    # We check fields for the value
    archive_val = fields.get('repository', fields.get('archive', ''))
    if expected_archive.lower() in archive_val.lower():
        score += 10
        feedback_parts.append("Correct Archive")
    else:
        feedback_parts.append(f"Incorrect/Missing Archive (found '{archive_val}')")

    # Anti-gaming check
    if not details.get('created_after_start', False):
        score = 0
        feedback_parts.insert(0, "ANTI-GAMING: Item appears to be from a previous session (timestamp check failed).")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }