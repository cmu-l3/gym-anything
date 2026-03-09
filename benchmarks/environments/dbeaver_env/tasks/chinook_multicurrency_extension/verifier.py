#!/usr/bin/env python3
"""
Verifier for Chinook Multi-Currency Extension Task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_multicurrency_extension(traj, env_info, task_info):
    """
    Verify the database extension task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming check: Original DB modification
    if result.get('original_db_modified', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Original 'chinook.db' was modified. You should only modify 'chinook_extended.db'."
        }

    # 2. Connection Check (10 pts)
    if result.get('connection_found'):
        score += 10
        feedback_parts.append("DBeaver connection 'ChinookExtended' found.")
    else:
        feedback_parts.append("DBeaver connection 'ChinookExtended' NOT found.")

    # 3. Currencies Table Check (15 pts)
    if result.get('currency_table_exists'):
        count = result.get('currency_row_count', 0)
        if count == 6:
            score += 15
            feedback_parts.append("Table 'currencies' created with 6 rows.")
        elif count > 0:
            score += 10
            feedback_parts.append(f"Table 'currencies' exists but has {count} rows (expected 6).")
        else:
            score += 5
            feedback_parts.append("Table 'currencies' exists but is empty.")
    else:
        feedback_parts.append("Table 'currencies' NOT found.")

    # 4. Invoices Column Check (10 pts)
    if result.get('has_currency_column'):
        score += 10
        feedback_parts.append("Column 'CurrencyCode' added to 'invoices'.")
    else:
        feedback_parts.append("Column 'CurrencyCode' NOT found in 'invoices'.")

    # 5. Data Update Logic Checks (30 pts total)
    # EUR Check (15 pts)
    eur_count = result.get('eur_invoice_count', 0)
    eur_expected = result.get('eur_expected_count', 0)
    if eur_expected > 0 and eur_count == eur_expected:
        score += 15
        feedback_parts.append(f"All {eur_expected} Eurozone invoices correctly mapped to EUR.")
    else:
        feedback_parts.append(f"EUR mapping mismatch: Found {eur_count}, Expected {eur_expected}.")

    # BRL Check (10 pts)
    brl_count = result.get('brl_invoice_count', 0)
    brl_expected = result.get('brl_expected_count', 0)
    if brl_expected > 0 and brl_count == brl_expected:
        score += 10
        feedback_parts.append(f"All {brl_expected} Brazil invoices correctly mapped to BRL.")
    else:
        feedback_parts.append(f"BRL mapping mismatch: Found {brl_count}, Expected {brl_expected}.")

    # NULL Check (5 pts)
    if result.get('null_currency_count', 1) == 0:
        score += 5
        feedback_parts.append("No NULL CurrencyCode values found.")
    else:
        feedback_parts.append("Found invoices with NULL CurrencyCode.")

    # 6. View Creation and Accuracy (20 pts)
    if result.get('view_exists'):
        score += 10
        feedback_parts.append("View 'currency_revenue_summary' exists.")
        
        # Check logic - USD is typically top revenue
        top_curr = result.get('view_top_currency', '')
        # We rely on the SQL view calculation for revenue. 
        # If USD is top or revenue > 0, we give points.
        # A more robust check compares exact revenue, but basic logic check is:
        if top_curr == 'USD':
            score += 10
            feedback_parts.append("View results appear correct (USD is top revenue).")
        else:
            feedback_parts.append(f"View top currency is {top_curr}, expected USD.")
    else:
        feedback_parts.append("View 'currency_revenue_summary' NOT found.")

    # 7. File Deliverables (15 pts)
    # CSV
    if result.get('csv_exists') and result.get('csv_size', 0) > 100:
        if result.get('csv_created_during_task'):
            score += 10
            feedback_parts.append("CSV export found and created during task.")
        else:
            score += 5
            feedback_parts.append("CSV export found but timestamp predates task start.")
    else:
        feedback_parts.append("CSV export missing or empty.")

    # SQL
    if result.get('sql_exists'):
        score += 5
        feedback_parts.append("SQL migration script found.")
    else:
        feedback_parts.append("SQL migration script missing.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }