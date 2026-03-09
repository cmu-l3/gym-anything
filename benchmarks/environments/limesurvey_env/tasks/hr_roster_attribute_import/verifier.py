#!/usr/bin/env python3
"""
Verifier for HR Roster Attribute Import Task.

Verifies:
1. Survey creation
2. Participant import (count > 0)
3. correct Attribute Mapping (CSV columns -> Token Attributes)
4. Correct Piping Syntax usage in question text
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_hr_roster_attribute_import(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: Survey Exists (10 pts)
    if result.get('survey_found', False):
        score += 10
        feedback_parts.append("Survey found")
    else:
        return {"passed": False, "score": 0, "feedback": "Survey 'Q4 Employee Engagement' not found"}

    # Criterion 2: Participants Imported (30 pts)
    count = result.get('participant_count', 0)
    if count >= 5:
        score += 30
        feedback_parts.append(f"Participants imported ({count})")
    elif count > 0:
        score += 15
        feedback_parts.append(f"Partial import ({count} < 7)")
    else:
        feedback_parts.append("No participants found in table")

    # Criterion 3: Attribute Mapping (40 pts total)
    # Expected: attr1="R&D", attr2="San Francisco", attr3="Miles Dyson" for Sarah Connor
    mapping = result.get('test_user_mapping', {})
    a1 = mapping.get('attr1_val', '').strip()
    a2 = mapping.get('attr2_val', '').strip()
    a3 = mapping.get('attr3_val', '').strip()

    # Check Department -> Attribute 1 (20 pts)
    if a1 == "R&D":
        score += 20
        feedback_parts.append("Dept mapped correctly")
    elif a1:
        feedback_parts.append(f"Dept mapping incorrect (got '{a1}')")
    else:
        feedback_parts.append("Dept not mapped")

    # Check Location -> Attribute 2 (10 pts)
    if a2 == "San Francisco":
        score += 10
        feedback_parts.append("Location mapped correctly")
    
    # Check Manager -> Attribute 3 (10 pts)
    if a3 == "Miles Dyson":
        score += 10
        feedback_parts.append("Manager mapped correctly")

    # Criterion 4: Piping Syntax (20 pts)
    if result.get('piping_syntax_found', False):
        score += 20
        feedback_parts.append("Piping syntax correct")
    else:
        feedback_parts.append("Piping syntax '{TOKEN:ATTRIBUTE_1}' not found in any question")

    # Final tally
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }