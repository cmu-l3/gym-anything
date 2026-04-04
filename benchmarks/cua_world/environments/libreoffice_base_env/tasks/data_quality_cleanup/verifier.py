#!/usr/bin/env python3
"""
Verifier for data_quality_cleanup task.

Verification Logic:
1. Extracts the ODB file to access the internal HSQLDB script.
2. Checks for presence of injected anomaly records (INSERT statements).
3. Checks total record counts against expected clean state.
4. Verifies integrity of original data (ensures no mass deletion).
5. Checks existence and content of the user's SQL log file.
"""

import json
import tempfile
import os
import shutil
import zipfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_data_quality_cleanup(traj, env_info, task_info):
    """
    Verify that anomalies were removed and original data preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- Load task metadata ---
    metadata = task_info.get('metadata', {})
    anomalies = metadata.get('anomalies', {})
    expected_counts = metadata.get('expected_counts', {})
    
    dup_customers = anomalies.get('customers', [60, 61, 62])
    orphan_invoices = anomalies.get('invoices', [413, 414])
    orphan_lines = anomalies.get('invoice_lines', [2241, 2242, 2243])

    # --- Retrieve result JSON ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # --- Initial Checks ---
    score = 0
    feedback_parts = []
    
    if not result.get('odb_exists', False):
        return {"passed": False, "score": 0, "feedback": "Database file deleted or missing"}
    
    if not result.get('odb_modified', False):
        return {"passed": False, "score": 0, "feedback": "Database file was not modified (did you save?)"}

    # --- Retrieve ODB File ---
    odb_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.odb')
    odb_path = odb_temp.name
    odb_temp.close()
    
    try:
        copy_from_env(result.get('odb_path', '/home/ga/chinook.odb'), odb_path)
    except Exception as e:
        if os.path.exists(odb_path): os.unlink(odb_path)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ODB file: {e}"}

    # --- Retrieve SQL Log File ---
    sql_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.sql')
    sql_path = sql_temp.name
    sql_temp.close()
    
    sql_content = ""
    try:
        if result.get('sql_exists', False):
            copy_from_env(result.get('sql_path', '/home/ga/cleanup_queries.sql'), sql_path)
            with open(sql_path, 'r', errors='ignore') as f:
                sql_content = f.read()
    except Exception as e:
        logger.warning(f"Failed to retrieve SQL file: {e}")

    # --- Analyze ODB Content ---
    work_dir = tempfile.mkdtemp()
    script_content = ""
    
    try:
        with zipfile.ZipFile(odb_path, 'r') as zf:
            zf.extractall(work_dir)
        
        script_file = os.path.join(work_dir, 'database', 'script')
        if os.path.exists(script_file):
            with open(script_file, 'r', errors='ignore') as f:
                script_content = f.read()
        else:
            return {"passed": False, "score": 0, "feedback": "Corrupt ODB: missing database script"}
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to analyze ODB: {e}"}
    finally:
        shutil.rmtree(work_dir)
        if os.path.exists(odb_path): os.unlink(odb_path)
        if os.path.exists(sql_path): os.unlink(sql_path)

    # --- Verification Helper Functions ---
    def count_inserts(table):
        # Pattern matches INSERT INTO PUBLIC."Table" VALUES(...)
        # Note: HSQLDB script format might vary slightly, but usually consistent in LO Base
        return len(re.findall(rf'INSERT INTO PUBLIC\."{table}" VALUES', script_content))

    def has_record(table, id_val):
        # Look for ID at start of values: VALUES(60, ...
        return bool(re.search(rf'INSERT INTO PUBLIC\."{table}" VALUES\(\s*{id_val}\b', script_content))

    # --- Criterion 1: Duplicate Customers (20 pts) ---
    customers_left = [cid for cid in dup_customers if has_record("Customer", cid)]
    curr_customer_count = count_inserts("Customer")
    exp_customer_count = expected_counts.get("Customer", 59)
    
    if not customers_left and curr_customer_count == exp_customer_count:
        score += 20
        feedback_parts.append("Duplicate customers removed ✓")
    elif not customers_left:
        score += 15
        feedback_parts.append(f"Duplicate customers removed, but count incorrect ({curr_customer_count} vs {exp_customer_count})")
    elif len(customers_left) < len(dup_customers):
        score += 10
        feedback_parts.append(f"Partially removed duplicate customers ({len(customers_left)} remaining)")
    else:
        feedback_parts.append("Duplicate customers NOT removed")

    # --- Criterion 2: Orphan Invoice Lines (20 pts) ---
    # These must be deleted before invoices to avoid FK errors (though agent might do it via cascading or UI)
    lines_left = [lid for lid in orphan_lines if has_record("InvoiceLine", lid)]
    curr_line_count = count_inserts("InvoiceLine")
    exp_line_count = expected_counts.get("InvoiceLine", 2240)

    if not lines_left and curr_line_count == exp_line_count:
        score += 20
        feedback_parts.append("Orphan invoice lines removed ✓")
    elif not lines_left:
        score += 15
        feedback_parts.append(f"Orphan lines removed, but count incorrect ({curr_line_count} vs {exp_line_count})")
    else:
        feedback_parts.append("Orphan invoice lines NOT removed")

    # --- Criterion 3: Orphan Invoices (20 pts) ---
    invoices_left = [iid for iid in orphan_invoices if has_record("Invoice", iid)]
    curr_invoice_count = count_inserts("Invoice")
    exp_invoice_count = expected_counts.get("Invoice", 412)

    if not invoices_left and curr_invoice_count == exp_invoice_count:
        score += 20
        feedback_parts.append("Orphan invoices removed ✓")
    elif not invoices_left:
        score += 15
        feedback_parts.append(f"Orphan invoices removed, but count incorrect ({curr_invoice_count} vs {exp_invoice_count})")
    else:
        feedback_parts.append("Orphan invoices NOT removed")

    # --- Criterion 4: Data Integrity (20 pts) ---
    # Check if original data (e.g., Customer ID 1) still exists
    integrity_ok = True
    if not has_record("Customer", 1): integrity_ok = False
    if not has_record("Invoice", 1): integrity_ok = False
    
    # Check if table schemas exist
    if 'CREATE TABLE PUBLIC."Customer"' not in script_content: integrity_ok = False

    if integrity_ok:
        score += 20
        feedback_parts.append("Original data integrity preserved ✓")
    else:
        feedback_parts.append("CRITICAL: Original data missing or schema corrupted")
        # Penalize heavily if integrity is lost
        score = min(score, 40) 

    # --- Criterion 5: SQL Log File (20 pts) ---
    if result.get('sql_created', False) and len(sql_content) > 50:
        sql_upper = sql_content.upper()
        if "DELETE" in sql_upper and ("CUSTOMER" in sql_upper or "INVOICE" in sql_upper):
            score += 20
            feedback_parts.append("SQL cleanup log verified ✓")
        else:
            score += 10
            feedback_parts.append("SQL log file exists but content unclear (missing DELETE/Table keywords)")
    elif result.get('sql_exists', False):
        score += 5
        feedback_parts.append("SQL log file exists but empty or too small")
    else:
        feedback_parts.append("SQL cleanup log NOT found")

    # --- Final Scoring ---
    passed = score >= 60 and integrity_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }