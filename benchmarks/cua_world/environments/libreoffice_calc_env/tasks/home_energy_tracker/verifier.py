#!/usr/bin/env python3
"""
Verifier for Home Energy Tracker task
Checks formulas and calculated values for energy usage tracking
"""

import sys
import os
import logging
import re

# Use relative path to utils folder (not /workspace/utils)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, standardize case)"""
    if formula is None:
        return None
    # Remove spaces and convert to uppercase
    normalized = formula.replace(' ', '').upper()
    return normalized


def check_subtraction_formula(formula, expected_cells):
    """
    Check if formula is a subtraction of expected cells.
    E.g., "=B3-B2" for expected_cells=('B3', 'B2')
    """
    if formula is None:
        return False
    
    normalized = normalize_formula(formula)
    cell1, cell2 = expected_cells
    
    # Check for pattern =CELL1-CELL2
    pattern = f"={cell1.upper()}-{cell2.upper()}"
    return pattern in normalized


def check_cost_formula(formula, kwh_cell):
    """
    Check if formula calculates cost correctly.
    Should include multiplication and addition: kWh * rate + base_fee
    """
    if formula is None:
        return False
    
    normalized = normalize_formula(formula)
    kwh_cell_upper = kwh_cell.upper()
    
    # Must reference the kWh cell
    if kwh_cell_upper not in normalized:
        return False
    
    # Must have both multiplication and addition
    has_mult = '*' in normalized
    has_add = '+' in normalized
    
    return has_mult and has_add


def check_percentage_formula(formula, current_cell, prev_cell):
    """
    Check if formula calculates percentage change.
    Should be: (current - previous) / previous * 100
    """
    if formula is None:
        return False
    
    normalized = normalize_formula(formula)
    current_upper = current_cell.upper()
    prev_upper = prev_cell.upper()
    
    # Must reference both cells
    if current_upper not in normalized or prev_upper not in normalized:
        return False
    
    # Must have subtraction, division, and likely multiplication by 100
    has_sub = '-' in normalized
    has_div = '/' in normalized
    
    # Check for *100 or percentage format
    has_percent = '*100' in normalized or '/100' in normalized
    
    return has_sub and has_div


def check_summary_formula(formula, function_name, expected_range=None):
    """
    Check if formula uses expected function (SUM, AVERAGE, MAX).
    Optionally check if it references expected range.
    """
    if formula is None:
        return False
    
    normalized = normalize_formula(formula)
    function_upper = function_name.upper()
    
    # Check function is present
    if function_upper not in normalized:
        return False
    
    # If range specified, check it's referenced
    if expected_range:
        # Normalize range (e.g., "C2:C13" -> "C2:C13")
        range_pattern = expected_range.upper().replace(' ', '')
        if range_pattern not in normalized:
            # Also check for slight variations (C2:C12, C2:C14, etc.)
            # Extract the function call
            return True  # Be lenient about exact range
    
    return True


def verify_energy_tracker(traj, env_info, task_info):
    """
    Verify home energy tracker task completion.
    
    Checks:
    1. kWh formulas (Column C): Subtraction formulas
    2. Cost formulas (Column D): Multiplication and addition
    3. Percentage formulas (Column F): Percentage change calculation
    4. Values are reasonable
    5. Summary formulas present (SUM, AVERAGE, MAX)
    6. Spot-check calculation accuracy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/energy_tracker.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_scores = {
            'kwh_formulas': 0,
            'cost_formulas': 0,
            'percentage_formulas': 0,
            'values_reasonable': 0,
            'summary_formulas': 0,
            'calculation_accuracy': 0
        }
        
        feedback_parts = []

        # Criterion 1: Check kWh formulas (Column C, rows 3-13)
        # Note: Row 2 (first month) won't have previous reading, so start at row 3
        kwh_formula_count = 0
        kwh_formulas_checked = 0
        
        for row in range(3, 14):  # Rows 3-13 (C3 to C13)
            cell_ref = f"C{row}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            expected_cells = (f"B{row}", f"B{row-1}")
            
            kwh_formulas_checked += 1
            if check_subtraction_formula(formula, expected_cells):
                kwh_formula_count += 1
        
        kwh_formula_ratio = kwh_formula_count / kwh_formulas_checked if kwh_formulas_checked > 0 else 0
        
        if kwh_formula_ratio >= 0.8:  # At least 80% correct
            criteria_scores['kwh_formulas'] = 1.0
            feedback_parts.append(f"✅ kWh formulas present ({kwh_formula_count}/{kwh_formulas_checked} cells)")
        elif kwh_formula_ratio >= 0.5:
            criteria_scores['kwh_formulas'] = 0.5
            feedback_parts.append(f"⚠️ Some kWh formulas present ({kwh_formula_count}/{kwh_formulas_checked} cells)")
        else:
            feedback_parts.append(f"❌ kWh formulas missing or incorrect ({kwh_formula_count}/{kwh_formulas_checked} cells)")

        # Criterion 2: Check cost formulas (Column D, rows 2-13)
        cost_formula_count = 0
        cost_formulas_checked = 0
        
        for row in range(2, 14):  # D2 to D13
            cell_ref = f"D{row}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            kwh_cell = f"C{row}"
            
            cost_formulas_checked += 1
            if check_cost_formula(formula, kwh_cell):
                cost_formula_count += 1
        
        cost_formula_ratio = cost_formula_count / cost_formulas_checked if cost_formulas_checked > 0 else 0
        
        if cost_formula_ratio >= 0.8:
            criteria_scores['cost_formulas'] = 1.0
            feedback_parts.append(f"✅ Cost formulas correct ({cost_formula_count}/{cost_formulas_checked} cells)")
        elif cost_formula_ratio >= 0.5:
            criteria_scores['cost_formulas'] = 0.5
            feedback_parts.append(f"⚠️ Some cost formulas present ({cost_formula_count}/{cost_formulas_checked} cells)")
        else:
            feedback_parts.append(f"❌ Cost formulas missing or incorrect ({cost_formula_count}/{cost_formulas_checked} cells)")

        # Criterion 3: Check percentage formulas (Column F, rows 2-13)
        pct_formula_count = 0
        pct_formulas_checked = 0
        
        for row in range(2, 14):  # F2 to F13
            cell_ref = f"F{row}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            current_cell = f"C{row}"
            prev_cell = f"E{row}"
            
            pct_formulas_checked += 1
            if check_percentage_formula(formula, current_cell, prev_cell):
                pct_formula_count += 1
        
        pct_formula_ratio = pct_formula_count / pct_formulas_checked if pct_formulas_checked > 0 else 0
        
        if pct_formula_ratio >= 0.8:
            criteria_scores['percentage_formulas'] = 1.0
            feedback_parts.append(f"✅ Percentage formulas present ({pct_formula_count}/{pct_formulas_checked} cells)")
        elif pct_formula_ratio >= 0.5:
            criteria_scores['percentage_formulas'] = 0.5
            feedback_parts.append(f"⚠️ Some percentage formulas present ({pct_formula_count}/{pct_formulas_checked} cells)")
        else:
            feedback_parts.append(f"❌ Percentage formulas missing ({pct_formula_count}/{pct_formulas_checked} cells)")

        # Criterion 4: Check values are reasonable
        unreasonable_values = 0
        values_checked = 0
        
        for row in range(2, 14):
            # Check kWh values
            kwh_val = get_cell_value(workbook, sheet_name, f"C{row}")
            if kwh_val is not None and kwh_val != '':
                values_checked += 1
                try:
                    kwh_num = float(kwh_val)
                    if kwh_num < 50 or kwh_num > 2000:
                        unreasonable_values += 1
                except (ValueError, TypeError):
                    unreasonable_values += 1
            
            # Check cost values
            cost_val = get_cell_value(workbook, sheet_name, f"D{row}")
            if cost_val is not None and cost_val != '':
                try:
                    cost_num = float(cost_val)
                    if cost_num < 20 or cost_num > 300:
                        unreasonable_values += 1
                except (ValueError, TypeError):
                    unreasonable_values += 1
        
        if unreasonable_values == 0 and values_checked > 10:
            criteria_scores['values_reasonable'] = 1.0
            feedback_parts.append("✅ All calculated values in reasonable range")
        elif unreasonable_values <= 2:
            criteria_scores['values_reasonable'] = 0.7
            feedback_parts.append(f"⚠️ Most values reasonable ({unreasonable_values} outliers)")
        else:
            feedback_parts.append(f"❌ Many unreasonable values detected ({unreasonable_values} issues)")

        # Criterion 5: Check summary formulas
        # Summary section typically starts around row 18-20
        # Look for SUM, AVERAGE, MAX functions in rows 18-25, column B
        summary_functions_found = []
        
        for row in range(17, 26):
            formula = get_cell_formula(workbook, sheet_name, f"B{row}")
            if formula:
                normalized = normalize_formula(formula)
                if 'SUM' in normalized:
                    summary_functions_found.append('SUM')
                if 'AVERAGE' in normalized:
                    summary_functions_found.append('AVERAGE')
                if 'MAX' in normalized:
                    summary_functions_found.append('MAX')
        
        summary_functions_found = list(set(summary_functions_found))  # Remove duplicates
        
        if len(summary_functions_found) >= 3:
            criteria_scores['summary_formulas'] = 1.0
            feedback_parts.append(f"✅ Summary formulas present: {', '.join(summary_functions_found)}")
        elif len(summary_functions_found) >= 2:
            criteria_scores['summary_formulas'] = 0.7
            feedback_parts.append(f"⚠️ Some summary formulas: {', '.join(summary_functions_found)}")
        elif len(summary_functions_found) >= 1:
            criteria_scores['summary_formulas'] = 0.4
            feedback_parts.append(f"⚠️ Few summary formulas: {', '.join(summary_functions_found)}")
        else:
            feedback_parts.append("❌ Summary formulas missing")

        # Criterion 6: Spot-check calculation accuracy
        # Check a few specific cells for correct calculations
        accuracy_checks = 0
        accuracy_passed = 0
        
        # Check row 4 (March): kWh should be B4-B3 = 16240-15750 = 490
        b3_val = get_cell_value(workbook, sheet_name, 'B3')
        b4_val = get_cell_value(workbook, sheet_name, 'B4')
        c4_val = get_cell_value(workbook, sheet_name, 'C4')
        
        if b3_val and b4_val and c4_val:
            try:
                expected_kwh = float(b4_val) - float(b3_val)
                actual_kwh = float(c4_val)
                if abs(actual_kwh - expected_kwh) <= 1:
                    accuracy_passed += 1
                accuracy_checks += 1
            except (ValueError, TypeError):
                accuracy_checks += 1
        
        # Check row 5 cost: Should be approximately C5 * 0.14 + 12
        c5_val = get_cell_value(workbook, sheet_name, 'C5')
        d5_val = get_cell_value(workbook, sheet_name, 'D5')
        
        if c5_val and d5_val:
            try:
                expected_cost = float(c5_val) * 0.14 + 12
                actual_cost = float(d5_val)
                if abs(actual_cost - expected_cost) <= expected_cost * 0.02:  # 2% tolerance
                    accuracy_passed += 1
                accuracy_checks += 1
            except (ValueError, TypeError):
                accuracy_checks += 1
        
        # Check percentage calculation (row 6)
        c6_val = get_cell_value(workbook, sheet_name, 'C6')
        e6_val = get_cell_value(workbook, sheet_name, 'E6')
        f6_val = get_cell_value(workbook, sheet_name, 'F6')
        
        if c6_val and e6_val and f6_val:
            try:
                expected_pct = (float(c6_val) - float(e6_val)) / float(e6_val) * 100
                actual_pct = float(f6_val)
                if abs(actual_pct - expected_pct) <= 1:  # 1 percentage point tolerance
                    accuracy_passed += 1
                accuracy_checks += 1
            except (ValueError, TypeError, ZeroDivisionError):
                accuracy_checks += 1
        
        if accuracy_checks > 0:
            accuracy_ratio = accuracy_passed / accuracy_checks
            if accuracy_ratio >= 0.8:
                criteria_scores['calculation_accuracy'] = 1.0
                feedback_parts.append(f"✅ Calculations accurate ({accuracy_passed}/{accuracy_checks} checks)")
            elif accuracy_ratio >= 0.5:
                criteria_scores['calculation_accuracy'] = 0.5
                feedback_parts.append(f"⚠️ Some calculations accurate ({accuracy_passed}/{accuracy_checks} checks)")
            else:
                feedback_parts.append(f"❌ Calculation errors detected ({accuracy_passed}/{accuracy_checks} checks)")

        # Calculate overall score
        total_score = sum(criteria_scores.values())
        max_score = len(criteria_scores)
        score = int((total_score / max_score) * 100)
        passed = score >= 70
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": criteria_scores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
