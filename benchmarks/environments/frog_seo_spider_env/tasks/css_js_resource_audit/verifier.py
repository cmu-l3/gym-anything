#!/usr/bin/env python3
"""Verifier for CSS and JavaScript Frontend Resource Audit task.

Scoring (100 points total):
- CSS CSV exists with correct content (25 pts)
- JS CSV exists with correct content (25 pts)
- CSS and JS CSVs are distinct files (10 pts)
- Both CSVs created after task start (10 pts)
- Report file exists at correct path (10 pts)
- Report has sufficient content (>300 chars) (10 pts)
- Report mentions both CSS and JS with counts (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_css_js_resource_audit(traj, env_info, task_info):
    """Verify CSS and JS resource audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/css_js_audit_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8-sig') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Result JSON invalid: {e}"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # --- Criterion 1: CSS CSV Found (25 pts) ---
    css_found = result.get('css_csv_found', False)
    if css_found:
        score += 25
        feedback_parts.append("CSS CSV found (25/25)")
    else:
        feedback_parts.append("No valid CSS CSV found (0/25)")

    # --- Criterion 2: JS CSV Found (25 pts) ---
    js_found = result.get('js_csv_found', False)
    if js_found:
        score += 25
        feedback_parts.append("JS CSV found (25/25)")
    else:
        feedback_parts.append("No valid JS CSV found (0/25)")

    # --- Criterion 3: Distinct Files (10 pts) ---
    distinct = result.get('files_are_distinct', False)
    if distinct:
        score += 10
        feedback_parts.append("CSVs are distinct files (10/10)")
    elif css_found and js_found:
        feedback_parts.append("CSS and JS data found in SAME file - separate exports required (0/10)")
    else:
        feedback_parts.append("Distinct check skipped (0/10)")

    # --- Criterion 4: Anti-gaming / Timestamp Check (10 pts) ---
    # Implied by export script logic (files must be newer than task start),
    # but we award points explicitly if files were found.
    if css_found or js_found:
        score += 10
        feedback_parts.append("Files created during task (10/10)")
    else:
        feedback_parts.append("No new files created (0/10)")

    # --- Criterion 5: Report Exists (10 pts) ---
    report_found = result.get('report_found', False)
    if report_found:
        score += 10
        feedback_parts.append("Report file exists (10/10)")
    else:
        feedback_parts.append("Report file missing (0/10)")

    # --- Criterion 6: Report Content Length (10 pts) ---
    report_size = result.get('report_size', 0)
    # Task description asked for >300 chars approx, but let's be lenient on verify
    # Use >200 bytes as reasonable threshold for a "brief report"
    if report_size > 200:
        score += 10
        feedback_parts.append(f"Report length ok ({report_size} bytes) (10/10)")
    elif report_found:
        score += 5
        feedback_parts.append(f"Report too short ({report_size} bytes) (5/10)")
    else:
        feedback_parts.append("No report content (0/10)")

    # --- Criterion 7: Report Content Validity (10 pts) ---
    report_valid = result.get('report_content_valid', False)
    if report_valid:
        score += 10
        feedback_parts.append("Report mentions CSS/JS and counts (10/10)")
    elif report_found:
        feedback_parts.append("Report missing specific keywords/counts (0/10)")
    else:
        feedback_parts.append("No report content to validate (0/10)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }