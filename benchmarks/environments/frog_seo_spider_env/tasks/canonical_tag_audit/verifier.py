#!/usr/bin/env python3
"""Verifier for Canonical Tag Audit task.

Scoring (100 points total):
- SF ran and produced new exports (15 pts)
- Canonical CSV found with correct structure (25 pts)
  - Has Canonical Link Element column (10 pts)
  - Has actual canonical URLs in data (10 pts)
  - Has Type or Self Referencing column (5 pts)
- CSV rows with target domain data (20 pts)
  - ≥10 rows + domain confirmed: 20 pts
  - ≥5 rows: 10 pts
  - ≥1 row: 5 pts
- Written report with canonical-specific analysis (25 pts)
  - Report exists ≥200 bytes (10 pts)
  - Report has numeric counts (8 pts)
  - Report uses canonical terminology (7 pts)
- SF crawl confirmed for crawler-test.com (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_canonical_tag_audit(traj, env_info, task_info):
    """Verify canonical tag audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/canonical_tag_audit_result.json', tmp.name)
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
    new_csv = result.get('new_csv_count', 0)
    domain_confirmed = result.get('target_domain_in_csv', False)

    if sf_ran or new_csv > 0:
        score += 15
        feedback_parts.append("SF ran (15/15)")
    else:
        feedback_parts.append("SF not confirmed running (0/15)")

    # --- Criterion 2: Canonical CSV with structure (25 pts) ---
    csv_found = result.get('canonical_csv_found', False)
    has_canon_col = result.get('has_canonical_column', False)
    has_actual_urls = result.get('has_actual_canonical_urls', False)
    has_type_col = result.get('has_type_column', False)
    has_self_ref = result.get('has_self_referencing_column', False)

    csv_score = 0
    if csv_found:
        if has_canon_col:
            csv_score += 10
        if has_actual_urls:
            csv_score += 10
        if has_type_col or has_self_ref:
            csv_score += 5
    score += csv_score

    if csv_found:
        feedback_parts.append(
            f"Canonical CSV found: canon_col={has_canon_col}, "
            f"urls={has_actual_urls}, type_cols={has_type_col or has_self_ref} ({csv_score}/25)"
        )
    else:
        feedback_parts.append("No canonical CSV found in ~/Documents/SEO/exports/ (0/25)")

    # --- Criterion 3: Sufficient rows with domain (20 pts) ---
    row_count = result.get('canonical_row_count', 0)

    if row_count >= 10 and domain_confirmed:
        score += 20
        feedback_parts.append(f"Canonical data: {row_count} rows, domain confirmed (20/20)")
    elif row_count >= 10:
        score += 10
        feedback_parts.append(f"Canonical data: {row_count} rows, domain not confirmed (10/20)")
    elif row_count >= 5 and domain_confirmed:
        score += 10
        feedback_parts.append(f"Canonical data: {row_count} rows, domain confirmed (10/20)")
    elif row_count >= 1:
        score += 5
        feedback_parts.append(f"Canonical data: only {row_count} rows (5/20)")
    else:
        feedback_parts.append("No canonical data rows found (0/20)")

    # --- Criterion 4: Written report (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_counts = result.get('report_has_counts', False)
    report_terms = result.get('report_has_canonical_terms', False)

    report_score = 0
    if report_exists and report_size >= 200:
        report_score += 10
    elif report_exists and report_size > 0:
        report_score += 5
    if report_counts:
        report_score += 8
    if report_terms:
        report_score += 7
    score += report_score

    if report_exists:
        feedback_parts.append(
            f"Report exists ({report_size} bytes), "
            f"counts={report_counts}, terms={report_terms} ({report_score}/25)"
        )
    else:
        feedback_parts.append("Written canonical report not found at ~/Documents/SEO/reports/canonical_report.txt (0/25)")

    # --- Criterion 5: Confirmed target domain crawled (15 pts) ---
    if domain_confirmed:
        score += 15
        feedback_parts.append("crawler-test.com domain confirmed in exports (15/15)")
    else:
        feedback_parts.append("Target domain not confirmed in exports (0/15)")

    # GATE: Both deliverables (CSV + written report) are required to pass.
    # If the written report is missing, cap score to prevent passing on CSV alone.
    if not report_exists and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50: written report is a required deliverable (canonical_report.txt)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "sf_ran": sf_ran or new_csv > 0,
            "csv_found": csv_found,
            "has_canonical_col": has_canon_col,
            "has_canonical_urls": has_actual_urls,
            "row_count": row_count,
            "domain_confirmed": domain_confirmed,
            "report_exists": report_exists,
        }
    }
