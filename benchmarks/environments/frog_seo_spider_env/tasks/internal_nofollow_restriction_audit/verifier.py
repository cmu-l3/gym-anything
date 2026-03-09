#!/usr/bin/env python3
"""
Verifier for internal_nofollow_restriction_audit task.

Checks:
1. Screaming Frog was used.
2. Correct CSV export file created (Bulk Export > Links format).
3. CSV contains correct data (Source/Destination/Nofollow status).
4. Summary report exists with analysis.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_internal_nofollow_restriction_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
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

    # 1. App Usage (10 pts)
    if result.get('app_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # 2. CSV File Existence & Freshness (20 pts)
    csv_exists = result.get('csv_exists', False)
    csv_fresh = result.get('csv_created_during_task', False)
    
    if csv_exists and csv_fresh:
        score += 20
        feedback_parts.append("New CSV file found (20/20)")
    elif csv_exists:
        score += 10
        feedback_parts.append("CSV file exists but not created during task (10/20)")
    else:
        feedback_parts.append("CSV file not found (0/20)")

    # 3. CSV Structure & Data (40 pts total)
    # This verifies they used "Bulk Export > Links" not just "Export"
    # Standard export uses "Address", Link export uses "Source" & "Destination"
    headers_correct = result.get('csv_has_correct_headers', False)
    has_data = result.get('csv_has_target_data', False)
    row_count = result.get('csv_row_count', 0)

    if headers_correct:
        score += 20
        feedback_parts.append("Correct Link Export format identified (Source/Destination columns) (20/20)")
    else:
        # Check if they might have exported the standard view (Address column)
        headers = result.get('csv_headers_preview', '')
        if 'Address' in headers and 'Source' not in headers:
            feedback_parts.append("Wrong export format: Looks like Page export, not Link export (0/20)")
        else:
            feedback_parts.append("Incorrect CSV headers (0/20)")

    if has_data and row_count > 0:
        score += 20
        feedback_parts.append(f"CSV contains valid data ({row_count} rows) (20/20)")
    elif row_count > 0:
        score += 10
        feedback_parts.append("CSV has rows but target data not confirmed (10/20)")
    else:
        feedback_parts.append("CSV is empty (0/20)")

    # 4. Summary Report (30 pts)
    report_exists = result.get('report_exists', False)
    report_fresh = result.get('report_created_during_task', False)
    report_has_nums = result.get('report_has_numbers', False)
    report_len = result.get('report_length', 0)

    if report_exists and report_fresh:
        if report_len > 10 and report_has_nums:
            score += 30
            feedback_parts.append("Summary report valid (30/30)")
        elif report_len > 0:
            score += 15
            feedback_parts.append("Summary report exists but lacks numeric details (15/30)")
        else:
            score += 5
            feedback_parts.append("Summary report is empty (5/30)")
    else:
        feedback_parts.append("Summary report missing (0/30)")

    # Final Pass Logic
    # Strict pass: Must have correct CSV export format
    passed = (score >= 60) and headers_correct and (row_count > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }