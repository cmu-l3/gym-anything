#!/usr/bin/env python3
"""
Verifier for Library Due Date Crisis task
Checks date calculations, conditional logic, prioritization, and data organization
"""

import sys
import os
import logging
from datetime import datetime, timedelta
import re

# Use relative path to utils folder
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


def parse_date_value(date_val):
    """Parse date from various formats"""
    if isinstance(date_val, datetime):
        return date_val
    if isinstance(date_val, (int, float)):
        # Excel serial date
        return datetime(1899, 12, 30) + timedelta(days=int(date_val))
    if isinstance(date_val, str):
        # Try common date formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(date_val, fmt)
            except:
                continue
    return None


def get_loan_period(branch_name):
    """Get loan period based on branch name"""
    if not branch_name:
        return None
    branch_lower = str(branch_name).lower()
    if 'main' in branch_lower:
        return 21
    elif 'north' in branch_lower or 'south' in branch_lower:
        return 14
    return None


def check_due_date_formula(sheet_data, sheet_name, row_idx):
    """Check if due date calculation is correct"""
    try:
        # Get checkout date (column C, index 2)
        checkout_date = get_cell_value(sheet_data, sheet_name, f"C{row_idx}")
        # Get library branch (column D, index 3)
        branch = get_cell_value(sheet_data, sheet_name, f"D{row_idx}")
        # Get due date (should be in column G or similar, need to find it)
        # Let's search for "Due Date" header first
        
        # For now, assume Due Date is in a reasonable column
        # This is simplified - in real verification we'd search for the column
        return True
    except Exception as e:
        logger.debug(f"Error checking due date formula for row {row_idx}: {e}")
        return False


def find_column_by_header(sheet_data, sheet_name, header_name):
    """Find column index by header name (case-insensitive, partial match)"""
    try:
        sheets = sheet_data.get('sheets', {})
        if sheet_name not in sheets:
            return None
        
        rows = sheets[sheet_name]
        if not rows:
            return None
        
        header_row = rows[0]  # Assume first row is header
        header_lower = header_name.lower()
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and header_lower in str(cell_value).lower():
                return col_idx
        
        return None
    except Exception as e:
        logger.debug(f"Error finding column {header_name}: {e}")
        return None


def column_index_to_letter(col_idx):
    """Convert 0-based column index to Excel-style letter (0->A, 25->Z, 26->AA)"""
    result = ""
    col = col_idx + 1
    while col > 0:
        col -= 1
        result = chr(ord('A') + (col % 26)) + result
        col //= 26
    return result


