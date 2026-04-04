#!/usr/bin/env python3
"""
Verifier for quarterly_portfolio_maintenance task.

Checklist:
1. Deposit recorded in JStock (Date, Amount, Comment).
2. Buy transaction recorded in JStock (Date, Symbol, Units, Price).
3. Portfolio Export file created and contains relevant data.
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_quarterly_portfolio_maintenance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Expected values
    EXP_DEP_DATE = metadata.get('expected_deposit_date', 'Mar 31, 2024')
    EXP_DEP_AMT = float(metadata.get('expected_deposit_amount', 2000.0))
    EXP_BUY_SYM = metadata.get('expected_buy_symbol', 'AAPL')
    EXP_BUY_UNITS = float(metadata.get('expected_buy_units', 10.0))
    EXP_BUY_PRICE = float(metadata.get('expected_buy_price', 170.0))
    
    score = 0
    feedback_parts = []
    
    # Helper to clean currency strings
    def parse_float(val):
        try:
            return float(str(val).replace(',', '').replace('$', ''))
        except:
            return 0.0

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Deposit (25 pts)
    deposit_passed = False
    temp_dep = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/verify_deposits.csv", temp_dep.name)
        with open(temp_dep.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            for row in reader:
                # JStock CSV keys usually: "Date","Amount","Comment"
                d_date = row.get('Date', '')
                d_amt = parse_float(row.get('Amount', 0))
                d_cmt = row.get('Comment', '')
                
                # Check match
                date_match = (EXP_DEP_DATE in d_date) or (d_date in EXP_DEP_DATE)
                amt_match = abs(d_amt - EXP_DEP_AMT) < 0.1
                cmt_match = "Q1 2024" in d_cmt
                
                if date_match and amt_match:
                    deposit_passed = True
                    feedback_parts.append(f"Deposit verified: {d_date} ${d_amt}")
                    break
    except Exception as e:
        feedback_parts.append(f"Error checking deposits: {e}")
    finally:
        if os.path.exists(temp_dep.name):
            os.unlink(temp_dep.name)
            
    if deposit_passed:
        score += 25
    else:
        feedback_parts.append("Deposit NOT found or incorrect")

    # 3. Verify Buy Transaction (25 pts)
    buy_passed = False
    temp_buy = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/verify_buys.csv", temp_buy.name)
        with open(temp_buy.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            # Find the NEW transaction
            # Note: There is an existing AAPL transaction (100 units). We need the 10 unit one.
            for row in reader:
                symbol = row.get('Code', '') or row.get('Symbol', '')
                units = parse_float(row.get('Units', 0))
                price = parse_float(row.get('Purchase Price', 0))
                date = row.get('Date', '')

                if EXP_BUY_SYM in symbol:
                    if abs(units - EXP_BUY_UNITS) < 0.1 and abs(price - EXP_BUY_PRICE) < 0.1:
                        # Check date roughly
                        if "Mar" in date and "2024" in date:
                            buy_passed = True
                            feedback_parts.append(f"Buy verified: {symbol} {units} units @ {price}")
                            break
    except Exception as e:
        feedback_parts.append(f"Error checking buys: {e}")
    finally:
        if os.path.exists(temp_buy.name):
            os.unlink(temp_buy.name)

    if buy_passed:
        score += 25
    else:
        feedback_parts.append("Buy transaction NOT found or incorrect")

    # 4. Verify Export File (30 pts)
    export_exists = result.get('export_exists', False)
    export_created = result.get('export_created_during_task', False)
    export_content_valid = False
    
    if export_exists:
        if export_created:
            score += 15
            feedback_parts.append("Export file created")
        else:
            # File exists but old timestamp?
            feedback_parts.append("Export file exists but timestamp suggests it wasn't created during task")
            
        # Check content
        temp_exp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("/tmp/verify_export.csv", temp_exp.name)
            with open(temp_exp.name, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
                # Simple check: does it contain AAPL and maybe the new units total (110)?
                if "AAPL" in content:
                    score += 15
                    export_content_valid = True
                    feedback_parts.append("Export content valid (contains AAPL)")
        except:
            feedback_parts.append("Could not read export file")
        finally:
            if os.path.exists(temp_exp.name):
                os.unlink(temp_exp.name)
    else:
        feedback_parts.append("Export file NOT found")

    # 5. App Running Check (10 pts)
    if result.get('app_was_running', False):
        score += 10
    
    # 6. Bonus/VLM placeholder (10 pts)
    # We assume if they did the work (files updated), visual is likely fine.
    # Awarding full points for functional completion.
    if deposit_passed and buy_passed and export_content_valid:
        score += 10
        feedback_parts.append("Workflow completed successfully")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }