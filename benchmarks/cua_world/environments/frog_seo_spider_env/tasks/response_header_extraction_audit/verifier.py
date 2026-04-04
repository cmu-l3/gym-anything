#!/usr/bin/env python3
"""Verifier for Response Header Extraction Audit task.

Scoring (100 points total):
- SF ran (10 pts)
- CSV file created and contains data (20 pts)
- CSV has correct Custom Extraction columns (30 pts)
- CSV has valid extracted content (Server, Mime, Date) (20 pts)
- Report file exists and contains analysis (20 pts)

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_response_header_extraction_audit(traj, env_info, task_info):
    """Verify response header extraction audit task."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/response_header_extraction_audit_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    csv_data = result.get("csv_data", {})
    report_data = result.get("report_data", {})

    # Criterion 1: SF Running (10 pts)
    if result.get("sf_running", False):
        score += 10
        feedback_parts.append("SF ran (10/10)")
    else:
        feedback_parts.append("SF not running (0/10)")

    # Criterion 2: CSV Created & Has Data (20 pts)
    if csv_data.get("csv_found", False):
        rows = csv_data.get("row_count", 0)
        if rows >= 20:
            score += 20
            feedback_parts.append(f"CSV found with {rows} rows (20/20)")
        elif rows > 0:
            score += 10
            feedback_parts.append(f"CSV found with {rows} rows (10/20)")
        else:
            feedback_parts.append("CSV empty (0/20)")
    else:
        feedback_parts.append("No CSV found (0/20)")

    # Criterion 3: Correct Custom Columns (30 pts)
    cols_found = 0
    if csv_data.get("has_server_header", False): cols_found += 1
    if csv_data.get("has_mime_type", False): cols_found += 1
    if csv_data.get("has_date_header", False): cols_found += 1
    
    col_score = cols_found * 10
    score += col_score
    feedback_parts.append(f"Found {cols_found}/3 required header columns ({col_score}/30)")

    # Criterion 4: Valid Extracted Content (20 pts)
    content_score = 0
    if csv_data.get("target_domain_found", False):
        content_score += 5
    if csv_data.get("extracted_server_value", ""):
        content_score += 10
    if csv_data.get("unique_mime_types", 0) > 0:
        content_score += 5
    
    score += content_score
    feedback_parts.append(f"Content validation ({content_score}/20)")

    # Criterion 5: Report Analysis (20 pts)
    rep_score = 0
    if report_data.get("report_found", False):
        if report_data.get("content_valid", False):
            rep_score += 10
        if report_data.get("mentions_server", False):
            rep_score += 10
    
    score += rep_score
    if report_data.get("report_found", False):
        feedback_parts.append(f"Report analysis ({rep_score}/20)")
    else:
        feedback_parts.append("Report not found (0/20)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }