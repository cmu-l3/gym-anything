#!/usr/bin/env python3
"""
Verifier for Mileage Deduction Calculator task
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def validate_deduction_formula(formula, row_num):
    """
    Verify formula follows pattern =E{row}*F{row} or variations
    Accepts:
    - =E2*F2, =F2*E2 (relative)
    - =E2*$F$2, =$F$2*E2 (absolute rate)
    - Variations with spaces
    """
    if not formula:
        return False
    
    formula_norm = normalize_formula(formula)
    
    # Pattern variations (multiplication of columns E and F)
    patterns = [
        f'=E{row_num}*F{row_num}',
        f'=F{row_num}*E{row_num}',
        f'=E{row_num}*$F$2',  # Absolute reference for rate (common pattern)
        f'=$F$2*E{row_num}',
        f'=E{row_num}*$F${row_num}',
        f'=$F${row_num}*E{row_num}',
    ]
    
    for pattern in patterns:
        if pattern.upper() in formula_norm:
            return True
    
    # More flexible check: contains E{row} and F (any form)
    if f'E{row_num}' in formula_norm and 'F' in formula_norm and '*' in formula_norm:
        return True
    
    return False


def validate_sum_formula(formula, expected_col, min_row=2, max_row=7):
    """
    Verify SUM formula references correct column range
    Accepts: =SUM(E2:E7), =SUM($E$2:$E$7), etc.
    """
    if not formula:
        return False
    
    formula_norm = normalize_formula(formula)
    
    # Check if it's a SUM formula
    if '=SUM(' not in formula_norm:
        return False
    
    # Extract the range
    match = re.search(r'=SUM\(\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)\)', formula_norm)
    if not match:
        return False
    
    start_col, start_row, end_col, end_row = match.groups()
    
    # Verify column matches
    if start_col != expected_col or end_col != expected_col:
        return False
    
    # Verify row range is reasonable (should cover data rows)
    start_row_num = int(start_row)
    end_row_num = int(end_row)
    
    # Check if range covers at least some data rows
    if start_row_num <= min_row and end_row_num >= min_row:
        return True
    
    return False


def verify_mileage_deduction(traj, env_info, task_info):
    """
    Verify mileage deduction calculator task completion.
    
    Checks:
    1. Deduction column contains formulas (not static values)
    2. Formulas multiply Miles × Rate
    3. Total miles has SUM formula
    4. Total deduction has SUM formula
    5. Mathematical accuracy of all calculations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/mileage_log.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Expected structure:
        # Row 1: Headers
        # Rows 2-7: Trip data (6 trips)
        # Row 8: TOTAL row
        
        trip_start_row = 2
        trip_end_row = 7
        total_row = 8
        
        # Criterion 1 & 2: Deduction formulas present and correct
        deduction_formulas_ok = True
        deduction_formula_count = 0
        deduction_calc_errors = []
        
        for row_num in range(trip_start_row, trip_end_row + 1):
            # Get cells
            miles_cell = get_cell_value(workbook, sheet_name, f'E{row_num}')
            rate_cell = get_cell_value(workbook, sheet_name, f'F{row_num}')
            deduction_cell = get_cell_value(workbook, sheet_name, f'G{row_num}')
            deduction_formula = get_cell_formula(workbook, sheet_name, f'G{row_num}')
            
            # Check if formula exists
            if not deduction_formula:
                deduction_formulas_ok = False
                feedback_parts.append(f"❌ Row {row_num}: Missing formula in Deduction column")
                continue
            
            # Check if formula is correct pattern
            if not validate_deduction_formula(deduction_formula, row_num):
                deduction_formulas_ok = False
                feedback_parts.append(f"❌ Row {row_num}: Invalid formula pattern: {deduction_formula}")
                continue
            
            deduction_formula_count += 1
            
            # Verify mathematical accuracy
            if miles_cell is not None and rate_cell is not None:
                try:
                    miles = float(miles_cell)
                    rate = float(rate_cell)
                    expected_deduction = miles * rate
                    
                    if deduction_cell is not None:
                        actual_deduction = float(deduction_cell)
                        if abs(actual_deduction - expected_deduction) > 0.01:
                            deduction_calc_errors.append(
                                f"Row {row_num}: Expected {expected_deduction:.2f}, got {actual_deduction:.2f}"
                            )
                except (ValueError, TypeError) as e:
                    deduction_calc_errors.append(f"Row {row_num}: Calculation error - {e}")
        
        if deduction_formula_count == 6 and deduction_formulas_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Deduction formulas present (6/6 rows)")
        else:
            feedback_parts.append(f"❌ Deduction formulas incomplete ({deduction_formula_count}/6 rows)")
        
        if not deduction_calc_errors and deduction_formula_count > 0:
            criteria_passed += 1
            feedback_parts.append("✅ Deduction calculations accurate")
        elif deduction_calc_errors:
            feedback_parts.append(f"❌ Calculation errors: {'; '.join(deduction_calc_errors[:2])}")
        
        # Criterion 3: Total Miles formula
        total_miles_formula = get_cell_formula(workbook, sheet_name, f'E{total_row}')
        total_miles_value = get_cell_value(workbook, sheet_name, f'E{total_row}')
        
        if total_miles_formula and validate_sum_formula(total_miles_formula, 'E'):
            criteria_passed += 1
            feedback_parts.append(f"✅ Total Miles formula correct: {total_miles_formula}")
            
            # Verify total miles calculation
            expected_total_miles = sum([45, 28, 67, 52, 38, 45])  # Sum of trip miles
            if total_miles_value is not None:
                try:
                    actual_total = float(total_miles_value)
                    if abs(actual_total - expected_total_miles) > 0.1:
                        feedback_parts.append(f"⚠️ Total miles value off: expected {expected_total_miles}, got {actual_total}")
                except (ValueError, TypeError):
                    pass
        else:
            feedback_parts.append(f"❌ Total Miles missing SUM formula (got: {total_miles_formula or 'no formula'})")
        
        # Criterion 4: Total Deduction formula
        total_deduction_formula = get_cell_formula(workbook, sheet_name, f'G{total_row}')
        total_deduction_value = get_cell_value(workbook, sheet_name, f'G{total_row}')
        
        if total_deduction_formula and validate_sum_formula(total_deduction_formula, 'G'):
            criteria_passed += 1
            feedback_parts.append(f"✅ Total Deduction formula correct: {total_deduction_formula}")
            
            # Verify total deduction calculation
            expected_total_deduction = sum([45, 28, 67, 52, 38, 45]) * 0.655
            if total_deduction_value is not None:
                try:
                    actual_total = float(total_deduction_value)
                    if abs(actual_total - expected_total_deduction) > 0.1:
                        feedback_parts.append(f"⚠️ Total deduction value off: expected ${expected_total_deduction:.2f}, got ${actual_total:.2f}")
                except (ValueError, TypeError):
                    pass
        else:
            feedback_parts.append(f"❌ Total Deduction missing SUM formula (got: {total_deduction_formula or 'no formula'})")
        
        # Criterion 5: Overall mathematical accuracy (already checked above)
        # This is implicit in the deduction calculation checks
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "deduction_formulas_present": deduction_formula_count == 6,
                "deduction_calculations_correct": len(deduction_calc_errors) == 0,
                "total_miles_formula": total_miles_formula is not None and 'SUM' in str(total_miles_formula).upper(),
                "total_deduction_formula": total_deduction_formula is not None and 'SUM' in str(total_deduction_formula).upper(),
                "mathematical_accuracy": len(deduction_calc_errors) == 0
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
