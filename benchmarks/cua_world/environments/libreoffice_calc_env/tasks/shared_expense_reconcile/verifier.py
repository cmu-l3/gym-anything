#!/usr/bin/env python3
"""
Verifier for Shared Expense Reconciliation task
Checks formulas, calculations, zero-sum property, and formatting
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_expected_totals():
    """
    Calculate expected values based on the pre-populated expense data.
    Returns dict with expected totals for verification.
    """
    # Expense data from setup
    expenses = [
        ("2024-01-05", "Groceries", 87.50, "Alice", "Equal"),
        ("2024-01-07", "Internet Bill", 60.00, "Bob", "Equal"),
        ("2024-01-10", "Cleaning Supplies", 34.20, "Carol", "Equal"),
        ("2024-01-12", "Alice's Dry Cleaning", 25.00, "Alice", "Alice"),
        ("2024-01-15", "Rent", 1500.00, "Alice", "Equal"),
        ("2024-01-18", "Bob's Medication", 45.00, "Carol", "Bob"),
        ("2024-01-22", "Groceries", 102.30, "Bob", "Equal"),
        ("2024-01-25", "Electricity", 78.00, "Carol", "Equal"),
        ("2024-01-28", "Carol's Books", 56.00, "Bob", "Carol"),
        ("2024-01-30", "Groceries", 94.75, "Alice", "Equal"),
    ]
    
    # Calculate what each person paid
    paid = {"Alice": 0, "Bob": 0, "Carol": 0}
    for exp in expenses:
        paid[exp[3]] += exp[2]
    
    # Calculate what each person owes
    owed = {"Alice": 0, "Bob": 0, "Carol": 0}
    for exp in expenses:
        amount = exp[2]
        split_type = exp[4]
        
        if split_type == "Equal":
            # Split equally among 3 people
            owed["Alice"] += amount / 3
            owed["Bob"] += amount / 3
            owed["Carol"] += amount / 3
        else:
            # Assigned to specific person
            owed[split_type] += amount
    
    # Calculate net balances
    balance = {
        "Alice": paid["Alice"] - owed["Alice"],
        "Bob": paid["Bob"] - owed["Bob"],
        "Carol": paid["Carol"] - owed["Carol"]
    }
    
    return {
        "paid": paid,
        "owed": owed,
        "balance": balance
    }


def check_conditional_formatting_ods(filepath):
    """
    Check if conditional formatting is applied to the ODS file.
    Returns True if formatting likely exists, False otherwise.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False
            
            content_xml = ods_zip.read('content.xml')
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Look for conditional formatting indicators in ODS
            # Note: This is a heuristic check
            indicators = [
                'conditional-format',
                'condition',
                'style:map',
                'style:condition'
            ]
            
            for indicator in indicators:
                if indicator in content_str:
                    logger.info(f"Found conditional formatting indicator: {indicator}")
                    return True
            
            return False
            
    except Exception as e:
        logger.debug(f"Could not check conditional formatting: {e}")
        return False


def verify_shared_expense_reconcile(traj, env_info, task_info):
    """
    Verify shared expense reconciliation task completion.
    
    Checks:
    1. Formulas present (not hardcoded values)
    2. Total Paid calculations correct
    3. Total Owed calculations correct
    4. Net Balance calculations correct
    5. Zero-sum property holds
    6. Conditional formatting applied (bonus)
    7. Settlement summary exists (bonus)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/expense_reconciliation.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        
        # Calculate expected values
        expected = calculate_expected_totals()
        tolerance = 0.10  # $0.10 tolerance for rounding
        
        # Criterion 1: Formulas present (not hardcoded)
        formulas_present = True
        formula_cells = [
            ('B14', 'Alice Total Paid'),
            ('B15', 'Bob Total Paid'),
            ('B16', 'Carol Total Paid'),
            ('C14', 'Alice Total Owed'),
            ('C15', 'Bob Total Owed'),
            ('C16', 'Carol Total Owed'),
            ('D14', 'Alice Net Balance'),
            ('D15', 'Bob Net Balance'),
            ('D16', 'Carol Net Balance'),
        ]
        
        missing_formulas = []
        for cell_ref, description in formula_cells:
            formula = get_cell_formula(workbook, sheet_name, cell_ref)
            if not formula or not formula.startswith('='):
                formulas_present = False
                missing_formulas.append(description)
        
        if formulas_present:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas present in all required cells")
        else:
            feedback_parts.append(f"❌ Missing formulas in: {', '.join(missing_formulas[:3])}")
        
        # Criterion 2: Total Paid calculations correct
        people = ['Alice', 'Bob', 'Carol']
        rows = {'Alice': 14, 'Bob': 15, 'Carol': 16}
        
        paid_correct = True
        for person in people:
            cell_ref = f'B{rows[person]}'
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            expected_val = expected['paid'][person]
            
            if actual is None or abs(float(actual) - expected_val) > tolerance:
                paid_correct = False
                feedback_parts.append(f"❌ {person} Total Paid incorrect: expected ${expected_val:.2f}, got {actual}")
                break
        
        if paid_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Total Paid calculations correct")
        
        # Criterion 3: Total Owed calculations correct
        owed_correct = True
        for person in people:
            cell_ref = f'C{rows[person]}'
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            expected_val = expected['owed'][person]
            
            if actual is None or abs(float(actual) - expected_val) > tolerance:
                owed_correct = False
                feedback_parts.append(f"❌ {person} Total Owed incorrect: expected ${expected_val:.2f}, got {actual}")
                break
        
        if owed_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Total Owed calculations correct")
        
        # Criterion 4: Net Balance calculations correct
        balance_correct = True
        for person in people:
            cell_ref = f'D{rows[person]}'
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            expected_val = expected['balance'][person]
            
            if actual is None or abs(float(actual) - expected_val) > tolerance:
                balance_correct = False
                feedback_parts.append(f"❌ {person} Net Balance incorrect: expected ${expected_val:.2f}, got {actual}")
                break
        
        if balance_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Net Balance calculations correct")
        
        # Criterion 5: Zero-sum property
        balance_sum = 0
        balances = []
        for person in people:
            cell_ref = f'D{rows[person]}'
            actual = get_cell_value(workbook, sheet_name, cell_ref)
            if actual is not None:
                balances.append(float(actual))
                balance_sum += float(actual)
        
        zero_sum_valid = abs(balance_sum) <= tolerance
        if zero_sum_valid:
            criteria_passed += 1
            feedback_parts.append(f"✅ Zero-sum property holds (sum = ${balance_sum:.2f})")
        else:
            feedback_parts.append(f"❌ Balance sum is ${balance_sum:.2f} (should be ~$0.00)")
        
        # Criterion 6: Conditional formatting (bonus)
        has_formatting = check_conditional_formatting_ods(workbook['filepath'])
        if has_formatting:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            feedback_parts.append("⚠️ Conditional formatting not detected (bonus criterion)")
        
        # Criterion 7: Settlement summary exists (bonus)
        settlement_exists = False
        for row_idx in range(19, 23):  # Check rows 20-22 (0-indexed: 19-21)
            for col_idx in range(5):
                try:
                    cell_ref = chr(65 + col_idx) + str(row_idx)
                    value = get_cell_value(workbook, sheet_name, cell_ref)
                    if value and isinstance(value, str) and len(str(value).strip()) > 5:
                        # Check if it contains settlement-related keywords
                        value_lower = str(value).lower()
                        if any(keyword in value_lower for keyword in ['pay', 'owe', 'settle', '$']):
                            settlement_exists = True
                            break
                except:
                    pass
            if settlement_exists:
                break
        
        if settlement_exists:
            criteria_passed += 1
            feedback_parts.append("✅ Settlement summary present")
        else:
            feedback_parts.append("⚠️ Settlement summary not found (bonus criterion)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        
        # Core criteria: 1-5 (formulas, calculations, zero-sum)
        core_criteria = sum([
            formulas_present,
            paid_correct,
            owed_correct,
            balance_correct,
            zero_sum_valid
        ])
        
        # Pass if core criteria met (at least 4/5 core + overall 70%)
        passed = core_criteria >= 4 and score >= 70
        
        # Add summary feedback
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent expense reconciliation!")
        elif passed:
            feedback_parts.insert(0, "✅ Expense reconciliation completed")
        else:
            feedback_parts.insert(0, "❌ Expense reconciliation incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formulas_present": formulas_present,
                "total_paid_correct": paid_correct,
                "total_owed_correct": owed_correct,
                "net_balance_correct": balance_correct,
                "zero_sum_valid": zero_sum_valid,
                "conditional_formatting": has_formatting,
                "settlement_summary": settlement_exists,
                "core_criteria_met": f"{core_criteria}/5"
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "error_details": str(e)
        }

    finally:
        cleanup_verification_temp(temp_dir)
