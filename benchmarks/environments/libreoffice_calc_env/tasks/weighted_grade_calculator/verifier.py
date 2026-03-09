#!/usr/bin/env python3
"""
Verifier for Weighted Grade Calculator task.
Validates weighted average formulas and letter grade assignments.
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_environment,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def detect_weighted_formula(formula_string):
    """
    Check if formula appears to be a weighted average.
    
    Args:
        formula_string: Raw formula string from cell
        
    Returns:
        bool: True if appears to be weighted average formula
    """
    if not formula_string or not formula_string.startswith('='):
        return False
    
    formula_upper = formula_string.upper()
    
    # Check for multiplication and addition operators
    has_mult = '*' in formula_string
    has_add = '+' in formula_string
    
    # Check for weight-like values (0.3, 0.4, 30%, 40%)
    weight_pattern = r'(0\.[234][0-9]?|[234]0%)'
    has_weights = bool(re.search(weight_pattern, formula_string))
    
    # Check for references to columns B, C, D (homework, midterm, final)
    has_data_refs = ('B' in formula_upper and 'C' in formula_upper and 'D' in formula_upper)
    
    return has_mult and has_add and (has_weights or has_data_refs)


def get_expected_letter_grade(percentage):
    """
    Get expected letter grade for a percentage.
    
    Args:
        percentage: Grade percentage (0-100)
        
    Returns:
        str: Expected letter grade
    """
    if percentage >= 90:
        return "A"
    elif percentage >= 80:
        return "B"
    elif percentage >= 70:
        return "C"
    elif percentage >= 60:
        return "D"
    else:
        return "F"


def calculate_weighted_grade(hw_score, midterm_score, final_score):
    """
    Calculate expected weighted grade.
    
    Args:
        hw_score: Homework score (0-100)
        midterm_score: Midterm score (0-100)
        final_score: Final exam score (0-100)
        
    Returns:
        float: Weighted grade percentage
    """
    return (hw_score * 0.30) + (midterm_score * 0.30) + (final_score * 0.40)


def check_weighted_grades(traj, env_info, task_info):
    """
    Main verification function for weighted grade calculator task.
    
    Verifies:
    1. Weighted formula present and correct
    2. All calculations accurate
    3. Letter grade IF formula present
    4. All letter grades correct
    5. Formulas propagated to all rows
    6. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the gradebook file
    container_path = "/home/ga/Documents/gradebook.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods', 'xlsx']
    )
    
    if not success:
        # Try CSV as fallback
        container_path = "/home/ga/Documents/gradebook.csv"
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats=['csv']
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to load gradebook: {error}"
            }
    
    data = file_info['sheet_data']
    temp_dir = file_info.get('temp_dir')
    
    try:
        # Get sheet name (should be first sheet)
        sheets = list(data.get('sheets', {}).keys())
        if not sheets:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in gradebook"
            }
        
        sheet_name = sheets[0]
        
        # Expected student data (from setup script)
        students = [
            {'name': 'Alice Johnson', 'hw': 85, 'mid': 92, 'final': 88},
            {'name': 'Bob Smith', 'hw': 78, 'mid': 81, 'final': 85},
            {'name': 'Carol Williams', 'hw': 92, 'mid': 95, 'final': 91},
            {'name': 'David Brown', 'hw': 65, 'mid': 70, 'final': 68},
            {'name': 'Emma Davis', 'hw': 88, 'mid': 84, 'final': 90},
            {'name': 'Frank Miller', 'hw': 72, 'mid': 75, 'final': 78},
            {'name': 'Grace Wilson', 'hw': 95, 'mid': 98, 'final': 96},
            {'name': 'Henry Moore', 'hw': 58, 'mid': 62, 'final': 55}
        ]
        
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Weighted formula present
        first_grade_formula = get_cell_formula(data, sheet_name, "E2")
        has_formula = first_grade_formula and detect_weighted_formula(first_grade_formula)
        
        if has_formula:
            criteria_met += 1
            feedback_parts.append(f"✅ Weighted average formula detected: {first_grade_formula}")
        else:
            feedback_parts.append(f"❌ Missing or invalid weighted average formula in E2 (got: {first_grade_formula or 'none'})")
        
        # Criterion 2: Calculation accuracy for all students
        correct_calculations = 0
        calculation_details = []
        
        for idx, student in enumerate(students):
            row_num = idx + 2  # Data starts at row 2 (after header)
            cell_ref_grade = f"E{row_num}"
            
            # Get calculated grade
            calc_grade = get_cell_value(data, sheet_name, cell_ref_grade)
            
            # Calculate expected weighted grade
            expected_grade = calculate_weighted_grade(student['hw'], student['mid'], student['final'])
            
            # Check calculation accuracy
            if calc_grade is not None:
                try:
                    calc_grade_num = float(calc_grade)
                    diff = abs(calc_grade_num - expected_grade)
                    if diff <= 0.1:
                        correct_calculations += 1
                    else:
                        calculation_details.append(
                            f"{student['name']}: expected {expected_grade:.1f}, got {calc_grade_num:.1f}"
                        )
                except (ValueError, TypeError):
                    calculation_details.append(
                        f"{student['name']}: invalid value '{calc_grade}'"
                    )
        
        if correct_calculations == len(students):
            criteria_met += 1
            feedback_parts.append(f"✅ All {len(students)} weighted calculations correct")
        else:
            feedback_parts.append(
                f"❌ Only {correct_calculations}/{len(students)} calculations correct"
            )
            if calculation_details:
                logger.info(f"Calculation errors: {calculation_details[:3]}")  # Log first 3 errors
        
        # Criterion 3: Letter grade formula present
        first_letter_formula = get_cell_formula(data, sheet_name, "F2")
        has_if_formula = first_letter_formula and 'IF' in first_letter_formula.upper()
        
        if has_if_formula:
            criteria_met += 1
            feedback_parts.append(f"✅ IF formula detected for letter grades")
        else:
            feedback_parts.append(f"❌ Missing IF formula in F2 (got: {first_letter_formula or 'none'})")
        
        # Criterion 4: All letter grades correct
        correct_letters = 0
        letter_details = []
        
        for idx, student in enumerate(students):
            row_num = idx + 2
            cell_ref_grade = f"E{row_num}"
            cell_ref_letter = f"F{row_num}"
            
            # Get values
            calc_grade = get_cell_value(data, sheet_name, cell_ref_grade)
            letter_grade = get_cell_value(data, sheet_name, cell_ref_letter)
            
            # Calculate expected
            expected_grade = calculate_weighted_grade(student['hw'], student['mid'], student['final'])
            expected_letter = get_expected_letter_grade(expected_grade)
            
            # Check letter grade
            if letter_grade and str(letter_grade).strip().upper() == expected_letter:
                correct_letters += 1
            else:
                letter_details.append(
                    f"{student['name']} ({expected_grade:.1f}%): expected {expected_letter}, got {letter_grade}"
                )
        
        if correct_letters == len(students):
            criteria_met += 1
            feedback_parts.append(f"✅ All {len(students)} letter grades correct")
        else:
            feedback_parts.append(f"❌ Only {correct_letters}/{len(students)} letter grades correct")
            if letter_details:
                logger.info(f"Letter grade errors: {letter_details[:3]}")  # Log first 3 errors
        
        # Criterion 5: Formula propagation (check multiple rows have formulas)
        grade_formulas_found = 0
        letter_formulas_found = 0
        
        for idx in range(len(students)):
            row_num = idx + 2
            if get_cell_formula(data, sheet_name, f"E{row_num}"):
                grade_formulas_found += 1
            if get_cell_formula(data, sheet_name, f"F{row_num}"):
                letter_formulas_found += 1
        
        # Need at least 80% coverage
        propagation_threshold = int(len(students) * 0.8)
        if grade_formulas_found >= propagation_threshold and letter_formulas_found >= propagation_threshold:
            criteria_met += 1
            feedback_parts.append(
                f"✅ Formulas propagated (E: {grade_formulas_found}/{len(students)}, F: {letter_formulas_found}/{len(students)})"
            )
        else:
            feedback_parts.append(
                f"❌ Incomplete formula propagation (E: {grade_formulas_found}/{len(students)}, F: {letter_formulas_found}/{len(students)})"
            )
        
        # Criterion 6: No formula errors
        has_errors = False
        error_cells = []
        
        for idx in range(len(students)):
            row_num = idx + 2
            for col in ['E', 'F']:
                cell_ref = f"{col}{row_num}"
                cell_val = get_cell_value(data, sheet_name, cell_ref)
                if cell_val and isinstance(cell_val, str) and cell_val.startswith('#'):
                    has_errors = True
                    error_cells.append(cell_ref)
        
        if not has_errors:
            criteria_met += 1
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append(f"❌ Formula errors in cells: {', '.join(error_cells[:5])}")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 85  # Need 5/6 criteria (85%)
        
        # Build feedback message
        feedback = " | ".join(feedback_parts)
        feedback += f" || Score: {criteria_met}/{total_criteria} criteria met"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "weighted_formula_present": has_formula,
                "calculations_correct": correct_calculations == len(students),
                "letter_formula_present": has_if_formula,
                "letter_grades_correct": correct_letters == len(students),
                "formulas_propagated": grade_formulas_found >= propagation_threshold,
                "no_errors": not has_errors
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
        if temp_dir:
            cleanup_verification_environment(temp_dir)
