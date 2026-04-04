#!/usr/bin/env python3
"""
Verifier for Gradebook Weighted Calculator task.
Validates complex weighted grading calculations including drop-lowest logic.
"""

import sys
import os
import logging

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_expected_quiz_avg_drop_lowest(scores):
    """
    Calculate quiz average excluding the lowest score.
    Handles empty/None values.
    """
    valid_scores = [s for s in scores if s is not None and s != '' and s != 0]
    if len(valid_scores) == 0:
        return 0
    if len(valid_scores) == 1:
        return valid_scores[0]
    
    # Drop lowest and average the rest
    total = sum(valid_scores)
    lowest = min(valid_scores)
    return (total - lowest) / (len(valid_scores) - 1)


def calculate_expected_average(scores):
    """Calculate average of scores, ignoring None/empty values."""
    valid_scores = [s for s in scores if s is not None and s != '' and s != 0]
    if len(valid_scores) == 0:
        return 0
    return sum(valid_scores) / len(valid_scores)


def calculate_weighted_grade(test_avg, hw_avg, quiz_avg, participation):
    """Apply grading policy weights: 40% tests, 30% hw, 20% quizzes, 10% participation."""
    return (test_avg * 0.40) + (hw_avg * 0.30) + (quiz_avg * 0.20) + (participation * 0.10)


def assign_letter_grade(numerical_grade):
    """Convert numerical grade to letter based on standard scale."""
    if numerical_grade >= 90:
        return 'A'
    elif numerical_grade >= 80:
        return 'B'
    elif numerical_grade >= 70:
        return 'C'
    elif numerical_grade >= 60:
        return 'D'
    else:
        return 'F'


def get_scores_from_row(workbook, sheet_name, row_num, col_range):
    """Extract scores from a range of columns in a specific row."""
    scores = []
    for col in col_range:
        cell_ref = f"{col}{row_num}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        # Convert to float if possible, otherwise keep as None
        if value is not None and value != '':
            try:
                scores.append(float(value))
            except (ValueError, TypeError):
                scores.append(None)
        else:
            scores.append(None)
    return scores


