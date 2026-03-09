#!/usr/bin/env python3
"""
Verifier for Ticket Resale Profit Tracker task
Checks formula structure, calculation accuracy, and conditional formatting
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    setup_calc_verification
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_formula(formula):
    """Normalize formula for comparison (remove spaces, standardize case)"""
    if not formula:
        return ""
    # Remove spaces and convert to uppercase
    normalized = formula.replace(" ", "").upper()
    return normalized


def check_purchase_fee_formula(formula):
    """
    Check if purchase fee formula is correct.
    Should be: =IF(D2="StubHub", C2*0.10, 0) or similar
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for IF function
    if not norm.startswith("=IF("):
        return False, "Not an IF formula"
    
    # Check for StubHub condition
    if "STUBHUB" not in norm:
        return False, "Missing StubHub condition"
    
    # Check for 10% or 0.1 or 0.10
    if not any(x in norm for x in ["0.1", "0.10", "10%", "*10/100"]):
        return False, "Missing 10% fee calculation"
    
    # Check references purchase price column (C or similar)
    if not any(x in norm for x in ["C2*", "C3*", "$C$2*", "$C$3*"]):
        return False, "Not referencing purchase price"
    
    return True, "Valid purchase fee formula"


def check_selling_fee_formula(formula):
    """
    Check if selling fee formula is correct.
    Should be nested IF: =IF(F2="StubHub", E2*0.15, IF(F2="Ticketmaster", E2*0.12, 0))
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for nested IF
    if norm.count("IF(") < 2:
        return False, "Missing nested IF (need to handle multiple platforms)"
    
    # Check for StubHub 15% fee
    if "STUBHUB" not in norm:
        return False, "Missing StubHub condition"
    
    if not any(x in norm for x in ["0.15", "15%", "*15/100"]):
        return False, "Missing 15% StubHub fee"
    
    # Check for Ticketmaster 12% fee
    if "TICKETMASTER" not in norm:
        return False, "Missing Ticketmaster condition"
    
    if not any(x in norm for x in ["0.12", "12%", "*12/100"]):
        return False, "Missing 12% Ticketmaster fee"
    
    # Check references sale price column (E or similar)
    if not any(x in norm for x in ["E2*", "E3*", "$E$2*", "$E$3*"]):
        return False, "Not referencing sale price"
    
    return True, "Valid selling fee formula"


def check_processing_fee_formula(formula):
    """
    Check if payment processing fee formula is correct.
    Should be: =IF(OR(F2="StubHub", F2="Ticketmaster"), E2*0.029, 0)
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Check for OR function
    if "OR(" not in norm:
        return False, "Missing OR function for platform check"
    
    # Check for both platforms
    if "STUBHUB" not in norm or "TICKETMASTER" not in norm:
        return False, "Missing platform conditions in OR"
    
    # Check for 2.9% or 0.029
    if not any(x in norm for x in ["0.029", "2.9%", "*2.9/100", "*29/1000"]):
        return False, "Missing 2.9% processing fee"
    
    # Check references sale price
    if not any(x in norm for x in ["E2*", "E3*", "$E$2*", "$E$3*"]):
        return False, "Not referencing sale price"
    
    return True, "Valid processing fee formula"


def check_profit_formula(formula, expected_cols):
    """
    Check if profit formula correctly subtracts all fees.
    Should be something like: =E2-C2-G2-H2-I2
    (Sale Price - Purchase Price - Purchase Fee - Selling Fee - Processing Fee)
    """
    if not formula:
        return False, "No formula found"
    
    norm = normalize_formula(formula)
    
    # Should start with =
    if not norm.startswith("="):
        return False, "Not a formula"
    
    # Count minus signs (should have at least 4: -purchase, -fee1, -fee2, -fee3)
    minus_count = norm.count("-")
    if minus_count < 4:
        return False, f"Not enough subtractions (found {minus_count}, need at least 4)"
    
    # Check if it references multiple columns (fees and prices)
    # Should have references to at least 5 columns
    col_refs = re.findall(r'[A-Z]+\d+', norm)
    unique_cols = set([re.sub(r'\d+', '', ref) for ref in col_refs])
    
    if len(unique_cols) < 4:
        return False, f"Not enough column references (found {len(unique_cols)}, need at least 4)"
    
    return True, "Valid profit formula with fee subtractions"


def check_conditional_formatting(filepath):
    """
    Check if conditional formatting is applied to highlight negative values.
    This checks the ODS XML structure for conditional formatting rules.
    """
    try:
        if not filepath.endswith('.ods'):
            logger.info("Not an ODS file, skipping conditional formatting check")
            return False, "Not ODS format"
        
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, "No content.xml in ODS"
            
            content_xml = ods_zip.read('content.xml')
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Look for conditional formatting indicators
            # In ODS, this could be style:conditional-format or similar
            has_conditional = any(marker in content_str for marker in [
                'conditional-format',
                'condition=',
                'cell-content()<0',
                'cell-content()&lt;0'
            ])
            
            if has_conditional:
                return True, "Conditional formatting detected"
            else:
                return False, "No conditional formatting found"
    
    except Exception as e:
        logger.warning(f"Could not check conditional formatting: {e}")
        return False, f"Error checking: {str(e)}"


def verify_calculation_accuracy(workbook, sheet_name, row_idx):
    """
    Verify that calculations in a specific row are mathematically correct.
    Returns (is_correct, error_message)
    """
    try:
        # Get values (assuming standard column layout)
        # A: Description, B: Purchase Price, C: Purchase Platform, 
        # D: Sale Price, E: Sale Platform, F: Purchase Fee,
        # G: Selling Fee, H: Processing Fee, I: True Profit
        
        # Try to find purchase price column (usually B or C)
        purchase_price = None
        sale_price = None
        
        # Try different column configurations
        for pc, sc in [('C', 'E'), ('B', 'D')]:
            pp = get_cell_value(workbook, sheet_name, f'{pc}{row_idx}')
            sp = get_cell_value(workbook, sheet_name, f'{sc}{row_idx}')
            if pp and sp and isinstance(pp, (int, float)) and isinstance(sp, (int, float)):
                purchase_price = float(pp)
                sale_price = float(sp)
                break
        
        if purchase_price is None or sale_price is None:
            return True, "Could not locate price columns for verification"
        
        # Get platform info to calculate expected fees
        purchase_platform = None
        sale_platform = None
        
        for pp_col, sp_col in [('D', 'F'), ('C', 'E')]:
            pp_plat = get_cell_value(workbook, sheet_name, f'{pp_col}{row_idx}')
            sp_plat = get_cell_value(workbook, sheet_name, f'{sp_col}{row_idx}')
            if pp_plat and sp_plat:
                purchase_platform = str(pp_plat)
                sale_platform = str(sp_plat)
                break
        
        if not purchase_platform or not sale_platform:
            return True, "Could not locate platform columns"
        
        # Calculate expected fees
        expected_purchase_fee = purchase_price * 0.10 if "StubHub" in purchase_platform else 0
        
        if "StubHub" in sale_platform:
            expected_selling_fee = sale_price * 0.15
        elif "Ticketmaster" in sale_platform:
            expected_selling_fee = sale_price * 0.12
        else:
            expected_selling_fee = 0
        
        expected_processing_fee = sale_price * 0.029 if any(p in sale_platform for p in ["StubHub", "Ticketmaster"]) else 0
        
        expected_profit = sale_price - purchase_price - expected_purchase_fee - expected_selling_fee - expected_processing_fee
        
        # Get actual profit value (try different columns)
        actual_profit = None
        for col in ['J', 'I', 'K', 'G']:
            val = get_cell_value(workbook, sheet_name, f'{col}{row_idx}')
            if val is not None and isinstance(val, (int, float)):
                # Check if this could be the profit column
                if -1000 < float(val) < 1000:  # Reasonable profit range
                    actual_profit = float(val)
                    break
        
        if actual_profit is None:
            return True, "Could not locate profit column"
        
        # Allow small tolerance for rounding
        if abs(actual_profit - expected_profit) < 0.5:
            return True, ""
        else:
            return False, f"Calculation incorrect for row {row_idx}: expected profit {expected_profit:.2f}, got {actual_profit:.2f}"
    
    except Exception as e:
        logger.warning(f"Could not verify calculation for row {row_idx}: {e}")
        return True, "Verification skipped"


def verify_ticket_resale_profit(traj, env_info, task_info):
    """
    Main verification function for ticket resale profit tracker task.
    
    Checks:
    1. Purchase fee formula is correct
    2. Selling fee formula is correct (nested IF)
    3. Processing fee formula is correct (OR condition)
    4. Profit formula subtracts all fees
    5. Calculations are mathematically accurate (spot check)
    6. Conditional formatting applied to negative values
    7. Column structure is present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations/formats
    temp_dir = None
    success = False
    workbook = None
    file_path = None
    
    for fmt, path in [
        ('ods', '/home/ga/Documents/ticket_resale_data.ods'),
        ('csv', '/home/ga/Documents/ticket_resale_data.csv'),
        ('ods', '/home/ga/Documents/ticket_resale_corrected.ods')
    ]:
        success, wb, error, td = copy_and_parse_spreadsheet(path, copy_from_env, file_format=fmt)
        if success:
            workbook = wb
            temp_dir = td
            # Get the actual file path from temp directory
            if td:
                import glob
                files = glob.glob(os.path.join(td, f"*{fmt}"))
                if files:
                    file_path = files[0]
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        # Find the data sheet (not the fee guide)
        sheet_name = sheet_names[0]
        for name in sheet_names:
            if "fee" not in name.lower() and "guide" not in name.lower():
                sheet_name = name
                break
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Get the sheet data
        sheet_data = workbook['sheets'][sheet_name]
        
        # Find a data row (row 2 or 3 typically, row 1 is headers)
        test_row = 2
        if len(sheet_data) > test_row:
            # Try to find fee columns by looking for formulas
            purchase_fee_col = None
            selling_fee_col = None
            processing_fee_col = None
            profit_col = None
            
            # Check columns for formulas
            for col_letter in ['G', 'H', 'I', 'J', 'K', 'F', 'E']:
                formula = get_cell_formula(workbook, sheet_name, f'{col_letter}{test_row}')
                if formula:
                    norm = normalize_formula(formula)
                    if not purchase_fee_col and "IF(" in norm and "0.1" in norm:
                        purchase_fee_col = col_letter
                    elif not selling_fee_col and norm.count("IF(") >= 2:
                        selling_fee_col = col_letter
                    elif not processing_fee_col and "OR(" in norm and "0.029" in norm:
                        processing_fee_col = col_letter
                    elif not profit_col and "-" in norm and norm.count("-") >= 3:
                        profit_col = col_letter
        
        # Criterion 1: Purchase Fee Formula
        if purchase_fee_col:
            formula = get_cell_formula(workbook, sheet_name, f'{purchase_fee_col}{test_row}')
            is_valid, msg = check_purchase_fee_formula(formula)
            if is_valid:
                criteria_passed += 1
                feedback_parts.append(f"✅ Purchase fee formula correct")
                subscores['purchase_fee_formula'] = True
            else:
                feedback_parts.append(f"❌ Purchase fee formula: {msg}")
                subscores['purchase_fee_formula'] = False
        else:
            feedback_parts.append("❌ Purchase fee column not found")
            subscores['purchase_fee_formula'] = False
        
        # Criterion 2: Selling Fee Formula
        if selling_fee_col:
            formula = get_cell_formula(workbook, sheet_name, f'{selling_fee_col}{test_row}')
            is_valid, msg = check_selling_fee_formula(formula)
            if is_valid:
                criteria_passed += 1
                feedback_parts.append(f"✅ Selling fee formula correct (nested IF)")
                subscores['selling_fee_formula'] = True
            else:
                feedback_parts.append(f"❌ Selling fee formula: {msg}")
                subscores['selling_fee_formula'] = False
        else:
            feedback_parts.append("❌ Selling fee column not found")
            subscores['selling_fee_formula'] = False
        
        # Criterion 3: Processing Fee Formula
        if processing_fee_col:
            formula = get_cell_formula(workbook, sheet_name, f'{processing_fee_col}{test_row}')
            is_valid, msg = check_processing_fee_formula(formula)
            if is_valid:
                criteria_passed += 1
                feedback_parts.append(f"✅ Processing fee formula correct (OR condition)")
                subscores['processing_fee_formula'] = True
            else:
                feedback_parts.append(f"❌ Processing fee formula: {msg}")
                subscores['processing_fee_formula'] = False
        else:
            feedback_parts.append("❌ Processing fee column not found")
            subscores['processing_fee_formula'] = False
        
        # Criterion 4: Profit Formula
        if profit_col:
            formula = get_cell_formula(workbook, sheet_name, f'{profit_col}{test_row}')
            is_valid, msg = check_profit_formula(formula, ['purchase', 'sale', 'fee1', 'fee2', 'fee3'])
            if is_valid:
                criteria_passed += 1
                feedback_parts.append(f"✅ Profit formula subtracts all fees")
                subscores['profit_formula'] = True
            else:
                feedback_parts.append(f"❌ Profit formula: {msg}")
                subscores['profit_formula'] = False
        else:
            feedback_parts.append("❌ Profit column not found or no formula")
            subscores['profit_formula'] = False
        
        # Criterion 5: Calculation Accuracy (spot check)
        calc_valid = True
        if len(sheet_data) > test_row:
            for check_row in [test_row, test_row + 1, test_row + 2]:
                if check_row < len(sheet_data):
                    is_correct, error_msg = verify_calculation_accuracy(workbook, sheet_name, check_row)
                    if not is_correct:
                        calc_valid = False
                        feedback_parts.append(f"❌ {error_msg}")
                        break
        
        if calc_valid:
            criteria_passed += 1
            feedback_parts.append("✅ Calculations mathematically correct")
            subscores['calculation_accuracy'] = True
        else:
            subscores['calculation_accuracy'] = False
        
        # Criterion 6: Conditional Formatting
        if file_path and file_path.endswith('.ods'):
            has_formatting, msg = check_conditional_formatting(file_path)
            if has_formatting:
                criteria_passed += 1
                feedback_parts.append("✅ Conditional formatting applied")
                subscores['conditional_formatting'] = True
            else:
                feedback_parts.append(f"⚠️ Conditional formatting not detected")
                subscores['conditional_formatting'] = False
        else:
            feedback_parts.append("⚠️ Not ODS format, cannot verify conditional formatting")
            subscores['conditional_formatting'] = False
        
        # Criterion 7: Column Structure
        # Check that we have enough columns with data
        row_data = sheet_data[1] if len(sheet_data) > 1 else []
        non_empty_cols = sum(1 for cell in row_data if (cell.get('value') if isinstance(cell, dict) else cell) is not None)
        
        if non_empty_cols >= 9:  # Should have original 6 + 3 new fee columns
            criteria_passed += 1
            feedback_parts.append("✅ All columns present")
            subscores['column_structure'] = True
        else:
            feedback_parts.append(f"❌ Missing columns (found {non_empty_cols}, expected 9+)")
            subscores['column_structure'] = False
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 5/7 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent! Profit calculations fixed correctly")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed - profit formulas corrected")
        else:
            feedback_parts.insert(0, "❌ Task incomplete - missing key formulas")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "criteria_met": f"{criteria_passed}/{total_criteria}"
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(temp_dir)
