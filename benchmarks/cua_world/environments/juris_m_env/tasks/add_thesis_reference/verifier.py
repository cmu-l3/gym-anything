#!/usr/bin/env python3
"""
Verifier for add_thesis_reference task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_thesis_reference(traj, env_info, task_info):
    """
    Verify that the user added the correct thesis reference.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    target_title = metadata.get('target_title', "A Symbolic Analysis of Relay and Switching Circuits")
    target_author_last = metadata.get('target_author_last', "Shannon")
    target_university = metadata.get('target_university', "Massachusetts Institute of Technology")
    target_type = metadata.get('target_type', "Master's Thesis")
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    if not result.get("item_found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No item matching the thesis title was found in the library."
        }

    # Criterion 1: Item created (30 pts)
    score += 30
    feedback_parts.append("Thesis item created")
    
    item = result.get("item", {})
    fields = item.get("fields", {})
    creators = item.get("creators", [])
    
    # Criterion 2: Correct Title (20 pts)
    title = fields.get("title", "")
    if target_title.lower() in title.lower():
        score += 20
        feedback_parts.append("Title correct")
    else:
        feedback_parts.append(f"Title incorrect ('{title}')")

    # Criterion 3: Correct Author (20 pts)
    author_found = False
    for creator in creators:
        if target_author_last.lower() in creator.get("lastName", "").lower():
            author_found = True
            break
    
    if author_found:
        score += 20
        feedback_parts.append("Author correct")
    else:
        feedback_parts.append("Author not found or incorrect")

    # Criterion 4: University (15 pts)
    # Field name for university in Jurism is usually 'university' or 'publisher' depending on mapping,
    # but for Thesis type it is specifically 'university'.
    university = fields.get("university", "")
    # Sometimes mapped to 'publisher' in generic queries, check both
    if not university:
        university = fields.get("publisher", "")
        
    if "massachusetts" in university.lower() and "technology" in university.lower():
        score += 15
        feedback_parts.append("University correct")
    else:
        feedback_parts.append(f"University incorrect ('{university}')")

    # Criterion 5: Date and Type (15 pts)
    date = fields.get("date", "")
    type_field = fields.get("type", "")
    
    date_ok = "1940" in date
    type_ok = "master" in type_field.lower() or "thesis" in type_field.lower()
    
    if date_ok and type_ok:
        score += 15
        feedback_parts.append("Date and Type correct")
    elif date_ok:
        score += 7
        feedback_parts.append("Date correct, Type incorrect")
    elif type_ok:
        score += 8
        feedback_parts.append("Type correct, Date incorrect")
    else:
        feedback_parts.append("Date and Type incorrect")

    # Anti-gaming check (Pass/Fail)
    if not result.get("timestamp_valid", False):
        score = 0
        feedback_parts = ["Item detected but timestamp indicates it pre-existed (anti-gaming violation)"]

    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }