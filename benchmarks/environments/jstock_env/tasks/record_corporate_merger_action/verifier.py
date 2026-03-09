#!/usr/bin/env python3
"""
Verifier for record_corporate_merger_action task.
"""

import json
import csv
import io
import tempfile
import os
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_string(csv_string):
    """Parses a CSV string into a list of dicts."""
    if not csv_string:
        return []
    try:
        f = io.StringIO(csv_string)
        reader = csv.DictReader(f)
        return list(reader)
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        return []

def verify_record_corporate_merger_action(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get Metadata
    metadata = task_info.get('metadata', {})
    expected_amd_units = metadata.get('expected_amd_units', 172.34)
    merger_date_str = metadata.get('merger_date', "Feb 14, 2022")
    
    # Load Result
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

    buy_content = result.get('buy_csv_content', '')
    sell_content = result.get('sell_csv_content', '')
    
    buy_rows = parse_csv_string(buy_content)
    sell_rows = parse_csv_string(sell_content)
    
    score = 0
    feedback = []
    
    # =========================================================
    # CRITERION 1: Check for AMD Buy Transaction (40 pts)
    # =========================================================
    amd_found = False
    amd_correct_units = False
    amd_correct_date = False
    amd_comment_ok = False
    
    for row in buy_rows:
        code = row.get('Code', '').upper()
        symbol = row.get('Symbol', '').upper()
        if 'AMD' in code or 'AMD' in symbol or 'ADVANCED MICRO' in symbol:
            amd_found = True
            
            # Check Units
            try:
                units = float(row.get('Units', '0'))
                if abs(units - expected_amd_units) < 0.1:
                    amd_correct_units = True
                else:
                    feedback.append(f"AMD units mismatch: Found {units}, expected {expected_amd_units}")
            except:
                pass
            
            # Check Date
            # JStock format is usually "MMM dd, yyyy" e.g., "Feb 14, 2022"
            date_val = row.get('Date', '')
            if 'Feb 14, 2022' in date_val or '2022-02-14' in date_val:
                amd_correct_date = True
            
            # Check Comment
            comment = row.get('Comment', '').lower()
            if 'merger' in comment or 'acquisition' in comment or 'xlnx' in comment:
                amd_comment_ok = True
                
            break # Found AMD, stop searching
            
    if amd_found:
        score += 15
        feedback.append("AMD buy transaction found.")
        if amd_correct_units:
            score += 25
            feedback.append("AMD units correct (172.34).")
        if amd_correct_date:
            score += 5
            feedback.append("AMD purchase date correct.")
        if amd_comment_ok:
            score += 5
            feedback.append("Transaction comment indicates merger.")
    else:
        feedback.append("AMD buy transaction NOT found.")

    # =========================================================
    # CRITERION 2: Check XLNX Closed/Sold (40 pts)
    # =========================================================
    xlnx_sold = False
    xlnx_units_correct = False
    xlnx_date_correct = False
    
    # Check if XLNX is in Sell Portfolio
    for row in sell_rows:
        code = row.get('Code', '').upper()
        if 'XLNX' in code or 'XILINX' in code:
            xlnx_sold = True
            
            try:
                units = float(row.get('Units', '0'))
                if abs(units - 100.0) < 0.1:
                    xlnx_units_correct = True
            except:
                pass
                
            date_val = row.get('Date', '')
            if 'Feb 14, 2022' in date_val or '2022-02-14' in date_val:
                xlnx_date_correct = True
            break
            
    # Check if XLNX remains in Buy Portfolio (should be gone or 0)
    xlnx_in_buy = False
    for row in buy_rows:
        code = row.get('Code', '').upper()
        if 'XLNX' in code or 'XILINX' in code:
            # If units are 0, it's effectively closed, though usually row is removed
            try:
                if float(row.get('Units', '0')) > 0:
                    xlnx_in_buy = True
            except:
                xlnx_in_buy = True
    
    if xlnx_sold:
        score += 20
        feedback.append("XLNX sell transaction found.")
        if xlnx_units_correct:
            score += 10
            feedback.append("XLNX sold units correct (100).")
        if xlnx_date_correct:
            score += 5
            feedback.append("XLNX sell date correct.")
    elif not xlnx_in_buy:
        # If not in sell CSV but also not in buy CSV, they deleted it?
        # That's not "Closing" a position correctly in JStock (which moves it to Sell), 
        # but it partially achieves the goal of removing the old holding.
        score += 10
        feedback.append("XLNX removed from holdings (but not recorded in sell history).")
    else:
        feedback.append("XLNX still present in holdings.")

    # =========================================================
    # CRITERION 3: Anti-Gaming / Metadata (15 pts)
    # =========================================================
    modified = result.get('buy_csv_modified', False) or result.get('sell_csv_modified', False)
    if modified:
        score += 15
    else:
        feedback.append("No portfolio files were modified during the task.")

    final_result = {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }
    return final_result