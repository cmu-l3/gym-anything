#!/usr/bin/env python3
"""
Verifier for Personal Lending Tracker Cleanup task

Validates:
1. Days On Loan formula with TODAY(), IF, ISBLANK
2. SUMIF formula for total unreturned value
3. Conditional formatting on overdue items
4. Formula coverage across all rows
"""

import sys
import os
import logging
import re
import zipfile
from datetime import datetime, timedelta
from xml.etree import ElementTree as ET

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_days_on_loan_formula(formula_text):
    """
    Check if formula contains required elements for Days On Loan calculation
    
    Valid patterns:
    - =IF(ISBLANK(D2), TODAY()-C2, "")
    - =IF(D2="", TODAY()-C2, 0)
    - =IF(LEN(D2)=0, TODAY()-C2, "")
    """
    if not formula_text:
        return False, "No formula found"
    
    formula_upper = formula_text.upper()
    
    # Must contain TODAY()
    if "TODAY()" not in formula_upper:
        return False, "Missing TODAY() function"
    
    # Must contain IF
    if "IF(" not in formula_upper:
        return False, "Missing IF() conditional logic"
    
    # Must have some blank check (ISBLANK, ="" or LEN)
    has_blank_check = (
        "ISBLANK" in formula_upper or
        '=""' in formula_text or
        "LEN(" in formula_upper
    )
    
    if not has_blank_check:
        return False, "Missing blank cell check (ISBLANK or similar)"
    
    # Should have date subtraction (TODAY() - something)
    if "-C" not in formula_upper and "-$C" not in formula_upper:
        return False, "Missing date subtraction from Lent Date column"
    
    return True, "Valid Days On Loan formula"


def check_sumif_formula(formula_text):
    """
    Check if formula contains SUMIF for calculating unreturned item value
    
    Valid patterns:
    - =SUMIF(D:D, "", E:E)
    - =SUMIF(D2:D11, "", E2:E11)
    - =SUMIFS(E:E, D:D, "")
    """
    if not formula_text:
        return False, "No formula found"
    
    formula_upper = formula_text.upper()
    
    # Must contain SUMIF or SUMIFS
    if "SUMIF" not in formula_upper:
        return False, "Missing SUMIF function"
    
    # Must have empty string criteria to find blanks
    if '""' not in formula_text and "''" not in formula_text:
        return False, "Missing blank criteria (empty string)"
    
    # Should reference Return Date column (D) and Value column (E)
    has_d_ref = "D:" in formula_upper or "D2:D" in formula_upper or "$D" in formula_upper
    has_e_ref = "E:" in formula_upper or "E2:E" in formula_upper or "$E" in formula_upper
    
    if not has_d_ref:
        return False, "Missing reference to Return Date column (D)"
    
    if not has_e_ref:
        return False, "Missing reference to Value column (E)"
    
    return True, "Valid SUMIF formula"


def find_days_on_loan_column(sheet_data):
    """Find which column contains Days On Loan formulas"""
    if not sheet_data or 'sheets' not in sheet_data:
        return None
    
    sheet_name = list(sheet_data['sheets'].keys())[0]
    rows = sheet_data['sheets'][sheet_name]
    
    # Check header row for "Days On Loan" or similar
    if len(rows) > 0:
        header_row = rows[0]
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and 'days' in str(cell_value).lower() and 'loan' in str(cell_value).lower():
                return col_idx
    
    # If not found by header, check for TODAY() formulas in columns E, F, G
    for col_idx in range(4, 8):  # Check columns E through H
        if len(rows) > 1:
            cell = rows[1][col_idx] if col_idx < len(rows[1]) else None
            if cell:
                formula = cell.get('formula') if isinstance(cell, dict) else None
                if formula and 'TODAY()' in formula.upper():
                    return col_idx
    
    return None


def find_sumif_formula_location(sheet_data):
    """Find cell containing SUMIF formula for unreturned value"""
    if not sheet_data or 'sheets' not in sheet_data:
        return None, None
    
    sheet_name = list(sheet_data['sheets'].keys())[0]
    rows = sheet_data['sheets'][sheet_name]
    
    # Search through all cells (focus on bottom area and value column area)
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            formula = cell.get('formula') if isinstance(cell, dict) else None
            if formula and 'SUMIF' in formula.upper() and '""' in formula:
                return row_idx, col_idx
    
    return None, None


def check_conditional_formatting_ods(filepath):
    """
    Check for conditional formatting in ODS file
    
    Returns: (has_formatting, details)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, "No content.xml found"
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting elements
            # In ODS, conditional formats are in table:conditional-formats
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'calcext': 'urn:org:documentfoundation:names:experimental:calc:xmlns:calcext:1.0'
            }
            
            # Check for conditional format elements
            cond_formats = root.findall('.//calcext:conditional-formats', namespaces)
            if cond_formats:
                return True, f"Found {len(cond_formats)} conditional format(s)"
            
            # Alternative: check for style:map elements which can indicate conditional formatting
            style_maps = root.findall('.//{urn:oasis:names:tc:opendocument:xmlns:style:1.0}map')
            if style_maps:
                return True, f"Found {len(style_maps)} style map(s) (may indicate conditional formatting)"
            
            return False, "No conditional formatting detected"
            
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False, f"Error checking: {str(e)}"


def check_conditional_formatting_xlsx(filepath):
    """
    Check for conditional formatting in XLSX file
    """
    try:
        from openpyxl import load_workbook
        wb = load_workbook(filepath)
        ws = wb.active
        
        if hasattr(ws, 'conditional_formatting') and ws.conditional_formatting:
            rules = ws.conditional_formatting._cf_rules
            if rules:
                return True, f"Found {len(rules)} conditional formatting rule(s)"
        
        return False, "No conditional formatting detected"
        
    except ImportError:
        logger.warning("openpyxl not available for XLSX conditional formatting check")
        return False, "Cannot check XLSX formatting"
    except Exception as e:
        logger.warning(f"Error checking XLSX conditional formatting: {e}")
        return False, f"Error: {str(e)}"


def verify_lending_tracker_cleanup(traj, env_info, task_info):
    """
    Verify lending tracker cleanup task
    
    Criteria:
    1. Days On Loan formula (40%) - Contains TODAY(), IF, ISBLANK
    2. SUMIF formula (30%) - Calculates unreturned value correctly  
    3. Conditional formatting (20%) - Applied to highlight overdue items
    4. Formula coverage (10%) - Formulas in all data rows
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    file_paths = [
        ("/home/ga/Documents/lending_tracker_cleaned.ods", ['ods']),
        ("/home/ga/Documents/lending_log.ods", ['ods']),
        ("/home/ga/Documents/lending_log.csv", ['csv', 'ods'])
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for container_path, formats in file_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            formats
        )
        if success:
            logger.info(f"✅ Found file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not load spreadsheet file. Tried: {[p[0] for p in file_paths]}"
        }
    
    try:
        sheet_data = file_info['sheet_data']
        file_path = file_info['file_path']
        temp_dir = file_info.get('temp_dir')
        
        if 'sheets' not in sheet_data or not sheet_data['sheets']:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = list(sheet_data['sheets'].keys())[0]
        rows = sheet_data['sheets'][sheet_name]
        
        criteria_scores = {}
        feedback_parts = []
        total_score = 0
        
        # CRITERION 1: Days On Loan Formula (40 points)
        logger.info("Checking Criterion 1: Days On Loan formula...")
        days_col = find_days_on_loan_column(sheet_data)
        
        if days_col is not None:
            # Check formula in first data row (row 1, 0-indexed)
            if len(rows) > 1 and days_col < len(rows[1]):
                cell = rows[1][days_col]
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                formula_valid, formula_msg = check_days_on_loan_formula(formula)
                
                if formula_valid:
                    # Check that formula is in multiple rows (at least 3 data rows)
                    formula_count = 0
                    for row_idx in range(1, min(len(rows), 11)):  # Check up to 10 data rows
                        if days_col < len(rows[row_idx]):
                            cell = rows[row_idx][days_col]
                            if isinstance(cell, dict) and cell.get('formula'):
                                formula_count += 1
                    
                    if formula_count >= 3:
                        total_score += 40
                        criteria_scores['days_formula'] = True
                        feedback_parts.append(f"✅ Days On Loan formula correct ({formula_count} rows)")
                    else:
                        total_score += 20  # Partial credit
                        criteria_scores['days_formula'] = False
                        feedback_parts.append(f"⚠️ Days formula exists but only in {formula_count} row(s)")
                else:
                    criteria_scores['days_formula'] = False
                    feedback_parts.append(f"❌ Days formula invalid: {formula_msg}")
            else:
                criteria_scores['days_formula'] = False
                feedback_parts.append("❌ Days On Loan column found but no formula in data rows")
        else:
            criteria_scores['days_formula'] = False
            feedback_parts.append("❌ Days On Loan column not found")
        
        # CRITERION 2: SUMIF Formula (30 points)
        logger.info("Checking Criterion 2: SUMIF formula...")
        sumif_row, sumif_col = find_sumif_formula_location(sheet_data)
        
        if sumif_row is not None and sumif_col is not None:
            cell = rows[sumif_row][sumif_col]
            formula = cell.get('formula') if isinstance(cell, dict) else None
            value = cell.get('value') if isinstance(cell, dict) else None
            
            formula_valid, formula_msg = check_sumif_formula(formula)
            
            if formula_valid:
                # Expected unreturned value: Circular Saw (120) + Pressure Washer (200) + 
                # Pasta Maker (80) + Board Game (60) + Kayak Paddle (65) + Extension Ladder (175) = 700
                expected_total = 700
                
                if value is not None:
                    try:
                        actual_value = float(value)
                        if abs(actual_value - expected_total) < 1:  # Allow small rounding
                            total_score += 30
                            criteria_scores['sumif_formula'] = True
                            feedback_parts.append(f"✅ SUMIF formula correct (${actual_value:.0f} outstanding)")
                        else:
                            total_score += 15  # Partial credit for having formula
                            criteria_scores['sumif_formula'] = False
                            feedback_parts.append(f"⚠️ SUMIF formula exists but value unexpected (got ${actual_value:.0f}, expected ~${expected_total})")
                    except (ValueError, TypeError):
                        total_score += 15
                        criteria_scores['sumif_formula'] = False
                        feedback_parts.append(f"⚠️ SUMIF formula exists but couldn't validate result")
                else:
                    total_score += 15
                    criteria_scores['sumif_formula'] = False
                    feedback_parts.append("⚠️ SUMIF formula exists but no calculated value")
            else:
                criteria_scores['sumif_formula'] = False
                feedback_parts.append(f"❌ SUMIF formula invalid: {formula_msg}")
        else:
            criteria_scores['sumif_formula'] = False
            feedback_parts.append("❌ SUMIF formula not found")
        
        # CRITERION 3: Conditional Formatting (20 points)
        logger.info("Checking Criterion 3: Conditional formatting...")
        file_ext = os.path.splitext(file_path)[1].lower()
        
        if file_ext == '.ods':
            has_formatting, format_details = check_conditional_formatting_ods(file_path)
        elif file_ext in ['.xlsx', '.xls']:
            has_formatting, format_details = check_conditional_formatting_xlsx(file_path)
        else:
            has_formatting, format_details = False, "Unsupported format for formatting check"
        
        if has_formatting:
            total_score += 20
            criteria_scores['conditional_formatting'] = True
            feedback_parts.append(f"✅ Conditional formatting applied ({format_details})")
        else:
            criteria_scores['conditional_formatting'] = False
            feedback_parts.append(f"❌ No conditional formatting detected ({format_details})")
        
        # CRITERION 4: Formula Coverage (10 points)
        logger.info("Checking Criterion 4: Formula coverage...")
        # Check that Days On Loan formulas cover most/all data rows
        if days_col is not None:
            data_rows = 0
            formula_rows = 0
            
            # Count data rows (non-empty rows after header)
            for row_idx in range(1, len(rows)):
                row = rows[row_idx]
                # Check if row has data (name column should have value)
                if len(row) > 0:
                    cell = row[0]
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    if value:
                        data_rows += 1
                        
                        # Check if this row has Days formula
                        if days_col < len(row):
                            days_cell = row[days_col]
                            if isinstance(days_cell, dict) and days_cell.get('formula'):
                                formula_rows += 1
            
            if data_rows > 0:
                coverage_pct = (formula_rows / data_rows) * 100
                if coverage_pct >= 80:  # At least 80% coverage
                    total_score += 10
                    criteria_scores['formula_coverage'] = True
                    feedback_parts.append(f"✅ Formula coverage good ({formula_rows}/{data_rows} rows)")
                elif coverage_pct >= 50:
                    total_score += 5  # Partial credit
                    criteria_scores['formula_coverage'] = False
                    feedback_parts.append(f"⚠️ Partial formula coverage ({formula_rows}/{data_rows} rows)")
                else:
                    criteria_scores['formula_coverage'] = False
                    feedback_parts.append(f"❌ Poor formula coverage ({formula_rows}/{data_rows} rows)")
            else:
                criteria_scores['formula_coverage'] = False
                feedback_parts.append("❌ Could not determine formula coverage")
        else:
            criteria_scores['formula_coverage'] = False
            feedback_parts.append("❌ No Days column to check coverage")
        
        # Final scoring
        passed = total_score >= 75
        
        if passed and total_score >= 95:
            feedback_parts.append("🎉 Excellent cleanup work!")
        elif passed:
            feedback_parts.append("✅ Lending tracker cleaned successfully")
        else:
            feedback_parts.append("❌ Cleanup incomplete - see requirements above")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "subscores": criteria_scores
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
