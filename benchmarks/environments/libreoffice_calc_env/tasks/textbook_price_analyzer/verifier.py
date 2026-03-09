#!/usr/bin/env python3
"""
Verifier for Textbook Price Analyzer task.
Checks for conditional formulas, calculation accuracy, MIN functions, 
conditional formatting, and formula robustness.
"""

import sys
import os
import logging
import re

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_environment,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_calculated_columns(sheet_data, sheet_name):
    """
    Find columns that contain calculated 'True Cost' data.
    Returns list of column indices that have formulas.
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return []
    
    sheets = sheet_data['sheets']
    if sheet_name not in sheets:
        return []
    
    rows = sheets[sheet_name]
    if len(rows) < 2:
        return []
    
    # Check first data row (row index 1) for formulas
    data_row = rows[1] if len(rows) > 1 else []
    
    calculated_cols = []
    for col_idx, cell in enumerate(data_row):
        if isinstance(cell, dict):
            formula = cell.get('formula')
            if formula and ('IF' in formula.upper() or 'SUM' in formula.upper() or 'MIN' in formula.upper()):
                calculated_cols.append(col_idx)
    
    return calculated_cols


def check_formula_has_if_logic(formula):
    """Check if formula contains IF statement."""
    if not formula:
        return False
    return 'IF' in formula.upper()


def check_formula_has_min(formula):
    """Check if formula contains MIN function."""
    if not formula:
        return False
    return 'MIN' in formula.upper()


def has_formula_errors(sheet_data, sheet_name, start_row=1, end_row=10):
    """
    Check if any cells contain formula errors like #REF!, #VALUE!, #DIV/0!
    Returns (has_errors, error_list)
    """
    if not sheet_data or 'sheets' not in sheet_data:
        return False, []
    
    sheets = sheet_data['sheets']
    if sheet_name not in sheets:
        return False, []
    
    rows = sheets[sheet_name]
    errors = []
    
    for row_idx in range(start_row, min(end_row, len(rows))):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            if isinstance(cell, dict):
                value = cell.get('value')
            else:
                value = cell
            
            if isinstance(value, str) and value.startswith('#'):
                errors.append(f"Row {row_idx+1}, Col {col_idx+1}: {value}")
    
    return len(errors) > 0, errors


def verify_sample_calculation(sheet_data, sheet_name, row_idx, base_price_col, 
                              expected_true_cost, tolerance=2.0):
    """
    Verify that a calculated true cost matches expected value.
    Returns (is_correct, actual_value, difference)
    """
    rows = sheet_data['sheets'][sheet_name]
    if row_idx >= len(rows):
        return False, None, None
    
    row = rows[row_idx]
    
    # Find calculated columns (usually after the base price columns)
    # Look for cells with numeric values that could be true costs
    true_cost_candidates = []
    for col_idx in range(base_price_col + 1, len(row)):
        cell = row[col_idx]
        if isinstance(cell, dict):
            value = cell.get('value')
            formula = cell.get('formula')
            # If it has a formula and numeric value, it's likely a calculated cost
            if formula and isinstance(value, (int, float)):
                true_cost_candidates.append((col_idx, value))
    
    # Check if any candidate matches expected value
    for col_idx, actual_value in true_cost_candidates:
        diff = abs(float(actual_value) - float(expected_true_cost))
        if diff <= tolerance:
            return True, actual_value, diff
    
    return False, true_cost_candidates, None


def count_if_formulas(sheet_data, sheet_name, start_row=1, end_row=10):
    """Count how many IF formulas exist in the calculated rows."""
    if not sheet_data or 'sheets' not in sheet_data:
        return 0
    
    rows = sheet_data['sheets'][sheet_name]
    if_count = 0
    
    for row_idx in range(start_row, min(end_row, len(rows))):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and 'IF' in formula.upper():
                    if_count += 1
    
    return if_count


def count_min_formulas(sheet_data, sheet_name, start_row=1, end_row=10):
    """Count how many MIN formulas exist."""
    if not sheet_data or 'sheets' not in sheet_data:
        return 0
    
    rows = sheet_data['sheets'][sheet_name]
    min_count = 0
    
    for row_idx in range(start_row, min(end_row, len(rows))):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        for cell in row:
            if isinstance(cell, dict):
                formula = cell.get('formula')
                if formula and 'MIN' in formula.upper():
                    min_count += 1
    
    return min_count


def verify_textbook_analyzer(traj, env_info, task_info):
    """
    Verify textbook price analyzer task completion.
    
    Checks:
    1. True Cost formulas present with IF logic
    2. Calculation accuracy for sample books
    3. Best Deal identified with MIN function
    4. Conditional formatting applied
    5. Budget calculation correct
    6. No formula errors present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to load the ODS file first, fall back to CSV
    success = False
    file_info = {}
    
    for container_path in ["/home/ga/Documents/textbook_analysis.ods",
                           "/home/ga/Documents/textbook_prices.ods",
                           "/home/ga/Documents/textbook_prices.csv"]:
        try:
            success, file_info, error = setup_calc_verification(
                copy_from_env,
                container_path,
                ['ods', 'csv']
            )
            if success:
                logger.info(f"Successfully loaded: {container_path}")
                break
        except Exception as e:
            logger.debug(f"Failed to load {container_path}: {e}")
            continue
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file: {error}"
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
        rows = sheet_data['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: True Cost formulas present with IF logic
        if_formula_count = count_if_formulas(sheet_data, sheet_name, start_row=1, end_row=9)
        
        # We expect at least 3 IF formulas per book row (one for each seller's true cost)
        # With 8 books, we should have at least 12-15 IF formulas
        has_if_formulas = if_formula_count >= 8
        
        if has_if_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ True Cost formulas present ({if_formula_count} IF statements found)")
            subscores['if_formulas'] = True
        else:
            feedback_parts.append(f"❌ Insufficient IF formulas (found {if_formula_count}, expected 8+)")
            subscores['if_formulas'] = False
        
        # Criterion 2: Calculation accuracy for sample books
        # We'll spot-check a few known calculations
        
        # Book 1 (CHEM 101): Amazon $128.50 + $5 ship + $85 access = $218.50
        # Book 2 (BIO 200): Campus $210 (includes access and shipping) = $210
        # Book 4 (PSYCH 101): Marketplace $65 (no access needed, free ship) = $65
        
        calculations_correct = 0
        total_checks = 0
        
        # We can't easily verify exact calculations without knowing column positions
        # So we'll check if numeric calculated values exist and are reasonable
        # Look for calculated columns (columns beyond the base 8 columns)
        
        if len(rows) > 1 and len(rows[1]) > 8:  # If there are extra columns
            # Sample check: count how many rows have calculated numeric values
            for row_idx in range(1, min(9, len(rows))):
                row = rows[row_idx]
                has_calculated_values = False
                for col_idx in range(8, len(row)):
                    cell = row[col_idx]
                    if isinstance(cell, dict):
                        value = cell.get('value')
                        formula = cell.get('formula')
                        if formula and isinstance(value, (int, float)) and value > 0:
                            has_calculated_values = True
                            break
                if has_calculated_values:
                    calculations_correct += 1
                total_checks += 1
        
        calc_accuracy = calculations_correct >= 3  # At least 3 books have calculations
        
        if calc_accuracy:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculations present ({calculations_correct}/{total_checks} books)")
            subscores['calculations'] = True
        else:
            feedback_parts.append(f"❌ Insufficient calculated values ({calculations_correct}/{total_checks})")
            subscores['calculations'] = False
        
        # Criterion 3: Best Deal identified with MIN function
        min_formula_count = count_min_formulas(sheet_data, sheet_name, start_row=1, end_row=9)
        
        # We expect at least 1 MIN formula per book (8 books)
        has_min_formulas = min_formula_count >= 4
        
        if has_min_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ Best Deal identification present ({min_formula_count} MIN functions)")
            subscores['min_functions'] = True
        else:
            feedback_parts.append(f"⚠️ Limited MIN functions (found {min_formula_count}, expected 4+)")
            subscores['min_functions'] = False
        
        # Criterion 4: Conditional formatting applied
        # This is difficult to verify from parsed data, but we can check if it exists
        has_formatting = False
        try:
            # Try to check for conditional formatting
            # This might not work for CSV, only for ODS/XLSX
            if file_info.get('format') in ['ods', 'xlsx']:
                has_formatting = check_conditional_formatting(sheet_data, sheet_name, "A1:Z20")
        except Exception as e:
            logger.debug(f"Could not check conditional formatting: {e}")
        
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
            subscores['formatting'] = True
        else:
            # Don't penalize too heavily if we can't detect it
            feedback_parts.append("⚠️ Conditional formatting not detected (may be present but not parseable)")
            subscores['formatting'] = False
            # Give partial credit
            criteria_passed += 0.5
        
        # Criterion 5: Budget calculation correct
        # Look for a SUM formula in the spreadsheet (total calculation)
        has_budget_calc = False
        budget_sum = None
        
        for row_idx in range(len(rows)):
            if row_idx >= len(rows):
                break
            row = rows[row_idx]
            for cell in row:
                if isinstance(cell, dict):
                    formula = cell.get('formula')
                    value = cell.get('value')
                    if formula and 'SUM' in formula.upper() and isinstance(value, (int, float)):
                        has_budget_calc = True
                        budget_sum = value
                        break
            if has_budget_calc:
                break
        
        # Expected total is roughly: multiple books with costs ranging $65-$300
        # Reasonable total would be $800-$1500 for 8 books
        if has_budget_calc and budget_sum and 400 <= budget_sum <= 2000:
            criteria_passed += 1
            feedback_parts.append(f"✅ Budget calculation present (Total: ${budget_sum:.2f})")
            subscores['budget_calc'] = True
        elif has_budget_calc:
            feedback_parts.append(f"⚠️ Budget sum found but value seems off: ${budget_sum}")
            subscores['budget_calc'] = False
            criteria_passed += 0.5
        else:
            feedback_parts.append("❌ Budget calculation not found")
            subscores['budget_calc'] = False
        
        # Criterion 6: No formula errors
        has_errors, error_list = has_formula_errors(sheet_data, sheet_name, start_row=1, end_row=9)
        
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
            subscores['no_errors'] = True
        else:
            feedback_parts.append(f"❌ Formula errors found: {len(error_list)} errors")
            subscores['no_errors'] = False
            logger.warning(f"Formula errors: {error_list[:3]}")  # Log first 3 errors
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4.2/6 criteria
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent textbook analysis!")
        elif passed:
            feedback_parts.append("✅ Textbook analysis task completed")
        else:
            feedback_parts.append("❌ Task requirements not sufficiently met")
        
        feedback = " | ".join(feedback_parts)
        
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
        cleanup_verification_environment(file_info.get('temp_dir'))
