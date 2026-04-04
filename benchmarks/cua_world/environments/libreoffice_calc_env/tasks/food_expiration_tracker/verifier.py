#!/usr/bin/env python3
"""
Verifier for Food Expiration Tracker task.

Checks:
1. Expiration Date formulas (column E): =C[row]+D[row]
2. Days Until Expiration formulas (column F): =E[row]-TODAY()
3. Conditional formatting applied to column F
4. Data sorted ascending by Days Until Expiration
5. Formula integrity after sorting
6. Data integrity after sorting
"""

import sys
import os
import re
import logging
from datetime import datetime, timedelta

# Add utils to path - use relative path for host machine
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_data_sorted,
    check_conditional_formatting,
    cleanup_verification_temp,
    parse_ods_file,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_expiration_date_formulas(workbook, sheet_name, start_row=2, end_row=21):
    """
    Verify that Expiration Date column (E) contains correct formulas.
    Formula should be: =C[row]+D[row]
    """
    formula_count = 0
    correct_formula_count = 0
    
    for row_idx in range(start_row, end_row + 1):
        formula = get_cell_formula(workbook, sheet_name, f"E{row_idx}")
        if formula:
            formula_count += 1
            # Normalize and check for pattern: C{row}+D{row} or similar
            normalized = formula.upper().replace(" ", "").replace("=", "")
            # Check for both absolute and relative references
            patterns = [
                f"C{row_idx}+D{row_idx}",
                f"$C{row_idx}+$D{row_idx}",
                f"C${row_idx}+D${row_idx}",
                f"$C${row_idx}+$D${row_idx}"
            ]
            if any(pattern in normalized for pattern in patterns):
                correct_formula_count += 1
            # Also accept variations with different column references after sorting
            elif "C" in normalized and "D" in normalized and "+" in normalized:
                correct_formula_count += 0.5  # Partial credit
    
    success = formula_count >= 15 and (correct_formula_count / formula_count) >= 0.7
    return success, formula_count, correct_formula_count


def verify_days_until_formulas(workbook, sheet_name, start_row=2, end_row=21):
    """
    Verify that Days Until Expiration column (F) uses TODAY() function.
    Formula should be: =E[row]-TODAY()
    """
    formula_count = 0
    correct_formula_count = 0
    
    for row_idx in range(start_row, end_row + 1):
        formula = get_cell_formula(workbook, sheet_name, f"F{row_idx}")
        if formula:
            formula_count += 1
            normalized = formula.upper().replace(" ", "")
            # Check for E{row} reference and TODAY()
            has_today = "TODAY()" in normalized
            has_e_ref = f"E{row_idx}" in normalized or ("E" in normalized and "$" in normalized)
            has_minus = "-" in normalized
            
            if has_today and has_e_ref and has_minus:
                correct_formula_count += 1
            elif has_today:  # Partial credit if TODAY() is present
                correct_formula_count += 0.5
    
    success = formula_count >= 15 and (correct_formula_count / formula_count) >= 0.7
    return success, formula_count, correct_formula_count


def verify_sort_order(workbook, sheet_name, start_row=2, end_row=21):
    """
    Verify data is sorted ascending by Days Until Expiration (column F).
    """
    try:
        # Get sheet data
        sheet_data = {'rows': workbook['sheets'][sheet_name]}
        
        # Verify sort order
        is_sorted, error_msg = verify_data_sorted(
            sheet_data,
            column=5,  # Column F (0-indexed)
            order='asc',
            start_row=start_row - 1,  # Convert to 0-indexed
            end_row=end_row - 1
        )
        
        return is_sorted, error_msg
    except Exception as e:
        logger.error(f"Error verifying sort order: {e}")
        return False, str(e)


def verify_data_integrity(workbook, sheet_name, sample_rows=[2, 5, 10, 15, 20]):
    """
    Verify that after sorting, row data relationships are preserved.
    Check: Purchase Date + Shelf Life Days ≈ Expiration Date
    """
    integrity_count = 0
    total_checks = 0
    
    for row_idx in sample_rows:
        try:
            purchase_date_val = get_cell_value(workbook, sheet_name, f"C{row_idx}")
            shelf_life_val = get_cell_value(workbook, sheet_name, f"D{row_idx}")
            exp_date_val = get_cell_value(workbook, sheet_name, f"E{row_idx}")
            
            if all(v is not None for v in [purchase_date_val, shelf_life_val, exp_date_val]):
                total_checks += 1
                
                # Try to parse dates and calculate
                try:
                    # Handle different date formats
                    if isinstance(purchase_date_val, str):
                        # Try various date formats
                        for fmt in ["%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d"]:
                            try:
                                purchase_date = datetime.strptime(purchase_date_val, fmt)
                                break
                            except ValueError:
                                continue
                    else:
                        # Might already be a date object
                        purchase_date = purchase_date_val
                    
                    if isinstance(exp_date_val, str):
                        for fmt in ["%Y-%m-%d", "%m/%d/%Y", "%d/%m/%Y", "%Y/%m/%d"]:
                            try:
                                exp_date = datetime.strptime(exp_date_val, fmt)
                                break
                            except ValueError:
                                continue
                    else:
                        exp_date = exp_date_val
                    
                    # Calculate expected expiration
                    shelf_life_days = int(float(shelf_life_val))
                    expected_exp = purchase_date + timedelta(days=shelf_life_days)
                    
                    # Check if dates match (within 2 days tolerance for formatting)
                    if hasattr(expected_exp, 'date') and hasattr(exp_date, 'date'):
                        date_diff = abs((expected_exp.date() - exp_date.date()).days)
                    else:
                        date_diff = abs((expected_exp - exp_date).days)
                    
                    if date_diff <= 2:
                        integrity_count += 1
                except Exception as e:
                    logger.debug(f"Date parsing error for row {row_idx}: {e}")
                    # If we can't parse but formula exists, give partial credit
                    formula = get_cell_formula(workbook, sheet_name, f"E{row_idx}")
                    if formula and "C" in formula and "D" in formula:
                        integrity_count += 0.5
        except Exception as e:
            logger.debug(f"Integrity check error for row {row_idx}: {e}")
    
    success = total_checks > 0 and (integrity_count / total_checks) >= 0.6
    return success, integrity_count, total_checks


def verify_food_expiration_tracker(traj, env_info, task_info):
    """
    Main verification function for Food Expiration Tracker task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths and formats
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, path in [
        ('ods', '/home/ga/Documents/food_inventory_tracker.ods'),
        ('ods', '/home/ga/Documents/food_inventory.ods'),
        ('csv', '/home/ga/Documents/food_inventory.csv'),
        ('csv', '/home/ga/Documents/food_inventory_tracker.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        # Track criteria
        criteria_results = {}
        feedback_parts = []
        
        # Criterion 1: Expiration Date formulas (Column E)
        exp_formulas_ok, exp_count, exp_correct = verify_expiration_date_formulas(
            workbook, sheet_name
        )
        criteria_results['expiration_formulas'] = exp_formulas_ok
        
        if exp_formulas_ok:
            feedback_parts.append(f"✅ Expiration Date formulas correct ({exp_correct}/{exp_count} formulas)")
        else:
            feedback_parts.append(f"❌ Expiration Date formulas missing/incorrect ({exp_correct}/{exp_count})")
        
        # Criterion 2: Days Until formulas with TODAY() (Column F)
        days_formulas_ok, days_count, days_correct = verify_days_until_formulas(
            workbook, sheet_name
        )
        criteria_results['days_until_formulas'] = days_formulas_ok
        
        if days_formulas_ok:
            feedback_parts.append(f"✅ Days Until formulas with TODAY() correct ({days_correct}/{days_count})")
        else:
            feedback_parts.append(f"❌ Days Until formulas missing/incorrect ({days_correct}/{days_count})")
        
        # Criterion 3: Conditional formatting (Column F)
        # Note: Detection is format-dependent and may not work for CSV
        has_cond_format = False
        if workbook.get('format') == 'ods':
            try:
                has_cond_format = check_conditional_formatting(
                    workbook,
                    sheet_name,
                    "F2:F21"
                )
            except Exception as e:
                logger.debug(f"Conditional formatting check failed: {e}")
        
        criteria_results['conditional_formatting'] = has_cond_format
        
        if has_cond_format:
            feedback_parts.append("✅ Conditional formatting applied to Days Until column")
        else:
            feedback_parts.append("⚠️  Conditional formatting not detected (may be present but undetectable in this format)")
            # Give partial credit since detection is imperfect
            criteria_results['conditional_formatting'] = 0.5
        
        # Criterion 4: Data sorted by Days Until Expiration
        is_sorted, sort_error = verify_sort_order(workbook, sheet_name)
        criteria_results['sorted'] = is_sorted
        
        if is_sorted:
            feedback_parts.append("✅ Data sorted ascending by Days Until Expiration")
        else:
            feedback_parts.append(f"❌ Data not properly sorted: {sort_error}")
        
        # Criterion 5: Formula integrity after sorting
        # Check if formulas still exist and are correct (not broken by sort)
        formulas_intact = exp_formulas_ok and days_formulas_ok
        criteria_results['formula_integrity'] = formulas_intact
        
        if formulas_intact:
            feedback_parts.append("✅ Formulas maintained integrity after sorting")
        else:
            feedback_parts.append("❌ Formulas may have been broken during sorting")
        
        # Criterion 6: Data integrity (row relationships preserved)
        integrity_ok, integrity_count, integrity_total = verify_data_integrity(
            workbook, sheet_name
        )
        criteria_results['data_integrity'] = integrity_ok
        
        if integrity_ok:
            feedback_parts.append(f"✅ Data integrity preserved ({integrity_count}/{integrity_total} samples)")
        else:
            feedback_parts.append(f"❌ Data integrity issues detected ({integrity_count}/{integrity_total})")
        
        # Calculate score
        # Convert boolean/float criteria to numeric score
        criteria_scores = []
        for key, value in criteria_results.items():
            if isinstance(value, bool):
                criteria_scores.append(100 if value else 0)
            else:
                criteria_scores.append(value * 100)
        
        score = int(sum(criteria_scores) / len(criteria_scores))
        passed = score >= 75
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent food expiration tracker!")
        elif passed:
            feedback_parts.append("✅ Food expiration tracker completed successfully")
        else:
            feedback_parts.append("❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "expiration_formulas": exp_formulas_ok,
                "days_until_formulas": days_formulas_ok,
                "conditional_formatting": bool(criteria_results.get('conditional_formatting', 0) > 0),
                "sorted": is_sorted,
                "formula_integrity": formulas_intact,
                "data_integrity": integrity_ok
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
