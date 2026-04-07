#!/bin/bash
# Export script for Concurrent Job Queue task
# Runs an in-container Python script to verify concurrency behavior using oracledb

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create the verification python script inside the container
# This script simulates two threads to test locking behavior
cat > /tmp/verify_concurrency.py << 'PYEOF'
import oracledb
import threading
import time
import json
import sys

# Configuration
USER = "hr"
PWD = "hr123"
DSN = "localhost:1521/XEPDB1"

result = {
    "procedure_exists": False,
    "compilation_valid": False,
    "functional_test_passed": False,
    "concurrency_test_passed": False,
    "behavior": "unknown",
    "job_claimed": None,
    "execution_time": 0,
    "error": None
}

def get_conn():
    return oracledb.connect(user=USER, password=PWD, dsn=DSN)

def reset_data():
    """Reset all jobs to PENDING"""
    try:
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("UPDATE payment_jobs SET status = 'PENDING', worker_id = NULL")
        conn.commit()
        conn.close()
    except Exception as e:
        print(f"Reset failed: {e}")

def blocking_worker(barrier):
    """
    Worker 1: Locks the top 2 priority jobs and holds them.
    """
    try:
        conn = get_conn()
        cur = conn.cursor()
        # Lock the top 2 jobs (High Priority)
        # We use a standard FOR UPDATE which will lock the rows
        cur.execute("""
            SELECT job_id FROM payment_jobs 
            WHERE status = 'PENDING' 
            ORDER BY priority DESC, job_id ASC 
            FETCH FIRST 2 ROWS ONLY 
            FOR UPDATE
        """)
        rows = cur.fetchall()
        print(f"Blocking Worker: Locked {len(rows)} rows: {[r[0] for r in rows]}")
        
        # Signal that we have the locks
        barrier.wait()
        
        # Hold locks for 3 seconds
        time.sleep(3)
        
        conn.rollback() # Release locks
        conn.close()
    except Exception as e:
        print(f"Blocking worker error: {e}")

def agent_procedure_worker(barrier, result_dict):
    """
    Worker 2: Tries to call the agent's procedure.
    Should SKIP the locked rows and get the 3rd job immediately.
    """
    try:
        conn = get_conn()
        cur = conn.cursor()
        
        # Wait for blocker to acquire locks
        barrier.wait()
        time.sleep(0.5) # Give slight buffer
        
        start_time = time.time()
        
        # Call agent procedure
        o_job_id = cur.var(oracledb.NUMBER)
        o_payload = cur.var(oracledb.STRING)
        
        print("Agent Worker: Calling CLAIM_NEXT_JOB...")
        cur.callproc("CLAIM_NEXT_JOB", ["AGENT_WORKER", o_job_id, o_payload])
        
        end_time = time.time()
        duration = end_time - start_time
        
        result_dict["execution_time"] = duration
        result_dict["job_claimed"] = o_job_id.getvalue()
        
        print(f"Agent Worker: Finished in {duration:.4f}s. Claimed Job: {o_job_id.getvalue()}")
        
        # Check if we waited too long (indicating blocking)
        if duration > 2.0:
            result_dict["behavior"] = "blocked"
        else:
            result_dict["behavior"] = "non_blocking"
            
        conn.close()
    except Exception as e:
        result_dict["error"] = str(e)
        print(f"Agent worker error: {e}")

try:
    # 1. Check if procedure exists and is valid
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT status FROM user_objects WHERE object_name = 'CLAIM_NEXT_JOB' AND object_type = 'PROCEDURE'")
    row = cur.fetchone()
    if row:
        result["procedure_exists"] = True
        result["compilation_valid"] = (row[0] == 'VALID')
    
    if not result["compilation_valid"]:
        print("Procedure invalid or missing")
        with open("/tmp/concurrency_result.json", "w") as f:
            json.dump(result, f)
        sys.exit(0)

    # 2. Functional Test (Single Thread)
    reset_data()
    o_job_id = cur.var(oracledb.NUMBER)
    o_payload = cur.var(oracledb.STRING)
    cur.callproc("CLAIM_NEXT_JOB", ["TEST_WORKER", o_job_id, o_payload])
    
    # Expect Job 1 (Highest priority, oldest)
    if o_job_id.getvalue() == 1:
        result["functional_test_passed"] = True
    else:
        print(f"Functional test failed: Expected Job 1, got {o_job_id.getvalue()}")

    cur.close()
    conn.close()

    # 3. Concurrency Test
    reset_data()
    barrier = threading.Barrier(2)
    
    t1 = threading.Thread(target=blocking_worker, args=(barrier,))
    t2 = threading.Thread(target=agent_procedure_worker, args=(barrier, result))
    
    t1.start()
    t2.start()
    
    t1.join()
    t2.join()
    
    # 4. Analyze Results
    # We reset data, so Jobs 1 & 2 were PENDING.
    # Blocker locked 1 & 2.
    # Agent should have picked Job 3 (next highest).
    # Agent should have finished quickly (< 2s).
    
    if result["behavior"] == "non_blocking" and result["job_claimed"] == 3:
        result["concurrency_test_passed"] = True

except Exception as e:
    result["error"] = str(e)

with open("/tmp/concurrency_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the python script
echo "Running verification script..."
python3 /tmp/verify_concurrency.py

# Extract procedure source code for static analysis
echo "Extracting procedure source..."
oracle_query_raw "SELECT text FROM user_source WHERE name = 'CLAIM_NEXT_JOB' ORDER BY line;" "hr" > /tmp/procedure_source.sql

# Create final result JSON
cat > /tmp/task_result.json << EOJSON
{
    "timestamp": $(date +%s),
    "concurrency_data": $(cat /tmp/concurrency_result.json),
    "source_code_preview": "$(head -n 20 /tmp/procedure_source.sql | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOJSON

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/procedure_source.sql

echo "=== Export Complete ==="
cat /tmp/task_result.json