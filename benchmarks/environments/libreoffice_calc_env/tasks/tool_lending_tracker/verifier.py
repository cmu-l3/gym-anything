#!/usr/bin/env python3
"""
Verifier for Tool Lending Tracker task.

Checks:
1. Days Out column with TODAY()-DateLent formula
2. Status column with IF formula (>30 days = OVERDUE)
3. Correct calculations (at least one OVERDUE item)
4. Conditional formatting applied to Status column
5. Formula propagation to all data rows
"""

import sys
import os
import logging
import re
import zipfile
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

# Add utils to path - use relative path for host machine verification
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


def check_ods_conditional_formatting(filepath, sheet_name=None):
    """
    Check if conditional formatting exists in ODS file.
    
    This is a simplified check that looks for style:map elements
    in the content.xml which indicate conditional formatting rules.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for style:map elements which indicate conditional formatting
            # Namespace for style
            style_ns = '{urn:oasis:names:tc:opendocument:xmlns:style:1.0}'
            
            # Search for style:map elements in the document
            maps = root.findall(f'.//{style_ns}map')
            
            # If we find any style maps, likely conditional formatting exists
            if len(maps) > 0:
                logger.info(f"Found {len(maps)} conditional formatting rules in ODS")
                return True
            
            return False
            
    except Exception as e:
        logger.debug(f"Could not check ODS conditional formatting: {e}")
        return False


def normalize_formula(formula):
    """Normalize formula for comparison by removing spaces and converting to uppercase."""
    if not formula:
        return ""
    return formula.replace(' ', '').upper()


def verify_days_out_formula(formula, date_lent_col='C', row_num=2):
    """
    Verify that formula calculates TODAY() - Date Lent.
    
    Accepts various valid formats:
    - =TODAY()-C2
    - =TODAY()-$C$2
    - =TODAY()-C2
    """
    if not formula:
        return False
    
    normalized = normalize_formula(formula)
    
    # Check for TODAY() function
    if 'TODAY()' not in normalized:
        return False
    
    # Check for subtraction
    if '-' not in normalized:
        return False
    
    # Check for reference to date column (C)
    if f'{date_lent_col}' not in normalized:
        return False
    
    # Should be a subtraction formula
    return True


def verify_status_formula(formula, days_col='E', row_num=2):
    """
    Verify that formula is IF statement with >30 threshold.
    
    Accepts formats like:
    - =IF(E2>30,"OVERDUE","OK")
    - =IF(E2>30;"OVERDUE";"OK")  (European format)
    - =IF($E$2>30,"OVERDUE","OK")
    """
    if not formula:
        return False
    
    normalized = normalize_formula(formula)
    
    # Check for IF function
    if 'IF(' not in normalized:
        return False
    
    # Check for >30 threshold
    if '>30' not in normalized:
        return False
    
    # Check for OVERDUE and OK
    if 'OVERDUE' not in normalized or 'OK' not in normalized:
        return False
    
    # Check for reference to days column
    if f'{days_col}' not in normalized:
        return False
    
    return True


def verify_calculation_accuracy(workbook, sheet_name, date_lent_col='C', days_out_col='E', status_col='F'):
    """
    Verify that calculated values are correct.
    Returns (is_accurate, has_overdue, details)
    """
    try:
        today = datetime.now().date()
        rows_checked = 0
        accurate_count = 0
        overdue_count = 0
        calculation_errors = []
        
        # Check rows 2 through 10 (assuming header in row 1)
        for row_idx in range(2, 11):
            cell_ref_date = f"{date_lent_col}{row_idx}"
            cell_ref_days = f"{days_out_col}{row_idx}"
            cell_ref_status = f"{status_col}{row_idx}"
            
            date_lent = get_cell_value(workbook, sheet_name, cell_ref_date)
            days_out = get_cell_value(workbook, sheet_name, cell_ref_days)
            status = get_cell_value(workbook, sheet_name, cell_ref_status)
            
            # Skip empty rows
            if not date_lent:
                continue
            
            rows_checked += 1
            
            # Parse date
            try:
                if isinstance(date_lent, str):
                    lent_date = datetime.strptime(date_lent, '%Y-%m-%d').date()
                elif isinstance(date_lent, datetime):
                    lent_date = date_lent.date()
                else:
                    lent_date = date_lent
                
                # Calculate expected days out
                expected_days = (today - lent_date).days
                
                # Check days out is approximately correct (within 1 day for timezone tolerance)
                if days_out is not None:
                    actual_days = int(float(days_out))
                    if abs(actual_days - expected_days) <= 1:
                        accurate_count += 1
                        
                        # Check status matches
                        expected_status = "OVERDUE" if actual_days > 30 else "OK"
                        if status == expected_status:
                            if status == "OVERDUE":
                                overdue_count += 1
                        else:
                            calculation_errors.append(f"Row {row_idx}: status mismatch (expected {expected_status}, got {status})")
                    else:
                        calculation_errors.append(f"Row {row_idx}: days out mismatch (expected ~{expected_days}, got {actual_days})")
                
            except Exception as e:
                logger.debug(f"Could not parse date in row {row_idx}: {e}")
                continue
        
        is_accurate = rows_checked > 0 and accurate_count >= rows_checked * 0.8
        has_overdue = overdue_count > 0
        
        return is_accurate, has_overdue, calculation_errors
        
    except Exception as e:
        logger.error(f"Error verifying calculations: {e}")
        return False, False, [str(e)]


def verify_tool_lending_tracker(traj, env_info, task_info):
    """
    Verify tool lending tracker task completion.
    
    Checks:
    1. Days Out column contains TODAY()-DateLent formula
    2. Status column contains IF(days>30,"OVERDUE","OK") formula
    3. Calculations are accurate
    4. At least one OVERDUE item exists
    5. Conditional formatting applied (optional, for bonus points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    file_paths = [
        ("/home/ga/Documents/tool_lending_result.ods", "ods"),
        ("/home/ga/Documents/tool_lending.ods", "ods"),
        ("/home/ga/Documents/tool_lending.csv", "csv"),
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
            filepath = workbook.get('filepath', '')
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not load tool lending file. Ensure file is saved."
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Determine column letters by checking headers
        # Assume: A=Tool, B=Borrower, C=DateLent, D=ExpectedReturn, E=Value or DaysOut, F=Status
        # We need to find "Days Out" and "Status" columns
        
        # Check row 1 for headers
        days_out_col = None
        status_col = None
        date_lent_col = 'C'  # Assumed from CSV structure
        
        for col_letter in ['E', 'F', 'G']:
            header = get_cell_value(workbook, sheet_name, f'{col_letter}1')
            if header and 'days' in str(header).lower():
                days_out_col = col_letter
            elif header and 'status' in str(header).lower():
                status_col = col_letter
        
        if not days_out_col:
            days_out_col = 'E'  # Default assumption
        if not status_col:
            status_col = 'F'  # Default assumption
        
        logger.info(f"Detected columns - Days Out: {days_out_col}, Status: {status_col}")
        
        # Criterion 1: Days Out formula exists and is correct
        days_formula_count = 0
        days_formula_correct = 0
        
        for row_idx in range(2, 11):  # Check rows 2-10
            formula = get_cell_formula(workbook, sheet_name, f'{days_out_col}{row_idx}')
            value = get_cell_value(workbook, sheet_name, f'{days_out_col}{row_idx}')
            
            if value is None:  # Empty row
                break
            
            days_formula_count += 1
            
            if formula and verify_days_out_formula(formula, date_lent_col, row_idx):
                days_formula_correct += 1
        
        if days_formula_count > 0 and days_formula_correct >= days_formula_count * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Days Out formula correct ({days_formula_correct}/{days_formula_count} rows)")
        else:
            feedback_parts.append(f"❌ Days Out formula missing or incorrect (found {days_formula_correct}/{days_formula_count} correct)")
        
        # Criterion 2: Status formula exists and is correct
        status_formula_count = 0
        status_formula_correct = 0
        
        for row_idx in range(2, 11):
            formula = get_cell_formula(workbook, sheet_name, f'{status_col}{row_idx}')
            value = get_cell_value(workbook, sheet_name, f'{status_col}{row_idx}')
            
            if value is None:
                break
            
            status_formula_count += 1
            
            if formula and verify_status_formula(formula, days_out_col, row_idx):
                status_formula_correct += 1
        
        if status_formula_count > 0 and status_formula_correct >= status_formula_count * 0.8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status formula correct ({status_formula_correct}/{status_formula_count} rows)")
        else:
            feedback_parts.append(f"❌ Status formula missing or incorrect (found {status_formula_correct}/{status_formula_count} correct)")
        
        # Criterion 3: Calculation accuracy
        is_accurate, has_overdue, calc_errors = verify_calculation_accuracy(
            workbook, sheet_name, date_lent_col, days_out_col, status_col
        )
        
        if is_accurate:
            criteria_passed += 1
            feedback_parts.append("✅ Calculations are accurate")
        else:
            feedback_parts.append("❌ Calculation errors detected")
            if calc_errors:
                logger.info(f"Calculation errors: {calc_errors[:3]}")
        
        # Criterion 4: At least one OVERDUE item identified
        if has_overdue:
            criteria_passed += 1
            feedback_parts.append("✅ Overdue items correctly identified")
        else:
            feedback_parts.append("⚠️ No overdue items found (check formulas)")
        
        # Criterion 5: Conditional formatting applied (optional, bonus)
        has_formatting = False
        
        if filepath.endswith('.ods'):
            has_formatting = check_ods_conditional_formatting(filepath, sheet_name)
        elif filepath.endswith('.xlsx'):
            has_formatting = check_conditional_formatting(workbook, sheet_name, f'{status_col}2:{status_col}10')
        
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied")
        else:
            feedback_parts.append("⚠️ Conditional formatting not detected (optional)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent work! Tool lending tracker completed perfectly!")
        elif passed:
            feedback_parts.append("✅ Tool lending tracker task completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "days_out_formula": days_formula_correct >= days_formula_count * 0.8 if days_formula_count > 0 else False,
                "status_formula": status_formula_correct >= status_formula_count * 0.8 if status_formula_count > 0 else False,
                "calculation_accurate": is_accurate,
                "has_overdue": has_overdue,
                "conditional_formatting": has_formatting
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
