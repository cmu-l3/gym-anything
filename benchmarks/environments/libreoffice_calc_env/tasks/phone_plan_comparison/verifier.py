#!/usr/bin/env python3
"""
Verifier for Phone Plan Comparison task
"""

import sys
import os
import logging
import re

# Add utils to path
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
    """Normalize formula for comparison by removing spaces and converting to uppercase"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def validate_carrier_a_formula(formula_str, result_value):
    """
    Validate Carrier A formula: =85 + (20 * 4) + 30 = 195
    Should include: base 85, per-line 20*4, data plan 30
    """
    if not formula_str:
        return False, "No formula found"
    
    formula_norm = normalize_formula(formula_str)
    
    # Check for key components
    has_85 = '85' in formula_norm
    has_20 = '20' in formula_norm
    has_4 = '4' in formula_norm
    has_30 = '30' in formula_norm
    
    # Check result
    try:
        result_ok = abs(float(result_value) - 195.0) <= 0.5
    except (ValueError, TypeError):
        result_ok = False
    
    if has_85 and has_20 and has_4 and has_30 and result_ok:
        return True, f"Valid formula: {formula_str} = {result_value}"
    elif result_ok:
        return True, f"Result correct but formula structure unclear: {formula_str} = {result_value}"
    else:
        return False, f"Formula incomplete or incorrect result: {formula_str} = {result_value}"


def validate_carrier_b_formula(formula_str, result_value):
    """
    Validate Carrier B formula: =60 + (25 * 4) + IF(22 > 20, (22 - 20) * 15, 0) = 190
    Must include: base 60, per-line 25*4, IF statement for overage
    """
    if not formula_str:
        return False, "No formula found"
    
    formula_norm = normalize_formula(formula_str)
    
    # Check for IF statement (critical for this carrier)
    has_if = 'IF(' in formula_norm
    
    # Check for key components
    has_60 = '60' in formula_norm
    has_25 = '25' in formula_norm
    has_4 = '4' in formula_norm
    has_22 = '22' in formula_norm
    has_20 = '20' in formula_norm
    has_15 = '15' in formula_norm
    
    # Check result
    try:
        result_ok = abs(float(result_value) - 190.0) <= 0.5
    except (ValueError, TypeError):
        result_ok = False
    
    if has_if and has_60 and has_25 and has_4 and result_ok:
        return True, f"Valid formula with IF logic: {formula_str} = {result_value}"
    elif result_ok and has_60 and has_25:
        # Partial credit if result is correct but IF logic might be missing
        if has_if:
            return True, f"Formula with IF statement: {formula_str} = {result_value}"
        else:
            return True, f"Result correct but IF logic unclear: {formula_str} = {result_value}"
    else:
        return False, f"Formula missing IF statement or incorrect result: {formula_str} = {result_value}"


def validate_carrier_c_formula(formula_str, result_value):
    """
    Validate Carrier C formula: =100 + (15 * 4) + 0 = 160
    Should include: base 100, per-line 15*4
    """
    if not formula_str:
        return False, "No formula found"
    
    formula_norm = normalize_formula(formula_str)
    
    # Check for key components
    has_100 = '100' in formula_norm
    has_15 = '15' in formula_norm
    has_4 = '4' in formula_norm
    
    # Check result
    try:
        result_ok = abs(float(result_value) - 160.0) <= 0.5
    except (ValueError, TypeError):
        result_ok = False
    
    if has_100 and has_15 and has_4 and result_ok:
        return True, f"Valid formula: {formula_str} = {result_value}"
    elif result_ok:
        return True, f"Result correct but formula structure unclear: {formula_str} = {result_value}"
    else:
        return False, f"Formula incomplete or incorrect result: {formula_str} = {result_value}"


def validate_min_formula(formula_str, result_value, carrier_results):
    """
    Validate MIN formula: =MIN(B14:B16) = 160
    Should reference the three carrier cost cells
    """
    if not formula_str:
        return False, "No formula found"
    
    formula_norm = normalize_formula(formula_str)
    
    # Check for MIN function
    has_min = 'MIN(' in formula_norm or 'MIN' in formula_norm
    
    # Check for cell range references
    has_b14 = 'B14' in formula_norm
    has_b15 = 'B15' in formula_norm
    has_b16 = 'B16' in formula_norm
    has_range = ':' in formula_norm and ('B14:B16' in formula_norm or 'B16:B14' in formula_norm)
    
    # Check result - should be the minimum of the three carriers
    try:
        result_ok = abs(float(result_value) - 160.0) <= 0.5
    except (ValueError, TypeError):
        result_ok = False
    
    if has_min and (has_range or (has_b14 and has_b15 and has_b16)) and result_ok:
        return True, f"Valid MIN formula: {formula_str} = {result_value}"
    elif result_ok:
        return True, f"Result correct but MIN formula structure unclear: {formula_str} = {result_value}"
    else:
        return False, f"MIN formula missing or incorrect result: {formula_str} = {result_value}"


def validate_savings_formula(formula_str, result_value):
    """
    Validate savings formula: =240 - B18 = 80
    Should subtract best plan from current cost
    """
    if not formula_str:
        return False, "No formula found"
    
    formula_norm = normalize_formula(formula_str)
    
    # Check for subtraction and reference to B18
    has_240 = '240' in formula_norm
    has_b18 = 'B18' in formula_norm
    has_subtraction = '-' in formula_norm
    
    # Check result
    try:
        result_ok = abs(float(result_value) - 80.0) <= 0.5
    except (ValueError, TypeError):
        result_ok = False
    
    if has_240 and has_b18 and has_subtraction and result_ok:
        return True, f"Valid savings formula: {formula_str} = {result_value}"
    elif result_ok:
        return True, f"Result correct but formula structure unclear: {formula_str} = {result_value}"
    else:
        return False, f"Savings formula incomplete or incorrect result: {formula_str} = {result_value}"


def verify_phone_plan_comparison(traj, env_info, task_info):
    """
    Verify phone plan comparison task completion.
    
    Checks:
    1. Cell B14 contains Carrier A cost formula (result = 195)
    2. Cell B15 contains Carrier B cost formula with IF logic (result = 190)
    3. Cell B16 contains Carrier C cost formula (result = 160)
    4. Cell B18 contains MIN formula to find best plan (result = 160)
    5. Cell B19 contains savings calculation (result = 80)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/phone_plan_comparison.ods"
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
        subscores = {}

        # Get all cell values and formulas
        b14_value = get_cell_value(workbook, sheet_name, 'B14')
        b14_formula = get_cell_formula(workbook, sheet_name, 'B14')
        
        b15_value = get_cell_value(workbook, sheet_name, 'B15')
        b15_formula = get_cell_formula(workbook, sheet_name, 'B15')
        
        b16_value = get_cell_value(workbook, sheet_name, 'B16')
        b16_formula = get_cell_formula(workbook, sheet_name, 'B16')
        
        b18_value = get_cell_value(workbook, sheet_name, 'B18')
        b18_formula = get_cell_formula(workbook, sheet_name, 'B18')
        
        b19_value = get_cell_value(workbook, sheet_name, 'B19')
        b19_formula = get_cell_formula(workbook, sheet_name, 'B19')

        logger.info(f"B14: {b14_formula} = {b14_value}")
        logger.info(f"B15: {b15_formula} = {b15_value}")
        logger.info(f"B16: {b16_formula} = {b16_value}")
        logger.info(f"B18: {b18_formula} = {b18_value}")
        logger.info(f"B19: {b19_formula} = {b19_value}")

        # Criterion 1: Carrier A formula
        carrier_a_valid, carrier_a_msg = validate_carrier_a_formula(b14_formula, b14_value)
        if carrier_a_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Carrier A: {carrier_a_msg}")
            subscores['carrier_a'] = True
        else:
            feedback_parts.append(f"❌ Carrier A: {carrier_a_msg}")
            subscores['carrier_a'] = False

        # Criterion 2: Carrier B formula (most complex - requires IF)
        carrier_b_valid, carrier_b_msg = validate_carrier_b_formula(b15_formula, b15_value)
        if carrier_b_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Carrier B: {carrier_b_msg}")
            subscores['carrier_b'] = True
        else:
            feedback_parts.append(f"❌ Carrier B: {carrier_b_msg}")
            subscores['carrier_b'] = False

        # Criterion 3: Carrier C formula
        carrier_c_valid, carrier_c_msg = validate_carrier_c_formula(b16_formula, b16_value)
        if carrier_c_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Carrier C: {carrier_c_msg}")
            subscores['carrier_c'] = True
        else:
            feedback_parts.append(f"❌ Carrier C: {carrier_c_msg}")
            subscores['carrier_c'] = False

        # Criterion 4: MIN formula for best plan
        carrier_results = [b14_value, b15_value, b16_value]
        min_valid, min_msg = validate_min_formula(b18_formula, b18_value, carrier_results)
        if min_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Best Plan: {min_msg}")
            subscores['best_plan'] = True
        else:
            feedback_parts.append(f"❌ Best Plan: {min_msg}")
            subscores['best_plan'] = False

        # Criterion 5: Savings calculation
        savings_valid, savings_msg = validate_savings_formula(b19_formula, b19_value)
        if savings_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Savings: {savings_msg}")
            subscores['savings'] = True
        else:
            feedback_parts.append(f"❌ Savings: {savings_msg}")
            subscores['savings'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need at least 4 out of 5 criteria
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.append("🎉 Phone plan comparison completed successfully!")
        elif passed:
            feedback_parts.append("✅ Task completed with minor issues")
        else:
            feedback_parts.append(f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria met)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
