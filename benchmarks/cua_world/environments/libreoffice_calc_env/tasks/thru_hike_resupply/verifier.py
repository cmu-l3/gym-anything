#!/usr/bin/env python3
"""
Verifier for Thru-Hike Resupply Calculator task
Checks cumulative distance, food calculations, pace validation, and date arithmetic
"""

import sys
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, Tuple, List, Optional

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Terrain pace limits (miles per day)
TERRAIN_LIMITS = {
    'Easy': 20,
    'Moderate': 15,
    'Hard': 12,
    'Very Hard': 8
}

START_DATE = datetime(2024, 6, 15)


def get_column_values(workbook: Dict, sheet_name: str, col_letter: str, 
                      start_row: int = 2, end_row: int = 22) -> List[Any]:
    """Extract values from a column range"""
    values = []
    for row_num in range(start_row, end_row + 1):
        cell_ref = f"{col_letter}{row_num}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        values.append(value)
    return values


def verify_cumulative_distance(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify cumulative distance calculations are correct.
    Column D should contain running totals of daily miles (column B).
    """
    try:
        daily_miles = get_column_values(workbook, sheet_name, 'B', 2, 22)
        cumulative = get_column_values(workbook, sheet_name, 'D', 2, 22)
        
        # Check that cumulative values exist
        if not any(cumulative):
            return False, "Cumulative distance column is empty"
        
        # Calculate expected cumulative totals
        expected_cumulative = 0
        errors = []
        
        for i, (daily, actual_cum) in enumerate(zip(daily_miles, cumulative)):
            if daily is None:
                continue
                
            expected_cumulative += float(daily)
            
            if actual_cum is None:
                errors.append(f"Row {i+2}: Missing cumulative value")
                continue
            
            # Allow small tolerance for floating point
            if abs(float(actual_cum) - expected_cumulative) > 0.5:
                errors.append(f"Row {i+2}: Expected {expected_cumulative:.1f}, got {actual_cum}")
                if len(errors) >= 3:  # Don't spam too many errors
                    break
        
        if errors:
            return False, f"Cumulative distance errors: {'; '.join(errors[:3])}"
        
        # Verify final total is realistic (180-280 miles for 21 days)
        if not (180 <= expected_cumulative <= 280):
            return False, f"Total distance {expected_cumulative:.1f} miles seems unrealistic"
        
        # Check that at least some formulas are used (not all hardcoded)
        formula_count = 0
        for i in range(2, 10):  # Check first few rows
            formula = get_cell_formula(workbook, sheet_name, f'D{i}')
            if formula:
                formula_count += 1
        
        if formula_count < 3:
            return False, "Cumulative distance appears hardcoded (no formulas found)"
        
        return True, f"Cumulative distance correct (total: {expected_cumulative:.1f} miles)"
        
    except Exception as e:
        logger.error(f"Error verifying cumulative distance: {e}", exc_info=True)
        return False, f"Error checking cumulative distance: {str(e)}"


def verify_food_calculations(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify food weight calculations.
    Column G should equal Column F × 2.0 (2 lbs per day of food).
    """
    try:
        days_food = get_column_values(workbook, sheet_name, 'F', 2, 22)
        food_weight = get_column_values(workbook, sheet_name, 'G', 2, 22)
        
        # Check that food calculations exist
        if not any(food_weight):
            return False, "Food weight column is empty"
        
        errors = []
        valid_calcs = 0
        
        for i, (days, weight) in enumerate(zip(days_food, food_weight)):
            # Skip if days value is missing
            if days is None or days == '' or days == 0:
                continue
            
            if weight is None:
                errors.append(f"Row {i+2}: Missing food weight")
                continue
            
            expected_weight = float(days) * 2.0
            
            # Allow small tolerance
            if abs(float(weight) - expected_weight) > 0.2:
                errors.append(f"Row {i+2}: Days={days}, expected {expected_weight:.1f} lbs, got {weight}")
                if len(errors) >= 3:
                    break
            else:
                valid_calcs += 1
        
        if errors and valid_calcs < 5:
            return False, f"Food calculation errors: {'; '.join(errors[:3])}"
        
        if valid_calcs == 0:
            return False, "No valid food calculations found"
        
        return True, f"Food calculations correct ({valid_calcs} valid entries)"
        
    except Exception as e:
        logger.error(f"Error verifying food calculations: {e}", exc_info=True)
        return False, f"Error checking food calculations: {str(e)}"


def verify_pace_validation(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify pace validation flags.
    Column H should contain "UNREALISTIC" or "OK" based on daily miles vs terrain limits.
    """
    try:
        daily_miles = get_column_values(workbook, sheet_name, 'B', 2, 22)
        terrain = get_column_values(workbook, sheet_name, 'C', 2, 22)
        pace_flags = get_column_values(workbook, sheet_name, 'H', 2, 22)
        
        # Check that pace validation exists
        if not any(pace_flags):
            return False, "Pace validation column is empty"
        
        errors = []
        correct_flags = 0
        unrealistic_count = 0
        
        for i, (miles, terr, flag) in enumerate(zip(daily_miles, terrain, pace_flags)):
            if miles is None or terr is None:
                continue
            
            if flag is None or flag == '':
                errors.append(f"Row {i+2}: Missing pace flag")
                continue
            
            # Determine expected flag
            limit = TERRAIN_LIMITS.get(str(terr).strip(), 15)
            expected_unrealistic = float(miles) > limit
            
            flag_str = str(flag).strip().upper()
            is_unrealistic = 'UNREALISTIC' in flag_str or 'UNREAL' in flag_str or 'NO' in flag_str or 'FALSE' in flag_str
            is_ok = 'OK' in flag_str or 'YES' in flag_str or 'TRUE' in flag_str or 'REALISTIC' in flag_str
            
            # Check if flag matches expected
            if expected_unrealistic:
                if is_unrealistic and not is_ok:
                    correct_flags += 1
                    unrealistic_count += 1
                else:
                    errors.append(f"Row {i+2}: {miles} mi on {terr} terrain (limit {limit}) should be UNREALISTIC")
                    if len(errors) >= 3:
                        break
            else:
                if is_ok and not is_unrealistic:
                    correct_flags += 1
                else:
                    errors.append(f"Row {i+2}: {miles} mi on {terr} terrain (limit {limit}) should be OK")
                    if len(errors) >= 3:
                        break
        
        # Should have caught at least a few unrealistic days
        if unrealistic_count == 0 and not errors:
            return False, "No unrealistic pace flags found (validation may be too lenient)"
        
        # Need at least 70% correct
        total_checked = correct_flags + len(errors)
        if total_checked > 0 and correct_flags / total_checked < 0.7:
            return False, f"Pace validation errors: {'; '.join(errors[:3])}"
        
        return True, f"Pace validation correct ({correct_flags} correct, {unrealistic_count} flagged unrealistic)"
        
    except Exception as e:
        logger.error(f"Error verifying pace validation: {e}", exc_info=True)
        return False, f"Error checking pace validation: {str(e)}"


def verify_date_calculations(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify date calculations.
    Column I should contain sequential dates starting from June 15, 2024.
    """
    try:
        dates = get_column_values(workbook, sheet_name, 'I', 2, 22)
        
        # Check that dates exist
        if not any(dates):
            return False, "Date column is empty"
        
        errors = []
        valid_dates = 0
        
        for i, date_val in enumerate(dates):
            if date_val is None or date_val == '':
                continue
            
            expected_date = START_DATE + timedelta(days=i)
            
            # Try to parse the date value
            try:
                # Handle various formats
                date_str = str(date_val)
                
                # Check if date contains expected components
                year_ok = '2024' in date_str
                month_ok = False
                day_ok = False
                
                # Check month (June = 06)
                expected_month = expected_date.month
                if str(expected_month).zfill(2) in date_str or expected_date.strftime('%B') in date_str or expected_date.strftime('%b') in date_str:
                    month_ok = True
                
                # Check day
                expected_day = expected_date.day
                if str(expected_day) in date_str:
                    day_ok = True
                
                if year_ok and month_ok and day_ok:
                    valid_dates += 1
                else:
                    if i < 3:  # Only show errors for first few
                        errors.append(f"Row {i+2}: Expected around {expected_date.strftime('%Y-%m-%d')}, got {date_str}")
            
            except Exception as e:
                errors.append(f"Row {i+2}: Could not parse date: {date_val}")
                if len(errors) >= 3:
                    break
        
        if valid_dates < 10:
            return False, f"Date calculation errors: {'; '.join(errors[:3]) if errors else 'Too few valid dates'}"
        
        return True, f"Date calculations correct ({valid_dates} valid dates)"
        
    except Exception as e:
        logger.error(f"Error verifying dates: {e}", exc_info=True)
        return False, f"Error checking dates: {str(e)}"


def verify_formula_usage(workbook: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Verify that formulas are used (not just hardcoded values).
    Check key columns for formula presence.
    """
    try:
        formula_count = 0
        columns_to_check = [
            ('D', 'Cumulative Distance'),
            ('G', 'Food Weight'),
            ('H', 'Pace Check')
        ]
        
        for col, name in columns_to_check:
            for row in range(2, 12):  # Check first 10 rows
                formula = get_cell_formula(workbook, sheet_name, f'{col}{row}')
                if formula:
                    formula_count += 1
                    break  # Found formula in this column, move to next
        
        if formula_count < 2:
            return False, f"Insufficient formula usage (found formulas in {formula_count}/3 key columns)"
        
        return True, f"Formulas used appropriately ({formula_count}/3 columns have formulas)"
        
    except Exception as e:
        logger.error(f"Error checking formula usage: {e}", exc_info=True)
        return False, f"Error checking formulas: {str(e)}"


def check_thru_hike_resupply(traj, env_info, task_info):
    """
    Main verifier function for thru-hike resupply task.
    
    Checks:
    1. Cumulative distance calculations
    2. Food weight calculations
    3. Pace validation against terrain
    4. Date calculations
    5. Formula usage (not hardcoded)
    6. Data integrity
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/resupply_plan.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet
        sheets = list(workbook.get('sheets', {}).keys())
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheets[0]

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}

        # Criterion 1: Cumulative Distance
        cumulative_ok, cumulative_msg = verify_cumulative_distance(workbook, sheet_name)
        if cumulative_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {cumulative_msg}")
        else:
            feedback_parts.append(f"❌ {cumulative_msg}")
        subscores['cumulative_distance'] = cumulative_ok

        # Criterion 2: Food Calculations
        food_ok, food_msg = verify_food_calculations(workbook, sheet_name)
        if food_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {food_msg}")
        else:
            feedback_parts.append(f"❌ {food_msg}")
        subscores['food_calculations'] = food_ok

        # Criterion 3: Pace Validation
        pace_ok, pace_msg = verify_pace_validation(workbook, sheet_name)
        if pace_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {pace_msg}")
        else:
            feedback_parts.append(f"❌ {pace_msg}")
        subscores['pace_validation'] = pace_ok

        # Criterion 4: Date Calculations
        date_ok, date_msg = verify_date_calculations(workbook, sheet_name)
        if date_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {date_msg}")
        else:
            feedback_parts.append(f"❌ {date_msg}")
        subscores['date_calculations'] = date_ok

        # Criterion 5: Formula Usage
        formula_ok, formula_msg = verify_formula_usage(workbook, sheet_name)
        if formula_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {formula_msg}")
        else:
            feedback_parts.append(f"❌ {formula_msg}")
        subscores['formula_usage'] = formula_ok

        # Criterion 6: Data Integrity (check original data preserved)
        daily_miles = get_column_values(workbook, sheet_name, 'B', 2, 22)
        terrain_values = get_column_values(workbook, sheet_name, 'C', 2, 22)
        
        data_intact = True
        if not any(daily_miles) or not any(terrain_values):
            data_intact = False
            feedback_parts.append("❌ Original data appears corrupted or missing")
        else:
            criteria_passed += 1
            feedback_parts.append("✅ Data integrity maintained")
        subscores['data_integrity'] = data_intact

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 4/6 criteria

        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent resupply planning!")
        elif passed:
            feedback_parts.insert(0, "✅ Resupply plan completed")
        else:
            feedback_parts.insert(0, f"❌ Insufficient completion ({criteria_passed}/{total_criteria} criteria)")

        feedback = " | ".join(feedback_parts)

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
