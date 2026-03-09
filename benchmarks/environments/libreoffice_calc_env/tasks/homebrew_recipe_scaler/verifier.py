#!/usr/bin/env python3
"""
Verifier for Homebrew Recipe Scaler task.
Validates proportional scaling formulas and ABV calculation.
"""

import sys
import os
import logging
import re

# Use relative path to utils (not /workspace/utils)
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
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def check_scale_factor(workbook, sheet_name, scale_cell="B2"):
    """
    Check if scale factor is correct (0.6 or 3/5).
    Returns: (is_correct, message, value)
    """
    value = get_cell_value(workbook, sheet_name, scale_cell)
    formula = get_cell_formula(workbook, sheet_name, scale_cell)
    
    # Check value
    if value is not None and isinstance(value, (int, float)):
        if abs(float(value) - 0.6) <= 0.01:
            if formula and ("3/5" in formula or "0.6" in formula):
                return True, f"Scale factor correct: {formula} = {value}", value
            else:
                # Value is correct but might be hardcoded
                return True, f"Scale factor value correct: {value}", value
    
    # Check formula even if value is not computed yet
    if formula and ("3/5" in formula or "0.6" in formula or "=3/5" in formula.upper()):
        return True, f"Scale factor formula present: {formula}", 0.6
    
    return False, f"Scale factor incorrect: value={value}, formula={formula}", None


def check_scaling_formulas(workbook, sheet_name, ingredient_cells, scale_cell_ref="$B$2"):
    """
    Check if ingredients are scaled using formulas with absolute reference.
    Returns: (score, details)
    """
    formulas_found = 0
    correct_reference = 0
    total = len(ingredient_cells)
    details = []
    
    for cell_ref in ingredient_cells:
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if formula:
            formulas_found += 1
            # Check for absolute reference (case insensitive)
            formula_upper = normalize_formula(formula)
            scale_ref_variants = ["$B$2", "B$2", "$B2"]  # Accept various forms of absolute reference
            
            has_absolute_ref = any(ref in formula for ref in scale_ref_variants)
            
            if has_absolute_ref:
                correct_reference += 1
                details.append(f"✓ {cell_ref}: {formula}")
            else:
                details.append(f"⚠ {cell_ref}: {formula} (missing absolute reference)")
        else:
            # No formula found
            if value is not None:
                details.append(f"✗ {cell_ref}: hardcoded value {value}")
            else:
                details.append(f"✗ {cell_ref}: empty")
    
    formula_percentage = (formulas_found / total) if total > 0 else 0
    reference_percentage = (correct_reference / total) if total > 0 else 0
    
    success = formula_percentage >= 0.8 and reference_percentage >= 0.7
    
    summary = f"Formulas: {formulas_found}/{total} ({formula_percentage:.0%}), Absolute refs: {correct_reference}/{total} ({reference_percentage:.0%})"
    
    return success, summary, details


def check_abv_formula(workbook, sheet_name, abv_cell="B22", og_cell="B20", fg_cell="B21"):
    """
    Check if ABV is calculated correctly using brewing formula.
    ABV = (OG - FG) × 131.25
    Returns: (is_correct, message)
    """
    formula = get_cell_formula(workbook, sheet_name, abv_cell)
    value = get_cell_value(workbook, sheet_name, abv_cell)
    
    if not formula:
        return False, f"ABV cell {abv_cell} contains no formula (value: {value})"
    
    # Normalize formula
    formula_norm = normalize_formula(formula)
    og_norm = og_cell.upper()
    fg_norm = fg_cell.upper()
    
    # Check if formula contains both gravity references
    has_og = og_norm in formula_norm or og_cell in formula
    has_fg = fg_norm in formula_norm or fg_cell in formula
    
    # Check for multiplier (131.25 or similar constant)
    has_multiplier = "131" in formula_norm or "131.25" in formula_norm
    
    # Alternative: some brewers use 1000 or other constants
    if not has_multiplier:
        has_multiplier = any(str(x) in formula_norm for x in ["1000", "129", "130", "132"])
    
    if has_og and has_fg and has_multiplier:
        # Check if result is reasonable
        if value is not None and isinstance(value, (int, float)):
            if 4.0 <= float(value) <= 6.0:
                return True, f"ABV formula correct: {formula} = {value:.2f}%"
            else:
                return False, f"ABV formula present but result unreasonable: {value:.2f}% (expected 4.5-5.5%)"
        else:
            # Formula present but not calculated yet
            return True, f"ABV formula structure correct: {formula}"
    
    return False, f"ABV formula incorrect: {formula} (needs (OG-FG)*131.25)"


def check_practical_values(workbook, sheet_name, scaled_cells):
    """
    Check if scaled values are within practical brewing ranges.
    Returns: (is_reasonable, issues)
    """
    issues = []
    
    # Define practical ranges
    grain_range = (0.3, 20.0)  # lbs for 3-gallon batch
    hop_range = (0.05, 5.0)    # oz per addition
    
    for cell_ref, expected_range, description in scaled_cells:
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value is not None and isinstance(value, (int, float)):
            min_val, max_val = expected_range
            if not (min_val <= float(value) <= max_val):
                issues.append(f"{cell_ref} ({description}): {value} out of range [{min_val}, {max_val}]")
    
    return len(issues) == 0, issues


def verify_homebrew_scaler(traj, env_info, task_info):
    """
    Verify homebrew recipe scaling task completion.
    
    Checks:
    1. Scale factor correct (0.6 or 3/5)
    2. Scaling formulas present with absolute references
    3. ABV calculated correctly
    4. Practical value ranges
    5. Formula integrity (not hardcoded)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/belgian_wit_recipe.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet name (should be "Recipe")
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}

        # Criterion 1: Scale Factor Correct
        scale_ok, scale_msg, scale_value = check_scale_factor(workbook, sheet_name, "B2")
        if scale_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {scale_msg}")
            subscores["scale_factor"] = True
        else:
            feedback_parts.append(f"❌ {scale_msg}")
            subscores["scale_factor"] = False

        # Criterion 2: Scaling Formulas Present
        # Define ingredient cells to check
        ingredient_cells = [
            "C8",   # Pilsner Malt scaled
            "C9",   # Wheat Malt scaled
            "C10",  # Oats scaled
            "D14",  # Hallertau scaled
            "D15",  # Coriander scaled
            "C18",  # Yeast scaled
            "C19"   # Orange Peel scaled
        ]
        
        formulas_ok, formulas_summary, formulas_details = check_scaling_formulas(
            workbook, sheet_name, ingredient_cells
        )
        
        if formulas_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ Scaling formulas: {formulas_summary}")
            subscores["scaling_formulas"] = True
        else:
            feedback_parts.append(f"❌ Scaling formulas incomplete: {formulas_summary}")
            subscores["scaling_formulas"] = False
            # Log details for debugging
            logger.info(f"Formula details: {formulas_details[:3]}")  # First 3 details

        # Criterion 3: ABV Formula Correct
        abv_ok, abv_msg = check_abv_formula(workbook, sheet_name, "B22", "B20", "B21")
        if abv_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {abv_msg}")
            subscores["abv_formula"] = True
        else:
            feedback_parts.append(f"❌ {abv_msg}")
            subscores["abv_formula"] = False

        # Criterion 4: Practical Values
        scaled_checks = [
            ("C8", (2.0, 6.0), "Pilsner Malt"),    # 6.5 * 0.6 = 3.9
            ("C9", (1.0, 4.0), "Wheat Malt"),      # 3.0 * 0.6 = 1.8
            ("C10", (0.2, 1.5), "Oats"),           # 0.5 * 0.6 = 0.3
            ("D14", (0.3, 2.0), "Hallertau"),      # 1.0 * 0.6 = 0.6
            ("D15", (0.2, 1.5), "Coriander"),      # 0.75 * 0.6 = 0.45
        ]
        
        practical_ok, practical_issues = check_practical_values(workbook, sheet_name, scaled_checks)
        if practical_ok:
            criteria_passed += 1
            feedback_parts.append("✅ Scaled values within practical ranges")
            subscores["practical_values"] = True
        else:
            if len(practical_issues) <= 2:
                # Allow some tolerance
                criteria_passed += 0.5
                feedback_parts.append(f"⚠️ Minor value issues: {len(practical_issues)}")
                subscores["practical_values"] = False
            else:
                feedback_parts.append(f"❌ Values out of range: {practical_issues[:2]}")
                subscores["practical_values"] = False

        # Criterion 5: Formula Integrity (not all hardcoded)
        # Check that at least the key cells have formulas
        key_formula_cells = ["B2", "C8", "D14", "B22"]
        formulas_present = 0
        for cell in key_formula_cells:
            if get_cell_formula(workbook, sheet_name, cell):
                formulas_present += 1
        
        formula_integrity = formulas_present >= 3  # At least 3 of 4 key formulas
        if formula_integrity:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used (not hardcoded)")
            subscores["formula_integrity"] = True
        else:
            feedback_parts.append(f"❌ Too few formulas detected ({formulas_present}/4)")
            subscores["formula_integrity"] = False

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
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
