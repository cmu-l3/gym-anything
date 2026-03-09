#!/usr/bin/env python3
"""
Verifier for Chinook Schema Modernization task.

Criteria:
1. DBeaver connection 'ChinookLegacy' created (10 pts)
2. Orphaned invoices deleted (count == 0) (20 pts)
3. Orphaned invoice items deleted (count == 0) (20 pts)
4. Foreign Key added to Invoices table (20 pts)
5. Foreign Key added to InvoiceItems table (15 pts)
6. InvoiceItems FK has ON DELETE CASCADE (15 pts)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_schema_modernization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Connection (10 pts)
    if result.get("connection_exists", False):
        if result.get("connection_name_correct", False):
            score += 10
            feedback.append("DBeaver connection 'ChinookLegacy' found.")
        else:
            score += 5
            feedback.append("DBeaver connection found, but name mismatch (expected 'ChinookLegacy').")
    else:
        feedback.append("No DBeaver connection found.")

    # 2. Orphans Invoices (20 pts)
    orphan_inv = result.get("orphaned_invoices_count", -1)
    if orphan_inv == 0:
        score += 20
        feedback.append("Orphaned invoices successfully removed.")
    elif orphan_inv == -1:
        feedback.append("Could not verify invoice orphans (DB access error).")
    else:
        feedback.append(f"Failed: {orphan_inv} orphaned invoices remain.")

    # 3. Orphans Items (20 pts)
    orphan_items = result.get("orphaned_items_count", -1)
    if orphan_items == 0:
        score += 20
        feedback.append("Orphaned invoice items successfully removed.")
    else:
        feedback.append(f"Failed: {orphan_items} orphaned invoice items remain.")

    # 4. Invoices FK (20 pts)
    if result.get("invoice_fk_exists", False):
        score += 20
        feedback.append("Foreign Key successfully added to 'invoices'.")
    else:
        feedback.append("Foreign Key missing on 'invoices' table.")

    # 5. Items FK (15 pts)
    if result.get("item_fk_exists", False):
        score += 15
        feedback.append("Foreign Key successfully added to 'invoice_items'.")
    else:
        feedback.append("Foreign Key missing on 'invoice_items' table.")

    # 6. Cascade (15 pts)
    if result.get("cascade_configured", False):
        score += 15
        feedback.append("ON DELETE CASCADE correctly configured.")
    else:
        # Check if they at least got the FK
        if result.get("item_fk_exists", False):
             feedback.append("ON DELETE CASCADE missing for 'invoice_items' FK.")

    # Anti-gaming check
    if not result.get("modified_during_task", False):
        feedback.append("WARNING: Database file timestamp suggests no changes were made during task.")
        # We don't fail immediately, but if score is high and file wasn't touched, suspicious.
        # However, DBeaver might update file mtime only on commit. SQLite usually updates mtime on transaction.
        # If score > 0 but modified is false, something is wrong.
        if score > 0:
            score = 0
            feedback.append("FAIL: Database file was not modified during task execution.")

    # Final tally
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }