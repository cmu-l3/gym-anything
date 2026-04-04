#!/usr/bin/env python3
"""
Verifier for Chinook ABC Inventory Classification Task.
"""

import json
import logging
import os
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_abc_inventory_classification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed (copy_from_env missing)"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. Connection Check (10 pts)
    if data.get("connection_found"):
        score += 10
        feedback.append("✅ DBeaver connection 'Chinook' found.")
    else:
        feedback.append("❌ DBeaver connection 'Chinook' not found in config.")

    # 2. Database Artifacts (Table Existence & Schema) (20 pts)
    if data.get("table_exists"):
        score += 10
        feedback.append("✅ Table 'track_abc_classification' exists.")
        if data.get("columns_valid"):
            score += 10
            feedback.append("✅ Table schema contains required columns.")
        else:
            feedback.append("⚠️ Table exists but is missing required columns (TrackId, CumulativePct, etc).")
    else:
        feedback.append("❌ Table 'track_abc_classification' was not created in the database.")

    # 3. Data Accuracy (30 pts)
    # Compare agent stats vs ground truth
    agent_stats = data.get("agent_stats", {})
    gt = data.get("ground_truth", {})
    
    # Revenue Check
    agent_rev = float(agent_stats.get("total_revenue", 0))
    gt_rev = float(gt.get("total_revenue", 0))
    if gt_rev > 0 and math.isclose(agent_rev, gt_rev, rel_tol=0.01):
        score += 10
        feedback.append(f"✅ Total revenue matches ground truth (${agent_rev:.2f}).")
    else:
        feedback.append(f"❌ Total revenue mismatch (Agent: ${agent_rev:.2f}, GT: ${gt_rev:.2f}).")

    # Category Counts Check
    # We allow some flexibility because boundary handling (inclusive vs exclusive) might vary slightly
    # But A/B/C proportions should be roughly correct.
    # Typically: A is few items, C is many.
    
    # Basic logic: Check if categories exist
    if agent_stats.get("count_a", 0) > 0 and agent_stats.get("count_b", 0) > 0 and agent_stats.get("count_c", 0) > 0:
        score += 10
        feedback.append("✅ All ABC categories populated.")
        
        # Check specific distribution (loose tolerance)
        a_diff = abs(agent_stats["count_a"] - gt.get("count_a", 0))
        if a_diff <= 5: # Allow small variance for boundary items
             score += 10
             feedback.append("✅ ABC distribution counts match ground truth accurately.")
        else:
             feedback.append(f"⚠️ ABC counts diverge from expected (Agent A: {agent_stats['count_a']}, GT A: {gt.get('count_a', 0)}). Boundary logic may differ.")
             score += 5 # Partial credit
    else:
        feedback.append("❌ Missing data for one or more ABC categories.")

    # 4. File Exports (40 pts)
    files = data.get("files", {})
    
    # Detailed CSV
    if files.get("detailed_csv") == "created":
        score += 15
        feedback.append("✅ Detailed CSV export created successfully.")
    elif files.get("detailed_csv") == "exists_old":
         feedback.append("❌ Detailed CSV exists but is old (pre-task).")
    else:
         feedback.append("❌ Detailed CSV export missing.")

    # Summary CSV
    if files.get("summary_csv") == "created":
        score += 15
        feedback.append("✅ Summary CSV report created successfully.")
    else:
        feedback.append("❌ Summary CSV report missing.")

    # SQL Script
    if files.get("sql_script") == "created":
        score += 10
        feedback.append("✅ SQL analysis script saved.")
    else:
        feedback.append("❌ SQL script missing.")

    # Final Evaluation
    if score >= 60 and data.get("table_exists") and files.get("detailed_csv") == "created":
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }