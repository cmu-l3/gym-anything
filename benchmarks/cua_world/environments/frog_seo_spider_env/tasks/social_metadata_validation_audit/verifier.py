#!/usr/bin/env python3
"""
Verifier for Social Metadata Audit task.

Scoring (100 points total):
- Screaming Frog running/used (10 pts)
- CSV export exists and was created during task (10 pts)
- CSV has correct target domain URLs (10 pts)
- Custom Extraction columns detected (30 pts)
- Valid extracted data found (e.g. non-empty values in custom cols) (30 pts)
- Report file exists and has content (10 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_social_metadata_audit(traj, env_info, task_info):
    """Verify social metadata audit task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback_parts = []

    # Get result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 1. Application Usage (10 pts)
    if result.get('sf_running', False) or result.get('csv_created_during_task', False):
        score += 10
        feedback_parts.append("Screaming Frog used")

    # 2. CSV Export Existence (10 pts)
    if result.get('csv_exists', False) and result.get('csv_created_during_task', False):
        score += 10
        feedback_parts.append("CSV export created")
    else:
        feedback_parts.append("CSV export missing/old")

    # 3. Domain Check (10 pts)
    if result.get('has_target_domain', False):
        score += 10
        feedback_parts.append("Target domain found in CSV")
    else:
        feedback_parts.append("Target domain missing in CSV")

    # 4. Custom Extraction Columns (30 pts)
    # The export script attempts to identify columns that look like "og" or "custom"
    # or just non-standard columns with data
    has_og_cols = result.get('has_og_cols', False)
    has_extracted = result.get('has_extracted_values', False)
    
    if has_og_cols:
        score += 30
        feedback_parts.append("Custom extraction columns detected")
    elif has_extracted:
        # Maybe named something weird but has data
        score += 20
        feedback_parts.append("Extracted data found (columns inferred)")
    else:
        feedback_parts.append("No custom extraction columns detected")

    # 5. Data Validation (30 pts)
    # Strictly checks if we actually got values out
    if has_extracted:
        score += 30
        feedback_parts.append("Extracted values verified")
    else:
        feedback_parts.append("No extracted values found (empty columns?)")

    # 6. Report Existence (10 pts)
    if result.get('report_exists', False) and result.get('report_content_length', 0) > 50:
        score += 10
        feedback_parts.append("Report created")
    else:
        feedback_parts.append("Report missing/empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }