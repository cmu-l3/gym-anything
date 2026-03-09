#!/usr/bin/env python3
"""
Verifier for Band Gig Profit Splitter task.

Checks that the agent correctly calculated:
1. Total revenue from all gigs
2. Total expenses (per-gig and monthly)
3. Net profit (revenue - expenses)
4. Individual member gig counts
5. Fair payment distribution based on attendance
"""

import sys
import os
import logging
import re

# Use relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_cell_with_value_near(sheet_data, target_value, tolerance=0.5, search_region='bottom'):
    """
    Search for a cell containing a specific numeric value.
    Returns (row_idx, col_idx) or None if not found.
    """
    rows = sheet_data if isinstance(sheet_data, list) else []
    
    # Define search region
    if search_region == 'bottom':
        start_row = max(0, len(rows) - 30)  # Search last 30 rows
    else:
        start_row = 0
    
    for row_idx in range(start_row, len(rows)):
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value is not None:
                try:
                    val_float = float(cell_value)
                    if abs(val_float - target_value) <= tolerance:
                        return (row_idx, col_idx)
                except (ValueError, TypeError):
                    pass
    return None


def extract_numbers_from_sheet(sheet_data):
    """Extract all numeric values and their locations from bottom region of sheet."""
    numbers = []
    rows = sheet_data if isinstance(sheet_data, list) else []
    start_row = max(0, len(rows) - 35)  # Search last 35 rows
    
    for row_idx in range(start_row, len(rows)):
        row = rows[row_idx]
        for col_idx, cell in enumerate(row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value is not None and cell_value != '':
                try:
                    val_float = float(cell_value)
                    if val_float > 0:  # Only positive numbers
                        numbers.append({
                            'value': val_float,
                            'row': row_idx,
                            'col': col_idx,
                            'cell': cell
                        })
                except (ValueError, TypeError):
                    pass
    return numbers


def verify_band_gig_splitter(traj, env_info, task_info):
    """
    Verify band gig profit splitter task completion.
    
    Expected calculations:
    - Total Revenue = 2660 (sum of all 8 gigs)
    - Total Expenses = 1450 (920 per-gig + 530 monthly for 2 months)
    - Net Profit = 1210 (2660 - 1450)
    - Member gig counts: Alex=6, Bailey=7, Casey=6, Drew=6 (total 25 shares)
    - Payment per share = 48.40 (1210 / 25)
    - Individual payments should sum to 1210
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/band_finances.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet data
        sheet_name = list(workbook['sheets'].keys())[0]
        sheet_data = workbook['sheets'][sheet_name]

        # Expected values based on the data
        EXPECTED_TOTAL_REVENUE = 2660  # 350+280+450+320+400+180+300+380
        EXPECTED_PER_GIG_EXPENSES = 920  # (75+40) * 8 gigs
        EXPECTED_MONTHLY_EXPENSES = 530  # (200+15+50) * 2 months
        EXPECTED_TOTAL_EXPENSES = 1450  # 920 + 530
        EXPECTED_NET_PROFIT = 1210  # 2660 - 1450
        
        # Member gig counts from data
        EXPECTED_GIG_COUNTS = {
            'Alex': 6,
            'Bailey': 7,
            'Casey': 6,
            'Drew': 6
        }
        EXPECTED_TOTAL_SHARES = 25

        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Extract all numbers from calculation area
        all_numbers = extract_numbers_from_sheet(sheet_data)
        
        # Criterion 1: Total Revenue calculation
        revenue_found = False
        for num in all_numbers:
            if abs(num['value'] - EXPECTED_TOTAL_REVENUE) < 1:
                revenue_found = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Revenue calculated: ${num['value']:.0f}")
                break
        
        if not revenue_found:
            feedback_parts.append(f"❌ Total Revenue not found (expected ${EXPECTED_TOTAL_REVENUE})")

        # Criterion 2: Total Expenses calculation
        expenses_found = False
        for num in all_numbers:
            if abs(num['value'] - EXPECTED_TOTAL_EXPENSES) < 10:  # Allow some tolerance for monthly calc
                expenses_found = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Total Expenses calculated: ${num['value']:.0f}")
                break
        
        if not expenses_found:
            feedback_parts.append(f"❌ Total Expenses not found (expected ~${EXPECTED_TOTAL_EXPENSES})")

        # Criterion 3: Net Profit calculation
        profit_found = False
        profit_value = None
        for num in all_numbers:
            if abs(num['value'] - EXPECTED_NET_PROFIT) < 10:
                profit_found = True
                profit_value = num['value']
                criteria_passed += 1
                feedback_parts.append(f"✅ Net Profit calculated: ${num['value']:.2f}")
                break
        
        if not profit_found:
            feedback_parts.append(f"❌ Net Profit not found (expected ~${EXPECTED_NET_PROFIT})")

        # Criterion 4: Gig attendance counts (should find counts around 5-8 for members)
        member_counts = []
        for num in all_numbers:
            if 4 <= num['value'] <= 8 and num['value'] == int(num['value']):
                member_counts.append(int(num['value']))
        
        # Check if we have at least 4 member counts
        if len(member_counts) >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Member gig counts found: {member_counts[:4]}")
        else:
            feedback_parts.append(f"❌ Member gig counts not found (found {len(member_counts)} counts)")

        # Criterion 5: Total shares calculation
        shares_found = False
        for num in all_numbers:
            if abs(num['value'] - EXPECTED_TOTAL_SHARES) < 1:
                shares_found = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Total shares calculated: {int(num['value'])}")
                break
        
        if not shares_found:
            feedback_parts.append(f"❌ Total shares not found (expected {EXPECTED_TOTAL_SHARES})")

        # Criterion 6: Individual member payments
        # Look for values that could be individual payments (between 200-400 range)
        # and check if they sum close to net profit
        individual_payments = []
        for num in all_numbers:
            if 200 <= num['value'] <= 400:
                individual_payments.append(num['value'])
        
        # Check if we have 4 payments that sum close to profit
        payments_valid = False
        if len(individual_payments) >= 4:
            # Try different combinations of 4 payments
            from itertools import combinations
            for combo in combinations(individual_payments, 4):
                payment_sum = sum(combo)
                if profit_value and abs(payment_sum - profit_value) < 5:
                    payments_valid = True
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Individual payments calculated and sum correctly: ${payment_sum:.2f}")
                    break
                elif not profit_value and abs(payment_sum - EXPECTED_NET_PROFIT) < 10:
                    payments_valid = True
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Individual payments calculated: ${payment_sum:.2f}")
                    break
        
        if not payments_valid:
            feedback_parts.append(f"❌ Individual member payments not correctly calculated")

        # Check for formulas (bonus check, not counted in criteria)
        formula_count = 0
        for row in sheet_data:
            for cell in row:
                if isinstance(cell, dict) and cell.get('formula'):
                    formula_count += 1
        
        if formula_count >= 8:
            feedback_parts.append(f"💡 Good use of formulas ({formula_count} found)")
        else:
            feedback_parts.append(f"⚠️ Few formulas detected ({formula_count} found) - consider using more formulas")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75  # Need 4.5/6 criteria (75%)
        
        if passed:
            feedback_parts.append("🎸 Band finances successfully calculated!")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "revenue_calculated": revenue_found,
                "expenses_calculated": expenses_found,
                "profit_calculated": profit_found,
                "gig_counts_found": len(member_counts) >= 4,
                "shares_calculated": shares_found,
                "payments_distributed": payments_valid
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
