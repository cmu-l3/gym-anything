#!/usr/bin/env python3
"""
Verifier for Redirect Loop Diagnosis task.

Scoring (100 points total):
- Screaming Frog Running: 10 pts
- CSV File Created/Modified: 20 pts
- CSV Validity (Contains Loop Data): 40 pts
    - Checks for specific URLs from crawler-test.com (e.g. 'loop_to_self')
    - Checks for SF status 'Redirect Loop'
- Report Created: 15 pts
- Report Content (Non-empty): 15 pts

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging
import csv

logger = logging.getLogger(__name__)

def verify_redirect_loop_diagnosis(traj, env_info, task_info):
    """Verify redirect loop diagnosis task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # --- Load Result JSON ---
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/redirect_loop_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    # --- Criterion 1: SF Running (10 pts) ---
    if result.get('sf_running', False):
        score += 10
        feedback_parts.append("Screaming Frog running (10/10)")
    else:
        feedback_parts.append("Screaming Frog not running (0/10)")

    # --- Criterion 2: CSV Created/Modified (20 pts) ---
    csv_exists = result.get('csv_exists', False)
    csv_modified = result.get('csv_modified', False)
    
    if csv_exists and csv_modified:
        score += 20
        feedback_parts.append("Loop CSV created (20/20)")
    elif csv_exists:
        # Existed but not modified? Likely failed to export new data
        feedback_parts.append("CSV exists but not modified (0/20)")
    else:
        feedback_parts.append("No CSV found (0/20)")

    # --- Criterion 3: CSV Content Validity (40 pts) ---
    # Need to verify specific crawler-test.com loop URLs
    csv_valid_score = 0
    loop_indicators_found = []
    
    if csv_exists and csv_modified:
        try:
            tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
            tmp_csv.close()
            try:
                copy_from_env('/tmp/redirect_loops_export.csv', tmp_csv.name)
                
                with open(tmp_csv.name, 'r', encoding='utf-8', errors='ignore') as f:
                    content = f.read().lower()
                    
                    # Check for URL signatures
                    if 'loop_to_self' in content:
                        loop_indicators_found.append('loop_to_self')
                    if 'loop_to_other' in content:
                        loop_indicators_found.append('loop_to_other')
                    
                    # Check for Status signatures
                    if 'redirect loop' in content or 'exceeded max redirects' in content:
                        loop_indicators_found.append('status_loop')
                    
            finally:
                if os.path.exists(tmp_csv.name):
                    os.unlink(tmp_csv.name)
        except Exception as e:
            feedback_parts.append(f"Error checking CSV content: {str(e)[:50]}")

    if len(loop_indicators_found) >= 2:
        # Strong evidence (URL + Status or multiple URL types)
        csv_valid_score = 40
        feedback_parts.append(f"CSV valid: {', '.join(loop_indicators_found)} found (40/40)")
    elif len(loop_indicators_found) == 1:
        # Weak evidence
        csv_valid_score = 20
        feedback_parts.append(f"CSV partially valid: {loop_indicators_found[0]} found (20/40)")
    elif csv_exists and csv_modified:
        # File exists but no loops found - likely wrong filter
        feedback_parts.append("CSV does not contain loop data (0/40)")
    
    score += csv_valid_score

    # --- Criterion 4: Report Created (15 pts) ---
    report_exists = result.get('report_exists', False)
    report_modified = result.get('report_modified', False)
    
    if report_exists and report_modified:
        score += 15
        feedback_parts.append("Report created (15/15)")
    else:
        feedback_parts.append("Report missing (0/15)")

    # --- Criterion 5: Report Content (15 pts) ---
    report_len = result.get('report_length', 0)
    if report_exists and report_modified and report_len > 20: # Arbitrary small threshold for non-empty
        score += 15
        feedback_parts.append(f"Report has content ({report_len} bytes) (15/15)")
    elif report_exists:
        feedback_parts.append("Report empty (0/15)")

    # --- Final Result ---
    # Must have valid CSV data to pass
    passed = score >= 70 and csv_valid_score >= 20

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }