#!/usr/bin/env python3
"""
Verifier for Tool Library Damage Investigation task

Verifies:
1. Date standardization (consistent formats)
2. Missing data inference (return dates filled in logically)
3. Damage period identification (May 15-20, 2024)
4. Cost calculations (sum to $85, proportional allocation)
5. Conditional formatting (highlighting applied)
6. Formula presence (not hardcoded values)
"""

import sys
import os
import logging
import re
from datetime import datetime, date
from typing import Dict, List, Tuple, Any

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    parse_ods_file,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Damage period constants
DAMAGE_START = date(2024, 5, 15)
DAMAGE_END = date(2024, 5, 20)
REPAIR_COST = 85.0


def parse_date_flexible(date_value) -> date:
    """
    Parse various date formats flexibly.
    Handles: "5/3/24", "May 15, 2024", "2024-05-18", "5-22-2024", DATE objects
    """
    if isinstance(date_value, date):
        return date_value
    
    if isinstance(date_value, datetime):
        return date_value.date()
    
    if isinstance(date_value, (int, float)):
        # Excel date serial number (days since 1900-01-01)
        try:
            base_date = date(1899, 12, 30)
            from datetime import timedelta
            return base_date + timedelta(days=int(date_value))
        except:
            return None
    
    if not isinstance(date_value, str):
        return None
    
    date_str = str(date_value).strip()
    
    # Try multiple date formats
    formats = [
        "%Y-%m-%d",      # 2024-05-18
        "%m/%d/%y",      # 5/3/24
        "%m/%d/%Y",      # 5/3/2024
        "%m-%d-%Y",      # 5-22-2024
        "%B %d, %Y",     # May 15, 2024
        "%b %d, %Y",     # May 15, 2024
        "%Y-%m-%d",      # 2024-05-08
        "%d/%m/%Y",      # fallback
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt).date()
        except ValueError:
            continue
    
    return None


def check_date_standardization(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if dates were standardized into consistent format.
    Returns: (success, feedback, count_standardized)
    """
    rows = sheet_data['sheets'][sheet_name]
    
    # Look for columns that might contain standardized dates
    # Check headers in first row
    header_row = rows[0] if rows else []
    
    standardized_count = 0
    total_date_cells = 0
    
    # Check if there are new columns with DATE types
    # Look at rows 2-8 (data rows), check for DATE type cells beyond column E
    for row_idx in range(1, min(9, len(rows))):
        row = rows[row_idx]
        for col_idx in range(5, min(15, len(row))):  # Check columns F onwards
            cell = row[col_idx]
            if isinstance(cell, dict):
                cell_value = cell.get('value')
                cell_type = cell.get('type', '')
                
                # Check if it's a date type or parseable date
                if cell_value:
                    total_date_cells += 1
                    parsed = parse_date_flexible(cell_value)
                    if parsed and parsed.year == 2024:
                        standardized_count += 1
    
    success = standardized_count >= 6  # At least 6 standardized dates (3 rows × 2 dates)
    
    if success:
        feedback = f"✅ Dates standardized ({standardized_count} date cells found)"
    else:
        feedback = f"❌ Insufficient date standardization ({standardized_count} dates, expected 6+)"
    
    return success, feedback, standardized_count


def check_missing_data_inference(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str]:
    """
    Check if missing return dates were logically inferred.
    Specifically check if Mike Roberts' missing return date was filled in.
    """
    rows = sheet_data['sheets'][sheet_name]
    
    # Find Mike Roberts row (should be row 3, index 3)
    mike_row_idx = None
    for idx, row in enumerate(rows[1:], start=1):  # Skip header
        if len(row) > 0:
            borrower_cell = row[0]
            borrower = borrower_cell.get('value') if isinstance(borrower_cell, dict) else borrower_cell
            if borrower and 'Mike' in str(borrower):
                mike_row_idx = idx
                break
    
    if mike_row_idx is None:
        return False, "❌ Could not find Mike Roberts row"
    
    # Check if return date was inferred (original was blank)
    # Look in column D (index 3) and any new standardized columns
    mike_row = rows[mike_row_idx]
    
    # Check original return date column (D, index 3)
    original_return = None
    if len(mike_row) > 3:
        cell = mike_row[3]
        original_return = cell.get('value') if isinstance(cell, dict) else cell
    
    # Check for inferred dates in columns beyond original (F onwards)
    inferred_found = False
    for col_idx in range(5, min(15, len(mike_row))):
        cell = mike_row[col_idx]
        if isinstance(cell, dict):
            value = cell.get('value')
            formula = cell.get('formula')
            
            # Check if there's a formula (inference logic) or a value
            if formula and ('IF' in formula.upper() or 'ISBLANK' in formula.upper()):
                inferred_found = True
                break
            elif value:
                parsed = parse_date_flexible(value)
                if parsed and parsed.year == 2024 and parsed.month == 5:
                    inferred_found = True
                    break
    
    if inferred_found:
        return True, "✅ Missing return dates inferred (Mike Roberts row)"
    else:
        return False, "❌ Missing return dates not inferred properly"


def check_damage_period_identification(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str, List[str]]:
    """
    Check if borrowers during May 15-20, 2024 were correctly identified.
    Returns: (success, feedback, identified_borrowers)
    """
    rows = sheet_data['sheets'][sheet_name]
    identified_borrowers = []
    
    # Look for a column that flags damage period overlap
    # This would be a YES/NO or similar flag
    for row_idx in range(1, min(9, len(rows))):
        row = rows[row_idx]
        
        # Get borrower name
        borrower_cell = row[0] if len(row) > 0 else None
        borrower = borrower_cell.get('value') if isinstance(borrower_cell, dict) else borrower_cell
        
        if not borrower:
            continue
        
        # Check for flag columns (likely after column E)
        for col_idx in range(5, min(20, len(row))):
            cell = row[col_idx]
            if isinstance(cell, dict):
                value = cell.get('value')
                
                # Look for YES, TRUE, or similar positive indicator
                if value and str(value).upper() in ['YES', 'TRUE', '1', 'Y', 'X']:
                    identified_borrowers.append(str(borrower))
                    break
    
    # Expected: Jessica Lee (definite), possibly Mike Roberts and Kevin Brown
    expected_count_min = 1  # At least Jessica
    expected_count_max = 4  # Could be Jessica, Mike, Kevin, Tom
    
    count = len(identified_borrowers)
    success = expected_count_min <= count <= expected_count_max
    
    if success:
        feedback = f"✅ Damage period borrowers identified ({count}: {', '.join(identified_borrowers[:3])})"
    else:
        feedback = f"❌ Incorrect damage period identification (found {count}, expected {expected_count_min}-{expected_count_max})"
    
    return success, feedback, identified_borrowers


def check_cost_calculations(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str, float]:
    """
    Check if costs were calculated and sum to $85 (±$0.50).
    Returns: (success, feedback, total_calculated)
    """
    rows = sheet_data['sheets'][sheet_name]
    
    cost_values = []
    
    # Look for currency values in the spreadsheet (likely in rightmost columns)
    for row_idx in range(1, min(9, len(rows))):
        row = rows[row_idx]
        
        for col_idx in range(5, min(25, len(row))):
            cell = row[col_idx]
            if isinstance(cell, dict):
                value = cell.get('value')
                
                # Check if it's a number that could be a cost
                if isinstance(value, (int, float)) and 1 <= value <= 85:
                    cost_values.append(float(value))
                elif isinstance(value, str):
                    # Try to parse currency strings like "$42.50"
                    cleaned = value.replace('$', '').replace(',', '').strip()
                    try:
                        cost = float(cleaned)
                        if 1 <= cost <= 85:
                            cost_values.append(cost)
                    except:
                        pass
    
    if not cost_values:
        return False, "❌ No cost calculations found", 0.0
    
    total_calculated = sum(cost_values)
    
    # Check if total is close to $85
    tolerance = 0.50
    if abs(total_calculated - REPAIR_COST) <= tolerance:
        feedback = f"✅ Costs calculated correctly (total: ${total_calculated:.2f})"
        return True, feedback, total_calculated
    else:
        feedback = f"❌ Cost calculation error (total: ${total_calculated:.2f}, expected: $85.00)"
        return False, feedback, total_calculated


def check_conditional_formatting_applied(filepath: str) -> Tuple[bool, str]:
    """
    Check if conditional formatting was applied to the spreadsheet.
    """
    try:
        import zipfile
        from xml.etree import ElementTree as ET
        
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, "❌ Could not read ODS content"
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in styles
            # ODF uses <table:conditional-formats> elements
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0'
            }
            
            # Check for conditional formatting elements
            cond_formats = root.findall('.//table:conditional-formats', namespaces)
            
            # Also check for cell styles that might indicate manual highlighting
            cell_styles = root.findall('.//style:style[@style:family="table-cell"]', namespaces)
            
            formatting_count = len(cond_formats) + (1 if len(cell_styles) > 5 else 0)
            
            if formatting_count >= 1:
                return True, f"✅ Conditional formatting applied ({formatting_count} rules/styles)"
            else:
                return False, "⚠️ No conditional formatting detected (optional)"
    
    except Exception as e:
        logger.debug(f"Error checking conditional formatting: {e}")
        return False, "⚠️ Could not verify conditional formatting"


def check_formulas_present(sheet_data: Dict, sheet_name: str) -> Tuple[bool, str, int]:
    """
    Check if formulas are used (not hardcoded values).
    """
    rows = sheet_data['sheets'][sheet_name]
    
    formula_count = 0
    
    # Check for formulas in data rows
    for row_idx in range(1, min(9, len(rows))):
        row = rows[row_idx]
        
        for col_idx in range(5, min(25, len(row))):
            cell = row[col_idx]
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula:
                    formula_count += 1
    
    success = formula_count >= 5  # At least 5 cells with formulas
    
    if success:
        feedback = f"✅ Formulas present ({formula_count} formula cells)"
    else:
        feedback = f"❌ Insufficient formulas ({formula_count} found, expected 5+)"
    
    return success, feedback, formula_count


def verify_tool_library_investigation(traj, env_info, task_info):
    """
    Main verifier for Tool Library Damage Investigation task.
    
    Checks:
    1. Date standardization
    2. Missing data inference
    3. Damage period identification
    4. Cost calculations
    5. Conditional formatting
    6. Formula presence
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/tool_damage_investigation.ods",
        "/home/ga/Documents/tool_library_log.ods",
        "/home/ga/Documents/tool_library_log.csv"
    ]
    
    success = False
    file_info = None
    for container_path in possible_paths:
        expected_formats = ['ods'] if container_path.endswith('.ods') else ['csv', 'ods']
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            container_path,
            expected_formats
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load investigation file: {error}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        sheet_names = list(sheet_data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Date Standardization
        date_std_success, date_std_feedback, std_count = check_date_standardization(
            sheet_data, sheet_name
        )
        if date_std_success:
            criteria_passed += 1
        feedback_parts.append(date_std_feedback)
        subscores['date_standardization'] = date_std_success
        
        # Criterion 2: Missing Data Inference
        infer_success, infer_feedback = check_missing_data_inference(
            sheet_data, sheet_name
        )
        if infer_success:
            criteria_passed += 1
        feedback_parts.append(infer_feedback)
        subscores['missing_data_inference'] = infer_success
        
        # Criterion 3: Damage Period Identification
        damage_success, damage_feedback, borrowers = check_damage_period_identification(
            sheet_data, sheet_name
        )
        if damage_success:
            criteria_passed += 1
        feedback_parts.append(damage_feedback)
        subscores['damage_period_identification'] = damage_success
        
        # Criterion 4: Cost Calculations
        cost_success, cost_feedback, total_cost = check_cost_calculations(
            sheet_data, sheet_name
        )
        if cost_success:
            criteria_passed += 1
        feedback_parts.append(cost_feedback)
        subscores['cost_calculations'] = cost_success
        
        # Criterion 5: Conditional Formatting (optional, half weight)
        format_success, format_feedback = check_conditional_formatting_applied(
            file_info['file_path']
        )
        if format_success:
            criteria_passed += 0.5  # Half credit
        feedback_parts.append(format_feedback)
        subscores['conditional_formatting'] = format_success
        
        # Criterion 6: Formulas Present
        formula_success, formula_feedback, formula_count = check_formulas_present(
            sheet_data, sheet_name
        )
        if formula_success:
            criteria_passed += 1
        feedback_parts.append(formula_feedback)
        subscores['formulas_present'] = formula_success
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (4/6 criteria)
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent investigation work!")
        elif passed:
            feedback_parts.insert(0, "✅ Investigation completed successfully")
        else:
            feedback_parts.insert(0, "❌ Investigation incomplete - more work needed")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "standardized_dates": std_count,
                "identified_borrowers": borrowers,
                "total_cost_calculated": total_cost,
                "formula_count": formula_count
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
