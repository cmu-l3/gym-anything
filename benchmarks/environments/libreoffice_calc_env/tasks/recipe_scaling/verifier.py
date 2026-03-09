#!/usr/bin/env python3
"""
Verifier for Recipe Scaling task

Checks:
1. Scaling factor formula in B4 (=B2/B1) with value ~2.5
2. Scaled amount formulas in D7-D15 with proper absolute/relative references
3. Calculation accuracy (all scaled amounts = original * 2.5)
4. Formula coverage (at least 8 ingredient rows have formulas)
"""

import sys
import os
import re
import logging

# Do not use /workspace/utils - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """
    Normalize formula for comparison by removing spaces and converting to uppercase.
    
    Args:
        formula: Formula string (e.g., "=B2/B1" or "= B2 / B1")
    
    Returns:
        Normalized formula string
    """
    if not formula:
        return ""
    return formula.replace(" ", "").upper()


def check_absolute_reference(formula, expected_cell="B4"):
    """
    Check if formula contains an absolute reference to expected_cell.
    
    Args:
        formula: Formula string
        expected_cell: Cell that should have absolute reference (default: B4)
    
    Returns:
        bool: True if absolute reference found
    """
    if not formula:
        return False
    
    # Normalize
    norm = normalize_formula(formula)
    
    # Check for $B$4 pattern
    abs_pattern = f"${expected_cell[0]}${expected_cell[1]}"
    
    return abs_pattern in norm


def extract_referenced_row(formula, column="B"):
    """
    Extract the row number referenced in a formula for a specific column.
    
    Args:
        formula: Formula string (e.g., "=B7*$B$4")
        column: Column letter to look for (default: "B")
    
    Returns:
        int: Row number or None if not found
    """
    if not formula:
        return None
    
    # Look for pattern like B7, B8, etc. (not $B$4)
    pattern = rf'{column}(\d+)(?!\$)'
    matches = re.findall(pattern, formula.upper())
    
    if matches:
        return int(matches[0])
    return None


def verify_recipe_scaling(traj, env_info, task_info):
    """
    Verify recipe scaling task completion.
    
    Checks:
    1. Scaling factor formula (B4 = B2/B1)
    2. Scaled amount formulas with correct pattern
    3. Calculation accuracy
    4. Formula coverage (at least 8 ingredients)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/recipe_scaling.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        
        # Get sheet name (should be Sheet1)
        sheet_names = list(data.get('sheets', {}).keys())
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}
        
        # --- Criterion 1: Scaling Factor Formula ---
        scaling_factor_formula = get_cell_formula(data, sheet_name, 'B4')
        scaling_factor_value = get_cell_value(data, sheet_name, 'B4')
        
        scaling_formula_correct = False
        norm_formula = normalize_formula(scaling_factor_formula)
        
        # Check if formula is B2/B1 or equivalent
        if scaling_factor_formula and ('/' in norm_formula):
            # Accept =B2/B1 or =B1/B2 (though B2/B1 is correct)
            if 'B2' in norm_formula and 'B1' in norm_formula:
                # Check the value is approximately 2.5
                try:
                    value = float(scaling_factor_value) if scaling_factor_value else 0
                    if abs(value - 2.5) < 0.1:
                        scaling_formula_correct = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Scaling factor formula correct: {scaling_factor_formula} = {value}")
                    else:
                        feedback_parts.append(f"⚠️ Scaling factor formula present but value incorrect: {value} (expected 2.5)")
                except (ValueError, TypeError):
                    feedback_parts.append(f"❌ Scaling factor formula present but value invalid: {scaling_factor_value}")
            else:
                feedback_parts.append(f"❌ Scaling factor formula incorrect: {scaling_factor_formula}")
        else:
            feedback_parts.append(f"❌ No scaling factor formula in B4 (found: {scaling_factor_formula or 'empty'})")
        
        subscores['scaling_factor_formula'] = scaling_formula_correct
        
        # --- Criterion 2: Formula Pattern (absolute reference) ---
        # Check D7-D15 for formulas with correct pattern
        formula_pattern_correct = True
        formulas_with_absolute_ref = 0
        formulas_checked = 0
        
        for row in range(7, 16):  # Rows 7-15 (ingredients)
            cell_ref = f"D{row}"
            formula = get_cell_formula(data, sheet_name, cell_ref)
            
            if formula and '=' in formula:
                formulas_checked += 1
                
                # Check for absolute reference to B4
                has_absolute = check_absolute_reference(formula, "B4")
                
                # Check for relative reference to same row in column B
                referenced_row = extract_referenced_row(formula, "B")
                has_relative = (referenced_row == row)
                
                if has_absolute and has_relative:
                    formulas_with_absolute_ref += 1
                elif has_absolute and not has_relative:
                    # Absolute ref correct but relative ref wrong
                    feedback_parts.append(f"⚠️ Formula in {cell_ref} has absolute ref but wrong relative ref: {formula}")
                    formula_pattern_correct = False
                elif not has_absolute:
                    # Missing absolute reference
                    feedback_parts.append(f"⚠️ Formula in {cell_ref} missing absolute reference $B$4: {formula}")
                    formula_pattern_correct = False
        
        if formulas_checked >= 8 and formulas_with_absolute_ref >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Formula pattern correct: {formulas_with_absolute_ref} formulas use $B$4 absolute reference")
        elif formulas_checked >= 8:
            feedback_parts.append(f"❌ Formula pattern issues: only {formulas_with_absolute_ref}/{formulas_checked} use correct absolute reference")
        else:
            feedback_parts.append(f"❌ Not enough formulas: only {formulas_checked} formulas found (need at least 8)")
        
        subscores['formula_pattern'] = (formulas_with_absolute_ref >= 8)
        
        # --- Criterion 3: All Ingredients Have Formulas ---
        formulas_present = formulas_checked >= 8
        
        if formulas_present:
            criteria_passed += 1
            feedback_parts.append(f"✅ All ingredients scaled: {formulas_checked} formulas in column D")
        else:
            feedback_parts.append(f"❌ Missing formulas: only {formulas_checked}/9 ingredients have formulas")
        
        subscores['all_ingredients_scaled'] = formulas_present
        
        # --- Criterion 4: Calculations Accurate ---
        # Check that scaled values equal original * 2.5
        calculations_correct = 0
        calculations_checked = 0
        
        for row in range(7, 16):
            original_value = get_cell_value(data, sheet_name, f"B{row}")
            scaled_value = get_cell_value(data, sheet_name, f"D{row}")
            
            if original_value is not None and scaled_value is not None:
                try:
                    original = float(original_value)
                    scaled = float(scaled_value)
                    expected = original * 2.5
                    
                    calculations_checked += 1
                    
                    if abs(scaled - expected) <= 0.01:
                        calculations_correct += 1
                    else:
                        logger.debug(f"Row {row}: {original} * 2.5 = {expected}, got {scaled}")
                
                except (ValueError, TypeError):
                    logger.warning(f"Non-numeric value in row {row}: original={original_value}, scaled={scaled_value}")
        
        calc_accuracy_rate = calculations_correct / max(calculations_checked, 1)
        
        if calc_accuracy_rate >= 0.9:  # At least 90% correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations accurate: {calculations_correct}/{calculations_checked} correct")
        else:
            feedback_parts.append(f"❌ Calculation errors: only {calculations_correct}/{calculations_checked} correct")
        
        subscores['calculations_accurate'] = (calc_accuracy_rate >= 0.9)
        
        # --- Calculate final score ---
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (3/4 criteria)
        
        # Add summary
        if passed:
            if score >= 95:
                feedback_parts.append("🎉 Recipe scaling completed perfectly!")
            else:
                feedback_parts.append("✅ Recipe scaling task completed")
        else:
            feedback_parts.append("❌ Recipe scaling requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        # Clean up temporary directory
        cleanup_verification_environment(file_info.get('temp_dir'))
