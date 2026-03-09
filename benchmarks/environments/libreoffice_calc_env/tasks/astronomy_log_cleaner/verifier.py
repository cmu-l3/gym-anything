#!/usr/bin/env python3
"""
Verifier for Astronomy Observation Log Cleaner task.

Checks:
1. Time format standardization (24-hour format, no AM/PM)
2. Missing Messier numbers filled (Column B complete)
3. Average quality calculations (Column G formulas)
4. Conditional beginner marking (Column H with IF logic)
5. Data sorted by quality (descending order)
6. Summary statistic (COUNTIF formula)
"""

import sys
import os
import re
import logging

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


def verify_time_format_standardized(workbook, sheet_name, time_column_index=2, start_row=1, end_row=9):
    """
    Verify all times are in 24-hour format (HH:MM) with no AM/PM.
    
    Args:
        workbook: Parsed spreadsheet data
        sheet_name: Sheet name
        time_column_index: Column index for time (0-based, default 2 for column C)
        start_row: First data row (0-based, after header)
        end_row: Last data row to check
    
    Returns:
        (bool, str): (success, feedback)
    """
    # Pattern for 24-hour time: HH:MM (00:00 to 23:59)
    time_24h_pattern = re.compile(r'^([01]?[0-9]|2[0-3]):[0-5][0-9]$')
    
    sheet_data = workbook['sheets'][sheet_name]
    failures = []
    
    for row_idx in range(start_row, min(end_row, len(sheet_data))):
        if row_idx < len(sheet_data) and time_column_index < len(sheet_data[row_idx]):
            cell = sheet_data[row_idx][time_column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if value:
                value_str = str(value).strip()
                
                # Check for AM/PM (should not be present)
                if 'AM' in value_str.upper() or 'PM' in value_str.upper():
                    failures.append(f"Row {row_idx+1}: Still contains AM/PM: '{value_str}'")
                    continue
                
                # Check format
                if not time_24h_pattern.match(value_str):
                    failures.append(f"Row {row_idx+1}: Invalid 24-hour format: '{value_str}'")
    
    success = len(failures) == 0
    feedback = "✅ All times standardized to 24-hour format" if success else f"❌ Time format issues: {'; '.join(failures[:3])}"
    
    return success, feedback


def verify_messier_numbers_complete(workbook, sheet_name, messier_column_index=1, start_row=1, end_row=9):
    """
    Verify no empty Messier numbers in Column B.
    
    Returns:
        (bool, str): (success, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    empty_count = 0
    
    for row_idx in range(start_row, min(end_row, len(sheet_data))):
        if row_idx < len(sheet_data) and messier_column_index < len(sheet_data[row_idx]):
            cell = sheet_data[row_idx][messier_column_index]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if not value or str(value).strip() == '':
                empty_count += 1
    
    success = empty_count == 0
    feedback = "✅ All Messier numbers filled" if success else f"❌ Found {empty_count} empty Messier numbers"
    
    return success, feedback


def verify_average_calculations(workbook, sheet_name, obs_columns=[3, 4, 5], avg_column=6, start_row=1, end_row=9):
    """
    Verify average quality calculations are correct and use formulas.
    
    Returns:
        (bool, str): (success, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    errors = []
    formula_count = 0
    
    for row_idx in range(start_row, min(end_row, len(sheet_data))):
        if row_idx >= len(sheet_data):
            continue
        
        # Get observer values
        obs_values = []
        for col_idx in obs_columns:
            if col_idx < len(sheet_data[row_idx]):
                cell = sheet_data[row_idx][col_idx]
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value is not None and str(value).strip() != '':
                    try:
                        obs_values.append(float(value))
                    except (ValueError, TypeError):
                        pass
        
        # Get average cell
        if avg_column < len(sheet_data[row_idx]):
            avg_cell = sheet_data[row_idx][avg_column]
            avg_value = avg_cell.get('value') if isinstance(avg_cell, dict) else avg_cell
            avg_formula = avg_cell.get('formula') if isinstance(avg_cell, dict) else None
            
            # Check if formula exists
            if avg_formula and 'AVERAGE' in str(avg_formula).upper():
                formula_count += 1
            
            # Calculate expected average
            if obs_values:
                expected_avg = sum(obs_values) / len(obs_values)
                
                if avg_value is not None:
                    try:
                        actual_avg = float(avg_value)
                        # Allow 0.2 tolerance for rounding differences
                        if abs(actual_avg - expected_avg) > 0.2:
                            errors.append(f"Row {row_idx+1}: Expected avg ~{expected_avg:.1f}, got {actual_avg:.1f}")
                    except (ValueError, TypeError):
                        errors.append(f"Row {row_idx+1}: Invalid average value")
    
    has_formulas = formula_count >= (end_row - start_row) * 0.7  # At least 70% have formulas
    calculation_correct = len(errors) <= 1  # Allow 1 error
    success = has_formulas and calculation_correct
    
    if success:
        feedback = f"✅ Average calculations correct ({formula_count} formulas detected)"
    elif not has_formulas:
        feedback = f"❌ Missing AVERAGE formulas (only {formula_count} found)"
    else:
        feedback = f"❌ Average calculation errors: {'; '.join(errors[:2])}"
    
    return success, feedback


def verify_conditional_logic(workbook, sheet_name, avg_column=6, beginner_column=7, start_row=1, end_row=9):
    """
    Verify beginner-friendly marking (Column H) based on avg quality >= 4.0.
    
    Returns:
        (bool, str): (success, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    errors = []
    formula_count = 0
    
    for row_idx in range(start_row, min(end_row, len(sheet_data))):
        if row_idx >= len(sheet_data):
            continue
        
        # Get average value
        if avg_column < len(sheet_data[row_idx]):
            avg_cell = sheet_data[row_idx][avg_column]
            avg_value = avg_cell.get('value') if isinstance(avg_cell, dict) else avg_cell
            
            # Get beginner cell
            if beginner_column < len(sheet_data[row_idx]):
                beginner_cell = sheet_data[row_idx][beginner_column]
                beginner_value = beginner_cell.get('value') if isinstance(beginner_cell, dict) else beginner_cell
                beginner_formula = beginner_cell.get('formula') if isinstance(beginner_cell, dict) else None
                
                # Check for IF formula
                if beginner_formula and 'IF' in str(beginner_formula).upper():
                    formula_count += 1
                
                # Verify logic
                if avg_value is not None and beginner_value is not None:
                    try:
                        avg_float = float(avg_value)
                        beginner_str = str(beginner_value).strip().lower()
                        
                        expected = "yes" if avg_float >= 4.0 else "no"
                        
                        if beginner_str != expected:
                            errors.append(f"Row {row_idx+1}: Avg={avg_float:.1f}, expected '{expected}', got '{beginner_str}'")
                    except (ValueError, TypeError):
                        pass
    
    has_formulas = formula_count >= (end_row - start_row) * 0.6  # At least 60% have formulas
    logic_correct = len(errors) <= 1
    success = has_formulas and logic_correct
    
    if success:
        feedback = f"✅ Conditional logic applied correctly ({formula_count} IF formulas)"
    elif not has_formulas:
        feedback = f"❌ Missing IF formulas (only {formula_count} found)"
    else:
        feedback = f"❌ Conditional logic errors: {'; '.join(errors[:2])}"
    
    return success, feedback


def verify_sort_order(workbook, sheet_name, avg_column=6, start_row=1, end_row=9):
    """
    Verify data is sorted in descending order by average quality.
    
    Returns:
        (bool, str): (success, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    avg_values = []
    
    for row_idx in range(start_row, min(end_row, len(sheet_data))):
        if row_idx >= len(sheet_data):
            continue
        
        if avg_column < len(sheet_data[row_idx]):
            cell = sheet_data[row_idx][avg_column]
            value = cell.get('value') if isinstance(cell, dict) else cell
            
            if value is not None:
                try:
                    avg_values.append(float(value))
                except (ValueError, TypeError):
                    pass
    
    # Check if sorted in descending order
    is_sorted = all(avg_values[i] >= avg_values[i+1] for i in range(len(avg_values)-1)) if len(avg_values) > 1 else True
    
    success = is_sorted
    feedback = "✅ Data sorted by quality (descending)" if success else "❌ Data not sorted in descending order by average quality"
    
    return success, feedback


def verify_summary_statistic(workbook, sheet_name, summary_row=11, summary_column=1):
    """
    Verify summary statistic (COUNTIF formula) for total Messier objects.
    Expected in cell B12 (row 11, column 1 in 0-indexed)
    
    Returns:
        (bool, str): (success, feedback)
    """
    sheet_data = workbook['sheets'][sheet_name]
    
    if summary_row >= len(sheet_data):
        return False, "❌ Summary row not found"
    
    if summary_column >= len(sheet_data[summary_row]):
        return False, "❌ Summary cell not found"
    
    cell = sheet_data[summary_row][summary_column]
    value = cell.get('value') if isinstance(cell, dict) else cell
    formula = cell.get('formula') if isinstance(cell, dict) else None
    
    # Check for COUNTIF formula
    has_countif = formula and 'COUNTIF' in str(formula).upper()
    
    # Check if value is reasonable (should be around 8 for the data we created)
    value_reasonable = False
    if value is not None:
        try:
            count_value = int(float(value))
            value_reasonable = 6 <= count_value <= 10  # Reasonable range
        except (ValueError, TypeError):
            pass
    
    success = has_countif and value_reasonable
    
    if success:
        feedback = f"✅ Summary statistic correct (COUNTIF formula, count={value})"
    elif not has_countif:
        feedback = f"❌ Missing COUNTIF formula in summary cell"
    elif not value_reasonable:
        feedback = f"❌ Summary count seems incorrect (got {value})"
    else:
        feedback = "❌ Summary statistic not completed"
    
    return success, feedback


def verify_astronomy_log_cleaner(traj, env_info, task_info):
    """
    Main verifier for Astronomy Log Cleaner task.
    
    Checks all 6 criteria:
    1. Time format standardization
    2. Messier numbers completion
    3. Average calculations
    4. Conditional logic
    5. Sort order
    6. Summary statistic
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/star_party_observations.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get the Observations sheet (first sheet)
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]  # "Observations" sheet
        logger.info(f"Verifying sheet: {sheet_name}")

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Criterion 1: Time format standardization
        success_1, feedback_1 = verify_time_format_standardized(workbook, sheet_name)
        if success_1:
            criteria_passed += 1
        feedback_parts.append(feedback_1)
        subscores['time_format_standardized'] = success_1

        # Criterion 2: Messier numbers complete
        success_2, feedback_2 = verify_messier_numbers_complete(workbook, sheet_name)
        if success_2:
            criteria_passed += 1
        feedback_parts.append(feedback_2)
        subscores['messier_numbers_filled'] = success_2

        # Criterion 3: Average calculations
        success_3, feedback_3 = verify_average_calculations(workbook, sheet_name)
        if success_3:
            criteria_passed += 1
        feedback_parts.append(feedback_3)
        subscores['averages_calculated'] = success_3

        # Criterion 4: Conditional logic
        success_4, feedback_4 = verify_conditional_logic(workbook, sheet_name)
        if success_4:
            criteria_passed += 1
        feedback_parts.append(feedback_4)
        subscores['conditional_logic_applied'] = success_4

        # Criterion 5: Sort order
        success_5, feedback_5 = verify_sort_order(workbook, sheet_name)
        if success_5:
            criteria_passed += 1
        feedback_parts.append(feedback_5)
        subscores['data_sorted'] = success_5

        # Criterion 6: Summary statistic
        success_6, feedback_6 = verify_summary_statistic(workbook, sheet_name)
        if success_6:
            criteria_passed += 1
        feedback_parts.append(feedback_6)
        subscores['summary_generated'] = success_6

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 5/6 criteria
        
        feedback = " | ".join(feedback_parts)
        
        if passed:
            feedback = f"🎉 Task completed successfully ({criteria_passed}/{total_criteria}) | " + feedback
        else:
            feedback = f"❌ Task incomplete ({criteria_passed}/{total_criteria} criteria) | " + feedback
        
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
