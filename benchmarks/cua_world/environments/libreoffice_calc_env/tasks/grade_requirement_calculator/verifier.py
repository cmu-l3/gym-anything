#!/usr/bin/env python3
"""
Verifier for Grade Requirement Calculator task
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
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grade_calculator(traj, env_info, task_info):
    """
    Verify grade calculator task completion.
    
    Checks:
    1. Current weighted grade calculated correctly
    2. Homework average excludes lowest score
    3. Required final score calculated correctly
    4. Mathematical feasibility assessed
    5. Formulas used (not hardcoded values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/grade_calculator.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get first sheet (Grade Calculator)
        sheet_name = list(workbook['sheets'].keys())[0]

        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []

        # Get reference data from Assignment Details sheet if available
        homework_percentages = [90, 76, 84, 70, 96]  # First 5 homework scores
        quiz_percentages = [90, 85, 80, 95]  # First 4 quiz scores
        midterm_score = 82

        # Calculate expected values
        # Homework average (drop lowest): (90 + 76 + 84 + 96) / 4 = 86.5 (dropped 70)
        hw_sorted = sorted(homework_percentages)
        hw_without_lowest = hw_sorted[1:]  # Remove lowest
        expected_hw_avg = sum(hw_without_lowest) / len(hw_without_lowest)  # 86.5
        
        # Quiz average: (90 + 85 + 80 + 95) / 4 = 87.5
        expected_quiz_avg = sum(quiz_percentages) / len(quiz_percentages)  # 87.5
        
        # Current weighted grade (only completed categories):
        # Homework contributes: 86.5 * 0.25 = 21.625
        # Quizzes contribute: 87.5 * 0.15 = 13.125
        # Midterm contributes: 82 * 0.20 = 16.4
        # Total from completed: 51.15 out of 60% possible (Homework + Quiz + Midterm = 25% + 15% + 20% = 60%)
        expected_current_weighted = (expected_hw_avg * 0.25) + (expected_quiz_avg * 0.15) + (midterm_score * 0.20)
        # This is 51.15 points out of 60 possible, or 85.25% of completed work
        
        # Required final score calculation:
        # Target: 87%
        # Currently have: 51.15 points (from 60% of grade)
        # Need: 87 - 51.15 = 35.85 points from remaining 40% (Project 15% + Final 25%)
        # If project = 90%, contributes: 90 * 0.15 = 13.5
        # Need from final: 35.85 - 13.5 = 22.35
        # Final exam score needed: 22.35 / 0.25 = 89.4%
        
        target_grade = 87.0
        project_score_90 = 90.0
        remaining_needed = target_grade - expected_current_weighted
        after_project_90 = remaining_needed - (project_score_90 * 0.15)
        expected_final_score_90 = after_project_90 / 0.25  # Should be around 89.4%

        logger.info(f"Expected homework avg (drop lowest): {expected_hw_avg:.2f}")
        logger.info(f"Expected quiz avg: {expected_quiz_avg:.2f}")
        logger.info(f"Expected current weighted grade: {expected_current_weighted:.2f}")
        logger.info(f"Expected required final (project=90): {expected_final_score_90:.2f}")

        # Criterion 1: Homework average calculation (with drop lowest)
        # Should be in cell C5 or referenced somewhere
        hw_avg_cell = get_cell_value(workbook, sheet_name, 'C5')
        hw_avg_formula = get_cell_formula(workbook, sheet_name, 'C5')
        
        hw_correct = False
        if hw_avg_cell is not None:
            try:
                hw_value = float(str(hw_avg_cell).replace('%', ''))
                if abs(hw_value - expected_hw_avg) < 1.0:  # Within 1%
                    criteria_passed += 1
                    hw_correct = True
                    feedback_parts.append(f"✅ Homework average correct: {hw_value:.1f}% (drop lowest applied)")
                else:
                    feedback_parts.append(f"❌ Homework average incorrect: expected ~{expected_hw_avg:.1f}%, got {hw_value:.1f}%")
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Homework average cell has non-numeric value: {hw_avg_cell}")
        else:
            feedback_parts.append("❌ Homework average not calculated (cell C5 empty)")

        # Criterion 2: Current weighted grade calculation
        # Should be in cell B11
        current_grade_cell = get_cell_value(workbook, sheet_name, 'B11')
        current_grade_formula = get_cell_formula(workbook, sheet_name, 'B11')
        
        current_grade_correct = False
        if current_grade_cell is not None:
            try:
                current_value = float(str(current_grade_cell).replace('%', ''))
                if abs(current_value - expected_current_weighted) < 1.0:  # Within 1%
                    criteria_passed += 1
                    current_grade_correct = True
                    feedback_parts.append(f"✅ Current weighted grade correct: {current_value:.1f}%")
                else:
                    feedback_parts.append(f"⚠️ Current weighted grade: expected ~{expected_current_weighted:.1f}%, got {current_value:.1f}%")
                    # Give partial credit if it's reasonable
                    if abs(current_value - expected_current_weighted) < 3.0:
                        criteria_passed += 0.5
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Current grade cell has non-numeric value: {current_grade_cell}")
        else:
            feedback_parts.append("❌ Current weighted grade not calculated (cell B11 empty)")

        # Criterion 3: Required final score calculation
        # Should be in cell D14 (for project=90 scenario)
        required_final_cell = get_cell_value(workbook, sheet_name, 'D14')
        required_final_formula = get_cell_formula(workbook, sheet_name, 'D14')
        
        required_final_correct = False
        if required_final_cell is not None:
            try:
                required_value = float(str(required_final_cell).replace('%', ''))
                if abs(required_value - expected_final_score_90) < 2.0:  # Within 2%
                    criteria_passed += 1
                    required_final_correct = True
                    feedback_parts.append(f"✅ Required final score calculated: {required_value:.1f}%")
                else:
                    feedback_parts.append(f"⚠️ Required final score: expected ~{expected_final_score_90:.1f}%, got {required_value:.1f}%")
                    # Give partial credit if it's in reasonable range
                    if abs(required_value - expected_final_score_90) < 5.0:
                        criteria_passed += 0.5
            except (ValueError, TypeError):
                feedback_parts.append(f"❌ Required final score has non-numeric value: {required_final_cell}")
        else:
            feedback_parts.append("❌ Required final score not calculated (cell D14 empty)")

        # Criterion 4: Feasibility check (is required score <= 100?)
        feasibility_correct = False
        if required_final_cell is not None:
            try:
                required_value = float(str(required_final_cell).replace('%', ''))
                if required_value <= 100:
                    criteria_passed += 1
                    feasibility_correct = True
                    if required_value <= 95:
                        feedback_parts.append(f"✅ Target grade achievable (need {required_value:.1f}% on final)")
                    else:
                        feedback_parts.append(f"⚠️ Target grade barely achievable (need {required_value:.1f}% on final)")
                else:
                    criteria_passed += 1  # Still correct to identify it's not achievable
                    feasibility_correct = True
                    feedback_parts.append(f"✅ Correctly identified: Target unachievable (would need {required_value:.1f}% on final)")
            except (ValueError, TypeError):
                pass
        
        if not feasibility_correct:
            feedback_parts.append("❌ Feasibility not assessed")

        # Criterion 5: Formula structure validation (not hardcoded)
        formulas_used = False
        formula_count = 0
        
        if hw_avg_formula and (any(fn in str(hw_avg_formula).upper() for fn in ['SUM', 'AVERAGE', 'MIN', 'MAX', 'COUNT'])):
            formula_count += 1
        
        if current_grade_formula and ('0.25' in str(current_grade_formula) or '0.15' in str(current_grade_formula)):
            formula_count += 1
        
        if required_final_formula and ('0.25' in str(required_final_formula) or '87' in str(required_final_formula)):
            formula_count += 1
        
        if formula_count >= 2:  # At least 2 key formulas present
            criteria_passed += 1
            formulas_used = True
            feedback_parts.append(f"✅ Formulas used (not hardcoded values) - {formula_count} key formulas found")
        else:
            feedback_parts.append(f"⚠️ Limited formula usage detected ({formula_count} formulas found)")
            if formula_count >= 1:
                criteria_passed += 0.5  # Partial credit

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria (80%)
        
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent grade calculation!")
        elif passed:
            feedback_parts.append("✅ Grade calculator completed successfully")
        else:
            feedback_parts.append("❌ Grade calculator requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "homework_drop_lowest": hw_correct,
                "current_weighted_grade": current_grade_correct,
                "required_final_score": required_final_correct,
                "feasibility_check": feasibility_correct,
                "formulas_used": formulas_used
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
