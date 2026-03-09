#!/usr/bin/env python3
"""
Verifier for consolidate_stock_positions@1
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_consolidate_stock_positions(traj, env_info, task_info):
    """
    Verifies that the user consolidated the NVDA position into a single average cost entry.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_units = metadata.get('expected_units', 50.0)
    expected_price = metadata.get('expected_price', 600.00)
    price_tolerance = metadata.get('price_tolerance', 0.05)
    expected_comment = metadata.get('expected_comment', "Average Cost Merge").lower()
    
    score = 0
    feedback = []
    
    # 1. Retrieve the result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check file modification
    if not result_data.get('file_modified_during_task', False):
        feedback.append("Portfolio file was not modified (did you save?).")
    else:
        score += 10
        feedback.append("Portfolio file modified.")

    # 2. Retrieve and Parse the CSV
    csv_path = result_data.get('portfolio_csv_path')
    if not csv_path:
        return {"passed": False, "score": score, "feedback": "Portfolio CSV not found in export."}

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        
        nvda_entries = []
        other_stocks = []
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # JStock CSVs sometimes have weird quoting, use standard reader
            reader = csv.DictReader(f)
            for row in reader:
                # Normalize keys (remove byte order marks if any)
                clean_row = {k.strip().replace('"', ''): v.strip().replace('"', '') for k, v in row.items() if k}
                
                symbol = clean_row.get('Symbol', '') or clean_row.get('Code', '')
                
                if 'NVDA' in symbol or 'NVIDIA' in symbol:
                    nvda_entries.append(clean_row)
                elif symbol:
                    other_stocks.append(symbol)
                    
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Verify Constraints
    
    # Check 1: Single NVDA Entry (20 pts)
    if len(nvda_entries) == 1:
        score += 20
        feedback.append("Correctly consolidated to a single NVDA entry.")
    elif len(nvda_entries) == 0:
        feedback.append("No NVDA entry found!")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}
    else:
        feedback.append(f"Found {len(nvda_entries)} NVDA entries (expected 1 consolidated entry).")
        # Proceed to check if *one* of them is correct, but cap score
    
    # Check 2: Correct Units (20 pts)
    # We check the consolidated entry (or the best matching one if multiple)
    target_entry = nvda_entries[0] if nvda_entries else {}
    
    # If multiple, try to find the one that looks like the result
    if len(nvda_entries) > 1:
        for entry in nvda_entries:
            try:
                u = float(entry.get('Units', 0))
                if abs(u - expected_units) < 0.1:
                    target_entry = entry
                    break
            except:
                pass

    try:
        actual_units = float(target_entry.get('Units', 0))
        if abs(actual_units - expected_units) < 0.1:
            score += 20
            feedback.append(f"Units correct ({actual_units}).")
        else:
            feedback.append(f"Units incorrect: {actual_units} (expected {expected_units}).")
    except ValueError:
        feedback.append("Could not parse Units.")

    # Check 3: Correct Price (25 pts)
    try:
        actual_price = float(target_entry.get('Purchase Price', 0))
        if abs(actual_price - expected_price) <= price_tolerance:
            score += 25
            feedback.append(f"Average price correct (${actual_price:.2f}).")
        else:
            feedback.append(f"Average price incorrect: ${actual_price:.2f} (expected ${expected_price:.2f}).")
    except ValueError:
        feedback.append("Could not parse Purchase Price.")

    # Check 4: Date (10 pts)
    date_str = target_entry.get('Date', '')
    if "Feb" in date_str and "15" in date_str and "2024" in date_str:
        score += 10
        feedback.append("Date correct.")
    else:
        feedback.append(f"Date incorrect or format mismatch: '{date_str}' (expected Feb 15, 2024).")

    # Check 5: Comment (10 pts)
    comment = target_entry.get('Comment', '').lower()
    if expected_comment in comment:
        score += 10
        feedback.append("Comment correct.")
    else:
        feedback.append(f"Comment missing required text '{expected_comment}'.")

    # Check 6: Data Integrity (5 pts)
    # Should still have AAPL and MSFT
    has_aapl = any('AAPL' in s or 'Apple' in s for s in other_stocks)
    has_msft = any('MSFT' in s or 'Microsoft' in s for s in other_stocks)
    
    if has_aapl and has_msft:
        score += 5
        feedback.append("Other portfolio entries preserved.")
    else:
        feedback.append("Warning: Other stocks (AAPL/MSFT) missing from portfolio.")

    # Final Pass Calculation
    # Must have Units and Price correct to pass
    units_ok = abs(actual_units - expected_units) < 0.1
    price_ok = abs(actual_price - expected_price) <= price_tolerance
    single_entry_ok = len(nvda_entries) == 1
    
    passed = (score >= 65) and units_ok and price_ok and single_entry_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }