#!/usr/bin/env python3
"""
Verifier for sakila_world_cross_db_revenue_analysis@1
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sakila_world_analysis(traj, env_info, task_info):
    """
    Verifies the Cross-DB Analysis task.
    
    Scoring Breakdown (100 pts):
    1. Table sakila.country_xref created with >= 40 rows: 20 pts
    2. View sakila.v_revenue_demographics created with correct columns: 20 pts
    3. Procedure sakila.sp_continent_report created: 15 pts
    4. Asia Revenue Report CSV (created, timestamp ok, content ok): 20 pts
    5. Per Capita Ranking CSV (created, timestamp ok, content ok): 15 pts
    6. Anti-gaming (Timestamps valid for all artifacts): 10 pts
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    db_objs = result.get("db_objects", {})
    files = result.get("files", {})
    
    score = 0
    feedback = []

    # 1. Verify Mapping Table (20 pts)
    # Expect >= 40 rows (there are about ~109 countries in sakila, overlapping with world)
    if db_objs.get("table_exists") and db_objs.get("table_rows", 0) >= 40:
        score += 20
        feedback.append("Mapping table created successfully.")
    elif db_objs.get("table_exists"):
        score += 5
        feedback.append("Mapping table exists but has too few rows (<40).")
    else:
        feedback.append("Mapping table sakila.country_xref not found.")

    # 2. Verify View (20 pts)
    # Check for existence and critical columns
    required_cols = ["revenue", "population", "gnp", "continent"]
    view_cols = db_objs.get("view_columns", "").lower()
    
    if db_objs.get("view_exists"):
        if all(c in view_cols for c in required_cols):
            score += 20
            feedback.append("Analytical view created with correct columns.")
        else:
            score += 10
            feedback.append("View created but missing some required columns.")
    else:
        feedback.append("View sakila.v_revenue_demographics not found.")

    # 3. Verify Procedure (15 pts)
    if db_objs.get("proc_exists"):
        score += 15
        feedback.append("Stored procedure created.")
    else:
        feedback.append("Stored procedure sakila.sp_continent_report not found.")

    # 4. Verify Asia Report CSV (20 pts)
    asia = files.get("asia_report", {})
    if asia.get("exists") and asia.get("rows", 0) >= 3:
        if asia.get("has_expected_content"):
            score += 20
            feedback.append("Asia revenue report exported successfully.")
        else:
            score += 10
            feedback.append("Asia report exists but content verification failed (expected Asian countries).")
    else:
        feedback.append("Asia revenue report missing or empty.")

    # 5. Verify Ranking CSV (15 pts)
    rank = files.get("ranking_report", {})
    if rank.get("exists") and rank.get("rows", 0) >= 10:
        if rank.get("has_metric_data"):
            score += 15
            feedback.append("Per capita ranking report exported successfully.")
        else:
            score += 10
            feedback.append("Ranking report exists but data format looks incorrect.")
    else:
        feedback.append("Revenue per capita ranking report missing or empty.")

    # 6. Anti-Gaming / Timestamp Check (10 pts)
    # Only award if ALL present files were created during the task
    asia_ok = not asia.get("exists") or asia.get("created_during_task")
    rank_ok = not rank.get("exists") or rank.get("created_during_task")
    
    if asia_ok and rank_ok and (asia.get("exists") or rank.get("exists")):
        score += 10
        feedback.append("Timestamp verification passed.")
    elif not asia.get("exists") and not rank.get("exists"):
        # Don't award timestamp points if nothing was created
        pass
    else:
        feedback.append("Timestamp verification failed: files appear pre-existing.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }