#!/usr/bin/env python3
"""Verifier for Regex Extraction Product IDs task.

Scoring (100 points total):
- CSV file exists in exports directory (10 pts)
- CSV contains books.toscrape.com URLs (15 pts)
- UPC column present with hex values (25 pts)
- ≥15 rows with data (20 pts)
- Review count data present (20 pts)
- Data freshness (10 pts)

Pass Threshold: 60 points with critical data (UPC)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_regex_extraction_product_ids(traj, env_info, task_info):
    """Verify regex extraction task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r', encoding='utf-8') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # Criterion 1: CSV exists (10 pts)
    # The export script logic already filters for files created after task start, 
    # so existence implies freshness to some degree, but we score explicitly.
    csv_found = result.get('csv_found', False)
    if csv_found:
        score += 10
        feedback_parts.append("CSV export found (10/10)")
    else:
        feedback_parts.append("No valid CSV export found (0/10)")
        return {"passed": False, "score": 0, "feedback": "No CSV file found in output directory", "details": result}

    # Criterion 6: Data freshness (10 pts) - Implicitly checked by export script logic
    # If csv_found is true, it means a file NEWER than task start was found.
    score += 10 
    feedback_parts.append("File created during task (10/10)")

    # Criterion 2: Target Domain (15 pts)
    has_domain = result.get('has_target_domain', False)
    if has_domain:
        score += 15
        feedback_parts.append("Target domain URLs found (15/15)")
    else:
        feedback_parts.append("Target domain NOT found in CSV (0/15)")

    # Criterion 3: UPC Data (25 pts)
    has_upc = result.get('has_upc_data', False)
    if has_upc:
        score += 25
        feedback_parts.append("Extracted UPC data (hex) found (25/25)")
    else:
        feedback_parts.append("UPC data patterns not found (0/25)")

    # Criterion 4: Review Data (20 pts)
    has_review = result.get('has_review_data', False)
    if has_review:
        score += 20
        feedback_parts.append("Extracted Review count data found (20/20)")
    else:
        feedback_parts.append("Review count data patterns not found (0/20)")

    # Criterion 5: Row Count (20 pts)
    row_count = result.get('row_count', 0)
    expected_rows = 15
    if row_count >= expected_rows:
        score += 20
        feedback_parts.append(f"Sufficient row count: {row_count} (20/20)")
    elif row_count > 0:
        partial = int(20 * (row_count / expected_rows))
        score += partial
        feedback_parts.append(f"Partial row count: {row_count} ({partial}/20)")
    else:
        feedback_parts.append("Empty or header-only CSV (0/20)")

    # Final Pass check
    # Must have CSV + Domain + UPC data to pass
    passed = csv_found and has_domain and has_upc and (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }