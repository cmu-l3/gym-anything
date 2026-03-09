#!/usr/bin/env python3
"""
Verifier for product_launch_kickoff task.

Checks that the agent:
  1. Created a 'Product Launch Kickoff' event
  2. Added >= 3 engineering/marketing team attendees
  3. Set location to 'Engineering Lab'
  4. Added a description/agenda
  5. Deleted the 'Sprint Planning - Engineering' event

Scoring (100 pts total, pass threshold = 70):
  - 'Product Launch Kickoff' event exists:           20 pts
  - Event has >= 3 attendees (team members):         25 pts
  - Location contains 'engineering' (any case):      20 pts
  - Description/agenda is non-empty (>= 20 chars):   10 pts
  - 'Sprint Planning - Engineering' deleted:          25 pts
"""

import json
import os
import re
import tempfile


def verify_product_launch_kickoff(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0,
                "feedback": "Verification error: copy_from_env not available"}

    with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
        tmp_path = tmp.name

    try:
        copy_from_env('/tmp/product_launch_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0,
                "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file: {e}"}
    finally:
        if os.path.exists(tmp_path):
            os.unlink(tmp_path)

    score = 0
    feedback = []

    # Criterion 1: Kickoff event created (20 pts)
    if result.get('kickoff_found'):
        score += 20
        feedback.append("PASS: 'Product Launch Kickoff' event created")
    else:
        feedback.append("FAIL: 'Product Launch Kickoff' event not found in calendar")

    # Criterion 2: >= 3 attendees added (25 pts)
    attendee_count = result.get('kickoff_attendee_count', 0)
    if attendee_count >= 3:
        score += 25
        names = result.get('kickoff_attendee_names', [])
        feedback.append(f"PASS: {attendee_count} attendees added ({', '.join(names[:4])})")
    elif attendee_count >= 1:
        score += 10
        feedback.append(f"PARTIAL: Only {attendee_count} attendee(s) added (need >= 3)")
    else:
        feedback.append("FAIL: No attendees added to the kickoff event")

    # Criterion 3: Location contains 'engineering' (20 pts)
    location = result.get('kickoff_location', '')
    if 'engineering' in location.lower():
        score += 20
        feedback.append(f"PASS: Location set to '{location}'")
    else:
        feedback.append(f"FAIL: Location is '{location}' — expected 'Engineering Lab'")

    # Criterion 4: Description/agenda non-empty (10 pts)
    description = result.get('kickoff_description', '')
    plain_desc = re.sub(r'<[^>]+>', '', description).strip()
    if len(plain_desc) >= 20:
        score += 10
        feedback.append(f"PASS: Description has {len(plain_desc)} chars of agenda")
    elif len(plain_desc) > 0:
        score += 5
        feedback.append(f"PARTIAL: Description very short ({len(plain_desc)} chars)")
    else:
        feedback.append("FAIL: No description/agenda written")

    # Criterion 5: Sprint Planning deleted (25 pts)
    if result.get('sprint_deleted'):
        score += 25
        feedback.append("PASS: 'Sprint Planning - Engineering' successfully deleted")
    else:
        feedback.append("FAIL: 'Sprint Planning - Engineering' still exists — must be cancelled")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
