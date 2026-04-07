#!/bin/bash
# Export script for BI Query Rewrite Task
# Verifies if the rewrite happens using EXPLAIN PLAN on the ORIGINAL query logic.

set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting BI Query Rewrite Results ==="

# 1. Configuration
DB_USER="sh_lite"
DB_PASS="password123"
DB_CONN="localhost:1521/XEPDB1"
PROOF_FILE="/home/ga/Desktop/optimization_proof.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Define the Original Query (Ground Truth)
# We test THIS query, regardless of what the agent put in the .sql file on desktop.
ORIGINAL_QUERY="SELECT p.prod_category, c.country_iso_code, SUM(s.amount_sold) as total_sales, COUNT(*) as num_txns FROM sales s JOIN products p ON s.prod_id = p.prod_id JOIN customers c ON s.cust_id = c.cust_id GROUP BY p.prod_category, c.country_iso_code ORDER BY total_sales DESC"

# 3. Python script to check DB state
python3 << PYEOF
import oracledb
import json
import os
import sys

result = {
    "mv_exists": False,
    "mv_name": None,
    "rewrite_enabled": False,
    "mv_status": None,
    "last_refresh": None,
    "rewrite_verified": False,
    "rewrite_cost": 0,
    "base_cost": 0,
    "proof_file_exists": False,
    "db_error": None
}

try:
    conn = oracledb.connect(user="${DB_USER}", password="${DB_PASS}", dsn="${DB_CONN}")
    cursor = conn.cursor()

    # A. Check for Materialized Views
    print("Checking MVs...")
    cursor.execute("""
        SELECT mview_name, rewrite_enabled, rewrite_capability, staleness, last_refresh_date
        FROM user_mviews
    """)
    mviews = cursor.fetchall()
    
    if mviews:
        # Just pick the first one that has rewrite enabled, or just the first one
        best_mv = None
        for mv in mviews:
            if mv[1] == 'Y':
                best_mv = mv
                break
        
        if not best_mv and mviews:
            best_mv = mviews[0]

        if best_mv:
            result["mv_exists"] = True
            result["mv_name"] = best_mv[0]
            result["rewrite_enabled"] = (best_mv[1] == 'Y')
            result["mv_status"] = best_mv[3] # Staleness
            result["last_refresh"] = str(best_mv[4])

    # B. Verify Rewrite Verification (The Core Test)
    # We explain the ORIGINAL query. If the plan shows MAT_VIEW REWRITE ACCESS, success.
    
    query_text = "${ORIGINAL_QUERY}"
    
    # 1. Get Base Plan (Disable rewrite to see baseline - just for info)
    cursor.execute("ALTER SESSION SET QUERY_REWRITE_ENABLED = FALSE")
    cursor.execute(f"EXPLAIN PLAN SET STATEMENT_ID = 'BASE' FOR {query_text}")
    cursor.execute("SELECT cost FROM plan_table WHERE statement_id = 'BASE' AND id = 0")
    base_row = cursor.fetchone()
    if base_row:
        result["base_cost"] = base_row[0]

    # 2. Get Optimized Plan
    cursor.execute("ALTER SESSION SET QUERY_REWRITE_ENABLED = TRUE")
    # Force integrity to trusted/stale_tolerated just in case agent didn't refresh perfectly
    # But strictly, for this task, they should build immediate. 
    # Let's stick to default enforcement. If they fail to refresh, rewrite won't happen (correct behavior).
    
    cursor.execute(f"EXPLAIN PLAN SET STATEMENT_ID = 'OPT' FOR {query_text}")
    
    # Check operations
    cursor.execute("""
        SELECT operation, options, object_name 
        FROM plan_table 
        WHERE statement_id = 'OPT'
    """)
    plan_ops = cursor.fetchall()
    
    mv_access_found = False
    for op in plan_ops:
        operation = str(op[0])
        options = str(op[1])
        obj_name = str(op[2])
        
        # Look for rewrite signature
        if "MAT_VIEW" in operation and "REWRITE" in options:
            mv_access_found = True
        
        # Also check if it's accessing the MV created
        if result["mv_name"] and result["mv_name"] in obj_name:
             pass # Good signal
             
    result["rewrite_verified"] = mv_access_found

    # Get optimized cost
    cursor.execute("SELECT cost FROM plan_table WHERE statement_id = 'OPT' AND id = 0")
    opt_row = cursor.fetchone()
    if opt_row:
        result["rewrite_cost"] = opt_row[0]

except Exception as e:
    result["db_error"] = str(e)
    print(f"DB Error: {e}")

# C. Check Proof File
proof_path = "${PROOF_FILE}"
if os.path.exists(proof_path):
    result["proof_file_exists"] = True

# Save to JSON
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Export complete.")
PYEOF

# 4. Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Permission fix
chmod 666 /tmp/task_result.json