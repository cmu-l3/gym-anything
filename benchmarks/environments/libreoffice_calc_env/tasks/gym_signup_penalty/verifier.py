#!/usr/bin/env python3
"""
Verifier for Gym Class Sign-up Penalty Calculator task
Checks data cleaning, formula correctness, penalty calculations, and fairness audit
"""

import sys
import os
import logging
import re
from typing import Dict, Any, List, Tuple

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_environment,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_hours_calculation(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify hours_before_class calculation is present and reasonable.
    Checks a few sample rows to ensure formula structure looks correct.
    """
    try:
        # Check if hours_before_class column exists (should be column H or similar)
        # Try to find it by checking headers
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, f"Sheet '{sheet_name}' not found"
        
        rows = sheets[sheet_name]
        if len(rows) < 2:
            return False, "Insufficient rows in Bookings sheet"
        
        # Check header row for hours_before_class column
        header_row = rows[0]
        hours_col_idx = None
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            if cell_value and 'hours' in str(cell_value).lower() and 'before' in str(cell_value).lower():
                hours_col_idx = idx
                break
        
        if hours_col_idx is None:
            return False, "hours_before_class column not found in headers"
        
        # Check a few data rows have numeric values or formulas
        valid_count = 0
        for i in range(1, min(10, len(rows))):
            if hours_col_idx < len(rows[i]):
                cell = rows[i][hours_col_idx]
                value = cell.get('value', '') if isinstance(cell, dict) else cell
                formula = cell.get('formula', '') if isinstance(cell, dict) else None
                
                # Valid if has a formula or numeric value
                if formula or isinstance(value, (int, float)):
                    valid_count += 1
        
        if valid_count >= 3:
            return True, f"Hours calculation present (validated {valid_count} rows)"
        else:
            return False, f"Hours calculation missing or incorrect (only {valid_count} valid rows)"
    
    except Exception as e:
        logger.error(f"Error checking hours calculation: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_strike_logic(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Verify strike_earned column exists and contains binary values (0 or 1).
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, f"Sheet '{sheet_name}' not found"
        
        rows = sheets[sheet_name]
        if len(rows) < 2:
            return False, "Insufficient rows"
        
        # Find strike_earned column
        header_row = rows[0]
        strike_col_idx = None
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
            if cell_value and 'strike' in str(cell_value).lower() and 'earned' in str(cell_value).lower():
                strike_col_idx = idx
                break
        
        if strike_col_idx is None:
            return False, "strike_earned column not found"
        
        # Check values are 0 or 1
        valid_count = 0
        for i in range(1, min(20, len(rows))):
            if strike_col_idx < len(rows[i]):
                cell = rows[i][strike_col_idx]
                value = cell.get('value', '') if isinstance(cell, dict) else cell
                if value in [0, 1, "0", "1", 0.0, 1.0]:
                    valid_count += 1
        
        if valid_count >= 10:
            return True, f"Strike logic implemented ({valid_count} valid entries)"
        else:
            return False, f"Strike logic incorrect (only {valid_count}/20 valid)"
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def check_member_penalties_sheet(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify Member_Penalties sheet exists with required columns.
    """
    try:
        sheets = data.get('sheets', {})
        
        # Look for sheet with "penalties" or "member" in name
        penalty_sheet = None
        for sheet_name in sheets.keys():
            if 'penalties' in sheet_name.lower() or ('member' in sheet_name.lower() and 'penalt' in sheet_name.lower()):
                penalty_sheet = sheet_name
                break
        
        if not penalty_sheet:
            return False, "Member_Penalties sheet not found"
        
        rows = sheets[penalty_sheet]
        if len(rows) < 2:
            return False, "Member_Penalties sheet has insufficient rows"
        
        # Check for required columns
        header_row = rows[0]
        header_values = [str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() for cell in header_row]
        
        required_cols = ['member', 'strike', 'penalty', 'status']
        found_cols = 0
        for req in required_cols:
            if any(req in h for h in header_values):
                found_cols += 1
        
        if found_cols >= 3:
            # Count data rows
            data_rows = len(rows) - 1
            return True, f"Member_Penalties sheet exists with {data_rows} members"
        else:
            return False, f"Member_Penalties missing required columns (found {found_cols}/4)"
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def check_penalty_status_assignment(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify penalty_status column has appropriate values.
    """
    try:
        sheets = data.get('sheets', {})
        
        # Find Member_Penalties sheet
        penalty_sheet = None
        for sheet_name in sheets.keys():
            if 'penalties' in sheet_name.lower() or 'member' in sheet_name.lower():
                penalty_sheet = sheet_name
                break
        
        if not penalty_sheet:
            return False, "Cannot find penalty sheet"
        
        rows = sheets[penalty_sheet]
        header_row = rows[0]
        
        # Find penalty_status column
        status_col_idx = None
        for idx, cell in enumerate(header_row):
            cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if 'penalty' in cell_value and 'status' in cell_value:
                status_col_idx = idx
                break
        
        if status_col_idx is None:
            # Try just "status"
            for idx, cell in enumerate(header_row):
                cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                if cell_value == 'status' or 'status' in cell_value:
                    status_col_idx = idx
                    break
        
        if status_col_idx is None:
            return False, "penalty_status column not found"
        
        # Check for expected values
        status_counts = {'good': 0, 'warning': 0, 'restricted': 0, 'other': 0}
        for i in range(1, len(rows)):
            if status_col_idx < len(rows[i]):
                cell = rows[i][status_col_idx]
                value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                
                if 'good' in value or 'standing' in value:
                    status_counts['good'] += 1
                elif 'warning' in value or 'warn' in value:
                    status_counts['warning'] += 1
                elif 'restrict' in value:
                    status_counts['restricted'] += 1
                elif value:
                    status_counts['other'] += 1
        
        total = sum(status_counts.values())
        if total < 10:
            return False, f"Too few penalty statuses assigned ({total})"
        
        # Should have at least some warnings and restrictions
        if status_counts['warning'] > 0 or status_counts['restricted'] > 0:
            return True, f"Penalty statuses assigned: {status_counts['restricted']} restricted, {status_counts['warning']} warnings, {status_counts['good']} good standing"
        else:
            return False, "No warnings or restrictions found (expected at least some)"
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def check_fairness_audit(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Verify Fairness_Summary sheet exists with demographic analysis.
    """
    try:
        sheets = data.get('sheets', {})
        
        # Look for fairness sheet
        fairness_sheet = None
        for sheet_name in sheets.keys():
            if 'fairness' in sheet_name.lower() or 'summary' in sheet_name.lower():
                fairness_sheet = sheet_name
                break
        
        if not fairness_sheet:
            return False, "Fairness_Summary sheet not found"
        
        rows = sheets[fairness_sheet]
        if len(rows) < 2:
            return False, "Fairness_Summary has insufficient data"
        
        # Check for demographic analysis columns
        header_row = rows[0]
        header_values = [str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() for cell in header_row]
        
        has_demographic = any('group' in h or 'demographic' in h or 'age' in h or 'membership' in h for h in header_values)
        has_avg = any('avg' in h or 'average' in h for h in header_values)
        
        if has_demographic and has_avg:
            data_rows = len(rows) - 1
            return True, f"Fairness audit complete with {data_rows} demographic groups"
        else:
            return False, "Fairness_Summary missing required analysis columns"
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def check_data_cleaning(data: Dict[str, Any], sheet_name: str) -> Tuple[bool, str]:
    """
    Check if data has been cleaned (duplicates removed, names standardized).
    This is approximate - we check row counts and name formatting.
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return False, f"Sheet '{sheet_name}' not found"
        
        rows = sheets[sheet_name]
        
        # Original data had 200 bookings + 8 duplicates = 208 total rows (+ header = 209)
        # After cleaning should have ~200 data rows
        data_row_count = len(rows) - 1  # Exclude header
        
        if 190 <= data_row_count <= 205:
            cleaned = True
            msg = f"Data appears cleaned (~{data_row_count} rows, expected ~200)"
        else:
            cleaned = False
            msg = f"Data may not be cleaned ({data_row_count} rows, expected ~200)"
        
        return cleaned, msg
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def check_conditional_formatting(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Note: Checking conditional formatting programmatically is complex.
    We'll give partial credit if the penalty status column exists with proper values,
    as applying formatting is a manual step that's hard to verify without rendering.
    """
    # For now, we check if penalty statuses are present
    # Real conditional formatting check would require parsing styles.xml
    try:
        sheets = data.get('sheets', {})
        
        # Find Member_Penalties sheet
        penalty_sheet = None
        for sheet_name in sheets.keys():
            if 'penalties' in sheet_name.lower():
                penalty_sheet = sheet_name
                break
        
        if penalty_sheet:
            return True, "Penalty sheet exists (conditional formatting expected)"
        else:
            return False, "Cannot verify conditional formatting"
    
    except Exception as e:
        return False, f"Error: {str(e)}"


def verify_gym_penalty_calculator(traj, env_info, task_info):
    """
    Main verifier for Gym Penalty Calculator task.
    
    Checks:
    1. Hours calculation present
    2. Strike logic implemented
    3. Rolling strike counts calculated
    4. Penalty statuses assigned correctly
    5. Fairness audit completed
    6. Data cleaned
    7. Conditional formatting applied (partial check)
    8. Summary sheets exist
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Set up verification
    container_path = "/home/ga/Documents/gym_bookings.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheets = list(data.get('sheets', {}).keys())
        
        if not sheets:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        # Find Bookings sheet
        bookings_sheet = None
        for sheet in sheets:
            if 'booking' in sheet.lower():
                bookings_sheet = sheet
                break
        if not bookings_sheet:
            bookings_sheet = sheets[0]  # Fallback to first sheet
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Hours calculation
        hours_ok, hours_msg = check_hours_calculation(data, bookings_sheet)
        if hours_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {hours_msg}")
        else:
            feedback_parts.append(f"❌ Hours calculation: {hours_msg}")
        subscores['hours_calculation'] = hours_ok
        
        # Criterion 2: Strike logic
        strike_ok, strike_msg = check_strike_logic(data, bookings_sheet)
        if strike_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {strike_msg}")
        else:
            feedback_parts.append(f"❌ Strike logic: {strike_msg}")
        subscores['strike_logic'] = strike_ok
        
        # Criterion 3: Member_Penalties sheet exists
        penalties_ok, penalties_msg = check_member_penalties_sheet(data)
        if penalties_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {penalties_msg}")
        else:
            feedback_parts.append(f"❌ Member_Penalties: {penalties_msg}")
        subscores['penalties_sheet'] = penalties_ok
        
        # Criterion 4: Penalty status assignment
        status_ok, status_msg = check_penalty_status_assignment(data)
        if status_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {status_msg}")
        else:
            feedback_parts.append(f"❌ Penalty status: {status_msg}")
        subscores['penalty_status'] = status_ok
        
        # Criterion 5: Fairness audit
        fairness_ok, fairness_msg = check_fairness_audit(data)
        if fairness_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {fairness_msg}")
        else:
            feedback_parts.append(f"❌ Fairness audit: {fairness_msg}")
        subscores['fairness_audit'] = fairness_ok
        
        # Criterion 6: Data cleaning
        clean_ok, clean_msg = check_data_cleaning(data, bookings_sheet)
        if clean_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {clean_msg}")
        else:
            feedback_parts.append(f"⚠️ {clean_msg}")
        subscores['data_cleaned'] = clean_ok
        
        # Criterion 7: Conditional formatting (partial check)
        format_ok, format_msg = check_conditional_formatting(data)
        if format_ok:
            criteria_passed += 0.5  # Partial credit
            feedback_parts.append(f"⚠️ {format_msg}")
        subscores['conditional_formatting'] = format_ok
        
        # Criterion 8: Multiple sheets present
        if len(sheets) >= 4:  # Original 3 + at least 1 new sheet
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary sheets created ({len(sheets)} sheets total)")
            subscores['summary_sheets'] = True
        else:
            feedback_parts.append(f"❌ Missing summary sheets ({len(sheets)} sheets, expected 4+)")
            subscores['summary_sheets'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Need 85% to pass (7/8 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_passed}/{total_criteria} criteria met, score={score}")
        
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
        cleanup_verification_environment(file_info.get('temp_dir'))
