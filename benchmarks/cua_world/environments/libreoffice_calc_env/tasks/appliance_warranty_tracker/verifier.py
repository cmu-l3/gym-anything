#!/usr/bin/env python3
"""
Verifier for Appliance Warranty Tracker task.
Validates date calculations, conditional logic, and conditional formatting.
"""

import sys
import os
import logging
from datetime import datetime, date, timedelta
import zipfile
from xml.etree import ElementTree as ET

# Use relative path to utils folder for host-side verification
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_environment,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_flexible(date_value):
    """
    Parse date from various formats (string, date object, datetime).
    Returns date object or None.
    """
    if isinstance(date_value, date):
        return date_value
    if isinstance(date_value, datetime):
        return date_value.date()
    
    if isinstance(date_value, str):
        # Try common date formats
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(date_value, fmt).date()
            except ValueError:
                continue
    
    return None


def calculate_expected_expiration(purchase_date_str, warranty_months):
    """
    Calculate expected warranty expiration date.
    Uses same logic as EDATE function.
    """
    try:
        purchase_date = parse_date_flexible(purchase_date_str)
        if not purchase_date:
            return None
        
        # Add months (EDATE logic)
        from dateutil.relativedelta import relativedelta
        expected_date = purchase_date + relativedelta(months=int(warranty_months))
        return expected_date
    except Exception as e:
        logger.error(f"Error calculating expiration date: {e}")
        return None


def verify_expiration_date_formula(formula_text, purchase_cell='B2', warranty_cell='C2'):
    """
    Check if formula uses appropriate date calculation.
    Returns True if formula contains EDATE or DATE with month addition.
    """
    if not formula_text:
        return False
    
    formula_upper = formula_text.upper()
    
    # Check for EDATE function
    if 'EDATE' in formula_upper:
        return True
    
    # Check for DATE function with MONTH addition
    if 'DATE' in formula_upper and 'MONTH' in formula_upper:
        return True
    
    return False


def verify_days_remaining_formula(formula_text, expiration_cell='F2'):
    """
    Check if formula correctly calculates days remaining.
    Should subtract TODAY() from expiration date.
    """
    if not formula_text:
        return False
    
    formula_upper = formula_text.upper()
    
    # Must contain TODAY()
    if 'TODAY()' not in formula_upper:
        return False
    
    # Should reference expiration date cell
    if expiration_cell.upper() in formula_upper:
        return True
    
    return False


def verify_status_formula(formula_text):
    """
    Check if status formula uses nested IF logic correctly.
    Expected: IF(G2<0, "Expired", IF(G2<90, "Expiring Soon", "Active"))
    """
    if not formula_text:
        return False
    
    formula_upper = formula_text.upper()
    
    # Must contain IF function
    if 'IF' not in formula_upper:
        return False
    
    # Check for key status terms
    has_expired = 'EXPIRED' in formula_upper
    has_expiring_soon = 'EXPIRING' in formula_upper or 'SOON' in formula_upper
    has_active = 'ACTIVE' in formula_upper
    
    # Should have at least 2 of 3 status terms
    status_terms = sum([has_expired, has_expiring_soon, has_active])
    
    return status_terms >= 2


def calculate_expected_status(days_remaining):
    """
    Calculate expected status based on days remaining.
    """
    if days_remaining is None:
        return None
    
    try:
        days = float(days_remaining)
        if days < 0:
            return "expired"
        elif days < 90:
            return "expiring soon"
        else:
            return "active"
    except (ValueError, TypeError):
        return None


def check_conditional_formatting_exists(ods_filepath, sheet_name='Sheet'):
    """
    Check if conditional formatting or varied cell styling exists in status column.
    This is a simplified check - full ODS conditional formatting parsing is complex.
    """
    try:
        with zipfile.ZipFile(ods_filepath, 'r') as ods_zip:
            # Check content.xml for conditional formatting styles
            if 'content.xml' not in ods_zip.namelist():
                return False, []
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Check for style:map elements (conditional formatting indicators)
            namespaces = {
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
            }
            
            # Look for conditional formatting maps
            style_maps = root.findall('.//style:map', namespaces)
            has_conditional = len(style_maps) > 0
            
            # Alternative: check for varied background colors in column H cells
            # This is a heuristic - if cells have different background colors, likely formatted
            table_ns = {'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0'}
            cells = root.findall(f'.//table:table-cell', table_ns)
            
            # Collect unique style names (indicates different formatting)
            style_names = set()
            for cell in cells:
                style_name = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}style-name')
                if style_name:
                    style_names.add(style_name)
            
            # If multiple styles present, likely has formatting
            has_varied_styles = len(style_names) > 3
            
            return has_conditional or has_varied_styles, list(style_names)
    
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False, []


def verify_warranty_tracker(traj, env_info, task_info):
    """
    Verify warranty tracker task completion.
    
    Checks:
    1. Expiration date formulas correct (EDATE or DATE with month addition)
    2. Days remaining formulas correct (uses TODAY())
    3. Status logic correct (nested IF statements)
    4. All rows have calculated values
    5. Conditional formatting applied (or varied styling)
    6. Appropriate color scheme (heuristic check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    container_paths = [
        "/home/ga/Documents/warranty_tracker.ods",
        "/home/ga/Documents/appliances_data.ods",
        "/home/ga/Documents/appliances_data.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            expected_formats=[file_format]
        )
        if success:
            logger.info(f"Found file at: {container_path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"File not found or parse error: {error}"}
    
    try:
        data = file_info['sheet_data']
        sheet_names = get_sheet_names(data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        
        # Expected data: 5 appliances in rows 2-6
        appliance_rows = [2, 3, 4, 5, 6]
        
        # Criterion 1: Expiration Date Formula Correct
        exp_date_formula = get_cell_formula(data, sheet_name, "F2")
        exp_date_value = get_cell_value(data, sheet_name, "F2")
        
        if verify_expiration_date_formula(exp_date_formula):
            # Verify calculated date is reasonable
            purchase_date = get_cell_value(data, sheet_name, "B2")
            warranty_months = get_cell_value(data, sheet_name, "C2")
            
            if purchase_date and warranty_months:
                expected_exp = calculate_expected_expiration(purchase_date, warranty_months)
                calc_exp = parse_date_flexible(exp_date_value)
                
                if expected_exp and calc_exp:
                    diff_days = abs((calc_exp - expected_exp).days)
                    
                    if diff_days <= 3:
                        criteria_met += 1
                        feedback_parts.append(f"✅ Expiration date formula correct: {exp_date_formula[:50]}")
                    else:
                        feedback_parts.append(f"⚠️ Expiration date off by {diff_days} days (formula: {exp_date_formula[:30]}...)")
                else:
                    feedback_parts.append(f"⚠️ Could not parse expiration date for validation")
                    criteria_met += 0.5  # Partial credit for having a formula
            else:
                feedback_parts.append("⚠️ Could not verify expiration calculation (missing source data)")
                criteria_met += 0.5
        else:
            feedback_parts.append(f"❌ Missing or incorrect expiration date formula (got: {exp_date_formula[:50] if exp_date_formula else 'None'})")
        
        # Criterion 2: Days Remaining Formula Correct
        days_remaining_formula = get_cell_formula(data, sheet_name, "G2")
        days_remaining_value = get_cell_value(data, sheet_name, "G2")
        
        if verify_days_remaining_formula(days_remaining_formula):
            # Verify calculation
            exp_date_value = get_cell_value(data, sheet_name, "F2")
            if exp_date_value:
                exp_dt = parse_date_flexible(exp_date_value)
                if exp_dt:
                    expected_days = (exp_dt - date.today()).days
                    
                    try:
                        actual_days = float(days_remaining_value) if days_remaining_value is not None else None
                        if actual_days is not None and abs(actual_days - expected_days) <= 1:
                            criteria_met += 1
                            feedback_parts.append(f"✅ Days remaining formula correct: {days_remaining_formula[:50]}")
                        else:
                            feedback_parts.append(f"⚠️ Days remaining calculation may be off")
                            criteria_met += 0.5
                    except (ValueError, TypeError):
                        feedback_parts.append(f"⚠️ Days remaining value not numeric")
                        criteria_met += 0.5
                else:
                    feedback_parts.append("⚠️ Could not verify days remaining")
                    criteria_met += 0.5
            else:
                feedback_parts.append("⚠️ Missing expiration date for days calculation")
                criteria_met += 0.5
        else:
            feedback_parts.append(f"❌ Missing or incorrect days remaining formula (got: {days_remaining_formula[:50] if days_remaining_formula else 'None'})")
        
        # Criterion 3: Status Logic Correct
        status_formula = get_cell_formula(data, sheet_name, "H2")
        status_value = get_cell_value(data, sheet_name, "H2")
        
        if verify_status_formula(status_formula):
            # Check if status matches expected value based on days remaining
            days_val = get_cell_value(data, sheet_name, "G2")
            expected_status = calculate_expected_status(days_val)
            
            if status_value and expected_status:
                actual_status = status_value.strip().lower()
                if actual_status == expected_status or actual_status.replace(' ', '') == expected_status.replace(' ', ''):
                    criteria_met += 1
                    feedback_parts.append(f"✅ Status logic correct: {status_formula[:60]}")
                else:
                    feedback_parts.append(f"⚠️ Status value unexpected (got '{status_value}', expected '{expected_status}')")
                    criteria_met += 0.5  # Partial credit for having logic
            else:
                feedback_parts.append("⚠️ Could not fully validate status logic")
                criteria_met += 0.5
        else:
            feedback_parts.append(f"❌ Missing or incorrect status formula (got: {status_formula[:50] if status_formula else 'None'})")
        
        # Criterion 4: All Rows Calculated
        complete_rows = 0
        for row_idx in appliance_rows:
            cell_ref_f = f"F{row_idx}"
            cell_ref_g = f"G{row_idx}"
            cell_ref_h = f"H{row_idx}"
            
            val_f = get_cell_value(data, sheet_name, cell_ref_f)
            val_g = get_cell_value(data, sheet_name, cell_ref_g)
            val_h = get_cell_value(data, sheet_name, cell_ref_h)
            
            if val_f is not None and val_g is not None and val_h:
                complete_rows += 1
        
        if complete_rows >= 5:
            criteria_met += 1
            feedback_parts.append(f"✅ All 5 appliances have calculations")
        elif complete_rows >= 3:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Only {complete_rows}/5 rows calculated")
        else:
            feedback_parts.append(f"❌ Only {complete_rows}/5 rows calculated")
        
        # Criterion 5 & 6: Conditional Formatting (simplified check)
        # For ODS files, check for conditional formatting indicators
        if file_info['format'] == 'ods':
            has_formatting, style_names = check_conditional_formatting_exists(
                file_info['file_path'], 
                sheet_name
            )
            
            if has_formatting:
                criteria_met += 1
                feedback_parts.append("✅ Conditional formatting or varied styling detected")
                
                # Criterion 6: Check if multiple styles exist (color variety)
                if len(style_names) >= 3:
                    criteria_met += 1
                    feedback_parts.append(f"✅ Multiple cell styles found ({len(style_names)} styles)")
                else:
                    criteria_met += 0.5
                    feedback_parts.append("⚠️ Limited style variety (may need more conditional formatting rules)")
            else:
                # Give partial credit if status column exists with values
                if status_value:
                    criteria_met += 0.5
                    feedback_parts.append("⚠️ Status column exists but conditional formatting not detected")
                else:
                    feedback_parts.append("❌ No conditional formatting detected")
        else:
            # For CSV files, can't check formatting
            if status_value:
                criteria_met += 1
                feedback_parts.append("⚠️ CSV format - cannot verify conditional formatting, giving credit for status column")
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (4/6 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "expiration_formula": exp_date_formula is not None and verify_expiration_date_formula(exp_date_formula),
                "days_remaining_formula": days_remaining_formula is not None and verify_days_remaining_formula(days_remaining_formula),
                "status_logic": status_formula is not None and verify_status_formula(status_formula),
                "all_rows_calculated": complete_rows >= 5,
                "criteria_met": criteria_met,
                "total_criteria": total_criteria
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_environment(file_info.get('temp_dir'))