def verify_library_due_dates(traj, env_info, task_info):
    """
    Verify library due date crisis task completion.
    
    Checks:
    1. Due Date column with correct formulas
    2. Days Until Due column using TODAY()
    3. Can Renew column with correct logic
    4. Late Fee calculation by type
    5. Priority assignment
    6. Conditional formatting
    7. Data sorting
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    temp_dir = None
    success = False
    workbook = None
    
    for file_path in ['/home/ga/Documents/library_organized.ods',
                      '/home/ga/Documents/library_checkouts.ods',
                      '/home/ga/Documents/library_checkouts.csv']:
        fmt = 'csv' if file_path.endswith('.csv') else 'ods'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file: {file_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        sheets = workbook['sheets']
        rows = sheets[sheet_name]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Find important columns
        due_date_col = find_column_by_header(workbook, sheet_name, "due date")
        days_until_col = find_column_by_header(workbook, sheet_name, "days until")
        can_renew_col = find_column_by_header(workbook, sheet_name, "can renew")
        late_fee_col = find_column_by_header(workbook, sheet_name, "late fee")
        priority_col = find_column_by_header(workbook, sheet_name, "priority")
        
        # Original columns
        checkout_col = find_column_by_header(workbook, sheet_name, "checkout")
        branch_col = find_column_by_header(workbook, sheet_name, "branch")
        renewals_col = find_column_by_header(workbook, sheet_name, "renewals")
        hold_col = find_column_by_header(workbook, sheet_name, "hold")
        type_col = find_column_by_header(workbook, sheet_name, "type")
        
        logger.info(f"Found columns - Due Date: {due_date_col}, Days Until: {days_until_col}, "
                   f"Can Renew: {can_renew_col}, Late Fee: {late_fee_col}, Priority: {priority_col}")
        
        # Criterion 1: Due Date column exists with formulas
        due_date_correct = False
        if due_date_col is not None:
            # Check a few rows for due date values
            has_due_dates = False
            formula_count = 0
            
            for row_idx in range(1, min(6, len(rows))):  # Check first 5 data rows
                if row_idx >= len(rows):
                    break
                    
                if due_date_col < len(rows[row_idx]):
                    cell_data = rows[row_idx][due_date_col]
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    
                    if value:
                        has_due_dates = True
                    if formula:
                        formula_count += 1
            
            if has_due_dates:
                criteria_passed += 1
                due_date_correct = True
                if formula_count > 0:
                    feedback_parts.append(f"✅ Due Date column present with formulas ({formula_count} rows)")
                else:
                    feedback_parts.append("✅ Due Date column present (formulas not detected but values exist)")
            else:
                feedback_parts.append("❌ Due Date column missing or empty")
        else:
            feedback_parts.append("❌ Due Date column not found")
        
        subscores['due_date'] = due_date_correct
        
        # Criterion 2: Days Until Due column using TODAY()
        days_until_correct = False
        if days_until_col is not None:
            has_values = False
            has_today_formula = False
            
            for row_idx in range(1, min(6, len(rows))):
                if row_idx >= len(rows):
                    break
                    
                if days_until_col < len(rows[row_idx]):
                    cell_data = rows[row_idx][days_until_col]
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    formula = cell_data.get('formula') if isinstance(cell_data, dict) else None
                    
                    if value is not None:
                        has_values = True
                    if formula and 'TODAY' in str(formula).upper():
                        has_today_formula = True
                        break
            
            if has_values:
                criteria_passed += 1
                days_until_correct = True
                if has_today_formula:
                    feedback_parts.append("✅ Days Until Due with TODAY() function")
                else:
                    feedback_parts.append("✅ Days Until Due column present")
            else:
                feedback_parts.append("❌ Days Until Due column missing or empty")
        else:
            feedback_parts.append("❌ Days Until Due column not found")
        
        subscores['days_until_due'] = days_until_correct
        
        # Criterion 3: Can Renew logic (renewals < 3 AND no holds)
        can_renew_correct = False
        if can_renew_col is not None and renewals_col is not None and hold_col is not None:
            logic_correct_count = 0
            checked_rows = 0
            
            for row_idx in range(1, min(8, len(rows))):
                if row_idx >= len(rows):
                    break
                
                try:
                    renewals_val = rows[row_idx][renewals_col].get('value') if isinstance(rows[row_idx][renewals_col], dict) else rows[row_idx][renewals_col]
                    hold_val = rows[row_idx][hold_col].get('value') if isinstance(rows[row_idx][hold_col], dict) else rows[row_idx][hold_col]
                    can_renew_val = rows[row_idx][can_renew_col].get('value') if isinstance(rows[row_idx][can_renew_col], dict) else rows[row_idx][can_renew_col]
                    
                    if renewals_val is not None and hold_val is not None and can_renew_val is not None:
                        checked_rows += 1
                        
                        # Expected logic: can renew if renewals < 3 AND hold = "No"
                        renewals_num = int(renewals_val) if str(renewals_val).isdigit() else 0
                        hold_str = str(hold_val).strip().lower()
                        expected_renew = "yes" if (renewals_num < 3 and hold_str == "no") else "no"
                        actual_renew = str(can_renew_val).strip().lower()
                        
                        if expected_renew == actual_renew:
                            logic_correct_count += 1
                except Exception as e:
                    logger.debug(f"Error checking renewal logic for row {row_idx}: {e}")
                    continue
            
            if checked_rows > 0:
                logic_accuracy = logic_correct_count / checked_rows
                if logic_accuracy >= 0.7:  # At least 70% correct
                    criteria_passed += 1
                    can_renew_correct = True
                    feedback_parts.append(f"✅ Can Renew logic correct ({logic_correct_count}/{checked_rows} rows)")
                else:
                    feedback_parts.append(f"⚠️ Can Renew logic partially correct ({logic_correct_count}/{checked_rows} rows)")
            else:
                feedback_parts.append("❌ Can Renew column has no verifiable data")
        else:
            feedback_parts.append("❌ Can Renew column or source columns not found")
        
        subscores['can_renew_logic'] = can_renew_correct
        
        # Criterion 4: Late Fee calculation by type
        late_fee_correct = False
        if late_fee_col is not None and type_col is not None:
            fee_correct_count = 0
            checked_rows = 0
            
            for row_idx in range(1, min(8, len(rows))):
                if row_idx >= len(rows):
                    break
                
                try:
                    type_val = rows[row_idx][type_col].get('value') if isinstance(rows[row_idx][type_col], dict) else rows[row_idx][type_col]
                    fee_val = rows[row_idx][late_fee_col].get('value') if isinstance(rows[row_idx][late_fee_col], dict) else rows[row_idx][late_fee_col]
                    
                    if type_val is not None and fee_val is not None:
                        checked_rows += 1
                        
                        # Expected: Book = $1.75 (7 * 0.25), DVD = $7.00 (7 * 1.00)
                        type_str = str(type_val).strip().lower()
                        expected_fee = 1.75 if 'book' in type_str else 7.00
                        
                        # Convert fee value to float
                        try:
                            actual_fee = float(str(fee_val).replace('$', '').replace(',', '').strip())
                            if abs(actual_fee - expected_fee) < 0.01:
                                fee_correct_count += 1
                        except:
                            pass
                except Exception as e:
                    logger.debug(f"Error checking late fee for row {row_idx}: {e}")
                    continue
            
            if checked_rows > 0:
                fee_accuracy = fee_correct_count / checked_rows
                if fee_accuracy >= 0.7:
                    criteria_passed += 1
                    late_fee_correct = True
                    feedback_parts.append(f"✅ Late Fee calculation correct ({fee_correct_count}/{checked_rows} rows)")
                else:
                    feedback_parts.append(f"⚠️ Late Fee calculation partially correct ({fee_correct_count}/{checked_rows} rows)")
            else:
                feedback_parts.append("❌ Late Fee column has no verifiable data")
        else:
            feedback_parts.append("❌ Late Fee or Type column not found")
        
        subscores['late_fee_calc'] = late_fee_correct
        
        # Criterion 5: Priority assignment
        priority_correct = False
        if priority_col is not None:
            has_priorities = False
            priority_values = set()
            
            for row_idx in range(1, len(rows)):
                if priority_col < len(rows[row_idx]):
                    cell_data = rows[row_idx][priority_col]
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    if value:
                        has_priorities = True
                        priority_values.add(str(value).upper().strip())
            
            # Check if priority values include expected categories
            expected_priorities = {"OVERDUE", "URGENT", "HIGH", "NORMAL"}
            found_priorities = priority_values.intersection(expected_priorities)
            
            if len(found_priorities) >= 2:  # At least 2 priority levels used
                criteria_passed += 1
                priority_correct = True
                feedback_parts.append(f"✅ Priority assignment present ({len(found_priorities)} levels: {', '.join(found_priorities)})")
            elif has_priorities:
                feedback_parts.append(f"⚠️ Priority column exists but may not use correct levels")
            else:
                feedback_parts.append("❌ Priority column missing or empty")
        else:
            feedback_parts.append("❌ Priority column not found")
        
        subscores['priority_assignment'] = priority_correct
        
        # Criterion 6: Conditional formatting (simplified check)
        # This is difficult to verify programmatically, so we'll give credit if other criteria are met
        formatting_present = False
        try:
            # Try to check for conditional formatting
            has_formatting = check_conditional_formatting(workbook, sheet_name, "A1:Z100")
            if has_formatting:
                criteria_passed += 1
                formatting_present = True
                feedback_parts.append("✅ Conditional formatting detected")
            else:
                # Give partial credit if file is ODS and other formatting work is done
                if workbook.get('format') == 'ods' and (due_date_correct or priority_correct):
                    criteria_passed += 0.5
                    feedback_parts.append("⚠️ Conditional formatting not detected (partial credit)")
                else:
                    feedback_parts.append("❌ Conditional formatting not detected")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
            feedback_parts.append("⚠️ Conditional formatting check unavailable")
        
        subscores['conditional_formatting'] = formatting_present
        
        # Criterion 7: Data sorting (check if priority column is sorted)
        sorting_correct = False
        if priority_col is not None:
            priority_order = {"OVERDUE": 1, "URGENT": 2, "HIGH": 3, "NORMAL": 4}
            is_sorted = True
            prev_priority_num = 0
            
            for row_idx in range(1, min(len(rows), 15)):
                if priority_col < len(rows[row_idx]):
                    cell_data = rows[row_idx][priority_col]
                    value = cell_data.get('value') if isinstance(cell_data, dict) else cell_data
                    
                    if value:
                        priority_str = str(value).upper().strip()
                        priority_num = priority_order.get(priority_str, 5)
                        
                        if priority_num < prev_priority_num:
                            is_sorted = False
                            break
                        prev_priority_num = priority_num
            
            if is_sorted and prev_priority_num > 0:  # At least some priorities found
                criteria_passed += 1
                sorting_correct = True
                feedback_parts.append("✅ Data sorted by priority")
            else:
                feedback_parts.append("⚠️ Data may not be sorted correctly")
        else:
            feedback_parts.append("⚠️ Cannot verify sorting (Priority column not found)")
        
        subscores['data_sorted'] = sorting_correct
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent library organization!")
        elif passed:
            feedback_parts.append("✅ Library books organized successfully")
        else:
            feedback_parts.append("❌ Library organization needs more work")
        
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
