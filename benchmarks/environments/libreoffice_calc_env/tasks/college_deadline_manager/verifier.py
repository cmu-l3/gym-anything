#!/usr/bin/env python3
"""
Verifier for College Deadline Manager task.

Checks:
1. Dates are standardized (proper date types, not text)
2. "Days Until Deadline" column exists with formulas
3. Data is sorted by urgency (ascending)
4. Conditional formatting is applied to urgent deadlines
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
from datetime import datetime, date

# Use relative path to utils folder (runs on host, not in container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_dates_standardized(sheet_data, deadline_col_idx):
    """
    Check that all deadline cells contain proper date types, not text strings.
    
    LibreOffice stores dates as float values (days since epoch).
    Text dates will have type 'string' and string values.
    
    Returns: (is_standardized, date_count, text_count, details)
    """
    date_count = 0
    text_count = 0
    mixed_count = 0
    details = []
    
    rows = sheet_data.get('rows', [])
    
    # Skip header row (index 0)
    for row_idx, row in enumerate(rows[1:], start=2):
        if deadline_col_idx >= len(row):
            continue
            
        cell = row[deadline_col_idx]
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        cell_type = cell.get('type', '') if isinstance(cell, dict) else ''
        
        if cell_value is None or cell_value == '':
            continue
        
        # LibreOffice stores dates as float values
        # Check if it's a numeric type (date) vs string type (text)
        if isinstance(cell_value, (int, float)):
            date_count += 1
            details.append(f"Row {row_idx}: Date value (numeric: {cell_value})")
        elif cell_type in ['float', 'date', 'percentage']:
            date_count += 1
            details.append(f"Row {row_idx}: Date type ({cell_type})")
        elif isinstance(cell_value, str):
            # Check if it looks like a date string
            if any(sep in cell_value for sep in ['/', '-']) or any(month in cell_value for month in ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December']):
                text_count += 1
                details.append(f"Row {row_idx}: Text date string ('{cell_value}')")
            else:
                mixed_count += 1
                details.append(f"Row {row_idx}: Unknown string ('{cell_value}')")
        else:
            mixed_count += 1
            details.append(f"Row {row_idx}: Unknown type ({type(cell_value).__name__})")
    
    is_standardized = (date_count > 0) and (text_count == 0)
    
    logger.info(f"Date standardization check: {date_count} dates, {text_count} text strings, {mixed_count} unknown")
    for detail in details[:10]:  # Log first 10
        logger.debug(detail)
    
    return is_standardized, date_count, text_count, details


def check_urgency_formulas(sheet_data, urgency_col_idx):
    """
    Check that "Days Until Deadline" column contains formulas with TODAY() or date arithmetic.
    
    Returns: (has_formulas, formula_count, details)
    """
    formula_count = 0
    value_only_count = 0
    details = []
    
    rows = sheet_data.get('rows', [])
    
    # Skip header row
    for row_idx, row in enumerate(rows[1:], start=2):
        if urgency_col_idx >= len(row):
            continue
            
        cell = row[urgency_col_idx]
        cell_formula = cell.get('formula') if isinstance(cell, dict) else None
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        
        if cell_value is None or cell_value == '':
            continue
        
        if cell_formula:
            # Check if formula contains TODAY() or date arithmetic
            formula_upper = cell_formula.upper()
            if 'TODAY' in formula_upper or 'NOW' in formula_upper or '-' in cell_formula:
                formula_count += 1
                details.append(f"Row {row_idx}: Formula found ('{cell_formula}')")
            else:
                details.append(f"Row {row_idx}: Formula without date logic ('{cell_formula}')")
        else:
            value_only_count += 1
            details.append(f"Row {row_idx}: Value only (no formula): {cell_value}")
    
    has_formulas = formula_count > 0 and value_only_count == 0
    
    logger.info(f"Formula check: {formula_count} formulas, {value_only_count} hardcoded values")
    for detail in details[:10]:
        logger.debug(detail)
    
    return has_formulas, formula_count, details


def check_sorted_by_urgency(sheet_data, urgency_col_idx):
    """
    Verify data is sorted by urgency column in ascending order (most urgent first).
    
    Returns: (is_sorted, values_list)
    """
    values = []
    rows = sheet_data.get('rows', [])
    
    # Skip header row
    for row_idx, row in enumerate(rows[1:], start=2):
        if urgency_col_idx >= len(row):
            continue
            
        cell = row[urgency_col_idx]
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        
        if cell_value is not None and cell_value != '':
            try:
                numeric_value = float(cell_value)
                values.append((row_idx, numeric_value))
            except (ValueError, TypeError):
                logger.warning(f"Row {row_idx}: Non-numeric urgency value: {cell_value}")
    
    # Check if sorted ascending (smallest first = most urgent)
    if len(values) < 2:
        return True, values  # Too few values to determine
    
    is_sorted = all(values[i][1] <= values[i+1][1] for i in range(len(values)-1))
    
    logger.info(f"Sort check: {len(values)} urgency values, sorted={is_sorted}")
    logger.debug(f"Urgency values: {[v[1] for v in values[:5]]}")
    
    return is_sorted, values


def check_conditional_formatting(filepath, sheet_name):
    """
    Check if conditional formatting rules exist in the ODS file.
    
    This is a heuristic check - we look for conditional formatting XML elements.
    
    Returns: (has_conditional_format, details)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            if 'content.xml' not in ods_zip.namelist():
                return False, "content.xml not found"
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting elements
            # In ODF, these are in calcext:conditional-formats or style:map
            namespaces = {
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'
            }
            
            # Look for conditional formatting
            conditional_formats = root.findall('.//calcext:conditional-formats', namespaces)
            style_maps = root.findall('.//style:map', namespaces)
            
            has_cf = len(conditional_formats) > 0 or len(style_maps) > 0
            
            details = f"Found {len(conditional_formats)} conditional format blocks, {len(style_maps)} style maps"
            
            logger.info(f"Conditional formatting check: {details}")
            
            return has_cf, details
    
    except Exception as e:
        logger.error(f"Error checking conditional formatting: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def find_urgency_column(sheet_data):
    """
    Find the column that likely contains "Days Until Deadline" data.
    
    Strategy:
    1. Look for header containing "days" and "deadline"
    2. Look for column with numeric values (likely calculated days)
    3. Return column index or None
    """
    rows = sheet_data.get('rows', [])
    
    if not rows:
        return None
    
    # Check header row for "Days Until Deadline" or similar
    header_row = rows[0]
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value and isinstance(cell_value, str):
            value_lower = cell_value.lower()
            if 'days' in value_lower and ('deadline' in value_lower or 'until' in value_lower):
                logger.info(f"Found urgency column by header at index {col_idx}: '{cell_value}'")
                return col_idx
    
    # Fallback: look for column D (index 3) which should be after Deadline column C
    # Check if it has numeric values
    if len(header_row) > 3:
        col_idx = 3
        has_numeric = False
        for row in rows[1:6]:  # Check first few data rows
            if col_idx < len(row):
                cell = row[col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                if isinstance(cell_value, (int, float)):
                    has_numeric = True
                    break
        
        if has_numeric:
            logger.info(f"Found urgency column by position at index {col_idx}")
            return col_idx
    
    # Another fallback: find first column after "Deadline" that has formulas
    deadline_col_idx = None
    for col_idx, cell in enumerate(header_row):
        cell_value = cell.get('value') if isinstance(cell, dict) else cell
        if cell_value and isinstance(cell_value, str) and 'deadline' in cell_value.lower():
            deadline_col_idx = col_idx
            break
    
    if deadline_col_idx is not None and deadline_col_idx + 1 < len(header_row):
        next_col_idx = deadline_col_idx + 1
        # Check if this column has formulas
        for row in rows[1:3]:
            if next_col_idx < len(row):
                cell = row[next_col_idx]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula:
                    logger.info(f"Found urgency column by formula at index {next_col_idx}")
                    return next_col_idx
    
    logger.warning("Could not find urgency column")
    return None


def verify_college_deadline_manager(traj, env_info, task_info):
    """
    Verify college deadline manager task completion.
    
    Criteria:
    1. Dates standardized (proper date types in Deadline column)
    2. Formulas correct (Days Until Deadline column with formulas)
    3. Sorted by urgency (ascending order)
    4. Conditional formatting applied
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup verification
    container_path = "/home/ga/Documents/college_deadlines.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = get_sheet_names(sheet_data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheets = sheet_data.get('sheets', {})
        sheet_rows_data = sheets.get(sheet_name, [])
        
        # Build a structured sheet_data dict for helper functions
        structured_sheet = {'rows': sheet_rows_data}
        
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        subscores = {}
        
        # --- Criterion 1: Dates Standardized ---
        deadline_col_idx = 2  # Column C (0-indexed)
        
        is_standardized, date_count, text_count, date_details = check_dates_standardized(
            structured_sheet, deadline_col_idx
        )
        
        if is_standardized and date_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Dates standardized ({date_count} proper dates)")
            subscores['dates_standardized'] = True
        else:
            feedback_parts.append(f"❌ Dates not standardized ({date_count} dates, {text_count} text strings)")
            subscores['dates_standardized'] = False
        
        # --- Criterion 2: Urgency Formulas ---
        urgency_col_idx = find_urgency_column(structured_sheet)
        
        if urgency_col_idx is not None:
            has_formulas, formula_count, formula_details = check_urgency_formulas(
                structured_sheet, urgency_col_idx
            )
            
            if has_formulas and formula_count >= 5:
                criteria_passed += 1
                feedback_parts.append(f"✅ Formulas correct ({formula_count} date formulas)")
                subscores['formulas_correct'] = True
            else:
                feedback_parts.append(f"❌ Formulas missing or incorrect ({formula_count} formulas found)")
                subscores['formulas_correct'] = False
        else:
            feedback_parts.append("❌ 'Days Until Deadline' column not found")
            subscores['formulas_correct'] = False
        
        # --- Criterion 3: Sorted by Urgency ---
        if urgency_col_idx is not None:
            is_sorted, urgency_values = check_sorted_by_urgency(
                structured_sheet, urgency_col_idx
            )
            
            if is_sorted and len(urgency_values) >= 5:
                criteria_passed += 1
                feedback_parts.append(f"✅ Sorted by urgency ({len(urgency_values)} rows in order)")
                subscores['sorted_correctly'] = True
            else:
                feedback_parts.append(f"❌ Not sorted by urgency (found {len(urgency_values)} values)")
                subscores['sorted_correctly'] = False
        else:
            feedback_parts.append("❌ Cannot verify sorting (urgency column not found)")
            subscores['sorted_correctly'] = False
        
        # --- Criterion 4: Conditional Formatting ---
        has_cf, cf_details = check_conditional_formatting(
            file_info['file_path'], sheet_name
        )
        
        if has_cf:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied")
            subscores['conditional_formatting'] = True
        else:
            feedback_parts.append("❌ Conditional formatting not detected")
            subscores['conditional_formatting'] = False
        
        # --- Calculate Score ---
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎓 Excellent work! Deadline tracker is well-organized.")
        elif passed:
            feedback_parts.insert(0, "✅ Good job! Most requirements met.")
        else:
            feedback_parts.insert(0, "❌ Task incomplete. More work needed.")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "dates_standardized": f"{date_count} dates, {text_count} text",
                "formulas_found": formula_count if urgency_col_idx else 0,
                "sort_verified": is_sorted if urgency_col_idx else False,
                "conditional_formatting": has_cf
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
        cleanup_verification_temp(file_info.get('temp_dir'))
