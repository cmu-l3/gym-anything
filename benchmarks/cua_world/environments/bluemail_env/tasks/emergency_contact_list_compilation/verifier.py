#!/usr/bin/env python3
"""
Verifier for emergency_contact_list_compilation task.

SCORING CRITERIA:
1. Draft Created (10 pts): Email draft exists.
2. Recipient Correct (10 pts): To: emergency-contacts@internal.org
3. Subject Relevant (10 pts): Contains 'emergency', 'phone', 'contact', or 'list'.
4. Valid Contacts (60 pts): 20 pts per VALIDATED phone number found in draft (up to 3).
   - Validation means the number was actually found in the inbox source emails.
   - Prevents hallucination or copy-pasting fake data.
5. Formatting (10 pts): Draft body has sufficient length/structure.

Pass Threshold: 70 points (Must get at least 2 valid numbers + draft mechanics).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_contact_list(traj, env_info, task_info):
    """Verify the emergency contact list task."""
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_recipient = metadata.get('target_recipient', 'emergency-contacts@internal.org')
    
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
    
    # 2. Check Draft Existence
    if result.get('draft_found', False):
        score += 10
        feedback_parts.append("Draft email found")
    else:
        return {"passed": False, "score": 0, "feedback": "No draft email found"}

    # 3. Check Recipient
    draft_to = result.get('draft_to', '').lower()
    if target_recipient.lower() in draft_to:
        score += 10
        feedback_parts.append("Recipient correct")
    else:
        feedback_parts.append(f"Incorrect recipient: '{draft_to}'")

    # 4. Check Subject
    subject = result.get('draft_subject', '').lower()
    keywords = metadata.get('required_subject_keywords', ['emergency', 'phone', 'contact', 'list'])
    if any(k in subject for k in keywords):
        score += 10
        feedback_parts.append("Subject contains keywords")
    else:
        feedback_parts.append("Subject missing keywords")

    # 5. Check Verified Numbers (The Core Task)
    # The export script has already cross-referenced draft numbers against the inbox.
    verified_count = result.get('verified_phone_count', 0)
    verified_numbers = result.get('verified_numbers', [])
    
    # Cap at 3 for scoring
    score_count = min(verified_count, 3)
    points_per_contact = 20
    contact_score = score_count * points_per_contact
    score += contact_score
    
    if verified_count >= 3:
        feedback_parts.append(f"Excellent! Found {verified_count} valid contacts ({', '.join(verified_numbers)})")
    elif verified_count > 0:
        feedback_parts.append(f"Found {verified_count} valid contacts. Need 3.")
    else:
        feedback_parts.append("No valid phone numbers found in draft (or numbers don't match inbox)")

    # 6. Formatting / Body Check
    body = result.get('draft_body_snippet', '')
    if len(body) > 30 and '\n' in body:
        score += 10
        feedback_parts.append("Body content appears structured")
    
    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "verified_numbers": verified_numbers,
            "draft_found": True
        }
    }