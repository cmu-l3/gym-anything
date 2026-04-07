#!/usr/bin/env python3
"""Verifier for Configure Default Dashboard task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_default_dashboard(traj, env_info, task_info):
    """
    Verify the default dashboard configuration.

    Scoring (100 points):
    1. 'Online users' block removed (20 points)
    2. 'Timeline' block added (30 points)
    3. 'Student Support' block added (title/existence) (15 points)
    4. 'Student Support' content correct (contains email) (15 points)
    5. Dashboard reset performed (custom user dashboard removed) (20 points)

    Pass threshold: 65 points (Must include Timeline + Support block creation)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_default_dashboard_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        logger.info(f"Verification result: {result}")

        # Criterion 1: Online users block removed (20 points)
        if not result.get('online_users_found', False):
            score += 20
            subscores["online_users_removed"] = True
            feedback_parts.append("Online Users block removed")
        else:
            subscores["online_users_removed"] = False
            feedback_parts.append("Online Users block still present")

        # Criterion 2: Timeline block added (30 points)
        if result.get('timeline_found', False):
            score += 30
            subscores["timeline_added"] = True
            feedback_parts.append("Timeline block added")
        else:
            subscores["timeline_added"] = False
            feedback_parts.append("Timeline block NOT found")

        # Criterion 3: Support block title (15 points)
        if result.get('support_block_title_correct', False):
            score += 15
            subscores["support_title"] = True
            feedback_parts.append("Support block title correct")
        elif result.get('support_block_found', False):
            # Block found but title mismatch - partial credit
            score += 5
            subscores["support_title"] = False
            feedback_parts.append("Support block found but title mismatch")
        else:
            subscores["support_title"] = False
            feedback_parts.append("Support block NOT found")

        # Criterion 4: Support block content (15 points)
        if result.get('support_block_content_correct', False):
            score += 15
            subscores["support_content"] = True
            feedback_parts.append("Support block content correct")
        else:
            subscores["support_content"] = False
            feedback_parts.append("Support block content missing/incorrect")

        # Criterion 5: Dashboard reset (20 points)
        # If user_custom_dashboard_exists is False, it means the record was deleted (Reset worked)
        if not result.get('user_custom_dashboard_exists', True):
            score += 20
            subscores["dashboard_reset"] = True
            feedback_parts.append("Dashboard successfully reset for all users")
        else:
            subscores["dashboard_reset"] = False
            feedback_parts.append("Dashboard NOT reset (user jsmith still has custom dashboard)")

        # Pass logic
        # Must have Timeline AND (Support Title OR Content) to pass basics
        essential_met = subscores.get("timeline_added", False) and (
            subscores.get("support_title", False) or subscores.get("support_content", False)
        )
        
        passed = score >= 65 and essential_met

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}