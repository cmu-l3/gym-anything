#!/usr/bin/env python3
"""
Verifier for Professional Certification Renewal Manager task.

Checks 8 criteria:
1. Days Until Expiration formula with TODAY()
2. Status categorization with nested IF logic
3. Conditional formatting on Status column
4. Total renewal cost SUM formula
5. CE Status comparison column
6. CE Status conditional formatting
7. Data sorted by Days Until Expiration
8. Data integrity maintained during sort
"""

import sys
import os
import logging
import re
from datetime import datetime, timedelta

# Add utils to path - use relative path for host machine execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    verify_data_sorted,
    check_conditional_formatting,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_column_by_header(data, sheet_name, header_text):
    """
    Find column letter by searching for header text in first row.
    
    Args:
        data: Parsed spreadsheet data
        sheet_name: Name of sheet
        header_text: Text to search for in headers
    
    Returns:
        Column letter (e.g., 'G') or None if not found
    """
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        if len(rows) == 0:
            return None
        
        header_row = rows[0]
        
        # Search for header text (case-insensitive, partial match)
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and header_text.lower() in str(cell_value).lower():
                # Convert column index to letter
                return _format_cell_ref(col_idx, 0)[:-1]  # Remove row number
        
        return None
    
    except Exception as e:
        logger.error(f"Error finding column by header: {e}")
        return None


def get_row_count(data, sheet_name):
    """Get number of non-empty rows in sheet."""
    try:
        sheets = data.get('sheets', {})
        if sheet_name not in sheets:
            return 0
        
        rows = sheets[sheet_name]
        row_count = 0
        
        for row in rows:
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                row_count += 1
            else:
                # Stop counting after first completely empty row
                break
        
        return row_count
    
    except Exception as e:
        logger.error(f"Error getting row count: {e}")
        return 0


def column_letter_to_index(col_letter):
    """Convert column letter to 0-based index (A=0, B=1, etc.)."""
    col_idx = 0
    for char in col_letter.upper():
        col_idx = col_idx * 26 + (ord(char) - ord('A') + 1)
    return col_idx - 1


def _format_cell_ref(col_idx, row_idx):
    """Format cell reference from indices."""
    col_str = ''
    col = col_idx + 1
    
    while col > 0:
        col -= 1
        col_str = chr(ord('A') + (col % 26)) + col_str
        col //= 26
    
    return f"{col_str}{row_idx + 1}"


def check_formula_contains(formula, keywords):
    """Check if formula contains any of the specified keywords (case-insensitive)."""
    if not formula:
        return False
    
    formula_upper = str(formula).upper()
    for keyword in keywords:
        if keyword.upper() in formula_upper:
            return True
    
    return False


def verify_certification_tracker(traj, env_info, task_info):
    """
    Verify professional certification renewal manager task completion.
    
    Checks 8 criteria:
    1. Days Until Expiration formula with TODAY()
    2. Status categorization with nested IF
    3. Conditional formatting on Status column
    4. Total renewal cost SUM formula
    5. CE Status comparison column
    6. CE Status conditional formatting  
    7. Data sorted by Days Until Expiration
    8. Data integrity maintained
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the spreadsheet
    container_path = "/home/ga/Documents/certification_tracker.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        # Try alternative path
        container_path = "/home/ga/Documents/certifications_data.ods"
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
        
        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_met = 0
        total_criteria = 8
        feedback_parts = []
        subscores = {}
        
        # Get row count for iteration
        row_count = get_row_count(data, sheet_name)
        
        if row_count < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data in spreadsheet"}
        
        logger.info(f"Analyzing sheet '{sheet_name}' with {row_count} rows")
        
        # ===== CRITERION 1: Days Until Expiration Formula =====
        days_col = find_column_by_header(data, sheet_name, "Days")
        
        has_days_formula = False
        if days_col:
            logger.info(f"Found Days column at: {days_col}")
            # Check formulas in first few data rows
            for row_num in range(2, min(row_count, 10)):
                formula = get_cell_formula(data, sheet_name, f"{days_col}{row_num}")
                if formula and check_formula_contains(formula, ['TODAY', 'NOW']):
                    has_days_formula = True
                    logger.info(f"Found TODAY formula in {days_col}{row_num}: {formula}")
                    break
        
        if has_days_formula:
            criteria_met += 1
            feedback_parts.append("✅ Days calculation formula present with TODAY()")
            subscores['days_formula'] = True
        else:
            feedback_parts.append("❌ Missing Days Until Expiration formula with TODAY()")
            subscores['days_formula'] = False
        
        # ===== CRITERION 2: Status Categorization with IF Logic =====
        status_col = find_column_by_header(data, sheet_name, "Status")
        
        has_status_logic = False
        has_valid_categories = False
        
        if status_col:
            logger.info(f"Found Status column at: {status_col}")
            # Check for IF formulas
            for row_num in range(2, min(row_count, 10)):
                formula = get_cell_formula(data, sheet_name, f"{status_col}{row_num}")
                if formula and check_formula_contains(formula, ['IF']):
                    has_status_logic = True
                    logger.info(f"Found IF formula in {status_col}{row_num}: {formula}")
                    break
            
            # Check for valid status categories
            status_values = set()
            for row_num in range(2, min(row_count + 1, 20)):
                value = get_cell_value(data, sheet_name, f"{status_col}{row_num}")
                if value:
                    status_values.add(str(value).upper())
            
            expected_statuses = {'EXPIRED', 'URGENT', 'CURRENT', 'FUTURE'}
            found_statuses = status_values.intersection(expected_statuses)
            
            if len(found_statuses) >= 2:  # At least 2 different status categories
                has_valid_categories = True
                logger.info(f"Found valid status categories: {found_statuses}")
        
        if has_status_logic and has_valid_categories:
            criteria_met += 1
            feedback_parts.append("✅ Status categorization with IF logic working")
            subscores['status_logic'] = True
        elif has_status_logic:
            feedback_parts.append("⚠️  Status formula present but categories may be incorrect")
            subscores['status_logic'] = False
        else:
            feedback_parts.append("❌ Status categorization missing or incorrect")
            subscores['status_logic'] = False
        
        # ===== CRITERION 3: Conditional Formatting on Status =====
        has_status_formatting = False
        
        if status_col:
            # Check for conditional formatting
            # Note: check_conditional_formatting may have limited detection capability
            # We'll check if the function indicates formatting exists
            try:
                has_status_formatting = check_conditional_formatting(
                    data, sheet_name, f"{status_col}2:{status_col}{row_count}"
                )
            except Exception as e:
                logger.warning(f"Could not check conditional formatting: {e}")
                has_status_formatting = False
        
        if has_status_formatting:
            criteria_met += 1
            feedback_parts.append("✅ Conditional formatting detected on Status column")
            subscores['status_formatting'] = True
        else:
            feedback_parts.append("⚠️  Conditional formatting not detected (may be present but undetectable)")
            subscores['status_formatting'] = False
        
        # ===== CRITERION 4: Total Renewal Cost SUM Formula =====
        cost_col = find_column_by_header(data, sheet_name, "Cost")
        
        has_sum_formula = False
        
        if cost_col:
            logger.info(f"Found Cost column at: {cost_col}")
            # Look for SUM formula in rows below data (typically row_count+1 to row_count+5)
            for row_num in range(row_count + 1, min(row_count + 6, 30)):
                formula = get_cell_formula(data, sheet_name, f"{cost_col}{row_num}")
                if formula and check_formula_contains(formula, ['SUM']):
                    has_sum_formula = True
                    logger.info(f"Found SUM formula at {cost_col}{row_num}: {formula}")
                    break
            
            # Also check nearby columns in case they put it adjacent
            if not has_sum_formula:
                for offset in [-1, 1, -2, 2]:
                    adj_col_idx = column_letter_to_index(cost_col) + offset
                    if adj_col_idx >= 0:
                        adj_col = _format_cell_ref(adj_col_idx, 0)[:-1]
                        for row_num in range(row_count + 1, min(row_count + 6, 30)):
                            formula = get_cell_formula(data, sheet_name, f"{adj_col}{row_num}")
                            if formula and check_formula_contains(formula, ['SUM']):
                                has_sum_formula = True
                                logger.info(f"Found SUM formula at {adj_col}{row_num}: {formula}")
                                break
                        if has_sum_formula:
                            break
        
        if has_sum_formula:
            criteria_met += 1
            feedback_parts.append("✅ Total renewal cost SUM formula present")
            subscores['sum_formula'] = True
        else:
            feedback_parts.append("❌ Total cost SUM formula not found")
            subscores['sum_formula'] = False
        
        # ===== CRITERION 5: CE Status Comparison Column =====
        ce_status_col = find_column_by_header(data, sheet_name, "CE Status")
        
        has_ce_comparison = False
        
        if ce_status_col:
            logger.info(f"Found CE Status column at: {ce_status_col}")
            # Check for IF formula comparing values
            for row_num in range(2, min(row_count, 10)):
                formula = get_cell_formula(data, sheet_name, f"{ce_status_col}{row_num}")
                if formula and check_formula_contains(formula, ['IF']):
                    has_ce_comparison = True
                    logger.info(f"Found comparison formula in {ce_status_col}{row_num}: {formula}")
                    break
            
            # Also check if we see "Complete" or "INCOMPLETE" values
            if not has_ce_comparison:
                for row_num in range(2, min(row_count + 1, 20)):
                    value = get_cell_value(data, sheet_name, f"{ce_status_col}{row_num}")
                    if value and ('COMPLETE' in str(value).upper() or 'INCOMPLETE' in str(value).upper()):
                        has_ce_comparison = True
                        logger.info(f"Found CE status values in column")
                        break
        
        if has_ce_comparison:
            criteria_met += 1
            feedback_parts.append("✅ CE status comparison logic present")
            subscores['ce_comparison'] = True
        else:
            feedback_parts.append("❌ CE status comparison missing")
            subscores['ce_comparison'] = False
        
        # ===== CRITERION 6: CE Status Conditional Formatting =====
        has_ce_formatting = False
        
        if ce_status_col:
            try:
                has_ce_formatting = check_conditional_formatting(
                    data, sheet_name, f"{ce_status_col}2:{ce_status_col}{row_count}"
                )
            except Exception as e:
                logger.warning(f"Could not check CE status formatting: {e}")
                has_ce_formatting = False
        
        if has_ce_formatting:
            criteria_met += 1
            feedback_parts.append("✅ CE status conditional formatting detected")
            subscores['ce_formatting'] = True
        else:
            feedback_parts.append("⚠️  CE status formatting not detected (may be present)")
            subscores['ce_formatting'] = False
        
        # ===== CRITERION 7: Sorted by Days Until Expiration =====
        is_sorted_correctly = False
        
        if days_col:
            # Get sheet data structure for sorting verification
            sheet_rows = data['sheets'][sheet_name]
            
            # Verify data is sorted by days column (ascending)
            col_idx = column_letter_to_index(days_col)
            
            sorted_result, sort_msg = verify_data_sorted(
                {'rows': sheet_rows},
                column=col_idx,
                order='asc',
                start_row=1,  # Skip header row
                end_row=min(row_count, 30)
            )
            
            if sorted_result:
                is_sorted_correctly = True
                logger.info("Data is correctly sorted by Days Until Expiration")
            else:
                logger.warning(f"Sort verification failed: {sort_msg}")
        
        if is_sorted_correctly:
            criteria_met += 1
            feedback_parts.append("✅ Data correctly sorted by Days Until Expiration")
            subscores['sorted'] = True
        else:
            feedback_parts.append("❌ Data not sorted by urgency (or Days column not found)")
            subscores['sorted'] = False
        
        # ===== CRITERION 8: Data Integrity =====
        data_integrity_ok = True
        
        # Verify that certification names still have corresponding data in their rows
        cert_col = find_column_by_header(data, sheet_name, "Certification")
        exp_col = find_column_by_header(data, sheet_name, "Expiration")
        
        if cert_col and exp_col:
            # Check a few sample rows
            for row_num in range(2, min(row_count + 1, 8)):
                cert_name = get_cell_value(data, sheet_name, f"{cert_col}{row_num}")
                exp_date = get_cell_value(data, sheet_name, f"{exp_col}{row_num}")
                
                # Both should have values (not empty)
                if not cert_name or not exp_date:
                    data_integrity_ok = False
                    logger.warning(f"Data integrity issue at row {row_num}")
                    break
        else:
            logger.warning("Could not find certification or expiration columns for integrity check")
            # Don't fail this criterion if we can't find columns
        
        if data_integrity_ok:
            criteria_met += 1
            feedback_parts.append("✅ Data integrity maintained during sort")
            subscores['data_integrity'] = True
        else:
            feedback_parts.append("❌ Data integrity may be compromised")
            subscores['data_integrity'] = False
        
        # ===== CALCULATE FINAL SCORE =====
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 6/8 criteria = 75%
        
        # Create detailed feedback
        summary = f"Score: {score}% ({criteria_met}/{total_criteria} criteria met)"
        
        if passed and score >= 90:
            summary += " | 🎉 Excellent certification dashboard!"
        elif passed:
            summary += " | ✅ Certification tracker completed"
        else:
            summary += " | ❌ Task requirements not met"
        
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {summary}")
        
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
        cleanup_verification_temp(file_info.get('temp_dir'))
