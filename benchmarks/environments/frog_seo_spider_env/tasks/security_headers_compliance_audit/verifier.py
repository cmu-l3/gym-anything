#!/usr/bin/env python3
"""
Verifier for Security Headers Compliance Audit task.

Scores based on:
1. CSV Export existence and validity (Security tab data, HTTPS).
2. Written Report existence and content (Counts, HSTS analysis).
3. Anti-gaming (Timestamps).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_security_headers_compliance_audit(traj, env_info, task_info):
    """
    Verify the agent audited security headers, exported data, and wrote a report.
    """
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

    score = 0
    feedback_parts = []

    # --- Criterion 1: CSV Export (40 points total) ---
    # File exists and modified (10 pts)
    if result.get('csv_exists') and result.get('csv_modified_after_start'):
        score += 10
        feedback_parts.append("CSV exported")
    else:
        feedback_parts.append("CSV missing or not new")

    # Correct Protocol (HTTPS) (15 pts) - Critical for security audit
    if result.get('csv_has_https'):
        score += 15
        feedback_parts.append("HTTPS audited")
    else:
        feedback_parts.append("No HTTPS URLs found in export (wrong protocol?)")

    # Content check (Security data) (15 pts)
    if result.get('csv_has_security_cols'):
        score += 15
        feedback_parts.append("Security data confirmed in CSV")
    else:
        feedback_parts.append("CSV lacks security header columns")
        
    # Minimum rows
    if result.get('csv_row_count', 0) < 5:
        score = max(0, score - 10) # Penalty for empty/trivial file
        feedback_parts.append("CSV has too few rows")

    # --- Criterion 2: Written Report (40 points total) ---
    # Report exists and modified (10 pts)
    if result.get('report_exists') and result.get('report_modified_after_start'):
        score += 10
        feedback_parts.append("Report created")
    else:
        feedback_parts.append("Report missing")

    # Has counts (15 pts)
    if result.get('report_has_counts'):
        score += 15
        feedback_parts.append("Report includes counts")
    else:
        feedback_parts.append("Report missing numeric counts")

    # Has HSTS mention (15 pts)
    if result.get('report_has_hsts'):
        score += 15
        feedback_parts.append("HSTS analysis present")
    else:
        feedback_parts.append("HSTS not mentioned in report")

    # --- Criterion 3: App Running (20 points total) ---
    # Verify tool was used
    if result.get('app_running'):
        score += 20
        feedback_parts.append("App running")
    else:
        # If they finished and closed it, we might still give points if files are good
        if score > 50:
            score += 10
            feedback_parts.append("App closed (partial credit)")
        else:
            feedback_parts.append("App not running")

    # Final check
    passed = score >= 80  # High bar because specific file paths and contents were requested
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }