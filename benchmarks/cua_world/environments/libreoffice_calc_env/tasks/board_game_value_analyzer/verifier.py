#!/usr/bin/env python3
"""
Verifier for Board Game Value Analyzer task

Checks:
1. Cost-per-play formula exists and handles zero plays
2. Normalized rating formula exists and converts different scales
3. Value score formula exists and combines metrics
4. Calculated values are mathematically correct
5. No formula errors (#DIV/0!, #VALUE!, etc.)
6. Formulas applied to all data rows
"""

import sys
import os
import re
import logging

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


def check_formula_pattern(formula, pattern_type):
    """
    Check if formula matches expected pattern.
    
    Args:
        formula: Formula string
        pattern_type: Type of formula ('cost_per_play', 'normalized_rating', 'value_score')
    
    Returns:
        bool: True if formula matches pattern
    """
    if not formula:
        return False
    
    formula_upper = formula.upper()
    
    if pattern_type == 'cost_per_play':
        # Should contain division and IF statement for error handling
        # Pattern: =IF(..., B/C, ...) or similar
        has_division = '/' in formula_upper
        has_if = 'IF' in formula_upper
        references_cost_and_plays = bool(re.search(r'B\d+.*C\d+|C\d+.*B\d+', formula_upper))
        return has_division and (has_if or references_cost_and_plays)
    
    elif pattern_type == 'normalized_rating':
        # Should contain division by 4 or 9 (for normalization)
        # Pattern: (D-1)/4 or (D-1)/9 or IF(D<=5, ..., ...)
        has_normalization = '/4' in formula_upper or '/9' in formula_upper
        references_rating = bool(re.search(r'D\d+', formula_upper))
        has_subtraction = '-' in formula_upper or 'MINUS' in formula_upper
        return has_normalization and references_rating
    
    elif pattern_type == 'value_score':
        # Should combine rating and cost columns
        # Pattern: G/F or G*something/F
        references_both = bool(re.search(r'[GF]\d+.*[GF]\d+', formula_upper))
        has_operation = any(op in formula_upper for op in ['/', '*', '+', '-'])
        return references_both and has_operation
    
    return False


def verify_calculated_value(actual, expected, tolerance=0.1):
    """
    Verify calculated value is close to expected.
    
    Args:
        actual: Actual cell value
        expected: Expected value
        tolerance: Absolute tolerance for comparison
    
    Returns:
        bool: True if values match within tolerance
    """
    if actual is None:
        return False
    
    try:
        actual_float = float(actual)
        expected_float = float(expected)
        return abs(actual_float - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def check_for_formula_errors(workbook, sheet_name, column, start_row=2, end_row=11):
    """
    Check if any cells in column contain formula errors.
    
    Returns:
        Tuple[bool, str]: (has_no_errors, error_message)
    """
    error_markers = ['#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#NUM!', '#N/A', '#NULL!']
    
    for row in range(start_row, end_row + 1):
        cell_ref = f"{column}{row}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value and any(err in str(value).upper() for err in error_markers):
            return False, f"Formula error in {cell_ref}: {value}"
    
    return True, ""


def verify_board_game_analyzer(traj, env_info, task_info):
    """
    Verify board game value analyzer task completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    workbook = None
    
    for file_path in [
        "/home/ga/Documents/board_game_analysis.ods",
        "/home/ga/Documents/board_game_collection.ods"
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {file_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # CRITERION 1: Cost-Per-Play Formula Present
        logger.info("Checking cost-per-play formula...")
        f2_formula = get_cell_formula(workbook, sheet_name, 'F2')
        cost_per_play_correct = check_formula_pattern(f2_formula, 'cost_per_play')
        
        if cost_per_play_correct:
            criteria_passed += 1
            subscores['cost_per_play_formula'] = True
            feedback_parts.append(f"✅ Cost-per-play formula found: {f2_formula}")
        else:
            subscores['cost_per_play_formula'] = False
            feedback_parts.append(f"❌ Cost-per-play formula missing or incorrect (F2: {f2_formula})")
        
        # CRITERION 2: Normalized Rating Formula Present
        logger.info("Checking normalized rating formula...")
        g2_formula = get_cell_formula(workbook, sheet_name, 'G2')
        normalized_rating_correct = check_formula_pattern(g2_formula, 'normalized_rating')
        
        if normalized_rating_correct:
            criteria_passed += 1
            subscores['normalized_rating_formula'] = True
            feedback_parts.append(f"✅ Normalized rating formula found: {g2_formula}")
        else:
            subscores['normalized_rating_formula'] = False
            feedback_parts.append(f"❌ Normalized rating formula missing or incorrect (G2: {g2_formula})")
        
        # CRITERION 3: Value Score Formula Present
        logger.info("Checking value score formula...")
        h2_formula = get_cell_formula(workbook, sheet_name, 'H2')
        value_score_correct = check_formula_pattern(h2_formula, 'value_score')
        
        if value_score_correct:
            criteria_passed += 1
            subscores['value_score_formula'] = True
            feedback_parts.append(f"✅ Value score formula found: {h2_formula}")
        else:
            subscores['value_score_formula'] = False
            feedback_parts.append(f"❌ Value score formula missing or incorrect (H2: {h2_formula})")
        
        # CRITERION 4: Correct Calculations (Spot Check)
        logger.info("Spot-checking calculated values...")
        calculations_correct = True
        
        # Wingspan (row 2): $40, 12 plays, rating 9/10
        # Expected: Cost/play = 3.33, Norm rating = 0.889, Value ≈ 26.7
        wingspan_cost = get_cell_value(workbook, sheet_name, 'F2')
        if wingspan_cost and verify_calculated_value(wingspan_cost, 3.33, tolerance=0.2):
            logger.info(f"Wingspan cost-per-play correct: {wingspan_cost}")
        else:
            calculations_correct = False
            feedback_parts.append(f"⚠️ Wingspan cost-per-play: expected ~3.33, got {wingspan_cost}")
        
        # Catan (row 3): $30, 15 plays, rating 4/5
        # Expected: Cost/play = 2.0, Norm rating = 0.75
        catan_cost = get_cell_value(workbook, sheet_name, 'F3')
        if catan_cost and verify_calculated_value(catan_cost, 2.0, tolerance=0.2):
            logger.info(f"Catan cost-per-play correct: {catan_cost}")
        else:
            calculations_correct = False
            feedback_parts.append(f"⚠️ Catan cost-per-play: expected ~2.0, got {catan_cost}")
        
        # Check normalized ratings
        wingspan_rating = get_cell_value(workbook, sheet_name, 'G2')
        if wingspan_rating and verify_calculated_value(wingspan_rating, 0.889, tolerance=0.1):
            logger.info(f"Wingspan normalized rating correct: {wingspan_rating}")
        else:
            calculations_correct = False
            feedback_parts.append(f"⚠️ Wingspan norm rating: expected ~0.89, got {wingspan_rating}")
        
        if calculations_correct:
            criteria_passed += 1
            subscores['calculations_correct'] = True
            feedback_parts.append("✅ Spot-checked calculations are correct")
        else:
            subscores['calculations_correct'] = False
        
        # CRITERION 5: No Formula Errors
        logger.info("Checking for formula errors...")
        errors_found = []
        
        for col in ['F', 'G', 'H']:
            no_errors, error_msg = check_for_formula_errors(workbook, sheet_name, col)
            if not no_errors:
                errors_found.append(error_msg)
        
        if not errors_found:
            criteria_passed += 1
            subscores['no_errors'] = True
            feedback_parts.append("✅ No formula errors detected")
        else:
            subscores['no_errors'] = False
            feedback_parts.append(f"❌ Formula errors found: {'; '.join(errors_found)}")
        
        # CRITERION 6: Formulas Applied to All Rows
        logger.info("Checking formula completeness...")
        formulas_complete = True
        
        # Check that formulas exist in rows 2-11 (all game entries)
        for row in range(2, 12):  # Rows 2-11
            for col, pattern_type in [('F', 'cost_per_play'), ('G', 'normalized_rating'), ('H', 'value_score')]:
                cell_ref = f"{col}{row}"
                formula = get_cell_formula(workbook, sheet_name, cell_ref)
                
                if not formula:
                    formulas_complete = False
                    logger.warning(f"Missing formula in {cell_ref}")
                    break
            
            if not formulas_complete:
                break
        
        if formulas_complete:
            criteria_passed += 1
            subscores['formulas_complete'] = True
            feedback_parts.append("✅ Formulas applied to all data rows")
        else:
            subscores['formulas_complete'] = False
            feedback_parts.append("⚠️ Some formulas missing in data rows")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (at least 4.2/6 criteria)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent board game analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Board game analysis completed")
        else:
            feedback_parts.insert(0, "❌ Board game analysis incomplete")
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
