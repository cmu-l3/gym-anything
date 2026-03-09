#!/usr/bin/env python3
import json
import os
import csv
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_flag_tax_loss_harvesting(traj, env_info, task_info):
    """
    Verify that the user identified the worst performing stock (INTC)
    and added the comment "Harvest Loss".
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_symbol = metadata.get('target_symbol', 'INTC')
    required_comment = metadata.get('required_comment', 'Harvest Loss')

    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Retrieve Portfolio CSV
    if not result_data.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found. Did you save the portfolio?"}

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/result_portfolio.csv", temp_csv.name)
        
        # Parse CSV
        rows = []
        with open(temp_csv.name, 'r', newline='', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read portfolio CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Evaluation Logic
    score = 0
    feedback = []
    
    target_found = False
    target_correctly_flagged = False
    false_positives = False
    data_integrity_violation = False
    
    # Pre-defined initial values to check integrity
    initial_values = {
        "NVDA": {"units": "10.0", "price": "400.0"},
        "AMD":  {"units": "20.0", "price": "100.0"},
        "INTC": {"units": "100.0", "price": "50.0"},
        "TSM":  {"units": "30.0", "price": "120.0"}
    }

    for row in rows:
        symbol = row.get('Code', '')
        comment = row.get('Comment', '')
        units = row.get('Units', '')
        price = row.get('Purchase Price', '')

        # Check Data Integrity (10 pts)
        if symbol in initial_values:
            expected = initial_values[symbol]
            # Simple string comparison sufficient as we pre-populated them
            if units != expected['units'] or price != expected['price']:
                data_integrity_violation = True
                feedback.append(f"Data integrity mismatch for {symbol}: Expected {expected['units']}@{expected['price']}, got {units}@{price}")

        # Check Target (40 pts + 30 pts)
        if symbol == target_symbol:
            target_found = True
            if required_comment.lower() in comment.lower():
                target_correctly_flagged = True
                score += 70 # 40 for ID + 30 for Comment
                feedback.append(f"Correctly flagged target {symbol}.")
            else:
                feedback.append(f"Target {symbol} found but comment was '{comment}' (expected '{required_comment}').")
        
        # Check False Positives (20 pts)
        elif required_comment.lower() in comment.lower():
            false_positives = True
            feedback.append(f"Incorrectly flagged {symbol} as harvest candidate.")

    # Scoring
    if not target_found:
        feedback.append(f"Target stock {target_symbol} not found in portfolio.")
    
    if not false_positives:
        score += 20
    else:
        feedback.append("Penalty: False positives detected.")

    if not data_integrity_violation:
        score += 10
    else:
        feedback.append("Penalty: Financial data (units/price) was modified.")

    # Check file modification timestamp (Anti-gaming)
    if not result_data.get('file_modified'):
        score = 0
        feedback = ["File was not modified during the task session."]

    return {
        "passed": score >= 100,
        "score": score,
        "feedback": " ".join(feedback)
    }