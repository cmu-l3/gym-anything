#!/usr/bin/env python3
"""
Verifier for Blood Donor Eligibility Matcher task
Validates date arithmetic, conditional logic, and blood type matching
"""

import sys
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Any, Optional

# Add utils to path - use relative path for host machine execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_flexible(date_value: Any) -> Optional[datetime]:
    """
    Parse date from various formats (string, datetime, Excel serial number)
    
    Args:
        date_value: Value that might represent a date
        
    Returns:
        datetime object or None if parsing fails
    """
    if date_value is None or date_value == '':
        return None
    
    # Already a datetime
    if isinstance(date_value, datetime):
        return date_value
    
    # Try parsing string
    if isinstance(date_value, str):
        # Common formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d', '%m-%d-%Y']:
            try:
                return datetime.strptime(date_value.strip(), fmt)
            except ValueError:
                continue
        
        # Try dateutil parser as fallback
        try:
            from dateutil import parser as date_parser
            return date_parser.parse(date_value)
        except:
            pass
    
    # Try Excel serial number (days since 1899-12-30)
    if isinstance(date_value, (int, float)):
        try:
            excel_epoch = datetime(1899, 12, 30)
            return excel_epoch + timedelta(days=float(date_value))
        except:
            pass
    
    return None


def find_column_index(sheet_data: List[List[Dict]], header_keywords: List[str]) -> Optional[int]:
    """
    Find column index by searching for keywords in header row
    
    Args:
        sheet_data: Sheet rows data
        header_keywords: List of possible header names (case-insensitive)
        
    Returns:
        Column index (0-based) or None if not found
    """
    if not sheet_data or len(sheet_data) == 0:
        return None
    
    header_row = sheet_data[0]
    
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value', '') if isinstance(cell, dict) else str(cell)
        if cell_value is None:
            continue
        
        cell_text = str(cell_value).strip().lower()
        
        for keyword in header_keywords:
            if keyword.lower() in cell_text:
                return col_idx
    
    return None


def verify_date_arithmetic(last_donation: Any, next_eligible: Any, tolerance_days: int = 1) -> Tuple[bool, str]:
    """
    Verify that next_eligible = last_donation + 56 days (within tolerance)
    
    Args:
        last_donation: Last donation date value
        next_eligible: Next eligible date value
        tolerance_days: Allowed difference in days
        
    Returns:
        (is_correct, message)
    """
    last_date = parse_date_flexible(last_donation)
    next_date = parse_date_flexible(next_eligible)
    
    if last_date is None:
        return True, "No last donation date (skipped)"
    
    if next_date is None:
        return False, "Next eligible date missing or invalid"
    
    expected_next = last_date + timedelta(days=56)
    actual_diff = abs((next_date - expected_next).days)
    
    if actual_diff <= tolerance_days:
        return True, f"Correct (+56 days)"
    else:
        return False, f"Incorrect: {actual_diff} days off from expected +56"


def verify_eligibility_logic(next_eligible: Any, eligible_now_value: Any, reference_date: datetime) -> Tuple[bool, str]:
    """
    Verify that eligible_now correctly reflects whether reference_date >= next_eligible
    
    Args:
        next_eligible: Next eligible date
        eligible_now_value: The "Eligible Now?" cell value
        reference_date: Today's date for comparison
        
    Returns:
        (is_correct, message)
    """
    next_date = parse_date_flexible(next_eligible)
    
    if next_date is None:
        # If no next eligible date, might be first-time donor
        # Could be marked as eligible or unknown
        return True, "No next eligible date (skipped)"
    
    # Determine if should be eligible
    should_be_eligible = reference_date >= next_date
    
    # Parse eligible_now_value
    eligible_text = str(eligible_now_value).strip().upper() if eligible_now_value else ""
    is_marked_eligible = eligible_text in ["YES", "TRUE", "1", "ELIGIBLE"]
    is_marked_not_eligible = eligible_text in ["NO", "FALSE", "0", "NOT ELIGIBLE"]
    
    if should_be_eligible:
        if is_marked_eligible:
            return True, "Correctly marked eligible"
        else:
            return False, f"Should be eligible but marked: {eligible_now_value}"
    else:
        if is_marked_not_eligible:
            return True, "Correctly marked not eligible"
        else:
            return False, f"Should NOT be eligible but marked: {eligible_now_value}"


def verify_urgent_match_logic(blood_type: Any, eligible_now: Any, urgent_match: Any) -> Tuple[bool, str]:
    """
    Verify urgent match: should be marked if (blood_type = O+ AND eligible = YES)
    
    Args:
        blood_type: Blood type value
        eligible_now: Eligible now value
        urgent_match: Urgent match value
        
    Returns:
        (is_correct, message)
    """
    blood_type_str = str(blood_type).strip().upper() if blood_type else ""
    is_o_positive = blood_type_str == "O+"
    
    eligible_text = str(eligible_now).strip().upper() if eligible_now else ""
    is_eligible = eligible_text in ["YES", "TRUE", "1", "ELIGIBLE"]
    
    should_be_urgent = is_o_positive and is_eligible
    
    urgent_text = str(urgent_match).strip() if urgent_match else ""
    is_marked_urgent = len(urgent_text) > 0 and any(
        marker in urgent_text.upper() for marker in ["URGENT", "★", "*", "PRIORITY", "YES"]
    )
    
    if should_be_urgent:
        if is_marked_urgent:
            return True, "Correctly marked urgent"
        else:
            return False, f"Should be urgent (O+ and eligible) but not marked"
    else:
        if not is_marked_urgent:
            return True, "Correctly not marked urgent"
        else:
            return False, f"Should NOT be urgent but marked: {urgent_match}"


def verify_blood_donor_eligibility(traj, env_info, task_info):
    """
    Verify blood donor eligibility task completion.
    
    Checks:
    1. Next Eligible Date column exists and contains date calculations
    2. Date arithmetic correct (sample verification)
    3. Eligibility logic correct ("Eligible Now?" reflects date comparison)
    4. Urgent match logic (O+ AND Eligible properly identified)
    5. Formula coverage (80%+ of rows have formulas)
    6. Minimal errors (<10% error cells)
    7. At least 2 urgent donors identified
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    file_paths = [
        ("/home/ga/Documents/blood_donor_eligibility.ods", "ods"),
        ("/home/ga/Documents/blood_donors.ods", "ods"),
        ("/home/ga/Documents/blood_donors.csv", "csv"),
    ]
    
    success = False
    file_info = None
    
    for container_path, fmt in file_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [fmt]
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(p[0] for p in file_paths)}"
        }
    
    try:
        workbook = file_info['sheet_data']
        sheet_names = get_sheet_names(workbook)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = workbook['sheets'][sheet_name]
        
        if len(sheet_rows) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows"}
        
        # Initialize criteria tracking
        criteria_met = 0
        total_criteria = 7
        feedback_parts = []
        
        today = datetime.now()
        
        # Find column indices
        blood_type_col = find_column_index(sheet_rows, ['blood type', 'type'])
        last_donation_col = find_column_index(sheet_rows, ['last donation', 'last donation date', 'donation date'])
        next_eligible_col = find_column_index(sheet_rows, ['next eligible', 'eligible date', 'next eligible date'])
        eligible_now_col = find_column_index(sheet_rows, ['eligible now', 'eligible', 'currently eligible'])
        urgent_match_col = find_column_index(sheet_rows, ['urgent', 'urgent match', 'o+', 'priority'])
        
        logger.info(f"Column indices - Blood Type: {blood_type_col}, Last Donation: {last_donation_col}, "
                   f"Next Eligible: {next_eligible_col}, Eligible Now: {eligible_now_col}, Urgent Match: {urgent_match_col}")
        
        # Criterion 1: Next Eligible Date column exists
        if next_eligible_col is not None:
            criteria_met += 1
            feedback_parts.append("✅ 'Next Eligible Date' column found")
        else:
            feedback_parts.append("❌ 'Next Eligible Date' column missing")
        
        # Criterion 2: Date arithmetic correct (sample check)
        date_arithmetic_checks = []
        if next_eligible_col is not None and last_donation_col is not None:
            sample_rows = min(10, len(sheet_rows) - 1)  # Check up to 10 data rows
            for row_idx in range(1, sample_rows + 1):
                if row_idx >= len(sheet_rows):
                    break
                
                row = sheet_rows[row_idx]
                if last_donation_col < len(row) and next_eligible_col < len(row):
                    last_donation = row[last_donation_col].get('value') if isinstance(row[last_donation_col], dict) else row[last_donation_col]
                    next_eligible = row[next_eligible_col].get('value') if isinstance(row[next_eligible_col], dict) else row[next_eligible_col]
                    
                    is_correct, msg = verify_date_arithmetic(last_donation, next_eligible)
                    date_arithmetic_checks.append(is_correct)
        
        if date_arithmetic_checks:
            accuracy = sum(date_arithmetic_checks) / len(date_arithmetic_checks)
            if accuracy >= 0.8:  # 80% of sampled rows correct
                criteria_met += 1
                feedback_parts.append(f"✅ Date arithmetic correct ({int(accuracy * 100)}% of sampled rows)")
            else:
                feedback_parts.append(f"❌ Date arithmetic errors ({int(accuracy * 100)}% correct, need 80%)")
        else:
            feedback_parts.append("⚠️ Could not verify date arithmetic (columns not found)")
        
        # Criterion 3: Eligibility logic correct
        eligibility_checks = []
        if next_eligible_col is not None and eligible_now_col is not None:
            sample_rows = min(10, len(sheet_rows) - 1)
            for row_idx in range(1, sample_rows + 1):
                if row_idx >= len(sheet_rows):
                    break
                
                row = sheet_rows[row_idx]
                if next_eligible_col < len(row) and eligible_now_col < len(row):
                    next_eligible = row[next_eligible_col].get('value') if isinstance(row[next_eligible_col], dict) else row[next_eligible_col]
                    eligible_now = row[eligible_now_col].get('value') if isinstance(row[eligible_now_col], dict) else row[eligible_now_col]
                    
                    is_correct, msg = verify_eligibility_logic(next_eligible, eligible_now, today)
                    eligibility_checks.append(is_correct)
        
        if eligibility_checks:
            accuracy = sum(eligibility_checks) / len(eligibility_checks)
            if accuracy >= 0.8:
                criteria_met += 1
                feedback_parts.append(f"✅ Eligibility logic correct ({int(accuracy * 100)}%)")
            else:
                feedback_parts.append(f"❌ Eligibility logic errors ({int(accuracy * 100)}% correct)")
        else:
            feedback_parts.append("⚠️ Could not verify eligibility logic")
        
        # Criterion 4: Urgent match logic
        urgent_match_checks = []
        urgent_donor_count = 0
        
        if blood_type_col is not None and eligible_now_col is not None and urgent_match_col is not None:
            for row_idx in range(1, len(sheet_rows)):
                row = sheet_rows[row_idx]
                if (blood_type_col < len(row) and eligible_now_col < len(row) and urgent_match_col < len(row)):
                    blood_type = row[blood_type_col].get('value') if isinstance(row[blood_type_col], dict) else row[blood_type_col]
                    eligible_now = row[eligible_now_col].get('value') if isinstance(row[eligible_now_col], dict) else row[eligible_now_col]
                    urgent_match = row[urgent_match_col].get('value') if isinstance(row[urgent_match_col], dict) else row[urgent_match_col]
                    
                    is_correct, msg = verify_urgent_match_logic(blood_type, eligible_now, urgent_match)
                    urgent_match_checks.append(is_correct)
                    
                    # Count urgent donors
                    urgent_text = str(urgent_match).strip() if urgent_match else ""
                    if len(urgent_text) > 0 and any(marker in urgent_text.upper() for marker in ["URGENT", "★", "*", "PRIORITY", "YES"]):
                        urgent_donor_count += 1
        
        if urgent_match_checks:
            accuracy = sum(urgent_match_checks) / len(urgent_match_checks)
            if accuracy >= 0.8:
                criteria_met += 1
                feedback_parts.append(f"✅ Urgent match logic correct ({int(accuracy * 100)}%)")
            else:
                feedback_parts.append(f"❌ Urgent match logic errors ({int(accuracy * 100)}% correct)")
        else:
            feedback_parts.append("⚠️ Could not verify urgent match logic")
        
        # Criterion 5: Formula coverage (check if formulas are used, not hardcoded)
        formula_count = 0
        total_cells_checked = 0
        
        for row_idx in range(1, len(sheet_rows)):
            row = sheet_rows[row_idx]
            for col_idx in [next_eligible_col, eligible_now_col, urgent_match_col]:
                if col_idx is not None and col_idx < len(row):
                    cell = row[col_idx]
                    if isinstance(cell, dict) and cell.get('formula'):
                        formula_count += 1
                    total_cells_checked += 1
        
        if total_cells_checked > 0:
            formula_coverage = formula_count / total_cells_checked
            if formula_coverage >= 0.8:
                criteria_met += 1
                feedback_parts.append(f"✅ Formula coverage good ({int(formula_coverage * 100)}%)")
            else:
                feedback_parts.append(f"⚠️ Low formula coverage ({int(formula_coverage * 100)}%, need 80%+)")
        
        # Criterion 6: Minimal errors (check for #VALUE!, #REF!, etc.)
        error_count = 0
        total_new_cells = 0
        
        for row_idx in range(1, len(sheet_rows)):
            row = sheet_rows[row_idx]
            for col_idx in [next_eligible_col, eligible_now_col, urgent_match_col]:
                if col_idx is not None and col_idx < len(row):
                    cell_value = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                    if cell_value and isinstance(cell_value, str) and any(err in str(cell_value) for err in ['#VALUE!', '#REF!', '#NAME?', '#DIV/0!', '#N/A']):
                        error_count += 1
                    total_new_cells += 1
        
        if total_new_cells > 0:
            error_rate = error_count / total_new_cells
            if error_rate < 0.1:
                criteria_met += 1
                feedback_parts.append(f"✅ Minimal formula errors ({error_count}/{total_new_cells})")
            else:
                feedback_parts.append(f"❌ Too many formula errors ({error_count}/{total_new_cells})")
        
        # Criterion 7: At least 2 urgent donors identified
        if urgent_donor_count >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Urgent donors identified ({urgent_donor_count} donors)")
        else:
            feedback_parts.append(f"⚠️ Few urgent donors found ({urgent_donor_count}, expected 2+)")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (5 out of 7 criteria)
        
        # Add summary
        if passed:
            feedback_parts.insert(0, f"🩸 Task completed: {criteria_met}/{total_criteria} criteria met")
        else:
            feedback_parts.insert(0, f"❌ Task incomplete: {criteria_met}/{total_criteria} criteria met (need 5)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "next_eligible_column_exists": next_eligible_col is not None,
                "date_arithmetic_correct": len(date_arithmetic_checks) > 0 and sum(date_arithmetic_checks) / len(date_arithmetic_checks) >= 0.8 if date_arithmetic_checks else False,
                "eligibility_logic_correct": len(eligibility_checks) > 0 and sum(eligibility_checks) / len(eligibility_checks) >= 0.8 if eligibility_checks else False,
                "urgent_match_logic_correct": len(urgent_match_checks) > 0 and sum(urgent_match_checks) / len(urgent_match_checks) >= 0.8 if urgent_match_checks else False,
                "formula_coverage_good": formula_coverage >= 0.8 if total_cells_checked > 0 else False,
                "minimal_errors": error_rate < 0.1 if total_new_cells > 0 else False,
                "urgent_donors_found": urgent_donor_count >= 2
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir') if file_info else None)
