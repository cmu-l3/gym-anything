#!/usr/bin/env python3
"""
Verifier for chinook_northwind_market_overlap task.
Checks database connections, created analysis database structure, data accuracy, and export files.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_market_overlap(traj, env_info, task_info):
    """
    Score the market overlap analysis task.
    """
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
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Database Connections (16 pts)
    conns = result.get('connections', {})
    if conns.get('chinook'):
        score += 8
        feedback.append("Chinook connection created")
    else:
        feedback.append("Missing Chinook connection")
        
    if conns.get('northwind'):
        score += 8
        feedback.append("Northwind connection created")
    else:
        feedback.append("Missing Northwind connection")

    # 2. Analysis Database & Tables (35 pts)
    db = result.get('database', {})
    if db.get('exists'):
        score += 5
        feedback.append("Analysis DB created")
        
        tables = db.get('tables', {})
        if tables.get('chinook_stats'):
            score += 10
            feedback.append("chinook_country_stats table found")
        
        if tables.get('northwind_stats'):
            score += 10
            feedback.append("northwind_country_stats table found")
            
        if tables.get('overlap'):
            score += 10
            feedback.append("market_overlap table found")
    else:
        feedback.append("Missing market_analysis.db")

    # 3. Data Accuracy & Logic (29 pts)
    # Check row counts and revenue
    overlap_rows = db.get('overlap_row_count', 0)
    uk_norm = db.get('uk_normalization_detected', False)
    
    # Overlap should be around 15-22 countries depending on matching stringency
    if 15 <= overlap_rows <= 22:
        score += 12
        feedback.append(f"Overlap row count correct ({overlap_rows})")
    elif overlap_rows > 0:
        score += 5
        feedback.append(f"Overlap row count partial ({overlap_rows}) - check country matching")
    else:
        feedback.append("Overlap table empty")

    # Check UK Normalization
    if uk_norm:
        score += 7
        feedback.append("UK/United Kingdom normalization detected")
    else:
        # If row count is high enough, they might have matched it under a different name or handled it manually
        if overlap_rows >= 16:
            score += 7
            feedback.append("Implicit normalization detected via row count")
        else:
            feedback.append("UK/United Kingdom match likely missing")

    # Check Top Revenue Country (Should be USA/US)
    top_country = db.get('top_country', '').lower()
    if 'usa' in top_country or 'united states' in top_country or 'us' == top_country:
        score += 10
        feedback.append("Top revenue country identified correctly (USA)")
    elif top_country:
        feedback.append(f"Wrong top country: {top_country} (Expected USA)")

    # 4. CSV Export (15 pts)
    csv = result.get('csv', {})
    if csv.get('exists') and csv.get('created_during_task'):
        if csv.get('rows', 0) >= 15 and csv.get('cols', 0) >= 7:
            score += 15
            feedback.append("CSV exported correctly")
        else:
            score += 7
            feedback.append("CSV exists but content format/size incorrect")
    elif csv.get('exists'):
        score += 5
        feedback.append("CSV exists but timestamp invalid (pre-existing?)")
    else:
        feedback.append("Missing CSV export")

    # 5. SQL Script (5 pts)
    sql = result.get('sql_script', {})
    if sql.get('exists') and sql.get('size', 0) > 50:
        score += 5
        feedback.append("SQL script saved")
    else:
        feedback.append("Missing or empty SQL script")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": ", ".join(feedback)
    }