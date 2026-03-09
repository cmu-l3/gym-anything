#!/usr/bin/env python3
"""
Verifier for Tide Window Calculator task.

Checks:
1. Low tides correctly identified
2. Daylight window filtering (7 AM - 7 PM)
3. Optimal height threshold (≤ 1.5 ft)
4. Activity window duration calculations
5. Summary statistics accuracy
6. Day recommendations validity
"""

import sys
import os
import logging
import re
from datetime import datetime, time
from typing import Dict, List, Any, Optional, Tuple

# Add utils to path (relative path for host execution)
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


def parse_time_value(time_val: Any) -> Optional[int]:
    """
    Extract hour from time value (handles various formats).
    
    Args:
        time_val: Time value from cell (string, float, or other)
        
    Returns:
        Hour as integer (0-23) or None if parsing fails
    """
    if time_val is None:
        return None
    
    try:
        # If it's a string like "05:23" or "17:34"
        if isinstance(time_val, str):
            # Try HH:MM format
            match = re.match(r'(\d{1,2}):(\d{2})', time_val)
            if match:
                return int(match.group(1))
            
            # Try just hour
            if time_val.isdigit():
                return int(time_val)
        
        # If it's a float (Excel time format: 0.0 to 1.0 represents 00:00 to 24:00)
        if isinstance(time_val, (float, int)):
            # If it looks like decimal time (0.0 - 1.0)
            if 0 <= time_val <= 1:
                hours = time_val * 24
                return int(hours)
            # If it looks like an hour value directly
            elif 0 <= time_val <= 24:
                return int(time_val)
        
        return None
    
    except Exception as e:
        logger.debug(f"Error parsing time value {time_val}: {e}")
        return None


def analyze_tide_data(workbook: Dict[str, Any], sheet_name: str) -> Dict[str, Any]:
    """
    Analyze the original tide data to establish ground truth.
    
    Returns:
        Dict with expected counts and lists of optimal tides
    """
    analysis = {
        'total_tides': 0,
        'low_tides': 0,
        'low_tides_daylight': 0,
        'optimal_tides': 0,
        'optimal_tide_rows': [],
        'low_tide_rows': []
    }
    
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Analyze each row (skip header)
        for row_idx, row in enumerate(sheet_data[1:], start=2):
            if len(row) < 4:
                continue
            
            # Extract values
            tide_type_cell = row[3] if len(row) > 3 else {}
            tide_type = tide_type_cell.get('value', '') if isinstance(tide_type_cell, dict) else tide_type_cell
            
            time_cell = row[1] if len(row) > 1 else {}
            time_val = time_cell.get('value', '') if isinstance(time_cell, dict) else time_cell
            
            height_cell = row[2] if len(row) > 2 else {}
            height_val = height_cell.get('value', 0) if isinstance(height_cell, dict) else height_cell
            
            analysis['total_tides'] += 1
            
            # Check if low tide
            is_low = str(tide_type).strip().lower() == 'low'
            if is_low:
                analysis['low_tides'] += 1
                analysis['low_tide_rows'].append(row_idx)
                
                # Check if in daylight
                hour = parse_time_value(time_val)
                if hour is not None and 7 <= hour < 19:
                    analysis['low_tides_daylight'] += 1
                    
                    # Check if optimal height
                    try:
                        height = float(height_val)
                        if height <= 1.5:
                            analysis['optimal_tides'] += 1
                            analysis['optimal_tide_rows'].append(row_idx)
                    except (ValueError, TypeError):
                        pass
        
        logger.info(f"Ground truth analysis: {analysis['total_tides']} total tides, "
                   f"{analysis['low_tides']} lows, {analysis['low_tides_daylight']} in daylight, "
                   f"{analysis['optimal_tides']} optimal")
        
    except Exception as e:
        logger.error(f"Error analyzing tide data: {e}", exc_info=True)
    
    return analysis


def check_low_tide_identification(workbook: Dict[str, Any], sheet_name: str, 
                                  ground_truth: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if low tides are correctly identified.
    Looks for a column that marks low tides (e.g., "Is_Low_Tide", "Low_Tide", etc.)
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Find a column that might contain low tide markers
        # Check columns E onwards (A-D are original data)
        low_tide_markers_found = 0
        total_rows_checked = 0
        
        for row_idx in range(1, len(sheet_data)):  # Skip header
            row = sheet_data[row_idx]
            
            # Check original Type column for reference
            if len(row) < 4:
                continue
            
            tide_type_cell = row[3]
            tide_type = tide_type_cell.get('value', '') if isinstance(tide_type_cell, dict) else tide_type_cell
            is_low_actual = str(tide_type).strip().lower() == 'low'
            
            # Look for marker in extended columns (E, F, G, etc.)
            found_marker = False
            for col_idx in range(4, min(len(row), 10)):  # Check up to column J
                cell = row[col_idx]
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                
                # Check if this cell marks low tide
                if cell_val:
                    cell_str = str(cell_val).strip().upper()
                    # Look for markers like TRUE, YES, LOW, X, 1
                    if is_low_actual and cell_str in ['TRUE', 'YES', 'LOW', 'X', '1', 'T']:
                        found_marker = True
                        break
                    elif not is_low_actual and cell_str in ['FALSE', 'NO', 'HIGH', '0', 'F', '']:
                        found_marker = True
                        break
            
            if found_marker:
                low_tide_markers_found += 1
            
            total_rows_checked += 1
        
        # Need at least 80% of rows correctly marked
        expected_low = ground_truth['low_tides']
        success = low_tide_markers_found >= (expected_low * 0.8)
        
        feedback = f"Low tide identification: {low_tide_markers_found}/{expected_low} expected low tides marked"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking low tide identification: {e}", exc_info=True)
        return False, f"Error checking low tides: {str(e)}"


def check_daylight_window_filter(workbook: Dict[str, Any], sheet_name: str,
                                 ground_truth: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if daylight window filtering is correctly implemented.
    Looks for formulas or values indicating 7 AM - 7 PM filtering.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Look for daylight markers in extended columns
        daylight_markers_found = 0
        expected_daylight = ground_truth['low_tides_daylight']
        
        # Also check for formulas containing HOUR or TIME functions
        formulas_with_time_logic = 0
        
        for row_idx in range(1, len(sheet_data)):
            row = sheet_data[row_idx]
            
            # Get time and type from original data
            if len(row) < 4:
                continue
            
            time_cell = row[1]
            time_val = time_cell.get('value', '') if isinstance(time_cell, dict) else time_cell
            hour = parse_time_value(time_val)
            
            tide_type_cell = row[3]
            tide_type = tide_type_cell.get('value', '') if isinstance(tide_type_cell, dict) else tide_type_cell
            is_low = str(tide_type).strip().lower() == 'low'
            
            in_daylight_actual = is_low and hour is not None and 7 <= hour < 19
            
            # Check extended columns for daylight markers
            for col_idx in range(4, min(len(row), 12)):
                cell = row[col_idx]
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                
                # Check for time-based formulas
                if cell_formula:
                    formula_upper = str(cell_formula).upper()
                    if 'HOUR' in formula_upper or 'TIME' in formula_upper:
                        formulas_with_time_logic += 1
                
                # Check if cell value matches expected daylight status
                if cell_val:
                    cell_str = str(cell_val).strip().upper()
                    if in_daylight_actual and cell_str in ['TRUE', 'YES', 'Y', '1', 'T']:
                        daylight_markers_found += 1
                        break
                    elif not in_daylight_actual and cell_str in ['FALSE', 'NO', 'N', '0', 'F', '']:
                        # Correct negative case
                        pass
        
        # Success if we found daylight markers for most expected cases
        success = (daylight_markers_found >= expected_daylight * 0.7) or (formulas_with_time_logic >= 5)
        
        feedback = f"Daylight filtering: {daylight_markers_found}/{expected_daylight} daylight tides marked"
        if formulas_with_time_logic > 0:
            feedback += f" | {formulas_with_time_logic} time-based formulas found"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking daylight filter: {e}", exc_info=True)
        return False, f"Error checking daylight: {str(e)}"


def check_height_threshold(workbook: Dict[str, Any], sheet_name: str,
                           ground_truth: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if height threshold (≤ 1.5 ft) is correctly applied.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        height_markers_found = 0
        expected_optimal = ground_truth['optimal_tides']
        
        for row_idx in range(1, len(sheet_data)):
            row = sheet_data[row_idx]
            
            if len(row) < 4:
                continue
            
            # Get height from original data
            height_cell = row[2]
            height_val = height_cell.get('value', 0) if isinstance(height_cell, dict) else height_cell
            
            tide_type_cell = row[3]
            tide_type = tide_type_cell.get('value', '') if isinstance(tide_type_cell, dict) else tide_type_cell
            is_low = str(tide_type).strip().lower() == 'low'
            
            try:
                height = float(height_val)
                meets_height = is_low and height <= 1.5
            except (ValueError, TypeError):
                meets_height = False
            
            # Check extended columns for height threshold markers
            for col_idx in range(4, min(len(row), 12)):
                cell = row[col_idx]
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                
                if cell_val:
                    cell_str = str(cell_val).strip().upper()
                    if meets_height and cell_str in ['TRUE', 'YES', 'Y', '1', 'T', 'OPTIMAL']:
                        height_markers_found += 1
                        break
        
        success = height_markers_found >= expected_optimal * 0.6
        feedback = f"Height threshold: {height_markers_found}/{expected_optimal} optimal heights marked"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking height threshold: {e}", exc_info=True)
        return False, f"Error checking height: {str(e)}"


def check_activity_windows(workbook: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Check if activity window durations are calculated.
    Looks for columns with time durations or formulas computing time differences.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Look for duration values or time arithmetic formulas
        duration_values_found = 0
        time_arithmetic_formulas = 0
        
        for row_idx in range(1, min(len(sheet_data), 15)):  # Check first 14 data rows
            row = sheet_data[row_idx]
            
            # Check extended columns
            for col_idx in range(4, min(len(row), 12)):
                cell = row[col_idx]
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                
                # Check for time arithmetic in formulas
                if cell_formula:
                    formula_str = str(cell_formula).upper()
                    # Look for subtraction, time functions, or duration calculations
                    if any(keyword in formula_str for keyword in ['B', 'TIME', '-', '*24', 'HOUR']):
                        time_arithmetic_formulas += 1
                
                # Check for numeric duration values (hours)
                if isinstance(cell_val, (int, float)):
                    if 0 < cell_val < 24:  # Reasonable duration in hours
                        duration_values_found += 1
        
        success = duration_values_found >= 3 or time_arithmetic_formulas >= 3
        feedback = f"Activity windows: {duration_values_found} duration values, {time_arithmetic_formulas} time formulas"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking activity windows: {e}", exc_info=True)
        return False, f"Error checking windows: {str(e)}"


def check_summary_statistics(workbook: Dict[str, Any], sheet_name: str,
                             ground_truth: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if summary statistics are present and accurate.
    Looks for COUNT/COUNTIF formulas and summary values.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Look for summary section (usually at bottom or side)
        summary_values_found = 0
        count_formulas_found = 0
        
        # Check all cells for summary-like content
        for row_idx, row in enumerate(sheet_data):
            for col_idx, cell in enumerate(row):
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                cell_formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                
                # Check for COUNT formulas
                if cell_formula:
                    formula_upper = str(cell_formula).upper()
                    if any(keyword in formula_upper for keyword in ['COUNT', 'SUM', 'COUNTA']):
                        count_formulas_found += 1
                
                # Check for summary values matching ground truth
                if isinstance(cell_val, (int, float)):
                    val = int(cell_val)
                    # Check if matches expected counts (with tolerance)
                    expected_values = [
                        ground_truth['low_tides'],
                        ground_truth['low_tides_daylight'],
                        ground_truth['optimal_tides']
                    ]
                    
                    for expected in expected_values:
                        if abs(val - expected) <= 1:  # ±1 tolerance
                            summary_values_found += 1
                            break
        
        success = summary_values_found >= 2 or count_formulas_found >= 2
        feedback = f"Summary statistics: {summary_values_found} matching values, {count_formulas_found} count formulas"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking summary: {e}", exc_info=True)
        return False, f"Error checking summary: {str(e)}"


def check_recommended_days(workbook: Dict[str, Any], sheet_name: str,
                          ground_truth: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Check if days are recommended appropriately.
    Looks for day markers or date-based recommendations.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        # Count rows marked as "good" or "recommended"
        recommended_count = 0
        
        # Check for recommendation markers in extended columns
        for row_idx in range(1, len(sheet_data)):
            row = sheet_data[row_idx]
            
            # Check if this row corresponds to an optimal tide
            is_optimal_row = (row_idx + 1) in ground_truth['optimal_tide_rows']
            
            # Look for recommendation markers
            for col_idx in range(4, min(len(row), 12)):
                cell = row[col_idx]
                cell_val = cell.get('value', '') if isinstance(cell, dict) else cell
                
                if cell_val:
                    cell_str = str(cell_val).strip().upper()
                    if cell_str in ['GOOD', 'RECOMMENDED', 'YES', 'OPTIMAL', 'BEST', 'GO']:
                        if is_optimal_row:
                            recommended_count += 1
                        break
        
        # Should have at least 2 recommended days for the week
        expected_min = 2
        success = recommended_count >= expected_min
        
        feedback = f"Day recommendations: {recommended_count} optimal tides marked (expected ≥{expected_min})"
        
        return success, feedback
        
    except Exception as e:
        logger.error(f"Error checking recommendations: {e}", exc_info=True)
        return False, f"Error checking recommendations: {str(e)}"


def verify_tide_calculator(traj, env_info, task_info):
    """
    Main verification function for tide window calculator task.
    
    Checks:
    1. Low tides correctly identified
    2. Daylight window filtering
    3. Height threshold applied
    4. Activity window calculations
    5. Summary statistics
    6. Day recommendations
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    file_paths = [
        ("/home/ga/Documents/tide_analysis.ods", 'ods'),
        ("/home/ga/Documents/cape_cod_tides.ods", 'ods'),
        ("/home/ga/Documents/cape_cod_tides.csv", 'csv'),
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path, file_format in file_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load tide data file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Establish ground truth from original data
        ground_truth = analyze_tide_data(workbook, sheet_name)
        
        # Run all verification checks
        criteria_results = []
        feedback_parts = []
        
        # Criterion 1: Low tide identification
        success_1, feedback_1 = check_low_tide_identification(workbook, sheet_name, ground_truth)
        criteria_results.append(success_1)
        feedback_parts.append(("✅" if success_1 else "❌") + " " + feedback_1)
        
        # Criterion 2: Daylight window filter
        success_2, feedback_2 = check_daylight_window_filter(workbook, sheet_name, ground_truth)
        criteria_results.append(success_2)
        feedback_parts.append(("✅" if success_2 else "❌") + " " + feedback_2)
        
        # Criterion 3: Height threshold
        success_3, feedback_3 = check_height_threshold(workbook, sheet_name, ground_truth)
        criteria_results.append(success_3)
        feedback_parts.append(("✅" if success_3 else "❌") + " " + feedback_3)
        
        # Criterion 4: Activity windows
        success_4, feedback_4 = check_activity_windows(workbook, sheet_name)
        criteria_results.append(success_4)
        feedback_parts.append(("✅" if success_4 else "❌") + " " + feedback_4)
        
        # Criterion 5: Summary statistics
        success_5, feedback_5 = check_summary_statistics(workbook, sheet_name, ground_truth)
        criteria_results.append(success_5)
        feedback_parts.append(("✅" if success_5 else "❌") + " " + feedback_5)
        
        # Criterion 6: Day recommendations
        success_6, feedback_6 = check_recommended_days(workbook, sheet_name, ground_truth)
        criteria_results.append(success_6)
        feedback_parts.append(("✅" if success_6 else "❌") + " " + feedback_6)
        
        # Calculate score
        criteria_passed = sum(criteria_results)
        total_criteria = len(criteria_results)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 60  # Need 4/6 criteria
        
        # Add summary
        feedback_parts.insert(0, f"Ground truth: {ground_truth['low_tides']} low tides, "
                                 f"{ground_truth['low_tides_daylight']} in daylight, "
                                 f"{ground_truth['optimal_tides']} optimal")
        
        if passed:
            feedback_parts.append("🎉 Tide analysis completed successfully!")
        else:
            feedback_parts.append("❌ Tide analysis incomplete - review calculations")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "low_tides_identified": success_1,
                "daylight_filter": success_2,
                "height_threshold": success_3,
                "activity_windows": success_4,
                "summary_stats": success_5,
                "day_recommendations": success_6
            },
            "ground_truth": ground_truth
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
