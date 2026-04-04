#!/usr/bin/env python3
"""
Verifier for Chinook Viral Track Analysis task.

Scoring Breakdown:
1. DBeaver Connection (10 pts): Check if 'ChinookViral' exists.
2. Output CSV Existence (10 pts): File exists.
3. Column Structure (15 pts): Headers match requirements.
4. Data Integrity (25 pts): Correct tracks identified (True Positives).
5. Calculation Accuracy (25 pts): Verifies the logic handles NULLs correctly (Left Join vs Inner Join).
6. SQL Script (15 pts): Script file saved.
"""

import json
import base64
import csv
import io
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_viral_track_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy unavailable"}

    # Load Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Connection Check (10 pts)
    if result.get("connection_exists"):
        score += 10
        feedback.append("✅ DBeaver connection 'ChinookViral' verified.")
    else:
        feedback.append("❌ Connection 'ChinookViral' not found in DBeaver.")

    # 2. SQL Script Check (15 pts)
    if result.get("sql_exists"):
        score += 15
        feedback.append("✅ SQL analysis script found.")
        
        # Keyword check (bonus/sanity check)
        try:
            sql_content = base64.b64decode(result.get("sql_content_b64", "")).decode('utf-8').upper()
            if "JOIN" in sql_content and "GROUP BY" in sql_content:
                 feedback.append("   (Script contains expected SQL keywords)")
            else:
                 feedback.append("   (Warning: Script content seems too simple)")
        except:
            pass
    else:
        feedback.append("❌ SQL analysis script not found at expected path.")

    # 3. CSV File Check (10 pts)
    if not result.get("csv_exists"):
        feedback.append("❌ Output CSV file not found.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}
    
    score += 10
    feedback.append("✅ Output CSV file exists.")

    # 4. Column Structure (15 pts)
    if result.get("csv_columns_valid"):
        score += 15
        feedback.append("✅ CSV header structure is correct.")
    else:
        feedback.append("❌ CSV missing required headers (AlbumTitle, TrackName, TrackRevenue, AlbumAvgRevenue, RevenueMultiplier).")

    # Decode CSVs for Data Verification
    try:
        agent_csv_str = base64.b64decode(result.get("csv_content_b64", "")).decode('utf-8')
        gt_csv_str = base64.b64decode(result.get("ground_truth_b64", "")).decode('utf-8')
        
        agent_rows = list(csv.DictReader(io.StringIO(agent_csv_str)))
        gt_rows = list(csv.DictReader(io.StringIO(gt_csv_str)))
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing CSV data: {str(e)}"}

    # 5. Data Integrity (25 pts) - True Positives
    # Check if the top viral track from ground truth is present
    if not gt_rows:
        return {"passed": False, "score": score, "feedback": "Error: Ground truth empty."}

    top_viral_track = gt_rows[0]['TrackName']
    found_top_track = any(r['TrackName'] == top_viral_track for r in agent_rows)

    if found_top_track:
        score += 25
        feedback.append(f"✅ Successfully identified the top viral track: {top_viral_track}.")
    else:
        feedback.append(f"❌ Failed to identify the top viral track: {top_viral_track}.")

    # 6. Calculation Accuracy (25 pts) - Handling Zero Sales
    # We verify the numerical values for the top track.
    # If the user used INNER JOIN instead of LEFT JOIN, the AlbumAvgRevenue will be higher
    # (because 0-sale tracks are excluded), and RevenueMultiplier will be lower.
    
    if found_top_track and len(agent_rows) > 0:
        # Find the agent's row for the top track
        agent_row = next((r for r in agent_rows if r['TrackName'] == top_viral_track), None)
        gt_row = gt_rows[0]
        
        try:
            agent_avg = float(agent_row['AlbumAvgRevenue'])
            gt_avg = float(gt_row['AlbumAvgRevenue'])
            
            # Tolerance for float comparison
            if abs(agent_avg - gt_avg) < 0.1:
                score += 25
                feedback.append("✅ Calculation accuracy verified (correctly handled 0-sale tracks).")
            else:
                feedback.append(f"❌ Calculation mismatch. Expected AvgRevenue: {gt_avg}, Got: {agent_avg}.")
                feedback.append("   (Hint: Did you include tracks with 0 sales in the average? Use LEFT JOIN.)")
        except ValueError:
            feedback.append("❌ Non-numeric values found in results.")

    # Anti-gaming Check
    if not result.get("file_created_during_task"):
        score = 0
        feedback = ["❌ ANTI-GAMING: Output file timestamp indicates it was not created during this session."]

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "\n".join(feedback)
    }