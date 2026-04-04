#!/usr/bin/env python3
import json
import base64
import csv
import io
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_portfolio_with_transaction(traj, env_info, task_info):
    """
    Verifies that the user created a new portfolio 'Retirement Fund' and added the TSLA transaction.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # Extract expectations
    metadata = task_info.get('metadata', {})
    expected_symbol = metadata.get('expected_symbol', 'TSLA')
    expected_units = metadata.get('expected_units', 40.0)
    expected_price = metadata.get('expected_price', 171.05)
    expected_date = metadata.get('expected_date_str', 'Mar 15, 2024')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Check if Portfolio Directory Exists (20 pts)
    if not result.get('portfolio_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "The 'Retirement Fund' portfolio was not created."
        }
    score += 20
    feedback.append("Portfolio 'Retirement Fund' created.")

    # 2. Anti-gaming: Check Timestamps (15 pts)
    # Ensure directory/file was created AFTER task start
    task_start = result.get('task_start_time', 0)
    dir_time = result.get('portfolio_dir_ctime', 0)
    csv_time = result.get('csv_mtime', 0)
    
    # Allow small clock skew or file system delays, but generally time > start
    if dir_time >= task_start or csv_time >= task_start:
        score += 15
        feedback.append("Portfolio created during task session.")
    else:
        feedback.append("Warning: Portfolio appears to be pre-existing (timestamp check failed).")

    # 3. Parse New Portfolio CSV Content
    csv_b64 = result.get('csv_content_b64', '')
    if not csv_b64:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback) + " | Portfolio is empty (no buyportfolio.csv found)."
        }

    try:
        csv_str = base64.b64decode(csv_b64).decode('utf-8')
        csv_reader = csv.DictReader(io.StringIO(csv_str))
        rows = list(csv_reader)
    except Exception as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Failed to parse portfolio data: {str(e)}"
        }

    # 4. Validate Transaction Details (40 pts total)
    target_found = False
    
    for row in rows:
        # JStock CSV columns: "Code","Symbol","Date","Units","Purchase Price", etc.
        # Check Symbol (TSLA)
        row_code = row.get('Code', '').upper()
        row_symbol = row.get('Symbol', '').upper()
        
        if expected_symbol in row_code or expected_symbol in row_symbol:
            target_found = True
            
            # Check Units (10 pts)
            try:
                units = float(row.get('Units', 0))
                if abs(units - expected_units) < 0.01:
                    score += 10
                    feedback.append(f"Correct units ({units}).")
                else:
                    feedback.append(f"Incorrect units: found {units}, expected {expected_units}.")
            except:
                feedback.append("Invalid units format.")

            # Check Price (10 pts)
            try:
                price = float(row.get('Purchase Price', 0))
                if abs(price - expected_price) < 0.01:
                    score += 10
                    feedback.append(f"Correct price ({price}).")
                else:
                    feedback.append(f"Incorrect price: found {price}, expected {expected_price}.")
            except:
                feedback.append("Invalid price format.")
                
            # Check Date (10 pts)
            row_date = row.get('Date', '')
            if row_date == expected_date:
                score += 10
                feedback.append(f"Correct date ({row_date}).")
            else:
                feedback.append(f"Incorrect date: found '{row_date}', expected '{expected_date}'.")
                
            # Found the target, stop looking
            break
    
    if target_found:
        score += 10 # Base points for finding the symbol
        feedback.append(f"Transaction for {expected_symbol} found.")
    else:
        feedback.append(f"No transaction for {expected_symbol} found in 'Retirement Fund'.")

    # 5. Check Default Portfolio Integrity (10 pts)
    # Ensure "My Portfolio" still contains original data (AAPL, MSFT, NVDA)
    default_b64 = result.get('default_portfolio_content_b64', '')
    if default_b64:
        default_str = base64.b64decode(default_b64).decode('utf-8')
        if "AAPL" in default_str and "MSFT" in default_str:
            score += 10
            feedback.append("Default 'My Portfolio' remains intact.")
        else:
            feedback.append("Warning: 'My Portfolio' seems to have been modified or corrupted.")
    else:
        feedback.append("Warning: Could not read 'My Portfolio'.")

    passed = (score >= 85) # Needs almost everything correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }