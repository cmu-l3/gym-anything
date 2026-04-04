#!/usr/bin/env python3
"""
Verifier for Chemical Reaction Yield Verification task.

Checks that formulas are correctly applied to calculate yields and identify discrepancies.
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected data for verification
EXPECTED_REACTIONS = [
    {"id": "RXN-001", "theoretical": 5.2, "actual": 4.1, "reported": 82.5, "expected_calc": 78.85, "has_error": True},
    {"id": "RXN-002", "theoretical": 3.8, "actual": 3.6, "reported": 94.7, "expected_calc": 94.74, "has_error": False},
    {"id": "RXN-003", "theoretical": 6.5, "actual": 5.2, "reported": 80.0, "expected_calc": 80.0, "has_error": False},
    {"id": "RXN-004", "theoretical": 4.1, "actual": 3.3, "reported": 79.5, "expected_calc": 80.49, "has_error": True},
    {"id": "RXN-005", "theoretical": 7.3, "actual": 6.8, "reported": 93.2, "expected_calc": 93.15, "has_error": False},
    {"id": "RXN-006", "theoretical": 2.9, "actual": 2.4, "reported": 82.8, "expected_calc": 82.76, "has_error": False},
    {"id": "RXN-007", "theoretical": 5.7, "actual": 4.9, "reported": 85.0, "expected_calc": 85.96, "has_error": True},
    {"id": "RXN-008", "theoretical": 4.5, "actual": 3.8, "reported": 84.4, "expected_calc": 84.44, "has_error": False},
]


def calculate_expected_yield(theoretical_g, actual_g):
    """Calculate percentage yield using chemistry formula."""
    if theoretical_g == 0:
        return None
    return (actual_g / theoretical_g) * 100.0


def normalize_formula(formula_str):
    """Normalize formula string for comparison (remove spaces, convert to uppercase)."""
    if not formula_str:
        return ""
    # Remove all whitespace
    normalized = re.sub(r'\s+', '', formula_str)
    # Convert to uppercase
    normalized = normalized.upper()
    return normalized


def check_yield_formula_pattern(formula_str, row_num):
    """
    Check if formula matches expected yield calculation pattern.
    Expected: =(C#/B#)*100 or =C#/B#*100 or similar variations
    """
    if not formula_str:
        return False, "No formula found"
    
    normalized = normalize_formula(formula_str)
    
    # Remove leading = if present
    if normalized.startswith('='):
        normalized = normalized[1:]
    
    # Expected pattern: contains C{row}/B{row} and *100
    expected_c_ref = f"C{row_num}"
    expected_b_ref = f"B{row_num}"
    
    # Check if formula contains expected cell references
    has_c_ref = expected_c_ref in normalized
    has_b_ref = expected_b_ref in normalized
    has_multiply_100 = "*100" in normalized
    has_division = "/" in normalized
    
    if has_c_ref and has_b_ref and has_division and has_multiply_100:
        return True, "Valid yield formula"
    
    # Provide specific feedback
    issues = []
    if not has_c_ref:
        issues.append(f"missing {expected_c_ref}")
    if not has_b_ref:
        issues.append(f"missing {expected_b_ref}")
    if not has_division:
        issues.append("missing division")
    if not has_multiply_100:
        issues.append("missing *100")
    
    return False, f"Invalid formula: {', '.join(issues)}"


def check_discrepancy_formula_pattern(formula_str, row_num):
    """
    Check if formula matches expected discrepancy calculation pattern.
    Expected: =E#-D# or similar
    """
    if not formula_str:
        return False, "No formula found"
    
    normalized = normalize_formula(formula_str)
    
    # Remove leading = if present
    if normalized.startswith('='):
        normalized = normalized[1:]
    
    # Expected pattern: E{row}-D{row}
    expected_e_ref = f"E{row_num}"
    expected_d_ref = f"D{row_num}"
    
    has_e_ref = expected_e_ref in normalized
    has_d_ref = expected_d_ref in normalized
    has_subtraction = "-" in normalized
    
    if has_e_ref and has_d_ref and has_subtraction:
        return True, "Valid discrepancy formula"
    
    issues = []
    if not has_e_ref:
        issues.append(f"missing {expected_e_ref}")
    if not has_d_ref:
        issues.append(f"missing {expected_d_ref}")
    if not has_subtraction:
        issues.append("missing subtraction")
    
    return False, f"Invalid formula: {', '.join(issues)}"


def verify_reaction_yields(traj, env_info, task_info):
    """
    Verify chemical reaction yield verification task completion.
    
    Checks:
    1. Column E contains valid yield formulas (not just values)
    2. Calculated yields match expected mathematical results (±0.1% tolerance)
    3. Column F contains valid discrepancy formulas
    4. At least 2 known erroneous reported values are flagged (discrepancy >0.5)
    5. All data rows have complete calculations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try both ODS and CSV formats
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/reaction_data.ods'),
        ('csv', '/home/ga/Documents/reaction_data.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded {file_format.upper()} file")
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
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Track detailed results
        formulas_found = 0
        calculations_correct = 0
        discrepancy_formulas_found = 0
        errors_detected = 0
        complete_rows = 0
        
        # Data starts at row 2 (row 1 is header)
        data_start_row = 2
        data_end_row = data_start_row + len(EXPECTED_REACTIONS) - 1
        
        # Criterion 1 & 2: Check yield formulas and calculations
        for i, expected in enumerate(EXPECTED_REACTIONS):
            row_num = data_start_row + i
            cell_e = f"E{row_num}"
            
            # Check formula exists
            formula_e = get_cell_formula(workbook, sheet_name, cell_e)
            value_e = get_cell_value(workbook, sheet_name, cell_e)
            
            if formula_e:
                formulas_found += 1
                
                # Check formula pattern
                is_valid, msg = check_yield_formula_pattern(formula_e, row_num)
                if is_valid:
                    # Check calculated value
                    try:
                        calc_value = float(value_e) if value_e is not None else None
                        if calc_value is not None:
                            # Compare with expected (tolerance ±0.1%)
                            if abs(calc_value - expected['expected_calc']) <= 0.1:
                                calculations_correct += 1
                            else:
                                logger.debug(f"Row {row_num}: calculation mismatch - expected {expected['expected_calc']:.2f}, got {calc_value:.2f}")
                    except (ValueError, TypeError) as e:
                        logger.debug(f"Row {row_num}: could not parse calculated value: {e}")
                else:
                    logger.debug(f"Row {row_num}: {msg}")
            else:
                logger.debug(f"Row {row_num}: No formula in column E")
        
        # Criterion 1: Formulas Present
        if formulas_found >= 7:  # At least 7/8 reactions should have formulas
            criteria_passed += 1
            feedback_parts.append(f"✅ Yield formulas present ({formulas_found}/8 rows)")
        else:
            feedback_parts.append(f"❌ Missing yield formulas ({formulas_found}/8 rows have formulas)")
        
        # Criterion 2: Calculations Correct
        if calculations_correct >= 7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations correct ({calculations_correct}/8 within tolerance)")
        else:
            feedback_parts.append(f"❌ Calculation errors ({calculations_correct}/8 correct)")
        
        # Criterion 3: Discrepancy formulas
        for i, expected in enumerate(EXPECTED_REACTIONS):
            row_num = data_start_row + i
            cell_f = f"F{row_num}"
            
            formula_f = get_cell_formula(workbook, sheet_name, cell_f)
            
            if formula_f:
                is_valid, msg = check_discrepancy_formula_pattern(formula_f, row_num)
                if is_valid:
                    discrepancy_formulas_found += 1
                else:
                    logger.debug(f"Row {row_num} column F: {msg}")
        
        if discrepancy_formulas_found >= 7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Discrepancy formulas present ({discrepancy_formulas_found}/8 rows)")
        else:
            feedback_parts.append(f"❌ Missing discrepancy formulas ({discrepancy_formulas_found}/8 rows)")
        
        # Criterion 4: Error Detection (at least 2 of the 3 known errors detected)
        for i, expected in enumerate(EXPECTED_REACTIONS):
            if not expected['has_error']:
                continue
            
            row_num = data_start_row + i
            cell_f = f"F{row_num}"
            
            discrepancy_value = get_cell_value(workbook, sheet_name, cell_f)
            
            try:
                if discrepancy_value is not None:
                    disc_val = float(discrepancy_value)
                    # Check if discrepancy is significant (>0.5 pp)
                    if abs(disc_val) > 0.5:
                        errors_detected += 1
                        logger.info(f"Error detected in {expected['id']}: discrepancy = {disc_val:.2f} pp")
            except (ValueError, TypeError):
                logger.debug(f"Could not parse discrepancy value for {expected['id']}")
        
        if errors_detected >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Errors detected ({errors_detected}/3 known errors flagged)")
        else:
            feedback_parts.append(f"❌ Insufficient error detection ({errors_detected}/3 known errors flagged)")
        
        # Criterion 5: Complete Coverage
        for i, expected in enumerate(EXPECTED_REACTIONS):
            row_num = data_start_row + i
            
            formula_e = get_cell_formula(workbook, sheet_name, f"E{row_num}")
            formula_f = get_cell_formula(workbook, sheet_name, f"F{row_num}")
            
            if formula_e and formula_f:
                complete_rows += 1
        
        if complete_rows >= 7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Complete coverage ({complete_rows}/8 rows have both formulas)")
        else:
            feedback_parts.append(f"❌ Incomplete coverage ({complete_rows}/8 rows complete)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80
        
        # Add summary message
        if passed and score == 100:
            feedback_parts.append("🎉 Perfect replication! All calculation errors detected!")
        elif passed:
            feedback_parts.append("✅ Task completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_present": formulas_found >= 7,
                "calculations_correct": calculations_correct >= 7,
                "discrepancy_formulas": discrepancy_formulas_found >= 7,
                "errors_detected": errors_detected >= 2,
                "complete_coverage": complete_rows >= 7
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
        cleanup_verification_temp(temp_dir)
