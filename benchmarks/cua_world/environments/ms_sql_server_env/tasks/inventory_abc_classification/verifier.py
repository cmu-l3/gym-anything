#!/usr/bin/env python3
"""
Verifier for Inventory ABC Classification Task.
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inventory_abc_classification(traj, env_info, task_info):
    """
    Score the ABC classification task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. Schema and View Existence (10 pts)
    if result.get('schema_exists') and result.get('view_exists'):
        score += 10
        feedback.append("Schema and View created.")
    else:
        feedback.append("Missing Inventory schema or vw_ABC_Classification_2013 view.")

    # 2. View Structure (10 pts)
    if result.get('has_required_columns'):
        score += 10
        feedback.append("View has correct columns.")
    else:
        feedback.append("View missing required columns (ProductID, Name, TotalRevenue, CumulativePct, ABC_Class).")

    # 3. Unsold Items Logic (Outer Join) (20 pts)
    total_products = result.get('total_db_products', 0)
    view_rows = result.get('view_row_count', 0)
    unsold_count = result.get('unsold_included_count', 0)
    
    # Tolerance for row count diffs (e.g. if db changed slightly, but shouldn't happen)
    if view_rows >= total_products and total_products > 0:
        score += 10
        feedback.append(f"View includes all {total_products} products.")
    else:
        feedback.append(f"View missing products. Expected ~{total_products}, got {view_rows}. Did you use INNER JOIN instead of LEFT JOIN?")
        
    if unsold_count > 0:
        score += 10
        feedback.append(f"View correctly includes {unsold_count} unsold items.")
    else:
        feedback.append("View excludes unsold items (Revenue=0).")

    # 4. Calculation Accuracy (20 pts)
    # Compare calculated revenue for known product 782
    try:
        calc_rev = float(result.get('calc_rev_782', 0))
        view_rev = float(result.get('view_rev_782', 0))
        if calc_rev > 0 and math.isclose(calc_rev, view_rev, rel_tol=0.01):
            score += 20
            feedback.append(f"Revenue calculation correct for sample product (${view_rev}).")
        else:
            feedback.append(f"Revenue mismatch for Product 782. Expected ~{calc_rev}, got {view_rev}.")
    except (ValueError, TypeError):
        feedback.append("Could not verify revenue calculation (invalid data).")

    # 5. Classification Logic (20 pts)
    # Check Max % for A
    try:
        max_pct_a = float(result.get('max_pct_a', 0))
        # Should be <= 0.80, or slightly above if the item straddles the line, but strict logic is <=
        # We allow up to 0.85 to account for "item that pushes it over 80%" implementations vs "strict cutoff"
        if 0.70 < max_pct_a <= 0.85:
            score += 10
            feedback.append(f"Class A threshold appears correct (Max Pct: {max_pct_a}).")
        else:
            feedback.append(f"Class A threshold questionable (Max Pct: {max_pct_a}). Expected ~0.80.")
    except:
        pass

    # Check Zero Revenue is C
    zero_class = result.get('zero_rev_class', '').strip()
    if zero_class == 'C':
        score += 10
        feedback.append("Unsold items correctly classified as 'C'.")
    else:
        feedback.append(f"Unsold items classified as '{zero_class}'. Expected 'C'.")

    # 6. CSV Export (20 pts)
    if result.get('csv_exists'):
        if result.get('csv_created_during'):
            score += 10
            feedback.append("CSV file created.")
        else:
            feedback.append("CSV file exists but is old.")
            
        # Check rows matches Class A count from DB
        csv_rows = result.get('csv_row_count', 0)
        db_a_rows = result.get('class_a_count', 0)
        
        # Allow small deviation
        if db_a_rows > 0 and abs(csv_rows - db_a_rows) <= 1:
            score += 10
            feedback.append(f"CSV row count ({csv_rows}) matches Class A items.")
        else:
            feedback.append(f"CSV row count ({csv_rows}) mismatches Class A items ({db_a_rows}).")
    else:
        feedback.append("CSV file not found.")

    if score >= 70:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }