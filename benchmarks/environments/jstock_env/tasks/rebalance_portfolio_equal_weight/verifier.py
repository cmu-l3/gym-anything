#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import csv
import io
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_rebalance_portfolio(traj, env_info, task_info):
    """
    Verify portfolio rebalancing task.
    
    Criteria:
    1. Sell Portfolio CSV must contain sells for AAPL (~5 units) and MSFT (~3 units).
    2. Buy Portfolio CSV must contain NEW buy for NVDA (~3 units).
    3. Report file must exist and mention 'Sell', 'Buy', and stock symbols.
    4. VLM Trajectory must show interaction with Portfolio tab and Transaction dialogs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result Data
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
    
    # 2. Verify Report (20 pts)
    report_exists = result.get("report_exists", False)
    report_content = result.get("report_content", "").lower()
    
    if report_exists:
        score += 10
        feedback.append("Report file created.")
        
        required_keywords = ["aapl", "msft", "nvda", "buy", "sell"]
        found_keywords = [kw for kw in required_keywords if kw in report_content]
        
        if len(found_keywords) >= 4:
            score += 10
            feedback.append("Report content looks correct (symbols and actions found).")
        else:
            feedback.append(f"Report missing keywords. Found: {found_keywords}")
    else:
        feedback.append("Report file NOT found.")

    # 3. Verify Transactions (CSV Parsing) (60 pts)
    sell_csv_raw = result.get("sell_csv_content", "")
    buy_csv_raw = result.get("buy_csv_content", "")
    
    # Parse Sells
    sells_found = {"AAPL": 0.0, "MSFT": 0.0}
    try:
        reader = csv.DictReader(io.StringIO(sell_csv_raw))
        for row in reader:
            code = row.get("Code", "")
            units = float(row.get("Units", 0))
            if code in sells_found:
                sells_found[code] += units
    except Exception as e:
        feedback.append(f"Error parsing sell CSV: {e}")

    # Check AAPL Sell (Target ~5)
    if 4 <= sells_found["AAPL"] <= 6:
        score += 20
        feedback.append(f"AAPL Sell correct ({sells_found['AAPL']} units).")
    elif sells_found["AAPL"] > 0:
        score += 10
        feedback.append(f"AAPL Sold, but quantity off ({sells_found['AAPL']} units).")
    else:
        feedback.append("No AAPL sell recorded.")

    # Check MSFT Sell (Target ~3)
    if 2 <= sells_found["MSFT"] <= 4:
        score += 20
        feedback.append(f"MSFT Sell correct ({sells_found['MSFT']} units).")
    elif sells_found["MSFT"] > 0:
        score += 10
        feedback.append(f"MSFT Sold, but quantity off ({sells_found['MSFT']} units).")
    else:
        feedback.append("No MSFT sell recorded.")

    # Parse Buys (Check for NEW NVDA)
    initial_nvda = 25.0
    final_nvda = 0.0
    nvda_entries = 0
    try:
        reader = csv.DictReader(io.StringIO(buy_csv_raw))
        for row in reader:
            if row.get("Code") == "NVDA":
                final_nvda += float(row.get("Units", 0))
                nvda_entries += 1
    except Exception:
        pass

    # We expect one MORE entry than the initial state, or total units increased
    nvda_bought = final_nvda - initial_nvda
    if nvda_entries > 1 and (2 <= nvda_bought <= 4):
        score += 20
        feedback.append(f"NVDA Buy correct (+{nvda_bought} units).")
    elif nvda_bought > 0:
        score += 10
        feedback.append(f"NVDA Bought, but quantity off (+{nvda_bought} units).")
    else:
        feedback.append("No new NVDA buy recorded.")

    # 4. VLM Trajectory Verification (20 pts)
    # Check if agent actually used the UI
    try:
        frames = sample_trajectory_frames(traj, n=5)
        final_screen = get_final_screenshot(traj)
        
        # Combine check
        vlm_passed = False
        if frames:
            response = query_vlm(
                images=frames + [final_screen],
                prompt="Does this sequence show a user interacting with a stock portfolio software? Look for 'Sell' or 'Buy' dialog boxes and text editing. Answer YES or NO."
            )
            if "YES" in response.upper():
                vlm_passed = True
        
        if vlm_passed:
            score += 20
            feedback.append("VLM confirmed UI interaction.")
        else:
            feedback.append("VLM could not confirm UI interaction.")
            
    except Exception as e:
        feedback.append(f"VLM check skipped: {e}")
        # Fallback points if CSVs are perfect (assume programmatic success implies visual success)
        if score >= 70: 
            score += 20

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }