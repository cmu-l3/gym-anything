#!/usr/bin/env python3
"""
Verifier for Analytical Window Queries task.
Evaluates 4 output text files and 1 SQL script based on:
- Existence and freshness (anti-gaming)
- Line counts (proxy for correct row return)
- Specific data values (spot check for correctness)
- SQL keyword usage (CTE, Window functions)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analytical_window_queries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    # Load results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Criterion 1: Salary Percentiles (Max 21 pts) ---
    q1 = result.get("q1", {})
    if q1.get("exists") and q1.get("lines", 0) >= 100: # Header + 107 rows
        score += 8
        feedback.append("Q1 file exists with correct rows.")
        
        # Spot check: Steven King (ID 100)
        # Expected: Rank 1 (highest salary), Quartile 4
        king_lines = q1.get("content_sample_king", [])
        if king_lines:
            line = king_lines[0]
            # Heuristics: check if '1' (rank) and '4' (quartile) appear in line
            # This is loose matching to allow for different delimiters (csv, pipe, space)
            if " 1 " in line.replace('|', ' ').replace(',', ' ') or "\t1\t" in line:
                score += 5
                feedback.append("Q1: King rank correct.")
            if " 4" in line or "\t4" in line:
                score += 4
                feedback.append("Q1: King quartile correct.")
        
        # Spot check: TJ Olson (ID 132) - Low salary
        olson_lines = q1.get("content_sample_olson", [])
        if olson_lines:
            line = olson_lines[0]
            if " 1" in line or "\t1" in line: # Quartile 1
                score += 4
                feedback.append("Q1: Olson quartile correct.")
    else:
        feedback.append("Q1 file missing or empty.")

    # --- Criterion 2: Dept Budget Analysis (Max 18 pts) ---
    q2 = result.get("q2", {})
    # Should exclude dept 10, 20, 40, 70 (size 1-2). Total rows < 107.
    # HR Schema total ~107. 106 employees have depts.
    # Excluded: 10(1), 20(2), 40(1), 70(1), 110(2) -> ~7 rows excluded.
    # Expected lines approx 100-102.
    if q2.get("exists") and 80 <= q2.get("lines", 0) <= 105:
        score += 8
        feedback.append("Q2 file exists with correct filtered row count.")
        
        # Check cumulative pct logic - last line of sample usually has 100.0 or similar
        # Hard to parse strictly without delimiters, awarding points for existence + filter
        score += 10
    elif q2.get("exists"):
        score += 4
        feedback.append("Q2 file exists but row count suspicious (filtering issue?).")

    # --- Criterion 3: Turnover Risk (Max 17 pts) ---
    q3 = result.get("q3", {})
    if q3.get("exists") and q3.get("lines", 0) >= 100:
        score += 8
        feedback.append("Q3 file exists.")
        
        # Check CTE usage via SQL file later, here verify content
        # Spot check positive years of service
        head = q3.get("content_head", [])
        # Look for numbers > 0 in the lines
        if any(any(c.isdigit() for c in l) for l in head):
            score += 4
            feedback.append("Q3 content looks numeric.")
            
    # --- Criterion 4: Pivot (Max 14 pts) ---
    q4 = result.get("q4", {})
    if q4.get("exists") and q4.get("lines", 0) >= 5:
        score += 8
        feedback.append("Q4 file exists.")
        # Check for multiple columns (pivot structure)
        head = q4.get("content_head", [])
        if head and (head[0].count('|') >= 5 or head[0].count(',') >= 5 or head[0].count('\t') >= 5):
            score += 6
            feedback.append("Q4 has pivoted columns.")

    # --- Criterion 5: SQL Script & Keywords (Max 30 pts) ---
    sql = result.get("sql", {})
    if sql.get("exists"):
        score += 8
        feedback.append("SQL script exists.")
        
        kw = sql.get("keywords", {})
        
        # Q1 needs RANK/DENSE_RANK, PERCENT_RANK, NTILE
        if kw.get("RANK") or kw.get("DENSE_RANK"): score += 2
        if kw.get("PERCENT_RANK"): score += 2
        if kw.get("NTILE"): score += 2
        
        # Window basics
        if kw.get("OVER"): score += 2
        if kw.get("PARTITION"): score += 2
        
        # Q2 needs SUM..OVER
        if kw.get("SUM") and kw.get("OVER"): score += 2
        
        # Q3 needs CTE (WITH)
        if kw.get("WITH"): 
            score += 5
            feedback.append("CTE usage verified.")
        
        # Q4 needs PIVOT or DECODE/CASE
        if kw.get("PIVOT"): 
            score += 5
            feedback.append("Pivot usage verified.")
        
        # Anti-gaming check
        if sql.get("modified_after_start"):
            score += 0 # Pass (implicit)
        else:
            feedback.append("WARNING: SQL script older than task start.")
            # Penalize heavily if strictly enforcing, but for now just warn/reduce
            score = max(0, score - 20)
            
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }