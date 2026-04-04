#!/usr/bin/env python3
"""
Verifier for Daily Hydration Goal Tracker task
Checks formulas, calculations, and goal tracking accuracy
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
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected water intake data (morning, afternoon, evening in oz)
EXPECTED_DATA = [
    (16, 24, 18),  # Total: 58 - No
    (20, 20, 28),  # Total: 68 - Yes
    (12, 16, 20),  # Total: 48 - No
    (18, 28, 22),  # Total: 68 - Yes
    (22, 20, 24),  # Total: 66 - Yes
    (14, 18, 16),  # Total: 48 - No
    (16, 20, 20),  # Total: 56 - No
    (24, 22, 26),  # Total: 72 - Yes
    (20, 24, 20),  # Total: 64 - Yes
    (18, 18, 18),  # Total: 54 - No
    (22, 24, 20),  # Total: 66 - Yes
    (20, 26, 22),  # Total: 68 - Yes
    (16, 22, 24),  # Total: 62 - No
    (24, 24, 24),  # Total: 72 - Yes
]

GOAL_THRESHOLD = 64
TOLERANCE = 0.1


def verify_sum_formula(formula_str):
    """Check if formula is a SUM formula"""
    if not formula_str:
        return False
    formula_upper = formula_str.upper()
    return 'SUM' in formula_upper


def verify_if_formula(formula_str):
    """Check if formula is an IF formula with goal comparison"""
    if not formula_str:
        return False
    formula_upper = formula_str.upper()
    # Must contain IF, and should reference goal (64) or comparison
    has_if = 'IF' in formula_upper
    has_comparison = '>=' in formula_str or '>' in formula_str
    # Some flexibility on exact goal value location
    return has_if and has_comparison


def verify_average_formula(formula_str):
    """Check if formula is an AVERAGE formula"""
    if not formula_str:
        return False
    formula_upper = formula_str.upper()
    return 'AVERAGE' in formula_upper


def verify_countif_formula(formula_str):
    """Check if formula is a COUNTIF formula"""
    if not formula_str:
        return False
    formula_upper = formula_str.upper()
    return 'COUNTIF' in formula_upper


def find_column_with_formulas(workbook, sheet_name, start_row, end_row, formula_checker):
    """
    Find which column contains formulas matching the checker.
    Returns column letter or None.
    """
    for col_letter in ['E', 'F', 'G', 'H']:  # Search reasonable range
        formula = get_cell_formula(workbook, sheet_name, f'{col_letter}{start_row}')
        if formula and formula_checker(formula):
            return col_letter
    return None


def find_statistic_formula(workbook, sheet_name, formula_checker, search_range_rows):
    """
    Find a statistic formula (AVERAGE or COUNTIF) in the spreadsheet.
    Search in rows after the data (row 17 onwards).
    Returns (row, col, formula, value) or None
    """
    for row in search_range_rows:
        for col_letter in ['E', 'F', 'G', 'D']:  # Common locations
            cell_ref = f'{col_letter}{row}'
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if formula and formula_checker(formula):
                value = get_cell_value(workbook, sheet_name, cell_ref)
                return (row, col_letter, formula, value)
    return None


def verify_hydration_tracker(traj, env_info, task_info):
    """
    Verify hydration tracking task completion.
    
    Checks:
    1. Daily Total formulas (SUM) present for all 14 days
    2. Daily totals calculate correctly
    3. Goal Met formulas (IF) present and check 64 oz threshold
    4. AVERAGE formula calculates mean daily intake
    5. COUNTIF formula counts days meeting goal
    6. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/hydration_data.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet
        sheets = list(workbook['sheets'].keys())
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        sheet_name = sheets[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []

        # Criterion 1 & 2: Daily Total formulas present and correct
        # Find which column has SUM formulas (should be E, but be flexible)
        sum_col = find_column_with_formulas(workbook, sheet_name, 2, 15, verify_sum_formula)
        
        daily_totals_correct = False
        sum_formulas_present = False
        
        if sum_col:
            sum_formulas_present = True
            criteria_passed += 1
            feedback_parts.append(f"✅ Daily Total formulas found in column {sum_col}")
            
            # Check calculations are correct
            all_correct = True
            for i, (morning, afternoon, evening) in enumerate(EXPECTED_DATA, start=2):
                row_num = i
                cell_ref = f'{sum_col}{row_num}'
                actual_value = get_cell_value(workbook, sheet_name, cell_ref)
                expected_total = morning + afternoon + evening
                
                if actual_value is not None:
                    try:
                        actual_float = float(actual_value)
                        if abs(actual_float - expected_total) > TOLERANCE:
                            all_correct = False
                            feedback_parts.append(f"⚠️ Row {row_num}: Expected total {expected_total}, got {actual_float}")
                            break
                    except (ValueError, TypeError):
                        all_correct = False
                        feedback_parts.append(f"⚠️ Row {row_num}: Non-numeric value {actual_value}")
                        break
                else:
                    all_correct = False
                    break
            
            if all_correct:
                daily_totals_correct = True
                criteria_passed += 1
                feedback_parts.append("✅ Daily total calculations are accurate")
            else:
                feedback_parts.append("❌ Some daily total calculations are incorrect")
        else:
            feedback_parts.append("❌ Daily Total SUM formulas not found in expected columns")

        # Criterion 3: Goal Met formulas (IF) present and correct
        if_col = find_column_with_formulas(workbook, sheet_name, 2, 15, verify_if_formula)
        
        goal_logic_correct = False
        
        if if_col:
            # Check a few samples to see if logic is correct
            sample_checks = [
                (2, 58, False),   # Row 2: 58 oz - should be "No"
                (3, 68, True),    # Row 3: 68 oz - should be "Yes"
                (9, 64, True),    # Row 9: 64 oz - should be "Yes" (boundary case)
            ]
            
            logic_correct = True
            for row_num, expected_total, should_meet_goal in sample_checks:
                cell_ref = f'{if_col}{row_num}'
                actual_value = get_cell_value(workbook, sheet_name, cell_ref)
                
                if actual_value:
                    actual_str = str(actual_value).strip().upper()
                    if should_meet_goal:
                        if 'YES' not in actual_str and 'TRUE' not in actual_str:
                            logic_correct = False
                            feedback_parts.append(f"⚠️ Row {row_num} ({expected_total} oz): Expected goal met, got '{actual_value}'")
                            break
                    else:
                        if 'NO' not in actual_str and 'FALSE' not in actual_str:
                            logic_correct = False
                            feedback_parts.append(f"⚠️ Row {row_num} ({expected_total} oz): Expected goal not met, got '{actual_value}'")
                            break
            
            if logic_correct:
                goal_logic_correct = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Goal Met formulas correct in column {if_col}")
            else:
                feedback_parts.append(f"❌ Goal Met logic appears incorrect")
        else:
            feedback_parts.append("❌ Goal Met IF formulas not found")

        # Criterion 4: AVERAGE formula present and correct
        avg_result = find_statistic_formula(workbook, sheet_name, verify_average_formula, range(16, 25))
        
        average_correct = False
        
        if avg_result:
            row, col, formula, value = avg_result
            expected_avg = sum([sum(row) for row in EXPECTED_DATA]) / len(EXPECTED_DATA)
            
            if value is not None:
                try:
                    actual_avg = float(value)
                    if abs(actual_avg - expected_avg) < 5.0:  # Allow some tolerance
                        average_correct = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ AVERAGE formula correct: {actual_avg:.1f} oz/day")
                    else:
                        feedback_parts.append(f"⚠️ AVERAGE value seems incorrect: {actual_avg:.1f} (expected ~{expected_avg:.1f})")
                except (ValueError, TypeError):
                    feedback_parts.append(f"⚠️ AVERAGE formula found but value is non-numeric: {value}")
            else:
                feedback_parts.append("⚠️ AVERAGE formula found but no calculated value")
        else:
            feedback_parts.append("❌ AVERAGE formula not found")

        # Criterion 5: COUNTIF formula present and correct
        count_result = find_statistic_formula(workbook, sheet_name, verify_countif_formula, range(16, 25))
        
        count_correct = False
        
        if count_result:
            row, col, formula, value = count_result
            # Expected: 8 days meet goal (64+ oz)
            expected_count = sum(1 for row in EXPECTED_DATA if sum(row) >= GOAL_THRESHOLD)
            
            if value is not None:
                try:
                    actual_count = int(float(value))
                    if actual_count == expected_count:
                        count_correct = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ COUNTIF formula correct: {actual_count} days met goal")
                    else:
                        # Allow some flexibility if agent's calculations differ slightly
                        if abs(actual_count - expected_count) <= 1:
                            count_correct = True
                            criteria_passed += 0.5
                            feedback_parts.append(f"⚠️ COUNTIF value close: {actual_count} (expected {expected_count})")
                        else:
                            feedback_parts.append(f"❌ COUNTIF value incorrect: {actual_count} (expected {expected_count})")
                except (ValueError, TypeError):
                    feedback_parts.append(f"⚠️ COUNTIF formula found but value is non-numeric: {value}")
            else:
                feedback_parts.append("⚠️ COUNTIF formula found but no calculated value")
        else:
            feedback_parts.append("❌ COUNTIF formula not found")

        # Criterion 6: No formula errors
        # Check for common error values in formula cells
        no_errors = True
        error_values = ['#DIV/0!', '#VALUE!', '#REF!', '#NAME?', '#NUM!', '#N/A', '#NULL!']
        
        for col_letter in ['E', 'F', 'G', 'H']:
            for row_num in range(2, 25):
                cell_ref = f'{col_letter}{row_num}'
                value = get_cell_value(workbook, sheet_name, cell_ref)
                if value and any(err in str(value) for err in error_values):
                    no_errors = False
                    feedback_parts.append(f"❌ Formula error in {cell_ref}: {value}")
                    break
            if not no_errors:
                break
        
        if no_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 5/6 criteria (80%)
        
        # Add summary feedback
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent hydration tracking analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Hydration tracking task completed successfully")
        else:
            feedback_parts.insert(0, "❌ Hydration tracking requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "sum_formulas_present": sum_formulas_present,
                "daily_totals_correct": daily_totals_correct,
                "goal_logic_correct": goal_logic_correct,
                "average_correct": average_correct,
                "count_correct": count_correct,
                "no_errors": no_errors
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
