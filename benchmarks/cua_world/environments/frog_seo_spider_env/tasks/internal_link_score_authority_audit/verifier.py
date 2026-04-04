#!/usr/bin/env python3
"""
Verifier for internal_link_score_authority_audit task.

Verifies:
1. Screaming Frog ran.
2. An exported CSV exists at the specific path.
3. The CSV contains the 'Link Score' column.
4. CRITICAL: Link Score values are > 0 (proving 'Crawl Analysis' was executed).
5. A summary report exists.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_internal_link_score_authority_audit(traj, env_info, task_info):
    """
    Verify authority audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Retrieve Result JSON
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

    # 2. Check CSV Existence & Timing (20 pts)
    csv_exists = result.get('csv_exists', False)
    csv_modified = result.get('csv_modified_during_task', False)
    
    if csv_exists and csv_modified:
        score += 20
        feedback_parts.append("Exported CSV found (20/20)")
    elif csv_exists:
        score += 5
        feedback_parts.append("Exported CSV found but timestamp is old (5/20)")
    else:
        feedback_parts.append("No exported CSV found (0/20)")

    # 3. Check Column Presence (20 pts)
    has_col = result.get('has_link_score_col', False)
    if has_col:
        score += 20
        feedback_parts.append("'Link Score' column present (20/20)")
    else:
        feedback_parts.append("'Link Score' column missing (0/20)")

    # 4. CRITICAL: Check Link Score Values (Analysis Run?) (40 pts)
    # If Crawl Analysis is NOT run, Link Score column exists but values are all 0
    max_score = result.get('max_link_score', 0)
    row_count = result.get('row_count', 0)
    
    # We expect some rows to have score > 0. Typically homepage is high.
    if row_count > 10 and max_score > 0:
        score += 40
        feedback_parts.append(f"Crawl Analysis confirmed (Max Score: {max_score}) (40/40)")
    elif row_count > 0 and max_score == 0:
        feedback_parts.append("Crawl Analysis NOT run (Link Scores are all 0) (0/40)")
    else:
        feedback_parts.append("Insufficient data rows to verify analysis (0/40)")

    # 5. Check Report (20 pts)
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', "")
    
    if report_exists and len(report_content.strip()) > 10:
        score += 20
        feedback_parts.append("Summary report created (20/20)")
    elif report_exists:
        score += 5
        feedback_parts.append("Summary report empty (5/20)")
    else:
        feedback_parts.append("Summary report missing (0/20)")

    # Final logic
    # Must have performed analysis (max_score > 0) to pass
    passed = (score >= 80) and (max_score > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }