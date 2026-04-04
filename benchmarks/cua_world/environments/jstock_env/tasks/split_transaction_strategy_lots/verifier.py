#!/usr/bin/env python3
import json
import os
import tempfile

def verify_split_transaction_strategy_lots(traj, env_info, task_info):
    """
    Verification for splitting AAPL transaction into two strategy lots.
    
    Criteria:
    1. 'buyportfolio.csv' modified after task start.
    2. Exactly two AAPL transaction rows exist.
    3. Total AAPL units sum to 100.
    4. One row has 50 units and comment 'Long Term Hold'.
    5. One row has 50 units and comment 'Short Term Trade'.
    6. Date (Jan 15, 2024) and Price (185.2) preserved for both.
    """
    
    # 1. Setup and load result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment interface error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    portfolio_data = result.get('portfolio_data', {})
    aapl_rows = portfolio_data.get('aapl_rows', [])
    file_modified = result.get('file_modified', False)
    
    score = 0
    feedback = []
    
    # 3. Scoring Logic
    
    # Criterion: File Modification (Anti-Gaming)
    if file_modified:
        score += 10
        feedback.append("Portfolio file modified.")
    else:
        feedback.append("Portfolio file NOT modified.")

    # Criterion: Row Count (Should be 2)
    row_count = len(aapl_rows)
    if row_count == 2:
        score += 20
        feedback.append("Correctly found 2 AAPL transactions.")
    else:
        feedback.append(f"Expected 2 AAPL transactions, found {row_count}.")

    # Criterion: Total Units (Should be 100)
    total_units = sum(row.get('units', 0) for row in aapl_rows)
    if abs(total_units - 100.0) < 0.01:
        score += 10
        feedback.append("Total share count preserved (100).")
    else:
        feedback.append(f"Total share count incorrect: {total_units} (expected 100).")

    # Analyze Rows for Specific Content
    found_long_term = False
    found_short_term = False
    data_integrity_score = 0
    
    # We allow slight variations in comment case or whitespace, but require the core phrase
    # Price/Date strings from CSV might vary slightly in formatting, so be careful
    target_date = "Jan 15, 2024"
    target_price_str = "185.2" 
    
    for row in aapl_rows:
        comment = row.get('comment', '').lower().strip()
        units = row.get('units', 0)
        date = row.get('date', '')
        price = str(row.get('price', ''))
        
        # Check integrity for this row (20 pts total distributed)
        row_integrity = 0
        if date == target_date:
            row_integrity += 5
        if target_price_str in price: # '185.2' in '185.2' or '185.20'
            row_integrity += 5
        data_integrity_score += row_integrity

        # Identify Strategy Lots
        if abs(units - 50.0) < 0.01:
            if "long term hold" in comment:
                found_long_term = True
            elif "short term trade" in comment:
                found_short_term = True

    score += min(data_integrity_score, 20) # Max 20 pts for integrity
    if data_integrity_score < 20:
        feedback.append("Date or Price mismatch in one or more rows.")

    # Criterion: Specific Lots
    if found_long_term:
        score += 20
        feedback.append("Found 'Long Term Hold' lot (50 units).")
    else:
        feedback.append("Missing or incorrect 'Long Term Hold' lot.")

    if found_short_term:
        score += 20
        feedback.append("Found 'Short Term Trade' lot (50 units).")
    else:
        feedback.append("Missing or incorrect 'Short Term Trade' lot.")

    # Pass Threshold
    passed = score >= 80 and found_long_term and found_short_term
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }