#!/usr/bin/env python3
"""
Verifier for Progressive Overload Calculator task.
Checks formulas, logic, conditional formatting, and calculations.
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_countifs_formula_present(sheet_data, sheet_name):
    """Check if any column contains COUNTIFS formula"""
    try:
        rows = sheet_data['sheets'][sheet_name]
        for row in rows:
            for cell in row:
                formula = cell.get('formula', '') if isinstance(cell, dict) else None
                if formula and 'COUNTIFS' in formula.upper():
                    logger.info(f"Found COUNTIFS formula: {formula}")
                    return True
        return False
    except Exception as e:
        logger.error(f"Error checking COUNTIFS: {e}")
        return False


def check_date_calculation_present(sheet_data, sheet_name):
    """Check if any column contains TODAY() or date calculations"""
    try:
        rows = sheet_data['sheets'][sheet_name]
        for row in rows:
            for cell in row:
                formula = cell.get('formula', '') if isinstance(cell, dict) else None
                if formula and ('TODAY()' in formula.upper() or 'NOW()' in formula.upper()):
                    logger.info(f"Found date calculation: {formula}")
                    return True
        return False
    except Exception as e:
        logger.error(f"Error checking date calculations: {e}")
        return False


def check_complex_if_logic(sheet_data, sheet_name):
    """Check if any column contains complex IF/AND/OR logic"""
    try:
        rows = sheet_data['sheets'][sheet_name]
        for row in rows:
            for cell in row:
                formula = cell.get('formula', '') if isinstance(cell, dict) else None
                if formula:
                    formula_upper = formula.upper()
                    # Look for IF combined with AND/OR
                    if 'IF' in formula_upper and ('AND' in formula_upper or 'OR' in formula_upper):
                        logger.info(f"Found complex IF logic: {formula}")
                        return True
        return False
    except Exception as e:
        logger.error(f"Error checking IF logic: {e}")
        return False


def verify_squat_progression_logic(sheet_data, sheet_name):
    """
    Verify that Squat at 235 lbs with multiple successful sessions shows ready for increase.
    Based on the data, Squat at 235 lbs appears 5 times with all 5 reps (rows ~29-46).
    Should be marked as ready for increase.
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        # Find rows where Exercise=Squat, Weight=235, Reps Completed=5
        squat_235_count = 0
        ready_status = None
        
        for idx, row in enumerate(rows):
            if len(row) < 6:  # Need at least 6 columns
                continue
            
            exercise = row[1].get('value', '') if isinstance(row[1], dict) else row[1]
            weight = row[2].get('value', '') if isinstance(row[2], dict) else row[2]
            reps_completed = row[3].get('value', '') if isinstance(row[3], dict) else row[3]
            notes = row[5].get('value', '') if isinstance(row[5], dict) else row[5] if len(row) > 5 else ''
            
            # Check if this is a Squat at 235 lbs with 5 reps
            if (str(exercise).strip() == 'Squat' and 
                (weight == 235 or str(weight) == '235') and 
                (reps_completed == 5 or str(reps_completed) == '5')):
                
                # Skip if it's a DELOAD week
                if notes and 'DELOAD' not in str(notes).upper():
                    squat_235_count += 1
                    
                    # Check if there's a "Ready" column (likely column H or later)
                    if len(row) >= 9:  # If helper columns exist
                        ready_cell = row[7].get('value', '') if isinstance(row[7], dict) else row[7]  # Column H
                        if ready_cell:
                            ready_status = str(ready_cell).strip().upper()
        
        logger.info(f"Squat at 235 lbs: {squat_235_count} successful sessions, Ready status: {ready_status}")
        
        # Should have 3+ sessions and be marked as YES
        if squat_235_count >= 3:
            if ready_status and 'YES' in ready_status:
                return True
            elif ready_status is None:
                # Helper columns might not be created yet
                return False
            else:
                logger.warning(f"Squat should be ready but status is: {ready_status}")
                return False
        
        return False
        
    except Exception as e:
        logger.error(f"Error verifying squat progression: {e}")
        return False


def verify_weight_recommendations(sheet_data, sheet_name):
    """
    Verify that recommended weights follow 5/10 lb increase rules.
    Upper body (Bench, OHP, Row): +5 lbs
    Lower body (Squat, Deadlift): +10 lbs
    """
    try:
        rows = sheet_data['sheets'][sheet_name]
        
        correct_recommendations = 0
        total_checks = 0
        
        for row in rows[1:6]:  # Check first few data rows
            if len(row) < 10:  # Need recommended weight column
                continue
            
            exercise = row[1].get('value', '') if isinstance(row[1], dict) else row[1]
            current_weight = row[2].get('value', '') if isinstance(row[2], dict) else row[2]
            recommended = row[8].get('value', '') if len(row) > 8 and isinstance(row[8], dict) else (row[8] if len(row) > 8 else None)
            
            if not exercise or not current_weight or recommended is None:
                continue
            
            exercise_str = str(exercise).strip()
            total_checks += 1
            
            try:
                current_weight = float(current_weight)
                recommended = float(recommended)
                
                # Determine expected increase
                if exercise_str in ['Squat', 'Deadlift']:
                    expected_increase = 10
                else:  # Bench Press, Overhead Press, Barbell Row
                    expected_increase = 5
                
                # Check if recommendation follows the rule (within tolerance)
                if abs(recommended - (current_weight + expected_increase)) < 1:
                    correct_recommendations += 1
                    
            except (ValueError, TypeError):
                continue
        
        logger.info(f"Weight recommendations: {correct_recommendations}/{total_checks} correct")
        
        return correct_recommendations >= 2  # At least 2 correct recommendations
        
    except Exception as e:
        logger.error(f"Error verifying weight recommendations: {e}")
        return False


def check_formula_errors(sheet_data, sheet_name):
    """Check for common formula errors like #REF!, #VALUE!, #DIV/0!"""
    try:
        rows = sheet_data['sheets'][sheet_name]
        error_patterns = ['#REF!', '#VALUE!', '#DIV/0!', '#NAME?', '#N/A', '#NUM!']
        
        for row in rows:
            for cell in row:
                value = cell.get('value', '') if isinstance(cell, dict) else cell
                if value and any(error in str(value) for error in error_patterns):
                    logger.warning(f"Formula error detected: {value}")
                    return True  # Has errors
        
        return False  # No errors
        
    except Exception as e:
        logger.error(f"Error checking formula errors: {e}")
        return True  # Assume errors if check fails


def verify_progressive_overload(traj, env_info, task_info):
    """
    Main verification function for Progressive Overload Calculator task.
    
    Checks:
    1. COUNTIFS formula present (25%)
    2. Progression logic correct (30%)
    3. Weight recommendations accurate (20%)
    4. Conditional formatting applied (15%)
    5. No formula errors (10%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible output paths
    container_paths = [
        "/home/ga/Documents/workout_progression.ods",
        "/home/ga/Documents/workout_log.ods",
        "/home/ga/Documents/workout_log.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        file_format = 'csv' if container_path.endswith('.csv') else 'ods'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load workout file: {error}"
        }
    
    try:
        sheet_data = file_info.get('sheet_data', {})
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        # Initialize scoring
        scores = {}
        feedback_parts = []
        
        # Criterion 1: COUNTIFS formula present (25 points)
        countifs_present = check_countifs_formula_present(sheet_data, sheet_name)
        scores['countifs'] = 25 if countifs_present else 0
        if countifs_present:
            feedback_parts.append("✅ COUNTIFS formula detected")
        else:
            feedback_parts.append("❌ No COUNTIFS formula found (needed for tracking sessions)")
        
        # Criterion 2: Progression logic correct (30 points)
        # Check if Squat at 235 with 3+ sessions is marked ready
        progression_correct = verify_squat_progression_logic(sheet_data, sheet_name)
        
        # Also check for IF/AND logic presence as partial credit
        if_logic_present = check_complex_if_logic(sheet_data, sheet_name)
        
        if progression_correct:
            scores['progression_logic'] = 30
            feedback_parts.append("✅ Progression logic correct (3x5 rule applied)")
        elif if_logic_present:
            scores['progression_logic'] = 15  # Partial credit for attempting logic
            feedback_parts.append("⚠️ Complex IF logic present but may not be fully correct")
        else:
            scores['progression_logic'] = 0
            feedback_parts.append("❌ Progression logic missing or incorrect")
        
        # Criterion 3: Weight recommendations accurate (20 points)
        weights_correct = verify_weight_recommendations(sheet_data, sheet_name)
        scores['weight_recommendations'] = 20 if weights_correct else 0
        if weights_correct:
            feedback_parts.append("✅ Weight recommendations follow 5/10 lb rules")
        else:
            feedback_parts.append("❌ Weight recommendations missing or incorrect")
        
        # Criterion 4: Conditional formatting applied (15 points)
        # This is difficult to verify from parsed data, so we'll check for:
        # a) Presence of helper columns (indicates work was done)
        # b) "YES/NO" values in a column (indicates ready status column exists)
        has_ready_column = False
        rows = sheet_data['sheets'][sheet_name]
        for row in rows[:10]:  # Check first 10 rows
            for cell in row[6:]:  # Check columns after F
                value = cell.get('value', '') if isinstance(cell, dict) else cell
                if value and str(value).strip().upper() in ['YES', 'NO']:
                    has_ready_column = True
                    break
            if has_ready_column:
                break
        
        # Try to check conditional formatting via the utility
        formatting_exists = False
        try:
            formatting_exists = check_conditional_formatting(sheet_data, sheet_name, "H:H")
        except:
            pass
        
        if formatting_exists or has_ready_column:
            scores['conditional_formatting'] = 15
            feedback_parts.append("✅ Ready status column present (formatting likely applied)")
        else:
            scores['conditional_formatting'] = 0
            feedback_parts.append("❌ No ready status column or conditional formatting detected")
        
        # Criterion 5: No formula errors (10 points)
        has_errors = check_formula_errors(sheet_data, sheet_name)
        scores['no_errors'] = 0 if has_errors else 10
        if not has_errors:
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append("❌ Formula errors present (#REF!, #VALUE!, etc.)")
        
        # Calculate total score
        total_score = sum(scores.values())
        passed = total_score >= 75
        
        # Add summary
        if passed and total_score >= 90:
            feedback_parts.insert(0, "🎉 Excellent progressive overload calculator!")
        elif passed:
            feedback_parts.insert(0, "✅ Progressive overload calculator functional")
        else:
            feedback_parts.insert(0, "❌ Task requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: Score={total_score}, Passed={passed}")
        logger.info(f"Subscores: {scores}")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": feedback,
            "subscores": {
                "countifs_present": countifs_present,
                "progression_logic": progression_correct or if_logic_present,
                "weight_recommendations": weights_correct,
                "formatting_or_ready_column": has_ready_column or formatting_exists,
                "no_formula_errors": not has_errors
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
        cleanup_verification_temp(file_info.get('temp_dir'))
