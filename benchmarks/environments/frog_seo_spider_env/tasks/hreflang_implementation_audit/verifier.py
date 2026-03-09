#!/usr/bin/env python3
"""Verifier for Hreflang Implementation Audit task.

Scoring (100 points total):
- SF ran and produced new exports (15 pts)
- Hreflang CSV found (20 pts)
  - Has Language column (10 pts)
  - Has language code values (10 pts)
- CSV has ≥5 rows with target domain (25 pts)
  - Partial: ≥2 rows (12 pts)
  - Full: ≥5 rows + domain confirmed (25 pts)
- Written report exists with meaningful content (25 pts)
  - Report exists ≥200 bytes (10 pts)
  - Report mentions language codes (8 pts)
  - Report mentions error types (7 pts)
- Multiple language codes in CSV (15 pts)
  - 1 code: 5 pts
  - 2+ codes: 10 pts
  - 3+ codes (en/de/fr or x-default): 15 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_hreflang_implementation_audit(traj, env_info, task_info):
    """Verify hreflang implementation audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/hreflang_implementation_audit_result.json', tmp.name)
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
    new_csv_count = result.get('new_csv_count', 0)
    if sf_ran or new_csv_count > 0:
        score += 15
        feedback_parts.append("SF ran (15/15)")
    else:
        feedback_parts.append("SF not confirmed running (0/15)")

    # --- Criterion 2: Hreflang CSV found with structure (20 pts) ---
    csv_found = result.get('hreflang_csv_found', False)
    has_lang_col = result.get('has_language_column', False)
    has_lang_codes = result.get('has_language_codes', False)

    csv_score = 0
    if csv_found:
        if has_lang_col:
            csv_score += 10
        if has_lang_codes:
            csv_score += 10
    score += csv_score

    if csv_found:
        feedback_parts.append(
            f"Hreflang CSV found: lang_col={has_lang_col}, lang_codes={has_lang_codes} ({csv_score}/20)"
        )
    else:
        feedback_parts.append("No hreflang CSV found (0/20)")

    # --- Criterion 3: CSV rows with domain (25 pts) ---
    row_count = result.get('hreflang_row_count', 0)
    domain_confirmed = result.get('target_domain_in_csv', False)

    if row_count >= 5 and domain_confirmed:
        score += 25
        feedback_parts.append(f"Hreflang data: {row_count} rows, domain confirmed (25/25)")
    elif row_count >= 5:
        score += 12
        feedback_parts.append(f"Hreflang data: {row_count} rows but domain not confirmed (12/25)")
    elif row_count >= 2 and domain_confirmed:
        score += 12
        feedback_parts.append(f"Hreflang data: only {row_count} rows, domain confirmed (12/25)")
    elif row_count >= 2:
        score += 6
        feedback_parts.append(f"Hreflang data: only {row_count} rows, domain not confirmed (6/25)")
    else:
        feedback_parts.append(f"Insufficient hreflang rows: {row_count} (0/25)")

    # --- Criterion 4: Written report (25 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_lang = result.get('report_has_language_codes', False)
    report_errors = result.get('report_has_error_types', False)

    report_score = 0
    if report_exists and report_size >= 200:
        report_score += 10
    elif report_exists and report_size > 0:
        report_score += 5
    if report_lang:
        report_score += 8
    if report_errors:
        report_score += 7
    score += report_score

    if report_exists:
        feedback_parts.append(
            f"Report exists ({report_size} bytes), "
            f"lang_codes={report_lang}, error_types={report_errors} ({report_score}/25)"
        )
    else:
        feedback_parts.append("Written hreflang report not found at ~/Documents/SEO/reports/hreflang_report.txt (0/25)")

    # --- Criterion 5: Multiple language codes in CSV (15 pts) ---
    unique_langs_str = result.get('unique_languages_found', '')
    lang_list = [l for l in unique_langs_str.split() if l] if unique_langs_str else []
    unique_count = len(lang_list)

    if unique_count >= 3:
        score += 15
        feedback_parts.append(f"Found {unique_count} unique language codes: {' '.join(lang_list[:5])} (15/15)")
    elif unique_count >= 2:
        score += 10
        feedback_parts.append(f"Found {unique_count} unique language codes (10/15)")
    elif unique_count >= 1:
        score += 5
        feedback_parts.append(f"Found only {unique_count} language code (5/15)")
    else:
        feedback_parts.append("No unique language codes extracted from CSV (0/15)")

    # GATE: Both deliverables (CSV + written report) are required to pass.
    # If the written report is missing, cap score to prevent passing on CSV alone.
    if not report_exists and score > 50:
        score = 50
        feedback_parts.append("Score capped at 50: written report is a required deliverable (hreflang_report.txt)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "sf_ran": sf_ran or new_csv_count > 0,
            "csv_found": csv_found,
            "has_lang_codes": has_lang_codes,
            "row_count": row_count,
            "domain_confirmed": domain_confirmed,
            "report_exists": report_exists,
            "unique_lang_count": unique_count,
        }
    }
