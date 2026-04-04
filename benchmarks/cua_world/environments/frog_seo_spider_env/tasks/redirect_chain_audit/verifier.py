#!/usr/bin/env python3
"""Verifier for Redirect Chain Audit task.

Scoring (100 points total):
- SF ran and crawled crawler-test.com (15 pts)
- Redirect CSV found with 3xx status codes (25 pts)
  - Has Status Code column (10 pts)
  - Has Redirect URL column (10 pts)
  - Has actual 3xx data rows (5 pts)
- CSV has ≥3 redirect rows from target domain (20 pts)
  - Partial: ≥1 row (10 pts)
  - Full: ≥3 rows with domain confirmed (20 pts)
- Written redirect report exists with meaningful content (25 pts)
  - Report exists with ≥200 bytes (10 pts)
  - Report has numeric counts (8 pts)
  - Report mentions specific redirect types (7 pts)
- Bonus: Both 301 and 302 types identified (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_redirect_chain_audit(traj, env_info, task_info):
    """Verify redirect chain audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/redirect_chain_audit_result.json', tmp.name)
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

    # --- Criterion 1: SF ran (15 pts) ---
    sf_ran = result.get('sf_running', False)
    has_new_csv = result.get('new_csv_count', 0) > 0
    if sf_ran or has_new_csv:
        score += 15
        feedback_parts.append("SF ran (15/15)")
    else:
        feedback_parts.append("SF not confirmed running (0/15)")

    # --- Criterion 2: Redirect CSV with proper structure (25 pts) ---
    csv_found = result.get('redirect_csv_found', False)
    has_status_col = result.get('has_status_code_column', False)
    has_redirect_col = result.get('has_redirect_url_column', False)
    has_3xx = result.get('has_3xx_data', False)

    csv_score = 0
    if csv_found:
        if has_status_col:
            csv_score += 10
        if has_redirect_col:
            csv_score += 10
        if has_3xx:
            csv_score += 5
    score += csv_score

    if csv_found:
        feedback_parts.append(
            f"Redirect CSV found: status_col={has_status_col}, "
            f"redirect_col={has_redirect_col}, 3xx_data={has_3xx} ({csv_score}/25)"
        )
    else:
        feedback_parts.append(f"No redirect CSV found (0/25)")

    # --- Criterion 3: Redirect rows from target domain (20 pts) ---
    row_count = result.get('redirect_row_count', 0)
    domain_confirmed = result.get('target_domain_in_csv', False)

    if row_count >= 3 and domain_confirmed:
        score += 20
        feedback_parts.append(f"Redirect data: {row_count} rows, domain confirmed (20/20)")
    elif row_count >= 1 and domain_confirmed:
        score += 10
        feedback_parts.append(f"Redirect data: only {row_count} rows but domain confirmed (10/20)")
    elif row_count >= 3:
        score += 10
        feedback_parts.append(f"Redirect data: {row_count} rows but domain not confirmed (10/20)")
    elif row_count >= 1:
        score += 5
        feedback_parts.append(f"Redirect data: only {row_count} rows, domain not confirmed (5/20)")
    else:
        feedback_parts.append(f"No 3xx redirect rows in CSV (0/20)")

    # --- Criterion 4: Written report with meaningful content (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_has_counts = result.get('report_has_counts', False)
    report_has_types = result.get('report_has_redirect_types', False)

    report_score = 0
    if report_exists and report_size >= 200:
        report_score += 10
    elif report_exists and report_size > 0:
        report_score += 5
    if report_has_counts:
        report_score += 8
    if report_has_types:
        report_score += 7
    score += report_score

    if report_exists:
        feedback_parts.append(
            f"Report exists ({report_size} bytes), "
            f"counts={report_has_counts}, types={report_has_types} ({report_score}/25)"
        )
    else:
        feedback_parts.append("Written redirect report not found at ~/Documents/SEO/reports/redirect_report.txt (0/25)")

    # --- Criterion 5: Both 301 and 302 identified (15 pts) ---
    has_301 = result.get('has_301', False)
    has_302 = result.get('has_302', False)
    if has_301 and has_302:
        score += 15
        feedback_parts.append("Both 301 and 302 redirect types identified (15/15)")
    elif has_301 or has_302:
        score += 7
        feedback_parts.append(f"Only one redirect type identified: 301={has_301}, 302={has_302} (7/15)")
    else:
        feedback_parts.append("No specific redirect types identified in CSV (0/15)")

    # GATE: Both deliverables (CSV + written report) are required to pass.
    # If the written report is missing, cap score to prevent passing on CSV alone.
    report_exists = result.get('report_exists', False)
    if not report_exists and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50: written report is a required deliverable (redirect_report.txt)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "sf_ran": sf_ran or has_new_csv,
            "csv_found": csv_found,
            "has_3xx_data": has_3xx,
            "row_count": row_count,
            "domain_confirmed": domain_confirmed,
            "report_exists": report_exists,
        }
    }
