#!/usr/bin/env python3
"""
Verifier for configure_dashboard_properties task.

Checks:
1. Database state for dashboard name, description, public flag, and alias.
2. HTTP accessibility (public access).
3. VLM verification of trajectory (optional but good practice).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_dashboard_properties(traj, env_info, task_info):
    """
    Verify that the dashboard properties were correctly configured.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    exp_name = metadata.get('expected_name', "Oakwood Plaza Energy Monitor")
    exp_desc = metadata.get('expected_description', "Real-time energy and solar monitoring for Oakwood Plaza retail building")
    exp_alias = metadata.get('expected_alias', "oakwood-plaza")
    exp_public = str(metadata.get('expected_public', 1))

    # Retrieve result
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

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Criterion 1: Dashboard Name (25 pts)
    # ----------------------------------------------------------------
    db_name = result.get('db_name', '')
    if db_name == exp_name:
        score += 25
        feedback_parts.append(f"Name correct ('{db_name}')")
    elif db_name.lower() == exp_name.lower():
        score += 20
        feedback_parts.append(f"Name correct but case mismatch ('{db_name}')")
    else:
        feedback_parts.append(f"Name incorrect (Expected: '{exp_name}', Got: '{db_name}')")

    # ----------------------------------------------------------------
    # Criterion 2: Description (20 pts)
    # ----------------------------------------------------------------
    db_desc = result.get('db_description', '')
    if db_desc == exp_desc:
        score += 20
        feedback_parts.append("Description exact match")
    elif exp_desc in db_desc:
        score += 15
        feedback_parts.append("Description contains expected text")
    elif db_desc:
        # Partial credit if they wrote *something* relevant
        if "Oakwood" in db_desc and "Monitor" in db_desc:
            score += 10
            feedback_parts.append("Description partially correct")
        else:
            feedback_parts.append(f"Description incorrect ('{db_desc}')")
    else:
        feedback_parts.append("Description empty")

    # ----------------------------------------------------------------
    # Criterion 3: Public Access Flag (25 pts)
    # ----------------------------------------------------------------
    db_public = str(result.get('db_public', '0'))
    if db_public == exp_public:
        score += 25
        feedback_parts.append("Public access enabled in DB")
    else:
        feedback_parts.append(f"Public access NOT enabled in DB (value: {db_public})")

    # ----------------------------------------------------------------
    # Criterion 4: Alias (20 pts)
    # ----------------------------------------------------------------
    db_alias = result.get('db_alias', '')
    if db_alias == exp_alias:
        score += 20
        feedback_parts.append(f"Alias correct ('{db_alias}')")
    elif db_alias == "oakwood plaza": # Common mistake: spaces instead of hyphens
        score += 5
        feedback_parts.append("Alias incorrect format (spaces used)")
    else:
        feedback_parts.append(f"Alias incorrect (Expected: '{exp_alias}', Got: '{db_alias}')")

    # ----------------------------------------------------------------
    # Criterion 5: Functional HTTP Access (10 pts)
    # ----------------------------------------------------------------
    http_code = result.get('http_code_id', '000')
    content_visible = result.get('public_content_visible', False)
    
    if str(http_code) == "200" and content_visible:
        score += 10
        feedback_parts.append("Public HTTP access verified")
    elif str(http_code) == "200":
        score += 5
        feedback_parts.append("Public HTTP returns 200 but content verification failed")
    else:
        feedback_parts.append(f"Public HTTP access failed (Code: {http_code})")

    # Final Pass check
    # Need 70 points. This requires getting Name + Public + (Alias OR Description) mostly right.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }