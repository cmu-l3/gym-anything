#!/usr/bin/env python3
"""
Verifier for bi_query_rewrite_acceleration task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bi_query_rewrite(traj, env_info, task_info):
    """
    Verifies that the agent created a Materialized View that accelerates
    the target query via Query Rewrite.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. MV Exists (20 pts)
    if result.get("mv_exists"):
        score += 20
        mv_name = result.get("mv_name")
        feedback_parts.append(f"Materialized View '{mv_name}' found (+20)")
    else:
        feedback_parts.append("No Materialized View found in SH_LITE schema")

    # 2. Rewrite Enabled (20 pts)
    if result.get("rewrite_enabled"):
        score += 20
        feedback_parts.append("Query Rewrite is enabled on the MV (+20)")
    elif result.get("mv_exists"):
        feedback_parts.append("MV exists but REWRITE_ENABLED is 'N' (0 pts)")

    # 3. Rewrite Verification (30 pts)
    # This checks if EXPLAIN PLAN on the ORIGINAL query uses the MV
    if result.get("rewrite_verified"):
        score += 30
        feedback_parts.append("Optimizer successfully rewrites the query to use the MV (+30)")
    else:
        feedback_parts.append("Optimizer did NOT choose to rewrite the query (check stats, freshness, or MV definition)")

    # 4. Performance Check (10 pts)
    # If rewrite happened, cost should be lower. 
    base_cost = result.get("base_cost", 0)
    rewrite_cost = result.get("rewrite_cost", 0)
    if result.get("rewrite_verified") and rewrite_cost < base_cost:
        score += 10
        feedback_parts.append(f"Performance improved (Cost: {base_cost} -> {rewrite_cost}) (+10)")
    
    # 5. Proof File (10 pts)
    if result.get("proof_file_exists"):
        score += 10
        feedback_parts.append("Evidence file found (+10)")
    else:
        feedback_parts.append("Optimization proof file not found")

    # 6. MV Freshness (10 pts)
    # If it rewrote, it must be fresh, but let's give points for explicit freshness
    mv_status = result.get("mv_status")
    if mv_status == 'FRESH':
        score += 10
        feedback_parts.append("MV is FRESH (+10)")
    elif result.get("rewrite_verified"):
         # If it rewrote, we assume it's good enough
         score += 10
         feedback_parts.append("MV valid for rewrite (+10)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }