#!/usr/bin/env python3
"""
Verifier for Medication Timing Optimizer task
Checks that formulas correctly identify 3 planted conflicts in medication schedule
"""

import sys
import os
import logging
import re
from datetime import time, datetime, timedelta

# Add utils to path - use relative path for host execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_value(cell_value):
    """
    Parse time value from various formats.
    Returns datetime.time object or None.
    """
    if cell_value is None:
        return None
    
    # If already a time string like "07:00:00"
    if isinstance(cell_value, str):
        try:
            # Try parsing HH:MM:SS or HH:MM
            parts = cell_value.split(':')
            if len(parts) >= 2:
                hour = int(parts[0])
                minute = int(parts[1])
                return time(hour, minute)
        except:
            pass
    
    return None


def time_to_minutes(t):
    """Convert time object to minutes since midnight"""
    if t is None:
        return None
    return t.hour * 60 + t.minute


def is_meal_window(dose_time, meal_time, window_minutes=30):
    """Check if dose time is within meal window (30 min before or after)"""
    if dose_time is None or meal_time is None:
        return False
    
    dose_min = time_to_minutes(dose_time)
    meal_min = time_to_minutes(meal_time)
    
    return abs(dose_min - meal_min) <= window_minutes


def is_empty_stomach(dose_time):
    """
    Check if dose time qualifies as empty stomach.
    Must be at least 1 hour before or 2 hours after any meal.
    Meals: 7:00 AM, 12:00 PM, 6:00 PM
    """
    if dose_time is None:
        return False
    
    dose_min = time_to_minutes(dose_time)
    
    # Meal times in minutes
    breakfast = 7 * 60  # 420
    lunch = 12 * 60     # 720
    dinner = 18 * 60    # 1080
    
    # Check each meal
    for meal_min in [breakfast, lunch, dinner]:
        # Within 1 hour before or 2 hours after
        if meal_min - 60 <= dose_min <= meal_min + 120:
            return False
    
    return True


def extract_medication_base_name(med_text):
    """Extract base medication name (e.g., 'Med_E (1)' -> 'Med_E')"""
    if med_text is None:
        return None
    
    # Remove dose number in parentheses
    match = re.match(r'([^\(]+)', str(med_text))
    if match:
        return match.group(1).strip()
    return str(med_text).strip()


def check_formula_exists(formula_text):
    """Check if a formula exists (starts with '=')"""
    if formula_text is None:
        return False
    return str(formula_text).strip().startswith('=')


def verify_medication_timing_optimizer(traj, env_info, task_info):
    """
    Verify medication timing optimizer task completion.
    
    Checks:
    1. Formulas present in validation columns (not manual entries)
    2. Food conflict detected: Med_A at 10 AM flagged
    3. Interaction conflict detected: Med_C and Med_D at 12 PM flagged
    4. Interval conflict detected: Med_E's 6-hour gap flagged
    5. No false positives: Other doses not incorrectly flagged
    6. Summary accurate (if present)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/medication_schedule.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get sheet names
        sheet_names = get_sheet_names(workbook)
        
        # Find Med_Rules and Current_Schedule sheets
        rules_sheet = None
        schedule_sheet = None
        
        for sheet in sheet_names:
            if 'rule' in sheet.lower() or sheet == 'Med_Rules':
                rules_sheet = sheet
            elif 'schedule' in sheet.lower() or sheet == 'Current_Schedule':
                schedule_sheet = sheet
        
        if not schedule_sheet:
            # Try first and second sheets
            if len(sheet_names) >= 2:
                rules_sheet = sheet_names[0]
                schedule_sheet = sheet_names[1]
            else:
                return {"passed": False, "score": 0, "feedback": "Could not find required sheets"}

        logger.info(f"Using sheets: Rules='{rules_sheet}', Schedule='{schedule_sheet}'")

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Track specific conflicts
        conflicts_detected = {
            'food_violation': False,
            'interaction_conflict': False,
            'interval_conflict': False
        }
        
        false_positives = []

        # Criterion 1: Check if formulas are present in validation columns
        formulas_present = False
        formula_count = 0
        
        for row_idx in range(2, 10):  # Check rows 2-9 (data rows)
            # Check columns C through G (Meal_Window through Interval_OK)
            for col in ['C', 'D', 'E', 'F', 'G']:
                cell_ref = f"{col}{row_idx}"
                formula = get_cell_formula(workbook, schedule_sheet, cell_ref)
                if check_formula_exists(formula):
                    formula_count += 1
        
        if formula_count >= 5:  # At least some formulas present
            formulas_present = True
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas present ({formula_count} formula cells found)")
        else:
            feedback_parts.append(f"❌ Insufficient formulas (found {formula_count}, expected 5+)")

        # Analyze each scheduled dose
        # Row 2: 7:00 AM Med_B (should be OK)
        # Row 3: 8:00 AM Med_E (1) (should be OK)
        # Row 4: 10:00 AM Med_A (CONFLICT: food requirement)
        # Row 5: 12:00 PM Med_C (1) (CONFLICT: interaction)
        # Row 6: 12:00 PM Med_D (CONFLICT: interaction)
        # Row 7: 2:00 PM Med_E (2) (CONFLICT: interval)
        # Row 8: 6:00 PM Med_F (should be OK)
        # Row 9: 9:00 PM Med_C (2) (should be OK)
        
        # Expected conflicts at specific rows
        expected_conflicts = {
            4: 'food',      # Row 4: Med_A at 10 AM
            5: 'interaction',  # Row 5: Med_C at 12 PM
            6: 'interaction',  # Row 6: Med_D at 12 PM
            7: 'interval'   # Row 7: Med_E (2) at 2 PM
        }
        
        expected_ok_rows = [2, 3, 8, 9]  # These should NOT have conflicts
        
        # Criterion 2: Food conflict detected (Row 4, Med_A at 10 AM)
        food_ok_cell = get_cell_value(workbook, schedule_sheet, 'E4')  # Food_OK column
        food_formula = get_cell_formula(workbook, schedule_sheet, 'E4')
        
        if food_ok_cell and 'CONFLICT' in str(food_ok_cell).upper():
            conflicts_detected['food_violation'] = True
            criteria_passed += 1
            feedback_parts.append("✅ Food conflict detected: Med_A at 10 AM flagged")
        else:
            feedback_parts.append(f"❌ Food conflict NOT detected: Med_A at 10 AM (E4={food_ok_cell})")
        
        # Criterion 3: Interaction conflict detected (Rows 5 & 6, Med_C and Med_D at 12 PM)
        interaction_c = get_cell_value(workbook, schedule_sheet, 'F5')  # Interaction_OK for Med_C
        interaction_d = get_cell_value(workbook, schedule_sheet, 'F6')  # Interaction_OK for Med_D
        
        interaction_detected = False
        if (interaction_c and 'CONFLICT' in str(interaction_c).upper()) or \
           (interaction_d and 'CONFLICT' in str(interaction_d).upper()):
            interaction_detected = True
            conflicts_detected['interaction_conflict'] = True
            criteria_passed += 1
            feedback_parts.append("✅ Interaction conflict detected: Med_C + Med_D at 12 PM flagged")
        else:
            feedback_parts.append(f"❌ Interaction conflict NOT detected: Med_C/Med_D at 12 PM (F5={interaction_c}, F6={interaction_d})")
        
        # Criterion 4: Interval conflict detected (Row 7, Med_E second dose)
        interval_cell = get_cell_value(workbook, schedule_sheet, 'G7')  # Interval_OK column
        
        if interval_cell and 'CONFLICT' in str(interval_cell).upper():
            conflicts_detected['interval_conflict'] = True
            criteria_passed += 1
            feedback_parts.append("✅ Interval conflict detected: Med_E 6-hour gap flagged")
        else:
            feedback_parts.append(f"❌ Interval conflict NOT detected: Med_E at 2 PM (G7={interval_cell})")
        
        # Criterion 5: No false positives (check rows that should be OK)
        false_positive_found = False
        
        for ok_row in expected_ok_rows:
            # Check Food_OK, Interaction_OK, and Interval_OK columns
            for col, col_name in [('E', 'Food'), ('F', 'Interaction'), ('G', 'Interval')]:
                cell_ref = f"{col}{ok_row}"
                cell_value = get_cell_value(workbook, schedule_sheet, cell_ref)
                if cell_value and 'CONFLICT' in str(cell_value).upper():
                    false_positive_found = True
                    med_name = get_cell_value(workbook, schedule_sheet, f"B{ok_row}")
                    false_positives.append(f"Row {ok_row} ({med_name}) - {col_name}")
        
        if not false_positive_found:
            criteria_passed += 1
            feedback_parts.append("✅ No false positives: Correct doses not flagged")
        else:
            feedback_parts.append(f"⚠️ False positives detected: {', '.join(false_positives)}")
        
        # Criterion 6: Summary accurate (optional - check if summary section exists)
        # Look for summary cells that might contain conflict counts
        summary_found = False
        summary_accurate = False
        
        # Check rows 11-20 for summary information
        for row_idx in range(11, 21):
            for col in ['A', 'B', 'C', 'D']:
                cell_value = get_cell_value(workbook, schedule_sheet, f"{col}{row_idx}")
                if cell_value:
                    cell_text = str(cell_value).lower()
                    if 'total' in cell_text or 'conflict' in cell_text or 'summary' in cell_text:
                        summary_found = True
                        # Check if the count is 3 (for 3 conflicts)
                        # Look in adjacent cells for the number
                        for check_col in ['B', 'C', 'D']:
                            count_cell = get_cell_value(workbook, schedule_sheet, f"{check_col}{row_idx}")
                            if count_cell in [3, '3', 3.0]:
                                summary_accurate = True
                                break
        
        if summary_accurate:
            criteria_passed += 1
            feedback_parts.append("✅ Summary accurate: Total conflict count = 3")
        elif summary_found:
            feedback_parts.append("⚠️ Summary found but count may be incorrect")
        else:
            # Give partial credit if all 3 conflicts detected even without summary
            if all(conflicts_detected.values()):
                criteria_passed += 1
                feedback_parts.append("✅ All conflicts detected (no summary section required)")
            else:
                feedback_parts.append("ℹ️ No summary section found")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 70% (4 out of 6 criteria)
        
        # Build detailed feedback
        conflict_summary = []
        if conflicts_detected['food_violation']:
            conflict_summary.append("Food")
        if conflicts_detected['interaction_conflict']:
            conflict_summary.append("Interaction")
        if conflicts_detected['interval_conflict']:
            conflict_summary.append("Interval")
        
        if conflict_summary:
            feedback_parts.append(f"Detected: {', '.join(conflict_summary)}")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_present": formulas_present,
                "food_conflict": conflicts_detected['food_violation'],
                "interaction_conflict": conflicts_detected['interaction_conflict'],
                "interval_conflict": conflicts_detected['interval_conflict'],
                "no_false_positives": not false_positive_found,
                "summary_accurate": summary_accurate or all(conflicts_detected.values())
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
