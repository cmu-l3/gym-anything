#!/usr/bin/env python3
"""
Verifier for Pet Medication Inventory Manager task.

Checks:
1. Date standardization
2. Formula presence in calculated columns
3. Reorder logic correctness
4. Calculation accuracy
5. Total cost SUM formula
6. Data integrity (no lost rows)
"""

import sys
import os
import logging
import re
from datetime import datetime, date
from typing import Dict, List, Any, Optional, Tuple

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
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


def parse_date_flexible(date_str: Any) -> Optional[date]:
    """
    Parse dates in various formats flexibly.
    
    Handles: YYYY-MM-DD, MM/DD/YYYY, DD-MMM-YY, etc.
    """
    if date_str is None:
        return None
    
    # If already a date object
    if isinstance(date_str, date):
        return date_str
    
    date_str = str(date_str).strip()
    
    if not date_str or date_str.upper() == 'N/A':
        return None
    
    # Try multiple date formats
    formats = [
        '%Y-%m-%d',      # 2024-04-03
        '%m/%d/%Y',      # 04/03/2024
        '%d-%b-%y',      # 03-Apr-24
        '%d/%m/%Y',      # 03/04/2024
        '%Y/%m/%d',      # 2024/04/03
        '%m-%d-%Y',      # 04-03-2024
        '%d-%m-%Y',      # 03-04-2024
        '%m/%d/%y',      # 04/03/24
        '%d/%m/%y',      # 03/04/24
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt).date()
        except (ValueError, AttributeError):
            continue
    
    logger.warning(f"Could not parse date: {date_str}")
    return None


def check_date_standardization(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if dates in Last Refill column are standardized.
    
    Returns: (is_standardized, feedback)
    """
    # Get dates from column D (Last Refill) - rows 2-7 (data rows)
    dates = []
    formats_found = set()
    
    for row_idx in range(2, 8):  # Rows 2-7 (assuming row 1 is header)
        cell_ref = f"D{row_idx}"
        date_val = get_cell_value(workbook, sheet_name, cell_ref)
        
        if date_val and str(date_val).strip() and str(date_val).upper() != 'N/A':
            date_str = str(date_val)
            dates.append(date_str)
            
            # Detect format patterns
            if re.match(r'\d{4}-\d{2}-\d{2}', date_str):
                formats_found.add('ISO')
            elif re.match(r'\d{2}/\d{2}/\d{4}', date_str):
                formats_found.add('US')
            elif re.match(r'\d{2}-[A-Za-z]{3}-\d{2}', date_str):
                formats_found.add('ABBR')
            elif re.match(r'\d{2}/\d{2}/\d{4}', date_str):
                formats_found.add('SLASH')
    
    if len(formats_found) <= 1:
        return True, f"✅ Dates standardized ({len(dates)} dates in consistent format)"
    else:
        return False, f"❌ Mixed date formats detected: {formats_found}"


def check_formula_presence(workbook: Dict, sheet_name: str, cell_ref: str, 
                          expected_functions: List[str]) -> Tuple[bool, str]:
    """
    Check if a cell contains a formula with expected functions.
    
    Args:
        cell_ref: Cell reference like "I2"
        expected_functions: List of function names to look for (e.g., ["TODAY", "SUM"])
    
    Returns: (has_formula, feedback)
    """
    formula = get_cell_formula(workbook, sheet_name, cell_ref)
    
    if formula is None:
        return False, f"No formula in {cell_ref}"
    
    formula_upper = formula.upper()
    
    # Check if any expected function is present
    for func in expected_functions:
        if func.upper() in formula_upper:
            return True, f"Formula found: {formula}"
    
    return False, f"Formula missing expected functions {expected_functions}: {formula}"


def verify_calculation_accuracy(workbook: Dict, sheet_name: str, 
                               row_idx: int) -> Tuple[bool, str]:
    """
    Verify calculation accuracy for a specific row.
    
    Checks the formula chain:
    Days Since Refill → Pills Used → Pills Remaining → Reorder Logic
    
    Args:
        row_idx: Row number (2-based, e.g., 2 for first data row)
    
    Returns: (is_accurate, feedback)
    """
    try:
        # Get values
        last_refill = get_cell_value(workbook, sheet_name, f"D{row_idx}")
        pills_per_bottle = get_cell_value(workbook, sheet_name, f"E{row_idx}")
        daily_dosage = get_cell_value(workbook, sheet_name, f"F{row_idx}")
        
        days_since = get_cell_value(workbook, sheet_name, f"I{row_idx}")
        pills_used = get_cell_value(workbook, sheet_name, f"J{row_idx}")
        pills_remaining = get_cell_value(workbook, sheet_name, f"K{row_idx}")
        reorder_needed = get_cell_value(workbook, sheet_name, f"L{row_idx}")
        
        # Parse and validate
        last_refill_date = parse_date_flexible(last_refill)
        if last_refill_date is None:
            return False, "Cannot verify: Last refill date missing or unparseable"
        
        # Calculate expected values
        today = date.today()
        expected_days = (today - last_refill_date).days
        
        # Convert to float for calculations
        daily_dosage = float(daily_dosage) if daily_dosage else 0
        pills_per_bottle = float(pills_per_bottle) if pills_per_bottle else 0
        days_since = float(days_since) if days_since else 0
        pills_used = float(pills_used) if pills_used else 0
        pills_remaining = float(pills_remaining) if pills_remaining else 0
        
        expected_pills_used = daily_dosage * expected_days
        expected_pills_remaining = pills_per_bottle - expected_pills_used
        expected_reorder = "YES" if expected_pills_remaining < (daily_dosage * 7) else "NO"
        
        # Check with tolerance
        days_tolerance = 1  # TODAY() might differ by a day
        pills_tolerance = daily_dosage * days_tolerance  # Corresponding pill tolerance
        
        issues = []
        
        if abs(days_since - expected_days) > days_tolerance:
            issues.append(f"Days Since mismatch: got {days_since}, expected ~{expected_days}")
        
        if abs(pills_used - expected_pills_used) > pills_tolerance:
            issues.append(f"Pills Used mismatch: got {pills_used}, expected ~{expected_pills_used:.1f}")
        
        if abs(pills_remaining - expected_pills_remaining) > pills_tolerance:
            issues.append(f"Pills Remaining mismatch: got {pills_remaining}, expected ~{expected_pills_remaining:.1f}")
        
        if reorder_needed and str(reorder_needed).upper() != expected_reorder:
            issues.append(f"Reorder logic: got '{reorder_needed}', expected '{expected_reorder}'")
        
        if issues:
            return False, " | ".join(issues)
        else:
            return True, f"Row {row_idx} calculations accurate"
        
    except Exception as e:
        logger.error(f"Error verifying row {row_idx}: {e}", exc_info=True)
        return False, f"Calculation verification error: {str(e)}"


def check_sum_formula(workbook: Dict, sheet_name: str, 
                     column: str, start_row: int, end_row: int) -> Tuple[bool, str]:
    """
    Check if a SUM formula exists at the bottom of a column.
    
    Args:
        column: Column letter (e.g., "N")
        start_row: First data row
        end_row: Last data row
    
    Returns: (has_sum, feedback)
    """
    # Check a few rows below the data range for SUM formula
    for check_row in range(end_row + 1, end_row + 5):
        cell_ref = f"{column}{check_row}"
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        
        if formula and 'SUM' in formula.upper():
            # Verify it references the correct range
            if f"{column}{start_row}" in formula or f"{column}2" in formula:
                return True, f"✅ SUM formula found: {formula} in {cell_ref}"
    
    return False, f"❌ No SUM formula found in column {column} below data"


def verify_pet_med_inventory(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for Pet Medication Inventory task.
    
    Verifies:
    1. Date standardization
    2. Formula presence (5+ calculated columns)
    3. Reorder logic correctness
    4. Calculation accuracy (spot check)
    5. Total cost SUM formula
    6. Data integrity (6 rows preserved)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, file_path in [
        ('ods', '/home/ga/Documents/pet_medications_updated.ods'),
        ('ods', '/home/ga/Documents/pet_medications.ods'),
        ('csv', '/home/ga/Documents/pet_medications.csv'),
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"✅ Loaded file: {file_path}")
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
        logger.info(f"Verifying sheet: {sheet_name}")
        
        # Criteria tracking
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Date standardization
        dates_ok, date_feedback = check_date_standardization(workbook, sheet_name)
        if dates_ok:
            criteria_passed += 1
            subscores['dates_standardized'] = True
        else:
            subscores['dates_standardized'] = False
        feedback_parts.append(date_feedback)
        
        # Criterion 2: Formula presence (check for formulas in calculated columns)
        formulas_found = 0
        expected_formula_columns = [
            ('I2', ['TODAY', '-'], 'Days Since Refill'),
            ('J2', ['*'], 'Pills Used'),
            ('K2', ['-'], 'Pills Remaining'),
            ('L2', ['IF', '<'], 'Reorder Needed'),
            ('M2', ['/'], 'Days Until Empty'),
            ('N2', ['IF'], 'Reorder Cost'),
        ]
        
        formula_details = []
        for cell_ref, expected_funcs, col_name in expected_formula_columns:
            has_formula, msg = check_formula_presence(workbook, sheet_name, cell_ref, expected_funcs)
            if has_formula:
                formulas_found += 1
                formula_details.append(f"{col_name}: ✓")
            else:
                formula_details.append(f"{col_name}: ✗")
        
        if formulas_found >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas present: {formulas_found}/6 columns ({', '.join(formula_details)})")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formulas: {formulas_found}/6 ({', '.join(formula_details)})")
            subscores['formulas_present'] = False
        
        # Criterion 3: Reorder logic correctness (check a specific row)
        # Check row 2 (Luna - Thyroid Pills) - should likely need reorder
        reorder_cell = get_cell_value(workbook, sheet_name, 'L2')
        pills_remaining = get_cell_value(workbook, sheet_name, 'K2')
        daily_dosage = get_cell_value(workbook, sheet_name, 'F2')
        
        reorder_logic_ok = False
        if pills_remaining is not None and daily_dosage is not None:
            try:
                pills_remaining = float(pills_remaining)
                daily_dosage = float(daily_dosage)
                expected_reorder = "YES" if pills_remaining < (daily_dosage * 7) else "NO"
                actual_reorder = str(reorder_cell).upper() if reorder_cell else ""
                
                if expected_reorder in actual_reorder:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Reorder logic correct: {pills_remaining:.1f} pills, {daily_dosage} daily → '{reorder_cell}'")
                    reorder_logic_ok = True
                else:
                    feedback_parts.append(f"❌ Reorder logic incorrect: {pills_remaining:.1f} pills, expected '{expected_reorder}', got '{reorder_cell}'")
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"⚠️ Could not verify reorder logic: {e}")
        else:
            feedback_parts.append("❌ Reorder logic: Missing data in Pills Remaining or Daily Dosage")
        
        subscores['reorder_logic'] = reorder_logic_ok
        
        # Criterion 4: Calculation accuracy (spot check row 2)
        calc_ok, calc_feedback = verify_calculation_accuracy(workbook, sheet_name, 2)
        if calc_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate: {calc_feedback}")
            subscores['calculations_accurate'] = True
        else:
            feedback_parts.append(f"⚠️ Calculation check: {calc_feedback}")
            subscores['calculations_accurate'] = False
        
        # Criterion 5: Total cost SUM formula
        sum_ok, sum_feedback = check_sum_formula(workbook, sheet_name, 'N', 2, 7)
        if sum_ok:
            criteria_passed += 1
            subscores['total_sum_present'] = True
        else:
            subscores['total_sum_present'] = False
        feedback_parts.append(sum_feedback)
        
        # Criterion 6: Data integrity (check that all 6 medication rows exist)
        sheet_rows = workbook['sheets'][sheet_name]
        data_rows = 0
        for row in sheet_rows[1:]:  # Skip header
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row[:3]):  # Check first 3 columns
                data_rows += 1
        
        if data_rows >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Data preserved: {data_rows} medication rows")
            subscores['data_preserved'] = True
        else:
            feedback_parts.append(f"❌ Data loss detected: {data_rows} rows (expected 6)")
            subscores['data_preserved'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4/6 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent medication inventory management!")
        elif passed:
            feedback_parts.append("✅ Task completed successfully")
        else:
            feedback_parts.append(f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met)")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "criteria_met": f"{criteria_passed}/{total_criteria}"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temporary files
        cleanup_verification_temp(temp_dir)
