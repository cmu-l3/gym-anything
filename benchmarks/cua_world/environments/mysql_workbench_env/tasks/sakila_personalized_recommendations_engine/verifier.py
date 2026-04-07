#!/usr/bin/env python3
"""
Verifier for Sakila Personalized Recommendations Engine task.

Verifies:
1. Database Objects (Table, Procedure)
2. Logic Correctness (Row counts, constraints, logic checks)
3. Output Artifacts (CSV Export)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_personalized_recommendations(traj, env_info, task_info):
    """
    Verify the recommendation engine implementation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Database Objects (20 points)
    # ---------------------------------------------------------
    if result.get('table_exists', 0) == 1:
        score += 10
        feedback_parts.append("Table 'customer_recommendations' created (10/10)")
    else:
        feedback_parts.append("Table 'customer_recommendations' MISSING (0/10)")

    if result.get('proc_exists', 0) == 1:
        score += 10
        feedback_parts.append("Procedure 'sp_generate_recommendations' created (10/10)")
    else:
        feedback_parts.append("Procedure 'sp_generate_recommendations' MISSING (0/10)")

    # ---------------------------------------------------------
    # Criterion 2: Data Population (20 points)
    # ---------------------------------------------------------
    # Expect roughly 599 customers * 3 recs = 1797 rows.
    row_count = result.get('row_count', 0)
    expected_rows = 1797
    # Allow small tolerance if some customers have < 3 valid recs (rare but possible)
    if 1750 <= row_count <= 1850:
        score += 20
        feedback_parts.append(f"Data populated correctly: {row_count} rows (20/20)")
    elif row_count > 0:
        score += 5
        feedback_parts.append(f"Data populated but row count suspicious: {row_count} (expected ~1797) (5/20)")
    else:
        feedback_parts.append("Table is empty (0/20)")

    # ---------------------------------------------------------
    # Criterion 3: Unseen Constraint Check (20 points)
    # ---------------------------------------------------------
    # Violations = number of recommended films that the user had ALREADY seen.
    # Should be 0.
    violations = result.get('unseen_violations', 9999)
    if violations == 0 and row_count > 0:
        score += 20
        feedback_parts.append("Constraint Verified: No previously rented films recommended (20/20)")
    elif violations > 0:
        feedback_parts.append(f"Logic Error: Found {violations} recommendations for films users had already seen (0/20)")
    else:
        # If row count is 0, this check is trivially passed but meaningless, don't award points
        feedback_parts.append("Cannot verify constraints (no data) (0/20)")

    # ---------------------------------------------------------
    # Criterion 4: Favorite Category Logic (20 points)
    # ---------------------------------------------------------
    # We checked one sample customer (Mary Smith).
    # If she has 3 recommendations, and all 3 match her calculated top category.
    mary_matches = result.get('mary_matching_recs', 0)
    if mary_matches == 3:
        score += 20
        feedback_parts.append("Category Logic Verified: Recommendations match top genre (20/20)")
    elif mary_matches > 0:
        score += 10
        feedback_parts.append(f"Category Logic Partial: Only {mary_matches}/3 recommendations matched top genre (10/20)")
    else:
        # Only penalize if there was data to check
        if row_count > 0:
            feedback_parts.append("Category Logic Failed: Recommendations do not match top genre (0/20)")
        else:
            feedback_parts.append("Cannot verify category logic (no data) (0/20)")

    # ---------------------------------------------------------
    # Criterion 5: CSV Export (20 points)
    # ---------------------------------------------------------
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    task_start = result.get('task_start_time', 0)
    csv_mtime = result.get('csv_mtime', 0)

    # Check if created during task
    created_during_task = csv_mtime > task_start

    if csv_exists and created_during_task and csv_rows >= 1700:
        score += 20
        feedback_parts.append("Valid CSV export found (20/20)")
    elif csv_exists and csv_rows > 0:
        score += 10
        feedback_parts.append("CSV exists but low row count or old timestamp (10/20)")
    else:
        feedback_parts.append("CSV export missing or empty (0/20)")

    # Final Pass Determination
    # Must have the table, the procedure, and passed the constraints to be considered "working"
    passed = (score >= 60) and (result.get('unseen_violations', 999) == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }