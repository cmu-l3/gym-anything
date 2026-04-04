#!/usr/bin/env python3
import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_workflow(traj, env_info, task_info):
    """
    Verify the end-to-end investment workflow in JStock.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve Data
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Validation Logic
    metadata = task_info.get('metadata', {})
    expected_deposit = metadata.get('deposit_amount', 2500.0)
    expected_comment = metadata.get('deposit_comment', "Capital Injection")
    expected_symbol = metadata.get('stock_symbol', "TSLA")
    expected_units = metadata.get('buy_units', 10.0)
    expected_price = metadata.get('buy_price', 175.5)
    expected_alert = metadata.get('alert_fall_below', 160.0)

    score = 0
    feedback = []
    task_start_time = result.get('task_start', 0)

    # --- Criteria 1: Deposit (25 pts) ---
    dep_found = result.get('deposit_found', False)
    dep_data = result.get('deposit_data', {})
    dep_ts = result.get('file_timestamps', {}).get('deposit', 0)
    
    if dep_found:
        try:
            amt = float(dep_data.get('amount', '0').replace(',', ''))
            cmt = dep_data.get('comment', '')
            
            # Check modification time
            if dep_ts < task_start_time:
                feedback.append("Deposit file was not modified during task.")
            elif abs(amt - expected_deposit) < 0.01:
                score += 20
                if expected_comment.lower() in cmt.lower():
                    score += 5
                    feedback.append(f"Deposit confirmed: ${amt} '{cmt}'.")
                else:
                    feedback.append(f"Deposit amount correct, but comment '{cmt}' mismatch.")
            else:
                feedback.append(f"Deposit found but amount ${amt} incorrect (expected ${expected_deposit}).")
        except:
            feedback.append("Error parsing deposit data.")
    else:
        feedback.append("No matching deposit found.")

    # --- Criteria 2: Watchlist Addition (20 pts) ---
    wl_found = result.get('watchlist_found', False)
    wl_ts = result.get('file_timestamps', {}).get('watchlist', 0)

    if wl_found:
        if wl_ts >= task_start_time:
            score += 20
            feedback.append(f"{expected_symbol} added to watchlist.")
        else:
            feedback.append("Watchlist file not modified during task.")
    else:
        feedback.append(f"{expected_symbol} not found in watchlist.")

    # --- Criteria 3: Buy Transaction (25 pts) ---
    port_found = result.get('portfolio_found', False)
    port_data = result.get('portfolio_data', {})
    port_ts = result.get('file_timestamps', {}).get('portfolio', 0)

    if port_found:
        try:
            units = float(port_data.get('units', '0'))
            price = float(port_data.get('price', '0'))
            
            if port_ts < task_start_time:
                feedback.append("Portfolio file not modified during task.")
            else:
                match = True
                if abs(units - expected_units) > 0.1:
                    feedback.append(f"Buy units mismatch: Found {units}, expected {expected_units}.")
                    match = False
                if abs(price - expected_price) > 0.1:
                    feedback.append(f"Buy price mismatch: Found {price}, expected {expected_price}.")
                    match = False
                
                if match:
                    score += 25
                    feedback.append("Buy transaction correct.")
                else:
                    score += 10 # Partial credit for creating the transaction
        except:
            feedback.append("Error parsing portfolio data.")
    else:
        feedback.append("Buy transaction not found.")

    # --- Criteria 4: Alert Configuration (30 pts) ---
    # Depends on watchlist being found
    if wl_found:
        wl_data = result.get('watchlist_data', {})
        try:
            fall_below = float(wl_data.get('fall_below', '0'))
            if abs(fall_below - expected_alert) < 0.1:
                score += 30
                feedback.append(f"Alert configured correctly at ${fall_below}.")
            elif fall_below > 0:
                feedback.append(f"Alert set but incorrect value: ${fall_below} (expected ${expected_alert}).")
                score += 10
            else:
                feedback.append("No Fall Below alert set.")
        except:
            feedback.append("Invalid alert value format.")

    # 4. Final Result
    passed = (score == 100)
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }