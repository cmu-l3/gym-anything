#!/usr/bin/env python3
"""
Verifier for Grade Calculator Task
Verifies weighted grade calculations and what-if analysis for required final exam score
"""

import sys
import os
import logging
import re

# Add utils to path (relative path for host-side verification)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grade_calculator(traj, env_info, task_info):
    """
    Verify grade calculation and what-if analysis.
    
    Checks:
    1. Current grade formula exists and is correct
    2. Current grade value is approximately 56.3 (±1%)
    3. Needed final score formula exists
    4. Needed final score value is approximately 96.3 (±1%)
    5. Algebraic verification: current + (needed * 0.35) ≈ 90
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification environment
    container_path = "/home/ga/Documents/my_grades.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods', 'xlsx']
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load gradebook: {error}"}

    try:
        sheet_data = file_info['sheet_data']
        sheet_names = get_sheet_names(sheet_data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_met = 0
        total_criteria = 5
        feedback_parts = []
        
        # Expected values based on the template
        homework_scores = [95, 88, 92, 100, 85]
        quiz_scores = [82, 90, 78, 88]
        midterm_score = 84
        target_grade = 90.0
        
        # Calculate expected values
        homework_avg = sum(homework_scores) / len(homework_scores)  # 92.0
        quiz_avg = sum(quiz_scores) / len(quiz_scores)              # 84.5
        
        # Expected current grade (before final)
        # = (homework_avg * 0.20) + (quiz_avg * 0.20) + (midterm * 0.25)
        expected_current = (homework_avg * 0.20) + (quiz_avg * 0.20) + (midterm_score * 0.25)
        # = 18.4 + 16.9 + 21.0 = 56.3
        
        # Expected needed final score
        # = (target - current) / 0.35
        expected_needed = (target_grade - expected_current) / 0.35
        # = (90 - 56.3) / 0.35 = 33.7 / 0.35 = 96.285...
        
        logger.info(f"Expected current grade: {expected_current:.2f}%")
        logger.info(f"Expected needed final: {expected_needed:.2f}%")
        
        # Verify category averages are calculated (optional check for context)
        hw_avg_cell = get_cell_value(sheet_data, sheet_name, 'B9')
        quiz_avg_cell = get_cell_value(sheet_data, sheet_name, 'B16')
        logger.info(f"Homework average (B9): {hw_avg_cell}")
        logger.info(f"Quiz average (B16): {quiz_avg_cell}")
        
        # CRITERION 1: Current Grade Formula Exists
        current_grade_formula = get_cell_formula(sheet_data, sheet_name, 'B21')
        logger.info(f"Current grade formula (B21): {current_grade_formula}")
        
        if current_grade_formula and '=' in str(current_grade_formula):
            criteria_met += 1
            feedback_parts.append(f"✅ Current grade uses formula: {current_grade_formula}")
        else:
            feedback_parts.append("❌ Current grade cell (B21) should contain a formula")
        
        # CRITERION 2: Current Grade Accuracy
        current_grade_value = get_cell_value(sheet_data, sheet_name, 'B21')
        logger.info(f"Current grade value (B21): {current_grade_value}")
        
        current_accurate = False
        if current_grade_value is not None:
            try:
                current_float = float(current_grade_value)
                # Allow 1% tolerance
                if abs(current_float - expected_current) <= 1.0:
                    criteria_met += 1
                    current_accurate = True
                    feedback_parts.append(f"✅ Current grade accurate: {current_float:.2f}% (expected ~{expected_current:.2f}%)")
                else:
                    feedback_parts.append(f"❌ Current grade incorrect: {current_float:.2f}%, expected ~{expected_current:.2f}%")
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Current grade value invalid: {current_grade_value}")
        else:
            feedback_parts.append("❌ Current grade cell (B21) is empty")
        
        # CRITERION 3: Needed Final Score Formula Exists
        needed_formula = get_cell_formula(sheet_data, sheet_name, 'B23')
        logger.info(f"Needed final formula (B23): {needed_formula}")
        
        if needed_formula and '=' in str(needed_formula):
            criteria_met += 1
            feedback_parts.append(f"✅ Needed final score uses formula: {needed_formula}")
        else:
            feedback_parts.append("❌ Needed final score cell (B23) should contain a formula")
        
        # CRITERION 4: Needed Final Score Accuracy
        needed_value = get_cell_value(sheet_data, sheet_name, 'B23')
        logger.info(f"Needed final value (B23): {needed_value}")
        
        needed_accurate = False
        if needed_value is not None:
            try:
                needed_float = float(needed_value)
                # Allow 1% tolerance
                if abs(needed_float - expected_needed) <= 1.5:  # Slightly larger tolerance due to rounding
                    criteria_met += 1
                    needed_accurate = True
                    feedback_parts.append(f"✅ Needed final score accurate: {needed_float:.2f}% (expected ~{expected_needed:.2f}%)")
                else:
                    feedback_parts.append(f"❌ Needed final score incorrect: {needed_float:.2f}%, expected ~{expected_needed:.2f}%")
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Needed final score value invalid: {needed_value}")
        else:
            feedback_parts.append("❌ Needed final score cell (B23) is empty")
        
        # CRITERION 5: Algebraic Verification
        # If student gets needed_value on final, do they achieve target grade?
        if current_grade_value is not None and needed_value is not None:
            try:
                current_float = float(current_grade_value)
                needed_float = float(needed_value)
                
                # Calculate final grade with this final exam score
                final_grade = current_float + (needed_float * 0.35)
                
                logger.info(f"Verification: {current_float:.2f} + ({needed_float:.2f} × 0.35) = {final_grade:.2f}")
                
                # Check if this produces target grade (±1%)
                if abs(final_grade - target_grade) <= 1.0:
                    criteria_met += 1
                    feedback_parts.append(f"✅ Algebra verified: Scoring {needed_float:.1f}% on final → {final_grade:.1f}% overall")
                else:
                    feedback_parts.append(f"❌ Algebra check failed: {needed_float:.1f}% on final → {final_grade:.1f}% (expected {target_grade}%)")
            except (ValueError, TypeError) as e:
                feedback_parts.append(f"❌ Could not verify algebra: invalid values")
        else:
            feedback_parts.append("❌ Cannot verify algebra: missing values")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 4/5 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent grade calculation and what-if analysis!")
        elif passed:
            feedback_parts.append("✅ Grade calculator task completed")
        else:
            feedback_parts.append("❌ Grade calculator incomplete or incorrect")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "current_grade_formula": current_grade_formula is not None and '=' in str(current_grade_formula),
                "current_grade_accurate": current_accurate,
                "needed_formula": needed_formula is not None and '=' in str(needed_formula),
                "needed_accurate": needed_accurate,
                "algebra_verified": criteria_met >= 5
            },
            "details": {
                "criteria_met": criteria_met,
                "total_criteria": total_criteria,
                "expected_current_grade": round(expected_current, 2),
                "expected_needed_final": round(expected_needed, 2),
                "actual_current_grade": current_grade_value,
                "actual_needed_final": needed_value
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
        # Cleanup temporary files
        cleanup_verification_environment(file_info.get('temp_dir'))
