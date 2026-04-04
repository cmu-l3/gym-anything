#!/usr/bin/env python3
"""
Verifier for extract_inactive_customers task.
Verifies that the agent created a table 'InactiveCustomers' with correct data.
"""

import json
import sqlite3
import re
import os
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_inactive_customers(traj, env_info, task_info):
    """
    Verifies the task by:
    1. Calculating ground truth from the original SQLite database.
    2. Parsing the HSQLDB INSERT statements extracted from the Agent's ODB file.
    3. Comparing the Agent's table content to the Ground Truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # --- 1. Retrieve Artifacts from Container ---
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_extracted_rows = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
    temp_ground_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.sqlite').name

    try:
        # Get result JSON
        copy_from_env("/tmp/task_result.json", temp_result_json)
        with open(temp_result_json, 'r') as f:
            result_data = json.load(f)

        # Get extracted rows (SQL INSERT statements)
        if os.path.exists(temp_extracted_rows):
            os.unlink(temp_extracted_rows) # clear before copy
        copy_from_env(result_data.get("extracted_rows_path", "/tmp/extracted_rows.txt"), temp_extracted_rows)

        # Get Ground Truth SQLite DB
        if os.path.exists(temp_ground_truth):
            os.unlink(temp_ground_truth)
        copy_from_env(result_data.get("ground_truth_path", "/tmp/ground_truth.sqlite"), temp_ground_truth)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification artifacts: {e}"}

    # --- 2. Calculate Ground Truth ---
    # Goal: Customers where MAX(InvoiceDate) < '2013-01-01'
    # Columns: CustomerId, FirstName, LastName, Email, LastPurchaseDate, LifetimeValue
    
    expected_rows = {} # Key: CustomerId, Value: Dict
    
    try:
        conn = sqlite3.connect(temp_ground_truth)
        cursor = conn.cursor()
        
        # Calculate last purchase date per customer
        # And filter for those strictly before 2013-01-01
        # SQLite dates in Chinook are strings 'YYYY-MM-DD HH:MM:SS'
        
        query = """
        SELECT 
            c.CustomerId,
            c.FirstName,
            c.LastName,
            c.Email,
            MAX(i.InvoiceDate) as LastPurchaseDate,
            SUM(i.Total) as LifetimeValue
        FROM Customer c
        JOIN Invoice i ON c.CustomerId = i.CustomerId
        GROUP BY c.CustomerId
        HAVING LastPurchaseDate < '2013-01-01'
        """
        
        cursor.execute(query)
        gt_data = cursor.fetchall()
        
        for row in gt_data:
            cid, fname, lname, email, last_date, ltv = row
            # Normalize date to YYYY-MM-DD for comparison
            date_str = last_date.split(' ')[0] if last_date else ""
            
            expected_rows[cid] = {
                "FirstName": fname,
                "LastName": lname,
                "Email": email,
                "LastPurchaseDate": date_str,
                "LifetimeValue": float(ltv)
            }
            
        conn.close()
        
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error calculating ground truth: {e}"}

    # --- 3. Parse Agent's Data ---
    # Expected format: INSERT INTO "InactiveCustomers" VALUES(1,'Luís','Gonçalves','luisg@embraer.com.br','2010-03-11 00:00:00.000000000',39.62)
    # Regex to parse values roughly.
    
    agent_rows = {}
    
    try:
        with open(temp_extracted_rows, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
            
        for line in lines:
            # Simple CSV-like parsing inside VALUES(...)
            # This is brittle if strings contain commas/quotes, but Chinook names are simple enough usually.
            # A more robust regex handles quoted strings vs numbers.
            match = re.search(r'VALUES\s*\((.*)\)', line, re.IGNORECASE)
            if match:
                content = match.group(1)
                # Split by comma, respecting single quotes
                # Regex split lookbehind/lookahead is complex, let's use a simple CSV splitter logic
                parts = []
                current = ""
                in_quote = False
                for char in content:
                    if char == "'" and (len(current) == 0 or current[-1] != '\\'): # Simple quote check
                        in_quote = not in_quote
                        continue # Don't keep quotes
                    if char == ',' and not in_quote:
                        parts.append(current.strip())
                        current = ""
                    else:
                        current += char
                parts.append(current.strip())
                
                # Check column count (should be 6)
                if len(parts) >= 6:
                    try:
                        cid = int(parts[0])
                        fname = parts[1]
                        lname = parts[2]
                        email = parts[3]
                        raw_date = parts[4]
                        raw_ltv = parts[5]
                        
                        # Clean up date format
                        # HSQLDB might output '2010-03-11 00:00:00.000000000'
                        date_str = raw_date.split(' ')[0]
                        
                        # Clean up LTV
                        ltv = float(raw_ltv)
                        
                        agent_rows[cid] = {
                            "FirstName": fname,
                            "LastName": lname,
                            "Email": email,
                            "LastPurchaseDate": date_str,
                            "LifetimeValue": ltv
                        }
                    except ValueError:
                        continue # Skip malformed rows

    except Exception as e:
        logger.warning(f"Error parsing agent data: {e}")

    # --- 4. Scoring ---
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Table Creation (20 pts)
    if os.path.exists(temp_extracted_rows) and os.path.getsize(temp_extracted_rows) > 0:
        score += 20
        feedback_parts.append("Table 'InactiveCustomers' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Table 'InactiveCustomers' not found or empty."}

    # Criterion 2: Correct Population & Row Count (30 pts)
    expected_count = len(expected_rows)
    agent_count = len(agent_rows)
    
    if agent_count == expected_count:
        score += 30
        feedback_parts.append(f"Row count correct ({expected_count}).")
    else:
        feedback_parts.append(f"Row count mismatch: Expected {expected_count}, Got {agent_count}.")
        # Partial credit for being close
        if abs(agent_count - expected_count) <= 5:
            score += 15

    # Criterion 3: Inactivity Logic (No 2013+ customers) (25 pts)
    # Check if any agent customer actually had a purchase in 2013 (false positives)
    # We need the full ground truth list to check this properly, 
    # but based on expected_rows, if a CID is NOT in expected_rows but IS in agent_rows, it's a False Positive.
    
    false_positives = 0
    false_negatives = 0
    
    for cid in agent_rows:
        if cid not in expected_rows:
            false_positives += 1
            
    for cid in expected_rows:
        if cid not in agent_rows:
            false_negatives += 1
            
    if false_positives == 0:
        score += 25
        feedback_parts.append("Inactivity logic correct (no recent customers included).")
    else:
        feedback_parts.append(f"Included {false_positives} active customers (error in date filter).")

    # Criterion 4: Lifetime Value Accuracy (15 pts)
    ltv_errors = 0
    for cid, data in agent_rows.items():
        if cid in expected_rows:
            expected_ltv = expected_rows[cid]["LifetimeValue"]
            actual_ltv = data["LifetimeValue"]
            if abs(expected_ltv - actual_ltv) > 0.05: # Float tolerance
                ltv_errors += 1
    
    if ltv_errors == 0 and agent_count > 0:
        score += 15
        feedback_parts.append("Lifetime values accurate.")
    elif agent_count > 0:
        feedback_parts.append(f"{ltv_errors} value calculation errors.")
        if ltv_errors < agent_count / 2:
            score += 7

    # Criterion 5: Last Purchase Date Accuracy (10 pts)
    date_errors = 0
    for cid, data in agent_rows.items():
        if cid in expected_rows:
            # Compare YYYY-MM-DD
            if data["LastPurchaseDate"] != expected_rows[cid]["LastPurchaseDate"]:
                date_errors += 1

    if date_errors == 0 and agent_count > 0:
        score += 10
        feedback_parts.append("Dates accurate.")
    elif agent_count > 0:
        feedback_parts.append(f"{date_errors} date errors.")

    # Cleanup
    for f in [temp_result_json, temp_extracted_rows, temp_ground_truth]:
        if os.path.exists(f):
            os.unlink(f)

    # Final Pass Decision
    # Threshold 75, and MUST strictly obey logic (false_positives == 0)
    passed = (score >= 75) and (false_positives == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }