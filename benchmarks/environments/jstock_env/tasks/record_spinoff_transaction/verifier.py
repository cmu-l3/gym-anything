#!/usr/bin/env python3
"""
Verifier for record_spinoff_transaction task.
"""

import json
import os
import csv
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_spinoff_transaction(traj, env_info, task_info):
    """
    Verifies that the MSFT spinoff to NVDA was recorded correctly.
    
    Criteria:
    1. MSFT position edited: Value reduced to ~90% ($16,852.50).
    2. NVDA position added: 5 units, Value ~10% ($1,872.50).
    3. Original NVDA position (25 units) preserved.
    4. Total value preserved (approx $18,725.00).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    portfolio_path = metadata.get('portfolio_file', "/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv")
    tolerance = metadata.get('value_tolerance', 5.0)

    # Expected values
    expected_msft_val = metadata.get('expected_msft_value', 16852.5)
    expected_nvda_units = metadata.get('expected_nvda_new_units', 5.0)
    expected_nvda_val = metadata.get('expected_nvda_new_value', 1872.5)
    
    # Files to retrieve
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv').name

    score = 0
    feedback = []
    passed = False

    try:
        # 1. Get Result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_json)
            with open(temp_json, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}

        if not result_data.get('file_modified', False):
            feedback.append("Portfolio file was not modified.")
        else:
            score += 10
            feedback.append("Portfolio file modified.")

        # 2. Get Portfolio CSV
        try:
            copy_from_env(portfolio_path, temp_csv)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve portfolio CSV: {e}"}

        # 3. Parse CSV
        # JStock CSV format: "Code","Symbol","Date","Units","Purchase Price",...
        msft_rows = []
        nvda_rows = []
        
        with open(temp_csv, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            header = next(reader, None) # Skip header
            if not header:
                 return {"passed": False, "score": score, "feedback": "Portfolio file is empty."}
            
            # Identify column indices (JStock structure can vary slightly by version, but usually fixed)
            # We look for headers.
            try:
                col_code = header.index("Code")
                col_units = header.index("Units")
                col_value = header.index("Purchase Value")
                col_comment = header.index("Comment")
            except ValueError as e:
                # Fallback indices if headers match expected default
                col_code, col_units, col_value, col_comment = 0, 3, 6, 17
            
            for row in reader:
                if not row or len(row) < 5: continue
                code = row[col_code]
                try:
                    units = float(row[col_units])
                    value = float(row[col_value])
                    comment = row[col_comment] if len(row) > col_comment else ""
                    
                    if code == "MSFT":
                        msft_rows.append({'units': units, 'value': value, 'comment': comment})
                    elif code == "NVDA":
                        nvda_rows.append({'units': units, 'value': value, 'comment': comment})
                except ValueError:
                    continue

        # 4. Verification Logic
        
        # Check MSFT (Criterion 1)
        msft_ok = False
        if len(msft_rows) == 1:
            m = msft_rows[0]
            if abs(m['value'] - expected_msft_val) <= tolerance:
                score += 30
                msft_ok = True
                feedback.append(f"MSFT cost basis correctly adjusted to {m['value']}.")
                if "Spinoff" in m['comment'] or "Adjustment" in m['comment']:
                    score += 5
            else:
                feedback.append(f"MSFT value mismatch. Expected ~{expected_msft_val}, got {m['value']}.")
        else:
            feedback.append(f"Found {len(msft_rows)} MSFT rows (expected 1).")

        # Check NVDA (Criterion 2 & 3)
        # Expecting one row with ~25 units (original) and one with ~5 units (new)
        nvda_original_found = False
        nvda_new_found = False
        
        for n in nvda_rows:
            # Check for Original (25 units)
            if abs(n['units'] - 25.0) < 0.1:
                if abs(n['value'] - 15382.5) < tolerance:
                    nvda_original_found = True
            
            # Check for New (5 units)
            if abs(n['units'] - expected_nvda_units) < 0.1:
                if abs(n['value'] - expected_nvda_val) <= tolerance:
                    nvda_new_found = True
                    if "Spinoff" in n['comment'] or "Received" in n['comment']:
                        score += 5

        if nvda_original_found:
            score += 10
            feedback.append("Original NVDA position preserved.")
        else:
            feedback.append("Original NVDA position (25 units) missing or altered.")

        if nvda_new_found:
            score += 40 # High weight for correctly recording the complex part
            feedback.append("New NVDA spin-off shares recorded correctly.")
        else:
            feedback.append(f"New NVDA position mismatch. Expected {expected_nvda_units} units @ ~{expected_nvda_val}.")

        # Pass Check
        if msft_ok and nvda_new_found and nvda_original_found:
            passed = True
        
    finally:
        if os.path.exists(temp_json): os.remove(temp_json)
        if os.path.exists(temp_csv): os.remove(temp_csv)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }