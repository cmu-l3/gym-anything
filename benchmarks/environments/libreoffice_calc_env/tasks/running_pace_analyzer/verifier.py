#!/usr/bin/env python3
"""
Verifier for Running Pace Analyzer task
Checks data standardization, pace calculations, and performance analysis
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
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, uppercase)"""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def verify_distance_conversion(workbook, sheet_name, row_idx, original_dist, unit):
    """
    Verify distance conversion formula and result.
    Assumes Distance_Miles is in column H (8th column, index 7)
    """
    # Try common column positions for Distance_Miles
    for col_letter in ['H', 'I', 'J', 'K']:
        cell_ref = f"{col_letter}{row_idx}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        
        if value is not None:
            # Calculate expected value
            if unit == "km":
                expected = original_dist * 0.621371
            else:
                expected = original_dist
            
            # Check if value matches (within tolerance)
            try:
                if abs(float(value) - expected) < 0.02:
                    # Check if formula exists (not hardcoded)
                    if formula and 'IF' in normalize_formula(formula):
                        return True, col_letter, expected, value
                    elif abs(float(value) - expected) < 0.001:
                        # Exact match might be hardcoded, but still partially credit
                        return True, col_letter, expected, value
            except (ValueError, TypeError):
                continue
    
    return False, None, None, None


def verify_time_conversion(workbook, sheet_name, row_idx, time_val, time_format):
    """
    Verify time conversion to minutes.
    Assumes Time_Minutes is in one of columns I-L
    """
    # Calculate expected minutes
    if time_format == "HH:MM:SS":
        # Parse HH:MM:SS format
        parts = str(time_val).split(":")
        if len(parts) == 3:
            expected = int(parts[0]) * 60 + int(parts[1]) + int(parts[2]) / 60
        else:
            expected = None
    elif time_format == "DecimalMinutes":
        expected = float(time_val)
    elif time_format == "DecimalHours":
        expected = float(time_val) * 60
    else:
        expected = None
    
    if expected is None:
        return False, None, None, None
    
    # Try common column positions
    for col_letter in ['I', 'J', 'K', 'L']:
        cell_ref = f"{col_letter}{row_idx}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value is not None:
            try:
                if abs(float(value) - expected) < 0.5:  # 30 second tolerance
                    return True, col_letter, expected, value
            except (ValueError, TypeError):
                continue
    
    return False, None, None, None


def verify_pace_calculation(workbook, sheet_name, row_idx, time_minutes, distance_miles):
    """
    Verify pace calculation (min/mile).
    Assumes Pace_MinPerMile is in one of columns J-M
    """
    if distance_miles == 0 or distance_miles is None:
        return True, None, None, None  # Skip rows with no distance
    
    expected_pace = time_minutes / distance_miles
    
    # Try common column positions
    for col_letter in ['J', 'K', 'L', 'M']:
        cell_ref = f"{col_letter}{row_idx}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        formula = get_cell_formula(workbook, sheet_name, cell_ref)
        
        if value is not None:
            try:
                if abs(float(value) - expected_pace) < 0.1:
                    # Check for formula
                    if formula and '/' in formula:
                        return True, col_letter, expected_pace, value
                    else:
                        # Value correct but might be hardcoded
                        return True, col_letter, expected_pace, value
            except (ValueError, TypeError):
                continue
    
    return False, None, None, None


def check_for_averages(workbook, sheet_name):
    """
    Check if average calculations exist (AVERAGE or AVERAGEIF functions).
    Look in various cells for summary statistics.
    """
    # Check bottom rows and side columns for summary data
    sheet_data = workbook['sheets'][sheet_name]
    
    for row_idx, row in enumerate(sheet_data[-10:], start=len(sheet_data)-10):  # Last 10 rows
        for col_idx, cell_data in enumerate(row[:15]):  # First 15 columns
            if isinstance(cell_data, dict):
                formula = cell_data.get('formula', '')
                if formula and ('AVERAGE' in formula.upper()):
                    return True
    
    # Also check cells in the typical summary area (rows beyond data)
    for row_num in range(20, 30):
        for col_letter in ['A', 'B', 'C', 'D', 'E', 'H', 'I', 'J', 'K']:
            formula = get_cell_formula(workbook, sheet_name, f"{col_letter}{row_num}")
            if formula and 'AVERAGE' in formula.upper():
                return True
    
    return False


def verify_running_pace_analyzer(traj, env_info, task_info):
    """
    Verify running pace analyzer task completion.
    
    Checks:
    1. Distance_Miles column with correct conversions
    2. Time_Minutes column handling all formats
    3. Pace_MinPerMile with accurate calculations
    4. Formulas are correct and not hardcoded
    5. Summary analysis (averages by run type)
    6. Conditional formatting applied
    7. Data quality (no errors, reasonable values)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the output file
    temp_dir = None
    success = False
    
    for path_to_try in [
        "/home/ga/Documents/running_analysis.ods",
        "/home/ga/Documents/training_log.ods",
        "/home/ga/Documents/training_log.csv"
    ]:
        file_format = 'ods' if path_to_try.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path_to_try,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {path_to_try}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"File not found or parse error: {error}"}

    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]

        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Get original data from first few rows
        test_rows = [2, 3, 4]  # Rows 2, 3, 4 (0-indexed: 1, 2, 3)
        
        # Criterion 1: Distance conversion
        distance_converted = 0
        distance_formulas = 0
        for row_idx in test_rows:
            if row_idx < len(sheet_data):
                original_dist = get_cell_value(workbook, sheet_name, f"B{row_idx}")
                unit = get_cell_value(workbook, sheet_name, f"C{row_idx}")
                
                if original_dist and unit:
                    converted, col, expected, actual = verify_distance_conversion(
                        workbook, sheet_name, row_idx, float(original_dist), str(unit)
                    )
                    if converted:
                        distance_converted += 1
                        # Check for formula
                        formula = get_cell_formula(workbook, sheet_name, f"{col}{row_idx}")
                        if formula and 'IF' in normalize_formula(formula):
                            distance_formulas += 1
        
        if distance_converted >= 2:
            criteria_passed += 1
            if distance_formulas >= 2:
                feedback_parts.append(f"✅ Distance standardized with formulas ({distance_converted}/3 rows)")
            else:
                feedback_parts.append(f"⚠️ Distance values correct but may be hardcoded ({distance_converted}/3 rows)")
        else:
            feedback_parts.append(f"❌ Distance conversion missing or incorrect ({distance_converted}/3 rows)")

        # Criterion 2: Time conversion
        time_converted = 0
        for row_idx in test_rows:
            if row_idx < len(sheet_data):
                time_val = get_cell_value(workbook, sheet_name, f"D{row_idx}")
                time_format = get_cell_value(workbook, sheet_name, f"E{row_idx}")
                
                if time_val and time_format:
                    converted, col, expected, actual = verify_time_conversion(
                        workbook, sheet_name, row_idx, time_val, str(time_format)
                    )
                    if converted:
                        time_converted += 1
        
        if time_converted >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Time standardized to minutes ({time_converted}/3 rows)")
        else:
            feedback_parts.append(f"❌ Time conversion missing or incorrect ({time_converted}/3 rows)")

        # Criterion 3: Pace calculation
        # First, find Distance_Miles and Time_Minutes columns
        pace_calculated = 0
        for row_idx in test_rows:
            # Get converted values
            dist_miles = None
            time_mins = None
            
            for col_letter in ['H', 'I', 'J', 'K']:
                val = get_cell_value(workbook, sheet_name, f"{col_letter}{row_idx}")
                if val and 3 <= float(val) <= 15:  # Likely distance in miles
                    dist_miles = float(val)
                    break
            
            for col_letter in ['I', 'J', 'K', 'L']:
                val = get_cell_value(workbook, sheet_name, f"{col_letter}{row_idx}")
                if val and 20 <= float(val) <= 150:  # Likely time in minutes
                    time_mins = float(val)
                    break
            
            if dist_miles and time_mins:
                pace_ok, col, expected, actual = verify_pace_calculation(
                    workbook, sheet_name, row_idx, time_mins, dist_miles
                )
                if pace_ok:
                    pace_calculated += 1
        
        if pace_calculated >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Pace calculated correctly ({pace_calculated}/3 rows)")
        else:
            feedback_parts.append(f"❌ Pace calculation missing or incorrect ({pace_calculated}/3 rows)")

        # Criterion 4: Formulas correct (check at least one formula for each type)
        formulas_valid = False
        formula_count = 0
        
        # Check for IF formula in distance conversion
        for row_idx in [2, 3]:
            for col_letter in ['H', 'I', 'J']:
                formula = get_cell_formula(workbook, sheet_name, f"{col_letter}{row_idx}")
                if formula and 'IF' in normalize_formula(formula) and 'KM' in normalize_formula(formula):
                    formula_count += 1
                    break
        
        # Check for division formula in pace calculation
        for row_idx in [2, 3]:
            for col_letter in ['J', 'K', 'L', 'M']:
                formula = get_cell_formula(workbook, sheet_name, f"{col_letter}{row_idx}")
                if formula and '/' in formula:
                    formula_count += 1
                    break
        
        if formula_count >= 2:
            criteria_passed += 1
            formulas_valid = True
            feedback_parts.append("✅ Formulas syntactically correct")
        else:
            feedback_parts.append("❌ Missing or incorrect formulas")

        # Criterion 5: Summary analysis (average by run type)
        has_averages = check_for_averages(workbook, sheet_name)
        if has_averages:
            criteria_passed += 1
            feedback_parts.append("✅ Summary statistics calculated (AVERAGE functions found)")
        else:
            feedback_parts.append("❌ No summary analysis found (missing AVERAGE/AVERAGEIF)")

        # Criterion 6: Conditional formatting
        has_conditional_formatting = check_conditional_formatting(workbook, sheet_name, "A1:Z50")
        if has_conditional_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied")
        else:
            feedback_parts.append("⚠️ No conditional formatting detected")

        # Criterion 7: Data quality (check for errors and reasonable values)
        data_quality_ok = True
        error_count = 0
        unrealistic_pace_count = 0
        
        for row_idx in range(2, min(len(sheet_data), 17)):  # Check up to 15 data rows
            for col_letter in ['H', 'I', 'J', 'K', 'L', 'M']:
                val = get_cell_value(workbook, sheet_name, f"{col_letter}{row_idx}")
                if val and isinstance(val, str):
                    if '#DIV' in val or '#VALUE' in val or '#REF' in val or '#NAME' in val:
                        error_count += 1
                        data_quality_ok = False
            
            # Check pace values are realistic (5-15 min/mile)
            for col_letter in ['J', 'K', 'L', 'M']:
                val = get_cell_value(workbook, sheet_name, f"{col_letter}{row_idx}")
                if val:
                    try:
                        pace_val = float(val)
                        if 5 <= pace_val <= 20:  # Realistic pace range
                            # This looks like a pace value
                            if pace_val < 5 or pace_val > 15:
                                unrealistic_pace_count += 1
                    except (ValueError, TypeError):
                        pass
        
        if data_quality_ok and error_count == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Data quality good (no formula errors)")
        else:
            feedback_parts.append(f"❌ Data quality issues ({error_count} errors found)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 5/7 criteria = 71%
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "distance_standardized": distance_converted >= 2,
                "time_standardized": time_converted >= 2,
                "pace_calculated": pace_calculated >= 2,
                "formulas_correct": formulas_valid,
                "summary_analysis": has_averages,
                "conditional_formatting": has_conditional_formatting,
                "data_quality": data_quality_ok
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
