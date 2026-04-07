#!/usr/bin/env python3
"""
Verifier for Compressed Log Ingestion Task.

Points Distribution (100 total):
1.  External Table Exists (10 pts)
2.  Configuration Correctness (30 pts):
    - Uses PREPROCESSOR clause (20 pts)
    - Points to a .gz file (not uncompressed) (10 pts)
3.  Functional Pipeline (30 pts):
    - Querying the table returns correct row count (5000)
    - This implicitly verifies: OS permissions, Directory object, Shell script validity
4.  Report Accuracy (20 pts):
    - Output file exists and contains reasonable data
5.  Storage Optimization (10 pts):
    - No uncompressed CSV found in the working directory

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compressed_ingestion(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Table Existence (10)
    if result.get("table_exists"):
        score += 10
        feedback.append("Table FIREWALL_LOGS_EXT created (+10).")
    else:
        feedback.append("Table FIREWALL_LOGS_EXT not found.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # 2. Configuration (30)
    # Preprocessor
    if result.get("preprocessor_used"):
        score += 20
        feedback.append("PREPROCESSOR clause used (+20).")
    else:
        feedback.append("PREPROCESSOR clause NOT detected in access parameters.")

    # File target
    location = result.get("location_file", "")
    if location.endswith(".gz") or location.endswith(".GZ"):
        score += 10
        feedback.append(f"Location points to compressed file: {location} (+10).")
    elif location:
        feedback.append(f"Location points to non-gzip file: {location} (0 pts).")
    else:
        feedback.append("No location file defined.")

    # 3. Functional Pipeline (30)
    # If the query worked, it means permissions, directory, and script are all perfect.
    row_count = result.get("row_count", 0)
    expected_count = task_info['metadata'].get("expected_count", 5000)
    
    if result.get("query_success"):
        if row_count == expected_count:
            score += 30
            feedback.append(f"Query successful! Counted {row_count} rows (+30).")
        else:
            score += 15
            feedback.append(f"Query ran but returned {row_count} rows (expected {expected_count}) (+15).")
    else:
        error = result.get("db_error", "Unknown Error")
        feedback.append(f"Query FAILED. This usually means OS permissions or script errors. DB Error: {error}")

    # 4. Report (20)
    if result.get("report_exists"):
        content = result.get("report_content", "")
        # Check for expected IPs/Counts broadly
        if len(content) > 10 and ("192." in content or "10." in content):
            score += 20
            feedback.append("Report file exists and contains data (+20).")
        else:
            score += 5
            feedback.append("Report file exists but content looks empty or invalid (+5).")
    else:
        feedback.append("Report file blocked_report.txt not found.")

    # 5. Storage Optimization (10)
    if not result.get("uncompressed_copy_found"):
        score += 10
        feedback.append("Storage optimized: No uncompressed CSV found (+10).")
    else:
        feedback.append("Uncompressed CSV found in working directory (0 pts - goal was to query compressed).")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }