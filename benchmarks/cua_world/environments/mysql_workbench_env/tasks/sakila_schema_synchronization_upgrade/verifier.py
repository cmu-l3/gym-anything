#!/usr/bin/env python3
"""
Verifier for sakila_schema_synchronization_upgrade task.

Evaluates if the agent successfully upgraded the production schema to match
development while preserving data.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_sakila_schema_synchronization_upgrade(traj, env_info, task_info):
    """
    Verify schema synchronization task.

    Scoring (100 points):
    - Schema Sync: Columns (30 pts)
    - Schema Sync: Table (20 pts)
    - Schema Sync: Index (20 pts)
    - Data Preservation (20 pts)
    - Migration Artifact (10 pts)

    CRITICAL FAIL: If data is lost (row counts drop), score is capped at 0.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        try:
            copy_from_env("/tmp/migration_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    score = 0
    feedback_parts = []
    
    # Check Data Preservation FIRST (Anti-Gaming / Safety Check)
    data_preserved = result.get('data_preserved', False)
    final_cust = result.get('final_customer_count', 0)
    final_film = result.get('final_film_count', 0)
    
    if not data_preserved:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL FAILURE: Production data was lost! Customer count: {final_cust}, Film count: {final_film}. Do NOT use DROP TABLE on production."
        }
    
    score += 20
    feedback_parts.append("Data preserved (20/20)")

    # 1. Schema Sync: Columns (30 pts)
    # 15 pts per column
    has_loyalty = result.get('has_loyalty_column', 0) > 0
    has_streaming = result.get('has_streaming_column', 0) > 0
    
    col_score = 0
    if has_loyalty: col_score += 15
    if has_streaming: col_score += 15
    score += col_score
    feedback_parts.append(f"Columns synced ({col_score}/30)")

    # 2. Schema Sync: Table (20 pts)
    if result.get('has_audit_table', 0) > 0:
        score += 20
        feedback_parts.append("Audit table created (20/20)")
    else:
        feedback_parts.append("Audit table missing (0/20)")

    # 3. Schema Sync: Index (20 pts)
    if result.get('has_payment_index', 0) > 0:
        score += 20
        feedback_parts.append("Payment index created (20/20)")
    else:
        feedback_parts.append("Payment index missing (0/20)")

    # 4. Migration Artifact (10 pts)
    if result.get('script_exists', False) and result.get('script_content_valid', False):
        score += 10
        feedback_parts.append("Migration script saved (10/10)")
    elif result.get('script_exists', False):
        score += 5
        feedback_parts.append("Migration script empty/invalid (5/10)")
    else:
        feedback_parts.append("No migration script found (0/10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }