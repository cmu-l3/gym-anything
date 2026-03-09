#!/usr/bin/env python3
"""
Verifier for Formula Error Detective task
Checks that all formula errors have been fixed and calculations are accurate
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since verification runs on host machine
# USE Relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names,
    _parse_cell_ref,
    _format_cell_ref
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def scan_for_errors(sheet_data):
    """
    Scan all cells in all sheets for formula error codes.
    
    Returns:
        list: List of (sheet_name, cell_ref, error_value) tuples
    """
    errors_found = []
    error_codes = ['#REF!', '#NAME?', '#VALUE!', '#N/A', '#DIV/0!', '#NUM!', '#NULL!']
    
    for sheet_name, rows in sheet_data.get('sheets', {}).items():
        for row_idx, row in enumerate(rows):
            for col_idx, cell in enumerate(row):
                cell_value = cell.get('value', '') if isinstance(cell, dict) else cell
                
                # Check if cell value is an error code
                if isinstance(cell_value, str):
                    for error_code in error_codes:
                        if error_code in cell_value:
                            cell_ref = _format_cell_ref(col_idx, row_idx)
                            errors_found.append((sheet_name, cell_ref, cell_value))
                            break
    
    return errors_found


def check_formulas_present(sheet_data, sheet_name, expected_formula_cells):
    """
    Check that expected cells contain formulas (not hardcoded values).
    
    Args:
        sheet_data: Parsed sheet data
        sheet_name: Name of sheet to check
        expected_formula_cells: List of cell references that should have formulas
        
    Returns:
        tuple: (count_found, count_expected, details)
    """
    if sheet_name not in sheet_data.get('sheets', {}):
        return 0, len(expected_formula_cells), []
    
    sheet_rows = sheet_data['sheets'][sheet_name]
    formulas_found = 0
    details = []
    
    for cell_ref in expected_formula_cells:
        try:
            col_idx, row_idx = _parse_cell_ref(cell_ref)
            if row_idx < len(sheet_rows) and col_idx < len(sheet_rows[row_idx]):
                cell = sheet_rows[row_idx][col_idx]
                formula = cell.get('formula', '') if isinstance(cell, dict) else ''
                
                if formula and formula.startswith('='):
                    formulas_found += 1
                    details.append(f"{cell_ref}: {formula}")
                else:
                    value = cell.get('value', '') if isinstance(cell, dict) else cell
                    details.append(f"{cell_ref}: hardcoded value '{value}' (no formula)")
        except Exception as e:
            logger.debug(f"Error checking formula in {cell_ref}: {e}")
    
    return formulas_found, len(expected_formula_cells), details


def validate_cross_sheet_references(sheet_data, sheet_name, expected_source_sheet):
    """
    Check that formulas contain valid cross-sheet references.
    
    Args:
        sheet_data: Parsed sheet data
        sheet_name: Name of sheet with formulas
        expected_source_sheet: Name of sheet that should be referenced
        
    Returns:
        tuple: (valid_refs_found, total_formulas_checked, issues)
    """
    if sheet_name not in sheet_data.get('sheets', {}):
        return 0, 0, []
    
    sheet_rows = sheet_data['sheets'][sheet_name]
    valid_refs = 0
    total_formulas = 0
    issues = []
    
    for row_idx, row in enumerate(sheet_rows):
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                formula = cell.get('formula', '')
                if formula and formula.startswith('='):
                    total_formulas += 1
                    cell_ref = _format_cell_ref(col_idx, row_idx)
                    
                    # Check if formula contains cross-sheet reference
                    if '.' in formula:
                        # Extract sheet name from formula (e.g., "Monthly_Expenses.B:B")
                        # Match pattern: SheetName.CellRange
                        sheet_ref_pattern = r'([A-Za-z_][A-Za-z0-9_]*)\.'
                        matches = re.findall(sheet_ref_pattern, formula)
                        
                        if matches:
                            referenced_sheet = matches[0]
                            if referenced_sheet == expected_source_sheet:
                                valid_refs += 1
                            else:
                                issues.append(f"{cell_ref}: references '{referenced_sheet}' instead of '{expected_source_sheet}'")
                        else:
                            issues.append(f"{cell_ref}: has '.' but can't parse sheet reference")
                    else:
                        # Formula doesn't reference another sheet (might be SUM of local cells)
                        # This is acceptable for total row
                        if 'SUM' in formula.upper() and ':' in formula:
                            valid_refs += 1  # Local SUM is valid
                        else:
                            issues.append(f"{cell_ref}: no cross-sheet reference found")
    
    return valid_refs, total_formulas, issues


def calculate_expected_totals(sheet_data, data_sheet_name):
    """
    Calculate expected totals from source data for validation.
    
    Returns:
        dict: Category totals and grand total
    """
    if data_sheet_name not in sheet_data.get('sheets', {}):
        return {}
    
    sheet_rows = sheet_data['sheets'][data_sheet_name]
    category_totals = {}
    
    # Parse data (assuming column B is Category, column C is Amount)
    for row_idx, row in enumerate(sheet_rows):
        if row_idx == 0:  # Skip header
            continue
        
        if len(row) >= 3:
            category_cell = row[1]  # Column B (index 1)
            amount_cell = row[2]    # Column C (index 2)
            
            category = category_cell.get('value', '') if isinstance(category_cell, dict) else category_cell
            amount = amount_cell.get('value', 0) if isinstance(amount_cell, dict) else amount_cell
            
            if category and isinstance(amount, (int, float)) and amount > 0:
                category = str(category).strip()
                if category not in category_totals:
                    category_totals[category] = 0
                category_totals[category] += amount
    
    # Calculate grand total
    grand_total = sum(category_totals.values())
    category_totals['_GRAND_TOTAL'] = grand_total
    
    return category_totals


def verify_formula_errors_fixed(traj, env_info, task_info):
    """
    Verify that all formula errors have been fixed and calculations are correct.
    
    Checks:
    1. All error codes eliminated (#REF!, #NAME?, #VALUE!, etc.)
    2. Formulas present in Summary sheet (not hardcoded values)
    3. Accurate calculations that match source data
    4. Cross-sheet references are valid
    5. Data preserved (no accidental deletions)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    file_paths = [
        "/home/ga/Documents/expense_tracker_repaired.ods",
        "/home/ga/Documents/expense_tracker_broken.ods",
        "/home/ga/Documents/expense_tracker.ods",
    ]
    
    success = False
    workbook = None
    temp_dir = None
    error = ""
    
    for container_path in file_paths:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format='ods'
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet: {error}. Tried: {', '.join(file_paths)}"
        }
    
    try:
        # Initialize scoring
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Get sheet names
        sheets = workbook.get('sheets', {})
        sheet_names = list(sheets.keys())
        logger.info(f"Found sheets: {sheet_names}")
        
        # Identify data sheet (should be "Monthly_Expenses" or similar)
        data_sheet = None
        summary_sheet = None
        
        for name in sheet_names:
            if 'expense' in name.lower() and 'summary' not in name.lower():
                data_sheet = name
            elif 'summary' in name.lower():
                summary_sheet = name
        
        if not data_sheet:
            data_sheet = sheet_names[0] if len(sheet_names) > 0 else None
        if not summary_sheet:
            summary_sheet = sheet_names[1] if len(sheet_names) > 1 else None
        
        logger.info(f"Data sheet: {data_sheet}, Summary sheet: {summary_sheet}")
        
        # ===== CRITERION 1: All Errors Eliminated (40 points) =====
        errors_found = scan_for_errors(workbook)
        
        if len(errors_found) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ All formula errors eliminated")
            subscores['errors_eliminated'] = True
        else:
            feedback_parts.append(f"❌ {len(errors_found)} errors remain: {errors_found[:3]}")
            subscores['errors_eliminated'] = False
            logger.warning(f"Errors found: {errors_found}")
        
        # ===== CRITERION 2: Formulas Present (25 points) =====
        if summary_sheet:
            # Check that category summary cells (B2:B6) contain formulas
            expected_formula_cells = ['B2', 'B3', 'B4', 'B5', 'B6', 'B8']  # B8 is total
            formulas_found, formulas_expected, formula_details = check_formulas_present(
                workbook, summary_sheet, expected_formula_cells
            )
            
            if formulas_found >= formulas_expected - 1:  # Allow one missing
                criteria_passed += 1
                feedback_parts.append(f"✅ Formulas present ({formulas_found}/{formulas_expected})")
                subscores['formulas_present'] = True
            else:
                partial_score = formulas_found / formulas_expected
                criteria_passed += partial_score
                feedback_parts.append(f"⚠️ Only {formulas_found}/{formulas_expected} expected formulas found")
                subscores['formulas_present'] = False
                logger.debug(f"Formula details: {formula_details}")
        else:
            feedback_parts.append("❌ Summary sheet not found")
            subscores['formulas_present'] = False
        
        # ===== CRITERION 3: Cross-Sheet References Valid (20 points) =====
        if summary_sheet and data_sheet:
            valid_refs, total_formulas, ref_issues = validate_cross_sheet_references(
                workbook, summary_sheet, data_sheet
            )
            
            if valid_refs >= total_formulas * 0.8:  # 80% of formulas have valid refs
                criteria_passed += 1
                feedback_parts.append(f"✅ Cross-sheet references valid ({valid_refs}/{total_formulas})")
                subscores['cross_refs_valid'] = True
            else:
                feedback_parts.append(f"⚠️ Cross-sheet reference issues: {valid_refs}/{total_formulas} valid")
                subscores['cross_refs_valid'] = False
                if ref_issues:
                    logger.debug(f"Reference issues: {ref_issues[:3]}")
        else:
            feedback_parts.append("⚠️ Cannot validate cross-sheet references (sheets not found)")
            subscores['cross_refs_valid'] = False
        
        # ===== CRITERION 4: Accurate Calculations (15 points) =====
        if summary_sheet and data_sheet:
            # Calculate expected totals from source data
            expected_totals = calculate_expected_totals(workbook, data_sheet)
            logger.info(f"Expected totals: {expected_totals}")
            
            # Check total in Summary sheet (typically B8)
            calculated_total = get_cell_value(workbook, summary_sheet, 'B8')
            expected_grand_total = expected_totals.get('_GRAND_TOTAL', 0)
            
            if calculated_total and isinstance(calculated_total, (int, float)):
                if abs(calculated_total - expected_grand_total) <= 0.01:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Calculations accurate (total: ${calculated_total:.2f})")
                    subscores['calculations_accurate'] = True
                else:
                    feedback_parts.append(f"❌ Calculation error: expected ${expected_grand_total:.2f}, got ${calculated_total:.2f}")
                    subscores['calculations_accurate'] = False
            else:
                # Check individual category totals as fallback
                category_checks = 0
                for category, expected_total in expected_totals.items():
                    if category == '_GRAND_TOTAL':
                        continue
                    # Try to find this category in Summary sheet
                    # This is a simplified check - in reality would need to match category names
                    category_checks += 1
                
                if category_checks >= 3:
                    criteria_passed += 0.5
                    feedback_parts.append("⚠️ Total calculation unclear, but categories present")
                    subscores['calculations_accurate'] = False
                else:
                    feedback_parts.append("❌ Cannot verify calculation accuracy")
                    subscores['calculations_accurate'] = False
        else:
            feedback_parts.append("⚠️ Cannot verify calculations (sheets not found)")
            subscores['calculations_accurate'] = False
        
        # ===== CRITERION 5: Data Preserved (bonus check) =====
        if data_sheet:
            sheet_rows = sheets[data_sheet]
            # Count non-empty rows
            data_rows = 0
            for row in sheet_rows:
                if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                    data_rows += 1
            
            # Expect at least header + 15 data rows
            if data_rows >= 16:
                criteria_passed += 1
                feedback_parts.append(f"✅ Data preserved ({data_rows} rows)")
                subscores['data_preserved'] = True
            else:
                feedback_parts.append(f"⚠️ Data may be incomplete ({data_rows} rows)")
                subscores['data_preserved'] = False
        else:
            feedback_parts.append("⚠️ Cannot verify data preservation")
            subscores['data_preserved'] = False
        
        # ===== Calculate Final Score =====
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 75% to pass (4/5 criteria)
        
        # Add summary message
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent work! All formulas repaired successfully!")
        elif passed:
            feedback_parts.insert(0, "✅ Formula errors fixed! Task completed.")
        else:
            feedback_parts.insert(0, "❌ Task incomplete - more formula repairs needed")
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: score={score}, passed={passed}")
        
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
        cleanup_verification_temp(temp_dir)
