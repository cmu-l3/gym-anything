#!/usr/bin/env python3
"""Verifier for bank_reconciliation task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_cell_formula,
    get_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_formula(wb, sheet_name, row, col, expected_substrings=None):
    """Check if cell contains a formula and optionally matches structural substrings."""
    formula = get_cell_formula(wb, sheet_name, row, col)
    
    # Fallback to get_cell_value if openpyxl read it strictly as a value string starting with =
    if not formula:
        val = get_cell_value(wb, sheet_name, row, col)
        if val and isinstance(val, str) and val.startswith('='):
            formula = val
            
    if not formula or not str(formula).startswith('='):
        return False, f"{sheet_name}!R{row}C{col} is not a formula"
        
    formula_upper = str(formula).upper()
    
    if expected_substrings:
        found = False
        for sub in expected_substrings:
            if sub in formula_upper:
                found = True
                break
        if not found:
            return False, f"{sheet_name}!R{row}C{col} missing expected logic ({expected_substrings})"
            
    return True, ""

def verify_bank_reconciliation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file does not exist"}
        
    if not result.get('file_modified_during_task'):
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task (anti-gaming)"}

    # Fetch spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/november_reconciliation.xlsx", copy_from_env, file_format='xlsx'
    )
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}
        
    try:
        feedback_parts = []
        score = 0
        
        sheets = wb.sheetnames
        if 'Recon_Summary' not in sheets:
            return {"passed": False, "score": 0, "feedback": "Recon_Summary sheet not found"}
            
        # 1. Ledger Formulas (20 pts)
        ledger_ok, err1 = check_formula(wb, 'Ledger', 2, 5)
        if ledger_ok:
            score += 20
            feedback_parts.append("Ledger formulas: OK")
        else:
            feedback_parts.append(f"Ledger formulas: {err1}")
            
        # 2. Bank Stmt Formulas (20 pts)
        bank_ok, err2 = check_formula(wb, 'Bank_Statement', 2, 5)
        if bank_ok:
            score += 20
            feedback_parts.append("Bank formulas: OK")
        else:
            feedback_parts.append(f"Bank formulas: {err2}")
            
        # 3. Unadjusted Balances (10 pts)
        b1_ok, b1_err = check_formula(wb, 'Recon_Summary', 1, 2, ['SUM'])
        b2_ok, b2_err = check_formula(wb, 'Recon_Summary', 2, 2, ['SUM'])
        if b1_ok and b2_ok:
            score += 10
            feedback_parts.append("Unadjusted formulas: OK")
        else:
            feedback_parts.append("Unadjusted formulas: Missing SUM logic")
            
        # 4. Reconciling Items (20 pts)
        b3_ok, b3_err = check_formula(wb, 'Recon_Summary', 3, 2, ['SUMIF'])
        b4_ok, b4_err = check_formula(wb, 'Recon_Summary', 4, 2, ['SUMIF'])
        if b3_ok and b4_ok:
            score += 20
            feedback_parts.append("Reconciling formulas: OK")
        else:
            feedback_parts.append("Reconciling formulas: Missing SUMIF logic")
            
        # 5. Adjusted & Variance (20 pts)
        b5_ok, b5_err = check_formula(wb, 'Recon_Summary', 5, 2, ['+', 'SUM'])
        b6_ok, b6_err = check_formula(wb, 'Recon_Summary', 6, 2, ['+', 'SUM'])
        b7_ok, b7_err = check_formula(wb, 'Recon_Summary', 7, 2, ['-'])
        if b5_ok and b6_ok and b7_ok:
            score += 20
            feedback_parts.append("Adjusted/Variance formulas: OK")
        else:
            feedback_parts.append("Adjusted/Variance formulas: Incorrect logic")
            
        # 6. Formatting (10 pts)
        formatting_ok = True
        for r in range(1, 8):
            fmt = wb['Recon_Summary'].cell(row=r, column=2).number_format
            if fmt == 'General':
                formatting_ok = False
                
        a7_font = wb['Recon_Summary'].cell(row=7, column=1).font
        b7_font = wb['Recon_Summary'].cell(row=7, column=2).font
        
        a7_bold = a7_font.bold if a7_font else False
        b7_bold = b7_font.bold if b7_font else False
        
        if formatting_ok and a7_bold and b7_bold:
            score += 10
            feedback_parts.append("Formatting: OK")
        else:
            feedback_parts.append("Formatting: Incomplete")
            
        passed = score >= 80 and b3_ok and b4_ok and b7_ok
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        cleanup_verification_temp(temp_dir)