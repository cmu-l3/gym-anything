#!/bin/bash
# Export script for Warehouse Transfer API task
# This script runs a functional test suite against the agent's PL/SQL code

set -e
echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Run Python verification suite inside the environment
# This connects to the DB and attempts to call the agent's procedure
python3 << 'PYEOF'
import oracledb
import json
import os
import sys

# Configuration
DB_CONFIG = {
    "user": "hr",
    "password": "hr123",
    "dsn": "localhost:1521/XEPDB1"
}

results = {
    "constraint_exists": False,
    "package_valid": False,
    "test_valid_transfer": False,
    "test_new_row_creation": False,
    "test_insufficient_funds": False,
    "test_audit_logging": False,
    "test_transaction_safety": False,
    "error_log": []
}

try:
    conn = oracledb.connect(**DB_CONFIG)
    cursor = conn.cursor()

    # ---------------------------------------------------------
    # CHECK 1: Constraint Existence
    # ---------------------------------------------------------
    try:
        cursor.execute("""
            SELECT constraint_name, status 
            FROM user_constraints 
            WHERE table_name = 'INVENTORY' 
            AND constraint_type = 'C'
            AND constraint_name = 'CHK_INV_QTY_NONNEG'
        """)
        row = cursor.fetchone()
        if row and row[1] == 'ENABLED':
            results["constraint_exists"] = True
        else:
            # Check if they named it something else but logic holds? 
            # (Task specifically asked for name, but let's check search condition if we wanted to be lenient.
            # Here we enforce the name for simplicity/strictness as per spec).
            pass
    except Exception as e:
        results["error_log"].append(f"Constraint check failed: {str(e)}")

    # ---------------------------------------------------------
    # CHECK 2: Package Validity
    # ---------------------------------------------------------
    try:
        cursor.execute("""
            SELECT status FROM user_objects 
            WHERE object_name = 'INV_MANAGER' 
            AND object_type = 'PACKAGE BODY'
        """)
        row = cursor.fetchone()
        if row and row[0] == 'VALID':
            results["package_valid"] = True
    except Exception as e:
        results["error_log"].append(f"Package check failed: {str(e)}")

    # ---------------------------------------------------------
    # FUNCTIONAL TESTS
    # Only run if package is valid
    # ---------------------------------------------------------
    if results["package_valid"]:
        
        # Helper to get qty
        def get_qty(sku, wh):
            cursor.execute("SELECT quantity FROM inventory WHERE sku=:1 AND wh_id=:2", [sku, wh])
            r = cursor.fetchone()
            return r[0] if r else 0

        # Helper to count logs
        def get_log_count():
            cursor.execute("SELECT COUNT(*) FROM transfer_log")
            return cursor.fetchone()[0]

        # TEST A: Normal Transfer (Existing Rows)
        # Move 2 XPS from WH 1 to WH 2
        # Initial: WH1=10, WH2=5
        try:
            initial_logs = get_log_count()
            cursor.callproc("INV_MANAGER.TRANSFER_STOCK", ['SKU-DELL-XPS', 1, 2, 2])
            
            q1 = get_qty('SKU-DELL-XPS', 1)
            q2 = get_qty('SKU-DELL-XPS', 2)
            
            if q1 == 8 and q2 == 7:
                results["test_valid_transfer"] = True
            
            if get_log_count() == initial_logs + 1:
                results["test_audit_logging"] = True
                
        except Exception as e:
            results["error_log"].append(f"Valid transfer test failed: {str(e)}")

        # TEST B: New Row Creation (Merge/Insert logic)
        # Move 1 SSD from WH 3 to WH 1 (WH 1 has no SSDs initially)
        # Initial: WH3=100, WH1=0 (no row)
        try:
            cursor.callproc("INV_MANAGER.TRANSFER_STOCK", ['SKU-SAM-SSD', 3, 1, 1])
            
            q3 = get_qty('SKU-SAM-SSD', 3)
            q1 = get_qty('SKU-SAM-SSD', 1)
            
            if q3 == 99 and q1 == 1:
                results["test_new_row_creation"] = True
        except Exception as e:
            results["error_log"].append(f"New row creation test failed: {str(e)}")

        # TEST C: Insufficient Funds (Transaction Safety)
        # Try to move 1000 XPS from WH 1 (has 8 now)
        try:
            initial_q1 = get_qty('SKU-DELL-XPS', 1)
            failed = False
            try:
                cursor.callproc("INV_MANAGER.TRANSFER_STOCK", ['SKU-DELL-XPS', 1, 2, 1000])
            except oracledb.DatabaseError as e:
                # Expecting an application error
                failed = True
            
            final_q1 = get_qty('SKU-DELL-XPS', 1)
            
            if failed and final_q1 == initial_q1:
                results["test_insufficient_funds"] = True
                results["test_transaction_safety"] = True
            elif not failed:
                results["error_log"].append("Insufficient funds did not raise exception")
            else:
                results["error_log"].append("Insufficient funds raised exception but data changed (rollback failed)")
                
        except Exception as e:
            results["error_log"].append(f"Insufficient funds test error: {str(e)}")

    conn.close()

except Exception as e:
    results["error_log"].append(f"Fatal DB Error: {str(e)}")

# Save Results
with open('/tmp/task_result.json', 'w') as f:
    json.dump(results, f, indent=2)

PYEOF

# Fix permissions
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json