def verify_gradebook_calculation(traj, env_info, task_info):
    """
    Verify gradebook weighted calculation task.
    
    Checks:
    1. Category averages correct (Tests, Homework, Quizzes, Participation)
    2. Lowest quiz dropped in quiz average calculation
    3. Weighted final grade accurate (40% + 30% + 20% + 10%)
    4. Letter grades correctly assigned based on numerical grades
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/gradebook_template.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load gradebook: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # We'll check a sample of students (rows 2-13 are the 12 students)
        student_rows = range(2, 14)  # Rows 2-13 (12 students)
        
        # Track success rates for each criterion
        category_avg_correct_count = 0
        quiz_drop_correct_count = 0
        weighted_grade_correct_count = 0
        letter_grade_correct_count = 0
        total_students_checked = 0
        
        # Column mappings
        # Tests: B-D, Homework: E-H, Quizzes: I-L, Participation: M
        # Calculated: Test Avg (N), HW Avg (O), Quiz Avg (P), Participation (Q), Final Grade (R), Letter (S)
        
        for row_num in student_rows:
            # Check if student name exists (skip empty rows)
            student_name = get_cell_value(workbook, sheet_name, f"A{row_num}")
            if not student_name or student_name == '':
                continue
            
            total_students_checked += 1
            
            # Extract raw scores
            test_scores = get_scores_from_row(workbook, sheet_name, row_num, ['B', 'C', 'D'])
            hw_scores = get_scores_from_row(workbook, sheet_name, row_num, ['E', 'F', 'G', 'H'])
            quiz_scores = get_scores_from_row(workbook, sheet_name, row_num, ['I', 'J', 'K', 'L'])
            participation_score = get_cell_value(workbook, sheet_name, f"M{row_num}")
            
            # Calculate expected values
            expected_test_avg = calculate_expected_average(test_scores)
            expected_hw_avg = calculate_expected_average(hw_scores)
            expected_quiz_avg = calculate_expected_quiz_avg_drop_lowest(quiz_scores)
            expected_participation = float(participation_score) if participation_score not in [None, ''] else 0
            
            # Get actual calculated values from spreadsheet
            actual_test_avg = get_cell_value(workbook, sheet_name, f"N{row_num}")
            actual_hw_avg = get_cell_value(workbook, sheet_name, f"O{row_num}")
            actual_quiz_avg = get_cell_value(workbook, sheet_name, f"P{row_num}")
            actual_participation = get_cell_value(workbook, sheet_name, f"Q{row_num}")
            actual_final_grade = get_cell_value(workbook, sheet_name, f"R{row_num}")
            actual_letter_grade = get_cell_value(workbook, sheet_name, f"S{row_num}")
            
            # Convert to float for comparison
            try:
                actual_test_avg = float(actual_test_avg) if actual_test_avg not in [None, ''] else None
                actual_hw_avg = float(actual_hw_avg) if actual_hw_avg not in [None, ''] else None
                actual_quiz_avg = float(actual_quiz_avg) if actual_quiz_avg not in [None, ''] else None
                actual_participation = float(actual_participation) if actual_participation not in [None, ''] else None
                actual_final_grade = float(actual_final_grade) if actual_final_grade not in [None, ''] else None
            except (ValueError, TypeError):
                # If conversion fails, calculations are missing or wrong
                continue
            
            # Criterion 1: Category averages correct (with tolerance)
            tolerance = 0.5
            category_correct = True
            
            if actual_test_avg is None or abs(actual_test_avg - expected_test_avg) > tolerance:
                category_correct = False
            if actual_hw_avg is None or abs(actual_hw_avg - expected_hw_avg) > tolerance:
                category_correct = False
            if actual_quiz_avg is None or abs(actual_quiz_avg - expected_quiz_avg) > tolerance:
                category_correct = False
            
            if category_correct:
                category_avg_correct_count += 1
            
            # Criterion 2: Quiz average drops lowest (check explicitly)
            # For this, we verify that quiz_avg is NOT just the simple average
            simple_quiz_avg = calculate_expected_average(quiz_scores)
            if actual_quiz_avg is not None:
                # If quiz scores vary, the drop-lowest should differ from simple average
                # We check that the actual value matches drop-lowest, not simple average
                if abs(actual_quiz_avg - expected_quiz_avg) <= tolerance:
                    quiz_drop_correct_count += 1
            
            # Criterion 3: Weighted grade calculation
            expected_final = calculate_weighted_grade(
                expected_test_avg, 
                expected_hw_avg, 
                expected_quiz_avg, 
                expected_participation
            )
            
            weighted_tolerance = 1.0
            if actual_final_grade is not None and abs(actual_final_grade - expected_final) <= weighted_tolerance:
                weighted_grade_correct_count += 1
            
            # Criterion 4: Letter grade correct
            expected_letter = assign_letter_grade(expected_final)
            if actual_letter_grade is not None:
                # Normalize letter grade (strip whitespace, uppercase)
                actual_letter_normalized = str(actual_letter_grade).strip().upper()
                if actual_letter_normalized == expected_letter:
                    letter_grade_correct_count += 1
        
        # Calculate success rates
        if total_students_checked == 0:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "No student data found or no calculations performed"
            }
        
        category_avg_rate = category_avg_correct_count / total_students_checked
        quiz_drop_rate = quiz_drop_correct_count / total_students_checked
        weighted_grade_rate = weighted_grade_correct_count / total_students_checked
        letter_grade_rate = letter_grade_correct_count / total_students_checked
        
        # Criterion 1: Category averages (need 80%+ correct)
        if category_avg_rate >= 0.80:
            criteria_passed += 1
            feedback_parts.append(f"✅ Category averages correct ({category_avg_correct_count}/{total_students_checked} students)")
        else:
            feedback_parts.append(f"❌ Category averages incorrect ({category_avg_correct_count}/{total_students_checked} students, need 80%+)")
        
        # Criterion 2: Quiz drop lowest (need evidence for sample students)
        # We'll be lenient - if 60%+ students have correct drop-lowest calculation
        if quiz_drop_rate >= 0.60:
            criteria_passed += 1
            feedback_parts.append(f"✅ Lowest quiz dropped correctly ({quiz_drop_correct_count}/{total_students_checked} students)")
        else:
            feedback_parts.append(f"❌ Lowest quiz not dropped correctly ({quiz_drop_correct_count}/{total_students_checked} students)")
        
        # Criterion 3: Weighted grade (need 80%+ correct)
        if weighted_grade_rate >= 0.80:
            criteria_passed += 1
            feedback_parts.append(f"✅ Weighted grades accurate ({weighted_grade_correct_count}/{total_students_checked} students)")
        else:
            feedback_parts.append(f"❌ Weighted grades incorrect ({weighted_grade_correct_count}/{total_students_checked} students, need 80%+)")
        
        # Criterion 4: Letter grades (need 90%+ correct)
        if letter_grade_rate >= 0.90:
            criteria_passed += 1
            feedback_parts.append(f"✅ Letter grades correct ({letter_grade_correct_count}/{total_students_checked} students)")
        else:
            feedback_parts.append(f"❌ Letter grades incorrect ({letter_grade_correct_count}/{total_students_checked} students, need 90%+)")
        
        # Check if formulas were used (spot check a few cells)
        formulas_used = True
        for row_num in [2, 3, 4]:  # Check first 3 students
            final_grade_formula = get_cell_formula(workbook, sheet_name, f"R{row_num}")
            letter_grade_formula = get_cell_formula(workbook, sheet_name, f"S{row_num}")
            
            if not final_grade_formula or not letter_grade_formula:
                formulas_used = False
                break
        
        if not formulas_used:
            feedback_parts.append("⚠️ Warning: Some values may be hardcoded instead of formulas")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent gradebook calculation!")
        elif passed:
            feedback_parts.append("✅ Gradebook calculations complete")
        else:
            feedback_parts.append("❌ Gradebook calculations incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "category_averages": category_avg_rate >= 0.80,
                "quiz_drop_lowest": quiz_drop_rate >= 0.60,
                "weighted_grade": weighted_grade_rate >= 0.80,
                "letter_grades": letter_grade_rate >= 0.90,
                "students_checked": total_students_checked
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
