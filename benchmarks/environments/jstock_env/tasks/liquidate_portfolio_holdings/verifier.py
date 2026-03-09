#!/usr/bin/env python3
"""
Verifier for Liquidate Portfolio Holdings task.
Checks if specific stocks were sold to bring net quantity to zero.
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_liquidate_portfolio_holdings(traj, env_info, task_info):
    """
    Verifies that the agent has recorded 'Sell' transactions for all holdings.
    
    Criteria:
    1. 'sellportfolio.csv' must contain valid sell records for AAPL, MSFT, NVDA.
    2. Sell prices must match instructions: AAPL@200, MSFT@400, NVDA@800 (with tolerance).
    3. Net quantity (Buy Units - Sell Units) must be 0 for all three.
    4. 'buyportfolio.csv' must still contain the original buy records (not deleted).
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load CSV files
    buy_rows = []
    sell_rows = []

    # Copy Buy CSV
    temp_buy = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/buyportfolio_result.csv", temp_buy.name)
        with open(temp_buy.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            buy_rows = list(reader)
    except Exception:
        pass # Handle empty/missing later
    finally:
        if os.path.exists(temp_buy.name):
            os.unlink(temp_buy.name)

    # Copy Sell CSV
    temp_sell = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/sellportfolio_result.csv", temp_sell.name)
        with open(temp_sell.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            sell_rows = list(reader)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_sell.name):
            os.unlink(temp_sell.name)

    # 2. Evaluation Logic
    score = 0
    feedback = []
    
    # Target Configuration
    targets = {
        "AAPL": {"buy_qty": 100.0, "sell_price": 200.0},
        "MSFT": {"buy_qty": 50.0, "sell_price": 400.0},
        "NVDA": {"buy_qty": 25.0, "sell_price": 800.0}
    }
    
    # Check 1: Buy History Preservation (Anti-gaming)
    # The buy csv should have at least the original 3 rows
    if len(buy_rows) >= 3:
        # Verify specific symbols are present in buy list
        buy_symbols = [r.get('Code', '') for r in buy_rows]
        if all(s in buy_symbols for s in ["AAPL", "MSFT", "NVDA"]):
            score += 15
            feedback.append("Buy history preserved.")
        else:
            feedback.append("Buy history compromised (missing symbols).")
    else:
        feedback.append("Buy history compromised (too few rows).")

    # Check 2: Sell Transactions and Net Quantity
    all_liquidated = True
    
    for symbol, data in targets.items():
        # Calculate total bought (from file)
        total_buy = sum(float(r.get('Units', 0)) for r in buy_rows if r.get('Code') == symbol)
        
        # Calculate total sold
        symbol_sells = [r for r in sell_rows if r.get('Code') == symbol]
        total_sell = sum(float(r.get('Units', 0)) for r in symbol_sells)
        
        # Net Quantity Check
        net_qty = total_buy - total_sell
        
        if total_sell > 0:
            # Check price accuracy
            # We look for at least one transaction close to target price
            valid_price = False
            for s in symbol_sells:
                try:
                    price = float(s.get('Selling Price', 0))
                    if abs(price - data['sell_price']) < 1.0:
                        valid_price = True
                        break
                except ValueError:
                    continue
            
            if valid_price and abs(net_qty) < 0.01:
                score += 25
                feedback.append(f"{symbol}: Liquidated successfully at correct price.")
            elif abs(net_qty) < 0.01:
                score += 15
                feedback.append(f"{symbol}: Liquidated, but price incorrect.")
            else:
                score += 10
                feedback.append(f"{symbol}: Partial sell recorded (Net: {net_qty}).")
                all_liquidated = False
        else:
            feedback.append(f"{symbol}: No sell records found.")
            all_liquidated = False

    # Check 3: File Modification Timestamp
    if result.get('sell_file_modified', False):
        score += 10
        feedback.append("Transaction file modified during task.")
    else:
        feedback.append("No changes detected in sell file during task window.")

    # 3. Final Result
    passed = (score >= 85) and all_liquidated
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }