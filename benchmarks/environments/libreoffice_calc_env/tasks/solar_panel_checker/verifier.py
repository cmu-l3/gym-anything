#!/usr/bin/env python3
"""
Verifier for Solar Panel Production Analyzer task.
Checks data cleaning, statistical analysis, and conditional logic formulas.
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, List, Optional

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_valid_production_values(sheet_data: Dict, sheet_name: str) -> Tuple[List[float], int]:
    """
    Extract valid production values from column B (Daily Production).
    Returns list of valid values and total row count.
    """
    valid_values = []
    rows = sheet_data['sheets'][sheet_name]
    
    # Skip header row, start from row 2 (index 1)
    for row_idx in range(1, len(rows)):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        # Column B is index 1 (0=Date, 1=Production, 2=Status)
        if len(row) > 1:
            cell = row[1]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            # Only include valid numeric values > 0
            if value is not None and value != '':
                try:
                    num_val = float(value)
                    if num_val > 0:
                        valid_values.append(num_val)
                except (ValueError, TypeError):
                    # Skip ERROR, blank, or invalid entries
                    pass
    
    return valid_values, len(rows) - 1  # Subtract header


def find_formula_in_sheet(sheet_data: Dict, sheet_name: str, 
                          formula_pattern: str, start_row: int = 0) -> Optional[Tuple[str, Any, str]]:
    """
    Search for a formula matching a pattern in the sheet.
    Returns (cell_ref, value, formula) tuple if found.
    """
    rows = sheet_data['sheets'][sheet_name]
    
    for row_idx in range(start_row, len(rows)):
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and re.search(formula_pattern, formula, re.IGNORECASE):
                    cell_ref = _format_cell_ref(col_idx, row_idx)
                    value = cell.get('value')
                    return (cell_ref, value, formula)
    
    return None


def _format_cell_ref(col_idx: int, row_idx: int) -> str:
    """Convert column/row indices to cell reference (e.g., A1)"""
    col_str = ''
    col = col_idx + 1
    
    while col > 0:
        col -= 1
        col_str = chr(ord('A') + (col % 26)) + col_str
        col //= 26
    
    return f"{col_str}{row_idx + 1}"


def check_average_formula(sheet_data: Dict, sheet_name: str, 
                         expected_avg: float, tolerance: float = 0.5) -> Tuple[bool, str]:
    """
    Check for average formula that correctly excludes errors.
    """
    # Look for AVERAGE formulas
    result = find_formula_in_sheet(sheet_data, sheet_name, r'AVERAGE')
    
    if not result:
        return False, "No AVERAGE formula found"
    
    cell_ref, value, formula = result
    logger.info(f"Found average formula at {cell_ref}: {formula} = {value}")
    
    # Check if formula has error handling (AVERAGEIF, >0, etc.)
    has_error_handling = any(pattern in formula.upper() for pattern in 
                            ['AVERAGEIF', '>0', '<>""', 'IFERROR', 'IF('])
    
    if not has_error_handling:
        return False, f"Average formula lacks error handling: {formula}"
    
    # Check if calculated value is reasonable
    try:
        calc_avg = float(value)
        if abs(calc_avg - expected_avg) > tolerance:
            return False, f"Average value unreasonable: {calc_avg} (expected ~{expected_avg})"
    except (TypeError, ValueError):
        return False, f"Average formula returned invalid value: {value}"
    
    return True, f"✅ Average formula correct at {cell_ref}: {formula} = {value}"


def check_flagging_formula(sheet_data: Dict, sheet_name: str, 
                          avg_threshold: float) -> Tuple[bool, str]:
    """
    Check for IF-based flagging formula with 80% threshold logic.
    """
    # Look for IF formulas with threshold logic
    result = find_formula_in_sheet(sheet_data, sheet_name, r'IF.*0\.8|IF.*80%|IF.*\*0\.8')
    
    if not result:
        # Try more general IF formula search
        result = find_formula_in_sheet(sheet_data, sheet_name, r'IF\s*\(')
        if not result:
            return False, "No IF flagging formula found"
    
    cell_ref, value, formula = result
    logger.info(f"Found flagging formula at {cell_ref}: {formula} = {value}")
    
    # Check if formula contains threshold logic
    has_threshold = any(pattern in formula for pattern in ['0.8', '0.80', '*0.8', '80%'])
    
    if not has_threshold:
        return False, f"IF formula lacks 80% threshold: {formula}"
    
    # Check if formula contains descriptive output
    has_output_text = any(pattern in formula.upper() for pattern in 
                         ['CHECK', 'LOW', 'PROBLEM', 'FLAG', 'INSPECT', 'OK'])
    
    if not has_output_text:
        return False, f"IF formula lacks descriptive output: {formula}"
    
    return True, f"✅ Flagging formula correct at {cell_ref}: {formula}"


def check_total_formula(sheet_data: Dict, sheet_name: str, 
                       expected_total: float, tolerance: float = 5.0) -> Tuple[bool, str]:
    """
    Check for SUM/SUMIF formula calculating total production.
    """
    # Look for SUM formulas
    result = find_formula_in_sheet(sheet_data, sheet_name, r'SUM')
    
    if not result:
        return False, "No SUM formula found for total production"
    
    cell_ref, value, formula = result
    logger.info(f"Found sum formula at {cell_ref}: {formula} = {value}")
    
    # Check if calculated value is reasonable
    try:
        calc_sum = float(value)
        if abs(calc_sum - expected_total) > tolerance:
            return False, f"Total production unreasonable: {calc_sum} (expected ~{expected_total})"
    except (TypeError, ValueError):
        return False, f"Sum formula returned invalid value: {value}"
    
    return True, f"✅ Total production formula correct at {cell_ref}: {formula} = {value}"


def check_savings_formula(sheet_data: Dict, sheet_name: str, 
                         rate: float = 0.12) -> Tuple[bool, str]:
    """
    Check for multiplication formula calculating savings.
    """
    rows = sheet_data['sheets'][sheet_name]
    
    # Look for formulas containing multiplication and the rate
    for row_idx in range(len(rows)):
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and '*' in formula:
                    # Check if formula references rate (0.12) or a cell
                    if '0.12' in formula or '.12' in formula:
                        cell_ref = _format_cell_ref(col_idx, row_idx)
                        value = cell.get('value')
                        logger.info(f"Found savings formula at {cell_ref}: {formula} = {value}")
                        return True, f"✅ Savings calculation found at {cell_ref}: {formula}"
    
    return False, "No savings calculation formula found (expected multiplication by $0.12)"


def check_formula_robustness(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check that formulas don't produce errors (#VALUE!, #DIV/0!, etc.)
    """
    rows = sheet_data['sheets'][sheet_name]
    error_cells = []
    
    for row_idx in range(len(rows)):
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                value = cell.get('value')
                if value and isinstance(value, str):
                    if value.startswith('#') or 'ERROR' in value.upper():
                        cell_ref = _format_cell_ref(col_idx, row_idx)
                        error_cells.append(f"{cell_ref}={value}")
    
    if error_cells:
        return False, f"Formula errors detected: {', '.join(error_cells[:5])}"
    
    return True, "✅ No formula errors detected"


def verify_solar_analysis(traj, env_info, task_info):
    """
    Verify solar panel production analysis task completion.
    
    Checks:
    1. Average formula correctly excludes errors
    2. Flagging formula with 80% threshold exists
    3. Total production calculated correctly
    4. Formulas are robust (no #VALUE! errors)
    5. Savings calculation present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths and formats
    temp_dir = None
    success = False
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/solar_production_log.ods'),
        ('csv', '/home/ga/Documents/solar_production_log.csv'),
        ('ods', '/home/ga/Documents/solar_analysis_complete.ods')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path, copy_from_env, file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file from {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Extract valid production values for reference
        valid_values, total_rows = extract_valid_production_values(workbook, sheet_name)
        
        if not valid_values:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No valid production data found in spreadsheet"
            }
        
        expected_avg = sum(valid_values) / len(valid_values)
        expected_total = sum(valid_values)
        
        logger.info(f"Expected average: {expected_avg:.2f} kWh, Total: {expected_total:.2f} kWh")
        logger.info(f"Valid days: {len(valid_values)}/{total_rows}")
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Average formula correct
        avg_ok, avg_msg = check_average_formula(workbook, sheet_name, expected_avg)
        if avg_ok:
            criteria_passed += 1
            subscores['average_formula'] = True
        else:
            subscores['average_formula'] = False
        feedback_parts.append(avg_msg)
        
        # Criterion 2: Flagging logic present
        flag_ok, flag_msg = check_flagging_formula(workbook, sheet_name, expected_avg * 0.8)
        if flag_ok:
            criteria_passed += 1
            subscores['flagging_logic'] = True
        else:
            subscores['flagging_logic'] = False
        feedback_parts.append(flag_msg)
        
        # Criterion 3: Total production accurate
        total_ok, total_msg = check_total_formula(workbook, sheet_name, expected_total)
        if total_ok:
            criteria_passed += 1
            subscores['total_production'] = True
        else:
            subscores['total_production'] = False
        feedback_parts.append(total_msg)
        
        # Criterion 4: Data cleaning effective (no formula errors)
        robust_ok, robust_msg = check_formula_robustness(workbook, sheet_name)
        if robust_ok:
            criteria_passed += 1
            subscores['formula_robustness'] = True
        else:
            subscores['formula_robustness'] = False
        feedback_parts.append(robust_msg)
        
        # Criterion 5: Savings calculation
        savings_ok, savings_msg = check_savings_formula(workbook, sheet_name)
        if savings_ok:
            criteria_passed += 1
            subscores['savings_calculated'] = True
        else:
            subscores['savings_calculated'] = False
        feedback_parts.append(savings_msg)
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60  # Pass threshold: 60% (3/5 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, f"🎉 Excellent solar analysis! ({criteria_passed}/{total_criteria} criteria)")
        elif passed:
            feedback_parts.insert(0, f"✅ Solar analysis completed ({criteria_passed}/{total_criteria} criteria)")
        else:
            feedback_parts.insert(0, f"❌ Solar analysis incomplete ({criteria_passed}/{total_criteria} criteria)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "valid_days": len(valid_values),
                "total_days": total_rows,
                "expected_average": round(expected_avg, 2),
                "expected_total": round(expected_total, 2)
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_verification_temp(temp_dir)
