#!/usr/bin/env python3
"""
Verifier for Rebate Deadline Tracker task
"""

import sys
import os
import logging
from datetime import datetime, timedelta
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


def parse_date_flexible(date_value):
    """
    Parse date from various formats.
    Returns datetime object or None.
    """
    if isinstance(date_value, datetime):
        return date_value
    
    if date_value is None:
        return None
    
    date_str = str(date_value).strip()
    
    # Common date formats
    formats = [
        "%Y-%m-%d",
        "%m/%d/%Y",
        "%d-%m-%Y",
        "%d/%m/%Y",
        "%Y/%m/%d",
        "%m-%d-%Y",
        "%b %d, %Y",
        "%B %d, %Y",
        "%d %b %Y",
        "%d %B %Y"
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except:
            continue
    
    # Try to extract date components with regex
    # Match patterns like: 11/15/2024, 12-01-2024, 2024-11-15
    patterns = [
        r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})',  # MM/DD/YYYY or DD-MM-YYYY
        r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})',  # YYYY-MM-DD
    ]
    
    for pattern in patterns:
        match = re.search(pattern, date_str)
        if match:
            try:
                parts = [int(p) for p in match.groups()]
                # Try different interpretations
                for day, month, year in [(parts[1], parts[0], parts[2]), 
                                         (parts[0], parts[1], parts[2]),
                                         (parts[2], parts[1], parts[0])]:
                    try:
                        if 1 <= day <= 31 and 1 <= month <= 12 and year > 2000:
                            return datetime(year, month, day)
                    except:
                        continue
            except:
                continue
    
    return None


def verify_dates_standardized(workbook, sheet_name):
    """Verify all purchase dates are valid date values."""
    valid_count = 0
    total_count = 0
    
    for row_idx in range(2, 12):  # Rows 2-11 (data rows)
        cell_ref = f"B{row_idx}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value:
            total_count += 1
            parsed_date = parse_date_flexible(value)
            if parsed_date:
                valid_count += 1
    
    if total_count == 0:
        return False, "No dates found"
    
    percentage = (valid_count / total_count) * 100
    passed = percentage == 100
    
    return passed, f"{valid_count}/{total_count} dates valid ({percentage:.0f}%)"


def verify_deadlines_complete(workbook, sheet_name):
    """Verify all deadline cells are populated."""
    filled_count = 0
    total_count = 10
    
    for row_idx in range(2, 12):
        cell_ref = f"E{row_idx}"
        value = get_cell_value(workbook, sheet_name, cell_ref)
        
        if value:
            parsed = parse_date_flexible(value)
            if parsed:
                filled_count += 1
    
    passed = filled_count >= 9  # Allow 1 empty
    return passed, f"{filled_count}/{total_count} deadlines populated"


def verify_days_remaining_calculated(workbook, sheet_name):
    """Verify days remaining are calculated correctly."""
    correct_count = 0
    total_count = 0
    today = datetime.now()
    
    for row_idx in range(2, 12):
        deadline = get_cell_value(workbook, sheet_name, f"E{row_idx}")
        days_remaining = get_cell_value(workbook, sheet_name, f"F{row_idx}")
        
        if deadline and days_remaining is not None:
            total_count += 1
            parsed_deadline = parse_date_flexible(deadline)
            
            if parsed_deadline:
                # Calculate expected days remaining
                expected_days = (parsed_deadline - today).days
                
                # Allow ±1 day tolerance (due to TODAY() timing)
                try:
                    actual_days = int(float(days_remaining))
                    if abs(actual_days - expected_days) <= 1:
                        correct_count += 1
                except:
                    pass
    
    if total_count == 0:
        return False, "No days remaining calculations found"
    
    percentage = (correct_count / total_count) * 100
    passed = percentage >= 70
    
    return passed, f"{correct_count}/{total_count} days remaining correct ({percentage:.0f}%)"


def verify_status_standardized(workbook, sheet_name):
    """Verify status field has been standardized."""
    status_values = set()
    
    for row_idx in range(2, 12):
        value = get_cell_value(workbook, sheet_name, f"G{row_idx}")
        if value:
            status_values.add(str(value).strip().lower())
    
    # Expected: submitted, pending, expired (case insensitive)
    expected_values = {"submitted", "pending", "expired"}
    
    # Check if all status values are in expected set
    unexpected = status_values - expected_values
    
    if len(unexpected) == 0 and len(status_values) <= 3:
        return True, f"Status standardized: {', '.join(sorted(status_values))}"
    elif len(unexpected) <= 1:
        return True, f"Mostly standardized: {', '.join(sorted(status_values))}"
    else:
        return False, f"Status not standardized: {', '.join(sorted(status_values))}"


def verify_priority_classification(workbook, sheet_name):
    """Verify priority logic is correct."""
    correct_count = 0
    total_count = 0
    
    for row_idx in range(2, 12):
        status = get_cell_value(workbook, sheet_name, f"G{row_idx}")
        days_remaining = get_cell_value(workbook, sheet_name, f"F{row_idx}")
        priority = get_cell_value(workbook, sheet_name, f"I{row_idx}")
        
        if priority:
            total_count += 1
            priority_str = str(priority).strip().upper()
            
            # Determine expected priority
            expected = None
            if status:
                status_lower = str(status).strip().lower()
                
                if status_lower == "expired" or "expire" in status_lower:
                    expected = "EXPIRED"
                elif status_lower == "submitted" or "submit" in status_lower:
                    expected = "COMPLETE"
                elif days_remaining is not None:
                    try:
                        days = int(float(days_remaining))
                        if days < 0:
                            expected = "MISSED"
                        elif days <= 7:
                            expected = "URGENT"
                        elif days <= 14:
                            expected = "SOON"
                        else:
                            expected = "OK"
                    except:
                        pass
            
            # Check if priority matches expected (with some flexibility)
            if expected:
                if expected in priority_str or priority_str in expected:
                    correct_count += 1
                elif expected == "COMPLETE" and ("OK" in priority_str or "DONE" in priority_str):
                    correct_count += 1
                elif expected == "SOON" and "URGENT" in priority_str:
                    correct_count += 0.5  # Partial credit
    
    if total_count == 0:
        return False, "No priority classifications found"
    
    percentage = (correct_count / total_count) * 100
    passed = percentage >= 80
    
    return passed, f"Priority logic: {correct_count}/{total_count} correct ({percentage:.0f}%)"


def verify_financial_totals(workbook, sheet_name):
    """Verify SUMIF formulas for financial totals."""
    # Check for formulas in rows 13-15 or nearby
    found_formulas = 0
    formula_rows = []
    
    for row_idx in range(13, 20):
        for col in ['B', 'C', 'D']:
            formula = get_cell_formula(workbook, sheet_name, f"{col}{row_idx}")
            if formula and 'SUMIF' in formula.upper():
                found_formulas += 1
                formula_rows.append(row_idx)
                break
    
    # Also check if values look reasonable
    total_values = []
    for row_idx in range(13, 20):
        for col in ['B', 'C', 'D']:
            value = get_cell_value(workbook, sheet_name, f"{col}{row_idx}")
            if value:
                try:
                    num_val = float(str(value).replace('$', '').replace(',', ''))
                    if 10 <= num_val <= 1000:  # Reasonable rebate range
                        total_values.append(num_val)
                except:
                    pass
    
    if found_formulas >= 2:
        return True, f"✅ Financial formulas found ({found_formulas} SUMIF)"
    elif found_formulas >= 1:
        return True, f"Partial: {found_formulas} SUMIF formula found"
    elif len(total_values) >= 2:
        return True, f"Financial totals calculated ({len(total_values)} totals)"
    else:
        return False, "No financial totals found"


def verify_conditional_formatting_applied(workbook, sheet_name):
    """Check if conditional formatting exists."""
    # Try to detect conditional formatting
    has_formatting = check_conditional_formatting(workbook, sheet_name, "I2:I11")
    
    if has_formatting:
        return True, "Conditional formatting detected"
    else:
        # Check if Priority column exists as fallback
        priority_values = []
        for row_idx in range(2, 12):
            value = get_cell_value(workbook, sheet_name, f"I{row_idx}")
            if value:
                priority_values.append(value)
        
        if len(priority_values) >= 8:
            return True, "Priority column exists (formatting may be present)"
        else:
            return False, "Conditional formatting not detected"


def verify_data_sorted(workbook, sheet_name):
    """Verify data is sorted with URGENT items at top."""
    urgent_positions = []
    non_urgent_positions = []
    
    for row_idx in range(2, 12):
        priority = get_cell_value(workbook, sheet_name, f"I{row_idx}")
        if priority:
            priority_str = str(priority).strip().upper()
            if "URGENT" in priority_str:
                urgent_positions.append(row_idx)
            elif "OK" in priority_str or "COMPLETE" in priority_str or "EXPIRE" in priority_str:
                non_urgent_positions.append(row_idx)
    
    # Check if urgent items are generally in top half
    if urgent_positions:
        avg_urgent = sum(urgent_positions) / len(urgent_positions)
        if non_urgent_positions:
            avg_non_urgent = sum(non_urgent_positions) / len(non_urgent_positions)
            if avg_urgent < avg_non_urgent:
                return True, f"Data sorted: URGENT items in rows {urgent_positions}"
            else:
                return False, f"Data not sorted properly"
        else:
            if avg_urgent <= 6:  # Top half of 2-11
                return True, f"URGENT items in top rows: {urgent_positions}"
    
    # Fallback: check if any priority column exists
    has_priority = False
    for row_idx in range(2, 12):
        if get_cell_value(workbook, sheet_name, f"I{row_idx}"):
            has_priority = True
            break
    
    if has_priority:
        return True, "Priority column exists (sorting may be applied)"
    else:
        return False, "No priority column or sorting detected"


def verify_rebate_tracker(traj, env_info, task_info):
    """
    Verify rebate deadline tracker task completion.
    
    Checks:
    1. Dates standardized
    2. Deadlines complete
    3. Days remaining accurate
    4. Status standardized
    5. Priority correctly classified
    6. Financial totals accurate
    7. Conditional formatting applied
    8. Data sorted
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    file_paths = [
        "/home/ga/Documents/rebate_tracker.ods",
        "/home/ga/Documents/rebate_tracker_completed.ods",
        "/home/ga/Documents/rebate_tracker_result.ods"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for container_path in file_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_results = []
        feedback_parts = []
        
        # Criterion 1: Dates standardized
        passed, msg = verify_dates_standardized(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Dates: {msg}")
        
        # Criterion 2: Deadlines complete
        passed, msg = verify_deadlines_complete(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Deadlines: {msg}")
        
        # Criterion 3: Days remaining calculated
        passed, msg = verify_days_remaining_calculated(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Days Remaining: {msg}")
        
        # Criterion 4: Status standardized
        passed, msg = verify_status_standardized(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Status: {msg}")
        
        # Criterion 5: Priority classification
        passed, msg = verify_priority_classification(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Priority: {msg}")
        
        # Criterion 6: Financial totals
        passed, msg = verify_financial_totals(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Totals: {msg}")
        
        # Criterion 7: Conditional formatting
        passed, msg = verify_conditional_formatting_applied(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Formatting: {msg}")
        
        # Criterion 8: Data sorted
        passed, msg = verify_data_sorted(workbook, sheet_name)
        criteria_results.append(passed)
        feedback_parts.append(("✅" if passed else "❌") + f" Sorted: {msg}")
        
        # Calculate score
        criteria_passed = sum(criteria_results)
        total_criteria = len(criteria_results)
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 6/8 criteria (70%)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "dates_standardized": criteria_results[0],
                "deadlines_complete": criteria_results[1],
                "days_remaining_accurate": criteria_results[2],
                "status_standardized": criteria_results[3],
                "priority_classified": criteria_results[4],
                "financial_totals": criteria_results[5],
                "conditional_formatting": criteria_results[6],
                "data_sorted": criteria_results[7]
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
