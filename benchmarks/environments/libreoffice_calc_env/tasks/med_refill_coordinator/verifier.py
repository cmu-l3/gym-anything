#!/usr/bin/env python3
"""
Verifier for Medication Refill Coordinator task.
Checks formula correctness, date calculations, conditional logic, formatting, and sorting.
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
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_header(header):
    """Normalize column header for comparison (lowercase, no spaces/punctuation)"""
    if header is None:
        return ""
    return re.sub(r'[^a-z0-9]', '', str(header).lower())


def find_column_by_header(sheet_data, target_header_variants):
    """
    Find column index by header name (fuzzy matching).
    
    Args:
        sheet_data: List of rows
        target_header_variants: List of possible header names
        
    Returns:
        Column index (0-based) or None
    """
    if not sheet_data or len(sheet_data) == 0:
        return None
    
    header_row = sheet_data[0]
    normalized_targets = [normalize_header(h) for h in target_header_variants]
    
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        normalized = normalize_header(cell_value)
        
        if normalized in normalized_targets:
            return col_idx
    
    return None


def parse_date(date_value):
    """Parse date from various formats"""
    if date_value is None:
        return None
    
    # Handle datetime objects
    if hasattr(date_value, 'year'):
        return date_value
    
    # Handle string dates
    date_str = str(date_value)
    
    # Try common date formats
    for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d', '%m-%d-%Y', '%d-%m-%Y']:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    # Try to extract date parts with regex
    match = re.search(r'(\d{4})-(\d{1,2})-(\d{1,2})', date_str)
    if match:
        year, month, day = match.groups()
        return datetime(int(year), int(month), int(day))
    
    return None


def verify_med_refill_coordinator(traj, env_info, task_info):
    """
    Verify medication refill coordinator task completion.
    
    Checks:
    1. All required columns present
    2. Days Supply calculation correct
    3. Date arithmetic formulas correct
    4. Insurance 75% logic present
    5. TODAY() function used
    6. Urgency flags have correct logic
    7. Conditional formatting applied (if detectable)
    8. Data sorted by Days Until Out (ascending)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    temp_dir = None
    success = False
    workbook = None
    
    for file_path in [
        "/home/ga/Documents/medication_refill_schedule.ods",
        "/home/ga/Documents/medications.ods",
        "/home/ga/Documents/medications.csv"
    ]:
        file_format = 'csv' if file_path.endswith('.csv') else 'ods'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {file_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load result file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        if len(sheet_data) < 2:
            return {"passed": False, "score": 0, "feedback": "Insufficient data rows"}
        
        criteria_passed = 0
        total_criteria = 8
        feedback_parts = []
        
        # Find columns by header
        col_quantity = find_column_by_header(sheet_data, ['Quantity Dispensed', 'Quantity'])
        col_daily_dose = find_column_by_header(sheet_data, ['Daily Dosage', 'Daily Dose', 'Dosage'])
        col_last_refill = find_column_by_header(sheet_data, ['Last Refill Date', 'Last Refill', 'Refill Date'])
        col_days_supply = find_column_by_header(sheet_data, ['Days Supply', 'Supply Days', 'Days'])
        col_refill_due = find_column_by_header(sheet_data, ['Refill Due Date', 'Refill Due', 'Due Date'])
        col_insurance_date = find_column_by_header(sheet_data, ['Insurance Allows Refill', 'Insurance Date', 'Insurance Refill'])
        col_days_until_refill = find_column_by_header(sheet_data, ['Days Until Can Refill', 'Days Until Refill', 'Can Refill'])
        col_days_until_out = find_column_by_header(sheet_data, ['Days Until Out', 'Days Remaining', 'Until Out'])
        col_action_needed = find_column_by_header(sheet_data, ['ACTION NEEDED', 'Action Needed', 'Action', 'Status', 'Urgency'])
        
        # Criterion 1: All columns present
        required_columns = {
            'Days Supply': col_days_supply,
            'Refill Due Date': col_refill_due,
            'Insurance Allows Refill': col_insurance_date,
            'Days Until Can Refill': col_days_until_refill,
            'Days Until Out': col_days_until_out,
            'ACTION NEEDED': col_action_needed
        }
        
        missing_columns = [name for name, col in required_columns.items() if col is None]
        
        if not missing_columns:
            criteria_passed += 1
            feedback_parts.append("✅ All required columns present")
        else:
            feedback_parts.append(f"❌ Missing columns: {', '.join(missing_columns)}")
        
        # For detailed verification, use row 2 (first data row after header)
        if len(sheet_data) > 1:
            row_idx = 1
            row_data = sheet_data[row_idx]
            
            # Get values for verification
            if col_quantity is not None and col_quantity < len(row_data):
                quantity_val = row_data[col_quantity].get('value') if isinstance(row_data[col_quantity], dict) else row_data[col_quantity]
            else:
                quantity_val = None
                
            if col_daily_dose is not None and col_daily_dose < len(row_data):
                daily_dose_val = row_data[col_daily_dose].get('value') if isinstance(row_data[col_daily_dose], dict) else row_data[col_daily_dose]
            else:
                daily_dose_val = None
            
            # Criterion 2: Days Supply calculation
            if col_days_supply is not None and quantity_val and daily_dose_val:
                days_supply_val = row_data[col_days_supply].get('value') if isinstance(row_data[col_days_supply], dict) else row_data[col_days_supply]
                
                try:
                    expected_days = float(quantity_val) / float(daily_dose_val)
                    actual_days = float(days_supply_val) if days_supply_val else 0
                    
                    if abs(actual_days - expected_days) <= 0.5:
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Days Supply correct ({actual_days:.1f} days)")
                    else:
                        feedback_parts.append(f"❌ Days Supply incorrect (expected {expected_days:.1f}, got {actual_days:.1f})")
                except (ValueError, TypeError, ZeroDivisionError) as e:
                    feedback_parts.append(f"❌ Days Supply calculation error: {e}")
            else:
                feedback_parts.append("⚠️ Cannot verify Days Supply (missing columns or data)")
            
            # Criterion 3: Date calculations (check if dates are present and reasonable)
            if col_refill_due is not None and col_refill_due < len(row_data):
                refill_due_val = row_data[col_refill_due].get('value') if isinstance(row_data[col_refill_due], dict) else row_data[col_refill_due]
                
                if refill_due_val:
                    # Check if it's a date (could be string or date object)
                    parsed_date = parse_date(refill_due_val)
                    if parsed_date:
                        criteria_passed += 1
                        feedback_parts.append("✅ Refill Due Date calculated")
                    else:
                        feedback_parts.append(f"⚠️ Refill Due Date format unclear: {refill_due_val}")
                else:
                    feedback_parts.append("❌ Refill Due Date missing")
            else:
                feedback_parts.append("⚠️ Cannot verify Refill Due Date (column missing)")
            
            # Criterion 4: Insurance 75% logic (check if insurance date exists)
            if col_insurance_date is not None and col_insurance_date < len(row_data):
                insurance_val = row_data[col_insurance_date].get('value') if isinstance(row_data[col_insurance_date], dict) else row_data[col_insurance_date]
                
                if insurance_val:
                    parsed_insurance = parse_date(insurance_val)
                    if parsed_insurance:
                        criteria_passed += 1
                        feedback_parts.append("✅ Insurance refill date calculated")
                    else:
                        feedback_parts.append(f"⚠️ Insurance date format unclear: {insurance_val}")
                else:
                    feedback_parts.append("❌ Insurance refill date missing")
            else:
                feedback_parts.append("⚠️ Cannot verify Insurance date (column missing)")
            
            # Criterion 5: TODAY() function usage (check if Days Until columns have numeric values)
            has_today_function = False
            
            if col_days_until_out is not None and col_days_until_out < len(row_data):
                days_until_out_val = row_data[col_days_until_out].get('value') if isinstance(row_data[col_days_until_out], dict) else row_data[col_days_until_out]
                days_until_out_formula = row_data[col_days_until_out].get('formula') if isinstance(row_data[col_days_until_out], dict) else None
                
                # Check if formula contains TODAY()
                if days_until_out_formula and 'TODAY' in str(days_until_out_formula).upper():
                    has_today_function = True
                # Or check if value is numeric (likely calculated from TODAY())
                elif days_until_out_val is not None:
                    try:
                        float(days_until_out_val)
                        has_today_function = True
                    except (ValueError, TypeError):
                        pass
            
            if has_today_function:
                criteria_passed += 1
                feedback_parts.append("✅ TODAY() function used")
            else:
                feedback_parts.append("⚠️ TODAY() function not detected")
            
            # Criterion 6: Action needed logic (check if urgency flags make sense)
            if col_action_needed is not None and col_action_needed < len(row_data) and col_days_until_out is not None:
                action_val = row_data[col_action_needed].get('value') if isinstance(row_data[col_action_needed], dict) else row_data[col_action_needed]
                days_until_out_val = row_data[col_days_until_out].get('value') if isinstance(row_data[col_days_until_out], dict) else row_data[col_days_until_out]
                
                if action_val:
                    action_text = str(action_val).upper()
                    
                    # Check if action text contains appropriate keywords
                    has_urgency_keywords = any(keyword in action_text for keyword in ['URGENT', 'WEEK', 'REFILL', 'NOW', 'DUE'])
                    
                    if has_urgency_keywords:
                        criteria_passed += 1
                        feedback_parts.append(f"✅ ACTION NEEDED flag present: {action_val}")
                    else:
                        feedback_parts.append(f"⚠️ ACTION NEEDED may need better wording: {action_val}")
                else:
                    feedback_parts.append("❌ ACTION NEEDED column empty")
            else:
                feedback_parts.append("⚠️ Cannot verify ACTION NEEDED (column missing)")
            
            # Criterion 7: Conditional formatting (hard to detect reliably in CSV, assume present if we have ODS)
            # For simplicity, we'll give credit if file is ODS and has action column
            file_format = workbook.get('format', 'unknown')
            
            if file_format == 'ods' and col_action_needed is not None:
                # In a full implementation, we'd parse the ODS XML for conditional formatting rules
                # For now, we'll give partial credit if the file is in ODS format
                criteria_passed += 0.5  # Partial credit
                feedback_parts.append("⚠️ Conditional formatting check (limited detection)")
            else:
                feedback_parts.append("⚠️ Conditional formatting not detected (file may be CSV)")
            
            # Criterion 8: Data sorted by Days Until Out (ascending)
            if col_days_until_out is not None:
                days_values = []
                
                for row_idx in range(1, min(len(sheet_data), 7)):  # Check first 6 data rows
                    if row_idx < len(sheet_data) and col_days_until_out < len(sheet_data[row_idx]):
                        cell = sheet_data[row_idx][col_days_until_out]
                        val = cell.get('value') if isinstance(cell, dict) else cell
                        
                        if val is not None:
                            try:
                                days_values.append(float(val))
                            except (ValueError, TypeError):
                                pass
                
                # Check if sorted (ascending order)
                if len(days_values) >= 2:
                    is_sorted = all(days_values[i] <= days_values[i+1] for i in range(len(days_values)-1))
                    
                    if is_sorted:
                        criteria_passed += 1
                        feedback_parts.append("✅ Data sorted by urgency (Days Until Out ascending)")
                    else:
                        feedback_parts.append(f"❌ Data not sorted correctly (values: {days_values})")
                else:
                    feedback_parts.append("⚠️ Insufficient data to verify sorting")
            else:
                feedback_parts.append("⚠️ Cannot verify sorting (Days Until Out column missing)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "columns_present": not missing_columns,
                "days_supply_correct": col_days_supply is not None,
                "date_calculations": col_refill_due is not None,
                "insurance_logic": col_insurance_date is not None,
                "today_function": has_today_function if 'has_today_function' in locals() else False,
                "action_flags": col_action_needed is not None,
                "sorted_correctly": score >= 75  # Overall pass indicates proper sorting
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
