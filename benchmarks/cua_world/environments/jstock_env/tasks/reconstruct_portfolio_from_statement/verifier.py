#!/usr/bin/env python3
import json
import os
import tempfile
import csv
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_string(csv_content):
    """Parses a CSV string into a list of dictionaries."""
    if not csv_content or not csv_content.strip():
        return []
    
    try:
        # JStock CSVs might have "timestamp=0" on the first line which is not the header
        lines = csv_content.strip().splitlines()
        start_row = 0
        if lines and "timestamp=" in lines[0]:
            start_row = 1
            
        if len(lines) <= start_row:
            return []

        reader = csv.DictReader(lines[start_row:])
        return list(reader)
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        return []

def normalize_date(date_str):
    """Normalize JStock date format (MMM dd, yyyy) to comparable string."""
    # Simple normalization: remove leading zeros in day, ensure spacing
    # Input: "Mar 05, 2023" -> Output: "Mar 5, 2023"
    try:
        parts = date_str.split()
        if len(parts) == 3:
            month = parts[0]
            day = parts[1].replace(',', '')
            year = parts[2]
            return f"{month} {int(day)}, {year}"
    except:
        pass
    return date_str

def verify_reconstruct_portfolio(traj, env_info, task_info):
    """
    Verifies the Reconstruction task by checking the exported CSV contents
    against the expected transaction details.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected = metadata.get('transactions', {})

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check Portfolio Existence (Anti-Gaming)
    if not result.get("portfolio_exists"):
        return {"passed": False, "score": 0, "feedback": "Portfolio 'Recovery' was not created."}
    
    if not result.get("created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Portfolio directory was not created during the task session (anti-gaming check failed)."}

    score = 10 # Base score for creating portfolio
    feedback = ["Portfolio created."]
    
    # 3. Parse CSVs
    files = result.get("files", {})
    buys = parse_csv_string(files.get("buy_csv", ""))
    sells = parse_csv_string(files.get("sell_csv", ""))
    deposits = parse_csv_string(files.get("deposit_csv", ""))
    dividends = parse_csv_string(files.get("dividend_csv", ""))

    logger.info(f"Parsed {len(buys)} buys, {len(sells)} sells, {len(deposits)} deposits, {len(dividends)} dividends")

    # 4. Verify Deposit (15 pts)
    # Target: Mar 1, 2023 | 25000.0
    deposit_found = False
    exp_dep = expected.get('deposit', {})
    for d in deposits:
        amt = float(d.get('Amount', 0))
        date = normalize_date(d.get('Date', ''))
        exp_date = normalize_date(exp_dep['date'])
        
        if abs(amt - exp_dep['amount']) < 0.01 and date == exp_date:
            deposit_found = True
            break
            
    if deposit_found:
        score += 15
        feedback.append("Deposit verified.")
    else:
        feedback.append("Deposit missing or incorrect.")

    # 5. Verify Buy INTC (15 pts)
    # Target: INTC | 500 | 30.5 | 4.95
    intc_buy_found = False
    exp_buy_intc = expected.get('buy_intc', {})
    for b in buys:
        if b.get('Code') == exp_buy_intc['symbol']:
            units = float(b.get('Units', 0))
            price = float(b.get('Purchase Price', 0))
            broker = float(b.get('Broker', 0))
            date = normalize_date(b.get('Date', ''))
            exp_date = normalize_date(exp_buy_intc['date'])
            
            if (abs(units - exp_buy_intc['units']) < 0.01 and 
                abs(price - exp_buy_intc['price']) < 0.01 and
                abs(broker - exp_buy_intc['fee']) < 0.01 and
                date == exp_date):
                intc_buy_found = True
                break
    
    if intc_buy_found:
        score += 15
        feedback.append("INTC buy verified.")
    else:
        feedback.append("INTC buy transaction incorrect.")

    # 6. Verify Buy AMD (15 pts)
    # Target: AMD | 100 | 95.0 | 4.95
    amd_buy_found = False
    exp_buy_amd = expected.get('buy_amd', {})
    for b in buys:
        if b.get('Code') == exp_buy_amd['symbol']:
            units = float(b.get('Units', 0))
            price = float(b.get('Purchase Price', 0))
            broker = float(b.get('Broker', 0))
            date = normalize_date(b.get('Date', ''))
            exp_date = normalize_date(exp_buy_amd['date'])

            if (abs(units - exp_buy_amd['units']) < 0.01 and 
                abs(price - exp_buy_amd['price']) < 0.01 and
                abs(broker - exp_buy_amd['fee']) < 0.01 and
                date == exp_date):
                amd_buy_found = True
                break

    if amd_buy_found:
        score += 15
        feedback.append("AMD buy verified.")
    else:
        feedback.append("AMD buy transaction incorrect.")

    # 7. Verify Dividend INTC (15 pts)
    # Target: INTC | 62.5
    div_found = False
    exp_div = expected.get('dividend_intc', {})
    for d in dividends:
        if d.get('Code') == exp_div['symbol']:
            amt = float(d.get('Amount', 0))
            date = normalize_date(d.get('Date', ''))
            exp_date = normalize_date(exp_div['date'])
            
            if abs(amt - exp_div['amount']) < 0.01 and date == exp_date:
                div_found = True
                break
    
    if div_found:
        score += 15
        feedback.append("INTC dividend verified.")
    else:
        feedback.append("INTC dividend incorrect.")

    # 8. Verify Sell AMD (20 pts)
    # Target: AMD | 50 | 110.0 | 4.95
    sell_found = False
    exp_sell = expected.get('sell_amd', {})
    for s in sells:
        if s.get('Code') == exp_sell['symbol']:
            units = float(s.get('Units', 0))
            price = float(s.get('Selling Price', 0))
            broker = float(s.get('Broker', 0))
            date = normalize_date(s.get('Date', ''))
            exp_date = normalize_date(exp_sell['date'])

            if (abs(units - exp_sell['units']) < 0.01 and 
                abs(price - exp_sell['price']) < 0.01 and
                abs(broker - exp_sell['fee']) < 0.01 and
                date == exp_date):
                sell_found = True
                break
    
    if sell_found:
        score += 20
        feedback.append("AMD sell verified.")
    else:
        feedback.append("AMD sell transaction incorrect.")

    # 9. Clean State Bonus (10 pts)
    # Check if there are extra transactions that shouldn't be there
    extra_tx = False
    if len(buys) > 2: extra_tx = True # Only INTC and AMD expected
    if len(sells) > 1: extra_tx = True # Only AMD sell expected
    if len(deposits) > 1: extra_tx = True
    if len(dividends) > 1: extra_tx = True
    
    if not extra_tx:
        score += 10
        feedback.append("Clean state verified (no extra transactions).")
    else:
        feedback.append("Extra transactions found (clean state penalty).")

    # Pass threshold
    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }