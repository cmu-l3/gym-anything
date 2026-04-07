#!/usr/bin/env python3
"""
Verifier for Sakila Inventory Demand Analysis Task

Verifies:
1. v_july_2005_utilization View exists.
2. View/Export logic handles business rules:
   - Filters July 2005.
   - Handles negative dates (excludes or counts as 0).
   - Handles NULL dates (counts as 24h).
   - Calculates utilization % correctly.
3. CSV file exists and matches Ground Truth data.
"""

import json
import logging
import os
import tempfile
import csv
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_mysql_output(raw_text):
    """Parses tab-separated MySQL output into a list of dicts."""
    lines = raw_text.strip().split('\n')
    if not lines:
        return []
    headers = lines[0].split('\t')
    data = []
    for line in lines[1:]:
        values = line.split('\t')
        if len(values) == len(headers):
            row = dict(zip(headers, values))
            data.append(row)
    return data

def parse_csv_content(raw_text):
    """Parses CSV content into list of dicts."""
    try:
        f = io.StringIO(raw_text)
        reader = csv.DictReader(f)
        return list(reader)
    except Exception as e:
        logger.warning(f"Failed to parse CSV: {e}")
        return []

def verify_sakila_inventory_demand_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    passed = False

    # 1. View Creation (20 pts)
    if result.get('view_exists'):
        score += 20
        feedback.append("View 'v_july_2005_utilization' created.")
    else:
        feedback.append("View 'v_july_2005_utilization' NOT found.")

    # 2. CSV Existence & Timestamp (10 pts)
    csv_exists = result.get('csv_exists')
    csv_mtime = result.get('csv_mtime', 0)
    task_start = result.get('task_start', 0)
    
    if csv_exists and csv_mtime > task_start:
        score += 10
        feedback.append("CSV export created during task.")
    elif csv_exists:
        score += 5
        feedback.append("CSV export exists but timestamp is suspicious (pre-task?).")
    else:
        feedback.append("CSV export NOT found.")

    # 3. Data Accuracy Check (70 pts total)
    # We compare the User's CSV (or View output if CSV failed) against Ground Truth
    
    ground_truth = parse_mysql_output(result.get('ground_truth_raw', ''))
    user_csv_data = parse_csv_content(result.get('user_csv_raw', ''))
    user_view_data = parse_mysql_output(result.get('user_view_raw', ''))
    
    # Prefer CSV for checking final output, fallback to view for partial credit
    user_data = user_csv_data if user_csv_data else user_view_data
    source_name = "CSV" if user_csv_data else ("View" if user_view_data else "None")

    if not ground_truth:
        return {"passed": False, "score": score, "feedback": "Verifier Error: Could not generate ground truth."}

    if not user_data:
        feedback.append("No data found in CSV or View to verify accuracy.")
    else:
        # Check Top 3 Items match
        matches = 0
        top_n = 30
        gt_titles = {row['title'].lower(): row for row in ground_truth[:top_n]}
        
        # Check specific logic indicators
        # We look at the actual values calculated
        
        valid_entries = 0
        total_error = 0.0
        
        for row in user_data[:top_n]:
            # Normalize keys (handling potential header differences)
            # User headers might be 'title', 'Title', 'utilization_pct', etc.
            title_key = next((k for k in row.keys() if 'title' in k.lower()), None)
            util_key = next((k for k in row.keys() if 'utilization' in k.lower() or 'pct' in k.lower()), None)
            
            if not title_key or not util_key:
                continue

            title = row[title_key].lower()
            try:
                util = float(row[util_key].replace('%', ''))
            except ValueError:
                continue

            if title in gt_titles:
                matches += 1
                gt_util = float(gt_titles[title]['utilization_pct'])
                error = abs(util - gt_util)
                if error <= 0.5: # Tolerance
                    valid_entries += 1
                else:
                    total_error += error
        
        # Scoring Logic based on data match
        # 20 pts for Calculation Logic (approx by value matching)
        # 20 pts for Data Cleaning (negative dates)
        # 10 pts for NULL handling
        # 20 pts for Data Accuracy (ranking)
        
        # We simplify: if values match closely, logic is likely correct.
        
        accuracy_score = 0
        if matches >= 10:
            accuracy_score += 20 # Good ranking overlap
        
        if valid_entries >= 10:
            accuracy_score += 50 # Values match within tolerance implies correct logic (cleaning + formulas)
        elif valid_entries >= 5:
            accuracy_score += 25 # Partial credit
            
        score += accuracy_score
        
        feedback.append(f"Data Source: {source_name}. Matched {matches}/{top_n} titles. {valid_entries} values within tolerance.")

    passed = (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }