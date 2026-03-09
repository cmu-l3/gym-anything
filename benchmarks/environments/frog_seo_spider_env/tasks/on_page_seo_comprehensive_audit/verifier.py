#!/usr/bin/env python3
"""Verifier for On-Page SEO Comprehensive Audit task.

Scoring (100 points total):
- SF ran and produced new exports (15 pts)
- Page titles export found with Title 1 column (15 pts)
- Meta descriptions export found with Meta Description 1 column (15 pts)
- H1 tags export found with H1-1 column (15 pts)
  Note: a single comprehensive internal export covering all three counts for all criteria
- Sufficient pages crawled (≥100 rows) from target domain (20 pts)
  - ≥50 rows: 10 pts
  - ≥100 rows + domain confirmed: 20 pts
- Written audit summary with multiple categories (20 pts)
  - Exists ≥200 bytes: 8 pts
  - Has numeric counts: 6 pts
  - Covers ≥2 issue categories (titles/meta/H1): 6 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_on_page_seo_comprehensive_audit(traj, env_info, task_info):
    """Verify on-page SEO comprehensive audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/on_page_seo_comprehensive_audit_result.json', tmp.name)
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

    # --- Criterion 2: Page titles export (15 pts) ---
    titles_found = result.get('titles_csv_found', False)
    has_title_col = result.get('has_title_column', False)
    if titles_found and has_title_col:
        score += 15
        feedback_parts.append("Page titles export found with Title 1 column (15/15)")
    elif titles_found:
        score += 7
        feedback_parts.append("Page titles export found but Title 1 column not confirmed (7/15)")
    else:
        feedback_parts.append("No page titles export found (0/15)")

    # --- Criterion 3: Meta descriptions export (15 pts) ---
    meta_found = result.get('meta_csv_found', False)
    has_meta_col = result.get('has_meta_column', False)
    if meta_found and has_meta_col:
        score += 15
        feedback_parts.append("Meta descriptions export found (15/15)")
    elif meta_found:
        score += 7
        feedback_parts.append("Meta descriptions export found but column not confirmed (7/15)")
    else:
        feedback_parts.append("No meta descriptions export found (0/15)")

    # --- Criterion 4: H1 tags export (15 pts) ---
    h1_found = result.get('h1_csv_found', False)
    has_h1_col = result.get('has_h1_column', False)
    if h1_found and has_h1_col:
        score += 15
        feedback_parts.append("H1 tags export found (15/15)")
    elif h1_found:
        score += 7
        feedback_parts.append("H1 export found but H1-1 column not confirmed (7/15)")
    else:
        feedback_parts.append("No H1 tags export found (0/15)")

    # --- Criterion 5: Pages crawled (≥100 from target domain) (20 pts) ---
    max_rows = result.get('max_row_count', 0)
    comprehensive_rows = result.get('comprehensive_row_count', 0)
    titles_rows = result.get('titles_row_count', 0)
    domain_confirmed = result.get('target_domain_in_csv', False)
    # Best row count across all exports
    best_rows = max(max_rows, comprehensive_rows, titles_rows)

    if best_rows >= 100 and domain_confirmed:
        score += 20
        feedback_parts.append(f"≥100 pages crawled from books.toscrape.com ({best_rows} rows) (20/20)")
    elif best_rows >= 50 and domain_confirmed:
        score += 10
        feedback_parts.append(f"Only {best_rows} pages in exports but domain confirmed (10/20)")
    elif best_rows >= 50:
        score += 7
        feedback_parts.append(f"{best_rows} rows found but domain not confirmed (7/20)")
    elif best_rows >= 10:
        score += 4
        feedback_parts.append(f"Only {best_rows} rows in exports — need ≥100 pages (4/20)")
    else:
        feedback_parts.append(f"Insufficient pages: only {best_rows} rows found (0/20)")

    # --- Criterion 6: Written audit summary (20 pts) ---
    report_exists = result.get('report_exists', False)
    report_size = result.get('report_size_bytes', 0)
    report_counts = result.get('report_has_counts', False)
    report_multi = result.get('report_has_multiple_categories', False)

    report_score = 0
    if report_exists and report_size >= 200:
        report_score += 8
    elif report_exists and report_size > 0:
        report_score += 4
    if report_counts:
        report_score += 6
    if report_multi:
        report_score += 6
    score += report_score

    if report_exists:
        feedback_parts.append(
            f"Audit summary exists ({report_size} bytes), "
            f"has_counts={report_counts}, multi_categories={report_multi} ({report_score}/20)"
        )
    else:
        feedback_parts.append("Written audit summary not found at ~/Documents/SEO/reports/on_page_audit.txt (0/20)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "sf_ran": sf_ran or new_csv_count > 0,
            "titles_found": titles_found,
            "meta_found": meta_found,
            "h1_found": h1_found,
            "best_row_count": best_rows,
            "domain_confirmed": domain_confirmed,
            "report_exists": report_exists,
        }
    }
