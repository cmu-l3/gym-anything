#!/usr/bin/env python3
"""
Verifier for update_staff_profile task.

Verifies that:
1. The staff record for Robert Thompson still exists (10 pts)
2. The values have changed from their initial state (anti-gaming) (10 pts)
3. The title is updated to "Dr." (35 pts)
4. The email is updated to "robert.thompson@demoschool.edu" (35 pts)
5. The name fields were not accidentally modified (integrity check) (10 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_update_staff_profile(traj, env_info, task_info):
    """
    Verify the staff profile update task.
    Uses data exported by export_result.sh.
    """
    # 1. Setup and retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata (or defaults)
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'Dr.')
    expected_email = metadata.get('expected_email', 'robert.thompson@demoschool.edu')
    expected_first = metadata.get('target_first_name', 'Robert')
    expected_last = metadata.get('target_last_name', 'Thompson')

    # Read the result JSON file from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    max_score = 100
    feedback_parts = []
    passed = False

    # Extract data
    found = result.get('record_found', False)
    current = result.get('current_state', {})
    initial = result.get('initial_state', {})
    
    cur_title = current.get('title', '').strip()
    cur_email = current.get('email', '').strip()
    cur_first = current.get('first_name', '').strip()
    cur_last = current.get('last_name', '').strip()
    
    init_title = initial.get('title', 'Mr.')
    init_email = initial.get('email', 'r.thompson@oldschool.edu')

    # Criterion 1: Record Exists (10 pts)
    if found:
        score += 10
        feedback_parts.append("Record found")
    else:
        feedback_parts.append("Staff record for Robert Thompson NOT found (may have been deleted or renamed)")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: Anti-Gaming / Change Detection (10 pts)
    # Check if values are different from initial
    values_changed = (cur_title != init_title) or (cur_email != init_email)
    
    if values_changed:
        score += 10
        feedback_parts.append("Values modified from initial state")
    else:
        feedback_parts.append("No changes detected (values match initial state)")
        # If nothing changed, we stop here to avoid giving points for "correctness" 
        # that is actually just the initial state (though in this task initial != expected)
        return {
            "passed": False,
            "score": score,  # 10 pts for finding record
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 3: Title Update (35 pts)
    # Allow loose matching (case insensitive, with/without period)
    match_title_exact = (cur_title == expected_title)
    match_title_loose = (cur_title.lower().replace('.', '') == expected_title.lower().replace('.', ''))
    
    if match_title_exact:
        score += 35
        feedback_parts.append(f"Title updated correctly ('{cur_title}')")
    elif match_title_loose:
        score += 30
        feedback_parts.append(f"Title updated with minor formatting diff ('{cur_title}')")
    elif cur_title != init_title:
        score += 5
        feedback_parts.append(f"Title changed but incorrect (Expected: '{expected_title}', Got: '{cur_title}')")
    else:
        feedback_parts.append(f"Title not updated ('{cur_title}')")

    # Criterion 4: Email Update (35 pts)
    match_email_exact = (cur_email.lower() == expected_email.lower())
    # Partial credit if domain is correct or username is correct
    match_email_partial = ('demoschool' in cur_email.lower() and 'robert' in cur_email.lower())
    
    if match_email_exact:
        score += 35
        feedback_parts.append(f"Email updated correctly ('{cur_email}')")
    elif match_email_partial:
        score += 25
        feedback_parts.append(f"Email close but not exact ('{cur_email}')")
    elif cur_email != init_email:
        score += 5
        feedback_parts.append(f"Email changed but incorrect (Expected: '{expected_email}', Got: '{cur_email}')")
    else:
        feedback_parts.append(f"Email not updated ('{cur_email}')")

    # Criterion 5: Data Integrity (10 pts)
    # Check if name fields were accidentally changed
    name_intact = (cur_first == expected_first) and (cur_last == expected_last)
    
    if name_intact:
        score += 10
        feedback_parts.append("Name fields preserved")
    else:
        feedback_parts.append(f"WARNING: Name fields modified (Got: {cur_first} {cur_last})")

    # 3. Final Determination
    # Pass threshold: 70 points (Requires record found + changed + reasonably correct title & email)
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "current_title": cur_title,
            "current_email": cur_email,
            "expected_title": expected_title,
            "expected_email": expected_email
        }
    }