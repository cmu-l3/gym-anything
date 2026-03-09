#!/usr/bin/env python3
"""
Verifier for subscription_audit_calculator@1

Verifies that the user has:
1. Added proper column headers
2. Created formulas for Annual Cost (based on billing cycle)
3. Created formulas for Cost Per Person (handling shared subscriptions)
4. Entered cancellation decisions
5. Created summary calculations (total spending, savings, etc.)
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, Any, List, Tuple, Optional

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    parse_xlsx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def is_cell_formula(ws, cell_ref: str) -> bool:
    """Check if a cell contains a formula (starts with =)"""
    try:
        cell = ws[cell_ref]
        # Check if cell has a formula attribute or if value starts with =
        if hasattr(cell, 'value') and cell.value:
            if isinstance(cell.value, str) and cell.value.startswith('='):
                return True
            # Some cells store formula separately
            if hasattr(cell, 'data_type') and cell.data_type == 'f':
                return True
        return False
    except:
        return False


def get_cell_formula(ws, cell_ref: str) -> Optional[str]:
    """Get the formula from a cell if it exists"""
    try:
        cell = ws[cell_ref]
        if hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
            return cell.value
        return None
    except:
        return None


def verify_annual_cost_calculation(ws, row: int, tolerance: float = 2.0) -> Tuple[bool, str]:
    """
    Verify that the Annual Cost in column F is calculated correctly based on billing cycle
    
    Returns: (is_correct, feedback_message)
    """
    try:
        billing_cycle = get_cell_value(ws, ws.title, f'B{row}')
        cost = get_cell_value(ws, ws.title, f'C{row}')
        annual_cost = get_cell_value(ws, ws.title, f'F{row}')
        
        if not billing_cycle or not cost:
            return False, "Missing billing cycle or cost data"
        
        if annual_cost is None:
            return False, "No annual cost calculated"
        
        # Calculate expected annual cost
        billing_cycle_str = str(billing_cycle).strip().lower()
        cost_float = float(cost)
        
        if "monthly" in billing_cycle_str or "month" in billing_cycle_str:
            expected = cost_float * 12
        elif "annual" in billing_cycle_str or "year" in billing_cycle_str:
            expected = cost_float
        elif "quarter" in billing_cycle_str:
            expected = cost_float * 4
        else:
            return False, f"Unknown billing cycle: {billing_cycle}"
        
        # Check if calculated value is close to expected
        if isinstance(annual_cost, (int, float)):
            if abs(float(annual_cost) - expected) <= tolerance:
                return True, "Correct"
            else:
                return False, f"Expected ~${expected:.2f}, got ${float(annual_cost):.2f}"
        else:
            return False, f"Invalid annual cost value: {annual_cost}"
            
    except Exception as e:
        logger.error(f"Error verifying annual cost for row {row}: {e}")
        return False, f"Verification error: {str(e)}"


def verify_per_person_calculation(ws, row: int, tolerance: float = 2.0) -> Tuple[bool, str]:
    """
    Verify that Cost Per Person in column G is calculated correctly
    
    Should divide Annual Cost by Num People, or use Annual Cost if Num People is empty/1
    """
    try:
        annual_cost = get_cell_value(ws, ws.title, f'F{row}')
        num_people = get_cell_value(ws, ws.title, f'E{row}')
        per_person = get_cell_value(ws, ws.title, f'G{row}')
        
        if annual_cost is None or per_person is None:
            return False, "Missing required values"
        
        annual_float = float(annual_cost)
        
        # Determine expected per-person cost
        if num_people and float(num_people) > 1:
            expected = annual_float / float(num_people)
        else:
            expected = annual_float
        
        # Check if calculated value is close to expected
        if isinstance(per_person, (int, float)):
            if abs(float(per_person) - expected) <= tolerance:
                return True, "Correct"
            else:
                return False, f"Expected ~${expected:.2f}, got ${float(per_person):.2f}"
        else:
            return False, f"Invalid per-person value: {per_person}"
            
    except Exception as e:
        logger.error(f"Error verifying per-person cost for row {row}: {e}")
        return False, f"Verification error: {str(e)}"


def find_sum_formula_result(ws, search_range_rows: range, target_col: str = 'F') -> Optional[float]:
    """
    Search for a SUM formula that sums the target column
    Returns the calculated value if found
    """
    try:
        for row in search_range_rows:
            for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']:
                cell = ws[f'{col}{row}']
                if cell.value and isinstance(cell.value, str):
                    formula = cell.value.upper()
                    if formula.startswith('=') and 'SUM(' in formula and target_col in formula:
                        # Found a SUM formula referencing the target column
                        # Try to get the calculated value
                        # Check nearby cells for the result
                        for check_col in [col, chr(ord(col) + 1)]:
                            for check_row in [row, row + 1, row - 1]:
                                val = get_cell_value(ws, ws.title, f'{check_col}{check_row}')
                                if val and isinstance(val, (int, float)) and val > 0:
                                    return float(val)
        return None
    except Exception as e:
        logger.error(f"Error finding SUM formula: {e}")
        return None


def find_sumif_formula_result(ws, search_range_rows: range) -> Optional[float]:
    """
    Search for a SUMIF formula (for calculating cancellation amounts)
    Returns the calculated value if found
    """
    try:
        for row in search_range_rows:
            for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']:
                cell = ws[f'{col}{row}']
                if cell.value and isinstance(cell.value, str):
                    formula = cell.value.upper()
                    if formula.startswith('=') and 'SUMIF' in formula:
                        # Found a SUMIF formula
                        # Try to get the calculated value
                        for check_col in [col, chr(ord(col) + 1)]:
                            for check_row in [row, row + 1, row - 1]:
                                val = get_cell_value(ws, ws.title, f'{check_col}{check_row}')
                                if val and isinstance(val, (int, float)) and val > 0:
                                    return float(val)
        return None
    except Exception as e:
        logger.error(f"Error finding SUMIF formula: {e}")
        return None


def verify_subscription_audit_calculator(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for subscription audit calculator task
    
    Scoring breakdown (100 points total):
    - File exists and valid: 10 points
    - Headers correct: 10 points  
    - Annual Cost formulas: 25 points (formulas exist + calculations correct)
    - Cost Per Person formulas: 25 points (formulas exist + calculations correct)
    - Decisions entered: 15 points
    - Summary calculations: 15 points
    
    Passing score: 75/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/Spreadsheets/subscriptions_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_subscription_')
    
    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(
            container_path,
            copy_from_env,
            file_format='xlsx'
        )
        
        if not success or wb is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open spreadsheet: {error}"
            }
        
        feedback_parts = []
        score = 0
        max_score = 100
        
        feedback_parts.append("✅ File exists and is valid XLSX")
        score += 10
        
        # Get the worksheet
        ws = wb.active
        
        # ============================================
        # CHECK 1: Headers Present (10 points)
        # ============================================
        headers_correct = 0
        
        f1_val = str(get_cell_value(wb, ws.title, 'F1') or "").lower()
        g1_val = str(get_cell_value(wb, ws.title, 'G1') or "").lower()
        h1_val = str(get_cell_value(wb, ws.title, 'H1') or "").lower()
        
        if "annual" in f1_val and "cost" in f1_val:
            headers_correct += 1
        else:
            feedback_parts.append(f"❌ Column F header incorrect: '{f1_val}' (expected 'Annual Cost')")
        
        if ("per person" in g1_val or "cost per" in g1_val) and "person" in g1_val:
            headers_correct += 1
        else:
            feedback_parts.append(f"❌ Column G header incorrect: '{g1_val}' (expected 'Cost Per Person')")
        
        if "decision" in h1_val:
            headers_correct += 1
        else:
            feedback_parts.append(f"❌ Column H header incorrect: '{h1_val}' (expected 'Decision')")
        
        if headers_correct == 3:
            feedback_parts.append("✅ All column headers present and correct")
            score += 10
        else:
            feedback_parts.append(f"⚠️ Only {headers_correct}/3 headers correct")
            score += int(10 * headers_correct / 3)
        
        # ============================================
        # CHECK 2: Annual Cost Formulas (25 points)
        # ============================================
        formula_count = 0
        correct_calculations = 0
        
        for row in range(2, 13):  # Rows 2-12 (11 subscriptions)
            # Check if formula exists
            if is_cell_formula(ws, f'F{row}'):
                formula_count += 1
            
            # Check if calculation is correct
            is_correct, msg = verify_annual_cost_calculation(ws, row)
            if is_correct:
                correct_calculations += 1
        
        annual_cost_score = 0
        
        if formula_count >= 8:
            feedback_parts.append(f"✅ Annual Cost formulas present ({formula_count}/11 cells)")
            annual_cost_score += 12
        else:
            feedback_parts.append(f"❌ Insufficient Annual Cost formulas ({formula_count}/11, need ≥8)")
            annual_cost_score += int(12 * formula_count / 8)
        
        if correct_calculations >= 8:
            feedback_parts.append(f"✅ Annual Cost calculations correct ({correct_calculations}/11)")
            annual_cost_score += 13
        else:
            feedback_parts.append(f"⚠️ Some Annual Cost calculations incorrect ({correct_calculations}/11 correct)")
            annual_cost_score += int(13 * correct_calculations / 8)
        
        score += annual_cost_score
        
        # ============================================
        # CHECK 3: Cost Per Person Formulas (25 points)
        # ============================================
        per_person_formulas = 0
        per_person_correct = 0
        
        for row in range(2, 13):
            # Check if formula exists
            if is_cell_formula(ws, f'G{row}'):
                per_person_formulas += 1
            
            # Check if calculation is correct
            is_correct, msg = verify_per_person_calculation(ws, row)
            if is_correct:
                per_person_correct += 1
        
        per_person_score = 0
        
        if per_person_formulas >= 8:
            feedback_parts.append(f"✅ Cost Per Person formulas present ({per_person_formulas}/11)")
            per_person_score += 12
        else:
            feedback_parts.append(f"❌ Insufficient Cost Per Person formulas ({per_person_formulas}/11, need ≥8)")
            per_person_score += int(12 * per_person_formulas / 8)
        
        if per_person_correct >= 8:
            feedback_parts.append(f"✅ Cost Per Person calculations correct ({per_person_correct}/11)")
            per_person_score += 13
        else:
            feedback_parts.append(f"⚠️ Some Cost Per Person calculations incorrect ({per_person_correct}/11 correct)")
            per_person_score += int(13 * per_person_correct / 8)
        
        score += per_person_score
        
        # ============================================
        # CHECK 4: Decisions Entered (15 points)
        # ============================================
        decisions = []
        for row in range(2, 13):
            decision_val = get_cell_value(wb, ws.title, f'H{row}')
            if decision_val:
                decisions.append(str(decision_val).strip().lower())
        
        keep_count = sum(1 for d in decisions if "keep" in d)
        cancel_count = sum(1 for d in decisions if "cancel" in d)
        total_decisions = len([d for d in decisions if d])  # Non-empty
        
        decision_score = 0
        
        if total_decisions >= 6:
            decision_score += 5
        else:
            feedback_parts.append(f"❌ Insufficient decisions entered ({total_decisions}/11, need ≥6)")
        
        if keep_count >= 3:
            decision_score += 5
        else:
            feedback_parts.append(f"❌ Need at least 3 'Keep' decisions (found {keep_count})")
        
        if cancel_count >= 2:
            decision_score += 5
        else:
            feedback_parts.append(f"❌ Need at least 2 'Cancel' decisions (found {cancel_count})")
        
        if decision_score == 15:
            feedback_parts.append(f"✅ Decisions properly entered ({keep_count} Keep, {cancel_count} Cancel)")
        
        score += decision_score
        
        # ============================================
        # CHECK 5: Summary Calculations (15 points)
        # ============================================
        summary_score = 0
        
        # Look for summary calculations in rows 13-30
        search_range = range(13, 31)
        
        # Check for total sum formula
        total_sum_found = False
        expected_total = sum([
            get_cell_value(wb, ws.title, f'F{row}') or 0 
            for row in range(2, 13)
            if isinstance(get_cell_value(wb, ws.title, f'F{row}'), (int, float))
        ])
        
        for row in search_range:
            for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']:
                cell_val = ws[f'{col}{row}'].value
                if isinstance(cell_val, (int, float)) and cell_val > 0:
                    # Check if this matches expected total
                    if abs(float(cell_val) - expected_total) <= 10:
                        # Check if there's a SUM formula nearby
                        for check_row in [row - 1, row, row + 1]:
                            for check_col in [chr(ord(col) - 1), col, chr(ord(col) + 1)]:
                                if check_col < 'A' or check_col > 'Z':
                                    continue
                                try:
                                    check_cell = ws[f'{check_col}{check_row}']
                                    if check_cell.value and isinstance(check_cell.value, str):
                                        if 'SUM' in str(check_cell.value).upper():
                                            total_sum_found = True
                                            break
                                except:
                                    pass
                            if total_sum_found:
                                break
                if total_sum_found:
                    break
            if total_sum_found:
                break
        
        if total_sum_found:
            feedback_parts.append(f"✅ Total Annual Spending formula found (~${expected_total:.2f})")
            summary_score += 8
        else:
            feedback_parts.append("❌ Total Annual Spending formula not found (should use SUM)")
        
        # Check for SUMIF or conditional sum for cancellations
        cancel_sum_found = False
        
        # Calculate expected cancel amount
        expected_cancel = sum([
            get_cell_value(wb, ws.title, f'F{row}') or 0
            for row in range(2, 13)
            if "cancel" in str(get_cell_value(wb, ws.title, f'H{row}') or "").lower()
            and isinstance(get_cell_value(wb, ws.title, f'F{row}'), (int, float))
        ])
        
        if expected_cancel > 0:
            for row in search_range:
                for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J']:
                    cell_val = ws[f'{col}{row}'].value
                    if isinstance(cell_val, (int, float)) and cell_val > 0:
                        # Check if this matches expected cancel amount
                        if abs(float(cell_val) - expected_cancel) <= 10:
                            cancel_sum_found = True
                            break
                    # Also check for SUMIF formula
                    if cell_val and isinstance(cell_val, str):
                        if 'SUMIF' in str(cell_val).upper():
                            cancel_sum_found = True
                            break
                if cancel_sum_found:
                    break
        
        if cancel_sum_found:
            feedback_parts.append(f"✅ Cancellation savings calculated (~${expected_cancel:.2f})")
            summary_score += 7
        elif expected_cancel == 0:
            feedback_parts.append("⚠️ No cancellations marked, cannot verify savings calculation")
            summary_score += 3
        else:
            feedback_parts.append("❌ Savings/cancellation formula not found (should use SUMIF)")
        
        score += summary_score
        
        # ============================================
        # Final Determination
        # ============================================
        passed = score >= 75
        normalized_score = score / max_score
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete. Score: {score}/{max_score}, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": float(normalized_score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.exception("Verification error occurred")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything framework
def verify(**kwargs):
    """Entry point called by gym-anything framework"""
    return verify_subscription_audit_calculator(**kwargs)