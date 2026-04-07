#!/usr/bin/env python3
"""
Verifier for Resolve Fatal Error and Optimize task.

This task requires the agent to diagnose a PHP fatal error caused by a rogue
plugin, delete the plugin folder via the terminal to restore the site, clean
up spam and revisions from the DB without destroying valid data, and publish
an incident report.

Scoring criteria (100 points total):
1. Site Recovered (HTTP 200/301/302) (20 pts)
2. Rogue plugin folder deleted (15 pts)
3. Spam comments removed (0 remaining) (15 pts)
4. Post revisions removed (0 remaining) (15 pts)
5. Valid data preserved (Valid posts > 1 AND valid comments > 0) (15 pts)
6. Incident Report published (20 pts)

Pass threshold: 75 points. MUST include Site Recovered AND Valid data preserved.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_resolve_fatal_error(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/resolve_fatal_error_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Site Recovered (20 pts)
    http_status = str(result.get('http_status', '0'))
    site_recovered = http_status in ['200', '301', '302']
    if site_recovered:
        score += 20
        feedback_parts.append("Site recovered (HTTP " + http_status + ")")
    else:
        feedback_parts.append("Site still down (HTTP " + http_status + ")")

    # 2. Rogue plugin deleted (15 pts)
    plugin_exists = result.get('plugin_exists', True)
    if not plugin_exists:
        score += 15
        feedback_parts.append("Rogue plugin deleted")
    else:
        feedback_parts.append("Rogue plugin still exists")

    # 3. Spam cleaned (15 pts)
    try:
        spam_count = int(result.get('spam_count', -1))
    except ValueError:
        spam_count = -1

    if spam_count == 0:
        score += 15
        feedback_parts.append("Spam cleaned")
    else:
        feedback_parts.append(f"Spam not fully cleaned ({spam_count} remaining)")

    # 4. Revisions cleaned (15 pts)
    try:
        revision_count = int(result.get('revision_count', -1))
    except ValueError:
        revision_count = -1

    if revision_count == 0:
        score += 15
        feedback_parts.append("Revisions cleaned")
    else:
        feedback_parts.append(f"Revisions not fully cleaned ({revision_count} remaining)")

    # 5. Data preserved (15 pts)
    # The setup generates valid comments and posts. We must ensure they weren't deleted
    # by a lazy TRUNCATE query.
    try:
        valid_comments = int(result.get('valid_comments_count', 0))
        valid_posts = int(result.get('valid_posts_count', 0))
    except ValueError:
        valid_comments = 0
        valid_posts = 0

    report_exists = result.get('report_post_exists', False)
    
    # If report exists, valid posts should be at least 2 (1 original + 1 report).
    # If no report, should be at least 1.
    expected_min_posts = 2 if report_exists else 1
    
    data_preserved = (valid_comments > 0) and (valid_posts >= expected_min_posts)
    
    if data_preserved:
        score += 15
        feedback_parts.append("Valid data preserved")
    else:
        feedback_parts.append(f"FAIL: Valid data deleted! (Posts: {valid_posts}, Comments: {valid_comments})")

    # 6. Incident report published (20 pts)
    if report_exists:
        score += 20
        feedback_parts.append("Incident report published")
    else:
        feedback_parts.append("Incident report missing")

    # Final logic
    passed = (score >= 75) and site_recovered and data_preserved

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }