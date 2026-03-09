#!/usr/bin/env python3
"""
Verifier for Unsafe Cross-Origin Link Security Audit task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_unsafe_cross_origin_audit(traj, env_info, task_info):
    """
    Verify the security audit task.
    
    Criteria:
    1. Screaming Frog ran (20 pts)
    2. Correct CSV exported (30 pts)
       - Exists, Modified, Contains Domain, Contains '_blank'
    3. Correct filter used (30 pts)
       - Inferred from 'Target' and 'Rel' columns being present in export
    4. Report file created (10 pts)
    5. Data consistency (10 pts)
       - Report count matches CSV row count
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. SF Running (20 pts)
    if result.get('sf_running', False):
        score += 20
        feedback_parts.append("Screaming Frog running (20/20)")
    else:
        feedback_parts.append("Screaming Frog not running (0/20)")

    # 2. CSV Created & Content (30 pts)
    csv_ok = False
    if result.get('csv_exists') and result.get('csv_modified'):
        if result.get('csv_contains_domain') and result.get('csv_contains_unsafe'):
            score += 30
            csv_ok = True
            feedback_parts.append("CSV exported with correct unsafe link data (30/30)")
        else:
            score += 15
            feedback_parts.append("CSV exists but content verification failed (domain or unsafe markers missing) (15/30)")
    else:
        feedback_parts.append("CSV output not found or not modified (0/30)")

    # 3. Correct Filter/Report Type (30 pts)
    # The 'Unsafe Cross-Origin' filter specifically exposes Target and Rel columns
    filter_ok = False
    if result.get('csv_has_target_col') and result.get('csv_has_rel_col'):
        score += 30
        filter_ok = True
        feedback_parts.append("Export contains Security tab columns (Target/Rel) (30/30)")
    elif csv_ok:
        # Partial credit if CSV is right domain but maybe wrong columns?
        score += 10
        feedback_parts.append("Export missing specific Security columns (10/30)")
    else:
        feedback_parts.append("Correct filter evidence not found in CSV (0/30)")

    # 4. Report Created (10 pts)
    if result.get('report_exists') and result.get('report_modified'):
        score += 10
        feedback_parts.append("Summary report created (10/10)")
    else:
        feedback_parts.append("Summary report missing (0/10)")

    # 5. Consistency (10 pts)
    csv_count = result.get('csv_row_count', -1)
    report_val = result.get('report_value', '')
    
    try:
        report_num = int(report_val) if report_val else -1
    except ValueError:
        report_num = -2

    if csv_count > 0 and report_num == csv_count:
        score += 10
        feedback_parts.append(f"Report count ({report_num}) matches CSV rows ({csv_count}) (10/10)")
    elif report_num != -1:
         feedback_parts.append(f"Report count ({report_num}) does not match CSV rows ({csv_count}) (0/10)")
    else:
         feedback_parts.append("Report contains no valid number (0/10)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }