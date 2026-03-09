#!/usr/bin/env python3
"""
Verifier for tax_lot_documentation task.
Checks:
1. JStock sell portfolio contains the correct NVDA transaction.
2. Tax report text file exists and contains calculated values.
"""

import json
import os
import re
import csv
import io
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tax_lot_documentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Expected values from metadata
    meta = task_info.get('metadata', {}).get('expected_values', {})
    exp_shares = meta.get('shares_sold', 10)
    exp_price = meta.get('sell_price', 950.0)
    exp_basis = meta.get('cost_basis', 6153.0)
    exp_proceeds = meta.get('proceeds', 9500.0)
    exp_gain = meta.get('gain', 3347.0)

    # =========================================================
    # Check 1: JStock Transaction (Sell Portfolio) - 40 points
    # =========================================================
    sell_csv_content = result.get('sell_csv_content', '')
    sell_modified = result.get('sell_csv_modified_during_task', False)
    
    transaction_found = False
    
    if sell_csv_content and sell_modified:
        try:
            # Parse CSV content
            f = io.StringIO(sell_csv_content)
            reader = csv.DictReader(f)
            for row in reader:
                # Check for NVDA
                code = row.get('Code', '') or row.get('Symbol', '')
                if 'NVDA' in code or 'NVIDIA' in row.get('Symbol', ''):
                    units = float(row.get('Units', 0))
                    price = float(row.get('Selling Price', 0))
                    date_str = row.get('Date', '')
                    
                    if abs(units - exp_shares) < 0.1 and abs(price - exp_price) < 1.0:
                        transaction_found = True
                        score += 40
                        feedback.append(f"Correct JStock transaction found: NVDA {units} units @ ${price}")
                        # Date check bonus
                        if 'Dec' in date_str and '2024' in date_str:
                            score += 5
                            feedback.append("Transaction date correct.")
                        break
        except Exception as e:
            feedback.append(f"Error parsing portfolio CSV: {str(e)}")
    
    if not transaction_found:
        feedback.append("No matching NVDA sell transaction found in JStock portfolio.")

    # =========================================================
    # Check 2: Tax Report File - 55 points
    # =========================================================
    report_content = result.get('report_content_preview', '')
    report_created = result.get('report_created_during_task', False)
    
    if result.get('report_exists') and report_created:
        score += 5 # File exists and created during task
        
        # Normalize content for searching
        content_lower = report_content.lower()
        
        # Check for values (allowing formatting variations)
        # We search for the numbers specifically
        
        # Cost Basis
        if str(int(exp_basis)) in report_content or f"{exp_basis:,.2f}" in report_content or "6,153" in report_content:
            score += 10
            feedback.append("Report: Cost basis correct.")
        
        # Proceeds
        if str(int(exp_proceeds)) in report_content or f"{exp_proceeds:,.2f}" in report_content or "9,500" in report_content:
            score += 10
            feedback.append("Report: Proceeds correct.")
            
        # Gain
        if str(int(exp_gain)) in report_content or f"{exp_gain:,.2f}" in report_content or "3,347" in report_content:
            score += 10
            feedback.append("Report: Gain correct.")
            
        # Shares and Symbol
        if "nvda" in content_lower and "10" in content_lower:
            score += 10
            feedback.append("Report: Symbol and share count mentioned.")
            
        # Remaining shares mentioned (15)
        if "15" in content_lower:
            score += 10
            feedback.append("Report: Remaining shares mentioned.")
            
    else:
        feedback.append("Tax report file not found or not created during task.")

    passed = (score >= 60 and transaction_found)
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback)
    }