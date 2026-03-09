#!/usr/bin/env python3
"""
Verifier for exit_and_remove_stock task.
Checks:
1. Sell transaction recorded for NVDA (25 units, 850 price) in sellportfolio.csv.
2. NVDA removed from realtimestock.csv (watchlist).
3. Files modified during task window.
"""

import json
import csv
import base64
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_from_b64(b64_str):
    """Decodes base64 string and returns list of dicts from CSV."""
    if not b64_str:
        return []
    try:
        csv_content = base64.b64decode(b64_str).decode('utf-8')
        # Skip lines that look like "timestamp=..." which JStock puts at the top of watchlist files
        lines = csv_content.splitlines()
        data_lines = [l for l in lines if not l.startswith("timestamp=")]
        
        reader = csv.DictReader(data_lines)
        # Handle JStock's quoted CSV format aggressively if needed, but standard csv lib usually handles it
        return list(reader)
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        return []

def verify_exit_and_remove_stock(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_symbol = metadata.get('target_symbol', 'NVDA')
    target_qty = float(metadata.get('target_qty', 25.0))
    target_sell_price = float(metadata.get('target_sell_price', 850.0))

    # Retrieve result file
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
    feedback_parts = []
    task_start = result.get('task_start', 0)

    # ============================================================
    # 1. Verify Sell Transaction (50 points)
    # ============================================================
    sell_data = result.get('sell_portfolio', {})
    sell_content = parse_csv_from_b64(sell_data.get('content_b64', ''))
    sell_mtime = sell_data.get('mtime', 0)

    sell_found = False
    sell_correct = False
    
    # Check if file was modified during task
    if sell_mtime > task_start:
        for row in sell_content:
            # JStock Code/Symbol check
            code = row.get('Code', '') or row.get('Symbol', '')
            if target_symbol in code:
                try:
                    units = float(row.get('Units', 0))
                    price = float(row.get('Selling Price', 0))
                    
                    if abs(units - target_qty) < 0.01:
                        sell_found = True
                        if abs(price - target_sell_price) < 0.01:
                            sell_correct = True
                            break
                        else:
                            feedback_parts.append(f"Wrong sell price: {price} (expected {target_sell_price})")
                    else:
                        feedback_parts.append(f"Wrong quantity sold: {units} (expected {target_qty})")
                except ValueError:
                    continue
    else:
        feedback_parts.append("Sell portfolio not modified during task")

    if sell_correct:
        score += 50
        feedback_parts.append("Sell transaction verified")
    elif sell_found:
        score += 25
        feedback_parts.append("Sell transaction found but price incorrect")
    else:
        feedback_parts.append("No valid sell transaction found")

    # ============================================================
    # 2. Verify Watchlist Removal (50 points)
    # ============================================================
    watchlist_data = result.get('watchlist', {})
    watchlist_content = parse_csv_from_b64(watchlist_data.get('content_b64', ''))
    watchlist_mtime = watchlist_data.get('mtime', 0)

    nvda_present = False
    other_stocks_present = False # To ensure file wasn't just wiped

    if watchlist_mtime > task_start:
        for row in watchlist_content:
            code = row.get('Code', '')
            if target_symbol in code:
                nvda_present = True
            if 'AAPL' in code or 'MSFT' in code:
                other_stocks_present = True
        
        if not nvda_present and other_stocks_present:
            score += 50
            feedback_parts.append(f"{target_symbol} removed from watchlist")
        elif nvda_present:
            feedback_parts.append(f"{target_symbol} still in watchlist")
        elif not other_stocks_present:
            score += 10 # Partial for effort, but suspicious
            feedback_parts.append("Watchlist seems empty or corrupted")
    else:
        # If timestamp didn't change, we still check content, but verify it wasn't already absent (setup ensures it was present)
        # If setup put it there, and now it's gone, mtime MUST have changed.
        # If mtime didn't change, agent didn't save.
        feedback_parts.append("Watchlist file not modified")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }