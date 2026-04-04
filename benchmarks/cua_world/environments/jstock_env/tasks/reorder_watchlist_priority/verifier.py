#!/usr/bin/env python3
"""
Verifier for reorder_watchlist_priority task.
Checks if the JStock watchlist CSV has stocks in the correct order.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reorder_watchlist_priority(traj, env_info, task_info):
    """
    Verify the watchlist order.
    Expected: 
      Row 1: MSFT
      Row 2: NVDA
      Row 3: AAPL
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata targets
    metadata = task_info.get('metadata', {})
    target_order = metadata.get('target_order', ["MSFT", "NVDA", "AAPL"])
    
    # 1. Get result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Get the watchlist CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/final_watchlist.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # JStock CSV often starts with "timestamp=X" line, then headers
            lines = f.readlines()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve watchlist CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Parsing the CSV content
    # Look for the header line starting with "Code" or "Symbol"
    header_idx = -1
    for i, line in enumerate(lines):
        if '"Code"' in line or '"Symbol"' in line:
            header_idx = i
            break
    
    if header_idx == -1:
        return {"passed": False, "score": 0, "feedback": "Invalid CSV format: Header not found"}

    # Extract data rows (below header)
    data_rows = []
    try:
        # Use csv module to handle quotes properly
        # Join lines from header onwards
        csv_content = "".join(lines[header_idx:])
        reader = csv.DictReader(csv_content.splitlines())
        for row in reader:
            data_rows.append(row)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"CSV parsing error: {str(e)}"}

    if not data_rows:
        return {"passed": False, "score": 0, "feedback": "Watchlist is empty"}

    # Evaluate Order
    score = 0
    feedback = []
    
    # Criterion 1: File Modified (Anti-gaming) (10 pts)
    if result_data.get("file_modified", False):
        score += 10
        feedback.append("File modification detected.")
    else:
        feedback.append("Warning: File timestamp indicates no save occurred.")

    # Criterion 2: Integrity check (10 pts)
    # Check if all original stocks are present (AAPL, MSFT, GOOGL, AMZN, NVDA)
    # Just checking symbols broadly
    current_symbols = [row.get('Code', '').strip() for row in data_rows]
    required = {"AAPL", "MSFT", "GOOGL", "AMZN", "NVDA"}
    present = set(current_symbols)
    if required.issubset(present):
        score += 10
        feedback.append("All required stocks are present.")
    else:
        missing = required - present
        feedback.append(f"Missing stocks: {missing}")

    # Criterion 3, 4, 5: Correct Rankings (80 pts total)
    # Rank 1: MSFT (30 pts)
    # Rank 2: NVDA (30 pts)
    # Rank 3: AAPL (20 pts)
    
    # Get top 3 symbols found
    top_3_found = current_symbols[:3] if len(current_symbols) >= 3 else current_symbols
    
    # Check Rank 1
    if len(top_3_found) > 0 and top_3_found[0] == target_order[0]:
        score += 30
        feedback.append(f"Rank 1 Correct: {target_order[0]}")
    else:
        actual = top_3_found[0] if len(top_3_found) > 0 else "None"
        feedback.append(f"Rank 1 Incorrect: Expected {target_order[0]}, found {actual}")

    # Check Rank 2
    if len(top_3_found) > 1 and top_3_found[1] == target_order[1]:
        score += 30
        feedback.append(f"Rank 2 Correct: {target_order[1]}")
    else:
        actual = top_3_found[1] if len(top_3_found) > 1 else "None"
        feedback.append(f"Rank 2 Incorrect: Expected {target_order[1]}, found {actual}")

    # Check Rank 3
    if len(top_3_found) > 2 and top_3_found[2] == target_order[2]:
        score += 20
        feedback.append(f"Rank 3 Correct: {target_order[2]}")
    else:
        actual = top_3_found[2] if len(top_3_found) > 2 else "None"
        feedback.append(f"Rank 3 Incorrect: Expected {target_order[2]}, found {actual}")

    passed = (score == 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }