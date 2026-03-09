#!/usr/bin/env python3
"""Verifier for Readability Content Quality Audit task.

Scoring (100 points total):
1. CSV Export Created (30 pts): File exists and modified during task.
2. Readability Configured (40 pts): CSV header contains "Flesch" or "Readability".
3. Data Populated (20 pts): CSV has data rows and target domain.
4. Analysis Report (10 pts): Text report exists and contains a URL.

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_readability_audit(traj, env_info, task_info):
    """Verify readability audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may not have run"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # 1. CSV Export Created (30 pts)
    csv_exists = result.get('csv_exists', False)
    csv_modified = result.get('csv_modified', False)
    
    if csv_exists and csv_modified:
        score += 30
        feedback_parts.append("CSV exported successfully (30/30)")
    elif csv_exists:
        score += 10
        feedback_parts.append("CSV exists but was not modified during task (10/30)")
    else:
        feedback_parts.append("No CSV export found (0/30)")

    # 2. Readability Configured (40 pts)
    # This checks if the "Flesch Reading Ease" column is present
    has_readability = result.get('has_readability_column', False)
    if has_readability:
        score += 40
        feedback_parts.append("Readability feature enabled (column found) (40/40)")
    else:
        feedback_parts.append("Readability column missing - feature likely not enabled (0/40)")

    # 3. Data Populated (20 pts)
    # Check if rows exist and domain matches
    row_count = result.get('row_count', 0)
    domain_found = result.get('target_domain_found', False)
    
    if row_count > 0 and domain_found:
        score += 20
        feedback_parts.append(f"Data populated correctly with {row_count} rows (20/20)")
    elif row_count > 0:
        score += 10
        feedback_parts.append(f"Data rows found ({row_count}) but target domain not confirmed (10/20)")
    else:
        feedback_parts.append("CSV is empty or missing data (0/20)")

    # 4. Analysis Report (10 pts)
    report_exists = result.get('report_exists', False)
    report_has_url = result.get('report_has_url', False)
    
    if report_exists and report_has_url:
        score += 10
        feedback_parts.append("Report created with URL (10/10)")
    elif report_exists:
        score += 5
        feedback_parts.append("Report exists but URL missing/invalid (5/10)")
    else:
        feedback_parts.append("No analysis report found (0/10)")

    # Pass logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }