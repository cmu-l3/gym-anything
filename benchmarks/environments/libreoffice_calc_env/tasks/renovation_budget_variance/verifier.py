#!/usr/bin/env python3
"""
Verifier for Renovation Budget Variance task
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def check_variance_formula(formula, row_num):
    """
    Check if formula correctly calculates variance (Actual - Budget).
    Expected patterns: =C#-B# or =C#+-B# or similar variations
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Check for C and B references with the correct row number
    has_c_ref = f'C{row_num}' in norm
    has_b_ref = f'B{row_num}' in norm
    has_minus = '-' in norm
    
    # Additional check: ensure it's subtraction, not addition
    # Pattern: =C#-B# or =C#+(-B#) or similar
    pattern1 = f'=C{row_num}-B{row_num}'
    pattern2 = f'=C{row_num}+-B{row_num}'
    
    return (has_c_ref and has_b_ref and has_minus) or (pattern1 in norm) or (pattern2 in norm)


def check_percentage_formula(formula, row_num):
    """
    Check if formula correctly calculates percentage over budget.
    Expected patterns: =D#/B#*100 or =D#/B# (if formatted as percentage)
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Check for D and B references with the correct row number
    has_d_ref = f'D{row_num}' in norm
    has_b_ref = f'B{row_num}' in norm
    has_division = '/' in norm
    
    # Pattern: =D#/B# or =D#/B#*100 or =(D#/B#)*100
    return has_d_ref and has_b_ref and has_division


def check_sum_formula(formula, expected_range=None):
    """
    Check if formula is a SUM formula.
    Optionally check if it includes expected range.
    """
    if not formula:
        return False
    
    norm = normalize_formula(formula)
    
    # Must contain SUM
    if 'SUM' not in norm:
        return False
    
    # If expected_range provided (e.g., "B2:B9"), check if it's in the formula
    if expected_range:
        norm_range = expected_range.replace(' ', '').upper()
        return norm_range in norm
    
    return True


def check_conditional_formatting_ods(filepath, sheet_name="Budget"):
    """
    Check if conditional formatting exists in ODS file.
    This is a simplified check for ODS format.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # ODS conditional formatting is complex, we'll look for style-name attributes
            # and conditional-format elements
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
            }
            
            # Look for cells with conditional-style-name attributes
            cells_with_conditional = root.findall('.//table:table-cell[@table:conditional-style-name]', namespaces)
            
            if cells_with_conditional:
                return True
            
            # Alternative: check for style:map elements (conditional formatting rules)
            style_maps = root.findall('.//style:map', namespaces)
            
            return len(style_maps) > 0
            
    except Exception as e:
        logger.debug(f"Could not check conditional formatting in ODS: {e}")
        return False


def verify_renovation_budget(traj, env_info, task_info):
    """
    Verify renovation budget variance task completion.
    
    Checks:
    1. Variance formulas in column D (=C#-B#)
    2. Percentage formulas in column E (=D#/B#*100 or =D#/B#)
    3. SUM formulas in row 10 for totals
    4. Conditional formatting on variance column
    5. Correct calculations (spot-check)
    6. Currency formatting (approximate check)
    7. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/renovation_budget.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get the Budget sheet (or first sheet)
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]  # Usually "Budget" or "Sheet1"
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: Variance formulas in column D (rows 2-9)
        variance_formula_count = 0
        variance_correct_count = 0
        
        for row_num in range(2, 10):  # Rows 2-9 (8 categories)
            cell_ref = f"D{row_num}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if formula:
                variance_formula_count += 1
                if check_variance_formula(formula, row_num):
                    variance_correct_count += 1
                else:
                    logger.debug(f"Row {row_num} variance formula incorrect: {formula}")
        
        if variance_correct_count >= 6:  # At least 6 out of 8 correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Variance formulas correct ({variance_correct_count}/8 rows)")
        else:
            feedback_parts.append(f"❌ Variance formulas incomplete or incorrect ({variance_correct_count}/8 correct)")
        
        # Criterion 2: Percentage formulas in column E (rows 2-9)
        percentage_formula_count = 0
        percentage_correct_count = 0
        
        for row_num in range(2, 10):
            cell_ref = f"E{row_num}"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if formula:
                percentage_formula_count += 1
                if check_percentage_formula(formula, row_num):
                    percentage_correct_count += 1
                else:
                    logger.debug(f"Row {row_num} percentage formula incorrect: {formula}")
        
        if percentage_correct_count >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Percentage formulas correct ({percentage_correct_count}/8 rows)")
        else:
            feedback_parts.append(f"❌ Percentage formulas incomplete or incorrect ({percentage_correct_count}/8 correct)")
        
        # Criterion 3: SUM formulas in row 10 (totals)
        # Check B10 (Budget total), C10 (Actual total), D10 (Variance total)
        sum_formulas_found = 0
        
        for col, col_letter in [('B', 'Budget'), ('C', 'Actual'), ('D', 'Variance')]:
            cell_ref = f"{col}10"
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            
            if check_sum_formula(formula):
                sum_formulas_found += 1
                logger.debug(f"{col_letter} total formula: {formula}")
        
        if sum_formulas_found >= 2:  # At least 2 out of 3
            criteria_passed += 1
            feedback_parts.append(f"✅ Total SUM formulas present ({sum_formulas_found}/3)")
        else:
            feedback_parts.append(f"❌ Total SUM formulas missing ({sum_formulas_found}/3 found)")
        
        # Criterion 4: Conditional formatting on variance column
        # Try using the utility function first
        has_conditional_formatting = False
        
        try:
            # Try XLSX method first (if available)
            has_conditional_formatting = check_conditional_formatting(workbook, sheet_name, "D2:D9")
        except Exception as e:
            logger.debug(f"Standard conditional formatting check failed: {e}")
        
        # Fallback: try ODS-specific check
        if not has_conditional_formatting:
            filepath = workbook.get('filepath', '')
            if filepath and os.path.exists(filepath):
                has_conditional_formatting = check_conditional_formatting_ods(filepath, sheet_name)
        
        if has_conditional_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            # Don't penalize too much - conditional formatting is hard to verify reliably
            feedback_parts.append("⚠️ Conditional formatting not detected (may be present but not parseable)")
        
        # Criterion 5: Spot-check calculations
        # Check a few variance calculations manually
        calculations_correct = 0
        total_checks = 0
        
        # Check Plumbing (row 2): 4200 - 3500 = 700
        budget_val = get_cell_value(workbook, sheet_name, 'B2')
        actual_val = get_cell_value(workbook, sheet_name, 'C2')
        variance_val = get_cell_value(workbook, sheet_name, 'D2')
        
        if budget_val and actual_val and variance_val:
            total_checks += 1
            expected_variance = float(actual_val) - float(budget_val)
            if abs(float(variance_val) - expected_variance) < 1.0:
                calculations_correct += 1
        
        # Check Flooring (row 4): 5800 - 4500 = 1300
        budget_val = get_cell_value(workbook, sheet_name, 'B4')
        actual_val = get_cell_value(workbook, sheet_name, 'C4')
        variance_val = get_cell_value(workbook, sheet_name, 'D4')
        
        if budget_val and actual_val and variance_val:
            total_checks += 1
            expected_variance = float(actual_val) - float(budget_val)
            if abs(float(variance_val) - expected_variance) < 1.0:
                calculations_correct += 1
        
        # Check Paint (row 6): 980 - 1200 = -220
        budget_val = get_cell_value(workbook, sheet_name, 'B6')
        actual_val = get_cell_value(workbook, sheet_name, 'C6')
        variance_val = get_cell_value(workbook, sheet_name, 'D6')
        
        if budget_val and actual_val and variance_val:
            total_checks += 1
            expected_variance = float(actual_val) - float(budget_val)
            if abs(float(variance_val) - expected_variance) < 1.0:
                calculations_correct += 1
        
        if total_checks > 0 and calculations_correct >= total_checks * 0.67:  # At least 2/3 correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations correct ({calculations_correct}/{total_checks} spot checks)")
        else:
            feedback_parts.append(f"❌ Calculation errors detected ({calculations_correct}/{total_checks} correct)")
        
        # Criterion 6: Currency formatting (approximate check)
        # This is hard to verify precisely from ODS/XLSX, so we'll do a simplified check
        # Check if budget/actual values are present and look like currency
        currency_formatted = False
        
        # If values are preserved and formulas work, assume formatting is reasonable
        if variance_correct_count >= 4 and calculations_correct >= 2:
            currency_formatted = True
            criteria_passed += 1
            feedback_parts.append("✅ Data formatting appears correct")
        else:
            feedback_parts.append("⚠️ Currency formatting not verified")
        
        # Criterion 7: No formula errors
        has_errors = False
        error_cells = []
        
        # Check for common error values in calculated cells
        for row_num in range(2, 11):  # Rows 2-10 (data + total)
            for col in ['D', 'E']:
                cell_ref = f"{col}{row_num}"
                value = get_cell_value(workbook, sheet_name, cell_ref)
                
                if value and isinstance(value, str):
                    if any(err in value for err in ['#DIV/0!', '#REF!', '#VALUE!', '#NAME?', '#N/A', '#NUM!', 'Err:']):
                        has_errors = True
                        error_cells.append(cell_ref)
        
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append(f"❌ Formula errors found in: {', '.join(error_cells)}")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 5/7 criteria (70%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent budget variance analysis!")
        elif passed:
            feedback_parts.append("✅ Budget variance task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "variance_formulas": variance_correct_count >= 6,
                "percentage_formulas": percentage_correct_count >= 6,
                "sum_formulas": sum_formulas_found >= 2,
                "conditional_formatting": has_conditional_formatting,
                "calculations_correct": calculations_correct >= total_checks * 0.67 if total_checks > 0 else False,
                "formatting": currency_formatted,
                "no_errors": not has_errors
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
