#!/usr/bin/env python3
"""
Verifier for Timezone Meeting Finder task.

Checks:
1. UTC conversion columns exist and contain formulas
2. Sample conversions are mathematically correct
3. Overlap detection logic is present
4. Valid 2-hour meeting window is identified
"""

import sys
import os
import re
import logging
from datetime import time, datetime, timedelta
from typing import Dict, List, Tuple, Any, Optional

# Use relative path to utils folder (host machine, not container)
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


def parse_time_string(time_str: str) -> Optional[float]:
    """
    Parse time string to decimal hours (0-24).
    Handles formats: "09:00", "9:00", "14:30", etc.
    Returns None if unparseable.
    """
    if not time_str:
        return None
    
    # Convert to string if not already
    time_str = str(time_str).strip()
    
    # Handle time object from spreadsheet
    if isinstance(time_str, time):
        return time_str.hour + time_str.minute / 60.0
    
    # Try HH:MM format
    match = re.match(r'(\d{1,2}):(\d{2})', time_str)
    if match:
        hours = int(match.group(1))
        minutes = int(match.group(2))
        return hours + minutes / 60.0
    
    # Try decimal format
    try:
        val = float(time_str)
        # If it's a fraction (e.g., 0.375 for 9:00 AM in Excel format)
        if 0 <= val < 1:
            return val * 24
        # If it's already in hours
        if 0 <= val < 24:
            return val
    except (ValueError, TypeError):
        pass
    
    return None


def time_to_string(hours: float) -> str:
    """Convert decimal hours to HH:MM string."""
    h = int(hours)
    m = int((hours - h) * 60)
    return f"{h:02d}:{m:02d}"


def times_match(actual: Any, expected_hours: float, tolerance_minutes: int = 15) -> bool:
    """
    Check if actual time matches expected time within tolerance.
    
    Args:
        actual: Cell value (could be string, time object, float, etc.)
        expected_hours: Expected time in decimal hours (e.g., 14.0 for 14:00)
        tolerance_minutes: Tolerance in minutes
    """
    actual_hours = parse_time_string(actual)
    if actual_hours is None:
        return False
    
    # Calculate difference in hours
    diff_hours = abs(actual_hours - expected_hours)
    
    # Handle wraparound (e.g., 23:00 vs 01:00 = 2 hours, not 22)
    if diff_hours > 12:
        diff_hours = 24 - diff_hours
    
    diff_minutes = diff_hours * 60
    return diff_minutes <= tolerance_minutes


def check_column_exists(data: Dict[str, Any], sheet_name: str, column_header: str) -> bool:
    """Check if a column with given header exists in the first row."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        if not rows:
            return False
        
        header_row = rows[0]
        for cell in header_row:
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and column_header.lower() in str(cell_value).lower():
                return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking column existence: {e}")
        return False


def find_column_index(data: Dict[str, Any], sheet_name: str, column_header: str) -> Optional[int]:
    """Find the column index for a given header."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        if not rows:
            return None
        
        header_row = rows[0]
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and column_header.lower() in str(cell_value).lower():
                return idx
        
        return None
    except Exception as e:
        logger.error(f"Error finding column: {e}")
        return None


def check_formulas_present(data: Dict[str, Any], sheet_name: str, 
                           column_headers: List[str], min_formulas: int = 3) -> bool:
    """Check if specified columns contain formulas (not just values)."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        formula_count = 0
        
        for col_header in column_headers:
            col_idx = find_column_index(data, sheet_name, col_header)
            if col_idx is None:
                continue
            
            # Check data rows (skip header)
            for row_idx in range(1, min(len(rows), 7)):  # Check first 6 data rows
                if row_idx < len(rows) and col_idx < len(rows[row_idx]):
                    cell = rows[row_idx][col_idx]
                    if isinstance(cell, dict):
                        formula = cell.get('formula')
                        if formula:
                            formula_count += 1
        
        return formula_count >= min_formulas
    except Exception as e:
        logger.error(f"Error checking formulas: {e}")
        return False


def validate_utc_conversions(data: Dict[str, Any], sheet_name: str) -> Tuple[int, int, List[str]]:
    """
    Validate UTC conversion accuracy.
    
    Returns:
        (correct_count, total_checked, feedback_list)
    """
    # Expected conversions (name, local_start_str, offset, expected_utc_hours)
    test_cases = [
        ("Alex", "09:00", -5, 14.0),      # NYC 9am → 14:00 UTC (9 - (-5) = 14)
        ("Priya", "08:00", 0, 8.0),       # London 8am → 8:00 UTC
        ("Kenji", "10:00", 9, 1.0),       # Tokyo 10am → 1:00 UTC (10 - 9 = 1)
        ("Sophie", "09:00", 11, 22.0),    # Sydney 9am → 22:00 UTC previous day (9 - 11 = -2 → 22)
        ("Carlos", "10:00", -8, 18.0),    # LA 10am → 18:00 UTC (10 - (-8) = 18)
    ]
    
    sheets = data.get('sheets', {})
    if sheet_name not in sheets:
        return 0, 0, ["Sheet not found"]
    
    rows = sheets[sheet_name]
    
    # Find column indices
    name_col = find_column_index(data, sheet_name, "Name")
    utc_start_col = find_column_index(data, sheet_name, "UTC Start")
    
    if name_col is None or utc_start_col is None:
        return 0, 0, ["Required columns not found"]
    
    correct = 0
    total = 0
    feedback = []
    
    for test_name, local_time, offset, expected_utc in test_cases:
        # Find the row for this person
        person_row_idx = None
        for row_idx in range(1, len(rows)):
            if row_idx < len(rows) and name_col < len(rows[row_idx]):
                cell_value = rows[row_idx][name_col]
                name_val = cell_value.get('value') if isinstance(cell_value, dict) else cell_value
                if name_val and test_name.lower() in str(name_val).lower():
                    person_row_idx = row_idx
                    break
        
        if person_row_idx is None:
            continue
        
        total += 1
        
        # Get UTC start value
        if person_row_idx < len(rows) and utc_start_col < len(rows[person_row_idx]):
            utc_cell = rows[person_row_idx][utc_start_col]
            utc_value = utc_cell.get('value') if isinstance(utc_cell, dict) else utc_cell
            
            if times_match(utc_value, expected_utc, tolerance_minutes=15):
                correct += 1
                feedback.append(f"✓ {test_name}: {expected_utc:.1f}h")
            else:
                actual_parsed = parse_time_string(utc_value)
                if actual_parsed is not None:
                    feedback.append(f"✗ {test_name}: expected {time_to_string(expected_utc)}, got {time_to_string(actual_parsed)}")
                else:
                    feedback.append(f"✗ {test_name}: expected {time_to_string(expected_utc)}, got {utc_value}")
    
    return correct, total, feedback


def find_overlap_analysis(data: Dict[str, Any], sheet_name: str) -> bool:
    """
    Check if there's evidence of overlap analysis in the spreadsheet.
    Looks for:
    - Multiple AND() formulas
    - References to multiple team members' UTC times
    - Cells with TRUE/FALSE or 1/0 indicating availability checks
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False
        
        rows = sheets[sheet_name]
        
        # Look for AND formulas in rows beyond the data
        and_formula_count = 0
        for row_idx in range(7, min(len(rows), 25)):  # Check rows 7-25 for analysis
            if row_idx >= len(rows):
                break
            
            for cell in rows[row_idx]:
                if isinstance(cell, dict):
                    formula = cell.get('formula')
                    if formula and 'AND' in str(formula).upper():
                        and_formula_count += 1
        
        return and_formula_count >= 1
    except Exception as e:
        logger.error(f"Error finding overlap analysis: {e}")
        return False


def find_meeting_recommendation(data: Dict[str, Any], sheet_name: str) -> Optional[str]:
    """
    Look for a meeting time recommendation in the spreadsheet.
    Searches for cells containing time ranges like "16:00-18:00" or similar.
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        
        # Search all cells for time range patterns
        time_range_pattern = re.compile(r'(\d{1,2}):(\d{2})\s*[-–—to]\s*(\d{1,2}):(\d{2})')
        
        for row in rows:
            for cell in row:
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                if cell_value:
                    match = time_range_pattern.search(str(cell_value))
                    if match:
                        return str(cell_value)
        
        return None
    except Exception as e:
        logger.error(f"Error finding meeting recommendation: {e}")
        return None


def validate_meeting_window(window_str: Optional[str], min_duration_hours: int = 2) -> bool:
    """
    Validate that a meeting window string represents a valid time range.
    
    Args:
        window_str: String like "16:00-18:00 UTC"
        min_duration_hours: Minimum duration in hours
    """
    if not window_str:
        return False
    
    # Extract times
    match = re.search(r'(\d{1,2}):(\d{2})\s*[-–—to]\s*(\d{1,2}):(\d{2})', window_str)
    if not match:
        return False
    
    start_h = int(match.group(1))
    start_m = int(match.group(2))
    end_h = int(match.group(3))
    end_m = int(match.group(4))
    
    start_hours = start_h + start_m / 60.0
    end_hours = end_h + end_m / 60.0
    
    # Handle wraparound
    if end_hours < start_hours:
        end_hours += 24
    
    duration = end_hours - start_hours
    return duration >= min_duration_hours


def verify_timezone_meeting_finder(traj, env_info, task_info):
    """
    Verify the timezone meeting scheduling task.
    
    Scoring breakdown:
    - UTC conversion columns exist: 20 points
    - Formulas used (not hardcoded): 10 points
    - Conversion accuracy (3+ correct out of 5): 30 points
    - Overlap detection logic: 25 points
    - Meeting window identified: 15 points
    
    Total: 100 points
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/meeting_schedule.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet name (should be "Schedule")
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        score = 0
        feedback_parts = []
        
        # Check 1: UTC conversion columns exist (20 points)
        utc_start_exists = check_column_exists(workbook, sheet_name, "UTC Start")
        utc_end_exists = check_column_exists(workbook, sheet_name, "UTC End")
        
        if utc_start_exists and utc_end_exists:
            score += 20
            feedback_parts.append("✅ UTC conversion columns present")
            
            # Check 2: Formulas used (10 points)
            has_formulas = check_formulas_present(workbook, sheet_name, ["UTC Start", "UTC End"], min_formulas=5)
            if has_formulas:
                score += 10
                feedback_parts.append("✅ UTC conversions use formulas (not hardcoded)")
            else:
                feedback_parts.append("⚠️ UTC values may be hardcoded instead of formulas")
        else:
            feedback_parts.append("❌ Missing UTC conversion columns")
        
        # Check 3: Validate conversion accuracy (30 points)
        correct, total, conversion_feedback = validate_utc_conversions(workbook, sheet_name)
        
        if total > 0:
            conversion_score = int((correct / total) * 30)
            score += conversion_score
            feedback_parts.append(f"{'✅' if correct >= 3 else '⚠️'} Conversions: {correct}/{total} correct ({conversion_score} pts)")
            
            # Add detailed feedback
            if conversion_feedback:
                logger.info(f"Conversion details: {', '.join(conversion_feedback)}")
        else:
            feedback_parts.append("❌ Could not validate conversions (columns missing)")
        
        # Check 4: Overlap detection logic (25 points)
        has_overlap_analysis = find_overlap_analysis(workbook, sheet_name)
        if has_overlap_analysis:
            score += 25
            feedback_parts.append("✅ Overlap analysis logic detected (AND formulas found)")
        else:
            # Give partial credit if UTC conversions are present
            if utc_start_exists and utc_end_exists:
                score += 10
                feedback_parts.append("⚠️ Overlap analysis incomplete (partial credit)")
            else:
                feedback_parts.append("❌ No overlap analysis found")
        
        # Check 5: Meeting window identified (15 points)
        meeting_window = find_meeting_recommendation(workbook, sheet_name)
        if meeting_window:
            if validate_meeting_window(meeting_window, min_duration_hours=2):
                score += 15
                feedback_parts.append(f"✅ Valid meeting window: {meeting_window}")
            else:
                score += 7
                feedback_parts.append(f"⚠️ Meeting window found but may be invalid: {meeting_window}")
        else:
            feedback_parts.append("❌ No meeting time recommendation found")
        
        # Determine pass/fail
        passed = score >= 70
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent timezone coordination!")
        elif passed:
            feedback_parts.append("✅ Task completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "utc_columns_exist": utc_start_exists and utc_end_exists,
                "formulas_used": has_formulas if utc_start_exists else False,
                "conversion_accuracy": f"{correct}/{total}" if total > 0 else "N/A",
                "overlap_logic": has_overlap_analysis,
                "meeting_window": meeting_window is not None
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
