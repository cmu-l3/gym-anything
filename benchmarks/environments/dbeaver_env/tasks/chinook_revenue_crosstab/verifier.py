#!/usr/bin/env python3
"""
Verifier for chinook_revenue_crosstab task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_revenue_crosstab(traj, env_info, task_info):
    """
    Verifies the Chinook Revenue Crosstab task.
    
    Scoring Criteria (Total 100):
    1. DBeaver Connection (10 pts)
    2. Table Created (15 pts)
    3. Table Schema Correct (15 pts)
    4. Row Count Correct (10 pts)
    5. Data Accuracy (Top Genre Revenue) (15 pts)
    6. Index Created (10 pts)
    7. CSV Exported (15 pts)
    8. SQL Script Saved (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    # 1. DBeaver Connection (10 pts)
    if result.get("db_connection_exists"):
        score += 10
        feedback.append("DBeaver connection 'ChinookCrosstab' found.")
    else:
        feedback.append("Missing DBeaver connection 'ChinookCrosstab'.")

    # 2. Table Created (15 pts)
    if result.get("table_exists"):
        score += 15
        feedback.append("Table 'genre_yearly_revenue' exists.")
    else:
        feedback.append("Table 'genre_yearly_revenue' NOT found.")

    # 3. Table Schema (15 pts)
    if result.get("columns_valid"):
        score += 15
        feedback.append("Table has correct columns (GenreName, Rev_2009...TotalRevenue).")
    elif result.get("table_exists"):
        feedback.append("Table exists but columns are incorrect or missing.")

    # 4. Row Count (10 pts)
    row_count = result.get("row_count", 0)
    gt_genre_count = result.get("ground_truth_genre_count", 25)
    # Allow small variance if they filtered out 0 revenue genres explicitly or implicitly
    if 20 <= row_count <= int(gt_genre_count) + 2:
        score += 10
        feedback.append(f"Row count ({row_count}) is valid.")
    else:
        feedback.append(f"Row count ({row_count}) is unexpected (expected ~{gt_genre_count}).")

    # 5. Data Accuracy (15 pts)
    # Check Top Genre (Rock) Total Revenue
    try:
        agent_total = float(result.get("top_genre_total", 0))
        agent_genre = result.get("top_genre_name", "")
        
        gt_data = result.get("ground_truth_json", [{}])[0]
        gt_total = float(gt_data.get("total_revenue", 826.65))
        
        tolerance = 0.10 # 10%
        
        if agent_genre.lower() == "rock" and abs(agent_total - gt_total) / gt_total < tolerance:
            score += 15
            feedback.append(f"Top genre data accuracy verified (Rock Revenue: {agent_total}).")
        else:
            feedback.append(f"Data accuracy failed. Top Genre: {agent_genre} (Expected Rock), Revenue: {agent_total} (Expected ~{gt_total}).")
            
    except (ValueError, IndexError, TypeError):
        feedback.append("Could not verify data accuracy (invalid format).")

    # 6. Index Created (10 pts)
    if result.get("index_exists"):
        score += 10
        feedback.append("Index 'idx_genre_total_revenue' found.")
    else:
        feedback.append("Index 'idx_genre_total_revenue' NOT found.")

    # 7. CSV Export (15 pts)
    if result.get("csv_exists") and result.get("csv_matches_db"):
        score += 15
        feedback.append("CSV export found and matches DB row count.")
    elif result.get("csv_exists"):
        score += 5
        feedback.append("CSV export found but content/size mismatch.")
    else:
        feedback.append("CSV export file NOT found.")

    # 8. SQL Script (10 pts)
    if result.get("sql_script_exists") and result.get("sql_content_valid"):
        score += 10
        feedback.append("SQL script found with valid content.")
    elif result.get("sql_script_exists"):
        score += 5
        feedback.append("SQL script found but missing required statements (CREATE TABLE/INDEX/CASE).")
    else:
        feedback.append("SQL script NOT found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }