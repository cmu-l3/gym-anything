#!/usr/bin/env python3
"""
Verifier for sakila_data_integrity_constraints task.

Scoring Breakdown (100 pts total):
1. Data Repair (30 pts):
   - Bad rental_duration fixed: 15 pts
   - Bad payment amount fixed: 15 pts
2. Constraints Enforced (30 pts):
   - chk_rental_duration exists: 15 pts
   - chk_payment_amount exists: 15 pts
3. Schema Enhancement (15 pts):
   - price_category column exists & populated correctly: 15 pts
4. Stored Function (15 pts):
   - fn_customer_lifetime_value exists & works: 15 pts
5. Reporting (10 pts):
   - CSV export exists with correct row count: 10 pts

Pass Threshold: 60 pts
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_data_integrity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/integrity_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # 1. Data Repair (30 pts)
        bad_films = result.get('remaining_bad_films', 99)
        bad_payments = result.get('remaining_bad_payments', 99)
        
        if bad_films == 0:
            score += 15
            feedback_parts.append("Fixed invalid rental_duration (15/15)")
        else:
            feedback_parts.append(f"Failed: {bad_films} films still have invalid duration (0/15)")
            
        if bad_payments == 0:
            score += 15
            feedback_parts.append("Fixed invalid payment amounts (15/15)")
        else:
            feedback_parts.append(f"Failed: {bad_payments} payments still have negative amounts (0/15)")

        # 2. Constraints (30 pts)
        # Note: If data wasn't fixed, adding constraints would fail in MySQL
        if result.get('has_film_constraint', 0) > 0:
            score += 15
            feedback_parts.append("Constraint chk_rental_duration exists (15/15)")
        else:
            feedback_parts.append("Constraint chk_rental_duration missing (0/15)")
            
        if result.get('has_payment_constraint', 0) > 0:
            score += 15
            feedback_parts.append("Constraint chk_payment_amount exists (15/15)")
        else:
            feedback_parts.append("Constraint chk_payment_amount missing (0/15)")

        # 3. Schema Enhancement (15 pts)
        has_col = result.get('has_price_category', 0) > 0
        logic_ok = result.get('price_logic_correct', False)
        nulls = result.get('price_category_nulls', 9999)
        
        if has_col and logic_ok and nulls == 0:
            score += 15
            feedback_parts.append("Column price_category added & populated correctly (15/15)")
        elif has_col:
            # Partial credit if column exists but data is wrong/missing
            score += 5
            feedback_parts.append("Column price_category exists but data/logic incorrect (5/15)")
        else:
            feedback_parts.append("Column price_category missing (0/15)")

        # 4. Stored Function (15 pts)
        has_func = result.get('has_function', 0) > 0
        func_ok = result.get('function_logic_correct', False)
        
        if has_func and func_ok:
            score += 15
            feedback_parts.append("Function fn_customer_lifetime_value correct (15/15)")
        elif has_func:
            score += 5
            feedback_parts.append("Function exists but returned incorrect value (5/15)")
        else:
            feedback_parts.append("Function fn_customer_lifetime_value missing (0/15)")

        # 5. Reporting (10 pts)
        csv_exists = result.get('csv_exists', False)
        csv_rows = result.get('csv_rows', 0)
        task_start = result.get('task_start', 0)
        csv_mtime = result.get('csv_mtime', 0)
        
        # Expect ~1000 rows (one per film)
        if csv_exists and csv_rows >= 990 and csv_mtime > task_start:
            score += 10
            feedback_parts.append(f"Report exported ({csv_rows} rows) (10/10)")
        elif csv_exists:
            feedback_parts.append(f"Report incomplete or old ({csv_rows} rows) (0/10)")
        else:
            feedback_parts.append("Report missing (0/10)")

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}