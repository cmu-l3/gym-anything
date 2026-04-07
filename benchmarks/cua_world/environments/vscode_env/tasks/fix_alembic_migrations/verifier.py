#!/usr/bin/env python3
"""
Verifier for the fix_alembic_migrations task.

Checks whether the agent fixed all 5 Alembic/SQLite migration bugs.
Evaluations are based on the independent execution run by the export script 
against a pristine SQLite database to prevent manual DB gaming.

Each bug fix is worth 20 points (total 100). Pass threshold: 60.
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_alembic_migrations(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_invoice_2009_count = metadata.get('expected_invoice_2009_count', 2)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/migration_result.json", temp_result.name)
        if not os.path.exists(temp_result.name) or os.path.getsize(temp_result.name) == 0:
            return {"passed": False, "score": 0, "feedback": "Verification result missing or empty."}
            
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    upgrade_success = result.get("upgrade_success", False)
    db_post_up = result.get("db_state_post_upgrade", {})
    downgrade_success = result.get("downgrade_success", False)
    db_post_down = result.get("db_state_post_downgrade", {})

    # ---------------------------------------------------------
    # Criterion 1: NOT NULL fix & Upgrade Success (20 pts)
    # ---------------------------------------------------------
    customer_cols_up = db_post_up.get("customer_columns", [])
    if upgrade_success and "IsPremium" in customer_cols_up:
        score += 20
        feedback_parts.append("[+] Upgrade ran successfully without NOT NULL crashing (20/20)")
    else:
        feedback_parts.append("[-] Upgrade failed or IsPremium missing. IsPremium nullable/server_default fix missing? (0/20)")

    # ---------------------------------------------------------
    # Criterion 2: SQLite DROP COLUMN fix via batch_alter_table (20 pts)
    # ---------------------------------------------------------
    if upgrade_success and "Fax" not in customer_cols_up:
        score += 20
        feedback_parts.append("[+] Fax column successfully dropped using batch_alter_table (20/20)")
    else:
        feedback_parts.append("[-] Fax column drop failed or not executed (0/20)")

    # ---------------------------------------------------------
    # Criterion 3: Raw SQL Data extraction Off-By-One (20 pts)
    # ---------------------------------------------------------
    invoice_count = db_post_up.get("invoice_2009_count", -1)
    if invoice_count == expected_invoice_2009_count:
        score += 20
        feedback_parts.append("[+] InvoiceYear extracted correctly. SQLite SUBSTR indexing fixed (20/20)")
    elif invoice_count > 0:
        score += 5
        feedback_parts.append(f"[-] InvoiceYear extracted incorrectly. Found {invoice_count} instead of {expected_invoice_2009_count} (5/20)")
    else:
        feedback_parts.append("[-] InvoiceYear extraction logic still broken (0/20)")

    # ---------------------------------------------------------
    # Criterion 4: CustomerLog Foreign Key Ref (20 pts)
    # ---------------------------------------------------------
    fks = db_post_up.get("customerlog_fks", [])
    # FK payload layout from PRAGMA: (id, seq, table, from, to, on_update, on_delete, match)
    # index 4 is 'to' column
    fk_correct = False
    for fk in fks:
        if len(fk) >= 5 and fk[2] == "Customer" and fk[4] == "CustomerId":
            fk_correct = True
            break
            
    if fk_correct:
        score += 20
        feedback_parts.append("[+] CustomerLog Foreign Key correctly references CustomerId (20/20)")
    else:
        feedback_parts.append("[-] CustomerLog Foreign Key reference to 'Id' not fixed (0/20)")

    # ---------------------------------------------------------
    # Criterion 5: Downgrade logic complete (20 pts)
    # ---------------------------------------------------------
    customer_cols_down = db_post_down.get("customer_columns", [])
    tables_down = db_post_down.get("tables", [])
    
    if downgrade_success:
        downgrade_score = 0
        if "IsPremium" not in customer_cols_down:
            downgrade_score += 5
        if "Fax" in customer_cols_down:
            downgrade_score += 5
        if "CustomerLog" not in tables_down:
            downgrade_score += 10
            
        score += downgrade_score
        if downgrade_score == 20:
            feedback_parts.append("[+] Downgrade successfully restored schema completely (20/20)")
        else:
            feedback_parts.append(f"[~] Downgrade executed but schema not perfectly restored ({downgrade_score}/20)")
    else:
        feedback_parts.append("[-] Downgrade logic incomplete or crashed (0/20)")

    # Combine feedback and calculate success
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "upgrade_success": upgrade_success,
            "downgrade_success": downgrade_success
        }
    }