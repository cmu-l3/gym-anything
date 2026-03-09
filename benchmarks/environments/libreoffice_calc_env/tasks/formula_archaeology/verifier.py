#!/usr/bin/env python3
"""
Verifier for Formula Archaeology task
Checks that broken formulas have been debugged and fixed correctly
"""

import sys
import os
import logging
import re

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_for_ref_errors(workbook, sheet_name):
    """
    Check if any cells contain #REF! errors
    Returns: (has_errors: bool, error_cells: list)
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return True, []
    
    error_cells = []
    rows = sheets[sheet_name]
    
    for row_idx, row in enumerate(rows, start=1):
        for col_idx, cell in enumerate(row):
            value = cell.get('value') if isinstance(cell, dict) else cell
            if value and isinstance(value, str):
                if '#REF!' in value or '#VALUE!' in value or '#NAME?' in value:
                    col_letter = chr(ord('A') + col_idx)
                    error_cells.append(f"{col_letter}{row_idx}")
    
    return len(error_cells) > 0, error_cells


def calculate_expected_category_totals(workbook, sheet_name):
    """
    Calculate expected category totals by manually summing expense data
    Returns: dict of {category: total}
    """
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return {}
    
    rows = sheets[sheet_name]
    
    # Sum expenses by category (rows 5-14, columns B=category, D=amount)
    category_totals = {
        "Office Supplies": 0,
        "Travel": 0,
        "Utilities": 0,
        "Marketing": 0
    }
    
    # Rows 5-14 are indices 4-13 (0-based)
    for row_idx in range(4, 14):
        if row_idx < len(rows):
            row = rows[row_idx]
            if len(row) > 3:
                # Column B (index 1) = category, Column D (index 3) = amount
                category_cell = row[1] if len(row) > 1 else {}
                amount_cell = row[3] if len(row) > 3 else {}
                
                category = category_cell.get('value') if isinstance(category_cell, dict) else category_cell
                amount = amount_cell.get('value') if isinstance(amount_cell, dict) else amount_cell
                
                if category in category_totals and amount:
                    try:
                        category_totals[category] += float(amount)
                    except (ValueError, TypeError):
                        pass
    
    return category_totals


def verify_category_totals(workbook, sheet_name, expected_totals, tolerance=0.01):
    """
    Verify category totals in row 17 (B17, C17, D17, E17)
    Returns: (all_correct: bool, results: dict)
    """
    results = {}
    
    # Row 17, columns B-E (indices: row 16, cols 1-4)
    category_columns = {
        'B17': ('Office Supplies', 1),
        'C17': ('Travel', 2),
        'D17': ('Utilities', 3),
        'E17': ('Marketing', 4)
    }
    
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False, results
    
    rows = sheets[sheet_name]
    if len(rows) < 17:
        return False, results
    
    row_17 = rows[16]  # 0-based index
    
    all_correct = True
    for cell_ref, (category, col_idx) in category_columns.items():
        if col_idx < len(row_17):
            cell = row_17[col_idx]
            actual = cell.get('value') if isinstance(cell, dict) else cell
            expected = expected_totals.get(category, 0)
            
            try:
                actual_float = float(actual) if actual is not None else 0
                expected_float = float(expected)
                
                is_correct = abs(actual_float - expected_float) <= tolerance
                results[category] = {
                    'correct': is_correct,
                    'expected': expected_float,
                    'actual': actual_float,
                    'cell': cell_ref
                }
                
                if not is_correct:
                    all_correct = False
            except (ValueError, TypeError):
                results[category] = {
                    'correct': False,
                    'expected': expected,
                    'actual': actual,
                    'cell': cell_ref
                }
                all_correct = False
        else:
            results[category] = {
                'correct': False,
                'expected': expected_totals.get(category, 0),
                'actual': None,
                'cell': cell_ref
            }
            all_correct = False
    
    return all_correct, results


def verify_variance_formulas(workbook, sheet_name, expected_variances, tolerance=0.01):
    """
    Verify variance calculations in row 22 (B22-E22)
    Variance should be: Total (row 17) - Budget (row 19)
    Returns: (all_correct: bool, results: dict)
    """
    results = {}
    
    # Row 22, columns B-E for variances
    variance_columns = {
        'B22': ('Office Supplies', 1),
        'C22': ('Travel', 2),
        'D22': ('Utilities', 3),
        'E22': ('Marketing', 4)
    }
    
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False, results
    
    rows = sheets[sheet_name]
    if len(rows) < 22:
        return False, results
    
    row_22 = rows[21]  # 0-based index
    
    all_correct = True
    for cell_ref, (category, col_idx) in variance_columns.items():
        if col_idx < len(row_22):
            cell = row_22[col_idx]
            actual = cell.get('value') if isinstance(cell, dict) else cell
            expected = expected_variances.get(category, 0)
            
            try:
                actual_float = float(actual) if actual is not None else 0
                expected_float = float(expected)
                
                is_correct = abs(actual_float - expected_float) <= tolerance
                results[category] = {
                    'correct': is_correct,
                    'expected': expected_float,
                    'actual': actual_float,
                    'cell': cell_ref
                }
                
                if not is_correct:
                    all_correct = False
            except (ValueError, TypeError):
                results[category] = {
                    'correct': False,
                    'expected': expected,
                    'actual': actual,
                    'cell': cell_ref
                }
                all_correct = False
        else:
            results[category] = {
                'correct': False,
                'expected': expected_variances.get(category, 0),
                'actual': None,
                'cell': cell_ref
            }
            all_correct = False
    
    return all_correct, results


def verify_warning_formulas(workbook, sheet_name, expected_warnings):
    """
    Verify status warnings in row 25 (B25-E25)
    Should show "OVER BUDGET" if variance > 0, "OK" otherwise
    Returns: (all_correct: bool, results: dict)
    """
    results = {}
    
    # Row 25, columns B-E for warnings
    warning_columns = {
        'B25': ('Office Supplies', 1),
        'C25': ('Travel', 2),
        'D25': ('Utilities', 3),
        'E25': ('Marketing', 4)
    }
    
    sheets = workbook.get('sheets', {})
    if sheet_name not in sheets:
        return False, results
    
    rows = sheets[sheet_name]
    if len(rows) < 25:
        return False, results
    
    row_25 = rows[24]  # 0-based index
    
    all_correct = True
    for cell_ref, (category, col_idx) in warning_columns.items():
        if col_idx < len(row_25):
            cell = row_25[col_idx]
            actual = cell.get('value') if isinstance(cell, dict) else cell
            expected = expected_warnings.get(category, "OK")
            
            actual_str = str(actual).strip().upper() if actual else ""
            expected_str = str(expected).strip().upper()
            
            is_correct = actual_str == expected_str
            results[category] = {
                'correct': is_correct,
                'expected': expected,
                'actual': actual,
                'cell': cell_ref
            }
            
            if not is_correct:
                all_correct = False
        else:
            results[category] = {
                'correct': False,
                'expected': expected_warnings.get(category, "OK"),
                'actual': None,
                'cell': cell_ref
            }
            all_correct = False
    
    return all_correct, results


def verify_formula_archaeology(traj, env_info, task_info):
    """
    Verify formula archaeology task completion.
    
    Checks:
    1. No #REF! errors remain
    2. Category totals are correct (Office Supplies=450, Travel=1250, Utilities=320, Marketing=890)
    3. Budget variances are correct (actual - budget)
    4. Over-budget warnings display correctly
    5. Formulas (not just values) are present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/expenses_broken.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet (should be "Expenses")
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]

        criteria_passed = 0
        max_criteria = 6
        feedback_parts = []

        # Expected values
        expected_totals = {
            "Office Supplies": 450.0,
            "Travel": 1250.0,
            "Utilities": 320.0,
            "Marketing": 890.0
        }
        
        expected_budgets = {
            "Office Supplies": 500.0,
            "Travel": 1100.0,
            "Utilities": 400.0,
            "Marketing": 800.0
        }
        
        expected_variances = {
            "Office Supplies": -50.0,
            "Travel": 150.0,
            "Utilities": -80.0,
            "Marketing": 90.0
        }
        
        expected_warnings = {
            "Office Supplies": "OK",
            "Travel": "OVER BUDGET",
            "Utilities": "OK",
            "Marketing": "OVER BUDGET"
        }

        # Criterion 1: No #REF! errors (2 points)
        has_errors, error_cells = check_for_ref_errors(workbook, sheet_name)
        if not has_errors:
            criteria_passed += 2
            feedback_parts.append("✅ No formula errors (#REF!, etc.)")
        else:
            feedback_parts.append(f"❌ Formula errors found in cells: {', '.join(error_cells[:5])}")

        # Criterion 2: Category totals correct (2 points)
        totals_correct, total_results = verify_category_totals(workbook, sheet_name, expected_totals)
        if totals_correct:
            criteria_passed += 2
            feedback_parts.append("✅ All category totals correct")
        else:
            incorrect_cats = [cat for cat, res in total_results.items() if not res['correct']]
            if len(incorrect_cats) <= 1:
                criteria_passed += 1  # Partial credit
                feedback_parts.append(f"⚠️ Most category totals correct (issue: {incorrect_cats[0]})")
            else:
                feedback_parts.append(f"❌ Category totals incorrect: {', '.join(incorrect_cats[:2])}")

        # Criterion 3: Budget variances correct (1 point)
        variances_correct, variance_results = verify_variance_formulas(workbook, sheet_name, expected_variances)
        if variances_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Budget variances calculated correctly")
        else:
            incorrect_vars = [cat for cat, res in variance_results.items() if not res['correct']]
            feedback_parts.append(f"❌ Variance formulas incorrect: {', '.join(incorrect_vars[:2])}")

        # Criterion 4: Warning formulas correct (1 point)
        warnings_correct, warning_results = verify_warning_formulas(workbook, sheet_name, expected_warnings)
        if warnings_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Over-budget warnings correct")
        else:
            incorrect_warns = [cat for cat, res in warning_results.items() if not res['correct']]
            feedback_parts.append(f"❌ Warning formulas incorrect: {', '.join(incorrect_warns[:2])}")
        
        # Calculate score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 85
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "no_errors": not has_errors,
                "totals_correct": totals_correct,
                "variances_correct": variances_correct,
                "warnings_correct": warnings_correct
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
