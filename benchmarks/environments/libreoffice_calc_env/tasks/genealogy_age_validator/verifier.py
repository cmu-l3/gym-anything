#!/usr/bin/env python3
"""
Verifier for Genealogy Age Validator task

Checks:
1. Column E has implied birth year formulas (=C#-D#)
2. Column F has flag formulas (=IF(ABS(B#-E#)>2,...))
3. Sample calculations are mathematically correct
4. Formulas applied to all data rows
5. At least one INVESTIGATE flag exists
6. At least one OK flag exists
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
    """Normalize formula string for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').replace('"', '').replace("'", '').upper()


def verify_implied_birth_formula(formula, row_num):
    """
    Check if formula correctly calculates implied birth year.
    Expected pattern: =C[row]-D[row]
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    # Allow various formats: =C2-D2, =(C2-D2), etc.
    pattern1 = f"=C{row_num}-D{row_num}"
    pattern2 = f"=(C{row_num}-D{row_num})"
    
    return pattern1 in norm or pattern2 in norm


def verify_flag_formula(formula, row_num):
    """
    Check if formula correctly flags inconsistencies.
    Expected pattern: =IF(ABS(B[row]-E[row])>2,"INVESTIGATE","OK")
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Must contain key components
    has_if = "IF(" in norm
    has_abs = "ABS(" in norm
    has_b_ref = f"B{row_num}" in norm
    has_e_ref = f"E{row_num}" in norm
    has_threshold = ">2" in norm or ">=3" in norm  # Allow slight variation
    has_investigate = "INVESTIGATE" in norm
    has_ok = "OK" in norm
    
    return has_if and has_abs and has_b_ref and has_e_ref and has_threshold and has_investigate and has_ok


def calculate_expected_implied_birth(record_date, recorded_age):
    """Calculate expected implied birth year"""
    try:
        return int(record_date) - int(recorded_age)
    except (ValueError, TypeError):
        return None


def calculate_expected_flag(known_birth, implied_birth):
    """Calculate expected flag value"""
    try:
        discrepancy = abs(int(known_birth) - int(implied_birth))
        return "INVESTIGATE" if discrepancy > 2 else "OK"
    except (ValueError, TypeError):
        return None


