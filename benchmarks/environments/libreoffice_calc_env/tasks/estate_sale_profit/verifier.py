#!/usr/bin/env python3
"""
Verifier for Estate Sale Profit Calculator task.
Checks data cleaning, conditional formulas, revenue calculation, and goal comparison.
"""

import sys
import os
import logging
import re
from typing import Dict, Any, Tuple, Optional

# Do not use /workspace/utils, since verification runs on host machine
# Use relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_calculated_column(workbook: Dict[str, Any], sheet_name: str) -> Optional[int]:
    """
    Find the column that contains calculated sale prices.
    Looks for a column with formulas that might contain IF/OR logic.
    
    Returns:
        Column index (0-based) or None if not found
    """
    try:
        sheet = workbook['sheets'][sheet_name]
        
        # Check columns E, F, G (indices 4, 5, 6) - most likely locations
        for col_idx in range(4, min(10, len(sheet[0]) if sheet else 0)):
            # Check a few rows for formulas
            has_formulas = False
            for row_idx in range(1, min(6, len(sheet))):
                if row_idx < len(sheet) and col_idx < len(sheet[row_idx]):
                    cell = sheet[row_idx][col_idx]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula and '=' in str(formula):
                        has_formulas = True
                        break
            
            if has_formulas:
                return col_idx
        
        return None
    except Exception as e:
        logger.error(f"Error finding calculated column: {e}")
        return None


def check_formula_has_conditional_logic(formula: Optional[str]) -> bool:
    """
    Check if formula contains conditional logic (IF, OR, AND).
    
    Args:
        formula: Formula string
        
    Returns:
        True if formula has conditional logic
    """
    if not formula:
        return False
    
    formula_upper = str(formula).upper()
    return 'IF(' in formula_upper or 'OR(' in formula_upper or 'AND(' in formula_upper


def check_formula_has_text_functions(formula: Optional[str]) -> bool:
    """
    Check if formula uses text parsing functions.
    
    Args:
        formula: Formula string
        
    Returns:
        True if formula has text functions
    """
    if not formula:
        return False
    
    formula_upper = str(formula).upper()
    text_functions = ['LOWER(', 'UPPER(', 'SEARCH(', 'FIND(', 'SUBSTITUTE(', 'VALUE(']
    return any(func in formula_upper for func in text_functions)


def find_total_revenue_cell(workbook: Dict[str, Any], sheet_name: str, 
                           calc_col_idx: int) -> Optional[Tuple[str, float]]:
    """
    Find cell containing total revenue calculation.
    
    Args:
        workbook: Parsed workbook data
        sheet_name: Sheet name
        calc_col_idx: Index of calculated column
        
    Returns:
        Tuple of (cell_reference, value) or None
    """
    try:
        sheet = workbook['sheets'][sheet_name]
        
        # Look for SUM formulas in the calculated column area
        # Check rows after the data (typically row 31-40 for 30 data rows)
        for row_idx in range(len(sheet) - 20, len(sheet)):
            if row_idx < len(sheet):
                for col_offset in range(-1, 3):  # Check nearby columns too
                    col_idx = calc_col_idx + col_offset
                    if col_idx >= 0 and col_idx < len(sheet[row_idx]):
                        cell = sheet[row_idx][col_idx]
                        formula = cell.get('formula') if isinstance(cell, dict) else None
                        if formula and 'SUM(' in str(formula).upper():
                            value = cell.get('value') if isinstance(cell, dict) else cell
                            cell_ref = _format_cell_ref(col_idx, row_idx)
                            logger.info(f"Found SUM formula at {cell_ref}: {formula} = {value}")
                            return (cell_ref, float(value) if value else 0)
        
        return None
    except Exception as e:
        logger.error(f"Error finding total revenue: {e}")
        return None


def find_goal_comparison_cells(workbook: Dict[str, Any], sheet_name: str) -> Optional[Dict[str, Any]]:
    """
    Find cells containing goal comparison information.
    
    Args:
        workbook: Parsed workbook data
        sheet_name: Sheet name
        
    Returns:
        Dict with goal info or None
    """
    try:
        sheet = workbook['sheets'][sheet_name]
        
        goal_info = {
            'target_found': False,
            'target_value': None,
            'comparison_found': False,
            'goal_met': None
        }
        
        # Search for cells containing "2000" or "goal" or "target"
        for row_idx, row in enumerate(sheet):
            for col_idx, cell in enumerate(row):
                value = cell.get('value') if isinstance(cell, dict) else cell
                formula = cell.get('formula') if isinstance(cell, dict) else None
                
                # Check for target amount (2000)
                if value == 2000 or str(value) == '2000':
                    goal_info['target_found'] = True
                    goal_info['target_value'] = 2000
                    logger.info(f"Found target at {_format_cell_ref(col_idx, row_idx)}")
                
                # Check for text containing "goal" or "met"
                value_str = str(value).lower() if value else ''
                if 'goal' in value_str or 'met' in value_str or 'yes' in value_str or 'no' in value_str:
                    goal_info['comparison_found'] = True
                    if 'yes' in value_str:
                        goal_info['goal_met'] = True
                    elif 'no' in value_str:
                        goal_info['goal_met'] = False
                    logger.info(f"Found goal comparison at {_format_cell_ref(col_idx, row_idx)}: {value}")
        
        return goal_info if goal_info['target_found'] or goal_info['comparison_found'] else None
    except Exception as e:
        logger.error(f"Error finding goal comparison: {e}")
        return None


def check_for_formula_errors(workbook: Dict[str, Any], sheet_name: str) -> bool:
    """
    Check if any cells contain formula errors.
    
    Args:
        workbook: Parsed workbook data
        sheet_name: Sheet name
        
    Returns:
        True if errors found
    """
    try:
        sheet = workbook['sheets'][sheet_name]
        error_indicators = ['#VALUE!', '#REF!', '#DIV/0!', '#NAME?', '#N/A', '#NUM!', '#NULL!']
        
        for row in sheet:
            for cell in row:
                value = cell.get('value') if isinstance(cell, dict) else cell
                if value and any(err in str(value) for err in error_indicators):
                    logger.warning(f"Found formula error: {value}")
                    return True
        
        return False
    except Exception as e:
        logger.error(f"Error checking for formula errors: {e}")
        return False


def verify_estate_sale(traj, env_info, task_info):
    """
    Verify estate sale profit calculator task completion.
    
    Checks:
    1. Calculated column created with formulas
    2. Formulas contain conditional logic (IF/OR)
    3. Total revenue calculated
    4. Goal comparison present ($2,000 target)
    5. Calculation accuracy (expected ~$2,150)
    6. No formula errors
    7. Clear presentation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try ODS first, then fall back to CSV
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, container_path in [
        ('ods', '/home/ga/Documents/estate_sale_results.ods'),
        ('ods', '/home/ga/Documents/estate_sale_inventory.ods'),
        ('csv', '/home/ga/Documents/estate_sale_inventory.csv')
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Criterion 1: Calculated column created with formulas
        calc_col_idx = find_calculated_column(workbook, sheet_name)
        has_calc_column = calc_col_idx is not None
        
        if has_calc_column:
            criteria_passed += 1
            feedback_parts.append(f"✅ Calculated column found (column {chr(65 + calc_col_idx)})")
        else:
            feedback_parts.append("❌ No calculated column with formulas found")
        
        # Criterion 2: Formulas contain conditional logic
        has_conditional = False
        has_text_parsing = False
        
        if has_calc_column:
            # Check a few formula cells
            sheet = workbook['sheets'][sheet_name]
            for row_idx in range(1, min(6, len(sheet))):
                if row_idx < len(sheet) and calc_col_idx < len(sheet[row_idx]):
                    cell = sheet[row_idx][calc_col_idx]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if check_formula_has_conditional_logic(formula):
                        has_conditional = True
                    if check_formula_has_text_functions(formula):
                        has_text_parsing = True
                    if has_conditional:
                        break
        
        if has_conditional:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas contain conditional logic (IF/OR)")
        else:
            feedback_parts.append("❌ Formulas missing conditional logic")
        
        # Criterion 3: Total revenue calculated
        total_revenue = None
        has_total = False
        
        if has_calc_column:
            total_result = find_total_revenue_cell(workbook, sheet_name, calc_col_idx)
            if total_result:
                has_total = True
                total_revenue = total_result[1]
                criteria_passed += 1
                feedback_parts.append(f"✅ Total revenue calculated: ${total_revenue:.2f}")
            else:
                feedback_parts.append("❌ Total revenue SUM formula not found")
        else:
            feedback_parts.append("❌ Cannot check total without calculated column")
        
        # Criterion 4: Goal comparison present
        goal_info = find_goal_comparison_cells(workbook, sheet_name)
        has_goal_comparison = goal_info is not None and (goal_info.get('target_found') or goal_info.get('comparison_found'))
        
        if has_goal_comparison:
            criteria_passed += 1
            if goal_info.get('goal_met') is not None:
                result = "YES" if goal_info['goal_met'] else "NO"
                feedback_parts.append(f"✅ Goal comparison present (Result: {result})")
            else:
                feedback_parts.append("✅ Goal target ($2,000) found")
        else:
            feedback_parts.append("❌ Goal comparison not found (should compare against $2,000)")
        
        # Criterion 5: Calculation accuracy
        # Expected total is approximately $2,150 based on the CSV data
        expected_total = 2150
        tolerance = 100  # Allow ±$100 for different interpretations
        
        calc_accurate = False
        if total_revenue is not None:
            if abs(total_revenue - expected_total) <= tolerance:
                criteria_passed += 1
                calc_accurate = True
                diff = total_revenue - 2000  # Compare to goal
                feedback_parts.append(f"✅ Calculation accurate (${diff:.2f} {'over' if diff > 0 else 'under'} goal)")
            else:
                feedback_parts.append(f"⚠️ Total seems off: ${total_revenue:.2f} (expected ~${expected_total})")
        else:
            feedback_parts.append("❌ Cannot verify calculation accuracy")
        
        # Criterion 6: No formula errors
        has_errors = check_for_formula_errors(workbook, sheet_name)
        if not has_errors:
            criteria_passed += 1
            feedback_parts.append("✅ No formula errors detected")
        else:
            feedback_parts.append("❌ Formula errors found (#VALUE!, #REF!, etc.)")
        
        # Criterion 7: Clear presentation
        # Check if results are well-labeled and easy to find
        clear_presentation = has_total and has_goal_comparison
        if clear_presentation:
            criteria_passed += 1
            feedback_parts.append("✅ Results clearly presented")
        else:
            feedback_parts.append("⚠️ Results could be more clearly labeled")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 5/7 criteria needed
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent data cleaning and analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Task completed successfully")
        else:
            feedback_parts.insert(0, "❌ Task requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "calculated_column": has_calc_column,
                "conditional_logic": has_conditional,
                "total_revenue": has_total,
                "goal_comparison": has_goal_comparison,
                "calculation_accurate": calc_accurate,
                "no_errors": not has_errors,
                "clear_presentation": clear_presentation
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


def _format_cell_ref(col_idx: int, row_idx: int) -> str:
    """Format cell reference from indices (0-based)"""
    col_str = ''
    col = col_idx + 1
    
    while col > 0:
        col -= 1
        col_str = chr(ord('A') + (col % 26)) + col_str
        col //= 26
    
    return f"{col_str}{row_idx + 1}"
