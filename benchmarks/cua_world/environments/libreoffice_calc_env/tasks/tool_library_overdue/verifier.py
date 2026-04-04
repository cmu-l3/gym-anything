#!/usr/bin/env python3
"""
Verifier for Tool Library Overdue Tracker task

Checks:
1. Days Overdue formula exists and uses TODAY()
2. Conditional logic checks for empty Return Date
3. Calculations are accurate for sample rows
4. Late Fee calculated correctly
5. Status logic properly implemented
6. Edge cases handled (returned items, items not yet due)
"""

import sys
import os
import re
import logging
from datetime import datetime, timedelta

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_value(date_val):
    """Parse date value from various formats"""
    if date_val is None or date_val == '' or date_val == 'None':
        return None
    
    date_str = str(date_val).strip()
    if not date_str or date_str.lower() == 'none':
        return None
    
    # Try various date formats
    for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%m/%d/%y', '%Y/%m/%d', '%d-%m-%Y']:
        try:
            return datetime.strptime(date_str, fmt).date()
        except (ValueError, AttributeError):
            continue
    
    # Try parsing as float (Excel serial date)
    try:
        # Excel/Calc date serial number (days since 1899-12-30)
        days = float(date_str)
        base_date = datetime(1899, 12, 30)
        return (base_date + timedelta(days=days)).date()
    except (ValueError, TypeError):
        pass
    
    return None


def calculate_expected_days_overdue(due_date_val, return_date_val):
    """
    Calculate expected days overdue based on due date and return date
    
    Returns:
        int: Expected days overdue (0 if returned or not yet due)
    """
    # If return date exists, should be 0
    return_date = parse_date_value(return_date_val)
    if return_date is not None:
        return 0
    
    # Parse due date
    due_date = parse_date_value(due_date_val)
    if due_date is None:
        return 0
    
    # Calculate days past due
    today = datetime.now().date()
    days_diff = (today - due_date).days
    
    # Return 0 if not yet overdue
    return max(0, days_diff)


def calculate_expected_status(days_overdue, has_return_date):
    """
    Calculate expected status based on days overdue
    
    Returns:
        str: Expected status
    """
    if has_return_date:
        return "Returned"
    elif days_overdue >= 7:
        return "URGENT"
    elif days_overdue > 0:
        return "Overdue"
    else:
        return "On Time"


def check_formula_structure(formula):
    """
    Check if formula has correct structure for Days Overdue calculation
    
    Returns:
        dict: Analysis of formula structure
    """
    if not formula:
        return {'valid': False, 'has_today': False, 'has_conditional': False, 'has_date_math': False}
    
    formula_upper = formula.upper()
    
    analysis = {
        'valid': True,
        'has_today': 'TODAY()' in formula_upper,
        'has_conditional': 'IF(' in formula_upper,
        'has_empty_check': '=""' in formula or '="")' in formula or '<>"")' in formula or '<>""' in formula,
        'has_date_math': re.search(r'TODAY\(\)\s*-|[-]\s*TODAY\(\)', formula_upper) is not None,
        'has_max_or_greater': 'MAX(' in formula_upper or '>0' in formula or '>=0' in formula
    }
    
    return analysis


def verify_tool_library_overdue(traj, env_info, task_info):
    """
    Verify tool library overdue tracker task completion.
    
    Checks:
    1. Days Overdue column (F) has formulas with TODAY()
    2. Late Fee column (G) calculated correctly
    3. Status column (H) has proper logic
    4. Calculations match expected values for sample rows
    5. Edge cases handled correctly
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try both ODS and CSV formats
    temp_dir = None
    success = False
    workbook = None
    
    for fmt, path in [('ods', '/home/ga/Documents/tool_library_data.ods'),
                      ('csv', '/home/ga/Documents/tool_library_data.csv')]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path,
            copy_from_env,
            file_format=fmt
        )
        if success:
            logger.info(f"Successfully loaded file as {fmt}: {path}")
            break
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_scores = {
            'days_overdue_formula': 0,      # 20 points
            'late_fee_formula': 0,          # 15 points
            'status_formula': 0,            # 15 points
            'calculation_accuracy': 0,       # 30 points
            'edge_cases': 0,                # 20 points
        }
        
        feedback_parts = []
        
        # ===== Check 1: Days Overdue Formula (20 points) =====
        days_overdue_formula_found = False
        formula_quality = 0
        
        for row in range(2, 15):  # Check rows 2-14 (data rows)
            formula = get_cell_formula(workbook, sheet_name, f'F{row}')
            if formula:
                analysis = check_formula_structure(formula)
                
                if analysis['has_today']:
                    days_overdue_formula_found = True
                    
                    # Quality scoring
                    if analysis['has_conditional'] and analysis['has_empty_check']:
                        formula_quality = max(formula_quality, 3)  # Excellent
                    elif analysis['has_conditional'] or analysis['has_empty_check']:
                        formula_quality = max(formula_quality, 2)  # Good
                    elif analysis['has_date_math']:
                        formula_quality = max(formula_quality, 1)  # Basic
                    
                    logger.info(f"Found Days Overdue formula in F{row}: {formula}")
                    break
        
        if days_overdue_formula_found:
            if formula_quality == 3:
                criteria_scores['days_overdue_formula'] = 20
                feedback_parts.append("✅ Days Overdue formula excellent (TODAY, IF, empty check)")
            elif formula_quality == 2:
                criteria_scores['days_overdue_formula'] = 15
                feedback_parts.append("✅ Days Overdue formula good (has conditional logic)")
            else:
                criteria_scores['days_overdue_formula'] = 10
                feedback_parts.append("⚠️ Days Overdue formula basic (missing conditional logic)")
        else:
            feedback_parts.append("❌ Days Overdue formula missing or no TODAY() function")
        
        # ===== Check 2: Late Fee Formula (15 points) =====
        late_fee_formula_found = False
        
        for row in range(2, 15):
            formula = get_cell_formula(workbook, sheet_name, f'G{row}')
            if formula:
                formula_upper = formula.upper()
                # Check if formula references column F and multiplies by 1
                if 'F' in formula_upper and ('*1' in formula or '*$1' in formula or '*1.0' in formula):
                    late_fee_formula_found = True
                    criteria_scores['late_fee_formula'] = 15
                    feedback_parts.append(f"✅ Late Fee formula found: {formula}")
                    logger.info(f"Found Late Fee formula in G{row}: {formula}")
                    break
                elif 'F' in formula_upper:
                    late_fee_formula_found = True
                    criteria_scores['late_fee_formula'] = 10
                    feedback_parts.append(f"⚠️ Late Fee formula references F but check calculation")
                    break
        
        if not late_fee_formula_found:
            feedback_parts.append("❌ Late Fee formula missing or incorrect")
        
        # ===== Check 3: Status Formula (15 points) =====
        status_formula_found = False
        status_quality = 0
        
        for row in range(2, 15):
            formula = get_cell_formula(workbook, sheet_name, f'H{row}')
            if formula:
                formula_upper = formula.upper()
                
                # Check for nested IF and key status words
                if_count = formula_upper.count('IF(')
                has_urgent = 'URGENT' in formula_upper
                has_returned = 'RETURNED' in formula_upper
                has_overdue = 'OVERDUE' in formula_upper
                has_ontime = 'ON TIME' in formula_upper or 'ONTIME' in formula_upper
                
                if if_count >= 2:  # Nested IFs
                    status_formula_found = True
                    # Count how many status types are present
                    status_types = sum([has_urgent, has_returned, has_overdue, has_ontime])
                    if status_types >= 3:
                        status_quality = 3
                    elif status_types >= 2:
                        status_quality = 2
                    else:
                        status_quality = 1
                    
                    logger.info(f"Found Status formula in H{row}: {formula}")
                    break
                elif if_count >= 1:
                    status_formula_found = True
                    status_quality = 1
                    break
        
        if status_formula_found:
            if status_quality == 3:
                criteria_scores['status_formula'] = 15
                feedback_parts.append("✅ Status formula excellent (nested IFs, multiple statuses)")
            elif status_quality == 2:
                criteria_scores['status_formula'] = 10
                feedback_parts.append("⚠️ Status formula good but missing some status types")
            else:
                criteria_scores['status_formula'] = 5
                feedback_parts.append("⚠️ Status formula basic (simple IF)")
        else:
            feedback_parts.append("❌ Status formula missing or no conditional logic")
        
        # ===== Check 4: Calculation Accuracy (30 points) =====
        accurate_calculations = 0
        total_checks = 0
        
        # Test several rows
        for row in range(2, min(15, len(workbook['sheets'][sheet_name]) + 1)):
            # Get dates from columns
            due_date_val = get_cell_value(workbook, sheet_name, f'D{row}')
            return_date_val = get_cell_value(workbook, sheet_name, f'E{row}')
            
            # Get calculated values
            days_overdue_actual = get_cell_value(workbook, sheet_name, f'F{row}')
            late_fee_actual = get_cell_value(workbook, sheet_name, f'G{row}')
            
            if due_date_val is None:
                continue
            
            # Calculate expected values
            expected_days = calculate_expected_days_overdue(due_date_val, return_date_val)
            expected_fee = expected_days * 1.0
            
            total_checks += 1
            
            # Check days overdue (allow tolerance of ±1 day due to timing)
            if days_overdue_actual is not None:
                try:
                    days_diff = abs(float(days_overdue_actual) - expected_days)
                    if days_diff <= 1:  # Allow 1 day tolerance
                        accurate_calculations += 1
                        logger.debug(f"Row {row}: Days overdue correct ({days_overdue_actual} ≈ {expected_days})")
                    else:
                        logger.debug(f"Row {row}: Days overdue mismatch ({days_overdue_actual} vs {expected_days})")
                except (ValueError, TypeError):
                    logger.debug(f"Row {row}: Could not parse days overdue value")
        
        if total_checks > 0:
            accuracy_ratio = accurate_calculations / total_checks
            criteria_scores['calculation_accuracy'] = int(30 * accuracy_ratio)
            feedback_parts.append(f"📊 Calculation accuracy: {accurate_calculations}/{total_checks} rows correct ({int(accuracy_ratio*100)}%)")
        else:
            feedback_parts.append("⚠️ Could not verify calculation accuracy")
        
        # ===== Check 5: Edge Cases (20 points) =====
        edge_case_score = 0
        edge_checks = []
        
        # Find a returned item and check it shows 0 days overdue
        returned_item_correct = False
        for row in range(2, 15):
            return_date = get_cell_value(workbook, sheet_name, f'E{row}')
            if return_date and str(return_date).strip() and str(return_date) != 'None':
                days_overdue = get_cell_value(workbook, sheet_name, f'F{row}')
                late_fee = get_cell_value(workbook, sheet_name, f'G{row}')
                try:
                    if float(days_overdue or 0) == 0 and float(late_fee or 0) == 0:
                        returned_item_correct = True
                        edge_checks.append("✅ Returned item shows 0 days/fees")
                        break
                except (ValueError, TypeError):
                    pass
        
        if not returned_item_correct:
            edge_checks.append("❌ Returned item not handled correctly")
        
        # Check for URGENT status on highly overdue items
        urgent_found = False
        for row in range(2, 15):
            days_overdue = get_cell_value(workbook, sheet_name, f'F{row}')
            status = get_cell_value(workbook, sheet_name, f'H{row}')
            try:
                if float(days_overdue or 0) >= 7:
                    if status and 'URGENT' in str(status).upper():
                        urgent_found = True
                        edge_checks.append("✅ URGENT status correctly applied")
                        break
            except (ValueError, TypeError):
                pass
        
        if not urgent_found:
            edge_checks.append("⚠️ URGENT status not found or incorrect")
        
        # Calculate edge case score
        if returned_item_correct and urgent_found:
            edge_case_score = 20
        elif returned_item_correct or urgent_found:
            edge_case_score = 10
        
        criteria_scores['edge_cases'] = edge_case_score
        feedback_parts.extend(edge_checks)
        
        # ===== Calculate Final Score =====
        total_score = sum(criteria_scores.values())
        passed = total_score >= 70
        
        # Add summary
        if passed:
            if total_score >= 90:
                feedback_parts.insert(0, "🎉 Excellent work! All formulas correct with proper logic")
            elif total_score >= 80:
                feedback_parts.insert(0, "✅ Good work! Formulas mostly correct")
            else:
                feedback_parts.insert(0, "✅ Task passed with acceptable formulas")
        else:
            feedback_parts.insert(0, "❌ Task incomplete - formulas missing or incorrect")
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "days_overdue_formula": criteria_scores['days_overdue_formula'],
                "late_fee_formula": criteria_scores['late_fee_formula'],
                "status_formula": criteria_scores['status_formula'],
                "calculation_accuracy": criteria_scores['calculation_accuracy'],
                "edge_cases": criteria_scores['edge_cases']
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
