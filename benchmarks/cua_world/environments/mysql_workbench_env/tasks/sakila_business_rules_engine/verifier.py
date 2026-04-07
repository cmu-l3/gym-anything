#!/usr/bin/env python3
"""
Verifier for sakila_business_rules_engine task.

Scoring Criteria:
1. Four Stored Functions Existence (10 pts each) -> 40 pts
2. Function Logic Correctness (checked via SQL calls in export script) -> 20 pts
3. View Existence and Schema -> 15 pts
4. Table Materialization (correct row count) -> 10 pts
5. CSV Export (exists, created during task, valid content) -> 15 pts

Total: 100 pts
Pass Threshold: 60 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_business_rules_engine(traj, env_info, task_info):
    """
    Verify the implementation of Sakila business rules.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Functions Existence (40 pts)
    fns = [
        ('fn_rental_late_days', result.get('fn_rental_late_days_exists', 0)),
        ('fn_late_fee', result.get('fn_late_fee_exists', 0)),
        ('fn_customer_tier', result.get('fn_customer_tier_exists', 0)),
        ('fn_film_popularity', result.get('fn_film_popularity_exists', 0))
    ]
    
    fn_score = 0
    for name, exists in fns:
        if exists:
            fn_score += 10
    
    score += fn_score
    if fn_score == 40:
        feedback_parts.append("All stored functions created (40/40)")
    else:
        feedback_parts.append(f"Stored functions incomplete ({fn_score}/40)")

    # 2. Verify Logic (20 pts)
    logic = result.get('logic_check', {})
    logic_score = 0
    
    # Tier logic
    if logic.get('tier_gold') == 'GOLD': logic_score += 4
    if logic.get('tier_silver') == 'SILVER': logic_score += 4
    if logic.get('tier_bronze') == 'BRONZE': logic_score += 4
    
    # Late fee logic
    # Rental 1185 is 3 days late. Fee should be 4.50
    try:
        days = float(logic.get('late_days_1185', 0))
        fee = float(logic.get('late_fee_1185', 0))
        
        if abs(days - 3.0) < 0.1: logic_score += 4
        if abs(fee - 4.50) < 0.1: logic_score += 4
    except ValueError:
        pass

    score += logic_score
    feedback_parts.append(f"Business logic verification ({logic_score}/20)")

    # 3. Verify View (15 pts)
    view_score = 0
    if result.get('view_exists', 0):
        view_score += 5
        cols = result.get('view_columns', '').lower()
        required_cols = ['customer_id', 'tier', 'total_rentals', 'total_payments', 'total_late_fees']
        if all(c in cols for c in required_cols):
            view_score += 10
            feedback_parts.append("View created with correct columns (15/15)")
        else:
            feedback_parts.append("View created but missing columns (5/15)")
    else:
        feedback_parts.append("View not created (0/15)")
    score += view_score

    # 4. Verify Table Materialization (10 pts)
    table_score = 0
    row_count = int(result.get('table_row_count', 0))
    expected_count = int(result.get('expected_row_count', 584))
    
    # Allow small tolerance
    if result.get('table_exists', 0):
        if abs(row_count - expected_count) <= 5:
            table_score += 10
            feedback_parts.append(f"Table created with {row_count} active customers (10/10)")
        else:
            table_score += 5
            feedback_parts.append(f"Table created but row count mismatch (Found {row_count}, Expected ~{expected_count}) (5/10)")
    else:
        feedback_parts.append("Table not created (0/10)")
    score += table_score

    # 5. Verify CSV Export (15 pts)
    csv_score = 0
    if result.get('csv_exists'):
        # Anti-gaming: Created during task
        task_start = int(result.get('task_start_time', 0))
        csv_mtime = int(result.get('csv_mtime', 0))
        
        if csv_mtime > task_start:
            # Check content size
            if result.get('csv_lines', 0) > 500:
                csv_score += 15
                feedback_parts.append("CSV exported successfully (15/15)")
            else:
                csv_score += 10
                feedback_parts.append("CSV exported but seems too short (10/15)")
        else:
            feedback_parts.append("CSV file exists but is old (0/15)")
    else:
        feedback_parts.append("CSV file not found (0/15)")
    score += csv_score

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }