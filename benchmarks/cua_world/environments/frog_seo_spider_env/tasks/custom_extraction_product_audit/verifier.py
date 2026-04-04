#!/usr/bin/env python3
"""Verifier for Custom Extraction Product Audit task.

Scoring (100 points total):
- Screaming Frog ran and crawled target domain (15 pts)
- Custom extraction CSV exists modified after task start (20 pts)
- Custom extraction CSV has price OR rating data with ≥20 rows (30 pts)
  - Partial: ≥10 rows (15 pts)
  - Full: ≥20 rows AND has extracted values (30 pts)
- Target domain (books.toscrape.com) confirmed in exports (20 pts)
- Internal HTML report also exported (15 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_custom_extraction_product_audit(traj, env_info, task_info):
    """Verify custom extraction product audit task completion."""
    copy_from_env = env_info.get('copy_from_env') or env_info.get('exec_capture')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/custom_extraction_product_audit_result.json', tmp.name)
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

    # --- Criterion 1: SF ran and crawled target domain (15 pts) ---
    sf_ran = result.get('sf_running', False) or result.get('window_has_target_domain', False)
    if sf_ran:
        score += 15
        feedback_parts.append("SF ran (15/15)")
    else:
        feedback_parts.append("SF not confirmed running (0/15)")

    # --- Criterion 2: Custom extraction CSV found (20 pts) ---
    custom_found = result.get('custom_csv_found', False)
    if custom_found:
        score += 20
        feedback_parts.append("Custom extraction CSV found (20/20)")
    else:
        feedback_parts.append("No custom extraction CSV found (0/20)")
        # Also check if there were any new CSVs at all
        new_csv_count = result.get('new_csv_count', 0)
        if new_csv_count > 0:
            feedback_parts.append(f"({new_csv_count} CSV(s) found but none identified as custom extraction)")

    # --- Criterion 3: Custom extraction has valid data with min rows (30 pts) ---
    has_price = result.get('custom_has_price_data', False)
    has_rating = result.get('custom_has_rating_data', False)
    row_count = result.get('custom_row_count', 0)

    if custom_found and (has_price or has_rating):
        if row_count >= 20:
            score += 30
            feedback_parts.append(f"Custom extraction has extracted data, {row_count} rows (30/30)")
        elif row_count >= 10:
            score += 15
            feedback_parts.append(f"Custom extraction has extracted data but only {row_count} rows (15/30)")
        else:
            score += 5
            feedback_parts.append(f"Custom extraction has extracted data but very few rows: {row_count} (5/30)")
    elif custom_found and row_count >= 20:
        # Has rows but extraction columns not identified by content — partial credit
        score += 15
        feedback_parts.append(f"Custom extraction CSV has {row_count} rows but extracted values not confirmed (15/30)")
    else:
        feedback_parts.append(f"Custom extraction: no extracted price/rating data found (0/30)")

    # --- Criterion 4: Target domain confirmed in exports (20 pts) ---
    domain_found = result.get('target_domain_found', False)
    if domain_found:
        score += 20
        feedback_parts.append("books.toscrape.com URLs confirmed in exports (20/20)")
    else:
        feedback_parts.append("Target domain not confirmed in exports (0/20)")

    # --- Criterion 5: Internal HTML report also exported (15 pts) ---
    internal_found = result.get('internal_csv_found', False)
    internal_rows = result.get('internal_row_count', 0)
    if internal_found and internal_rows >= 5:
        score += 15
        feedback_parts.append(f"Internal HTML report exported with {internal_rows} rows (15/15)")
    elif internal_found:
        score += 7
        feedback_parts.append(f"Internal HTML report found but only {internal_rows} rows (7/15)")
    else:
        feedback_parts.append("Internal HTML report not found (0/15)")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "sf_ran": sf_ran,
            "custom_csv_found": custom_found,
            "has_extracted_data": has_price or has_rating,
            "row_count": row_count,
            "domain_confirmed": domain_found,
            "internal_csv_found": internal_found,
        }
    }
