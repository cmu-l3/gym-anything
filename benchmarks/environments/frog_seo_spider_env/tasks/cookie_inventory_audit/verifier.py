#!/usr/bin/env python3
"""Verifier for Cookie Inventory Audit task.

Scoring (100 points total):
- Screaming Frog running (10 pts)
- Valid Cookie CSV Export (50 pts):
  - File created during task (10 pts)
  - Has correct headers (proving 'All Cookies' export) (20 pts)
  - Has data rows (proving 'Store Cookies' was enabled) (20 pts)
- Data Validity (20 pts):
  - Contains 'crawler-test.com' domain (20 pts)
- Summary Report (20 pts):
  - File exists and has content (20 pts)

Pass threshold: 70 points (Must have valid CSV with data)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_cookie_inventory_audit(traj, env_info, task_info):
    """Verify cookie inventory audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Read result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/cookie_audit_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. SF Running (10 pts)
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("SF running (10/10)")
    else:
        feedback_parts.append("SF not running (0/10)")

    # 2. CSV Existence & Headers (30 pts)
    csv_created = result.get('csv_created_during_task', False)
    has_headers = result.get('csv_has_cookie_headers', False)
    
    if csv_created:
        score += 10
        feedback_parts.append("CSV created (10/10)")
        if has_headers:
            score += 20
            feedback_parts.append("Correct cookie headers found (20/20)")
        else:
            feedback_parts.append("Incorrect CSV format/headers (0/20)")
    else:
        feedback_parts.append("No new CSV found (0/30)")

    # 3. CSV Data Content (20 pts) - Proves 'Store Cookies' enabled
    row_count = result.get('csv_row_count', 0)
    if row_count > 0:
        score += 20
        feedback_parts.append(f"Cookie data found: {row_count} rows (20/20)")
    elif csv_created and has_headers:
        feedback_parts.append("CSV empty - 'Store Cookies' likely not enabled (0/20)")
    else:
        feedback_parts.append("No data (0/20)")

    # 4. Domain Check (20 pts)
    if result.get('csv_has_crawler_test', False):
        score += 20
        feedback_parts.append("Domain 'crawler-test.com' confirmed (20/20)")
    else:
        feedback_parts.append("Target domain not found in export (0/20)")

    # 5. Summary Report (20 pts)
    if result.get('report_exists', False) and result.get('report_length', 0) > 10:
        score += 20
        feedback_parts.append("Summary report exists (20/20)")
    else:
        feedback_parts.append("Summary report missing or empty (0/20)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }