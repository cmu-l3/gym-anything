#!/usr/bin/env python3
"""
Verifier for SNAP Expense Statement task

This verifier checks that the agent correctly:
1. Created a structured expense statement spreadsheet
2. Used a SUM formula (not hard-coded total)
3. Entered accurate expense data from the notes
4. Included all required expense categories
5. Applied appropriate formatting
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_file_in_container(copy_from_env, search_paths):
    """
    Search for the expense statement file in multiple possible locations.
    
    Args:
        copy_from_env: Function to copy files from container
        search_paths: List of potential file paths to check
    
    Returns:
        Tuple of (found_path, temp_file_path) or (None, None)
    """
    for container_path in search_paths:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        try:
            copy_from_env(container_path, temp_file.name)
            if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                logger.info(f"Found file at: {container_path}")
                return container_path, temp_file.name
        except Exception as e:
            logger.debug(f"File not found at {container_path}: {e}")
        finally:
            temp_file.close()
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    
    return None, None


def check_formula_exists(sheet, cell_ref):
    """
    Check if a cell contains a formula (starts with =).
    
    Args:
        sheet: Worksheet object
        cell_ref: Cell reference like 'B13'
    
    Returns:
        Tuple of (has_formula, formula_text)
    """
    try:
        cell = sheet[cell_ref]
        # Check if cell has a formula
        if hasattr(cell, 'value') and cell.value:
            cell_value_str = str(cell.value)
            if cell_value_str.startswith('='):
                return True, cell_value_str
        
        # Try to get formula from data_type
        if hasattr(cell, 'data_type') and cell.data_type == 'f':
            return True, str(cell.value) if cell.value else "=FORMULA"
        
        return False, None
    except Exception as e:
        logger.debug(f"Error checking formula in {cell_ref}: {e}")
        return False, None


def find_total_row(sheet, max_rows=30):
    """
    Find the row containing the total/sum.
    
    Args:
        sheet: Worksheet object
        max_rows: Maximum rows to search
    
    Returns:
        Row number or None
    """
    for row_idx in range(1, max_rows + 1):
        try:
            cell_a = sheet[f'A{row_idx}']
            if cell_a.value:
                cell_text = str(cell_a.value).lower()
                if 'total' in cell_text and ('expense' in cell_text or 'monthly' in cell_text):
                    return row_idx
        except:
            continue
    return None


def extract_expense_data(sheet, max_rows=25):
    """
    Extract expense categories and amounts from the spreadsheet.
    
    Args:
        sheet: Worksheet object
        max_rows: Maximum rows to search
    
    Returns:
        Dictionary mapping category keywords to amounts
    """
    expenses = {}
    
    for row_idx in range(1, max_rows + 1):
        try:
            cell_a = sheet[f'A{row_idx}']
            cell_b = sheet[f'B{row_idx}']
            
            if not cell_a.value:
                continue
            
            category_text = str(cell_a.value).lower()
            amount = cell_b.value
            
            # Skip headers and totals
            if 'category' in category_text or 'total' in category_text:
                continue
            
            # Convert amount to float if possible
            if amount is not None:
                try:
                    amount_val = float(amount)
                    
                    # Categorize by keywords
                    if 'hous' in category_text or 'rent' in category_text or 'mortgage' in category_text:
                        expenses['housing'] = amount_val
                    elif 'electric' in category_text:
                        expenses['electric'] = amount_val
                    elif 'gas' in category_text or 'heat' in category_text:
                        expenses['gas'] = amount_val
                    elif 'water' in category_text or 'sewer' in category_text:
                        expenses['water'] = amount_val
                    elif 'child' in category_text:
                        expenses['childcare'] = amount_val
                    elif 'medical' in category_text or 'health' in category_text:
                        expenses['medical'] = amount_val
                    elif 'phone' in category_text:
                        expenses['phone'] = amount_val
                        
                except (ValueError, TypeError):
                    pass
                    
        except Exception as e:
            logger.debug(f"Error processing row {row_idx}: {e}")
            continue
    
    return expenses


def verify_snap_expense_statement(traj, env_info, task_info):
    """
    Verify that the SNAP expense statement was created correctly.
    
    Scoring criteria (each 20%):
    1. Structural Integrity: Headers, organization, categories present
    2. Formula Validation: Total uses =SUM() formula, not hard-coded
    3. Data Accuracy: Amounts match source data (±2 tolerance)
    4. Completeness: Required categories present (min 6 of 7)
    5. Total Correctness: Formula produces correct sum
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Search for the file in multiple possible locations
    search_paths = [
        "/home/ga/Documents/Spreadsheets/SNAP_Expense_Statement.xlsx",
        "/home/ga/Documents/SNAP_Expense_Statement.xlsx",
        "/home/ga/Desktop/SNAP_Expense_Statement.xlsx",
        "/home/ga/SNAP_Expense_Statement.xlsx",
    ]
    
    container_path, temp_path = find_file_in_container(copy_from_env, search_paths)
    
    if not container_path:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ SNAP_Expense_Statement.xlsx not found in expected locations"
        }

    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_snap_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to parse spreadsheet: {error}"
            }

        # Get the first sheet (most likely where data is)
        sheet = wb.active
        sheet_name = sheet.title
        
        logger.info(f"Analyzing sheet: {sheet_name}")

        criteria_scores = []
        feedback_parts = []

        # Expected expense values from the notes
        expected_expenses = {
            'housing': 875,
            'electric': 67,  # Accept 67-67.23
            'gas': 43,
            'water': 29,
            'childcare': 200,
            'medical': 85,  # 35 + 50
            'phone': 45  # Optional
        }
        
        # CRITERION 1: Structural Integrity (20%)
        structure_score = 0
        has_title = False
        has_headers = False
        
        # Check for title in first few rows
        for row in range(1, 6):
            try:
                cell_val = str(sheet[f'A{row}'].value or '').lower()
                if 'snap' in cell_val or 'recertification' in cell_val or 'expense statement' in cell_val:
                    has_title = True
                    break
            except:
                pass
        
        # Check for column headers
        for row in range(1, 8):
            try:
                cell_val = str(sheet[f'A{row}'].value or '').lower()
                if 'category' in cell_val or 'expense' in cell_val:
                    has_headers = True
                    break
            except:
                pass
        
        if has_title and has_headers:
            structure_score = 20
            feedback_parts.append("✅ Structure: Title and headers present")
        elif has_headers:
            structure_score = 15
            feedback_parts.append("⚠️ Structure: Headers present but missing title")
        else:
            structure_score = 5
            feedback_parts.append("❌ Structure: Missing headers or title")
        
        criteria_scores.append(structure_score)

        # CRITERION 2: Formula Validation (20%)
        formula_score = 0
        total_row = find_total_row(sheet)
        
        if total_row:
            has_formula, formula_text = check_formula_exists(sheet, f'B{total_row}')
            
            if has_formula:
                if 'SUM' in formula_text.upper():
                    formula_score = 20
                    feedback_parts.append(f"✅ Formula: Valid SUM formula in B{total_row}")
                else:
                    formula_score = 10
                    feedback_parts.append(f"⚠️ Formula: Has formula but not SUM in B{total_row}")
            else:
                # Check if it's a hard-coded number
                total_val = get_cell_value(wb, sheet_name, f'B{total_row}')
                if isinstance(total_val, (int, float)):
                    formula_score = 5
                    feedback_parts.append(f"❌ Formula: Hard-coded number instead of =SUM() formula")
                else:
                    formula_score = 0
                    feedback_parts.append("❌ Formula: No total found")
        else:
            formula_score = 0
            feedback_parts.append("❌ Formula: No total row found")
        
        criteria_scores.append(formula_score)

        # CRITERION 3: Data Accuracy (20%)
        expenses = extract_expense_data(sheet)
        
        accuracy_checks = 0
        total_checks = 0
        
        for category, expected_val in expected_expenses.items():
            if category == 'phone':  # Phone is optional
                continue
            
            total_checks += 1
            if category in expenses:
                actual_val = expenses[category]
                # Allow ±2 tolerance for rounding
                if abs(actual_val - expected_val) <= 2:
                    accuracy_checks += 1
                else:
                    logger.debug(f"{category}: expected {expected_val}, got {actual_val}")
        
        accuracy_score = int((accuracy_checks / total_checks) * 20) if total_checks > 0 else 0
        
        if accuracy_score >= 18:
            feedback_parts.append(f"✅ Data Accuracy: {accuracy_checks}/{total_checks} amounts correct")
        elif accuracy_score >= 12:
            feedback_parts.append(f"⚠️ Data Accuracy: {accuracy_checks}/{total_checks} amounts correct")
        else:
            feedback_parts.append(f"❌ Data Accuracy: Only {accuracy_checks}/{total_checks} amounts correct")
        
        criteria_scores.append(accuracy_score)

        # CRITERION 4: Completeness (20%)
        required_categories = ['housing', 'electric', 'gas', 'water', 'childcare', 'medical']
        found_categories = sum(1 for cat in required_categories if cat in expenses)
        
        completeness_score = int((found_categories / len(required_categories)) * 20)
        
        if found_categories >= 6:
            feedback_parts.append(f"✅ Completeness: All {found_categories}/{len(required_categories)} required categories")
        elif found_categories >= 4:
            feedback_parts.append(f"⚠️ Completeness: {found_categories}/{len(required_categories)} required categories")
        else:
            feedback_parts.append(f"❌ Completeness: Only {found_categories}/{len(required_categories)} required categories")
        
        criteria_scores.append(completeness_score)

        # CRITERION 5: Total Correctness (20%)
        total_score = 0
        
        if total_row:
            total_val = get_cell_value(wb, sheet_name, f'B{total_row}')
            
            if isinstance(total_val, (int, float)):
                # Calculate expected total from found expenses
                expected_total = sum(expenses.values())
                
                # Also check against known minimum (without phone)
                min_expected = sum(expected_expenses[k] for k in required_categories)
                max_expected = min_expected + expected_expenses['phone']
                
                if abs(total_val - expected_total) <= 5:
                    total_score = 20
                    feedback_parts.append(f"✅ Total: Correct (${total_val:.2f})")
                elif min_expected - 10 <= total_val <= max_expected + 10:
                    total_score = 15
                    feedback_parts.append(f"⚠️ Total: Close to expected (${total_val:.2f})")
                else:
                    total_score = 5
                    feedback_parts.append(f"❌ Total: Incorrect (${total_val:.2f}, expected ~${min_expected}-${max_expected})")
            else:
                total_score = 0
                feedback_parts.append(f"❌ Total: Invalid or missing")
        
        criteria_scores.append(total_score)

        # Calculate final score
        final_score = sum(criteria_scores)
        passed = final_score >= 80  # Pass threshold

        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Criteria scores: {criteria_scores} = {final_score}/100")
        logger.info(f"Found expenses: {expenses}")

        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
