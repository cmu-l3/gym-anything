#!/usr/bin/env python3
"""
Verifier for Sakila Legacy Normalization task.

Task requires:
1. Creating a normalized database 'rental_norm'.
2. Creating 4 normalized tables with appropriate row counts (deduplicated).
3. Setting up PKs and FKs.
4. Creating a reconstruction view.
5. Exporting customer data to CSV.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_legacy_normalization(traj, env_info, task_info):
    """
    Verify normalization task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/normalization_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []

    # Expected approximate counts (based on standard Sakila)
    EXP_CUSTOMERS = 599
    EXP_FILMS = 950  # Roughly
    EXP_STORES = 2
    EXP_RENTALS = 16044
    
    # 1. Database Creation (5 pts)
    if result.get('db_exists', 0) == 1:
        score += 5
        feedback_parts.append("Database 'rental_norm' created (5/5)")
    else:
        feedback_parts.append("Database 'rental_norm' NOT created (0/5)")

    # 2. Table Creation & Data Migration (45 pts total)
    # Customers (15 pts: 5 structure, 10 data)
    c_count = result.get('count_customers', 0)
    if c_count > 0:
        score += 5
        if abs(c_count - EXP_CUSTOMERS) < 50:
            score += 10
            feedback_parts.append(f"norm_customers populated correctly (~{c_count}) (15/15)")
        else:
            feedback_parts.append(f"norm_customers has unexpected row count: {c_count} (expected ~{EXP_CUSTOMERS}) (5/15)")
    else:
        feedback_parts.append("norm_customers missing or empty (0/15)")

    # Films (15 pts: 5 structure, 10 data)
    f_count = result.get('count_films', 0)
    if f_count > 0:
        score += 5
        if f_count > 900 and f_count < 1100:
            score += 10
            feedback_parts.append(f"norm_films populated correctly (~{f_count}) (15/15)")
        else:
            feedback_parts.append(f"norm_films has unexpected row count: {f_count} (expected ~1000) (5/15)")
    else:
        feedback_parts.append("norm_films missing or empty (0/15)")

    # Stores (5 pts)
    s_count = result.get('count_stores', 0)
    if s_count == 2:
        score += 5
        feedback_parts.append("norm_stores populated correctly (5/5)")
    elif s_count > 0:
        score += 2
        feedback_parts.append(f"norm_stores exists but has {s_count} rows (expected 2) (2/5)")
    else:
        feedback_parts.append("norm_stores missing (0/5)")
        
    # Rentals (10 pts)
    r_count = result.get('count_rentals', 0)
    if r_count > 0:
        if abs(r_count - EXP_RENTALS) < 200:
            score += 10
            feedback_parts.append(f"norm_rentals populated correctly (~{r_count}) (10/10)")
        else:
            score += 5
            feedback_parts.append(f"norm_rentals has unexpected row count: {r_count} (5/10)")
    else:
        feedback_parts.append("norm_rentals missing (0/10)")

    # 3. Constraints (20 pts)
    # Primary keys (5 pts)
    pks = result.get('pk_customers', 0) + result.get('pk_films', 0) + result.get('pk_stores', 0) + result.get('pk_rentals', 0)
    if pks == 4:
        score += 5
        feedback_parts.append("Primary keys set on all tables (5/5)")
    elif pks > 0:
        score += 2
        feedback_parts.append("Some primary keys missing (2/5)")
    
    # Foreign Keys (10 pts)
    # Expecting at least 3 FKs in rental table (customer, film, store)
    fk_count = result.get('fk_count_rentals', 0)
    if fk_count >= 3:
        score += 10
        feedback_parts.append("Foreign keys configured correctly (10/10)")
    elif fk_count > 0:
        score += 5
        feedback_parts.append(f"Partial foreign keys found: {fk_count} (5/10)")
    else:
        feedback_parts.append("No foreign keys found on norm_rentals (0/10)")

    # Unique constraint (5 pts)
    if result.get('unique_email', 0) > 0:
        score += 5
        feedback_parts.append("Unique constraint on email found (5/5)")
    else:
        feedback_parts.append("Unique constraint on email missing (0/5)")

    # 4. View Creation (10 pts)
    v_rows = result.get('view_rows', 0)
    if v_rows > 15000:
        score += 10
        feedback_parts.append("Reconstruction view works (10/10)")
    elif result.get('view_exists', 0) == 1:
        score += 5
        feedback_parts.append("View exists but returned few/no rows (5/10)")
    else:
        feedback_parts.append("Reconstruction view missing (0/10)")

    # 5. CSV Export (20 pts)
    csv_exists = result.get('csv_exists', False)
    csv_rows = result.get('csv_rows', 0)
    task_start = result.get('task_start', 0)
    csv_mtime = result.get('csv_mtime', 0)
    
    if csv_exists and csv_rows > 500 and csv_mtime > task_start:
        score += 20
        feedback_parts.append("CSV export successful and valid (20/20)")
    elif csv_exists:
        score += 5
        feedback_parts.append("CSV exists but invalid content or timestamp (5/20)")
    else:
        feedback_parts.append("CSV export missing (0/20)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }