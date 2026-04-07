#!/usr/bin/env python3
"""
Verifier for Data Pump Schema Repair task.

Scoring Criteria:
1. Schema HR_APP exists (10 pts)
2. REGIONS table does NOT exist in HR_APP (15 pts)
3. EMPLOYEES data migrated (count > 100) (15 pts)
4. Primary Keys preserved (indicates proper metadata export/import, not just CTAS) (20 pts)
5. EMP_DETAILS_VIEW exists (10 pts)
6. EMP_DETAILS_VIEW is VALID (20 pts)
7. View column modification verified (no region_name) (10 pts)

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_datapump_repair(traj, env_info, task_info):
    """
    Verifies that the HR schema was cloned via Data Pump (excluding REGIONS)
    and the broken view was fixed.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available"
        }

    # Copy result JSON
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "datapump_repair_result.json")
        try:
            copy_from_env("/tmp/datapump_repair_result.json", result_path)
        except Exception as e:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": f"Could not retrieve result file: {e}"
            }

        if not os.path.exists(result_path):
            return {
                "score": 0.0,
                "passed": False,
                "feedback": "Result file not found."
            }

        try:
            with open(result_path, "r") as f:
                result = json.load(f)
        except json.JSONDecodeError:
            return {
                "score": 0.0,
                "passed": False,
                "feedback": "Result JSON is malformed."
            }

    score = 0
    feedback_parts = []
    
    if result.get("db_error"):
        return {
            "score": 0,
            "passed": False,
            "feedback": f"Database check failed: {result['db_error']}"
        }

    # 1. Schema Existence (10 pts)
    if result.get("hr_app_exists"):
        score += 10
        feedback_parts.append("HR_APP schema created (+10)")
    else:
        feedback_parts.append("HR_APP schema NOT found (0 pts)")
        return {
            "score": score,
            "passed": False,
            "feedback": " | ".join(feedback_parts)
        }

    # 2. Table Exclusion (15 pts)
    if not result.get("regions_table_exists"):
        score += 15
        feedback_parts.append("REGIONS table successfully excluded (+15)")
    else:
        feedback_parts.append("REGIONS table found (exclusion failed) (0 pts)")

    # 3. Data Migration (15 pts)
    count = result.get("employees_row_count", 0)
    if count >= 100:
        score += 15
        feedback_parts.append(f"Employee data migrated ({count} rows) (+15)")
    else:
        feedback_parts.append(f"Data migration failed or incomplete ({count} rows) (0 pts)")

    # 4. Metadata/PK Preservation (20 pts)
    # This distinguishes Data Pump from simple 'CREATE TABLE AS SELECT'
    if result.get("pk_exists_on_employees"):
        score += 20
        feedback_parts.append("Primary Keys preserved (metadata valid) (+20)")
    else:
        feedback_parts.append("Primary Keys missing (likely used CTAS instead of Data Pump) (0 pts)")

    # 5. View Existence (10 pts)
    if result.get("view_exists"):
        score += 10
        feedback_parts.append("EMP_DETAILS_VIEW exists (+10)")
    else:
        feedback_parts.append("EMP_DETAILS_VIEW missing (0 pts)")

    # 6. View Validity (20 pts)
    view_status = result.get("view_status", "UNKNOWN")
    if view_status == "VALID":
        score += 20
        feedback_parts.append("EMP_DETAILS_VIEW is VALID (+20)")
    else:
        feedback_parts.append(f"EMP_DETAILS_VIEW is {view_status} (expected VALID) (0 pts)")

    # 7. View Content Check (10 pts)
    # The view should NOT have the region column anymore
    if not result.get("view_has_region_column", True):
        score += 10
        feedback_parts.append("View definition corrected (dependency removed) (+10)")
    else:
        # If the view is valid BUT still has the column, they might have created a fake table or something weird
        if view_status == "VALID":
             feedback_parts.append("View still contains REGION column but is VALID? (Suspicious) (0 pts)")
        else:
             feedback_parts.append("View modification incorrect (0 pts)")

    # Bonus: Check logs for "EXCLUDE" keyword to be sure
    log_content = result.get("log_content_preview", "").upper()
    if "EXCLUDE" in log_content or "REGIONS" in log_content:
        # Just a sanity check/confirmation, no extra points but good for debugging
        pass

    passed = score >= 70
    
    return {
        "score": score,
        "passed": passed,
        "feedback": " | ".join(feedback_parts)
    }