#!/usr/bin/env python3
"""Verifier for support_backlog_triage task.

Scoring (100 points):
- 4 conversations tagged 'awaiting-first-response': 25 pts (partial credit)
- Tagged conversations assigned to Admin User: 20 pts (partial credit)
- Internal notes on unresponded conversations: 15 pts (partial credit)
- 3 closed conversations reopened to active: 15 pts (partial credit)
- Target conversation replied with correct content: 15 pts
- Target conversation assigned to Derek Thompson: 10 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

EXPECTED_UNRESPONDED = 4
EXPECTED_CLOSED = 3


def verify_support_backlog_triage(traj, env_info, task_info):
    """Verify support backlog triage task completion."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tag = metadata.get('expected_tag', 'awaiting-first-response')
    target_keywords = metadata.get('target_reply_keywords', ['patience', 'engineering', 'resolved'])

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

    # Criterion 1: Conversations tagged 'awaiting-first-response' (25 pts, partial credit)
    try:
        tagged_count = int(result.get('tagged_count', 0))
        if tagged_count >= EXPECTED_UNRESPONDED:
            score += 25
            feedback_parts.append(f"All {tagged_count} unresponded conversations tagged '{expected_tag}' (25/25)")
        elif tagged_count == 3:
            score += 18
            feedback_parts.append(f"3/{EXPECTED_UNRESPONDED} conversations tagged '{expected_tag}' (18/25)")
        elif tagged_count == 2:
            score += 12
            feedback_parts.append(f"2/{EXPECTED_UNRESPONDED} conversations tagged '{expected_tag}' (12/25)")
        elif tagged_count == 1:
            score += 6
            feedback_parts.append(f"1/{EXPECTED_UNRESPONDED} conversation tagged '{expected_tag}' (6/25)")
        else:
            feedback_parts.append(f"No conversations tagged '{expected_tag}' (0/25)")
    except Exception as e:
        feedback_parts.append(f"Tag check error: {e}")

    # Criterion 2: Tagged conversations assigned to Admin User (20 pts, partial credit)
    try:
        tagged_assigned = int(result.get('tagged_assigned_to_admin', 0))
        tagged_count = int(result.get('tagged_count', 0))
        if tagged_count > 0 and tagged_assigned >= tagged_count:
            score += 20
            feedback_parts.append(f"All tagged conversations assigned to Admin User (20/20)")
        elif tagged_assigned >= 3:
            score += 15
            feedback_parts.append(f"{tagged_assigned} tagged conversations assigned to Admin User (15/20)")
        elif tagged_assigned >= 2:
            score += 10
            feedback_parts.append(f"{tagged_assigned} tagged conversations assigned to Admin User (10/20)")
        elif tagged_assigned == 1:
            score += 5
            feedback_parts.append(f"1 tagged conversation assigned to Admin User (5/20)")
        else:
            feedback_parts.append(f"No tagged conversations assigned to Admin User (0/20)")
    except Exception as e:
        feedback_parts.append(f"Assignment check error: {e}")

    # Criterion 3: Internal notes on unresponded conversations (15 pts, partial credit)
    try:
        notes_count = int(result.get('notes_on_unresponded', 0))
        if notes_count >= EXPECTED_UNRESPONDED:
            score += 15
            feedback_parts.append(f"Internal notes added to all {notes_count} unresponded conversations (15/15)")
        elif notes_count >= 3:
            score += 11
            feedback_parts.append(f"Internal notes on {notes_count}/{EXPECTED_UNRESPONDED} unresponded conversations (11/15)")
        elif notes_count >= 2:
            score += 7
            feedback_parts.append(f"Internal notes on {notes_count}/{EXPECTED_UNRESPONDED} unresponded conversations (7/15)")
        elif notes_count == 1:
            score += 4
            feedback_parts.append(f"Internal note on 1/{EXPECTED_UNRESPONDED} unresponded conversations (4/15)")
        else:
            feedback_parts.append(f"No internal notes found on unresponded conversations (0/15)")
    except Exception as e:
        feedback_parts.append(f"Notes check error: {e}")

    # Criterion 4: Closed conversations reopened to Active (15 pts, partial credit)
    try:
        reopened_count = int(result.get('reopened_count', 0))
        if reopened_count >= EXPECTED_CLOSED:
            score += 15
            feedback_parts.append(f"All {reopened_count} closed conversations reopened (15/15)")
        elif reopened_count == 2:
            score += 10
            feedback_parts.append(f"2/{EXPECTED_CLOSED} closed conversations reopened (10/15)")
        elif reopened_count == 1:
            score += 5
            feedback_parts.append(f"1/{EXPECTED_CLOSED} closed conversation reopened (5/15)")
        else:
            feedback_parts.append(f"No closed conversations reopened (0/15)")
    except Exception as e:
        feedback_parts.append(f"Reopen check error: {e}")

    # Criterion 5: Target conversation replied with correct content (15 pts)
    try:
        target_replied = result.get('target_replied', False)
        reply_body = result.get('target_reply_body', '').lower()
        if target_replied:
            keywords_found = sum(1 for kw in target_keywords if kw.lower() in reply_body)
            if keywords_found >= 2:
                score += 15
                feedback_parts.append(f"'Software installation failure' replied with correct content ({keywords_found}/{len(target_keywords)} keywords) (15/15)")
            elif keywords_found == 1:
                score += 8
                feedback_parts.append(f"'Software installation failure' replied but content may be incomplete ({keywords_found}/{len(target_keywords)} keywords) (8/15)")
            else:
                score += 5
                feedback_parts.append(f"'Software installation failure' has an agent reply but content doesn't match expected (5/15)")
        else:
            feedback_parts.append(f"'Software installation failure' has no agent reply (0/15)")
    except Exception as e:
        feedback_parts.append(f"Reply check error: {e}")

    # Criterion 6: Target conversation assigned to Derek Thompson (10 pts)
    try:
        derek_assigned = result.get('target_assigned_to_derek', False)
        if derek_assigned:
            score += 10
            feedback_parts.append("'Software installation failure' assigned to Derek Thompson (10/10)")
        else:
            feedback_parts.append("'Software installation failure' NOT assigned to Derek Thompson (0/10)")
    except Exception as e:
        feedback_parts.append(f"Derek assignment check error: {e}")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
