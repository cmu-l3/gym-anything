#!/usr/bin/env python3
"""
Verifier for Partition Exchange Load Optimization.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_partition_exchange(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database verification failed: {result['db_error']}"}

    score = 0
    feedback = []

    # Criteria 1: Data Transfer (30 pts)
    # Initial staging count was ~9000 (300 * 31 days). 
    # Fact partition should now have approximately that number.
    initial_staging = result.get("initial_staging_count", 0)
    current_fact = result.get("fact_partition_count", 0)
    current_staging = result.get("current_staging_count", 0)

    # Tolerance of small count difference if random generation varied slightly, but here we expect exact swap.
    # If Staging was 9300, Fact should be 9300.
    if current_fact > 0 and abs(current_fact - initial_staging) < 100:
        score += 30
        feedback.append("Data successfully loaded into partition.")
    else:
        feedback.append(f"Data load failed. Expected ~{initial_staging} rows in partition, found {current_fact}.")

    # Criteria 2: Exchange Method Used (20 pts)
    # Staging should be empty (or near empty if they did something weird, but exchange swaps with empty partition).
    if current_staging == 0:
        score += 20
        feedback.append("Staging table is empty (indicates successful exchange).")
    else:
        feedback.append(f"Staging table not empty ({current_staging} rows). Did you use INSERT instead of EXCHANGE?")

    # Criteria 3: Global Index Valid (30 pts)
    g_status = result.get("global_index_status", "UNKNOWN")
    if g_status == "VALID":
        score += 30
        feedback.append("Global index IDX_SALES_CUSTOMER is VALID.")
    else:
        feedback.append(f"Global index IDX_SALES_CUSTOMER is {g_status} (Expected VALID). Did you forget 'UPDATE GLOBAL INDEXES'?")

    # Criteria 4: Local Index Valid (10 pts)
    l_status = result.get("local_index_status", "UNKNOWN")
    if l_status == "VALID":
        score += 10
        feedback.append("Local indexes are VALID.")
    else:
        feedback.append("Local indexes have UNUSABLE partitions.")

    # Criteria 5: Staging Index Prepared (10 pts)
    # Check if staging table has indexes (swapped from partition)
    if result.get("staging_index_created"):
        score += 10
        feedback.append("Staging table has indexes (Prerequisite met).")
    else:
        feedback.append("No indexes found on staging table. Exchange usually swaps indexes.")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }