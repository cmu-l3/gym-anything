#!/usr/bin/env python3
"""
Verifier for add_letter_reference task.

Criteria:
1. Item exists with correct title "Letter from Birmingham Jail" (30 pts)
2. Item type is "letter" (20 pts)
3. Author is Martin Luther King Jr. (10 pts)
4. Recipient is Eight Alabama Clergymen (distinct role check) (20 pts)
5. Date and Type fields populated correctly (10 pts)
6. Created during task execution (10 pts)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_letter_reference(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    
    # 1. Load result from VM
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/add_letter_reference_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}

    if not result.get("found"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Item 'Letter from Birmingham Jail' not found in library. Did you create it and enter the title correctly?"
        }

    score = 0
    feedback = []
    item = result.get("item", {})
    fields = item.get("fields", {})
    creators = result.get("creators", [])
    
    # Metadata targets
    metadata = task_info.get("metadata", {})
    target_title = metadata.get("target_title", "Letter from Birmingham Jail")

    # Criterion 1: Title & Existence (already confirmed existence above)
    title = fields.get("title", "")
    if target_title.lower() in title.lower():
        score += 30
        feedback.append("Title matches (+30)")
    else:
        feedback.append(f"Title mismatch: found '{title}'")

    # Criterion 2: Item Type
    # In Zotero schema, typeName for letter is 'letter'
    type_name = item.get("type", "").lower()
    if type_name == "letter":
        score += 20
        feedback.append("Item type is 'Letter' (+20)")
    else:
        feedback.append(f"Incorrect item type: found '{type_name}', expected 'Letter'")

    # Criterion 3: Author (King)
    author_found = False
    for c in creators:
        # Check for role 'author' or generic primary creator
        if c['role'] == 'author' and 'king' in c['last'].lower():
            author_found = True
            break
    
    if author_found:
        score += 10
        feedback.append("Author 'King' found (+10)")
    else:
        feedback.append("Author 'Martin Luther King Jr.' not found")

    # Criterion 4: Recipient (Clergymen)
    # This is the key "advanced" part of the task - changing creator role
    recipient_found = False
    for c in creators:
        if c['role'] == 'recipient' and 'clergymen' in c['last'].lower():
            recipient_found = True
            break
            
    if recipient_found:
        score += 20
        feedback.append("Recipient 'Eight Alabama Clergymen' found (+20)")
    else:
        # Check if they added as author instead
        misclassified = any(c['role'] == 'author' and 'clergymen' in c['last'].lower() for c in creators)
        if misclassified:
            feedback.append("Clergymen added as Author instead of Recipient (0 pts for this criterion)")
        else:
            feedback.append("Recipient 'Eight Alabama Clergymen' not found")

    # Criterion 5: Other Metadata (Date, Type, Abstract)
    meta_score = 0
    date = fields.get("date", "")
    letter_type = fields.get("type", "") # The field name for 'Letter Type' is often just 'type' in fields table or mapped
    # Fallback: sometimes 'letterType' is the field name depending on Jurism version
    if not letter_type:
        letter_type = fields.get("letterType", "")
    
    abstract = fields.get("abstractNote", "")

    if "1963" in date:
        meta_score += 3
    if "open" in letter_type.lower():
        meta_score += 3
    if "nonviolent" in abstract.lower():
        meta_score += 4
        
    score += meta_score
    if meta_score == 10:
        feedback.append("Date, Letter Type, and Abstract correct (+10)")
    elif meta_score > 0:
        feedback.append(f"Partial metadata correct (+{meta_score})")

    # Criterion 6: Anti-gaming
    if result.get("created_during_task"):
        score += 10
        feedback.append("Item created during task (+10)")
    else:
        feedback.append("Item timestamp indicates pre-existence or clock error")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "item_type": type_name,
            "creators": creators,
            "fields": fields
        }
    }