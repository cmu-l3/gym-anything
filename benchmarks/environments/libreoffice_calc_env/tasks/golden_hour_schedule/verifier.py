#!/usr/bin/env python3
"""
Verifier for Golden Hour Photography Schedule Task

Checks:
1. Data is sorted by Optimal Start Time (ascending)
2. Arrival Time column exists with formulas
3. Time arithmetic is correct (cumulative calculations)
4. Schedule is logically consistent
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
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    verify_data_sorted
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_value(time_val):
    """
    Parse time value from various formats to minutes since midnight.
    
    Args:
        time_val: Time value (could be string "18:30", float 0.75, or datetime)
    
    Returns:
        int: Minutes since midnight, or None if parsing fails
    """
    if time_val is None:
        return None
    
    try:
        # Handle string format "HH:MM" or "HH:MM:SS"
        if isinstance(time_val, str):
            time_val = time_val.strip()
            if ':' in time_val:
                parts = time_val.split(':')
                hours = int(parts[0])
                minutes = int(parts[1])
                return hours * 60 + minutes
        
        # Handle float (fraction of day: 0.5 = 12:00)
        if isinstance(time_val, (float, int)):
            if 0 <= time_val <= 1:
                total_minutes = int(time_val * 1440)  # 1440 minutes in a day
                return total_minutes
            elif time_val > 1:
                # Might be minutes already
                return int(time_val)
        
        # Handle datetime object
        if hasattr(time_val, 'hour') and hasattr(time_val, 'minute'):
            return time_val.hour * 60 + time_val.minute
        
        return None
        
    except (ValueError, AttributeError, TypeError) as e:
        logger.debug(f"Could not parse time value {time_val}: {e}")
        return None


def format_minutes_to_time(minutes):
    """Convert minutes since midnight to HH:MM string"""
    if minutes is None:
        return "N/A"
    hours = minutes // 60
    mins = minutes % 60
    return f"{hours:02d}:{mins:02d}"


def verify_golden_hour_schedule(traj, env_info, task_info):
    """
    Verify golden hour photography schedule optimization task.
    
    Checks:
    1. Data sorted by Optimal Start Time (ascending)
    2. Arrival Time column exists and has formulas
    3. Time calculations are mathematically correct
    4. Schedule is logically consistent
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the file (ODS first, then CSV)
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/photo_locations.ods'),
        ('ods', '/home/ga/Documents/photography_schedule.ods'),
        ('csv', '/home/ga/Documents/photo_locations.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not load schedule file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}
        
        # Extract header row to find column indices
        if not sheet_data or len(sheet_data) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows"}
        
        header_row = sheet_data[0]
        
        # Find column indices
        optimal_time_col = None
        arrival_time_col = None
        travel_time_col = None
        setup_time_col = None
        
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
            cell_str = str(cell_value).lower().strip()
            
            if 'optimal' in cell_str and 'time' in cell_str:
                optimal_time_col = idx
            elif 'arrival' in cell_str and 'time' in cell_str:
                arrival_time_col = idx
            elif 'travel' in cell_str:
                travel_time_col = idx
            elif 'setup' in cell_str:
                setup_time_col = idx
        
        if optimal_time_col is None:
            return {"passed": False, "score": 0, "feedback": "Could not find 'Optimal Start Time' column"}
        
        # CRITERION 1: Check if data is sorted by Optimal Start Time
        optimal_times = []
        data_rows = sheet_data[1:]  # Skip header
        
        for row_idx, row in enumerate(data_rows, start=1):
            if row_idx >= len(data_rows):
                break
            if optimal_time_col < len(row):
                cell = row[optimal_time_col]
                time_val = cell.get('value') if isinstance(cell, dict) else cell
                parsed_time = parse_time_value(time_val)
                if parsed_time is not None:
                    optimal_times.append(parsed_time)
        
        is_sorted = all(optimal_times[i] <= optimal_times[i+1] for i in range(len(optimal_times)-1))
        
        if is_sorted and len(optimal_times) >= 5:
            criteria_passed += 1
            subscores['sorted'] = True
            feedback_parts.append(f"✅ Sorted correctly by Optimal Start Time ({len(optimal_times)} locations)")
        else:
            subscores['sorted'] = False
            if len(optimal_times) < 5:
                feedback_parts.append(f"❌ Insufficient data rows (found {len(optimal_times)}, expected 5)")
            else:
                feedback_parts.append("❌ Data not sorted by Optimal Start Time (ascending order required)")
        
        # CRITERION 2: Check if Arrival Time column exists with formulas
        has_arrival_column = arrival_time_col is not None
        has_formulas = False
        
        if has_arrival_column:
            # Check if arrival time cells have formulas (not hardcoded)
            formula_count = 0
            for row_idx in range(1, min(len(sheet_data), 7)):  # Check up to 6 data rows
                if arrival_time_col < len(sheet_data[row_idx]):
                    formula = get_cell_formula(workbook, sheet_name, f"{chr(65+arrival_time_col)}{row_idx+1}")
                    if formula:
                        formula_count += 1
            
            has_formulas = formula_count >= 3  # At least 3 formulas (reasonable threshold)
            
            if has_formulas:
                criteria_passed += 1
                subscores['has_formulas'] = True
                feedback_parts.append(f"✅ Arrival Time column with formulas ({formula_count} formulas found)")
            elif has_arrival_column:
                subscores['has_formulas'] = False
                feedback_parts.append("❌ Arrival times appear hardcoded (formulas not detected)")
            else:
                subscores['has_formulas'] = False
                feedback_parts.append("❌ No Arrival Time column found")
        else:
            subscores['has_formulas'] = False
            feedback_parts.append("❌ Missing 'Arrival Time' column - need to add column F")
        
        # CRITERION 3: Verify time arithmetic correctness
        time_calc_correct = False
        
        if has_arrival_column and travel_time_col is not None and setup_time_col is not None:
            calc_errors = 0
            total_checks = 0
            
            arrival_times = []
            travel_times = []
            setup_times = []
            
            # Extract all times
            for row_idx in range(1, min(len(sheet_data), 7)):
                row = sheet_data[row_idx]
                
                # Arrival time
                if arrival_time_col < len(row):
                    arrival_val = row[arrival_time_col].get('value') if isinstance(row[arrival_time_col], dict) else row[arrival_time_col]
                    arrival_times.append(parse_time_value(arrival_val))
                
                # Travel time
                if travel_time_col < len(row):
                    travel_val = row[travel_time_col].get('value') if isinstance(row[travel_time_col], dict) else row[travel_time_col]
                    try:
                        travel_times.append(int(float(travel_val)) if travel_val else 0)
                    except (ValueError, TypeError):
                        travel_times.append(0)
                
                # Setup time
                if setup_time_col < len(row):
                    setup_val = row[setup_time_col].get('value') if isinstance(row[setup_time_col], dict) else row[setup_time_col]
                    try:
                        setup_times.append(int(float(setup_val)) if setup_val else 5)
                    except (ValueError, TypeError):
                        setup_times.append(5)
            
            # Verify calculations (skip first location, check cumulative for rest)
            for i in range(1, len(arrival_times)):
                if arrival_times[i] is None or arrival_times[i-1] is None:
                    continue
                
                total_checks += 1
                expected_arrival = arrival_times[i-1] + travel_times[i-1] + setup_times[i-1]
                actual_arrival = arrival_times[i]
                
                # Allow 2-minute tolerance for rounding
                if abs(expected_arrival - actual_arrival) <= 2:
                    pass  # Correct
                else:
                    calc_errors += 1
                    logger.debug(f"Time calc error at location {i+1}: expected {format_minutes_to_time(expected_arrival)}, got {format_minutes_to_time(actual_arrival)}")
            
            if total_checks > 0 and calc_errors == 0:
                criteria_passed += 1
                time_calc_correct = True
                subscores['time_arithmetic'] = True
                feedback_parts.append(f"✅ Time calculations correct ({total_checks} verified)")
            elif total_checks > 0:
                subscores['time_arithmetic'] = False
                feedback_parts.append(f"❌ Time calculation errors ({calc_errors}/{total_checks} incorrect)")
            else:
                subscores['time_arithmetic'] = False
                feedback_parts.append("⚠️ Could not verify time calculations")
        else:
            subscores['time_arithmetic'] = False
            feedback_parts.append("⚠️ Missing columns needed for time calculation verification")
        
        # CRITERION 4: Logical consistency (times progress forward, within reasonable window)
        logical = False
        
        if has_arrival_column and len(arrival_times) >= 5:
            # Check that arrival times progress forward
            times_progress = all(
                arrival_times[i] is None or arrival_times[i+1] is None or arrival_times[i] <= arrival_times[i+1]
                for i in range(len(arrival_times)-1)
            )
            
            # Check that all arrivals are within reasonable golden hour window
            valid_arrivals = [t for t in arrival_times if t is not None]
            if valid_arrivals:
                time_span = max(valid_arrivals) - min(valid_arrivals)
                within_window = time_span <= 90  # 90 minutes is reasonable for golden hour shoot
            else:
                within_window = False
            
            if times_progress and within_window:
                criteria_passed += 1
                logical = True
                subscores['logical'] = True
                feedback_parts.append(f"✅ Schedule logically consistent (span: {time_span} min)")
            else:
                subscores['logical'] = False
                if not times_progress:
                    feedback_parts.append("❌ Arrival times don't progress forward logically")
                else:
                    feedback_parts.append(f"⚠️ Time span ({time_span} min) exceeds typical golden hour")
        else:
            subscores['logical'] = False
            feedback_parts.append("⚠️ Cannot verify logical consistency")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 3/4 criteria
        
        # Add summary message
        if passed and score == 100:
            feedback_parts.append("🎉 Perfect schedule optimization!")
        elif passed:
            feedback_parts.append("✅ Schedule optimization completed")
        else:
            feedback_parts.append("❌ Schedule optimization requirements not met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
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
            cleanup_verification_temp(temp_dir)
