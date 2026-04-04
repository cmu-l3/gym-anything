#!/usr/bin/env python3
"""
Verifier for Coffee Roast Freshness Tracker task
Checks: date formula, conditional formatting, sort order, calculation accuracy
"""

import sys
import os
import logging
from datetime import datetime, timedelta

# Add utils to path (relative path for host-side verification)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting,
    verify_data_sorted,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_days_column(sheet_data):
    """
    Find the column containing days-since-roast calculations.
    Returns column index or None.
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return None
    
    sheets = sheet_data.get('sheets', {})
    if not sheets:
        return None
    
    sheet_name = list(sheets.keys())[0]
    rows = sheets[sheet_name]
    
    if len(rows) < 2:
        return None
    
    # Check first few rows for TODAY() or NOW() formula
    for col_idx in range(min(len(rows[0]), 15)):  # Check up to column O
        for row_idx in range(1, min(len(rows), 5)):  # Check first few data rows
            if col_idx < len(rows[row_idx]):
                cell = rows[row_idx][col_idx]
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    if formula:
                        formula_upper = str(formula).upper()
                        if 'TODAY()' in formula_upper or 'NOW()' in formula_upper:
                            logger.info(f"Found date formula in column {col_idx}: {formula}")
                            return col_idx
    
    return None


def find_roast_date_column(sheet_data):
    """
    Find the column containing roast dates.
    Returns column index (typically 2 for column C).
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return 2  # Default to column C
    
    sheets = sheet_data.get('sheets', {})
    if not sheets:
        return 2
    
    sheet_name = list(sheets.keys())[0]
    rows = sheets[sheet_name]
    
    if len(rows) < 2:
        return 2
    
    # Check header row for "date" keyword
    header_row = rows[0] if rows else []
    for col_idx, cell in enumerate(header_row):
        if isinstance(cell, dict):
            value = cell.get('value', '')
        else:
            value = cell
        
        if value and 'date' in str(value).lower():
            logger.info(f"Found date column at index {col_idx}")
            return col_idx
    
    return 2  # Default to column C if not found


def calculate_expected_days(roast_date_value):
    """
    Calculate expected days since roast date.
    Returns integer days or None if calculation fails.
    """
    try:
        today = datetime.now().date()
        
        # Parse roast date
        if isinstance(roast_date_value, str):
            # Try common date formats
            for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
                try:
                    roast_date = datetime.strptime(roast_date_value, fmt).date()
                    break
                except ValueError:
                    continue
            else:
                logger.warning(f"Could not parse date: {roast_date_value}")
                return None
        elif hasattr(roast_date_value, 'date'):
            roast_date = roast_date_value.date()
        else:
            roast_date = roast_date_value
        
        days_diff = (today - roast_date).days
        return days_diff
    
    except Exception as e:
        logger.warning(f"Error calculating days: {e}")
        return None


def verify_coffee_roast_tracker(traj, env_info, task_info):
    """
    Verify coffee roast tracker task completion.
    
    Checks:
    1. Days-since-roast formula exists using TODAY() or NOW()
    2. Conditional formatting applied to days column
    3. Data sorted by roast date
    4. Calculations are accurate (±1 day tolerance)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    file_paths = [
        "/home/ga/Documents/coffee_roast_tracker.ods",
        "/home/ga/Documents/coffee_roast_log.ods",
        "/home/ga/Documents/coffee_roast_log.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in file_paths:
        file_format = 'csv' if container_path.endswith('.csv') else 'ods'
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load file. Tried: {', '.join(file_paths)}. Error: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheets = sheet_data.get('sheets', {})
        
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheets.keys())[0]
        rows = sheets[sheet_name]
        
        if len(rows) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows"}
        
        score = 0.0
        criteria_met = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: Check for days-since-roast formula
        days_column = find_days_column(sheet_data)
        formula_found = days_column is not None
        
        if formula_found:
            criteria_met += 1
            score += 0.25
            feedback_parts.append(f"✅ Date calculation formula found in column {days_column + 1}")
        else:
            feedback_parts.append("❌ No TODAY() or NOW() formula detected for days-since-roast")
        
        # Criterion 2: Check for conditional formatting
        formatting_ok = check_conditional_formatting(sheet_data, sheet_name, "")
        
        if formatting_ok:
            criteria_met += 1
            score += 0.25
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            feedback_parts.append("❌ No conditional formatting found")
        
        # Criterion 3: Check data sorting by roast date
        roast_date_column = find_roast_date_column(sheet_data)
        
        # Prepare data for sort verification
        sheet_for_sort = {'rows': rows}
        is_sorted_asc, sort_msg = verify_data_sorted(
            sheet_for_sort,
            column=roast_date_column,
            order='asc',
            start_row=1,
            end_row=None
        )
        
        is_sorted_desc = False
        if not is_sorted_asc:
            is_sorted_desc, _ = verify_data_sorted(
                sheet_for_sort,
                column=roast_date_column,
                order='desc',
                start_row=1,
                end_row=None
            )
        
        if is_sorted_asc or is_sorted_desc:
            criteria_met += 1
            score += 0.25
            sort_direction = "ascending" if is_sorted_asc else "descending"
            feedback_parts.append(f"✅ Data sorted by roast date ({sort_direction})")
        else:
            feedback_parts.append(f"❌ Data not properly sorted by roast date")
        
        # Criterion 4: Verify calculation accuracy
        if days_column is not None:
            accurate_calculations = 0
            total_checks = 0
            
            for row_idx in range(1, min(len(rows), 15)):  # Check up to 14 data rows
                if roast_date_column < len(rows[row_idx]) and days_column < len(rows[row_idx]):
                    roast_date_cell = rows[row_idx][roast_date_column]
                    days_cell = rows[row_idx][days_column]
                    
                    roast_date_value = roast_date_cell.get('value') if isinstance(roast_date_cell, dict) else roast_date_cell
                    days_value = days_cell.get('value') if isinstance(days_cell, dict) else days_cell
                    
                    if roast_date_value and days_value is not None:
                        expected_days = calculate_expected_days(roast_date_value)
                        
                        if expected_days is not None:
                            try:
                                actual_days = int(float(days_value))
                                total_checks += 1
                                
                                # Allow ±1 day tolerance for timing differences
                                if abs(actual_days - expected_days) <= 1:
                                    accurate_calculations += 1
                                else:
                                    logger.debug(f"Row {row_idx}: Expected {expected_days} days, got {actual_days}")
                            except (ValueError, TypeError):
                                logger.debug(f"Could not parse days value: {days_value}")
            
            if total_checks > 0:
                accuracy_ratio = accurate_calculations / total_checks
                if accuracy_ratio >= 0.75:  # At least 75% of calculations correct
                    criteria_met += 1
                    score += 0.25
                    feedback_parts.append(f"✅ Calculations accurate ({accurate_calculations}/{total_checks} correct)")
                else:
                    feedback_parts.append(f"❌ Calculation accuracy too low ({accurate_calculations}/{total_checks} correct)")
            else:
                feedback_parts.append("⚠️ Could not verify calculation accuracy")
        else:
            feedback_parts.append("❌ Cannot verify calculations without formula column")
        
        # Calculate final score
        score_pct = int(score * 100)
        passed = score_pct >= 75
        
        # Add summary feedback
        if passed:
            if score_pct >= 90:
                feedback_parts.append("🎉 Coffee roast tracker completed successfully!")
            else:
                feedback_parts.append("✅ Task requirements met")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        return {
            "passed": passed,
            "score": score_pct,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "formula_present": formula_found,
                "conditional_formatting": formatting_ok,
                "data_sorted": is_sorted_asc or is_sorted_desc,
                "calculations_accurate": criteria_met >= 3
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