def verify_genealogy_analysis(traj, env_info, task_info):
    """
    Verify genealogy age validation task completion.
    
    Checks:
    1. Column E has correct formulas for implied birth year
    2. Column F has correct formulas for flagging inconsistencies
    3. Sample calculations are accurate
    4. Formulas applied to all data rows
    5. At least one INVESTIGATE flag present
    6. At least one OK flag present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/genealogy_analysis.ods"
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
        sheet_rows = workbook['sheets'][sheet_name]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Count data rows (skip header row)
        data_row_count = 0
        for i, row in enumerate(sheet_rows[1:], start=1):  # Skip header
            # Check if row has data in columns A-D
            if len(row) >= 4:
                name_val = row[0].get('value') if isinstance(row[0], dict) else row[0]
                if name_val:
                    data_row_count += 1
        
        if data_row_count < 10:
            return {"passed": False, "score": 0, "feedback": f"Insufficient data rows found: {data_row_count}"}

        logger.info(f"Found {data_row_count} data rows to verify")

        # Criterion 1: Column E has implied birth year formulas
        formulas_e_correct = 0
        formulas_e_present = 0
        
        for row_num in range(2, min(2 + data_row_count, 20)):  # Check up to row 19
            cell_ref_e = f"E{row_num}"
            formula_e = get_cell_formula(workbook, sheet_name, cell_ref_e)
            
            if formula_e:
                formulas_e_present += 1
                if verify_implied_birth_formula(formula_e, row_num):
                    formulas_e_correct += 1

        if formulas_e_correct >= data_row_count * 0.9:  # 90% of rows
            criteria_passed += 1
            feedback_parts.append(f"✅ Implied birth year formulas correct ({formulas_e_correct}/{data_row_count} rows)")
        elif formulas_e_present >= data_row_count * 0.5:
            feedback_parts.append(f"⚠️ Some implied birth year formulas present but incorrect ({formulas_e_present}/{data_row_count} rows)")
        else:
            feedback_parts.append(f"❌ Missing implied birth year formulas in column E ({formulas_e_present}/{data_row_count} found)")

        # Criterion 2: Column F has flag formulas
        formulas_f_correct = 0
        formulas_f_present = 0
        
        for row_num in range(2, min(2 + data_row_count, 20)):
            cell_ref_f = f"F{row_num}"
            formula_f = get_cell_formula(workbook, sheet_name, cell_ref_f)
            
            if formula_f:
                formulas_f_present += 1
                if verify_flag_formula(formula_f, row_num):
                    formulas_f_correct += 1

        if formulas_f_correct >= data_row_count * 0.9:
            criteria_passed += 1
            feedback_parts.append(f"✅ Flag formulas correct ({formulas_f_correct}/{data_row_count} rows)")
        elif formulas_f_present >= data_row_count * 0.5:
            feedback_parts.append(f"⚠️ Some flag formulas present but incorrect ({formulas_f_present}/{data_row_count} rows)")
        else:
            feedback_parts.append(f"❌ Missing flag formulas in column F ({formulas_f_present}/{data_row_count} found)")

        # Criterion 3: Verify sample calculations
        sample_rows_to_check = min(5, data_row_count)
        correct_calculations = 0
        
        for i in range(sample_rows_to_check):
            row_num = 2 + i
            
            # Get values from columns B, C, D
            known_birth = get_cell_value(workbook, sheet_name, f"B{row_num}")
            record_date = get_cell_value(workbook, sheet_name, f"C{row_num}")
            recorded_age = get_cell_value(workbook, sheet_name, f"D{row_num}")
            implied_birth = get_cell_value(workbook, sheet_name, f"E{row_num}")
            flag = get_cell_value(workbook, sheet_name, f"F{row_num}")
            
            # Calculate expected values
            expected_implied = calculate_expected_implied_birth(record_date, recorded_age)
            expected_flag = calculate_expected_flag(known_birth, expected_implied) if expected_implied else None
            
            # Check if calculations match
            calculation_correct = True
            if expected_implied is not None:
                try:
                    if abs(float(implied_birth) - float(expected_implied)) < 0.01:
                        # Implied birth year correct
                        pass
                    else:
                        calculation_correct = False
                        logger.debug(f"Row {row_num}: Implied birth incorrect. Expected {expected_implied}, got {implied_birth}")
                except (ValueError, TypeError):
                    calculation_correct = False
            
            if expected_flag is not None and flag:
                if str(flag).upper().strip() == expected_flag:
                    # Flag correct
                    pass
                else:
                    calculation_correct = False
                    logger.debug(f"Row {row_num}: Flag incorrect. Expected {expected_flag}, got {flag}")
            
            if calculation_correct:
                correct_calculations += 1

        if correct_calculations >= sample_rows_to_check * 0.8:  # 80% of samples
            criteria_passed += 1
            feedback_parts.append(f"✅ Sample calculations accurate ({correct_calculations}/{sample_rows_to_check} rows)")
        else:
            feedback_parts.append(f"❌ Calculation errors found ({correct_calculations}/{sample_rows_to_check} correct)")

        # Criterion 4: Formulas applied to all data rows
        all_rows_have_data = True
        empty_count_e = 0
        empty_count_f = 0
        
        for row_num in range(2, min(2 + data_row_count, 20)):
            val_e = get_cell_value(workbook, sheet_name, f"E{row_num}")
            val_f = get_cell_value(workbook, sheet_name, f"F{row_num}")
            
            if val_e is None or val_e == "":
                empty_count_e += 1
            if val_f is None or val_f == "":
                empty_count_f += 1

        if empty_count_e == 0 and empty_count_f == 0:
            criteria_passed += 1
            feedback_parts.append("✅ All data rows have calculated values")
        else:
            feedback_parts.append(f"❌ Empty cells found (E: {empty_count_e}, F: {empty_count_f})")

        # Criterion 5 & 6: Check for INVESTIGATE and OK flags
        has_investigate = False
        has_ok = False
        
        for row_num in range(2, min(2 + data_row_count, 20)):
            flag_value = get_cell_value(workbook, sheet_name, f"F{row_num}")
            if flag_value:
                flag_str = str(flag_value).upper().strip()
                if "INVESTIGATE" in flag_str:
                    has_investigate = True
                if "OK" == flag_str:
                    has_ok = True

        if has_investigate:
            criteria_passed += 1
            feedback_parts.append("✅ INVESTIGATE flags present (inconsistent records detected)")
        else:
            feedback_parts.append("❌ No INVESTIGATE flags found")

        if has_ok:
            criteria_passed += 1
            feedback_parts.append("✅ OK flags present (consistent records detected)")
        else:
            feedback_parts.append("❌ No OK flags found")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 4/6 criteria
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "implied_birth_formulas": formulas_e_correct >= data_row_count * 0.9,
                "flag_formulas": formulas_f_correct >= data_row_count * 0.9,
                "calculation_accuracy": correct_calculations >= sample_rows_to_check * 0.8,
                "complete_application": empty_count_e == 0 and empty_count_f == 0,
                "has_investigate_flags": has_investigate,
                "has_ok_flags": has_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
