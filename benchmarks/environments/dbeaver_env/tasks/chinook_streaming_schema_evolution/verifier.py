#!/usr/bin/env python3
"""
Verifier for chinook_streaming_schema_evolution task.

Criteria:
1. DBeaver Connection 'ChinookStreaming' exists (10 pts)
2. 'subscription_plans' table exists with 3 correct rows (30 pts)
3. 'customers' table altered with SubscriptionPlanId (10 pts)
4. 'tracks' table altered with PlayCount (10 pts)
5. 'listening_history' table exists (15 pts)
6. Two indexes created (10 pts)
7. Migration SQL script saved (15 pts)

Anti-gaming: DB must be modified after task start.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_streaming_schema_evolution(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # Check 1: Anti-gaming - DB modified
    if not result.get("db_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Database file was not modified. No changes persisted."
        }

    # Check 2: DBeaver Connection (10 pts)
    if result.get("connection_exists", False):
        score += 10
        feedback.append("DBeaver connection 'ChinookStreaming' created.")
    else:
        feedback.append("Connection 'ChinookStreaming' not found in DBeaver config.")

    # Check 3: Subscription Plans Table & Data (30 pts)
    # 15 for table existence, 15 for data
    if result.get("table_subscription_plans", False):
        score += 15
        data_count = result.get("plan_data_match_count", 0)
        if data_count == 3:
            score += 15
            feedback.append("Table 'subscription_plans' created with correct data.")
        else:
            partial = int((data_count / 3) * 15)
            score += partial
            feedback.append(f"Table 'subscription_plans' exists but data mismatch ({data_count}/3 rows).")
    else:
        feedback.append("Table 'subscription_plans' not found.")

    # Check 4: Customers Alteration (10 pts)
    if result.get("column_subscription_plan_id", False):
        # Verify defaults were applied (data integrity)
        total = result.get("cust_total_count", 0)
        match = result.get("cust_default_match_count", 0)
        if total > 0 and match == total:
            score += 10
            feedback.append("Column 'SubscriptionPlanId' added to customers with correct default.")
        else:
            score += 5
            feedback.append("Column 'SubscriptionPlanId' added but default values not fully applied.")
    else:
        feedback.append("Column 'SubscriptionPlanId' not found in customers.")

    # Check 5: Tracks Alteration (10 pts)
    if result.get("column_play_count", False):
        total = result.get("track_total_count", 0)
        match = result.get("track_default_match_count", 0)
        if total > 0 and match == total:
            score += 10
            feedback.append("Column 'PlayCount' added to tracks with correct default.")
        else:
            score += 5
            feedback.append("Column 'PlayCount' added but default values not fully applied.")
    else:
        feedback.append("Column 'PlayCount' not found in tracks.")

    # Check 6: Listening History Table (15 pts)
    if result.get("table_listening_history", False):
        score += 15
        feedback.append("Table 'listening_history' created.")
    else:
        feedback.append("Table 'listening_history' not found.")

    # Check 7: Indexes (10 pts)
    idx_score = 0
    if result.get("index_customer", False): idx_score += 5
    if result.get("index_track", False): idx_score += 5
    score += idx_score
    if idx_score == 10:
        feedback.append("Performance indexes created.")
    elif idx_score > 0:
        feedback.append("Some indexes missing.")
    else:
        feedback.append("Performance indexes not found.")

    # Check 8: Migration Script (15 pts)
    if result.get("script_exists", False):
        size = result.get("script_size", 0)
        if size > 100: # Arbitrary small threshold for non-empty script
            score += 15
            feedback.append("Migration script saved.")
        else:
            score += 5
            feedback.append("Migration script file exists but is empty/too small.")
    else:
        feedback.append("Migration script not found.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }