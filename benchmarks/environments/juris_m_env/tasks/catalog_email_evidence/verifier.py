#!/usr/bin/env python3
"""
Verifier for catalog_email_evidence task.
Verifies that an 'E-mail' item with specific metadata was created.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_catalog_email_evidence(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify the creation of the email evidence item."""
    
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    expected_subject = metadata.get("expected_subject", "Resignation implications")
    expected_author_last = metadata.get("expected_author_last", "Skilling")
    expected_recipient_last = metadata.get("expected_recipient_last", "Lay")
    expected_date = metadata.get("expected_date", "2001-08-14")
    expected_abstract_fragment = metadata.get("expected_abstract_fragment", "stock impact")

    # Retrieve result file
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/catalog_email_evidence_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result: {e}"
        }

    if not result.get("item_found"):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No item found with subject '{expected_subject}'. Ensure you entered the Subject field correctly."
        }

    details = result.get("item_details", {})
    fields = details.get("fields", {})
    creators = details.get("creators", [])
    item_type = details.get("itemType", "").lower()

    score = 0
    feedback = []

    # 1. Check Item Type (20 pts)
    # Jurism/Zotero typically stores email as 'email' type
    if item_type == "email":
        score += 20
        feedback.append("Item type 'email' correct (+20)")
    else:
        feedback.append(f"Item type incorrect: found '{item_type}', expected 'email'")

    # 2. Check Subject (20 pts) - implicit in finding the item, but verify exact match
    # Zotero maps 'Subject' in UI to 'title' field in DB for emails usually, or 'subject'
    title_val = fields.get("title", "") or fields.get("subject", "")
    if expected_subject.lower() in title_val.lower():
        score += 20
        feedback.append("Subject correct (+20)")
    else:
        feedback.append(f"Subject mismatch: expected '{expected_subject}', got '{title_val}'")

    # 3. Check Date (10 pts)
    date_val = fields.get("date", "")
    if expected_date in date_val:
        score += 10
        feedback.append("Date correct (+10)")
    else:
        feedback.append(f"Date incorrect: expected '{expected_date}', got '{date_val}'")

    # 4. Check Abstract (10 pts)
    abstract_val = fields.get("abstractNote", "")
    if expected_abstract_fragment.lower() in abstract_val.lower():
        score += 10
        feedback.append("Abstract content verified (+10)")
    else:
        feedback.append("Abstract missing or incorrect")

    # 5. Check Creators (Author/Recipient) (40 pts)
    author_found = False
    recipient_found = False

    for c in creators:
        c_type = c.get("creatorType", "").lower()
        last = c.get("lastName", "").lower()
        first = c.get("firstName", "").lower()
        
        if c_type == "author" and expected_author_last.lower() in last:
            author_found = True
        elif c_type == "recipient" and expected_recipient_last.lower() in last:
            recipient_found = True
    
    if author_found:
        score += 20
        feedback.append(f"Author ({expected_author_last}) found (+20)")
    else:
        feedback.append(f"Author ({expected_author_last}) NOT found")

    if recipient_found:
        score += 20
        feedback.append(f"Recipient ({expected_recipient_last}) found (+20)")
    else:
        feedback.append(f"Recipient ({expected_recipient_last}) NOT found")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }